#include "Audio/Realtime/DYPlusAtomicAudioFormat.h"
#include <thread>
#include <cstdio>
#include <chrono>

int main() {
    DYPlusAtomicAudioFormat format;
    std::atomic<uint32_t> version{0};
    std::atomic<bool> finished{false};
    auto begin = std::chrono::steady_clock::now();
    std::thread writer([&] {
        for (uint32_t index = 1; index <= 200000; index++) {
            AudioStreamBasicDescription value{};
            value.mSampleRate = index;
            value.mFormatID = value.mFormatFlags = value.mBytesPerPacket = value.mFramesPerPacket = index;
            value.mBytesPerFrame = value.mChannelsPerFrame = value.mBitsPerChannel = value.mReserved = index;
            version.fetch_add(1, std::memory_order_acq_rel);
            format.store(value);
            version.fetch_add(1, std::memory_order_release);
        }
        finished.store(true, std::memory_order_release);
    });
    unsigned long snapshots = 0;
    bool valid = true;
    while (!finished.load(std::memory_order_acquire)) {
        uint32_t before = version.load(std::memory_order_acquire);
        if (!before || (before & 1)) continue;
        auto snapshot = format.load();
        std::atomic_thread_fence(std::memory_order_acquire);
        if (before != version.load(std::memory_order_acquire)) continue;
        snapshots++;
        auto index = snapshot.mReserved;
        valid = valid && snapshot.mSampleRate == index && snapshot.mFormatID == index && snapshot.mFormatFlags == index
            && snapshot.mBytesPerPacket == index && snapshot.mFramesPerPacket == index && snapshot.mBytesPerFrame == index
            && snapshot.mChannelsPerFrame == index && snapshot.mBitsPerChannel == index;
    }
    writer.join();
    auto last = format.load();
    valid = valid && last.mReserved == 200000 && last.mSampleRate == 200000;
    double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-begin).count();
    printf("AUDIO ATOMIC: %s; 200000 writes; %lu consistent snapshots; %.2f ms\n", valid ? "PASS" : "FAIL", snapshots, milliseconds);
    return valid ? 0 : 1;
}
