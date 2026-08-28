# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lua add-ons for **Betaflight battery configuration** on color/touchscreen **EdgeTX** radios
(developed and tested on a RadioMaster TX15). Four independent deliverables — a user installs
only the ones they want, each to a fixed path on the radio's SD card:

| Source | SD card destination | Type | Needs `/SCRIPTS/BF/`? |
|--------|--------------------|------|-----------------------|
| `widgets/BattView/main.lua` | `WIDGETS/BattView/main.lua` | Home-screen widget, live telemetry | No |
| `widgets/BattCfg/main.lua` | `WIDGETS/BattCfg/main.lua` | Home-screen widget + full-screen editor | Yes |
| `tools/battcfg.lua` | `SCRIPTS/TOOLS/battcfg.lua` | `SYS > Tools` full-screen editor | Yes |
| `bf-page/battery2.lua` | `SCRIPTS/BF/PAGES/battery2.lua` | Extra page inside the BF Lua scripts | Yes (it *is* a BF page) |

The `bf-page/` folder also ships patched copies of three upstream loader files
(`pages.lua`, `scripts.lua`, `scripts_compiled.lua`) — see "The Battery+ page" below.

## No build / test / lint tooling

These are plain Lua scripts loaded directly by EdgeTX's embedded interpreter. There is no
package manager, build step, or test suite, and no CI.

- **Syntax check** (catches parse errors only; EdgeTX API globals will read as undefined):
  ```bash
  luac -p tools/battcfg.lua
  ```
  or, if installed, `luacheck --globals lcd getValue getFieldInfo getRSSI getTime loadScript -- tools/battcfg.lua`
- **Real testing** happens on hardware or in the **EdgeTX Companion simulator**: copy the file
  to the matching SD-card path above, restart the radio / reload the widget, and drive it with
  a connected (or simulated) flight controller. Writes to the FC only work while **disarmed**.
- `.png` files under `docs/` are README screenshots, not test fixtures.

## Architecture

### Two families

1. **Telemetry-only — `BattView`.** Pure `getValue()` / `getFieldInfo()` reads, no MSP, no
   dependency on the BF Lua scripts. Auto-detects the voltage sensor by trying a list of
   candidate names (`RxBt`, `VFAS`, …), latches the highest cell count it has seen, and draws
   a theme-adaptive gauge. Works on CRSF/ELRS and SmartPort.

2. **MSP-based — `BattCfg` widget, `battcfg.lua` tool, `battery2.lua` page.** These read and
   write Betaflight's battery config over MSP. The widget and the tool **bootstrap the BF MSP
   layer at runtime** by `loadScript`-ing files out of `/SCRIPTS/BF/` (`protocols.lua`, the
   transport named by `protocol.mspTransport`, `MSP/common.lua`), so `/SCRIPTS/BF/` must exist
   on the SD card. `battery2.lua` instead runs *inside* that project and uses its page framework.

### MSP battery-config protocol (shared by all three MSP scripts)

- Command IDs: `MSP_READ = 32`, `MSP_WRITE = 33`, `MSP_EEPROM = 250`, `MSP_REBOOT = 68`.
- 13-byte payload, 1-indexed. Full layout is documented in the header of
  [`bf-page/battery2.lua`](bf-page/battery2.lua). Key offsets: `4,5` capacity (uint16 mAh);
  `8,9` / `10,11` / `12,13` min / max / warning cell voltage (uint16, 0.01 V); `1,2,3` legacy
  0.1 V copies that must be kept consistent with the centivolt values.
- Save sequence: `MSP_WRITE` → on reply `MSP_READ`(EEPROM) → on reply `MSP_READ`(REBOOT).
  The FC reboot (v1.0.2) is deliberate: it makes cell-count re-detection for the low-voltage
  warning take effect without unplugging the battery. Widgets show "connect FC" during the
  few-second link drop, then re-read.

### Staging model (BattCfg widget + battcfg tool)

All edits — tapping a profile, `-50` / `+50`, a capacity quick-pick — only **stage** bytes
into the working buffer (`raw` / `S.raw`) and set a `dirty` flag. Nothing is sent to the FC
until **SAVE**. The SAVE button turns amber and shows `SAVE *` while dirty. Leaving the editor
(`EVT_VIRTUAL_EXIT` / returning to the home zone) calls `discard()` and forces a fresh re-read,
so unsaved edits are dropped. Treat profile + capacity as one atomic package.

### Duplicated code — keep the copies in sync by hand

`tools/battcfg.lua` and `widgets/BattCfg/main.lua` are near-identical: the same `profileName` /
`presets` / `capPresets` tables, MSP constants, byte helpers (`rd16`, `parseCfg`,
`detectProfile`, `setV`, `applyProfileToBytes`, `setCapacity`), drawing helpers (`btn`,
`covers`, `vctr`), `layout()`, and full-screen event handling. There is **no shared module** —
a change to the editor logic or the profile tables usually has to be made in **both** files
(and often mirrored in `bf-page/battery2.lua`, which reimplements the same idea on the BF page
framework).

### Profile tables

Defaults live in a `presets` table near the top of each file and are meant to be user-edited:

- LiPo `3.30 / 3.50 / 4.30`, Li-Ion `3.00 / 3.30 / 4.20`, LiHV `3.30 / 3.50 / 4.35` (V/cell:
  min / warn / max).
- Capacity quick-picks: `8400 / 4000 / 3300 / 1550 / 1480` mAh, step 50.
- **Inconsistency to be aware of:** `battcfg.lua` and `BattCfg/main.lua` have all three
  chemistries and auto-detect as `maxV >= 4.33 → LiHV`, `minV <= 3.15 → Li-Ion`, else LiPo.
  `bf-page/battery2.lua` only has **LiPo / Li-Ion** and detects `minV <= 3.15 → Li-Ion` else
  LiPo. Adding LiHV there means extending `profileTable`, `presets`, the field `max`, and
  `postLoad`.

### The Battery+ page and its patched loaders

`bf-page/pages.lua` and `bf-page/scripts.lua` are **modified copies of upstream
betaflight-tx-lua-scripts files**, each with a single line added to register `battery2.lua`
(`pages.lua` ~line 48, `scripts.lua` ~line 42). `bf-page/scripts_compiled.lua` is just
`return false`, which forces the BF tool to recompile once so the new page is picked up
(alternative: delete all `*.luac` under `SCRIPTS/BF/`). If upstream changes these loaders,
re-apply the one-line additions on top of the new versions rather than shipping stale copies.

`battery2.lua` adds a **virtual byte 14** to the payload to remember the chosen chemistry; the
FC ignores it on write (frames are masked to `0xFF` per byte on send). Profile changes are
applied in `postEdit` only when the selection actually changed, guarded by
`self.appliedProfile`, so manually tuned voltages are not clobbered by stray input.

### Screen coordinates

`layout()` uses absolute pixel positions tuned for ~320×480 EdgeTX color screens (`LCD_W`,
`LCD_H`). Ported layouts for other resolutions would need those constants revisited.

## Releasing

`VERSION` is a hardcoded string in `tools/battcfg.lua` and `widgets/BattCfg/main.lua`
(currently `v1.0.2`). On a release, bump it in every file that has it and add a section to
[`CHANGELOG.md`](CHANGELOG.md). `README.md`'s install steps and the profile/capacity defaults
table should match the code.

## Repository workflow

GPL-3.0 (the MSP-based scripts are derivative works of betaflight-tx-lua-scripts; see
[`NOTICE.md`](NOTICE.md)). `origin` is `github.com/TiGRiceK55/bf-battery-tools-edgetx`. History
before this point was made by uploading files through the GitHub web UI ("Add files via
upload" commits); normal branch + commit + PR flow applies from here.
