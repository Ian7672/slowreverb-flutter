#include "audio_engine.h"

#include <android/log.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstring>

namespace {
constexpr char kTag[] = "SlowReverbEngine";

void loge(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  __android_log_vprint(ANDROID_LOG_ERROR, kTag, fmt, args);
  va_end(args);
}

void logi(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  __android_log_vprint(ANDROID_LOG_INFO, kTag, fmt, args);
  va_end(args);
}
}  // namespace

AudioEngine::AudioEngine() {
  soundTouch_.setSetting(SETTING_USE_AA_FILTER, 1);
  soundTouch_.setSetting(SETTING_USE_QUICKSEEK, 1);
}

AudioEngine::~AudioEngine() { stop(); }

void AudioEngine::setTempo(double tempo) {
  const float safe = std::clamp(static_cast<float>(tempo), 0.5f, 1.5f);
  targetTempo_.store(safe);
}

void AudioEngine::setPitchSemiTones(double semi) {
  targetPitch_.store(static_cast<float>(semi));
}

void AudioEngine::setWet(double wet) {
  targetWet_.store(std::clamp(static_cast<float>(wet), 0.0f, 1.0f));
}

void AudioEngine::setDecay(double seconds) {
  targetDecay_.store(std::clamp(static_cast<float>(seconds), 0.2f, 12.0f));
}

void AudioEngine::setTone(double tone) {
  targetTone_.store(std::clamp(static_cast<float>(tone), 0.0f, 1.0f));
}

void AudioEngine::setRoomSize(double room) {
  targetRoom_.store(std::clamp(static_cast<float>(room), 0.0f, 1.0f));
}

void AudioEngine::setEcho(double echoMs) {
  targetEcho_.store(std::max(0.0f, static_cast<float>(echoMs)));
}

bool AudioEngine::start(const std::string& path) {
  stop();
  running_.store(true);
  decoderReady_.store(false);
  playedFrames_.store(0);
  durationUs_.store(0);
  decodeThread_ = std::thread(&AudioEngine::decodingLoop, this, path);
  // wait for decoder to initialize sample rate
  const auto timeout = std::chrono::steady_clock::now() +
                       std::chrono::milliseconds(1500);
  while (!decoderReady_.load() &&
         std::chrono::steady_clock::now() < timeout) {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  if (!decoderReady_.load()) {
    loge("Decoder failed to initialize");
    stop();
    return false;
  }
  if (!openStream(sampleRate_, channelCount_)) {
    stop();
    return false;
  }
  reverb_.configure(sampleRate_, channelCount_);
  wetMix_ = targetWet_.load();
  decaySeconds_ = targetDecay_.load();
  toneBalance_ = targetTone_.load();
  roomSize_ = targetRoom_.load();
  echoMs_ = targetEcho_.load();
  reverb_.setParameters(wetMix_, decaySeconds_, toneBalance_, roomSize_,
                        echoMs_);
  currentTempo_ = targetTempo_.load();
  pitchSemi_ = targetPitch_.load();
  soundTouch_.setTempo(currentTempo_);
  soundTouch_.setPitchSemiTones(pitchSemi_);
  return true;
}

void AudioEngine::stop() {
  running_.store(false);
  if (decodeThread_.joinable()) {
    decodeThread_.join();
  }
  playedFrames_.store(0);
  durationUs_.store(0);
  ringWriteIndex_.store(0, std::memory_order_release);
  ringReadIndex_.store(0, std::memory_order_release);
  ringCapacityFrames_ = 0;
  decodeRing_.clear();
  closeStream();
  soundTouch_.clear();
}

bool AudioEngine::openStream(int32_t sampleRate, int32_t channelCount) {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Output)
      .setPerformanceMode(oboe::PerformanceMode::LowLatency)
      .setSharingMode(oboe::SharingMode::Exclusive)
      .setFormat(oboe::AudioFormat::Float)
      .setSampleRate(sampleRate)
      .setChannelCount(channelCount)
      .setCallback(this)
      .setErrorCallback(this);

  oboe::AudioStream* stream = nullptr;
  const auto result = builder.openStream(&stream);
  if (result != oboe::Result::OK) {
    loge("Failed to open audio stream: %s", oboe::convertToText(result));
    return false;
  }
  stream_.reset(stream);
  if (stream_->requestStart() != oboe::Result::OK) {
    loge("Failed to start audio stream");
    return false;
  }
  tempBuffer_.resize(channelCount * stream_->getBufferCapacityInFrames());
  return true;
}

void AudioEngine::closeStream() {
  if (stream_) {
    stream_->stop();
    stream_->close();
    stream_.reset();
  }
}

oboe::DataCallbackResult AudioEngine::onAudioReady(
    oboe::AudioStream* stream,
    void* audioData,
    int32_t numFrames) {
  float* out = static_cast<float*>(audioData);
  int32_t framesRemaining = numFrames;
  updateSmoothedParameters();

  const int kChunk = 1024;
  if (ringCapacityFrames_ > 0) {
    ringScratch_.resize(static_cast<size_t>(kChunk) *
                        static_cast<size_t>(channelCount_));
    while (true) {
      const int pulled =
          popFromRing(ringScratch_.data(), kChunk);
      if (pulled <= 0) break;
      soundTouch_.putSamples(ringScratch_.data(), pulled);
      if (pulled < kChunk) break;
    }
  }

  while (framesRemaining > 0) {
    const int32_t received = soundTouch_.receiveSamples(
        tempBuffer_.data(), framesRemaining);
    if (received <= 0) {
      std::fill(out, out + framesRemaining * channelCount_, 0.0f);
      break;
    }
    reverb_.process(tempBuffer_.data(), received);
    std::memcpy(out, tempBuffer_.data(),
                sizeof(float) * received * channelCount_);
    out += received * channelCount_;
    framesRemaining -= received;
  }

  playedFrames_.fetch_add(numFrames);
  return oboe::DataCallbackResult::Continue;
}

void AudioEngine::onErrorAfterClose(oboe::AudioStream*,
                                    oboe::Result error) {
  loge("Stream error: %s", oboe::convertToText(error));
}

double AudioEngine::currentPositionMs() const {
  const int64_t frames = playedFrames_.load();
  if (sampleRate_ <= 0) return 0.0;
  return static_cast<double>(frames) * 1000.0 /
         static_cast<double>(sampleRate_);
}

double AudioEngine::durationMs() const {
  return static_cast<double>(durationUs_.load()) / 1000.0;
}

float AudioEngine::smoothTowards(float current, float target, float factor) {
  const float delta = target - current;
  if (std::fabs(delta) < 1e-4f) {
    return target;
  }
  return current + delta * factor;
}

void AudioEngine::updateSmoothedParameters() {
  constexpr float kTempoSmooth = 0.12f;
  constexpr float kReverbSmooth = 0.08f;

  const float tempoTarget = targetTempo_.load();
  const float pitchTarget = targetPitch_.load();
  const float tempoNext =
      smoothTowards(currentTempo_, tempoTarget, kTempoSmooth);
  const float pitchNext =
      smoothTowards(pitchSemi_, pitchTarget, kTempoSmooth);
  const bool tempoChanged = std::fabs(tempoNext - currentTempo_) > 5e-4f;
  const bool pitchChanged = std::fabs(pitchNext - pitchSemi_) > 5e-4f;
  if (tempoChanged || pitchChanged) {
    std::lock_guard<std::mutex> lock(soundTouchMutex_);
    if (tempoChanged) {
      soundTouch_.setTempo(tempoNext);
      currentTempo_ = tempoNext;
    } else {
      currentTempo_ = tempoNext;
    }
    if (pitchChanged) {
      soundTouch_.setPitchSemiTones(pitchNext);
      pitchSemi_ = pitchNext;
    } else {
      pitchSemi_ = pitchNext;
    }
  } else {
    currentTempo_ = tempoNext;
    pitchSemi_ = pitchNext;
  }

  const float wetNext = smoothTowards(wetMix_, targetWet_.load(), kReverbSmooth);
  const float decayNext =
      smoothTowards(decaySeconds_, targetDecay_.load(), kReverbSmooth);
  const float toneNext =
      smoothTowards(toneBalance_, targetTone_.load(), kReverbSmooth);
  const float roomNext =
      smoothTowards(roomSize_, targetRoom_.load(), kReverbSmooth);
  const float echoNext =
      smoothTowards(echoMs_, targetEcho_.load(), kReverbSmooth);

  const bool reverbNeedsUpdate =
      std::fabs(wetNext - wetMix_) > 5e-4f ||
      std::fabs(decayNext - decaySeconds_) > 5e-4f ||
      std::fabs(toneNext - toneBalance_) > 5e-4f ||
      std::fabs(roomNext - roomSize_) > 5e-4f ||
      std::fabs(echoNext - echoMs_) > 5e-4f;

  if (reverbNeedsUpdate) {
    wetMix_ = wetNext;
    decaySeconds_ = decayNext;
    toneBalance_ = toneNext;
    roomSize_ = roomNext;
    echoMs_ = echoNext;
    reverb_.setParameters(wetMix_, decaySeconds_, toneBalance_, roomSize_,
                          echoMs_);
  }
}

void AudioEngine::initRingBuffer(int32_t sampleRate, int32_t channels) {
  ringCapacityFrames_ = static_cast<size_t>(sampleRate) * 2;  // ~2 seconds
  const size_t samples = ringCapacityFrames_ * static_cast<size_t>(channels);
  decodeRing_.assign(samples, 0.0f);
  ringScratch_.clear();
  decoderScratch_.clear();
  ringWriteIndex_.store(0, std::memory_order_release);
  ringReadIndex_.store(0, std::memory_order_release);
}

void AudioEngine::writeFrames(int64_t frameIndex,
                              const float* src,
                              int frames) {
  if (frames <= 0 || ringCapacityFrames_ == 0) return;
  const size_t capacity = ringCapacityFrames_;
  const size_t channels = static_cast<size_t>(channelCount_);
  size_t head = static_cast<size_t>(frameIndex % static_cast<int64_t>(capacity));
  size_t framesToEnd = capacity - head;
  int firstFrames = std::min<int>(frames, static_cast<int>(framesToEnd));
  size_t samplesFirst = static_cast<size_t>(firstFrames) * channels;
  std::memcpy(
      decodeRing_.data() + head * channels, src,
      samplesFirst * sizeof(float));
  int remainingFrames = frames - firstFrames;
  if (remainingFrames > 0) {
    std::memcpy(
        decodeRing_.data(),
        src + samplesFirst,
        static_cast<size_t>(remainingFrames) * channels * sizeof(float));
  }
}

void AudioEngine::readFrames(int64_t frameIndex,
                             float* dst,
                             int frames) {
  if (frames <= 0 || ringCapacityFrames_ == 0) return;
  const size_t capacity = ringCapacityFrames_;
  const size_t channels = static_cast<size_t>(channelCount_);
  size_t tail = static_cast<size_t>(frameIndex % static_cast<int64_t>(capacity));
  size_t framesToEnd = capacity - tail;
  int firstFrames = std::min<int>(frames, static_cast<int>(framesToEnd));
  size_t samplesFirst = static_cast<size_t>(firstFrames) * channels;
  std::memcpy(
      dst,
      decodeRing_.data() + tail * channels,
      samplesFirst * sizeof(float));
  int remainingFrames = frames - firstFrames;
  if (remainingFrames > 0) {
    std::memcpy(
        dst + samplesFirst,
        decodeRing_.data(),
        static_cast<size_t>(remainingFrames) * channels * sizeof(float));
  }
}

int AudioEngine::pushToRing(const float* data, int frames) {
  if (ringCapacityFrames_ == 0 || frames <= 0) return 0;
  const size_t capacity = ringCapacityFrames_;
  if (frames > static_cast<int>(capacity)) {
    const int skip = frames - static_cast<int>(capacity);
    data += skip * channelCount_;
    frames = static_cast<int>(capacity);
  }
  auto write = ringWriteIndex_.load(std::memory_order_relaxed);
  auto read = ringReadIndex_.load(std::memory_order_acquire);
  size_t used = static_cast<size_t>(write - read);
  const size_t freeSpace = capacity > used ? capacity - used : 0;
  if (static_cast<size_t>(frames) > freeSpace) {
    const size_t drop = static_cast<size_t>(frames) - freeSpace;
    ringReadIndex_.fetch_add(static_cast<int64_t>(drop),
                             std::memory_order_acq_rel);
    read += static_cast<int64_t>(drop);
    used -= std::min(used, drop);
  }
  writeFrames(write, data, frames);
  ringWriteIndex_.store(write + frames, std::memory_order_release);
  return frames;
}

int AudioEngine::popFromRing(float* dst, int maxFrames) {
  if (ringCapacityFrames_ == 0 || maxFrames <= 0) return 0;
  auto write = ringWriteIndex_.load(std::memory_order_acquire);
  auto read = ringReadIndex_.load(std::memory_order_relaxed);
  int64_t available = write - read;
  if (available <= 0) return 0;
  const int frames = std::min<int>(maxFrames, static_cast<int>(available));
  readFrames(read, dst, frames);
  ringReadIndex_.fetch_add(frames, std::memory_order_release);
  return frames;
}

void AudioEngine::decodingLoop(const std::string& path) {
  AMediaExtractor* extractor = AMediaExtractor_new();
  if (!extractor) {
    loge("Failed to create extractor");
    return;
  }
  if (AMediaExtractor_setDataSource(extractor, path.c_str()) != AMEDIA_OK) {
    loge("Failed to set data source %s", path.c_str());
    AMediaExtractor_delete(extractor);
    return;
  }
  AMediaCodec* codec = nullptr;
  const char* mime = nullptr;
  int32_t channels = 2;
  int32_t sampleRate = 48000;

  const size_t trackCount = AMediaExtractor_getTrackCount(extractor);
  for (size_t i = 0; i < trackCount; ++i) {
    AMediaFormat* format = AMediaExtractor_getTrackFormat(extractor, i);
    const char* formatMime = nullptr;
    if (AMediaFormat_getString(format, AMEDIAFORMAT_KEY_MIME,
                               &formatMime) &&
        strncmp(formatMime, "audio/", 6) == 0) {
      AMediaExtractor_selectTrack(extractor, i);
      mime = formatMime;
      AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channels);
      AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &sampleRate);
      int64_t durationValue = 0;
      if (AMediaFormat_getInt64(format, AMEDIAFORMAT_KEY_DURATION,
                                &durationValue)) {
        durationUs_.store(durationValue);
      }
      codec = AMediaCodec_createDecoderByType(mime);
      if (codec &&
          AMediaCodec_configure(codec, format, nullptr, nullptr, 0) ==
              AMEDIA_OK) {
        AMediaCodec_start(codec);
        AMediaFormat_delete(format);
        break;
      }
      if (codec) {
        AMediaCodec_delete(codec);
        codec = nullptr;
      }
    }
    AMediaFormat_delete(format);
  }

  if (!codec) {
    loge("Failed to initialize decoder for %s", path.c_str());
    AMediaExtractor_delete(extractor);
    return;
  }

  channelCount_ = std::max(1, channels);
  sampleRate_ = std::max(8000, sampleRate);
  soundTouch_.setChannels(channelCount_);
  soundTouch_.setSampleRate(sampleRate_);
  soundTouch_.setTempo(currentTempo_);
  soundTouch_.setPitchSemiTones(pitchSemi_);
  initRingBuffer(sampleRate_, channelCount_);
  decoderReady_.store(true);

  const size_t bufferCapacity = 4096 * channelCount_;
  std::vector<float> floatBuffer(bufferCapacity);

  AMediaCodecBufferInfo info;
  bool extractorEos = false;
  while (running_.load()) {
    if (!extractorEos) {
      const ssize_t inputIndex = AMediaCodec_dequeueInputBuffer(codec, 10000);
      if (inputIndex >= 0) {
        size_t bufSize = 0;
        auto* buffer = AMediaCodec_getInputBuffer(codec, inputIndex, &bufSize);
        const int sampleSize =
            AMediaExtractor_readSampleData(extractor, buffer, bufSize);
        const int64_t presentationTimeUs =
            AMediaExtractor_getSampleTime(extractor);
        if (sampleSize < 0) {
          extractorEos = true;
          AMediaCodec_queueInputBuffer(
              codec, inputIndex, 0, 0, 0,
              AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
        } else {
          AMediaCodec_queueInputBuffer(codec, inputIndex, 0, sampleSize,
                                       presentationTimeUs, 0);
          AMediaExtractor_advance(extractor);
        }
      }
    }

    const ssize_t outputIndex =
        AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);
    if (outputIndex >= 0) {
      size_t outSize = 0;
      auto* buffer = AMediaCodec_getOutputBuffer(codec, outputIndex, &outSize);
      if (info.size > 0 && buffer) {
        const int frameCount =
            info.size / (sizeof(int16_t) * channelCount_);
        if (static_cast<size_t>(frameCount * channelCount_) >
            floatBuffer.size()) {
          floatBuffer.resize(frameCount * channelCount_);
        }
        const int16_t* src = reinterpret_cast<int16_t*>(buffer);
        for (int i = 0; i < frameCount * channelCount_; ++i) {
          floatBuffer[i] = static_cast<float>(src[i]) / 32768.0f;
        }
        pushToRing(floatBuffer.data(), frameCount);
      }
      AMediaCodec_releaseOutputBuffer(
          codec, outputIndex, info.size != 0);

      if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
        logi("Decoder reached end of stream");
        std::lock_guard<std::mutex> lock(soundTouchMutex_);
        soundTouch_.flush();
        break;
      }
    }
  }

  AMediaCodec_stop(codec);
  AMediaCodec_delete(codec);
  AMediaExtractor_delete(extractor);
  logi("Decoder thread exit");
}
