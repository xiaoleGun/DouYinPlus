//
//  DYPlusAudioTap.mm
//  DYYY
//
//  实时层。这个文件里凡是会被音频渲染线程执行到的代码（DYYYRenderNotify、
//  DYYYCaptureBuffer 及其调用链）必须遵守：不分配内存、不加锁、不发 ObjC 消息、
//  不做任何可能阻塞的系统调用。缓冲区在采样开始前于主线程一次性分配。
//
//  取样口是公开只读的 AudioUnitAddRenderNotify：抖音全二进制 0 引用该 API，
//  我们独占；回调里只读 ioData 并原样返回 noErr，不影响它的输出。
//  只读导出（JSON 报表、事件行、调用者镜像）拆在 DYYYAudioReport.mm，
//  下混与频谱分析拆在 DYYYAudioAnalysis.mm；共享结构见 DYYYAudioTapPrivate.h。
//

#import "Audio/Realtime/DYPlusUtilsAudio.h"
#import "Audio/Realtime/DYPlusAudioTapPrivate.h"
#import "Core/Runtime/DYPlusFishhook.h"

#import <CoreMedia/CoreMedia.h>
#import <MediaToolbox/MediaToolbox.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#import <unistd.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>

constexpr uint32_t kDYPlusCaptureSlots = 8;
constexpr double kDYPlusMaxSampleRate = 192000.0;
constexpr double kDYPlusMaxPCMSeconds = 4.0;
constexpr uint64_t kDYPlusMaxPCMFrames = (uint64_t)(kDYPlusMaxSampleRate * kDYPlusMaxPCMSeconds);

// 实时电平旁路的容量。全部是 BSS 里的定长数组：实时侧永远不分配，也没有生命周期问题。
// 4 路 × 4096 帧 × 4 字节 = 64 KB；4096 帧在 48 kHz 下是 85 ms，够 1024 点分析窗用还有余量。
constexpr uint32_t kDYPlusLiveRings = 4;
constexpr uint32_t kDYPlusLiveRingFrames = 4096;
constexpr uint32_t kDYPlusLiveRingMask = kDYPlusLiveRingFrames - 1;
static_assert((kDYPlusLiveRingFrames & kDYPlusLiveRingMask) == 0, "环长必须是 2 的幂");
// 单次回调最多下混这么多帧进环。抖音实测 1024，留一倍余量；栈上 8 KB。
constexpr uint32_t kDYPlusLiveBlockFrames = 2048;

// MARK: - 事件

// MARK: - 符号

const char *const DYPlusSymbolNames[DYPlusSymbolCount] = {
    "AudioComponentInstanceNew",
    "AudioComponentInstanceDispose",
    "AudioUnitInitialize",
    "AudioOutputUnitStart",
    "AudioOutputUnitStop",
    "AudioQueueNewOutput",
    "AudioQueueNewOutputWithDispatchQueue",
    "AudioQueueStart",
    "AudioQueueStop",
    "AudioQueueDispose",
    "AudioQueueEnqueueBuffer",
    "MTAudioProcessingTapCreate",
};

// MARK: - 源

struct DYPlusPCMSlot {
    float *samples;
    std::atomic<int> sourceID;
    std::atomic<uint64_t> frameCount;
    AudioStreamBasicDescription format;
};

// MARK: - 全局状态

DYPlusSource DYPlusSources[kDYPlusMaxSources];
std::atomic<uint32_t> DYPlusSourceCount { 0 };
std::atomic<uint64_t> DYPlusSourceOverflow { 0 };
static os_unfair_lock DYPlusSourceLock = OS_UNFAIR_LOCK_INIT;

DYPlusEvent DYPlusEvents[kDYPlusMaxEvents];
std::atomic<uint32_t> DYPlusEventCount { 0 };
std::atomic<uint64_t> DYPlusEventOverflow { 0 };
DYPlusSymbolCoverage DYPlusCoverage[DYPlusSymbolCount];

static DYPlusPCMSlot DYPlusPCMSlots[kDYPlusCaptureSlots];
std::atomic<uint64_t> DYPlusPCMAllocationFailures { 0 };
std::atomic<int> DYPlusActiveWriters { 0 };

// 实时电平旁路：每路一个滚动环，单写者（该源自己的渲染线程）+ 单读者（主线程）。
static std::atomic<float> DYPlusLiveRing[kDYPlusLiveRings][kDYPlusLiveRingFrames];
static std::atomic<uint32_t> DYPlusLiveRingsClaimed { 0 };
static std::atomic<bool> DYPlusLiveEnabled { false };

static std::atomic<bool> DYPlusTapEnabled { false };
static std::atomic<bool> DYPlusTapInstalled { false };
static std::atomic<bool> DYPlusCaptureActive { false };
static os_unfair_lock DYPlusCaptureControlLock = OS_UNFAIR_LOCK_INIT;
std::atomic<uint64_t> DYPlusCaptureStartTicks { 0 };
std::atomic<uint64_t> DYPlusCaptureStopTicks { 0 };
static std::atomic<uint64_t> DYPlusPCMStartTicks { 0 };
static std::atomic<uint64_t> DYPlusPCMStopTicks { 0 };
static mach_timebase_info_data_t DYPlusTimebase;

static __attribute__((always_inline)) inline uintptr_t DYPlusStripCaller(void *address) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(address, ptrauth_key_return_address);
#else
    return (uintptr_t)address;
#endif
}

#define DYPLUS_CALLER() DYPlusStripCaller(__builtin_return_address(0))

static uint64_t DYPlusNanosecondsToTicks(uint64_t ns) {
    if (DYPlusTimebase.numer == 0) mach_timebase_info(&DYPlusTimebase);
    return (uint64_t)((long double)ns * DYPlusTimebase.denom / DYPlusTimebase.numer);
}

double DYPlusTicksToSeconds(uint64_t ticks) {
    if (DYPlusTimebase.numer == 0) mach_timebase_info(&DYPlusTimebase);
    return (double)((long double)ticks * DYPlusTimebase.numer / DYPlusTimebase.denom / 1000000000.0L);
}

double DYPlusRelativeSeconds(uint64_t ticks, uint64_t origin) {
    if (ticks == 0 || origin == 0) return -1.0;
    return ticks >= origin ? DYPlusTicksToSeconds(ticks - origin) : -DYPlusTicksToSeconds(origin - ticks);
}

// MARK: - 格式读写（seqlock）

static void DYPlusWriteSourceFormat(DYPlusSource *source, const AudioStreamBasicDescription *format) {
    if (!source || !format) return;
    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t version = source->formatVersion.load(std::memory_order_acquire);
        if (version & 1) continue;
        if (!source->formatVersion.compare_exchange_weak(version, version + 1,
                                                         std::memory_order_acq_rel,
                                                         std::memory_order_relaxed)) continue;
        source->format.store(*format);
        source->formatVersion.store(version + 2, std::memory_order_release);
        return;
    }
    source->configurationOverflow.fetch_add(1, std::memory_order_relaxed);
}

bool DYPlusReadSourceFormat(DYPlusSource *source, AudioStreamBasicDescription *format) {
    if (!source || !format) return false;
    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t before = source->formatVersion.load(std::memory_order_acquire);
        if (before == 0 || (before & 1)) continue;
        AudioStreamBasicDescription copy = source->format.load();
        std::atomic_thread_fence(std::memory_order_acquire);
        uint32_t after = source->formatVersion.load(std::memory_order_acquire);
        if (before == after && !(after & 1)) {
            *format = copy;
            return copy.mSampleRate > 0 && copy.mChannelsPerFrame > 0;
        }
    }
    return false;
}

static void DYPlusAppendFormatRecord(DYPlusSource *source, uint32_t scope,
                                 const AudioStreamBasicDescription *format) {
    if (!source || !format) return;
    uint32_t index = source->formatRecordCount.fetch_add(1, std::memory_order_relaxed);
    if (index >= kDYPlusMaxFormatRecords) {
        source->configurationOverflow.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    DYPlusFormatRecord &record = source->formatRecords[index];
    record.version.store(1, std::memory_order_release);
    record.scope = scope;
    record.ticks = mach_continuous_time();
    record.format = *format;
    record.version.store(2, std::memory_order_release);
}

// MARK: - 源登记

static DYPlusSource *DYPlusFindSource(uintptr_t handle, uint32_t kind) {
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    for (uint32_t offset = 0; offset < count; offset++) {
        uint32_t i = count - offset - 1;
        if (DYPlusSources[i].kind == kind &&
            DYPlusSources[i].disposed.load(std::memory_order_relaxed) == 0 &&
            DYPlusSources[i].handle.load(std::memory_order_acquire) == handle) return &DYPlusSources[i];
    }
    return nullptr;
}

static DYPlusSource *DYPlusCreateSource(uintptr_t handle, uint32_t kind,
                                const AudioStreamBasicDescription *format) {
    if (!handle) return nullptr;
    DYPlusSource *existing = DYPlusFindSource(handle, kind);
    if (existing) {
        if (format) {
            DYPlusWriteSourceFormat(existing, format);
            DYPlusAppendFormatRecord(existing, UINT32_MAX, format);
        }
        return existing;
    }

    os_unfair_lock_lock(&DYPlusSourceLock);
    existing = DYPlusFindSource(handle, kind);
    if (existing) {
        os_unfair_lock_unlock(&DYPlusSourceLock);
        if (format) {
            DYPlusWriteSourceFormat(existing, format);
            DYPlusAppendFormatRecord(existing, UINT32_MAX, format);
        }
        return existing;
    }

    uint32_t index = DYPlusSourceCount.load(std::memory_order_relaxed);
    if (index >= kDYPlusMaxSources) {
        DYPlusSourceOverflow.fetch_add(1, std::memory_order_relaxed);
        os_unfair_lock_unlock(&DYPlusSourceLock);
        return nullptr;
    }

    DYPlusSource *source = &DYPlusSources[index];
    source->sourceID = index + 1;
    source->kind = kind;
    source->componentType = 0;
    source->componentSubType = 0;
    source->componentManufacturer = 0;
    source->formatVersion.store(0, std::memory_order_relaxed);
    source->formatRecordCount.store(0, std::memory_order_relaxed);
    for (uint32_t i = 0; i < kDYPlusMaxFormatRecords; i++) {
        source->formatRecords[i].version.store(0, std::memory_order_relaxed);
    }
    source->active.store(0, std::memory_order_relaxed);
    source->disposed.store(0, std::memory_order_relaxed);
    source->notifyInstalled.store(0, std::memory_order_relaxed);
    source->notifyStatus.store(0, std::memory_order_relaxed);
    source->hits.store(0, std::memory_order_relaxed);
    source->frames.store(0, std::memory_order_relaxed);
    source->firstCallbackTicks.store(0, std::memory_order_relaxed);
    source->previousCallbackTicks.store(0, std::memory_order_relaxed);
    source->callbackIntervalCount.store(0, std::memory_order_relaxed);
    source->callbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->minCallbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->maxCallbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->estimatedDroppedFrames.store(0, std::memory_order_relaxed);
    source->lastTicks.store(0, std::memory_order_relaxed);
    source->lastStatus.store(0, std::memory_order_relaxed);
    source->contentionDrops.store(0, std::memory_order_relaxed);
    source->unsupportedBuffers.store(0, std::memory_order_relaxed);
    source->unreadableFrames.store(0, std::memory_order_relaxed);
    source->captureSlotMisses.store(0, std::memory_order_relaxed);
    source->formatMismatchBuffers.store(0, std::memory_order_relaxed);
    source->pcmCapacityDroppedFrames.store(0, std::memory_order_relaxed);
    source->configurationOverflow.store(0, std::memory_order_relaxed);
    source->probeTicks.store(0, std::memory_order_relaxed);
    source->probeBlocks.store(0, std::memory_order_relaxed);
    source->maxProbeTicks.store(0, std::memory_order_relaxed);
    source->captureSlot.store(-1, std::memory_order_relaxed);
    source->layoutNumberBuffers.store(0, std::memory_order_relaxed);
    source->layoutChannelsPerBuffer.store(0, std::memory_order_relaxed);
    source->layoutDataByteSize.store(0, std::memory_order_relaxed);
    source->layoutRenderFrames.store(0, std::memory_order_relaxed);
    source->liveRing.store(-1, std::memory_order_relaxed);
    source->liveWrite.store(0, std::memory_order_relaxed);
    source->liveTicks.store(0, std::memory_order_relaxed);
    source->liveSampleRate.store(0, std::memory_order_relaxed);
    source->liveEnergy.store(0, std::memory_order_relaxed);
    source->captureGuard.clear(std::memory_order_relaxed);
    if (format) {
        DYPlusWriteSourceFormat(source, format);
        DYPlusAppendFormatRecord(source, UINT32_MAX, format);
    }
    source->handle.store(handle, std::memory_order_release);
    DYPlusSourceCount.store(index + 1, std::memory_order_release);
    os_unfair_lock_unlock(&DYPlusSourceLock);
    return source;
}

// MARK: - 统计

static void DYPlusUpdateMax(std::atomic<uint64_t> &value, uint64_t candidate) {
    uint64_t current = value.load(std::memory_order_relaxed);
    while (candidate > current &&
           !value.compare_exchange_weak(current, candidate, std::memory_order_relaxed)) {}
}

static void DYPlusUpdateMinNonZero(std::atomic<uint64_t> &value, uint64_t candidate) {
    uint64_t current = value.load(std::memory_order_relaxed);
    while ((current == 0 || candidate < current) &&
           !value.compare_exchange_weak(current, candidate, std::memory_order_relaxed)) {}
}

static void DYPlusRecordProbeElapsed(DYPlusSource *source, uint64_t begin) {
    if (!source || begin == 0) return;
    uint64_t elapsed = mach_continuous_time() - begin;
    source->probeTicks.fetch_add(elapsed, std::memory_order_relaxed);
    source->probeBlocks.fetch_add(1, std::memory_order_relaxed);
    DYPlusUpdateMax(source->maxProbeTicks, elapsed);
}

static void DYPlusRecordCallbackActivity(DYPlusSource *source, uint32_t frames, OSStatus status) {
    if (!source || !DYPlusTapEnabled.load(std::memory_order_relaxed)) return;
    uint64_t now = mach_continuous_time();
    source->hits.fetch_add(1, std::memory_order_relaxed);
    source->frames.fetch_add(frames, std::memory_order_relaxed);
    source->lastTicks.store(now, std::memory_order_relaxed);
    source->lastStatus.store(status, std::memory_order_relaxed);
    if (!DYPlusCaptureActive.load(std::memory_order_relaxed)) return;

    uint64_t zero = 0;
    source->firstCallbackTicks.compare_exchange_strong(zero, now, std::memory_order_relaxed);
    uint64_t previous = source->previousCallbackTicks.exchange(now, std::memory_order_relaxed);
    if (previous == 0 || now <= previous) return;
    uint64_t interval = now - previous;
    source->callbackIntervalCount.fetch_add(1, std::memory_order_relaxed);
    source->callbackIntervalTicks.fetch_add(interval, std::memory_order_relaxed);
    DYPlusUpdateMinNonZero(source->minCallbackIntervalTicks, interval);
    DYPlusUpdateMax(source->maxCallbackIntervalTicks, interval);

    AudioStreamBasicDescription format = {};
    if (!DYPlusReadSourceFormat(source, &format) || format.mSampleRate <= 0 || frames == 0) return;
    uint64_t expected = DYPlusNanosecondsToTicks((uint64_t)llround((double)frames / format.mSampleRate * 1.0e9));
    if (expected == 0 || interval <= expected + expected / 2) return;
    uint64_t periods = interval / expected;
    if (periods > 1) {
        source->estimatedDroppedFrames.fetch_add((periods - 1) * frames, std::memory_order_relaxed);
    }
}

static void DYPlusRecordEvent(uint32_t kind, DYPlusSource *source, OSStatus status,
                          uintptr_t caller, uint64_t value1, uint64_t value2 = 0) {
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return;
    uint32_t index = DYPlusEventCount.fetch_add(1, std::memory_order_relaxed);
    if (index >= kDYPlusMaxEvents) {
        DYPlusEventOverflow.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    DYPlusEvent *event = &DYPlusEvents[index];
    event->kind = kind;
    event->sourceID = source ? source->sourceID : 0;
    event->status = status;
    event->ticks = mach_continuous_time();
    event->caller = caller;
    event->value1 = value1;
    event->value2 = value2;
    event->ready.store(1, std::memory_order_release);
}

static void DYPlusHitSymbol(DYPlusSymbolIndex index, OSStatus status, uintptr_t caller) {
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return;
    DYPlusSymbolCoverage &coverage = DYPlusCoverage[index];
    uint64_t now = mach_continuous_time();
    if (coverage.hits.fetch_add(1, std::memory_order_relaxed) == 0) {
        coverage.firstTicks.store(now, std::memory_order_relaxed);
        coverage.firstCaller.store(caller, std::memory_order_relaxed);
    }
    coverage.lastTicks.store(now, std::memory_order_relaxed);
    coverage.lastCaller.store(caller, std::memory_order_relaxed);
    coverage.lastStatus.store(status, std::memory_order_relaxed);
}

// MARK: - PCM 写入（实时路径）

static int DYPlusClaimCaptureSlot(DYPlusSource *source, const AudioStreamBasicDescription &format) {
    int existing = source->captureSlot.load(std::memory_order_acquire);
    if (existing >= 0) return existing;
    for (uint32_t i = 0; i < kDYPlusCaptureSlots; i++) {
        int expected = 0;
        int reservation = -(int)source->sourceID;
        if (DYPlusPCMSlots[i].sourceID.compare_exchange_strong(expected, reservation,
                                                           std::memory_order_acq_rel)) {
            DYPlusPCMSlots[i].format = format;
            DYPlusPCMSlots[i].sourceID.store((int)source->sourceID, std::memory_order_release);
            source->captureSlot.store((int)i, std::memory_order_release);
            return (int)i;
        }
        if (expected == (int)source->sourceID) {
            source->captureSlot.store((int)i, std::memory_order_release);
            return (int)i;
        }
    }
    return -1;
}

static bool DYPlusFormatCanConvert(const AudioStreamBasicDescription &format) {
    if (format.mFormatID != kAudioFormatLinearPCM || format.mChannelsPerFrame == 0 ||
        format.mSampleRate <= 0 || format.mSampleRate > kDYPlusMaxSampleRate ||
        (format.mFormatFlags & kAudioFormatFlagIsBigEndian) ||
        !(format.mFormatFlags & kAudioFormatFlagIsPacked)) return false;
    if ((format.mFormatFlags & kAudioFormatFlagIsFloat) &&
        (format.mBitsPerChannel == 32 || format.mBitsPerChannel == 64)) return true;
    if ((format.mFormatFlags & kAudioFormatFlagIsSignedInteger) &&
        (format.mBitsPerChannel == 16 || format.mBitsPerChannel == 32)) return true;
    return false;
}

static bool DYPlusFormatsMatch(const AudioStreamBasicDescription &l,
                           const AudioStreamBasicDescription &r) {
    return fabs(l.mSampleRate - r.mSampleRate) < 0.001 && l.mFormatID == r.mFormatID &&
           l.mFormatFlags == r.mFormatFlags && l.mBytesPerFrame == r.mBytesPerFrame &&
           l.mChannelsPerFrame == r.mChannelsPerFrame && l.mBitsPerChannel == r.mBitsPerChannel;
}

static uint32_t DYPlusCaptureBuffer(DYPlusSource *source, const AudioBufferList *bufferList,
                                uint32_t frameCount) {
    if (!source || !bufferList || frameCount == 0 ||
        !DYPlusCaptureActive.load(std::memory_order_relaxed)) return 0;

    uint64_t now = mach_continuous_time();
    if (now < DYPlusPCMStartTicks.load(std::memory_order_relaxed) ||
        now >= DYPlusPCMStopTicks.load(std::memory_order_relaxed)) return 0;
    uint64_t begin = now;

    AudioStreamBasicDescription format = {};
    if (!DYPlusReadSourceFormat(source, &format) || !DYPlusFormatCanConvert(format)) {
        source->unsupportedBuffers.fetch_add(1, std::memory_order_relaxed);
        DYPlusRecordProbeElapsed(source, begin);
        return 0;
    }

    int slotIndex = DYPlusClaimCaptureSlot(source, format);
    if (slotIndex < 0 || !DYPlusPCMSlots[slotIndex].samples) {
        source->captureSlotMisses.fetch_add(1, std::memory_order_relaxed);
        DYPlusRecordProbeElapsed(source, begin);
        return 0;
    }
    if (!DYPlusFormatsMatch(DYPlusPCMSlots[slotIndex].format, format)) {
        source->formatMismatchBuffers.fetch_add(1, std::memory_order_relaxed);
        DYPlusRecordProbeElapsed(source, begin);
        return 0;
    }

    if (source->captureGuard.test_and_set(std::memory_order_acquire)) {
        source->contentionDrops.fetch_add(1, std::memory_order_relaxed);
        DYPlusRecordProbeElapsed(source, begin);
        return 0;
    }
    DYPlusActiveWriters.fetch_add(1, std::memory_order_relaxed);

    DYPlusPCMSlot &slot = DYPlusPCMSlots[slotIndex];
    uint64_t written = slot.frameCount.load(std::memory_order_relaxed);
    uint64_t available = written < kDYPlusMaxPCMFrames ? kDYPlusMaxPCMFrames - written : 0;
    uint32_t capacity = (uint32_t)std::min<uint64_t>(available, UINT32_MAX);
    if (capacity < frameCount) {
        source->pcmCapacityDroppedFrames.fetch_add(frameCount - capacity, std::memory_order_relaxed);
    }
    uint64_t unreadable = 0;
    uint32_t count = DYPlusAudioSignalDownmix(bufferList, &format, frameCount,
                                          slot.samples + written, capacity, &unreadable);
    if (unreadable) source->unreadableFrames.fetch_add(unreadable, std::memory_order_relaxed);
    slot.frameCount.store(written + count, std::memory_order_release);

    DYPlusRecordProbeElapsed(source, begin);
    DYPlusActiveWriters.fetch_sub(1, std::memory_order_relaxed);
    source->captureGuard.clear(std::memory_order_release);
    return count;
}

// MARK: - 实时电平旁路

// 音频渲染线程执行。认领一个环槽位；抢不到（已满 4 路）就永久放弃，返回 -1。
static int DYPlusClaimLiveRing(DYPlusSource *source) {
    int ring = source->liveRing.load(std::memory_order_acquire);
    if (ring >= 0) return ring;
    if (ring < -1) return -1;                    // -2 表示试过且抢不到

    uint32_t claimed = DYPlusLiveRingsClaimed.load(std::memory_order_relaxed);
    while (claimed < kDYPlusLiveRings) {
        if (DYPlusLiveRingsClaimed.compare_exchange_weak(claimed, claimed + 1,
                                                     std::memory_order_acq_rel,
                                                     std::memory_order_relaxed)) {
            source->liveWrite.store(0, std::memory_order_relaxed);
            source->liveRing.store((int)claimed, std::memory_order_release);
            return (int)claimed;
        }
    }
    source->liveRing.store(-2, std::memory_order_release);
    return -1;
}

// 音频渲染线程执行。下混一块进栈上缓冲，再拷进滚动环，顺手更新能量与时刻。
// 与 DYYYCaptureBuffer 各走各的：采集窗口开没开都不影响这里。
static void DYPlusPublishLive(DYPlusSource *source, const AudioBufferList *bufferList, uint32_t frameCount) {
    if (!source || !bufferList || frameCount == 0) return;
    if (!DYPlusLiveEnabled.load(std::memory_order_relaxed)) return;

    AudioStreamBasicDescription format = {};
    if (!DYPlusReadSourceFormat(source, &format) || !DYPlusFormatCanConvert(format)) return;

    int ring = DYPlusClaimLiveRing(source);
    if (ring < 0) return;

    float block[kDYPlusLiveBlockFrames];
    uint32_t want = std::min(frameCount, kDYPlusLiveBlockFrames);
    uint64_t unreadable = 0;
    uint32_t count = DYPlusAudioSignalDownmix(bufferList, &format, want, block,
                                          kDYPlusLiveBlockFrames, &unreadable);
    if (count == 0) return;

    uint64_t write = source->liveWrite.load(std::memory_order_relaxed);
    uint32_t head = (uint32_t)(write & kDYPlusLiveRingMask);
    uint32_t first = std::min(count, kDYPlusLiveRingFrames - head);
    for (uint32_t index = 0; index < first; index++) DYPlusLiveRing[ring][head + index].store(block[index], std::memory_order_relaxed);
    for (uint32_t index = first; index < count; index++) DYPlusLiveRing[ring][index - first].store(block[index], std::memory_order_relaxed);
    source->liveWrite.store(write + count, std::memory_order_release);

    double sum = 0.0;
    for (uint32_t i = 0; i < count; i++) sum += (double)block[i] * block[i];
    float rms = (float)sqrt(sum / count);
    // 选源用的能量：上升立刻跟上，下降留一点惯性，避免在块间抖动时来回换源。
    float previous = source->liveEnergy.load(std::memory_order_relaxed);
    source->liveEnergy.store(rms > previous ? rms : previous + (rms - previous) * 0.25f,
                             std::memory_order_relaxed);
    source->liveSampleRate.store(format.mSampleRate, std::memory_order_relaxed);
    source->liveTicks.store(mach_continuous_time(), std::memory_order_release);
}

// MARK: - 只读旁路

// 音频渲染线程执行。四条 relaxed store，记最近一次 ioData 的真实排布。
static void DYPlusRecordBufferLayout(DYPlusSource *source, const AudioBufferList *data, uint32_t frames) {
    if (!source || !data || data->mNumberBuffers == 0) return;
    const AudioBuffer &first = data->mBuffers[0];
    source->layoutNumberBuffers.store(data->mNumberBuffers, std::memory_order_relaxed);
    source->layoutChannelsPerBuffer.store(first.mNumberChannels, std::memory_order_relaxed);
    source->layoutDataByteSize.store(first.mDataByteSize, std::memory_order_relaxed);
    source->layoutRenderFrames.store(frames, std::memory_order_relaxed);
}

// 音频渲染线程执行。只在 PostRender 且无错误时读一次 ioData，然后原样返回。
static OSStatus DYPlusRenderNotify(void *refCon,
                               AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *timestamp,
                               UInt32 bus,
                               UInt32 frames,
                               AudioBufferList *data) {
    (void)timestamp;
    if (!flags || !(*flags & kAudioUnitRenderAction_PostRender)) return noErr;
    if (*flags & kAudioUnitRenderAction_PostRenderError) return noErr;
    if (bus != 0) return noErr;   // 输出单元的输出 element 固定为 0
    DYPlusSource *source = (DYPlusSource *)refCon;
    if (!source || !DYPlusTapEnabled.load(std::memory_order_relaxed)) return noErr;
    DYPlusRecordCallbackActivity(source, frames, noErr);
    if (data) {
        DYPlusRecordBufferLayout(source, data, frames);
        DYPlusPublishLive(source, data, frames);
        DYPlusCaptureBuffer(source, data, frames);
    }
    return noErr;
}

// 输出单元送进 RemoteIO 的客户端格式在 Input scope element 0。必须在非实时线程读好。
static void DYPlusCacheOutputUnitFormat(AudioUnit unit, DYPlusSource *source) {
    if (!unit || !source) return;
    AudioStreamBasicDescription format = {};
    UInt32 size = sizeof(format);
    if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &format, &size) != noErr) return;
    if (format.mSampleRate <= 0 || format.mChannelsPerFrame == 0) return;
    AudioStreamBasicDescription current = {};
    if (DYPlusReadSourceFormat(source, &current) && DYPlusFormatsMatch(current, format)) return;
    DYPlusWriteSourceFormat(source, &format);
    DYPlusAppendFormatRecord(source, kAudioUnitScope_Input, &format);
}

static void DYPlusInstallRenderNotify(AudioUnit unit, DYPlusSource *source, uintptr_t caller) {
    if (!unit || !source) return;
    int expected = 0;
    if (!source->notifyInstalled.compare_exchange_strong(expected, 1, std::memory_order_acq_rel)) return;
    OSStatus status = AudioUnitAddRenderNotify(unit, DYPlusRenderNotify, source);
    source->notifyStatus.store(status, std::memory_order_relaxed);
    if (status != noErr) source->notifyInstalled.store(0, std::memory_order_release);
    DYPlusRecordEvent(DYPlusEventRenderNotifyInstall, source, status, caller, (uintptr_t)unit);
}

static void DYPlusRemoveRenderNotify(AudioUnit unit, DYPlusSource *source) {
    if (!unit || !source) return;
    if (source->notifyInstalled.exchange(0, std::memory_order_acq_rel) == 0) return;
    AudioUnitRemoveRenderNotify(unit, DYPlusRenderNotify, source);
}

// MARK: - 原始函数

static OSStatus (*DYPlusOrigComponentNew)(AudioComponent, AudioComponentInstance *);
static OSStatus (*DYPlusOrigComponentDispose)(AudioComponentInstance);
static OSStatus (*DYPlusOrigUnitInitialize)(AudioUnit);
static OSStatus (*DYPlusOrigOutputStart)(AudioUnit);
static OSStatus (*DYPlusOrigOutputStop)(AudioUnit);
static OSStatus (*DYPlusOrigQueueNewOutput)(const AudioStreamBasicDescription *, AudioQueueOutputCallback, void *, CFRunLoopRef, CFStringRef, UInt32, AudioQueueRef *);
static OSStatus (*DYPlusOrigQueueNewOutputDispatch)(AudioQueueRef *, const AudioStreamBasicDescription *, UInt32, dispatch_queue_t, AudioQueueOutputCallbackBlock);
static OSStatus (*DYPlusOrigQueueStart)(AudioQueueRef, const AudioTimeStamp *);
static OSStatus (*DYPlusOrigQueueStop)(AudioQueueRef, Boolean);
static OSStatus (*DYPlusOrigQueueDispose)(AudioQueueRef, Boolean);
static OSStatus (*DYPlusOrigQueueEnqueue)(AudioQueueRef, AudioQueueBufferRef, UInt32, const AudioStreamPacketDescription *);
static OSStatus (*DYPlusOrigTapCreate)(CFAllocatorRef, const MTAudioProcessingTapCallbacks *, MTAudioProcessingTapCreationFlags, MTAudioProcessingTapRef *);

// MARK: - 包装

static OSStatus DYPlusHookComponentNew(AudioComponent component, AudioComponentInstance *instanceOut) {
    uintptr_t caller = DYPLUS_CALLER();
    OSStatus status = DYPlusOrigComponentNew ? DYPlusOrigComponentNew(component, instanceOut) : kAudio_ParamError;
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    DYPlusHitSymbol(DYPlusSymbolComponentNew, status, caller);
    DYPlusSource *source = nullptr;
    if (status == noErr && instanceOut && *instanceOut) {
        source = DYPlusCreateSource((uintptr_t)*instanceOut, DYPlusAudioTapSourceKindAudioUnit, nullptr);
        AudioComponentDescription description = {};
        if (source && component && AudioComponentGetDescription(component, &description) == noErr) {
            source->componentType = description.componentType;
            source->componentSubType = description.componentSubType;
            source->componentManufacturer = description.componentManufacturer;
        }
    }
    DYPlusRecordEvent(DYPlusEventComponentNew, source, status, caller,
                  instanceOut ? (uintptr_t)*instanceOut : 0);
    return status;
}

static OSStatus DYPlusHookComponentDispose(AudioComponentInstance instance) {
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusSource *source = DYPlusFindSource((uintptr_t)instance, DYPlusAudioTapSourceKindAudioUnit);
    // 必须在实例失效之前摘掉 notify，否则回调指针悬空。
    if (source) DYPlusRemoveRenderNotify(instance, source);
    OSStatus status = DYPlusOrigComponentDispose ? DYPlusOrigComponentDispose(instance) : kAudio_ParamError;
    if (source && status == noErr) {
        source->active.store(0, std::memory_order_relaxed);
        source->disposed.store(1, std::memory_order_relaxed);
    }
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    DYPlusHitSymbol(DYPlusSymbolComponentDispose, status, caller);
    DYPlusRecordEvent(DYPlusEventComponentDispose, source, status, caller, (uintptr_t)instance);
    return status;
}

static OSStatus DYPlusHookUnitInitialize(AudioUnit unit) {
    OSStatus status = DYPlusOrigUnitInitialize ? DYPlusOrigUnitInitialize(unit) : kAudio_ParamError;
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolUnitInitialize, status, caller);
    DYPlusSource *source = DYPlusFindSource((uintptr_t)unit, DYPlusAudioTapSourceKindAudioUnit);
    if (source && status == noErr) DYPlusCacheOutputUnitFormat(unit, source);
    DYPlusRecordEvent(DYPlusEventUnitInitialize, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DYPlusHookOutputStart(AudioUnit unit) {
    OSStatus status = DYPlusOrigOutputStart ? DYPlusOrigOutputStart(unit) : kAudio_ParamError;
    BOOL enabled = DYPlusTapEnabled.load(std::memory_order_relaxed);
    DYPlusSource *source = enabled
        ? DYPlusCreateSource((uintptr_t)unit, DYPlusAudioTapSourceKindAudioUnit, nullptr)
        : DYPlusFindSource((uintptr_t)unit, DYPlusAudioTapSourceKindAudioUnit);
    if (source && status == noErr) source->active.store(1, std::memory_order_relaxed);
    if (!enabled) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolOutputStart, status, caller);
    // 只有被 AudioOutputUnitStart 启动过的实例才是输出单元，也只有它值得挂旁路。
    if (source && status == noErr) {
        DYPlusCacheOutputUnitFormat(unit, source);
        DYPlusInstallRenderNotify(unit, source, caller);
    }
    if (source) source->lastStatus.store(status, std::memory_order_relaxed);
    DYPlusRecordEvent(DYPlusEventOutputStart, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DYPlusHookOutputStop(AudioUnit unit) {
    OSStatus status = DYPlusOrigOutputStop ? DYPlusOrigOutputStop(unit) : kAudio_ParamError;
    DYPlusSource *source = DYPlusFindSource((uintptr_t)unit, DYPlusAudioTapSourceKindAudioUnit);
    if (source && status == noErr) source->active.store(0, std::memory_order_relaxed);
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolOutputStop, status, caller);
    // notify 留着：同一只 unit 常被反复启停，重复装卸没有收益。
    DYPlusRecordEvent(DYPlusEventOutputStop, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DYPlusHookQueueNewOutput(const AudioStreamBasicDescription *format,
                                     AudioQueueOutputCallback callback,
                                     void *userData,
                                     CFRunLoopRef runLoop,
                                     CFStringRef mode,
                                     UInt32 flags,
                                     AudioQueueRef *queueOut) {
    uintptr_t caller = DYPLUS_CALLER();
    OSStatus status = DYPlusOrigQueueNewOutput
        ? DYPlusOrigQueueNewOutput(format, callback, userData, runLoop, mode, flags, queueOut)
        : kAudio_ParamError;
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    DYPlusHitSymbol(DYPlusSymbolQueueNewOutput, status, caller);
    DYPlusSource *source = status == noErr && queueOut && *queueOut
        ? DYPlusCreateSource((uintptr_t)*queueOut, DYPlusAudioTapSourceKindAudioQueue, format) : nullptr;
    DYPlusRecordEvent(DYPlusEventQueueNew, source, status, caller, queueOut ? (uintptr_t)*queueOut : 0, flags);
    return status;
}

static OSStatus DYPlusHookQueueNewOutputDispatch(AudioQueueRef *queueOut,
                                             const AudioStreamBasicDescription *format,
                                             UInt32 flags,
                                             dispatch_queue_t queue,
                                             AudioQueueOutputCallbackBlock block) {
    uintptr_t caller = DYPLUS_CALLER();
    OSStatus status = DYPlusOrigQueueNewOutputDispatch
        ? DYPlusOrigQueueNewOutputDispatch(queueOut, format, flags, queue, block) : kAudio_ParamError;
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    DYPlusHitSymbol(DYPlusSymbolQueueNewOutputDispatch, status, caller);
    DYPlusSource *source = status == noErr && queueOut && *queueOut
        ? DYPlusCreateSource((uintptr_t)*queueOut, DYPlusAudioTapSourceKindAudioQueue, format) : nullptr;
    DYPlusRecordEvent(DYPlusEventQueueNew, source, status, caller, queueOut ? (uintptr_t)*queueOut : 0, flags);
    return status;
}

static OSStatus DYPlusHookQueueStart(AudioQueueRef queue, const AudioTimeStamp *time) {
    OSStatus status = DYPlusOrigQueueStart ? DYPlusOrigQueueStart(queue, time) : kAudio_ParamError;
    DYPlusSource *source = DYPlusFindSource((uintptr_t)queue, DYPlusAudioTapSourceKindAudioQueue);
    if (source && status == noErr) source->active.store(1, std::memory_order_relaxed);
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolQueueStart, status, caller);
    DYPlusRecordEvent(DYPlusEventQueueStart, source, status, caller, (uintptr_t)queue);
    return status;
}

static OSStatus DYPlusHookQueueStop(AudioQueueRef queue, Boolean immediate) {
    OSStatus status = DYPlusOrigQueueStop ? DYPlusOrigQueueStop(queue, immediate) : kAudio_ParamError;
    DYPlusSource *source = DYPlusFindSource((uintptr_t)queue, DYPlusAudioTapSourceKindAudioQueue);
    if (source && status == noErr) source->active.store(0, std::memory_order_relaxed);
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolQueueStop, status, caller);
    DYPlusRecordEvent(DYPlusEventQueueStop, source, status, caller, (uintptr_t)queue, immediate);
    return status;
}

static OSStatus DYPlusHookQueueDispose(AudioQueueRef queue, Boolean immediate) {
    OSStatus status = DYPlusOrigQueueDispose ? DYPlusOrigQueueDispose(queue, immediate) : kAudio_ParamError;
    DYPlusSource *source = DYPlusFindSource((uintptr_t)queue, DYPlusAudioTapSourceKindAudioQueue);
    if (source && status == noErr) {
        source->active.store(0, std::memory_order_relaxed);
        source->disposed.store(1, std::memory_order_relaxed);
    }
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusHitSymbol(DYPlusSymbolQueueDispose, status, caller);
    DYPlusRecordEvent(DYPlusEventQueueDispose, source, status, caller, (uintptr_t)queue, immediate);
    return status;
}

// AudioQueue 走的是「入队即将播放的缓冲」，比 AudioUnit 旁路多一个缓冲的延迟，
// 但同样不改数据。这条是 AudioUnit 路径不成立时的兜底取样口。
static OSStatus DYPlusHookQueueEnqueue(AudioQueueRef queue,
                                   AudioQueueBufferRef buffer,
                                   UInt32 packetCount,
                                   const AudioStreamPacketDescription *packets) {
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) {
        return DYPlusOrigQueueEnqueue ? DYPlusOrigQueueEnqueue(queue, buffer, packetCount, packets)
                                  : kAudio_ParamError;
    }
    uintptr_t caller = DYPLUS_CALLER();
    DYPlusSource *source = DYPlusFindSource((uintptr_t)queue, DYPlusAudioTapSourceKindAudioQueue);
    uint32_t frames = 0;
    if (source && buffer && buffer->mAudioData && buffer->mAudioDataByteSize > 0) {
        AudioStreamBasicDescription format = {};
        if (DYPlusReadSourceFormat(source, &format) && format.mBytesPerFrame > 0) {
            frames = buffer->mAudioDataByteSize / format.mBytesPerFrame;
            struct {
                UInt32 count;
                AudioBuffer buffer;
            } list = { 1, { format.mChannelsPerFrame, buffer->mAudioDataByteSize, buffer->mAudioData } };
            DYPlusCaptureBuffer(source, (const AudioBufferList *)&list, frames);
        }
    }
    OSStatus status = DYPlusOrigQueueEnqueue
        ? DYPlusOrigQueueEnqueue(queue, buffer, packetCount, packets) : kAudio_ParamError;
    DYPlusHitSymbol(DYPlusSymbolQueueEnqueue, status, caller);
    if (source) DYPlusRecordCallbackActivity(source, frames, status);
    if (DYPlusCaptureActive.load(std::memory_order_relaxed)) {
        DYPlusRecordEvent(DYPlusEventQueueEnqueue, source, status, caller,
                      buffer ? buffer->mAudioDataByteSize : 0, packetCount);
    }
    return status;
}

// 只登记「有没有人用 AVPlayer 的音频 tap」，不接管它的 process 回调。
static OSStatus DYPlusHookTapCreate(CFAllocatorRef allocator,
                                const MTAudioProcessingTapCallbacks *callbacks,
                                MTAudioProcessingTapCreationFlags flags,
                                MTAudioProcessingTapRef *tapOut) {
    uintptr_t caller = DYPLUS_CALLER();
    OSStatus status = DYPlusOrigTapCreate ? DYPlusOrigTapCreate(allocator, callbacks, flags, tapOut)
                                      : kAudio_ParamError;
    if (!DYPlusTapEnabled.load(std::memory_order_relaxed)) return status;
    DYPlusHitSymbol(DYPlusSymbolTapCreate, status, caller);
    DYPlusSource *source = status == noErr && tapOut && *tapOut
        ? DYPlusCreateSource((uintptr_t)*tapOut, DYPlusAudioTapSourceKindMediaTap, nullptr) : nullptr;
    DYPlusRecordEvent(DYPlusEventMediaTapCreate, source, status, caller,
                  tapOut ? (uintptr_t)*tapOut : 0, flags);
    return status;
}

static void DYPlusInstallRebindings(void) {
    for (uint32_t i = 0; i < DYPlusSymbolCount; i++) {
        DYPlusCoverage[i].original = dlsym(RTLD_DEFAULT, DYPlusSymbolNames[i]);
        DYPlusCoverage[i].rebindResult = -1;
    }
#define DYPLUS_RESOLVE(VAR, INDEX) VAR = reinterpret_cast<decltype(VAR)>(DYPlusCoverage[INDEX].original)
    DYPLUS_RESOLVE(DYPlusOrigComponentNew, DYPlusSymbolComponentNew);
    DYPLUS_RESOLVE(DYPlusOrigComponentDispose, DYPlusSymbolComponentDispose);
    DYPLUS_RESOLVE(DYPlusOrigUnitInitialize, DYPlusSymbolUnitInitialize);
    DYPLUS_RESOLVE(DYPlusOrigOutputStart, DYPlusSymbolOutputStart);
    DYPLUS_RESOLVE(DYPlusOrigOutputStop, DYPlusSymbolOutputStop);
    DYPLUS_RESOLVE(DYPlusOrigQueueNewOutput, DYPlusSymbolQueueNewOutput);
    DYPLUS_RESOLVE(DYPlusOrigQueueNewOutputDispatch, DYPlusSymbolQueueNewOutputDispatch);
    DYPLUS_RESOLVE(DYPlusOrigQueueStart, DYPlusSymbolQueueStart);
    DYPLUS_RESOLVE(DYPlusOrigQueueStop, DYPlusSymbolQueueStop);
    DYPLUS_RESOLVE(DYPlusOrigQueueDispose, DYPlusSymbolQueueDispose);
    DYPLUS_RESOLVE(DYPlusOrigQueueEnqueue, DYPlusSymbolQueueEnqueue);
    DYPLUS_RESOLVE(DYPlusOrigTapCreate, DYPlusSymbolTapCreate);
#undef DYPLUS_RESOLVE

    struct dyplus_rebinding bindings[DYPlusSymbolCount] = {
        { DYPlusSymbolNames[DYPlusSymbolComponentNew], (void *)DYPlusHookComponentNew, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolComponentDispose], (void *)DYPlusHookComponentDispose, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolUnitInitialize], (void *)DYPlusHookUnitInitialize, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolOutputStart], (void *)DYPlusHookOutputStart, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolOutputStop], (void *)DYPlusHookOutputStop, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueNewOutput], (void *)DYPlusHookQueueNewOutput, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueNewOutputDispatch], (void *)DYPlusHookQueueNewOutputDispatch, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueStart], (void *)DYPlusHookQueueStart, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueStop], (void *)DYPlusHookQueueStop, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueDispose], (void *)DYPlusHookQueueDispose, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolQueueEnqueue], (void *)DYPlusHookQueueEnqueue, nullptr },
        { DYPlusSymbolNames[DYPlusSymbolTapCreate], (void *)DYPlusHookTapCreate, nullptr },
    };
    int result = dyplus_rebind_symbols(bindings, DYPlusSymbolCount);
    for (uint32_t i = 0; i < DYPlusSymbolCount; i++) DYPlusCoverage[i].rebindResult = result;
}

// MARK: - 对外接口

void DYPlusAudioTapInstall(void) {
    bool expected = false;
    if (!DYPlusTapInstalled.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) return;
    mach_timebase_info(&DYPlusTimebase);
    DYPlusInstallRebindings();
}

void DYPlusAudioTapSetEnabled(BOOL enabled) {
    BOOL previous = DYPlusTapEnabled.exchange(enabled, std::memory_order_acq_rel);
    if (previous == enabled) return;
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    if (!enabled) {
        DYPlusCaptureActive.store(false, std::memory_order_release);
        DYPlusLiveEnabled.store(false, std::memory_order_release);
        for (uint32_t i = 0; i < count; i++) {
            DYPlusSource *source = &DYPlusSources[i];
            if (source->kind != DYPlusAudioTapSourceKindAudioUnit) continue;
            AudioUnit unit = (AudioUnit)source->handle.load(std::memory_order_acquire);
            DYPlusRemoveRenderNotify(unit, source);
        }
        return;
    }
    for (uint32_t i = 0; i < count; i++) {
        DYPlusSource *source = &DYPlusSources[i];
        if (source->kind != DYPlusAudioTapSourceKindAudioUnit ||
            source->disposed.load(std::memory_order_relaxed) ||
            !source->active.load(std::memory_order_relaxed)) continue;
        AudioUnit unit = (AudioUnit)source->handle.load(std::memory_order_acquire);
        DYPlusCacheOutputUnitFormat(unit, source);
        DYPlusInstallRenderNotify(unit, source, 0);
    }
}

// MARK: - 实时电平旁路（读侧，主线程）

void DYPlusAudioTapSetLiveMeteringEnabled(BOOL enabled) {
    DYPlusLiveEnabled.store(enabled, std::memory_order_release);
}

BOOL DYPlusAudioTapIsLiveMeteringEnabled(void) {
    return DYPlusLiveEnabled.load(std::memory_order_acquire);
}

// 挑当前最响、且还在活动的那一路。
//
// beta2 实测抖音同时跑两只 RemoteIO，其中一只全程恒零——取"第一路"会永远画不出东西，
// 必须按能量选。staleSeconds 之外的源不参选，否则一首歌停了还会锁在旧源上。
static DYPlusSource *DYPlusLoudestLiveSource(double staleSeconds, uint64_t now) {
    uint32_t count = DYPlusSourceCount.load(std::memory_order_acquire);
    DYPlusSource *best = nullptr;
    float bestEnergy = -1.0f;
    for (uint32_t i = 0; i < count; i++) {
        DYPlusSource *source = &DYPlusSources[i];
        if (source->liveRing.load(std::memory_order_acquire) < 0) continue;
        uint64_t ticks = source->liveTicks.load(std::memory_order_acquire);
        if (ticks == 0 || now < ticks) continue;
        if (DYPlusTicksToSeconds(now - ticks) > staleSeconds) continue;
        float energy = source->liveEnergy.load(std::memory_order_relaxed);
        if (energy > bestEnergy) { bestEnergy = energy; best = source; }
    }
    return best;
}

uint32_t DYPlusAudioTapCopyLatestSamples(float *out, uint32_t count, double *sampleRateOut) {
    if (!out || count == 0 || count > kDYPlusLiveRingFrames) return 0;
    if (!DYPlusLiveEnabled.load(std::memory_order_acquire)) return 0;

    DYPlusSource *source = DYPlusLoudestLiveSource(0.25, mach_continuous_time());
    if (!source) return 0;
    int ring = source->liveRing.load(std::memory_order_acquire);
    if (ring < 0 || ring >= (int)kDYPlusLiveRings) return 0;

    uint64_t before = source->liveWrite.load(std::memory_order_acquire);
    if (before < count) return 0;                 // 环还没填满一个分析窗

    uint32_t start = (uint32_t)((before - count) & kDYPlusLiveRingMask);
    uint32_t first = std::min(count, kDYPlusLiveRingFrames - start);
    for (uint32_t index = 0; index < first; index++) out[index] = DYPlusLiveRing[ring][start + index].load(std::memory_order_relaxed);
    for (uint32_t index = first; index < count; index++) out[index] = DYPlusLiveRing[ring][index - first].load(std::memory_order_relaxed);

    // 拷贝期间实时侧可能已经绕回来盖掉了我们正在读的那一段。复读游标判定：
    // 写入前进超过"环长 − 窗长"就说明被追上了，这一帧直接丢（60 Hz 下看不出来）。
    uint64_t after = source->liveWrite.load(std::memory_order_acquire);
    if (after - before > kDYPlusLiveRingFrames - count) return 0;

    if (sampleRateOut) {
        double rate = source->liveSampleRate.load(std::memory_order_relaxed);
        *sampleRateOut = rate > 0 ? rate : 48000.0;
    }
    return count;
}

BOOL DYPlusAudioTapHasRecentAudio(double withinSeconds) {
    if (!DYPlusLiveEnabled.load(std::memory_order_acquire)) return NO;
    return DYPlusLoudestLiveSource(withinSeconds, mach_continuous_time()) != nullptr;
}

BOOL DYPlusAudioTapIsInstalled(void) {
    return DYPlusTapInstalled.load(std::memory_order_acquire);
}

BOOL DYPlusAudioTapIsCapturing(void) {
    return DYPlusCaptureActive.load(std::memory_order_acquire);
}

uint64_t DYPlusAudioTapCaptureStartTicks(void) {
    return DYPlusCaptureStartTicks.load(std::memory_order_acquire);
}

uint64_t DYPlusAudioTapCaptureStopTicks(void) {
    return DYPlusCaptureStopTicks.load(std::memory_order_acquire);
}

double DYPlusAudioTapSecondsFromTicks(uint64_t ticks) {
    return DYPlusTicksToSeconds(ticks);
}

double DYPlusAudioTapSecondsRelativeTo(uint64_t ticks, uint64_t origin) {
    return DYPlusRelativeSeconds(ticks, origin);
}

double DYPlusAudioTapCurrentCaptureSecond(void) {
    uint64_t start = DYPlusCaptureStartTicks.load(std::memory_order_acquire);
    return start ? DYPlusRelativeSeconds(mach_continuous_time(), start) : -1.0;
}

BOOL DYPlusAudioTapBeginCapture(double warmupSeconds, double recordSeconds) {
    if (!DYPlusTapInstalled.load(std::memory_order_acquire) ||
        !DYPlusTapEnabled.load(std::memory_order_acquire) ||
        warmupSeconds < 0 || recordSeconds <= 0 || recordSeconds > kDYPlusMaxPCMSeconds) return NO;

    os_unfair_lock_lock(&DYPlusCaptureControlLock);
    if (DYPlusCaptureActive.load(std::memory_order_acquire)) {
        os_unfair_lock_unlock(&DYPlusCaptureControlLock);
        return NO;
    }

    DYPlusCaptureStartTicks.store(0, std::memory_order_release);
    DYPlusCaptureStopTicks.store(0, std::memory_order_release);
    DYPlusPCMAllocationFailures.store(0, std::memory_order_relaxed);
    BOOL anySlot = NO;
    for (uint32_t i = 0; i < kDYPlusCaptureSlots; i++) {
        if (!DYPlusPCMSlots[i].samples) DYPlusPCMSlots[i].samples = (float *)calloc(kDYPlusMaxPCMFrames, sizeof(float));
        if (DYPlusPCMSlots[i].samples) anySlot = YES;
        else DYPlusPCMAllocationFailures.fetch_add(1, std::memory_order_relaxed);
        DYPlusPCMSlots[i].sourceID.store(0, std::memory_order_relaxed);
        DYPlusPCMSlots[i].frameCount.store(0, std::memory_order_relaxed);
        DYPlusPCMSlots[i].format = {};
    }
    if (!anySlot) {
        os_unfair_lock_unlock(&DYPlusCaptureControlLock);
        return NO;
    }

    uint32_t sourceCount = DYPlusSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < sourceCount; i++) {
        DYPlusSource &source = DYPlusSources[i];
        source.captureSlot.store(-1, std::memory_order_relaxed);
        source.firstCallbackTicks.store(0, std::memory_order_relaxed);
        source.previousCallbackTicks.store(0, std::memory_order_relaxed);
        source.callbackIntervalCount.store(0, std::memory_order_relaxed);
        source.callbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.minCallbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.maxCallbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.estimatedDroppedFrames.store(0, std::memory_order_relaxed);
        source.contentionDrops.store(0, std::memory_order_relaxed);
        source.unsupportedBuffers.store(0, std::memory_order_relaxed);
        source.unreadableFrames.store(0, std::memory_order_relaxed);
        source.captureSlotMisses.store(0, std::memory_order_relaxed);
        source.formatMismatchBuffers.store(0, std::memory_order_relaxed);
        source.pcmCapacityDroppedFrames.store(0, std::memory_order_relaxed);
        source.probeTicks.store(0, std::memory_order_relaxed);
        source.probeBlocks.store(0, std::memory_order_relaxed);
        source.maxProbeTicks.store(0, std::memory_order_relaxed);
    }

    uint64_t start = mach_continuous_time();
    uint64_t pcmStart = start + DYPlusNanosecondsToTicks((uint64_t)(warmupSeconds * 1.0e9));
    DYPlusCaptureStartTicks.store(start, std::memory_order_release);
    DYPlusPCMStartTicks.store(pcmStart, std::memory_order_release);
    DYPlusPCMStopTicks.store(pcmStart + DYPlusNanosecondsToTicks((uint64_t)(recordSeconds * 1.0e9)),
                         std::memory_order_release);
    DYPlusCaptureActive.store(true, std::memory_order_release);
    os_unfair_lock_unlock(&DYPlusCaptureControlLock);
    return YES;
}

void DYPlusAudioTapEndCapture(void) {
    DYPlusCaptureActive.store(false, std::memory_order_release);
    uint64_t zero = 0;
    DYPlusCaptureStopTicks.compare_exchange_strong(zero, mach_continuous_time(),
                                               std::memory_order_release,
                                               std::memory_order_relaxed);
}

void DYPlusAudioTapWaitForWriters(void) {
    for (int attempt = 0; attempt < 100 && DYPlusActiveWriters.load(std::memory_order_acquire) > 0; attempt++) {
        usleep(1000);
    }
}

uint32_t DYPlusAudioTapSlotCount(void) {
    return kDYPlusCaptureSlots;
}

BOOL DYPlusAudioTapReadSlot(uint32_t index, DYPlusAudioTapSlot *out) {
    if (index >= kDYPlusCaptureSlots || !out) return NO;
    int sourceID = DYPlusPCMSlots[index].sourceID.load(std::memory_order_acquire);
    uint64_t frames = DYPlusPCMSlots[index].frameCount.load(std::memory_order_acquire);
    if (sourceID <= 0 || frames == 0 || !DYPlusPCMSlots[index].samples) return NO;
    out->sourceID = (uint32_t)sourceID;
    out->kind = (uint32_t)sourceID <= kDYPlusMaxSources ? DYPlusSources[sourceID - 1].kind : 0;
    out->samples = DYPlusPCMSlots[index].samples;
    out->frameCount = frames;
    out->sampleRate = DYPlusPCMSlots[index].format.mSampleRate;
    out->sourceFormat = DYPlusPCMSlots[index].format;
    return YES;
}
