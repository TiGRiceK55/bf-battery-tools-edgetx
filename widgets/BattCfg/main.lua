--------------------------------------------------------------------------------
-- BattCfg  -  EdgeTX widget for quick battery setup changes in Betaflight
--             (RadioMaster TX15 and other color touch radios)
--
--  Home screen (small zone):  profile + voltages (min/warn/max) + capacity.
--  Full-screen (hold finger -> Full screen):  large TOUCH buttons
--      [ LiPo ] [ Li-Ion ]            -> one tap = profile + save to FC
--      capacity  [ -50 ]  mAh  [ +50 ]
--      quick picks:  [8400][4000][3300][1550][1480]  -> set capacity
--      [ SAVE ]                        -> save capacity to the FC
--  Also works with the rotary/ENTER.  No FC reboot.  Write only while disarmed.
--  Reuses the proven MSP layer from /SCRIPTS/BF.
--------------------------------------------------------------------------------

local BF = "/SCRIPTS/BF/"
local VERSION = "v1.0.1"

-- ---- profiles (V per cell) + capacity quick picks (edit to taste) -----------
local profileName = { [1] = "LiPo", [2] = "Li-Ion" }
local presets = {
    [1] = { min = 3.30, warn = 3.50, max = 4.30 }, -- LiPo
    [2] = { min = 3.00, warn = 3.30, max = 4.20 }, -- Li-Ion
}
local capPresets = { 8400, 4000, 3300, 1550, 1480 } -- mAh
local CAP_STEP = 50

-- ---- MSP constants ----------------------------------------------------------
local MSP_READ, MSP_WRITE, MSP_EEPROM = 32, 33, 250

-- ---- custom color scheme (high contrast, theme-independent) -----------------
local COL, colorsReady = {}, false
local function initColors()
    if colorsReady then return end
    local function rgb(r, g, b) if lcd.RGB then return lcd.RGB(r, g, b) end return 0 end
    COL.panel  = rgb(20, 24, 34)   -- dark panel (background)
    COL.bar    = rgb(38, 46, 64)   -- title bar / value box
    COL.btn    = rgb(58, 66, 88)   -- inactive button
    COL.act    = rgb(0, 150, 70)   -- active profile (green)
    COL.preset = rgb(40, 92, 150)  -- quick-pick buttons (blue)
    COL.focus  = rgb(95, 165, 245) -- focus outline
    COL.white  = rgb(255, 255, 255)
    COL.dim    = rgb(178, 188, 205)
    COL.val    = rgb(120, 205, 255) -- bright value (capacity)
    -- adaptive theme colors (for the home-screen zone): dark text on a light theme,
    -- light on a dark theme. The zone background is not filled -> the theme shows through.
    COL.themeTxt = COLOR_THEME_PRIMARY1 or rgb(255, 255, 255)
    colorsReady = true
end

--------------------------------------------------------------------------------
-- Bootstrap the MSP layer
--------------------------------------------------------------------------------
local inited = false
local function bootstrap()
    protocol = assert(loadScript(BF .. "protocols.lua"))()
    assert(loadScript(BF .. protocol.mspTransport))()
    assert(loadScript(BF .. "MSP/common.lua"))()
    return true
end

--------------------------------------------------------------------------------
-- Battery config bytes
--------------------------------------------------------------------------------
local function rd16(b, lo, hi) return (b[lo] or 0) + (b[hi] or 0) * 256 end
local function parseCfg(b)
    return { capacity = rd16(b, 4, 5), minV = rd16(b, 8, 9) / 100,
             maxV = rd16(b, 10, 11) / 100, warnV = rd16(b, 12, 13) / 100 }
end
local function detectProfile(c) if c.minV <= 3.15 then return 2 end return 1 end
local function setV(b, lo, hi, v) local cv = math.floor(v * 100 + 0.5); b[lo] = cv % 256; b[hi] = math.floor(cv / 256) % 256 end
local function applyProfileToBytes(b, p)
    local pr = presets[p]; if not pr then return end
    setV(b, 8, 9, pr.min); setV(b, 10, 11, pr.max); setV(b, 12, 13, pr.warn)
    b[1] = math.floor(pr.min * 10 + 0.5) % 256
    b[2] = math.floor(pr.max * 10 + 0.5) % 256
    b[3] = math.floor(pr.warn * 10 + 0.5) % 256
end
local function setCapacity(b, m)
    if m < 0 then m = 0 elseif m > 20000 then m = 20000 end
    b[4] = m % 256; b[5] = math.floor(m / 256) % 256
end

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------
local function covers(ts, x, y, w, h)
    return ts and ts.x and ts.x >= x and ts.x <= x + w and ts.y >= y and ts.y <= y + h
end
local function vctr(size)   -- vertical centering based on font size
    if size == DBLSIZE then return 16 elseif size == MIDSIZE then return 11 else return 8 end
end
local function btn(x, y, w, h, text, bg, focused, size)
    size = size or MIDSIZE
    lcd.drawFilledRectangle(x, y, w, h, bg)
    if focused then lcd.drawRectangle(x, y, w, h, COL.focus, 3) end
    lcd.drawText(x + w / 2, y + h / 2 - vctr(size), text, COL.white + CENTER + BOLD + size)
end

--------------------------------------------------------------------------------
-- Widget lifecycle
--------------------------------------------------------------------------------
local function create(zone, options)
    return { zone = zone, options = options, state = "idle", ts = 0,
             cfg = nil, raw = nil, profile = 1, focus = 1, status = "" }
end
local function update(self, options) self.options = options end

local function startRead(self)
    if self.state == "idle" then protocol.mspRead(MSP_READ); self.state = "read"; self.ts = getTime() end
end
local function startWrite(self)
    if self.state == "idle" and self.raw then
        protocol.mspWrite(MSP_WRITE, self.raw); self.state = "write"; self.ts = getTime(); self.status = "Saving..."
    end
end
local function applyAndSave(self, prof)
    if not self.raw then return end
    self.profile = prof; applyProfileToBytes(self.raw, prof); self.cfg = parseCfg(self.raw); startWrite(self)
end
local function changeCapacity(self, delta)
    if not self.raw then return end
    setCapacity(self.raw, rd16(self.raw, 4, 5) + delta); self.cfg = parseCfg(self.raw)
end
local function setCapVal(self, v)
    if not self.raw then return end
    setCapacity(self.raw, v); self.cfg = parseCfg(self.raw)
end

local function pumpMsp(self)
    mspProcessTxQ()
    local cmd, buf = mspPollReply()
    if cmd == MSP_READ and buf and #buf >= 13 then
        self.raw = {}; for i = 1, 13 do self.raw[i] = buf[i] or 0 end
        self.cfg = parseCfg(self.raw); self.profile = detectProfile(self.cfg); self.state = "idle"
    elseif cmd == MSP_WRITE then
        protocol.mspRead(MSP_EEPROM); self.state = "eeprom"; self.ts = getTime()
    elseif cmd == MSP_EEPROM then
        self.state = "idle"; self.status = "Saved - replug battery"; startRead(self)
    end
    if self.state ~= "idle" and (self.ts + 200 < getTime()) then
        self.state = "idle"; if self.status == "Saving..." then self.status = "Timeout" end
    end
end

--------------------------------------------------------------------------------
-- Small home-screen zone (display only, theme-adaptive text, no background fill)
--------------------------------------------------------------------------------
local function drawZone(self)
    local z = self.zone
    local x = z.x + 6
    local TX = COL.themeTxt   -- theme-adaptive text color
    -- NO background fill -> the system theme background (dark/light) shows through
    if not self.cfg then
        lcd.drawText(x, z.y + 6, "BattCfg: connect FC", TX + SMLSIZE)
        return
    end
    local minV, warnV, maxV, cap = self.cfg.minV, self.cfg.warnV, self.cfg.maxV, self.cfg.capacity

    -- very short zone: 2 compact lines
    if z.h < 92 then
        lcd.drawText(x, z.y + 2, profileName[self.profile] .. "  " .. cap .. "mAh", TX + SMLSIZE + BOLD)
        lcd.drawText(x, z.y + z.h - 14,
            string.format("%.2f / %.2f / %.2f", minV, warnV, maxV), TX + SMLSIZE)
        return
    end

    -- standard (e.g. 1/4 of the screen): vertical stacking without overlap.
    -- We MEASURE the profile height (lcd.sizeText) so capacity never lands "inside" it.
    local profSize = MIDSIZE   -- smaller than DBLSIZE, fits better
    local pTxt = profileName[self.profile]
    lcd.drawText(x, z.y + 4, pTxt, TX + profSize + BOLD)
    local ph = 24
    if lcd.sizeText then local _, h = lcd.sizeText(pTxt, profSize); if h and h > 0 then ph = h end end

    -- 2) capacity - right below the measured profile height (+ gap)
    local yCap = z.y + 4 + ph + 8
    lcd.drawText(x, yCap, string.format("%d mAh", cap), TX + MIDSIZE)

    -- 3) min / warn / max - at the bottom, in three columns
    local valFont = (z.w >= 200) and MIDSIZE or 0
    local yVal = z.y + z.h - ((valFont == MIDSIZE) and 24 or 16)
    local yLab = yVal - 13
    local cx  = { z.x + z.w * 0.06, z.x + z.w * 0.40, z.x + z.w * 0.72 }
    local lab = { "min", "warn", "max" }
    local val = { minV, warnV, maxV }
    for i = 1, 3 do
        lcd.drawText(cx[i], yLab, lab[i], TX + SMLSIZE)
        lcd.drawText(cx[i], yVal, string.format("%.2f", val[i]), TX + valFont)
    end
end

--------------------------------------------------------------------------------
-- Full-screen control (after holding the widget -> Full screen)
--------------------------------------------------------------------------------
local function layout()
    local m, W = 8, LCD_W
    local bw = (W - m * 3) / 2
    local L = {
        lipo  = { x = m, y = 38, w = bw, h = 48 },
        liion = { x = m * 2 + bw, y = 38, w = bw, h = 48 },
        volts = { x = m, y = 92 },
        capM  = { x = m, y = 138, w = 74, h = 46 },
        capV  = { x = m + 82, y = 138, w = W - 2 * m - 2 * 74 - 16, h = 46 },
        capP  = { x = W - m - 74, y = 138, w = 74, h = 46 },
        save  = { x = m, y = 246, w = W - 2 * m, h = 50 },
        presets = {},
    }
    local n = #capPresets
    local gap = 6
    local pw = (W - 2 * m - gap * (n - 1)) / n
    for i = 1, n do
        L.presets[i] = { x = m + (i - 1) * (pw + gap), y = 194, w = pw, h = 44 }
    end
    return L
end

-- activate the control by focus index (for rotary/ENTER)
local function activate(self, idx)
    local n = #capPresets
    if idx == 1 then applyAndSave(self, 1)
    elseif idx == 2 then applyAndSave(self, 2)
    elseif idx == 3 then changeCapacity(self, -CAP_STEP)
    elseif idx == 4 then changeCapacity(self, CAP_STEP)
    elseif idx >= 5 and idx <= 4 + n then setCapVal(self, capPresets[idx - 4])
    elseif idx == 5 + n then startWrite(self)
    end
end

local function drawFull(self, event, ts)
    local L = layout()
    local n = #capPresets
    lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COL.panel)
    lcd.drawFilledRectangle(0, 0, LCD_W, 30, COL.bar)
    lcd.drawText(8, 4, "Battery Config", COL.white + MIDSIZE)
    lcd.drawText(LCD_W - 8, 7, VERSION, COL.dim + SMLSIZE + RIGHT)

    if not self.cfg then
        lcd.drawText(LCD_W / 2, LCD_H / 2 - 10, "Connecting to FC...", COL.dim + MIDSIZE + CENTER)
        lcd.drawText(8, LCD_H - 24, self.status, COL.dim + SMLSIZE)
        return
    end

    btn(L.lipo.x, L.lipo.y, L.lipo.w, L.lipo.h, "LiPo",
        self.profile == 1 and COL.act or COL.btn, self.focus == 1)
    btn(L.liion.x, L.liion.y, L.liion.w, L.liion.h, "Li-Ion",
        self.profile == 2 and COL.act or COL.btn, self.focus == 2)

    lcd.drawText(L.volts.x, L.volts.y,
        string.format("min %.2f V    warn %.2f V    max %.2f V",
            self.cfg.minV, self.cfg.warnV, self.cfg.maxV), COL.white + MIDSIZE)

    lcd.drawText(L.capM.x, L.capM.y - 18, "Capacity (mAh)", COL.dim + SMLSIZE)
    btn(L.capM.x, L.capM.y, L.capM.w, L.capM.h, "-50", COL.btn, self.focus == 3)
    lcd.drawFilledRectangle(L.capV.x, L.capV.y, L.capV.w, L.capV.h, COL.bar)
    lcd.drawText(L.capV.x + L.capV.w / 2, L.capV.y + 8,
        string.format("%d", self.cfg.capacity), COL.val + DBLSIZE + CENTER)
    btn(L.capP.x, L.capP.y, L.capP.w, L.capP.h, "+50", COL.btn, self.focus == 4)

    for i = 1, n do
        local p = L.presets[i]
        btn(p.x, p.y, p.w, p.h, tostring(capPresets[i]),
            (self.cfg.capacity == capPresets[i]) and COL.act or COL.preset,
            self.focus == 4 + i, 0)
    end

    btn(L.save.x, L.save.y, L.save.w, L.save.h, "SAVE", COL.preset, self.focus == 5 + n)
    lcd.drawText(8, LCD_H - 22, self.status, COL.dim + SMLSIZE)

    -- TOUCH
    if event == EVT_TOUCH_TAP and ts then
        if covers(ts, L.lipo.x, L.lipo.y, L.lipo.w, L.lipo.h) then applyAndSave(self, 1)
        elseif covers(ts, L.liion.x, L.liion.y, L.liion.w, L.liion.h) then applyAndSave(self, 2)
        elseif covers(ts, L.capM.x, L.capM.y, L.capM.w, L.capM.h) then changeCapacity(self, -CAP_STEP)
        elseif covers(ts, L.capP.x, L.capP.y, L.capP.w, L.capP.h) then changeCapacity(self, CAP_STEP)
        elseif covers(ts, L.save.x, L.save.y, L.save.w, L.save.h) then startWrite(self)
        else
            for i = 1, n do
                local p = L.presets[i]
                if covers(ts, p.x, p.y, p.w, p.h) then setCapVal(self, capPresets[i]); break end
            end
        end
    -- KEYS / ROTARY
    elseif event == EVT_VIRTUAL_NEXT then
        self.focus = self.focus % (5 + n) + 1
    elseif event == EVT_VIRTUAL_PREV then
        self.focus = (self.focus + 3 + n) % (5 + n) + 1
    elseif event == EVT_VIRTUAL_ENTER then
        activate(self, self.focus)
    elseif event == EVT_VIRTUAL_EXIT then
        lcd.exitFullScreen()
    end
end

--------------------------------------------------------------------------------
local function refresh(self, event, touchState)
    initColors()
    local z = self.zone
    -- no telemetry -> "connect FC" mode (like BattView), even after a mid-session
    -- disconnect; we never show stale values when the link is down
    if getRSSI() == 0 then
        if event == nil then
            lcd.drawText(z.x + 6, z.y + 6, "BattCfg: connect FC", COL.themeTxt + SMLSIZE)
        else
            lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COL.panel)
            lcd.drawText(LCD_W / 2, LCD_H / 2, "BattCfg: connect FC", COL.dim + MIDSIZE + CENTER)
        end
        return
    end

    if not inited then
        inited = pcall(bootstrap)
        if not inited then return end
    end

    pumpMsp(self)
    if not self.cfg and self.state == "idle" then startRead(self) end

    if event == nil then drawZone(self) else drawFull(self, event, touchState) end
end

return { name = "BattCfg", options = {}, create = create, update = update, refresh = refresh }
