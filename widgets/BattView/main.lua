--------------------------------------------------------------------------------
-- BattView  -  EdgeTX widget: LIVE battery data from telemetry
--   Voltage + cell count (auto), volts/cell, a colored charge gauge,
--   current (A) and consumption (mAh) when those sensors are available.
--   Colors follow the active THEME (dark/light): the background shows through
--   and the text uses the theme color. Semantic colors (green/yellow/red) stay.
--   No MSP - pure telemetry via getValue(). Works on CRSF/ELRS and SmartPort.
--------------------------------------------------------------------------------

-- candidate sensor names (auto-detection)
local V_NAMES   = { "RxBt", "VFAS", "Vbat", "VBat", "Batt", "Bat", "A4", "Volt", "RXBt", "RxBt+" }
local CUR_NAMES = { "Curr", "Cur" }
local CAP_NAMES = { "Capa", "Fuel", "mAh" }
local PCT_NAMES = { "Bat%", "Bat", "Rem" }

-- colors: text from the theme (adaptive), battery state semantic
local T, ready = {}, false
local function initColors()
    if ready then return end
    local function rgb(r, g, b) if lcd.RGB then return lcd.RGB(r, g, b) end return 0 end
    T.text   = COLOR_THEME_PRIMARY1 or WHITE   -- adapts: dark on a light theme, light on a dark theme
    T.track  = COLOR_THEME_SECONDARY1 or GREY  -- gauge background
    T.green  = rgb(60, 200, 90)
    T.yellow = rgb(240, 190, 60)
    T.red    = rgb(235, 80, 70)
    ready = true
end
local function battColor(pc)
    if pc >= 3.80 then return T.green
    elseif pc >= 3.50 then return T.yellow
    else return T.red end
end

local function sensorExists(n)
    if getFieldInfo and getFieldInfo(n) then return true end
    local v = getValue(n)
    return type(v) == "number" and v ~= 0
end
local function resolveName(list)
    for _, n in ipairs(list) do if sensorExists(n) then return n end end
    return nil
end
local function readSensor(name)
    if not name then return nil end
    local v = getValue(name)
    if type(v) == "number" then return v end
    return nil
end
local function guessCells(v)
    if v <= 0 then return 1 end
    return math.max(1, math.min(12, math.floor(v / 4.35) + 1))
end
local function txtSize(s, flags, fb)
    if lcd.sizeText then local w, h = lcd.sizeText(s, flags); return w or 0, (h and h > 0) and h or fb end
    return #s * 8, fb
end

local function create(zone, options)
    return { zone = zone, options = options, cells = 0,
             vName = nil, curName = nil, capName = nil, pctName = nil, lastScan = 0 }
end
local function update(self, options) self.options = options end

local function scan(self)
    local t = getTime()
    if self.vName and (t - self.lastScan) < 300 then return end
    self.lastScan = t
    self.vName   = self.vName   or resolveName(V_NAMES)
    self.curName = self.curName or resolveName(CUR_NAMES)
    self.capName = self.capName or resolveName(CAP_NAMES)
    self.pctName = self.pctName or resolveName(PCT_NAMES)
end

local function refresh(self, event, touchState)
    initColors()
    local z = self.zone
    local x, r = z.x + 4, z.x + z.w - 4
    -- NO background fill -> the theme background (dark/light) shows through
    scan(self)

    local v
    if self.options and self.options.Battery and self.options.Battery ~= 0 then
        v = readSensor(self.options.Battery)
    else
        v = readSensor(self.vName)
    end

    if getRSSI() == 0 then
        lcd.drawText(x, z.y + 6, "BattView: connect FC", T.text + SMLSIZE)
        return
    end
    if not v then
        lcd.drawText(x, z.y + 6, "BattView: no V sensor", T.text + SMLSIZE)
        return
    end

    -- cell count (auto with a latch, or forced via options)
    if v < 1 then self.cells = 0 else
        local c = guessCells(v); if c > self.cells then self.cells = c end
    end
    local cells = (self.options and self.options.Cells and self.options.Cells > 0)
        and self.options.Cells or math.max(1, self.cells)
    local perCell = v / cells
    local minC = ((self.options and self.options.MinCell) or 33) / 10
    local maxC = ((self.options and self.options.MaxCell) or 42) / 10
    local frac = (perCell - minC) / (maxC - minC)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local cc = battColor(perCell)

    local cur = readSensor(self.curName)
    local cap = readSensor(self.capName)
    local pct = readSensor(self.pctName)
    local haveExtras = (cur and cur > 0) or (cap and cap > 0)

    -- ---- vertical layout that uses the zone height ----
    -- cell count and % are RIGHT-aligned (no width measuring -> no overlap)
    local vFlags = MIDSIZE
    local availH = z.h
    -- the content is 4 logical rows; the gap scales with the available height
    local gap = math.max(2, math.floor((availH - 80) / 6))
    if gap > 14 then gap = 14 end
    local y = z.y + 3

    -- row 1: voltage (left)  +  cell count (right)
    local vTxt = string.format("%.1fV", v)
    lcd.drawText(x, y, vTxt, cc + vFlags + BOLD)
    lcd.drawText(r, y + 2, string.format("%dS", cells), T.text + MIDSIZE + RIGHT)
    local _, vh = txtSize(vTxt, vFlags, 22)
    y = y + vh + gap

    -- row 2: volts/cell (left)  +  percent (right, if present)
    local pcTxt = string.format("%.2f V/cell", perCell)
    lcd.drawText(x, y, pcTxt, T.text + MIDSIZE)
    if pct and pct > 0 then
        lcd.drawText(r, y, string.format("%d%%", math.floor(pct + 0.5)), T.text + MIDSIZE + RIGHT)
    end
    local _, ph = txtSize(pcTxt, MIDSIZE, 16)
    y = y + ph + gap

    -- row 3: charge gauge (height scales with the free space)
    local bottomNeed = haveExtras and 16 or 2
    local room = (z.y + z.h) - y - bottomNeed
    if room >= 8 then
        local gh = math.max(8, math.min(22, room - gap))
        local gw = r - x
        lcd.drawFilledRectangle(x, y, gw, gh, T.track)
        lcd.drawFilledRectangle(x, y, math.floor(gw * frac), gh, cc)
        lcd.drawRectangle(x, y, gw, gh, T.text)
        y = y + gh + gap
    end

    -- row 4: current + consumption (if present and there is room)
    if haveExtras and (z.y + z.h) - y >= 11 then
        local parts = {}
        if cur and cur > 0 then parts[#parts + 1] = string.format("%.1fA", cur) end
        if cap and cap > 0 then parts[#parts + 1] = string.format("%dmAh", math.floor(cap + 0.5)) end
        lcd.drawText(x, y, table.concat(parts, "   "), T.text + SMLSIZE)
    end
end

return {
    name = "BattView",
    options = {
        { "Battery", SOURCE, 0 },         -- optional: pick the voltage sensor (0 = auto)
        { "Cells",   VALUE, 0, 0, 12 },   -- 0 = auto-detect
        { "MinCell", VALUE, 33, 25, 42 }, -- tenths of a volt: empty gauge (3.3V)
        { "MaxCell", VALUE, 42, 38, 44 }, -- tenths of a volt: full gauge (4.2V)
    },
    create = create,
    update = update,
    refresh = refresh,
}
