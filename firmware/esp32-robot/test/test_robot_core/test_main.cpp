// Host tests of the robot core: `pio test -e native`.
#include <stdio.h>
#include <string.h>
#include <unity.h>

#include <ArduinoJson.h>

#include "robot_config.h"
#include "robot_core.h"

using openmind::Command;
using openmind::RobotCore;
using openmind::State;

namespace {

RobotCore* robot = nullptr;
uint32_t now = 0;
int seq = 0;

bool status(const char* state = "running") {
  char buf[160];
  snprintf(buf, sizeof(buf), "{\"v\":1,\"ts\":1.0,\"state\":\"%s\",\"model\":\"m\",\"user\":\"P00\"}",
           state);
  return robot->handleStatus(buf, strlen(buf), now);
}

bool command(const char* name, float confidence = 0.95f, int forcedSeq = -1) {
  char buf[200];
  snprintf(buf, sizeof(buf),
           "{\"v\":1,\"ts\":1.0,\"command\":\"%s\",\"confidence\":%.3f,\"user\":\"P00\",\"seq\":%d}",
           name, confidence, forcedSeq >= 0 ? forcedSeq : seq++);
  return robot->handleCommand(buf, strlen(buf), now);
}

openmind::WheelSpeeds run(float seconds, bool heartbeat = true, float obstacle = -1.0f) {
  openmind::WheelSpeeds wheels{0, 0};
  const int steps = static_cast<int>(seconds / 0.02f + 0.5f);
  for (int i = 0; i < steps; ++i) {
    now += 20;
    if (heartbeat && i % 12 == 0) status();
    wheels = robot->step(now, obstacle);
  }
  return wheels;
}

}  // namespace

void setUp() {
  now = 100000;
  seq = 0;
  robot = new RobotCore(openmind::defaultParams());
  robot->step(now, -1.0f);
}

void tearDown() { delete robot; }

void test_config_comes_from_robot_yaml() {
  TEST_ASSERT_EQUAL_FLOAT(0.2f, openmind::kObstacleStopM);
  TEST_ASSERT_EQUAL_FLOAT(2.0f, openmind::kStatusTimeoutS);
}

void test_stopped_before_the_first_status() {
  command("forward");
  auto wheels = run(1.0f, false);
  TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
  TEST_ASSERT_EQUAL_STRING("no_status", robot->reason());
  TEST_ASSERT_EQUAL_FLOAT(0.0f, wheels.left);
}

void test_stops_when_status_stops() {
  status();
  command("forward");
  run(1.0f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
  run(1.7f, false);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
  auto wheels = run(0.5f, false);
  TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
  TEST_ASSERT_EQUAL_STRING("no_status", robot->reason());
  TEST_ASSERT_EQUAL_FLOAT(0.0f, wheels.right);
}

void test_non_running_status_stops_at_once() {
  status();
  command("forward");
  run(0.5f);
  status("calibrating");
  robot->step(now, -1.0f);
  TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
  TEST_ASSERT_EQUAL_STRING("decoder_calibrating", robot->reason());
}

void test_low_confidence_is_ignored() {
  status();
  command("forward");
  run(1.0f);
  command("left", 0.5f);
  auto wheels = run(0.02f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
  TEST_ASSERT_TRUE(wheels.left > 0.0f);
  TEST_ASSERT_EQUAL_UINT32(1, robot->ignoredLowConfidence());
}

void test_rest_stops_whatever_its_confidence() {
  status();
  command("forward");
  run(1.0f);
  command("rest", 0.05f);
  auto wheels = run(0.02f);
  TEST_ASSERT_EQUAL(State::Stopped, robot->state());
  TEST_ASSERT_EQUAL_FLOAT(0.0f, wheels.left);
}

void test_action_has_its_own_threshold() {
  TEST_ASSERT_TRUE(openmind::kMinConfidenceAction > openmind::kMinConfidenceForward);
  status();
  command("action", 0.82f);
  run(0.5f);
  TEST_ASSERT_EQUAL(State::Stopped, robot->state());
}

void test_stale_seq_ignored_and_reset_after_silence() {
  status();
  command("forward", 0.95f, 10);
  command("rest", 0.95f, 5);
  run(0.2f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
  run(2.5f, false);
  status();
  command("left", 0.95f, 0);  // restarted decoder
  run(0.1f);
  TEST_ASSERT_EQUAL(State::Pivoting, robot->state());
}

void test_obstacle_stop_and_pivot_away() {
  status();
  command("forward");
  run(1.0f, true, 0.5f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
  auto wheels = run(0.1f, true, 0.19f);
  TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
  TEST_ASSERT_EQUAL_STRING("obstacle", robot->reason());
  TEST_ASSERT_EQUAL_FLOAT(0.0f, wheels.left);
  wheels = run(0.1f, true, 0.2f);  // exactly at the stop distance: still blocked
  TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
  command("left");
  wheels = run(0.1f, true, 0.19f);
  TEST_ASSERT_EQUAL(State::Pivoting, robot->state());
  TEST_ASSERT_TRUE(wheels.left < 0.0f && wheels.right > 0.0f);
}

void test_speed_is_bounded() {
  status();
  command("forward");
  auto wheels = run(1.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, openmind::kAccelerationMps2, wheels.left);
  wheels = run(10.0f);
  TEST_ASSERT_EQUAL_FLOAT(openmind::kMaxSpeedMps, wheels.left);
}

void test_u_turn_completes_despite_rest_and_left() {
  status();
  command("action");
  run(0.1f);
  command("rest");
  run(0.5f);
  command("left");
  command("action");
  run(0.5f);
  TEST_ASSERT_EQUAL(State::Pivoting, robot->state());
  run(1.5f);
  TEST_ASSERT_EQUAL(State::Stopped, robot->state());
}

void test_opposite_rotation_cancels_u_turn() {
  status();
  command("action");
  run(0.5f);
  command("right");
  auto wheels = run(0.1f);
  TEST_ASSERT_EQUAL(State::Stopped, robot->state());
  TEST_ASSERT_EQUAL_FLOAT(0.0f, wheels.right);
}

void test_forward_interrupts_u_turn() {
  status();
  command("action");
  run(0.5f);
  command("forward");
  run(0.1f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
}

void test_invalid_messages_fail_safe() {
  status();
  command("forward");
  run(0.5f);
  const char* bad[] = {
      "not json",
      "{\"v\":2,\"ts\":1,\"command\":\"left\",\"confidence\":0.9,\"user\":\"P00\",\"seq\":1}",
      "{\"v\":1,\"ts\":1,\"command\":\"jump\",\"confidence\":0.9,\"user\":\"P00\",\"seq\":1}",
      "{\"v\":1,\"ts\":1,\"command\":\"left\",\"confidence\":1.5,\"user\":\"P00\",\"seq\":1}",
  };
  for (const char* payload : bad) {
    status();
    TEST_ASSERT_FALSE(robot->handleCommand(payload, strlen(payload), now));
    robot->step(now, -1.0f);
    TEST_ASSERT_EQUAL(State::SafetyStop, robot->state());
    TEST_ASSERT_EQUAL_STRING("invalid_message", robot->reason());
  }
  status();
  command("forward");
  run(0.1f);
  TEST_ASSERT_EQUAL(State::Moving, robot->state());
}

void test_disconnection_fails_safe() {
  status();
  command("forward");
  run(0.5f);
  robot->fault("disconnected");
  run(0.1f, false);
  TEST_ASSERT_EQUAL_STRING("disconnected", robot->reason());
}

void test_telemetry_is_a_protocol_event() {
  status();
  command("forward");
  run(0.5f);
  char buffer[384];
  const size_t n = robot->telemetryJson(buffer, sizeof(buffer), 0.8f, 1763478000.25);
  TEST_ASSERT_TRUE(n > 0);
  JsonDocument doc;
  TEST_ASSERT_EQUAL(DeserializationError::Ok, deserializeJson(doc, buffer, n).code());
  TEST_ASSERT_EQUAL(1, doc["v"].as<int>());
  TEST_ASSERT_EQUAL_STRING("robot", doc["object"]);
  TEST_ASSERT_EQUAL_STRING("telemetry", doc["kind"]);
  TEST_ASSERT_EQUAL_STRING("MOVING", doc["data"]["state"]);
  TEST_ASSERT_TRUE(doc["data"]["reason"].isNull());
  TEST_ASSERT_EQUAL(0, robot->telemetryJson(buffer, 8, 0.8f, 0.0));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_config_comes_from_robot_yaml);
  RUN_TEST(test_stopped_before_the_first_status);
  RUN_TEST(test_stops_when_status_stops);
  RUN_TEST(test_non_running_status_stops_at_once);
  RUN_TEST(test_low_confidence_is_ignored);
  RUN_TEST(test_rest_stops_whatever_its_confidence);
  RUN_TEST(test_action_has_its_own_threshold);
  RUN_TEST(test_stale_seq_ignored_and_reset_after_silence);
  RUN_TEST(test_obstacle_stop_and_pivot_away);
  RUN_TEST(test_speed_is_bounded);
  RUN_TEST(test_u_turn_completes_despite_rest_and_left);
  RUN_TEST(test_opposite_rotation_cancels_u_turn);
  RUN_TEST(test_forward_interrupts_u_turn);
  RUN_TEST(test_invalid_messages_fail_safe);
  RUN_TEST(test_disconnection_fails_safe);
  RUN_TEST(test_telemetry_is_a_protocol_event);
  return UNITY_END();
}
