//
//  DYPlusAudioReport.mm
//  DYYY
//
//  事件与源状态的只读导出层：JSON 报表、事件行、调用者镜像、指针 → 源映射。
//  全部在主线程/非实时线程调用；实时侧只往 DYYYAudioTap.mm 里的环形结构写入。
//

#import "Audio/Realtime/DYPlusUtilsAudio.h"
#import "Audio/Realtime/DYPlusAudioTapPrivate.h"
#import "Core/Runtime/DYPlusFishhook.h"

#import <dlfcn.h>

#include <algorithm>
#include <atomic>
#include <cmath>

static const char *DYPlusEventName(uint32_t kind) {
    switch (kind) {
        case DYPlusEventComponentNew: return "AudioComponentInstanceNew";
        case DYPlusEventComponentDispose: return "AudioComponentInstanceDispose";
        case DYPlusEventUnitInitialize: return "AudioUnitInitialize";
        case DYPlusEventOutputStart: return "AudioOutputUnitStart";
        case DYPlusEventOutputStop: return "AudioOutputUnitStop";
        case DYPlusEventRenderNotifyInstall: return "AudioUnitAddRenderNotify";
        case DYPlusEventQueueNew: return "AudioQueueNewOutput";
        case DYPlusEventQueueStart: return "AudioQueueStart";
        case DYPlusEventQueueStop: return "AudioQueueStop";
        case DYPlusEventQueueDispose: return "AudioQueueDispose";
        case DYPlusEventQueueEnqueue: return "AudioQueueEnqueueBuffer";
        case DYPlusEventMediaTapCreate: return "MTAudioProcessingTapCreate";
    }
    return "Unknown";
}

static NSString *DYPlusPointerString(uintptr_t pointer) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)pointer];
}

static NSString *DYPlusFourCC(OSType value) {
    char chars[5] = {
        (char)((value >> 24) & 0xff), (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff), (char)(value & 0xff), 0
    };
    for (int i = 0; i < 4; i++) {
        if (chars[i] < 32 || chars[i] > 126) return [NSString stringWithFormat:@"0x%08x", value];
    }
    return [NSString stringWithUTF8String:chars] ?: @"";
}

static NSString *DYPlusImageForAddress(uintptr_t address) {
    if (!address) return @"";
    Dl_info info = {};
    if (dladdr((const void *)address, &info) == 0 || !info.dli_fname) return @"";
    NSString *path = [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    return path.lastPathComponent ?: @"";
}

static NSString *DYPlusSymbolForAddress(uintptr_t address) {
    if (!address) return @"";
    Dl_info info = {};
    if (dladdr((const void *)address, &info) == 0 || !info.dli_sname) return @"";
    return [NSString stringWithUTF8String:info.dli_sname] ?: @"";
}

static NSString *DYPlusSourceKindName(uint32_t kind) {
    switch (kind) {
        case DYPlusAudioTapSourceKindAudioUnit: return @"AudioUnit";
        case DYPlusAudioTapSourceKindAudioQueue: return @"AudioQueue";
        case DYPlusAudioTapSourceKindMediaTap: return @"MediaProcessingTap";
    }
    return @"Unknown";
}

static NSDictionary *DYPlusASBDJSON(const AudioStreamBasicDescription &format) {
    return @{
        @"sampleRate": @(format.mSampleRate),
        @"formatID": DYPlusFourCC(format.mFormatID),
        @"formatFlags": @(format.mFormatFlags),
        @"bytesPerPacket": @(format.mBytesPerPacket),
        @"framesPerPacket": @(format.mFramesPerPacket),
        @"bytesPerFrame": @(format.mBytesPerFrame),
        @"channelsPerFrame": @(format.mChannelsPerFrame),
        @"bitsPerChannel": @(format.mBitsPerChannel),
        @"nonInterleaved": @((format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0),
        @"float": @((format.mFormatFlags & kAudioFormatFlagIsFloat) != 0),
        @"signedInteger": @((format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0),
    };
}

// ioData 的实测排布，以及它与缓存 ASBD 的说法是否一致。
//
// 两者本来就允许不一致：ASBD 来自 kAudioUnitScope_Input，描述的是抖音推进去的格式；
// ioData 是 unit 填完之后交给硬件的那份。0.5.2-beta2 在设备上就是「ASBD 说交错、
// ioData 是 2 buffer × 1 声道」，按 ASBD 读会读错——下混因此改为只信这里的数字。
static NSDictionary *DYPlusBufferLayoutJSON(DYPlusSource *source) {
    uint32_t buffers = source->layoutNumberBuffers.load(std::memory_order_relaxed);
    if (buffers == 0) return @{};   // 窗口内没有回调，没量到

    uint32_t channels = source->layoutChannelsPerBuffer.load(std::memory_order_relaxed);
    uint32_t byteSize = source->layoutDataByteSize.load(std::memory_order_relaxed);
    uint32_t renderFrames = source->layoutRenderFrames.load(std::memory_order_relaxed);

    AudioStreamBasicDescription format = {};
    BOOL hasFormat = DYPlusReadSourceFormat(source, &format);
    uint32_t bytesPerSample = hasFormat ? format.mBitsPerChannel / 8 : 0;
    uint32_t stride = channels * bytesPerSample;
    uint32_t framesPerBuffer = stride ? byteSize / stride : 0;

    // ASBD 声称非交错就该是「每 buffer 一个声道」，声称交错就该是「单 buffer 承载全部声道」。
    BOOL declaredNonInterleaved = hasFormat &&
        (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    BOOL actualNonInterleaved = buffers > 1 || (channels == 1 && format.mChannelsPerFrame > 1);

    return @{
        @"numberBuffers": @(buffers),
        @"channelsPerBuffer": @(channels),
        @"dataByteSizePerBuffer": @(byteSize),
        @"framesPerBuffer": @(framesPerBuffer),
        @"renderFrames": @(renderFrames),
        @"coversRenderFrames": @(framesPerBuffer >= renderFrames),
        @"declaredNonInterleaved": @(declaredNonInterleaved),
        @"actualNonInterleaved": @(actualNonInterleaved),
        @"matchesDeclaredFormat": @(declaredNonInterleaved == actualNonInterleaved),
    };
}

NSArray<NSDictionary *> *DYPlusAudioTapBackendsJSON(void) {
    uint64_t captureStart = DYPlusCaptureStartTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < count; i++) {
        DYPlusSource *source = &DYPlusSources[i];
        AudioStreamBasicDescription format = {};
        BOOL hasFormat = DYPlusReadSourceFormat(source, &format);

        NSMutableArray *history = [NSMutableArray array];
        uint32_t records = std::min<uint32_t>(source->formatRecordCount.load(std::memory_order_acquire),
                                              kDYPlusMaxFormatRecords);
        for (uint32_t r = 0; r < records; r++) {
            DYPlusFormatRecord &record = source->formatRecords[r];
            uint32_t before = record.version.load(std::memory_order_acquire);
            if (before == 0 || (before & 1)) continue;
            uint32_t scope = record.scope;
            uint64_t ticks = record.ticks;
            AudioStreamBasicDescription recorded = record.format;
            if (record.version.load(std::memory_order_acquire) != before) continue;
            [history addObject:@{
                @"scope": @(scope),
                @"ticks": @(ticks),
                @"second": @(DYPlusRelativeSeconds(ticks, captureStart)),
                @"asbd": DYPlusASBDJSON(recorded),
            }];
        }

        uint64_t intervalCount = source->callbackIntervalCount.load(std::memory_order_relaxed);
        uint64_t intervalTicks = source->callbackIntervalTicks.load(std::memory_order_relaxed);
        uint64_t probeBlocks = source->probeBlocks.load(std::memory_order_relaxed);
        uint64_t probeTicks = source->probeTicks.load(std::memory_order_relaxed);
        [result addObject:@{
            @"sourceID": [NSString stringWithFormat:@"source-%02u", source->sourceID],
            @"kind": DYPlusSourceKindName(source->kind),
            @"handle": DYPlusPointerString(source->handle.load(std::memory_order_relaxed)),
            @"active": @(source->active.load(std::memory_order_relaxed) != 0),
            @"disposed": @(source->disposed.load(std::memory_order_relaxed) != 0),
            @"renderNotifyInstalled": @(source->notifyInstalled.load(std::memory_order_relaxed) != 0),
            @"renderNotifyStatus": @(source->notifyStatus.load(std::memory_order_relaxed)),
            @"componentType": DYPlusFourCC(source->componentType),
            @"componentSubType": DYPlusFourCC(source->componentSubType),
            @"componentManufacturer": DYPlusFourCC(source->componentManufacturer),
            @"format": hasFormat ? DYPlusASBDJSON(format) : @{},
            @"formatHistory": history,
            @"bufferLayout": DYPlusBufferLayoutJSON(source),
            @"hits": @(source->hits.load(std::memory_order_relaxed)),
            @"frames": @(source->frames.load(std::memory_order_relaxed)),
            @"lastStatus": @(source->lastStatus.load(std::memory_order_relaxed)),
            @"lastActivitySecond": @(DYPlusRelativeSeconds(source->lastTicks.load(std::memory_order_relaxed), captureStart)),
            @"firstCaptureCallbackSecond": @(DYPlusRelativeSeconds(source->firstCallbackTicks.load(std::memory_order_relaxed), captureStart)),
            @"captureSlot": @(source->captureSlot.load(std::memory_order_relaxed)),
            @"callbackTiming": @{
                @"intervalCount": @(intervalCount),
                @"meanMilliseconds": @(intervalCount ? DYPlusTicksToSeconds(intervalTicks / intervalCount) * 1000.0 : 0),
                @"minMilliseconds": @(DYPlusTicksToSeconds(source->minCallbackIntervalTicks.load(std::memory_order_relaxed)) * 1000.0),
                @"maxMilliseconds": @(DYPlusTicksToSeconds(source->maxCallbackIntervalTicks.load(std::memory_order_relaxed)) * 1000.0),
                @"estimatedDroppedFrames": @(source->estimatedDroppedFrames.load(std::memory_order_relaxed)),
            },
            @"contentionDrops": @(source->contentionDrops.load(std::memory_order_relaxed)),
            @"unsupportedBuffers": @(source->unsupportedBuffers.load(std::memory_order_relaxed)),
            @"unreadableFrames": @(source->unreadableFrames.load(std::memory_order_relaxed)),
            @"captureSlotMisses": @(source->captureSlotMisses.load(std::memory_order_relaxed)),
            @"formatMismatchBuffers": @(source->formatMismatchBuffers.load(std::memory_order_relaxed)),
            @"pcmCapacityDroppedFrames": @(source->pcmCapacityDroppedFrames.load(std::memory_order_relaxed)),
            @"configurationOverflow": @(source->configurationOverflow.load(std::memory_order_relaxed)),
            @"probeBlocks": @(probeBlocks),
            @"probeAverageMicroseconds": @(probeBlocks ? DYPlusTicksToSeconds(probeTicks / probeBlocks) * 1000000.0 : 0),
            @"probeMaxMicroseconds": @(DYPlusTicksToSeconds(source->maxProbeTicks.load(std::memory_order_relaxed)) * 1000000.0),
        }];
    }
    return result;
}

NSArray<NSDictionary *> *DYPlusAudioTapSymbolCoverageJSON(void) {
    uint64_t captureStart = DYPlusCaptureStartTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:DYPlusSymbolCount];
    for (uint32_t i = 0; i < DYPlusSymbolCount; i++) {
        DYPlusSymbolCoverage &coverage = DYPlusCoverage[i];
        struct dyplus_rebinding_status rebinding = {};
        BOOL hasStatus = dyplus_rebinding_status_for_name(DYPlusSymbolNames[i], &rebinding) == 0;
        uintptr_t firstCaller = coverage.firstCaller.load(std::memory_order_relaxed);
        uintptr_t lastCaller = coverage.lastCaller.load(std::memory_order_relaxed);
        [result addObject:@{
            @"symbol": [NSString stringWithUTF8String:DYPlusSymbolNames[i]] ?: @"",
            @"originalAvailable": @(coverage.original != nullptr),
            @"rebindResult": @(coverage.rebindResult),
            @"symbolPointerMatches": @(hasStatus ? rebinding.symbol_matches : 0),
            @"successfulRebindings": @(hasStatus ? rebinding.successful_writes : 0),
            @"protectionFailures": @(hasStatus ? rebinding.protection_failures : 0),
            @"rebound": @(hasStatus && rebinding.successful_writes > 0),
            @"hitCount": @(coverage.hits.load(std::memory_order_relaxed)),
            @"firstSecond": @(DYPlusRelativeSeconds(coverage.firstTicks.load(std::memory_order_relaxed), captureStart)),
            @"lastSecond": @(DYPlusRelativeSeconds(coverage.lastTicks.load(std::memory_order_relaxed), captureStart)),
            @"firstCallerImage": DYPlusImageForAddress(firstCaller),
            @"lastCallerImage": DYPlusImageForAddress(lastCaller),
            @"firstCallerSymbol": DYPlusSymbolForAddress(firstCaller),
            @"lastCallerSymbol": DYPlusSymbolForAddress(lastCaller),
            @"lastStatus": @(coverage.lastStatus.load(std::memory_order_relaxed)),
        }];
    }
    return result;
}

NSArray<NSDictionary *> *DYPlusAudioTapEventRows(void) {
    uint64_t captureStart = DYPlusCaptureStartTicks.load(std::memory_order_relaxed);
    uint64_t captureStop = DYPlusCaptureStopTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    uint32_t count = std::min<uint32_t>(DYPlusEventCount.load(std::memory_order_acquire), kDYPlusMaxEvents);
    for (uint32_t i = 0; i < count; i++) {
        DYPlusEvent *event = &DYPlusEvents[i];
        if (!event->ready.load(std::memory_order_acquire)) continue;
        [rows addObject:@{
            @"ticks": @(event->ticks),
            @"secondsSinceCaptureStart": @(DYPlusRelativeSeconds(event->ticks, captureStart)),
            @"withinCapture": @(captureStart > 0 && event->ticks >= captureStart &&
                                (captureStop == 0 || event->ticks <= captureStop)),
            @"event": [NSString stringWithUTF8String:DYPlusEventName(event->kind)] ?: @"",
            @"sourceID": event->sourceID ? [NSString stringWithFormat:@"source-%02u", event->sourceID] : @"",
            @"status": @(event->status),
            @"callerImage": DYPlusImageForAddress(event->caller),
            @"callerSymbol": DYPlusSymbolForAddress(event->caller),
            @"value1": @(event->value1),
            @"value2": @(event->value2),
        }];
    }
    return rows;
}

NSDictionary *DYPlusAudioTapCountersJSON(void) {
    uint64_t contentionDrops = 0, estimatedDroppedFrames = 0, capacityDroppedFrames = 0;
    uint64_t captureSlotMisses = 0, unsupportedBuffers = 0, unreadableFrames = 0;
    uint64_t configurationOverflow = 0, formatMismatchBuffers = 0;
    uint32_t callbackSources = 0, notifySources = 0;
    double maxProbeMicroseconds = 0;
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < count; i++) {
        DYPlusSource &source = DYPlusSources[i];
        maxProbeMicroseconds = std::max(maxProbeMicroseconds,
            DYPlusTicksToSeconds(source.maxProbeTicks.load(std::memory_order_relaxed)) * 1000000.0);
        contentionDrops += source.contentionDrops.load(std::memory_order_relaxed);
        estimatedDroppedFrames += source.estimatedDroppedFrames.load(std::memory_order_relaxed);
        capacityDroppedFrames += source.pcmCapacityDroppedFrames.load(std::memory_order_relaxed);
        captureSlotMisses += source.captureSlotMisses.load(std::memory_order_relaxed);
        unsupportedBuffers += source.unsupportedBuffers.load(std::memory_order_relaxed);
        unreadableFrames += source.unreadableFrames.load(std::memory_order_relaxed);
        configurationOverflow += source.configurationOverflow.load(std::memory_order_relaxed);
        formatMismatchBuffers += source.formatMismatchBuffers.load(std::memory_order_relaxed);
        if (source.firstCallbackTicks.load(std::memory_order_relaxed) != 0) callbackSources++;
        if (source.notifyInstalled.load(std::memory_order_relaxed) != 0) notifySources++;
    }
    return @{
        @"registeredSources": @(count),
        @"sourceOverflow": @(DYPlusSourceOverflow.load(std::memory_order_relaxed)),
        @"renderNotifySources": @(notifySources),
        @"callbackSourcesDuringCapture": @(callbackSources),
        @"eventCount": @(std::min<uint32_t>(DYPlusEventCount.load(std::memory_order_relaxed), kDYPlusMaxEvents)),
        @"eventOverflow": @(DYPlusEventOverflow.load(std::memory_order_relaxed)),
        @"activeWritersAfterStop": @(DYPlusActiveWriters.load(std::memory_order_relaxed)),
        @"pcmAllocationFailures": @(DYPlusPCMAllocationFailures.load(std::memory_order_relaxed)),
        @"contentionDrops": @(contentionDrops),
        @"estimatedDroppedFrames": @(estimatedDroppedFrames),
        @"pcmCapacityDroppedFrames": @(capacityDroppedFrames),
        @"captureSlotMisses": @(captureSlotMisses),
        @"unsupportedBuffers": @(unsupportedBuffers),
        @"unreadableFrames": @(unreadableFrames),
        @"configurationOverflow": @(configurationOverflow),
        @"formatMismatchBuffers": @(formatMismatchBuffers),
        @"probeMaxMicroseconds": @(maxProbeMicroseconds),
    };
}

NSArray<NSString *> *DYPlusAudioTapCallerImageNames(void) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (uint32_t i = 0; i < DYPlusSymbolCount; i++) {
        NSString *first = DYPlusImageForAddress(DYPlusCoverage[i].firstCaller.load(std::memory_order_relaxed));
        NSString *last = DYPlusImageForAddress(DYPlusCoverage[i].lastCaller.load(std::memory_order_relaxed));
        if (first.length) [names addObject:first];
        if (last.length) [names addObject:last];
    }
    return names.array;
}

NSString *DYPlusAudioTapSourceIDForPointer(uintptr_t pointer) {
    if (!pointer) return nil;
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    for (uint32_t offset = 0; offset < count; offset++) {
        uint32_t i = count - offset - 1;
        if (DYPlusSources[i].handle.load(std::memory_order_relaxed) != pointer) continue;
        if (DYPlusSources[i].disposed.load(std::memory_order_relaxed) != 0) continue;
        return [NSString stringWithFormat:@"source-%02u", DYPlusSources[i].sourceID];
    }
    return nil;
}
