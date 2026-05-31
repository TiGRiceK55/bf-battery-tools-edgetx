--------------------------------------------------------------------------------
-- Battery+  (battery2.lua)
--
-- Extended version of the stock "Battery" page for the Betaflight TX Lua scripts.
--  * shows the current battery setup from the FC (same format as "Battery")
--  * lets you switch chemistry profile:  LiPo  <->  Li-Ion
--      - switching the profile auto-fills the per-cell voltages
--  * battery capacity stays user-editable (the profile never touches it)
--
-- MSP:  MSP_BATTERY_CONFIG (32) / MSP_SET_BATTERY_CONFIG (33)
-- Payload layout (1-indexed, same as stock battery.lua):
--   1     legacy min cell        (0.1 V)
--   2     legacy max cell        (0.1 V)
--   3     legacy warning cell    (0.1 V)
--   4,5   battery capacity       (mAh, uint16)
--   6     voltage meter source
--   7     current meter source
--   8,9   min cell voltage       (0.01 V, uint16)
--   10,11 max cell voltage       (0.01 V, uint16)
--   12,13 warning cell voltage   (0.01 V, uint16)
--   14    << chemistry profile >>  (EXTRA byte, the FC ignores it on write)
--------------------------------------------------------------------------------

local template = assert(loadScript(radio.template))()
local margin = template.margin
local indent = template.indent
local lineSpacing = template.lineSpacing
local tableSpacing = template.tableSpacing
local sp = template.listSpacing.field
local yMinLim = radio.yMinLimit
local x = margin
local y = yMinLim - lineSpacing
local inc = { x = function(val) x = x + val return x end, y = function(val) y = y + val return y end }
local labels = {}
local fields = {}

--------------------------------------------------------------------------------
-- PROFILE CONFIGURATION  (feel free to tweak these values to taste)
-- voltages are in Volts per cell
--------------------------------------------------------------------------------
local profileTable = { [1] = "LiPo", [2] = "Li-Ion" }

local presets = {
    [1] = { min = 3.30, warn = 3.50, max = 4.30 },  -- LiPo
    [2] = { min = 3.00, warn = 3.30, max = 4.20 },  -- Li-Ion
}

local PROFILE_BYTE = 14   -- virtual byte used to store the selected profile

--------------------------------------------------------------------------------
-- Page fields
--------------------------------------------------------------------------------
labels[#labels + 1] = { t = "Battery Profile", x = x,          y = inc.y(lineSpacing) }
fields[#fields + 1] = { t = "Chemistry",       x = x + indent, y = inc.y(lineSpacing), sp = x + sp, min = 1, max = 2, vals = { PROFILE_BYTE }, table = profileTable }
local F_PROFILE = #fields

labels[#labels + 1] = { t = "Voltage / Cell",  x = x,          y = inc.y(lineSpacing) }
fields[#fields + 1] = { t = "Minimum",         x = x + indent, y = inc.y(lineSpacing), sp = x + sp, min = 0, max = 500, vals = { 8, 9 },   scale = 100 }
local F_MIN = #fields
fields[#fields + 1] = { t = "Warning",         x = x + indent, y = inc.y(lineSpacing), sp = x + sp, min = 0, max = 500, vals = { 12, 13 }, scale = 100 }
local F_WARN = #fields
fields[#fields + 1] = { t = "Maximum",         x = x + indent, y = inc.y(lineSpacing), sp = x + sp, min = 0, max = 500, vals = { 10, 11 }, scale = 100 }
local F_MAX = #fields

labels[#labels + 1] = { t = "Capacity",        x = x,          y = inc.y(lineSpacing) }
fields[#fields + 1] = { t = "Battery mAh",     x = x + indent, y = inc.y(lineSpacing), sp = x + sp, min = 0, mult = 25, max = 20000, vals = { 4, 5 } }
local F_CAP = #fields

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

-- Write a voltage (V) into the given field and into the raw MSP bytes (centivolts).
-- Masking down to a byte happens only when the frame is sent (mspSendRequest -> band 0xFF),
-- exactly like the stock incValue in ui.lua does it.
local function applyVolts(self, field, volts)
    field.value = volts
    local scale = field.scale or 1
    local raw = math.floor(volts * scale + 0.5)
    for idx = 1, #field.vals do
        self.values[field.vals[idx]] = bit32.rshift(raw, (idx - 1) * 8)
    end
end

-- Apply a whole chemistry profile to the voltage fields (leaves capacity alone).
local function applyProfile(self, prof)
    local p = presets[prof]
    if not p then return end
    applyVolts(self, self.fields[F_MIN],  p.min)
    applyVolts(self, self.fields[F_WARN], p.warn)
    applyVolts(self, self.fields[F_MAX],  p.max)
    -- keep the legacy 0.1 V bytes consistent with the new mV values
    self.values[1] = math.floor(p.min  * 10 + 0.5)
    self.values[2] = math.floor(p.max  * 10 + 0.5)
    self.values[3] = math.floor(p.warn * 10 + 0.5)
    self.appliedProfile = prof
end

-- Apply the profile only when the user actually changes the selection (after leaving edit).
-- The appliedProfile guard prevents stray input from overwriting manually tuned
-- voltages when the profile did not really change.
fields[F_PROFILE].postEdit = function(self)
    local prof = self.values[PROFILE_BYTE]
    if prof ~= self.appliedProfile then
        applyProfile(self, prof)
    end
end

--------------------------------------------------------------------------------
-- Page definition
--------------------------------------------------------------------------------
return {
    read        = 32, -- MSP_BATTERY_CONFIG
    write       = 33, -- MSP_SET_BATTERY_CONFIG
    title       = "Battery+",
    reboot      = true,
    eepromWrite = true,
    minBytes    = 13,
    labels      = labels,
    fields      = fields,

    -- After loading from the FC: add the virtual profile byte and auto-detect
    -- the chemistry from the currently configured minimum cell voltage.
    postLoad = function(self)
        local minV = self.fields[F_MIN].value or 3.30
        local prof = 1                  -- LiPo
        if minV <= 3.15 then prof = 2 end  -- Li-Ion (low min voltage)
        self.values[PROFILE_BYTE] = prof
        self.fields[F_PROFILE].value = prof
        self.appliedProfile = prof
    end,
}
