# Changelog

## v1.0.2
- Battery Config now treats all settings as one package: selecting a profile no
  longer saves immediately. Profile (LiPo/Li-Ion/LiHV) and capacity are staged,
  the SAVE button shows "SAVE *" while there are unsaved changes, and SAVE writes
  everything at once. Leaving the editor without saving discards staged changes.
- After SAVE the FC reboots automatically, so settings apply without unplugging
  and replugging the battery.
- Added a LiHV profile (3.30 / 3.50 / 4.35 V/cell) to the widget, the tool and
  the Battery+ page. Profile auto-detection now recognises LiHV by max cell voltage.

## v1.0.1
- Config tools now show "Saved - replug battery"; the README explains why a
  battery replug is recommended after changing the profile (cell count is
  detected at battery connect and the tools do not reboot the FC).
- Unified "connect FC" state across both widgets when telemetry is down.
- The full-screen Battery Config screen now shows the version number.

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
