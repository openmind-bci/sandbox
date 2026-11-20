# ESP32 robot firmware

`firmware/esp32-robot/` is a [PlatformIO](https://platformio.org) project
(Arduino framework, `esp32dev`) for the wheeled robot: Wi-Fi + MQTT
(`PubSubClient`), JSON (`ArduinoJson`), TB6612FNG motor driver, HC-SR04 distance
sensor. **Do not flash it before the hardware validation (SBX-090).**

```bash
cd firmware/esp32-robot
cp include/secrets.h.example include/secrets.h   # Wi-Fi and broker; never committed
uvx --from platformio pio run -e esp32dev        # build
uvx --from platformio pio test -e native         # safety tests on the computer
```

## Structure

| Path | Content |
|---|---|
| `lib/robot_core/` | protocol parsing, safety rules and state machine (`STOPPED`, `MOVING`, `PIVOTING`, `SAFETY_STOP`); no Arduino code, tested on the host |
| `src/main.cpp` | hardware glue: Wi-Fi, MQTT, motors, sensor, telemetry |
| `include/robot_config.h` | **generated** from `config/robot.yaml` by `openmind-sandbox export-firmware` (a test fails when it is stale) |
| `include/secrets.h.example` | template of the excluded `secrets.h` |
| `test/test_robot_core/` | Unity tests run by `pio test -e native` |

## Safety rules (cannot be bypassed)

The core applies them before every motor update, with the same behaviour as the
mock robot and the Godot twin:

- stopped at start until a `running` status arrives; stop 2 s after the last
  status, and at once when the status is not `running` (`decoder_<state>`);
- stop on a command below `min_confidence` (`low_confidence`); stale `seq`
  ignored, reset after a decoder silence;
- stop on an invalid message or a lost broker (`invalid_message`,
  `disconnected`) until the next valid `running` status;
- no forward motion at or below `obstacle_stop_m` (`obstacle`); pivoting away
  stays possible; forward speed bounded by `max_speed_mps`.

The motor driver is put in standby (STBY low) whenever both wheels are stopped.
The U-turn of `action` is timed (no wheel encoder). Telemetry is published on
`openmind/v1/events` with `"object": "robot"` at `telemetry.rate_hz`.

Pins (to be confirmed with the wiring diagram of SBX-090): STBY 27; left motor
PWM 25, AIN1 33, AIN2 32; right motor PWM 26, BIN1 14, BIN2 12; HC-SR04 TRIG 5,
ECHO 18 (through a voltage divider: the ESP32 is not 5 V tolerant).
