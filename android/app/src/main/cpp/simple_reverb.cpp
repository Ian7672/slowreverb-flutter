#include "simple_reverb.h"

#include <algorithm>

namespace {
constexpr int kCombCount = 4;
constexpr int kEchoCount = 2;
}  // namespace

void SimpleReverb::configure(int32_t sampleRate, int32_t channels) {
  sampleRate_ = std::max(1, sampleRate);
  channels_ = std::max(1, channels);
  ensureLines();
}

void SimpleReverb::setParameters(float wet,
                                 float decay,
                                 float tone,
                                 float room,
                                 float echo) {
  wet_ = std::clamp(wet, 0.0f, 1.0f);
  decay_ = std::clamp(decay, 0.1f, 12.0f);
  tone_ = std::clamp(tone, 0.0f, 1.0f);
  room_ = std::clamp(room, 0.0f, 1.0f);
  echoMs_ = std::max(0.0f, echo);
  ensureLines();
}

void SimpleReverb::ensureLines() {
  const float roomScale = 0.5f + room_ * 0.8f;
  const int combBaseMs[kCombCount] = {35, 47, 58, 67};
  const int echoBaseMs[kEchoCount] = {120, 180};

  combLines_.resize(channels_ * kCombCount);
  for (int ch = 0; ch < channels_; ++ch) {
    for (int i = 0; i < kCombCount; ++i) {
      const float delayMs = combBaseMs[i] * roomScale;
      const size_t samples =
          static_cast<size_t>(delayMs * sampleRate_ / 1000.0f) + 1;
      auto& line = combLines_[ch * kCombCount + i];
      line.buffer.resize(samples, 0.0f);
      line.index %= samples;
    }
  }

  echoLines_.resize(channels_ * kEchoCount);
  for (int ch = 0; ch < channels_; ++ch) {
    for (int i = 0; i < kEchoCount; ++i) {
      const float delayMs = echoBaseMs[i] + echoMs_;
      const size_t samples =
          static_cast<size_t>(delayMs * sampleRate_ / 1000.0f) + 1;
      auto& line = echoLines_[ch * kEchoCount + i];
      line.buffer.resize(samples, 0.0f);
      line.index %= samples;
    }
  }
}

void SimpleReverb::process(float* interleaved, int32_t frames) {
  if (frames <= 0 || wet_ <= 0.0f) return;
  const float combGain = std::clamp(decay_ / 8.0f, 0.05f, 0.9f);
  const float echoGain = std::clamp(0.2f + (tone_ * 0.4f), 0.2f, 0.7f);
  const float dryMix = 1.0f - wet_;

  for (int32_t frame = 0; frame < frames; ++frame) {
    for (int ch = 0; ch < channels_; ++ch) {
      const int idx = frame * channels_ + ch;
      const float dry = interleaved[idx];
      float accum = 0.0f;
      for (int i = 0; i < kCombCount; ++i) {
        auto& line = combLines_[ch * kCombCount + i];
        const float delayed = line.buffer[line.index];
        line.buffer[line.index] = dry + delayed * combGain;
        line.index = (line.index + 1) % line.buffer.size();
        accum += delayed;
      }
      for (int i = 0; i < kEchoCount; ++i) {
        auto& line = echoLines_[ch * kEchoCount + i];
        const float delayed = line.buffer[line.index];
        line.buffer[line.index] = dry + delayed * echoGain;
        line.index = (line.index + 1) % line.buffer.size();
        accum += delayed * 0.5f;
      }
      const float wetSample = accum / (kCombCount + kEchoCount * 0.5f);
      interleaved[idx] = dry * dryMix + wetSample * wet_;
    }
  }
}
