#include "audio_engine.h"

#include <jni.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace {
std::mutex gMutex;
std::unordered_map<intptr_t, std::unique_ptr<AudioEngine>> gEngines;
intptr_t gNextHandle = 1;

AudioEngine* getEngine(intptr_t handle) {
  auto it = gEngines.find(handle);
  return it == gEngines.end() ? nullptr : it->second.get();
}
}  // namespace

extern "C" {

__attribute__((visibility("default"))) intptr_t slowreverb_engine_create() {
  std::lock_guard<std::mutex> lock(gMutex);
  const intptr_t handle = gNextHandle++;
  gEngines[handle] = std::make_unique<AudioEngine>();
  return handle;
}

__attribute__((visibility("default"))) void slowreverb_engine_dispose(
    intptr_t handle) {
  std::lock_guard<std::mutex> lock(gMutex);
  auto it = gEngines.find(handle);
  if (it != gEngines.end()) {
    it->second->stop();
    gEngines.erase(it);
  }
}

__attribute__((visibility("default"))) int slowreverb_engine_start(
    intptr_t handle,
    const char* path) {
  auto* engine = getEngine(handle);
  if (!engine) return -1;
  return engine->start(path) ? 0 : -2;
}

__attribute__((visibility("default"))) void slowreverb_engine_stop(
    intptr_t handle) {
  auto* engine = getEngine(handle);
  if (engine) engine->stop();
}

__attribute__((visibility("default"))) void slowreverb_engine_set_tempo(
    intptr_t handle,
    double tempo) {
  auto* engine = getEngine(handle);
  if (engine) engine->setTempo(tempo);
}

__attribute__((visibility("default"))) void slowreverb_engine_set_pitch(
    intptr_t handle,
    double semi) {
  auto* engine = getEngine(handle);
  if (engine) engine->setPitchSemiTones(semi);
}

__attribute__((visibility("default"))) void slowreverb_engine_set_mix(
    intptr_t handle,
    double wet) {
  auto* engine = getEngine(handle);
  if (engine) engine->setWet(wet);
}

__attribute__((visibility("default")))
void slowreverb_engine_set_reverb(
    intptr_t handle,
    double decay,
    double tone,
    double room,
    double echo_ms) {
  auto* engine = getEngine(handle);
  if (!engine) return;
  engine->setDecay(decay);
  engine->setTone(tone);
  engine->setRoomSize(room);
  engine->setEcho(echo_ms);
}

__attribute__((visibility("default"))) double slowreverb_engine_get_position_ms(
    intptr_t handle) {
  auto* engine = getEngine(handle);
  if (!engine) return 0.0;
  return engine->currentPositionMs();
}

__attribute__((visibility("default"))) double slowreverb_engine_get_duration_ms(
    intptr_t handle) {
  auto* engine = getEngine(handle);
  if (!engine) return 0.0;
  return engine->durationMs();
}

}  // extern "C"
