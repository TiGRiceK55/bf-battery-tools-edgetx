-- TNS|Battery Config|TNE
--------------------------------------------------------------------------------
-- battcfg.lua  -  EdgeTX TOOL (SYS > Tools) for quick battery changes in BF
--   Opens straight to full screen, touch works IMMEDIATELY.
--   [ LiPo ] [ Li-Ion ]            -> one tap = profile + save to FC
--   capacity  [ -50 ]  mAh  [ +50 ]
--   quick picks:  [8400][4000][3300][1550][1480]  -> set capacity
--   [ SAVE ]                        -> save capacity to the FC
--   Also works with rotary/ENTER. A short RTN exits. No FC reboot.
--   Write only while disarmed. Reuses the proven MSP layer from /SCRIPTS/BF.
--------------------------------------------------------------------------------
local toolName = "TNS|Battery Config|TNE"
local BF = "/SCRIPTS/BF/"

local profileName = { [1] = "LiPo", [2] = "Li-Ion" }
local presets = {
    [1] = { min = 3.30, warn = 3.50, max = 4.30 }, -- LiPo
    [2] = { min = 3.00, warn = 3.30, max = 4.20 }, -- Li-Ion
}
local capPresets = { 8400, 4000, 3300, 1550, 1480 }
local CAP_STEP = 50

local MSP_READ, MSP_WRITE, MSP_EEPROM = 32, 33, 250

local COL, colorsReady = {}, false
local function initColors()
    if colorsReady then return end
    local function rgb(r, g, b) if lcd.RGB then return lcd.RGB(r, g, b) end return 0 end
    COL.panel  = rgb(20, 24, 34)
    COL.bar    = rgb(38, 46, 64)
    COL.btn    = rgb(58, 66, 88)
    COL.act    = rgb(0, 150, 70)
    COL.preset = rgb(40, 92, 150)
    COL.focus  = rgb(95, 165, 245)
    COL.white  = rgb(255, 255, 255)
    COL.dim    = rgb(178, 188, 205)
    COL.val    = rgb(120, 205, 255)
    colorsReady = true
end

local S = { state = "idle", ts = 0, cfg = nil, raw = nil, profile = 1, focus = 1, status = "" }
local inited = false

local function bootstrap()
    protocol = assert(loadScript(BF .. "protocols.lua"))()
    assert(loadScript(BF .. protocol.mspTransport))()
    assert(loadScript(BF .. "MSP/common.lua"))()
    return true
end

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

local function covers(ts, x, y, w, h)
    return ts and ts.x and ts.x >= x and ts.x <= x + w and ts.y >= y and ts.y <= y + h
end
local function vctr(size)
    if size == DBLSIZE then return 16 elseif size == MIDSIZE then return 11 else return 8 end
end
local function btn(x, y, w, h, text, bg, focused, size)
    size = size or MIDSIZE
    lcd.drawFilledRectangle(x, y, w, h, bg)
    if focused then lcd.drawRectangle(x, y, w, h, COL.focus, 3) end
    lcd.drawText(x + w / 2, y + h / 2 - vctr(size), text, COL.white + CENTER + BOLD + size)
end

local function startRead()
    if S.state == "idle" then protocol.mspRead(MSP_READ); S.state = "read"; S.ts = getTime() end
end
local function startWrite()
    if S.state == "idle" and S.raw then
        protocol.mspWrite(MSP_WRITE, S.raw); S.state = "write"; S.ts = getTime(); S.status = "Saving..."
    end
end
local function applyAndSave(prof)
    if not S.raw then return end
    S.profile = prof; applyProfileToBytes(S.raw, prof); S.cfg = parseCfg(S.raw); startWrite()
end
local function changeCapacity(delta)
    if not S.raw then return end
    setCapacity(S.raw, rd16(S.raw, 4, 5) + delta); S.cfg = parseCfg(S.raw)
end
local function setCapVal(v)
    if not S.raw then return end
    setCapacity(S.raw, v); S.cfg = parseCfg(S.raw)
end

local function pumpMsp()
    mspProcessTxQ()
    local cmd, buf = mspPollReply()
    if cmd == MSP_READ and buf and #buf >= 13 then
        S.raw = {}; for i = 1, 13 do S.raw[i] = buf[i] or 0 end
        S.cfg = parseCfg(S.raw); S.profile = detectProfile(S.cfg); S.state = "idle"
    elseif cmd == MSP_WRITE then
        protocol.mspRead(MSP_EEPROM); S.state = "eeprom"; S.ts = getTime()
    elseif cmd == MSP_EEPROM then
        S.state = "idle"; S.status = "Saved"; startRead()
    end
    if S.state ~= "idle" and (S.ts + 200 < getTime()) then
        S.state = "idle"; if S.status == "Saving..." then S.status = "Timeout" end
    end
end

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
    local n, gap = #capPresets, 6
    local pw = (W - 2 * m - gap * (n - 1)) / n
    for i = 1, n do L.presets[i] = { x = m + (i - 1) * (pw + gap), y = 194, w = pw, h = 44 } end
    return L
end

local function activate(idx)
    local n = #capPresets
    if idx == 1 then applyAndSave(1)
    elseif idx == 2 then applyAndSave(2)
    elseif idx == 3 then changeCapacity(-CAP_STEP)
    elseif idx == 4 then changeCapacity(CAP_STEP)
    elseif idx >= 5 and idx <= 4 + n then setCapVal(capPresets[idx - 4])
    elseif idx == 5 + n then startWrite()
    end
end

local function draw(event, ts)
    local L = layout()
    local n = #capPresets
    lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COL.panel)
    lcd.drawFilledRectangle(0, 0, LCD_W, 30, COL.bar)
    lcd.drawText(8, 4, "Battery Config", COL.white + MIDSIZE)

    if not S.cfg then
        lcd.drawText(LCD_W / 2, LCD_H / 2 - 10, "Connecting to FC...", COL.dim + MIDSIZE + CENTER)
        lcd.drawText(8, LCD_H - 24, S.status, COL.dim + SMLSIZE)
        return
    end

    btn(L.lipo.x, L.lipo.y, L.lipo.w, L.lipo.h, "LiPo", S.profile == 1 and COL.act or COL.btn, S.focus == 1)
    btn(L.liion.x, L.liion.y, L.liion.w, L.liion.h, "Li-Ion", S.profile == 2 and COL.act or COL.btn, S.focus == 2)

    lcd.drawText(L.volts.x, L.volts.y,
        string.format("min %.2f V    warn %.2f V    max %.2f V", S.cfg.minV, S.cfg.warnV, S.cfg.maxV),
        COL.white + MIDSIZE)

    lcd.drawText(L.capM.x, L.capM.y - 18, "Capacity (mAh)", COL.dim + SMLSIZE)
    btn(L.capM.x, L.capM.y, L.capM.w, L.capM.h, "-50", COL.btn, S.focus == 3)
    lcd.drawFilledRectangle(L.capV.x, L.capV.y, L.capV.w, L.capV.h, COL.bar)
    lcd.drawText(L.capV.x + L.capV.w / 2, L.capV.y + 8, string.format("%d", S.cfg.capacity), COL.val + DBLSIZE + CENTER)
    btn(L.capP.x, L.capP.y, L.capP.w, L.capP.h, "+50", COL.btn, S.focus == 4)

    for i = 1, n do
        local p = L.presets[i]
        btn(p.x, p.y, p.w, p.h, tostring(capPresets[i]),
            (S.cfg.capacity == capPresets[i]) and COL.act or COL.preset, S.focus == 4 + i, 0)
    end

    btn(L.save.x, L.save.y, L.save.w, L.save.h, "SAVE", COL.preset, S.focus == 5 + n)
    lcd.drawText(8, LCD_H - 22, S.status, COL.dim + SMLSIZE)

    if event == EVT_TOUCH_TAP and ts then
        if covers(ts, L.lipo.x, L.lipo.y, L.lipo.w, L.lipo.h) then applyAndSave(1)
        elseif covers(ts, L.liion.x, L.liion.y, L.liion.w, L.liion.h) then applyAndSave(2)
        elseif covers(ts, L.capM.x, L.capM.y, L.capM.w, L.capM.h) then changeCapacity(-CAP_STEP)
        elseif covers(ts, L.capP.x, L.capP.y, L.capP.w, L.capP.h) then changeCapacity(CAP_STEP)
        elseif covers(ts, L.save.x, L.save.y, L.save.w, L.save.h) then startWrite()
        else
            for i = 1, n do
                local p = L.presets[i]
                if covers(ts, p.x, p.y, p.w, p.h) then setCapVal(capPresets[i]); break end
            end
        end
    elseif event == EVT_VIRTUAL_NEXT then
        S.focus = S.focus % (5 + n) + 1
    elseif event == EVT_VIRTUAL_PREV then
        S.focus = (S.focus + 3 + n) % (5 + n) + 1
    elseif event == EVT_VIRTUAL_ENTER then
        activate(S.focus)
    end
end

local function run(event, touchState)
    initColors()
    lcd.clear()
    if not inited then
        if getRSSI() == 0 then
            lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COL.panel)
            lcd.drawText(LCD_W / 2, LCD_H / 2, "No telemetry / FC off", COL.dim + MIDSIZE + CENTER)
            if event == EVT_VIRTUAL_EXIT then return 1 end
            return 0
        end
        inited = pcall(bootstrap)
        if not inited then return 0 end
    end
    pumpMsp()
    if not S.cfg and S.state == "idle" then startRead() end
    draw(event, touchState)
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
end

return { run = run }
