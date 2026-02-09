#pragma once

#include <cstdint>
#include <vector>

class SimpleReverb {
 public:
  void configure(int32_t sampleRate, int32_t channels);
  void setParameters(float wet, float decay, float tone, float room, float echo);
  void process(float* interleaved, int32_t frames);

 private:
  struct DelayLine {
    std::vector<float> buffer;
    size_t index = 0;
  };

  void ensureLines();

  int32_t sampleRate_ = 48000;
  int32_t channels_ = 2;
  float wet_ = 0.25f;
  float decay_ = 0.6f;
  float tone_ = 0.6f;
  float room_ = 0.8f;
  float echoMs_ = 0.0f;
  std::vector<DelayLine> combLines_;
  std::vector<DelayLine> echoLines_;
};
