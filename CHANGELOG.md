# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Keyboard command simulator `openmind-sandbox keys`: held arrows give
  `left` / `right` / `forward`, space one `action`, no key `rest`, adjustable
  confidence; `running` status at 4 Hz; script mode replaying commands from
  YAML (`examples/keys-demo.yaml`); fake `bandpower` messages at 10 Hz
  (`--bandpower`) with a desynchronization over C4, C3 or Cz. Every message is
  validated against `openmind-protocol`. See `docs/keys.md`.
- `MqttLink`: MQTT connection publishing validated protocol messages.
- Repository skeleton: `openmind-sandbox` package and command, dependency on
  `openmind-protocol` 1.0.1 (from the core repository), lint, typing and tests,
  CI, Git LFS rules for heavy assets.
- Local Mosquitto broker for development (`dev/docker-compose.yml`, MQTT on
  1883 and WebSocket on 9001, anonymous access, development only).
