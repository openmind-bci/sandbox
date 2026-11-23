# Adapter template

A starting point to connect your own object (a lamp, a toy, a robot arm, a game)
to OpenMind BCI. The safety rules are inherited from `Adapter`; you only write
what the commands do and how to stop.

1. Copy this folder next to your project and rename `my_object.py`.
2. Rename the class and the `name` given to `super().__init__`.
3. Implement `on_command(command, confidence)` and `stop()`. Optionally
   override `context_allows_action()`.
4. Run the development broker (`docker compose -f dev/docker-compose.yml up -d`),
   then your adapter (`python my_object.py`), then the keyboard simulator in
   another terminal (`openmind-sandbox keys`). Arrows and space move your object;
   quit the simulator and your object stops within 2 seconds.

See [docs/create-your-object.md](../../docs/create-your-object.md).
