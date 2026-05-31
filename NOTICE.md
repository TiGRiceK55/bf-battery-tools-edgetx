# Notices

This project includes a page (`bf-page/battery2.lua`) and patched loader files
(`pages.lua`, `scripts.lua`, `scripts_compiled.lua`) that are derived from and
designed to run inside the Betaflight TX Lua Scripts:

  https://github.com/betaflight/betaflight-tx-lua-scripts  (GPL-3.0)

The `pages.lua` and `scripts.lua` files are modified copies of the originals
from that project, with one line added each to register the Battery+ page.
Original copyright belongs to the Betaflight project and contributors.

The widgets (`widgets/BattCfg`, `widgets/BattView`) and the tool
(`tools/battcfg.lua`) are original works; `BattCfg`/`battcfg.lua` load the
Betaflight MSP layer at runtime and are therefore distributed under the same
license for clarity.
