#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <atomic>

// seqlock 只能检测写入，不能让普通 C++ 字段的并发读写合法。
// 格式字段各自原子化；外层版本号仍用于验证整个格式快照一致性。
struct DYPlusAtomicAudioFormat {
    std::atomic<double> sampleRate{0};
    std::atomic<uint32_t> formatID{0}, flags{0}, bytesPerPacket{0}, framesPerPacket{0};
    std::atomic<uint32_t> bytesPerFrame{0}, channels{0}, bits{0}, reserved{0};
    void store(const AudioStreamBasicDescription &value) {
        sampleRate.store(value.mSampleRate, std::memory_order_relaxed);
        formatID.store(value.mFormatID, std::memory_order_relaxed);
        flags.store(value.mFormatFlags, std::memory_order_relaxed);
        bytesPerPacket.store(value.mBytesPerPacket, std::memory_order_relaxed);
        framesPerPacket.store(value.mFramesPerPacket, std::memory_order_relaxed);
        bytesPerFrame.store(value.mBytesPerFrame, std::memory_order_relaxed);
        channels.store(value.mChannelsPerFrame, std::memory_order_relaxed);
        bits.store(value.mBitsPerChannel, std::memory_order_relaxed);
        reserved.store(value.mReserved, std::memory_order_relaxed);
    }
    AudioStreamBasicDescription load() const {
        AudioStreamBasicDescription value{};
        value.mSampleRate = sampleRate.load(std::memory_order_relaxed);
        value.mFormatID = formatID.load(std::memory_order_relaxed);
        value.mFormatFlags = flags.load(std::memory_order_relaxed);
        value.mBytesPerPacket = bytesPerPacket.load(std::memory_order_relaxed);
        value.mFramesPerPacket = framesPerPacket.load(std::memory_order_relaxed);
        value.mBytesPerFrame = bytesPerFrame.load(std::memory_order_relaxed);
        value.mChannelsPerFrame = channels.load(std::memory_order_relaxed);
        value.mBitsPerChannel = bits.load(std::memory_order_relaxed);
        value.mReserved = reserved.load(std::memory_order_relaxed);
        return value;
    }
};
static_assert(std::atomic<double>::is_always_lock_free, "Realtime double atomics must be lock free");
static_assert(std::atomic<float>::is_always_lock_free, "Realtime sample atomics must be lock free");
static_assert(std::atomic<uint32_t>::is_always_lock_free, "Realtime format atomics must be lock free");
