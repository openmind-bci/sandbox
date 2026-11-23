# Wheeled robot: hardware guide (SBX-090)

How to build, flash, power on and validate the OpenMind wheeled robot. It is a
checklist to run **with the real parts**, and the results go in the tables below.
The firmware is in [`firmware/esp32-robot/`](../../firmware/esp32-robot/) (see
[Firmware](../firmware.md)); the parameters are those of
[`config/robot.yaml`](../../config/robot.yaml) (see [Robot configuration](../robot-config.md)).

> Research and experimentation project, not a medical device. The robot is a
> small toy: keep it on a table-top course, away from stairs, people's feet and
> pets, and keep the motor switch within reach.

## 1. Parts

| Part | Notes |
|---|---|
| ESP32 DevKit (`esp32dev`, 30 or 38 pins) | any board PlatformIO builds as `esp32dev` |
| TB6612FNG motor driver board | dual H-bridge, 1.2 A per channel; a breakout with `VM`, `VCC`, `GND`, `STBY`, `PWMA/AIN1/AIN2`, `PWMB/BIN1/BIN2`, `AO1/AO2`, `BO1/BO2` |
| HC-SR04 ultrasonic sensor | 5 V part, 2 cm to 4 m |
| 2 DC gear motors with 65 mm wheels | `robot.yaml` assumes 65 mm wheels, 130 mm apart; take motors rated for your battery voltage (6 V gear motors are common) |
| Ball or skid caster | third point of support at the rear |
| Motor battery pack | between 4.5 V and 13.5 V (TB6612FNG `VM`), for example 4 AA (6 V) or 2S Li-ion with its protection board |
| Logic power | a USB power bank on the ESP32 USB port, **or** a 5 V buck converter on the battery |
| Switch on the motor supply | a physical kill switch for the motors |
| Resistors 1 kohm and 2 kohm (or 1 kohm and 2.2 kohm) | divider on the HC-SR04 `ECHO` |
| 10 kohm resistor | pull-down on `STBY`, so the motors stay off while the ESP32 boots |
| 100 uF electrolytic capacitor | across `VM` and `GND`, close to the driver |
| Breadboard or perfboard, jumper wires | solder or screw terminals for the motor wires |
| Chassis | about 180 x 150 mm (`geometry.length_m`, `width_m`); the sensor faces forward at the front edge |

## 2. Wiring

Pins are those of `firmware/esp32-robot/src/main.cpp`. Change them there and
here together, never only one.

| ESP32 GPIO | Connected to | Role |
|---|---|---|
| 27 | TB6612FNG `STBY` (+ 10 kohm to GND) | standby: low = motors off |
| 25 | `PWMA` | left motor speed (PWM 20 kHz, 8 bits) |
| 33 | `AIN1` | left motor direction |
| 32 | `AIN2` | left motor direction |
| 26 | `PWMB` | right motor speed (PWM 20 kHz, 8 bits) |
| 14 | `BIN1` | right motor direction |
| 12 | `BIN2` | right motor direction |
| 5 | HC-SR04 `TRIG` | trigger (3.3 V is read as high) |
| 18 | HC-SR04 `ECHO`, **through the divider** | echo |
| 3V3 | TB6612FNG `VCC` | logic supply of the driver |
| GND | `GND` of the driver, of the sensor, of the battery | **common ground, mandatory** |
| VIN / 5V | HC-SR04 `VCC` | 5 V of the USB supply |

| Other connections | |
|---|---|
| Battery + (through the kill switch) | TB6612FNG `VM` (and the 100 uF capacitor) |
| Battery - | `GND` (common with the ESP32) |
| `AO1`, `AO2` | left motor |
| `BO1`, `BO2` | right motor |

**ECHO divider.** The HC-SR04 answers at 5 V and the ESP32 inputs are **not**
5 V tolerant. Put 1 kohm from `ECHO` to GPIO 18 and 2 kohm from GPIO 18 to GND:
GPIO 18 then sees about 3.3 V.

```
 Battery + ──[switch]──┬──────────────► TB6612FNG VM          ┌─► left motor
                       └─ 100 uF ─┐                      AO1 ──┤
 Battery - ──────────────┬────────┴──► GND (common)      AO2 ──┘
                         │
 USB power bank ─► ESP32 USB                              BO1 ──┐
                                                          BO2 ──┴─► right motor
   ESP32                          TB6612FNG
  ┌─────────┐                    ┌──────────┐
  │ 3V3     ├───────────────────►│ VCC      │
  │ GPIO27  ├───────┬───────────►│ STBY     │
  │         │   10k to GND       │          │
  │ GPIO25  ├───────────────────►│ PWMA     │
  │ GPIO33  ├───────────────────►│ AIN1     │
  │ GPIO32  ├───────────────────►│ AIN2     │
  │ GPIO26  ├───────────────────►│ PWMB     │
  │ GPIO14  ├───────────────────►│ BIN1     │
  │ GPIO12  ├───────────────────►│ BIN2     │
  │ GND     ├───────────────────►│ GND      │
  └─────────┘                    └──────────┘

   ESP32                          HC-SR04
  ┌─────────┐                    ┌──────────┐
  │ VIN(5V) ├───────────────────►│ VCC      │
  │ GPIO5   ├───────────────────►│ TRIG     │
  │ GPIO18  ├◄── divider (below) ┤ ECHO     │
  │ GND     ├───────────────────►│ GND      │
  └─────────┘                    └──────────┘

  ECHO divider:   ECHO ──[ 1k ]──┬── GPIO18
                                 │
                               [ 2k ]
                                 │
                                GND
```

The drawing is schematic; follow the table when wiring.

Cautions:

- GPIO 12 (`BIN2`) is a boot-strapping pin of the ESP32: if it is held high at
  reset the board may refuse to boot. The TB6612FNG inputs have no pull-up, so it
  should work; if the board does not boot, unplug the `BIN2` wire while flashing
  and plug it again afterwards. GPIO 5 (`TRIG`) is also read at boot; do not pull
  it low. (To be confirmed on the real board: note it in the results.)
- Never power the motors from the ESP32 pins or its USB port.
- The 3.3 V of the ESP32 powers the logic of the driver only.

## 3. Flashing

The firmware is built and its safety tests run on the computer without any
hardware; flash only after the wiring is checked.

1. Install [PlatformIO](https://platformio.org) (or use `uvx --from platformio pio`).
2. Prepare the **local** configuration:

   ```bash
   cd firmware/esp32-robot
   cp include/secrets.h.example include/secrets.h
   ```

   Edit `include/secrets.h`: `OPENMIND_WIFI_SSID`, `OPENMIND_WIFI_PASSWORD`, and
   `OPENMIND_MQTT_HOST` (the **local IP address** of the computer running the
   broker, port 1883). `secrets.h` is excluded from Git: never commit it.
3. Start the **local** development broker on that computer
   (`docker compose -f dev/docker-compose.yml up -d`, see
   [Development broker](../dev-broker.md)). It has no authentication: use it on
   your own network only, never a public broker, and do not expose port 1883.
   The ESP32 uses 2.4 GHz Wi-Fi.
4. Run the safety tests and build:

   ```bash
   uvx --from platformio pio test -e native
   uvx --from platformio pio run -e esp32dev
   ```
5. **Wheels off the ground** (section 4), USB cable plugged, flash and open the
   monitor:

   ```bash
   uvx --from platformio pio run -e esp32dev -t upload
   uvx --from platformio pio device monitor
   ```

   The monitor prints `OpenMind robot, robot.yaml 1.1.0` (the version of
   `config/robot.yaml` compiled in). Watch the broker with
   `mosquitto_sub -h localhost -t 'openmind/v1/#' -v`: telemetry events
   (`"object":"robot"`) appear at 5 Hz once Wi-Fi and MQTT are connected.

## 4. First power-on: safety

- **Put the robot on a stand, wheels off the ground**, for every first test and
  after every change of wiring or firmware.
- Keep one hand on the motor switch. Start with the motor switch **off**: check
  that the ESP32 boots and publishes telemetry (state `SAFETY_STOP`, reason
  `no_status`) with nothing moving.
- Switch the motors on. The wheels must stay still until a `running` status
  arrives. If a wheel turns by itself, switch off at once and check `STBY` and
  the pull-down.
- Start the simulator: `openmind-sandbox keys` (it publishes the `running`
  status). Press the left arrow, then the right arrow, then forward, then rest:
  the wheels follow, `rest` stops them.
- Stop `keys` (Ctrl+C): the wheels must stop within 2 s.

## 5. Validation procedure

Run it in this order. Write each result in the table of the step; a failed step
is fixed before the next one. Date and tester: ____________________.

Tools: a tape measure, a stopwatch (or a phone), a flat board for the obstacle, masking
tape, the laptop with `keys`, the broker and `bridge --log` (section 5.7).

### 5.1 Connection

Wi-Fi and MQTT connected, telemetry received.

| Check | Result |
|---|---|
| Monitor shows `robot.yaml 1.1.0` | |
| Telemetry at about 5 Hz on `openmind/v1/events` | |
| Unplug the broker: the robot stops (`reason` `disconnected`), then reconnects | |

### 5.2 Motor direction (wheels off the ground)

With `keys`, hold each arrow for 2 s.

| Command | Expected | Left wheel | Right wheel | OK |
|---|---|---|---|---|
| `forward` | both wheels turn forward | | | |
| `left` | left wheel backward, right wheel forward (pivot to the left, counter-clockwise from above) | | | |
| `right` | left wheel forward, right wheel backward | | | |
| `rest` | both stop | | | |

If one wheel turns the wrong way, swap its two motor wires on the driver
(`AO1`/`AO2` or `BO1`/`BO2`). Do not change the firmware.

### 5.3 Speed against `robot.yaml`

Put the robot on the floor. The firmware turns the commanded speed into a PWM
duty with a calibration constant, `kFullPwmSpeedMps` (0.35 m/s at full PWM), which
is a first estimate: measure the real speed.

**Forward speed.** Stick two marks 1.0 m apart, starting 0.7 m from the start
line (`forward` accelerates at 0.10 m/s2, so it needs about 2.5 s to reach
`max_speed_mps`). Hold forward (`keys`), time the robot between the marks,
speed = 1.0 / time. Do 5 runs, use the average.

**Pivot speed.** Hold `left` for 10 s and count the turns (mark the heading with
tape on the floor): speed = turns x 360 / 10 deg/s. Do it for `left` and `right`.

**U-turn.** Press `action` (space) 5 times and note the angle reached
(protractor or tape): it should be 180 degrees; it is timed, without encoder.

| Quantity | `robot.yaml` | Run 1 | 2 | 3 | 4 | 5 | Average | Deviation |
|---|---|---|---|---|---|---|---|---|
| Max forward speed (m/s) | 0.25 | | | | | | | |
| Pivot `left` (deg/s) | 90 | | | | | | | |
| Pivot `right` (deg/s) | 90 | | | | | | | |
| U-turn (deg) | 180 | | | | | | | |

A deviation above 10 % (a suggested tolerance, to be decided with the first
measurements) means a correction: either the real robot is the reference and
`robot.yaml` changes (section 6), or the PWM calibration constant is adjusted
so that the robot reaches the value of `robot.yaml`.

### 5.4 Obstacle stop at 20 cm (10 trials)

Hold the flat board straight across the path, perpendicular to the robot. Drive
forward at full speed from at least 1 m, hold `forward`. The robot must stop on
its own: state `SAFETY_STOP`, reason `obstacle`. Measure the distance between the
board and the sensor once stopped (`obstacle_stop_m` = 0.20 m). Also try pivoting away
from the board: it must stay possible.

| Trial | Stopped on its own | Distance to the board (cm) | Touched the board |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |
| 9 | | | |
| 10 | | | |

Expected: 10 stops out of 10, no touch, distance close to 20 cm. Also note whether the sensor
misses a thin or oblique object (a chair leg, a board at 45 degrees): that is a
known limit of an ultrasonic sensor, write it down.

### 5.5 Stop when the decoder is cut (no more `status`)

With the robot driving forward under `keys`:

| Test | Expected | Time to stop (s) | OK |
|---|---|---|---|
| Ctrl+C in `keys` | stops within 2 s, reason `no_status` | | |
| Kill the `keys` process (`kill -9`) | stops within 2 s | | |
| Stop the broker (`docker compose -f dev/docker-compose.yml stop`) | stops, reason `disconnected` | | |
| A status other than `running` (see below) | stops at once, reason `decoder_<state>` | | |
| Restart `keys`: the robot does not move by itself | stays stopped until a command | | |

Repeat the first test 3 times. `keys` only sends `running`; to test another state
publish one by hand, for example `mosquitto_pub -h localhost -t
openmind/v1/status -m '{"v":1,"ts":'$(date +%s)',"state":"calibrating","model":"test","user":"P00"}'`
(check the fields against `openmind-protocol` if the message is rejected).

### 5.6 Low confidence

With `keys`, lower the confidence below 0.80 (key `-`) and press forward: the
robot must ignore it. `rest` at low confidence must still stop it.

| Check | Result |
|---|---|
| `forward` at 0.7 ignored | |
| `action` at 0.82 ignored (threshold 0.85) | |
| `rest` at 0.1 stops the robot | |

### 5.7 Same course as the twin

Mark the arena of `scenarios/courses/twin_default.yaml` on the floor with tape: 3 m
by 3 m, start at (0.5, 0.5) facing +y, waypoints at (0.5, 2.4), (2.4, 2.4),
(2.4, 1.5), (1.5, 0.5) with a radius of 0.18 m, and the two posts at (1.5, 1.5)
(radius 0.20) and (2.3, 0.9) (radius 0.12). Record the events:

```bash
openmind-sandbox bridge --log runs/robot-course-1.jsonl
```

Replay the same plan as the twin, `openmind-sandbox keys --script
examples/keys-twin-course.yaml`, or drive it by hand with the arrows. Then:

```bash
openmind-sandbox report runs/robot-course-1.jsonl
```

The real robot sends only telemetry: the report gives a `session` run (duration,
stops, commands, speed). Waypoints and errors are read by eye: a waypoint counts
when the robot centre passes within 0.18 m; an error is a command ignored for
low confidence or a manual correction. Do the same run on the twin (cockpit,
robot twin scene, same script) and compare. See [Course report](../report.md).

| | Twin | Real robot |
|---|---|---|
| Duration (s) | | |
| Waypoints reached (of 4) | | |
| Errors | | |
| Obstacle stops | | |
| Final position error (cm) | n/a | |
| Remarks (drift, slip, sensor) | | |

Do 3 runs of each and note the spread. A real robot that drifts or turns by
more than a few degrees means the speeds of 5.3 are not right yet.

## 6. After the measurements

The results above are the reference; the contract follows them:

1. Edit `config/robot.yaml` with the measured values (`max_speed_mps`,
   `pivot_speed_dps`, `acceleration_mps2`, `wheel_diameter_m`, `wheel_base_m`,
   `obstacle_stop_m`, thresholds...). It is a **contract**: raise `version` (SemVer, a
   value change is a **patch**), add a line to the version table of
   [Robot configuration](../robot-config.md) and to the `CHANGELOG`.
2. Regenerate the firmware header (a test fails when it is stale):

   ```bash
   uv run openmind-sandbox export-firmware
   ```
3. Regenerate the Godot copies: `uv run openmind-sandbox export-godot`.
4. Run `uv run pytest -q`, build the firmware again, flash, and repeat 5.3 and 5.7
   to check that the three robots (real, twin, mock) now agree.
5. If the PWM calibration constant (`kFullPwmSpeedMps` in `main.cpp`) was
   adjusted, say so in the commit message: it is not part of `robot.yaml`.
6. Tick SBX-090 only when every table above is filled and passes.
