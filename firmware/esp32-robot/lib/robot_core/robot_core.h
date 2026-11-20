// Portable core of the OpenMind robot firmware: protocol parsing, safety rules
// and state machine. No Arduino dependency, so it is unit-tested on the host
// (`pio test -e native`). Mirrors src/openmind_sandbox/mock_robot.py.
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace openmind {

enum class State : uint8_t { Stopped, Moving, Pivoting, SafetyStop };
enum class Command : uint8_t { Rest, Left, Right, Forward, Action };

struct RobotParams {
  float wheelBaseM;
  float maxSpeedMps;
  float accelerationMps2;
  float pivotSpeedDps;
  float uturnDeg;
  float obstacleStopM;
  float statusTimeoutS;
  float minConfidence;
};

// Parameters of include/robot_config.h (generated from config/robot.yaml).
RobotParams defaultParams();

// Signed surface speed of each wheel, m/s (positive = forward).
struct WheelSpeeds {
  float left;
  float right;
};

const char* stateName(State state);
const char* commandName(Command command);

class RobotCore {
 public:
  explicit RobotCore(const RobotParams& params);

  // Feed a payload received on openmind/v1/status or openmind/v1/commands.
  // An invalid payload (bad JSON, schema, other major version) is a fault:
  // the robot stops until the next valid running status. Returns false then.
  bool handleStatus(const char* payload, size_t length, uint32_t nowMs);
  bool handleCommand(const char* payload, size_t length, uint32_t nowMs);

  // Fail safe on a lost broker connection (or any other fault).
  void fault(const char* reason);

  // Advance to nowMs. obstacleM is the measured distance ahead, or a negative
  // value when nothing is in range. Returns the wheel speeds to apply.
  WheelSpeeds step(uint32_t nowMs, float obstacleM);

  State state() const { return state_; }
  const char* reason() const { return reason_; }
  Command command() const { return command_; }
  float speed() const { return speed_; }
  float turnRateDps() const { return turnRateDps_; }
  bool decoderAlive(uint32_t nowMs) const;

  // Telemetry JSON (protocol `event`, object "robot", kind "telemetry").
  // Returns the length written, 0 if the buffer is too small.
  size_t telemetryJson(char* buffer, size_t size, float obstacleM, double unixTime) const;

 private:
  void stopCommand();
  void setState(State state, const char* reason);

  RobotParams p_;
  State state_ = State::SafetyStop;
  const char* reason_ = "no_status";
  const char* commandReason_ = "";
  const char* fault_ = nullptr;
  Command command_ = Command::Rest;
  float speed_ = 0.0f;
  float turnRateDps_ = 0.0f;
  float uturnLeftDeg_ = 0.0f;
  bool haveStatus_ = false;
  bool statusRunning_ = false;
  uint32_t lastStatusMs_ = 0;
  uint32_t lastStepMs_ = 0;
  bool stepped_ = false;
  bool haveSeq_ = false;
  int64_t lastSeq_ = -1;
  char statusReason_[32] = "decoder_";  // "decoder_<state>" when not running
};

}  // namespace openmind
