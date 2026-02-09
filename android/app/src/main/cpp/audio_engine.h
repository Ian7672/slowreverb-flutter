#pragma once

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "oboe/Oboe.h"

#define SOUNDTOUCH_FLOAT_SAMPLES 1
#include "SoundTouch.h"

#include "simple_reverb.h"

class AudioEngine : public oboe::AudioStreamDataCallback,
                    public oboe::AudioStreamErrorCallback {
 public:
  AudioEngine();
  ~AudioEngine();

  bool start(const std::string& path);
  void stop();
  bool isRunning() const { return running_.load(); }

  void setTempo(double tempo);
  void setPitchSemiTones(double semi);
  void setWet(double wet);
  void setDecay(double seconds);
  void setTone(double tone);
  void setRoomSize(double room);
  void setEcho(double echoMs);

  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                        void* audioData,
                                        int32_t numFrames) override;
  void onErrorAfterClose(oboe::AudioStream* stream,
                         oboe::Result error) override;

  double currentPositionMs() const;
  double durationMs() const;

 private:
  void updateSmoothedParameters();
  static float smoothTowards(float current, float target, float factor);

  void initRingBuffer(int32_t sampleRate, int32_t channelCount);
  int pushToRing(const float* data, int frames);
  int popFromRing(float* dst, int maxFrames);
  void writeFrames(int64_t frameIndex, const float* src, int frames);
  void readFrames(int64_t frameIndex, float* dst, int frames);
  bool openStream(int32_t sampleRate, int32_t channelCount);
  void closeStream();
  void decodingLoop(const std::string& path);

  std::atomic<bool> running_{false};
  std::atomic<bool> decoderReady_{false};
  std::unique_ptr<oboe::AudioStream> stream_;
  std::thread decodeThread_;

  soundtouch::SoundTouch soundTouch_;
  SimpleReverb reverb_;

  std::vector<float> tempBuffer_;
  std::vector<float> ringScratch_;
  std::vector<float> decodeRing_;
  int32_t channelCount_ = 2;
  int32_t sampleRate_ = 48000;
  float wetMix_ = 0.25f;
  float decaySeconds_ = 6.0f;
  float toneBalance_ = 0.6f;
  float roomSize_ = 0.8f;
  float echoMs_ = 0.0f;
  size_t ringCapacityFrames_ = 0;
  std::atomic<int64_t> ringWriteIndex_{0};
  std::atomic<int64_t> ringReadIndex_{0};
  float currentTempo_ = 1.0f;
  float pitchSemi_ = 0.0f;
  std::atomic<float> targetTempo_{1.0f};
  std::atomic<float> targetPitch_{0.0f};
  std::atomic<float> targetWet_{0.25f};
  std::atomic<float> targetDecay_{6.0f};
  std::atomic<float> targetTone_{0.6f};
  std::atomic<float> targetRoom_{0.8f};
  std::atomic<float> targetEcho_{0.0f};
  std::atomic<int64_t> playedFrames_{0};
  std::atomic<int64_t> durationUs_{0};
};
