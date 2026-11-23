#!/usr/bin/env bash
# Full OpenMind chain without a headset (development only):
#   EEG source (plug) -> decoder (core) -> MQTT broker -> mock robot / cockpit.
# See docs/full-chain.md. Run with --help for the options.
#
# The three repositories are expected side by side; as a local convenience the
# defaults below are the sibling directories of this repository. Override them
# with OPENMIND_PLUG_DIR and OPENMIND_CORE_DIR (or --plug-dir / --core-dir).
set -eu

usage() {
  cat <<'EOF'
Usage: dev/run-chain.sh [options]

Starts the broker, an EEG source, the decoder and an object, then waits.
Ctrl+C stops everything; the robot ends stopped.

Source:
  --synthetic          synthetic EEG (montage C), no download (default: replay)
  --dataset NAME       replayed public dataset (default: bnci2014_001)
  --subject N          subject of the replayed dataset (default: 1)
Decoder:
  --model NAME         registry name of the model (default: ts-lr-bnci2014_001-c-riemann,
                       trained on subjects 2-9 when missing: downloads the dataset)
  --profile ID         pseudonymized profile (default: P00, created when missing)
  --warmup-s SECONDS   decoder warm-up on clean signal (default: 30)
  --brain              also publish the band power for the 3D brain
Object:
  --bridge             run the cockpit gateway (ws://127.0.0.1:8780) instead of
                       the mock robot; open the cockpit with: godot --path godot
Test:
  --check              non-interactive: run for --duration, print a summary, exit
                       non-zero when no command or no status was received
  --duration SECONDS   length of a --check run (default: 60)
Paths:
  --plug-dir DIR       plug repository (default: $OPENMIND_PLUG_DIR or ../plug)
  --core-dir DIR       core repository (default: $OPENMIND_CORE_DIR or ../core)
  -h, --help           show this help

Logs: ${OPENMIND_DATA_DIR:-~/openmind-data}/logs/chain-<name>.log
EOF
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SANDBOX_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

SOURCE=replay
DATASET=bnci2014_001
SUBJECT=1
MODEL=ts-lr-bnci2014_001-c-riemann
MODEL_GIVEN=0
PROFILE=P00
WARMUP=30
BRAIN=0
BRIDGE=0
CHECK=0
DURATION=60
PLUG_DIR=${OPENMIND_PLUG_DIR:-}
CORE_DIR=${OPENMIND_CORE_DIR:-}

need_value() {
  if [ "$#" -lt 2 ]; then
    echo "error: $1 needs a value" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --synthetic) SOURCE=synthetic ;;
    --dataset) need_value "$@"; DATASET=$2; shift ;;
    --subject) need_value "$@"; SUBJECT=$2; shift ;;
    --model) need_value "$@"; MODEL=$2; MODEL_GIVEN=1; shift ;;
    --profile) need_value "$@"; PROFILE=$2; shift ;;
    --warmup-s) need_value "$@"; WARMUP=$2; shift ;;
    --brain) BRAIN=1 ;;
    --bridge) BRIDGE=1 ;;
    --check) CHECK=1 ;;
    --duration) need_value "$@"; DURATION=$2; shift ;;
    --plug-dir) need_value "$@"; PLUG_DIR=$2; shift ;;
    --core-dir) need_value "$@"; CORE_DIR=$2; shift ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$PLUG_DIR" ] || PLUG_DIR=$SANDBOX_DIR/../plug
[ -n "$CORE_DIR" ] || CORE_DIR=$SANDBOX_DIR/../core
for d in "$PLUG_DIR" "$CORE_DIR"; do
  if [ ! -d "$d" ]; then
    echo "error: repository not found: $d (use --plug-dir / --core-dir)" >&2
    exit 2
  fi
done
PLUG_DIR=$(cd "$PLUG_DIR" && pwd)
CORE_DIR=$(cd "$CORE_DIR" && pwd)

# The calling shell may have another project's environment activated.
unset VIRTUAL_ENV

DATA_DIR=${OPENMIND_DATA_DIR:-$HOME/openmind-data}
export OPENMIND_DATA_DIR=$DATA_DIR
LOG_DIR=$DATA_DIR/logs
mkdir -p "$LOG_DIR"

# One process group per background job, so that a whole `uv run` tree can be stopped.
set -m
PIDS=""
CLEANED=0

log() { echo "[chain] $*"; }

start() { # start NAME DIR COMMAND...
  name=$1
  dir=$2
  shift 2
  log "starting $name (log: $LOG_DIR/chain-$name.log)"
  (cd "$dir" && exec "$@") >"$LOG_DIR/chain-$name.log" 2>&1 &
  PIDS="$PIDS $!"
  eval "PID_$name=$!"
}

stop_pid() {
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null || true
}

cleanup() {
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  trap - INT TERM EXIT
  log "stopping"
  # Decoder side first: without status for 2 s the robot stops by itself.
  for name in online bandpower plug; do
    eval "pid=\${PID_$name:-}"
    [ -n "$pid" ] && stop_pid "$pid"
  done
  if [ -n "${PID_robot:-}${PID_bridge:-}" ]; then
    sleep 3
  fi
  for pid in $PIDS; do
    stop_pid "$pid"
  done
  for pid in $PIDS; do
    wait "$pid" 2>/dev/null || true
  done
  if [ -n "${PID_robot:-}" ]; then
    log "robot stopped (no status from the decoder for more than 2 s)"
  fi
  if [ "$STARTED_BROKER" = 1 ]; then
    log "broker left running (stop it with: docker compose -f dev/docker-compose.yml down)"
  fi
}
STARTED_BROKER=0
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

wait_for_log() { # wait_for_log NAME PATTERN SECONDS
  i=0
  while [ "$i" -lt "$3" ]; do
    if grep -q -i -E "$2" "$LOG_DIR/chain-$1.log" 2>/dev/null; then
      return 0
    fi
    eval "pid=\${PID_$1:-}"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

fail_log() { # fail_log NAME
  echo "error: $1 failed; last lines of $LOG_DIR/chain-$1.log:" >&2
  tail -n 15 "$LOG_DIR/chain-$1.log" >&2 || true
  exit 1
}

port_open() {
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 1883 >/dev/null 2>&1
  else
    (exec 3<>/dev/tcp/127.0.0.1/1883) >/dev/null 2>&1
  fi
}

# 1. Broker.
if port_open; then
  log "broker already listening on 1883"
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: no broker on port 1883 and docker is not installed (see docs/dev-broker.md)" >&2
    exit 1
  fi
  log "starting the broker (docker compose)"
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d >"$LOG_DIR/chain-broker.log" 2>&1 ||
    { cat "$LOG_DIR/chain-broker.log" >&2; echo "error: cannot start the broker (is docker running?)" >&2; exit 1; }
  STARTED_BROKER=1
  i=0
  while ! port_open; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && { echo "error: broker did not open port 1883" >&2; exit 1; }
    sleep 1
  done
fi

# 2. Profile and model.
if ! (cd "$CORE_DIR" && uv run openmind-core profile show "$PROFILE" >/dev/null 2>&1); then
  log "creating profile $PROFILE"
  (cd "$CORE_DIR" && uv run openmind-core profile create "$PROFILE") >"$LOG_DIR/chain-profile.log" 2>&1 ||
    fail_log profile
fi
if [ ! -f "$DATA_DIR/models/$MODEL/card.json" ]; then
  if [ "$MODEL_GIVEN" = 1 ]; then
    echo "error: model $MODEL not found in $DATA_DIR/models (train it with openmind-core train)" >&2
    exit 1
  fi
  log "training $MODEL on $DATASET subjects 2-9 (downloads the dataset, a few minutes)"
  (cd "$CORE_DIR" && uv run --extra research openmind-core train --dataset "$DATASET" \
    --subjects 2-9 --model ts-lr --classes left,right,forward --channels C \
    --alignment riemann --name "$MODEL") >"$LOG_DIR/chain-train.log" 2>&1 || fail_log train
fi

# 3. EEG source.
if [ "$SOURCE" = synthetic ]; then
  start plug "$PLUG_DIR" uv run openmind-plug stream --source synthetic --montage C --no-keyboard
else
  start plug "$PLUG_DIR" uv run --extra replay openmind-plug stream --source replay \
    --dataset "$DATASET" --subject "$SUBJECT" --montage C --loop
fi
sleep 5
kill -0 "$PID_plug" 2>/dev/null || fail_log plug

# 4. Optional band power for the 3D brain.
if [ "$BRAIN" = 1 ]; then
  start bandpower "$CORE_DIR" uv run --with-editable "$PLUG_DIR" openmind-core bandpower --user "$PROFILE" --expected C
fi

# 5. Decoder.
start online "$CORE_DIR" uv run --with-editable "$PLUG_DIR" openmind-core online --profile "$PROFILE" --model "$MODEL" \
  --warmup-s "$WARMUP" --quiet
sleep 3
kill -0 "$PID_online" 2>/dev/null || fail_log online

# 6. Object.
EVENTS=$LOG_DIR/chain-events.jsonl
if [ "$CHECK" = 1 ]; then
  : >"$EVENTS"
  start bridge "$SANDBOX_DIR" uv run openmind-sandbox bridge --no-lsl --log "$EVENTS"
  start robot "$SANDBOX_DIR" uv run openmind-sandbox mock-robot --quiet
  log "checking for $DURATION s (decoder warm-up: $WARMUP s, the robot stays stopped meanwhile)"
  elapsed=0
  while [ "$elapsed" -lt "$DURATION" ]; do
    kill -0 "$PID_online" 2>/dev/null || fail_log online
    sleep 1
    elapsed=$((elapsed + 1))
  done
  cd "$SANDBOX_DIR"
  status=0
  uv run python "$SCRIPT_DIR/summarize_chain.py" "$EVENTS" || status=$?
  exit "$status"
fi

if [ "$BRIDGE" = 1 ]; then
  start bridge "$SANDBOX_DIR" uv run openmind-sandbox bridge --log "$EVENTS"
  log "gateway on ws://127.0.0.1:8780; open the cockpit: godot --path godot"
  log "Ctrl+C to stop"
  wait "$PID_bridge" || true
else
  # The live state line goes straight to the terminal (no log file).
  log "mock robot running; Ctrl+C to stop"
  (cd "$SANDBOX_DIR" && exec uv run openmind-sandbox mock-robot) &
  PID_robot=$!
  PIDS="$PIDS $PID_robot"
  wait "$PID_robot" || true
fi
