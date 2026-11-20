# Development MQTT broker

`dev/docker-compose.yml` starts [Eclipse Mosquitto](https://mosquitto.org) 2 with
the configuration in `dev/mosquitto/mosquitto.conf`:

| Port | Protocol | Used by |
|---|---|---|
| 1883 | MQTT over TCP | Python tools, ESP32 robot |
| 9001 | MQTT over WebSocket | browser tools |

```bash
docker compose -f dev/docker-compose.yml up -d
docker compose -f dev/docker-compose.yml logs -f mosquitto
docker compose -f dev/docker-compose.yml down
```

> [!CAUTION]
> **Development only.** This broker accepts anonymous clients without TLS: anyone
> who can reach its ports can publish commands to your objects. Keep it on your
> machine or on a trusted local network, and never forward its ports to the
> internet. A deployment with real objects needs authentication (password file
> or certificates) and access control lists.

Without Docker, any MQTT 3.1.1 or 5 broker works (for example `brew install
mosquitto` then `mosquitto -c dev/mosquitto/mosquitto.conf`).

To watch the traffic, with the Mosquitto clients installed:

```bash
mosquitto_sub -h localhost -t 'openmind/v1/#' -v
```
