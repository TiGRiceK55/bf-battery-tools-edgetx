# Changelog

## v1.0.0
First public release.

- **BattView** widget: live battery telemetry (voltage, auto cell count,
  V/cell, colored charge gauge, current and mAh when available). Auto-detects
  the voltage sensor (RxBt/VFAS/...); colors follow the EdgeTX theme.
- **BattCfg** widget: battery config on the home screen with a full-screen
  touch editor (LiPo/Li-Ion profile, capacity +/-50 and quick picks, SAVE).
- **Battery Config** tool (`SYS > Tools`): the same editor, opens full-screen
  with touch working immediately.
- **Battery+** page for the Betaflight TX Lua scripts: LiPo/Li-Ion profile
  switch with manual capacity.
- Unified "connect FC" state across both widgets when telemetry is down.
