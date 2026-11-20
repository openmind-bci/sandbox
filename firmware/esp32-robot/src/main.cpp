// OpenMind wheeled robot: Wi-Fi + MQTT, TB6612FNG motor driver, HC-SR04 sensor.
//
// All decisions (safety rules, state machine) are in lib/robot_core, which is
// unit-tested on the host. This file only wires it to the hardware. The robot
// starts stopped and stays stopped until a running decoder status arrives.
#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <time.h>

#include "robot_config.h"
#include "robot_core.h"

#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy include/secrets.h.example to include/secrets.h and fill it in."
#endif

namespace {

// --- Pins (see docs/hardware/robot.md) -------------------------------------
constexpr int kPinStby = 27;  // TB6612FNG standby: LOW = motors off
constexpr int kPinPwmA = 25, kPinAin1 = 33, kPinAin2 = 32;  // left motor
constexpr int kPinPwmB = 26, kPinBin1 = 14, kPinBin2 = 12;  // right motor
constexpr int kPinTrig = 5, kPinEcho = 18;                  // HC-SR04
constexpr int kPwmChannelA = 0, kPwmChannelB = 1, kPwmBits = 8, kPwmHz = 20000;

// Wheel speed giving full PWM; calibrated on the real robot (SBX-090).
constexpr float kFullPwmSpeedMps = 0.35f;
constexpr uint32_t kStepMs = 20;
constexpr uint32_t kSonarMs = 60;

constexpr const char* kTopicCommands = "openmind/v1/commands";
constexpr const char* kTopicStatus = "openmind/v1/status";
constexpr const char* kTopicEvents = "openmind/v1/events";

WiFiClient wifi;
PubSubClient mqtt(wifi);
openmind::RobotCore core(openmind::defaultParams());
float obstacleM = -1.0f;
uint32_t lastStep = 0, lastSonar = 0, lastTelemetry = 0;

void driveMotor(int pwmChannel, int in1, int in2, float speedMps) {
  const float duty = fminf(fabsf(speedMps) / kFullPwmSpeedMps, 1.0f);
  digitalWrite(in1, speedMps > 0.0f ? HIGH : LOW);
  digitalWrite(in2, speedMps < 0.0f ? HIGH : LOW);
  ledcWrite(pwmChannel, static_cast<uint32_t>(duty * ((1 << kPwmBits) - 1)));
}

void applyWheels(const openmind::WheelSpeeds& wheels) {
  const bool moving = wheels.left != 0.0f || wheels.right != 0.0f;
  digitalWrite(kPinStby, moving ? HIGH : LOW);
  driveMotor(kPwmChannelA, kPinAin1, kPinAin2, wheels.left);
  driveMotor(kPwmChannelB, kPinBin1, kPinBin2, wheels.right);
}

float readSonarM() {
  digitalWrite(kPinTrig, LOW);
  delayMicroseconds(2);
  digitalWrite(kPinTrig, HIGH);
  delayMicroseconds(10);
  digitalWrite(kPinTrig, LOW);
  const uint32_t timeoutUs = static_cast<uint32_t>(openmind::kSensorRangeM * 2.0f / 343.0f * 1e6f);
  const unsigned long echoUs = pulseIn(kPinEcho, HIGH, timeoutUs);
  if (echoUs == 0) return -1.0f;  // nothing in range
  return echoUs * 343.0f / 2.0f / 1e6f;
}

void onMessage(char* topic, uint8_t* payload, unsigned int length) {
  const char* text = reinterpret_cast<const char*>(payload);
  if (strcmp(topic, kTopicStatus) == 0) core.handleStatus(text, length, millis());
  else if (strcmp(topic, kTopicCommands) == 0) core.handleCommand(text, length, millis());
}

void ensureMqtt() {
  if (mqtt.connected()) return;
  core.fault("disconnected");
  applyWheels({0.0f, 0.0f});
  if (WiFi.status() != WL_CONNECTED) return;
  char clientId[32];
  snprintf(clientId, sizeof(clientId), "openmind-robot-%06lx",
           static_cast<unsigned long>(ESP.getEfuseMac() & 0xFFFFFF));
  if (mqtt.connect(clientId)) {
    mqtt.subscribe(kTopicCommands);
    mqtt.subscribe(kTopicStatus);
  }
}

double unixTime() {
  time_t now = time(nullptr);
  return now > 1600000000 ? static_cast<double>(now) : 0.0;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kPinStby, OUTPUT);
  digitalWrite(kPinStby, LOW);  // motors off until the first running status
  for (int pin : {kPinAin1, kPinAin2, kPinBin1, kPinBin2, kPinTrig}) pinMode(pin, OUTPUT);
  pinMode(kPinEcho, INPUT);
  ledcSetup(kPwmChannelA, kPwmHz, kPwmBits);
  ledcSetup(kPwmChannelB, kPwmHz, kPwmBits);
  ledcAttachPin(kPinPwmA, kPwmChannelA);
  ledcAttachPin(kPinPwmB, kPwmChannelB);
  applyWheels({0.0f, 0.0f});

  WiFi.mode(WIFI_STA);
  WiFi.begin(OPENMIND_WIFI_SSID, OPENMIND_WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org");  // ts of telemetry only, never for safety
  mqtt.setServer(OPENMIND_MQTT_HOST, OPENMIND_MQTT_PORT);
  mqtt.setCallback(onMessage);
  mqtt.setBufferSize(512);
  Serial.printf("OpenMind robot, robot.yaml %s\n", openmind::kRobotConfigVersion);
}

void loop() {
  ensureMqtt();
  mqtt.loop();
  const uint32_t now = millis();
  if (now - lastSonar >= kSonarMs) {
    lastSonar = now;
    obstacleM = readSonarM();
  }
  if (now - lastStep >= kStepMs) {
    lastStep = now;
    applyWheels(core.step(now, obstacleM));
  }
  if (now - lastTelemetry >= static_cast<uint32_t>(1000.0f / openmind::kTelemetryRateHz)) {
    lastTelemetry = now;
    char buffer[384];
    const size_t n = core.telemetryJson(buffer, sizeof(buffer), obstacleM, unixTime());
    if (n > 0 && mqtt.connected()) mqtt.publish(kTopicEvents, buffer, n);
  }
}
