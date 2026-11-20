#include "robot_core.h"

#include <ArduinoJson.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "robot_config.h"

namespace openmind {

namespace {

constexpr int kProtocolMajor = 1;
constexpr float kStopTolerance = 1e-6f;
constexpr float kDegToRad = 3.14159265358979f / 180.0f;

bool parseCommandName(const char* name, Command* out) {
  if (name == nullptr) return false;
  if (strcmp(name, "rest") == 0) *out = Command::Rest;
  else if (strcmp(name, "left") == 0) *out = Command::Left;
  else if (strcmp(name, "right") == 0) *out = Command::Right;
  else if (strcmp(name, "forward") == 0) *out = Command::Forward;
  else if (strcmp(name, "action") == 0) *out = Command::Action;
  else return false;
  return true;
}

bool validVersion(JsonDocument& doc) {
  return doc["v"].is<int>() && doc["v"].as<int>() == kProtocolMajor && doc["ts"].is<float>();
}

}  // namespace

RobotParams defaultParams() {
  return RobotParams{kWheelBaseM,       kMaxSpeedMps,          kAccelerationMps2,
                     kPivotSpeedDps,    kUturnDeg,             kObstacleStopM,
                     kStatusTimeoutS,   kMinConfidenceLeft,    kMinConfidenceRight,
                     kMinConfidenceForward, kMinConfidenceAction};
}

float RobotParams::threshold(Command command) const {
  switch (command) {
    case Command::Left: return minConfidenceLeft;
    case Command::Right: return minConfidenceRight;
    case Command::Forward: return minConfidenceForward;
    case Command::Action: return minConfidenceAction;
    case Command::Rest:
    default: return 0.0f;
  }
}

const char* stateName(State state) {
  switch (state) {
    case State::Stopped: return "STOPPED";
    case State::Moving: return "MOVING";
    case State::Pivoting: return "PIVOTING";
    case State::SafetyStop: return "SAFETY_STOP";
  }
  return "?";
}

const char* commandName(Command command) {
  switch (command) {
    case Command::Rest: return "rest";
    case Command::Left: return "left";
    case Command::Right: return "right";
    case Command::Forward: return "forward";
    case Command::Action: return "action";
  }
  return "?";
}

RobotCore::RobotCore(const RobotParams& params) : p_(params) {}

bool RobotCore::decoderAlive(uint32_t nowMs) const {
  if (!haveStatus_ || !statusRunning_) return false;
  return (nowMs - lastStatusMs_) < static_cast<uint32_t>(p_.statusTimeoutS * 1000.0f);
}

bool RobotCore::handleStatus(const char* payload, size_t length, uint32_t nowMs) {
  JsonDocument doc;
  if (deserializeJson(doc, payload, length) != DeserializationError::Ok || !validVersion(doc) ||
      !doc["state"].is<const char*>() || !doc["model"].is<const char*>()) {
    fault("invalid_message");
    return false;
  }
  const char* state = doc["state"];
  if (!decoderAlive(nowMs)) {
    haveSeq_ = false;  // the decoder was silent or restarted: its seq starts over
  }
  haveStatus_ = true;
  lastStatusMs_ = nowMs;
  statusRunning_ = strcmp(state, "running") == 0;
  snprintf(statusReason_, sizeof(statusReason_), "decoder_%s", state);
  if (statusRunning_) {
    fault_ = nullptr;
  } else {
    stopCommand();
  }
  return true;
}

bool RobotCore::handleCommand(const char* payload, size_t length, uint32_t nowMs) {
  JsonDocument doc;
  Command command;
  if (deserializeJson(doc, payload, length) != DeserializationError::Ok || !validVersion(doc) ||
      !parseCommandName(doc["command"] | static_cast<const char*>(nullptr), &command) ||
      !doc["confidence"].is<float>() || !doc["seq"].is<int64_t>() ||
      !doc["user"].is<const char*>()) {
    fault("invalid_message");
    return false;
  }
  const float confidence = doc["confidence"];
  const int64_t seq = doc["seq"];
  if (confidence < 0.0f || confidence > 1.0f || seq < 0) {
    fault("invalid_message");
    return false;
  }
  if (!decoderAlive(nowMs) || fault_ != nullptr) return true;  // ignored
  if (confidence < p_.threshold(command)) {
    ++ignoredLowConfidence_;  // ignored: the robot keeps doing what it does
    return true;
  }
  if (haveSeq_ && seq <= lastSeq_) return true;  // stale or duplicate
  haveSeq_ = true;
  lastSeq_ = seq;
  if (command_ == Command::Action) {
    // U-turn in progress: rest, left and action do not cut it; right (the
    // opposite rotation) cancels it; forward interrupts it.
    if (command == Command::Rest || command == Command::Left || command == Command::Action) {
      return true;
    }
    if (command == Command::Right) {
      stopCommand();
      return true;
    }
  }
  if (command == Command::Action) uturnLeftDeg_ = p_.uturnDeg;
  command_ = command;
  return true;
}

void RobotCore::fault(const char* reason) {
  fault_ = reason;
  stopCommand();
}

WheelSpeeds RobotCore::step(uint32_t nowMs, float obstacleM) {
  const float dt = stepped_ ? static_cast<float>(nowMs - lastStepMs_) / 1000.0f : 0.0f;
  stepped_ = true;
  lastStepMs_ = nowMs;

  const char* safety = nullptr;
  if (fault_ != nullptr) safety = fault_;
  else if (haveStatus_ && !statusRunning_) safety = statusReason_;
  else if (!decoderAlive(nowMs)) safety = "no_status";
  if (safety != nullptr) {
    stopCommand();
    setState(State::SafetyStop, safety);
    return WheelSpeeds{0.0f, 0.0f};
  }

  const bool blocked = obstacleM >= 0.0f && obstacleM <= p_.obstacleStopM + kStopTolerance;
  const float pivotWheel = p_.pivotSpeedDps * kDegToRad * p_.wheelBaseM / 2.0f;
  switch (command_) {
    case Command::Forward:
      turnRateDps_ = 0.0f;
      if (blocked) {
        speed_ = 0.0f;
        setState(State::SafetyStop, "obstacle");
        return WheelSpeeds{0.0f, 0.0f};
      }
      speed_ = fminf(p_.maxSpeedMps, speed_ + p_.accelerationMps2 * dt);
      setState(State::Moving, "");
      return WheelSpeeds{speed_, speed_};
    case Command::Left:
    case Command::Right: {
      speed_ = 0.0f;
      const float sign = command_ == Command::Left ? 1.0f : -1.0f;
      turnRateDps_ = sign * p_.pivotSpeedDps;
      setState(State::Pivoting, "");
      return WheelSpeeds{-sign * pivotWheel, sign * pivotWheel};
    }
    case Command::Action: {
      speed_ = 0.0f;
      uturnLeftDeg_ -= p_.pivotSpeedDps * dt;  // open loop: no wheel encoder
      if (uturnLeftDeg_ <= 0.0f) {
        stopCommand();
        setState(State::Stopped, "");
        return WheelSpeeds{0.0f, 0.0f};
      }
      turnRateDps_ = p_.pivotSpeedDps;
      setState(State::Pivoting, "");
      return WheelSpeeds{-pivotWheel, pivotWheel};
    }
    case Command::Rest:
    default:
      stopCommand();
      setState(State::Stopped, "");
      return WheelSpeeds{0.0f, 0.0f};
  }
}

size_t RobotCore::telemetryJson(char* buffer, size_t size, float obstacleM,
                                double unixTime) const {
  JsonDocument doc;
  doc["v"] = kProtocolMajor;
  doc["ts"] = unixTime;
  doc["object"] = "robot";
  doc["kind"] = "telemetry";
  JsonObject data = doc["data"].to<JsonObject>();
  data["speed_mps"] = speed_;
  data["turn_dps"] = turnRateDps_;
  if (obstacleM >= 0.0f) data["obstacle_m"] = obstacleM;
  else data["obstacle_m"] = nullptr;
  data["state"] = stateName(state_);
  if (reason_[0] != '\0') data["reason"] = reason_;
  else data["reason"] = nullptr;
  data["command"] = commandName(command_);
  const size_t needed = measureJson(doc);
  if (needed + 1 > size) return 0;
  return serializeJson(doc, buffer, size);
}

void RobotCore::stopCommand() {
  command_ = Command::Rest;
  speed_ = 0.0f;
  turnRateDps_ = 0.0f;
  uturnLeftDeg_ = 0.0f;
}

void RobotCore::setState(State state, const char* reason) {
  state_ = state;
  reason_ = reason;
}

}  // namespace openmind
