-- HoA Better Gear - color the hero stats by how much they've grown this run.
--
-- On the character pane's stats panel (HoA's VanillaBonkHeroStats) and in
-- the live stats window, each value is colored like the gear upgrade %:
--   under 5% more than at the start of the run  white
--   5-15%                                        green
--   15-30%                                       blue
--   30% or more                                  purple
--   at its cap (Dodge 60%, Speed 50%, Armor 300, ...) orange - only when maxed
-- Outside a run, only Crit chance, Crit damage, Armor, Dodge and Speed are
-- colored, by their own value (see ValueColor below).
--
-- The starting point is what the panel last showed before the run (outside
-- a run), else the first values seen in the run. Runs start and end with
-- the server's BONK~start / BONK~end messages; BONK~stats~<1|0>~... also
-- says whether you're in a run.

local ns = HoABetterGear

-- HoA's panel order (VanillaBonk.lua STAT_LAYOUT): stat ids per line.
local PANEL_IDS = { 0, 1, 15, 16, 10, 18, 12, 14, 17, 4, 3, 8 }
-- HoA's hard caps (STATS[id].cap), used if a tooltip doesn't name one.
-- Armor (12) has no cap entry, but its damage reduction maxes out at 60%
-- at 300 Armor (HoA: min(0.6, armor / (armor * 4/3 + 100))); past 300 it
-- gives max health instead, so 300 counts as maxed.
local CAPS = { [2] = 5, [3] = 50, [8] = 400, [12] = 300, [14] = 60 }

local WHITE = { 1, 1, 1 }
local BANDS = {                  -- same as the gear upgrade colors
    { min = 5,  color = { 0.12, 1, 0 } },     -- uncommon
    { min = 15, color = { 0, 0.44, 0.87 } },  -- rare
    { min = 30, color = { 0.64, 0.21, 0.93 } }, -- epic (the most an uncapped stat gets)
}
local CAPPED = { 1, 0.5, 0 }     -- legendary orange: maxed

local inRun = false
local lastOutside      -- values seen outside a run: [key] = number
local elapsedSince = 0

local function Number(text)
    if type(text) ~= "string" then return nil end
    local clean = string.gsub(text, "[%%,%s]", "")
    return tonumber(clean)
end

-- A stable key for a panel line: HoA's stat id when the panel has its usual
-- 12 lines, else the label text.
local function LineKey(line, index, count)
    if count == 12 and PANEL_IDS[index] then return PANEL_IDS[index] end
    return line.label and line.label:GetText() or index
end

-- The cap HoA's tooltip states for this stat ("Maximum 60%."), else ours.
local function CapOf(line, key)
    if type(line.lines) == "table" then
        for _, text in ipairs(line.lines) do
            if type(text) == "string" then
                local _, _, n = string.find(text, "^Maximum ([%d%.]+)")
                if n then return tonumber(n) end
            end
        end
    end
    return CAPS[key]
end

local function Snapshot(lines, count)
    local values = {}
    for i, line in ipairs(lines) do
        local v = Number(line.value:GetText())
        if v then values[LineKey(line, i, count)] = v end
    end
    return values
end

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-------------------------------------------------------------------------------
-- Outside a run: a few stats colored by their own value
-------------------------------------------------------------------------------
-- Crit chance / damage: purple above 100%, orange from 200%.
-- Armor, Dodge, Speed: by how close they are to their cap - green from a
-- quarter of the way, blue from half, purple from three quarters, orange at
-- the cap (Armor 300, Dodge 60%, Speed 50%).
local GREEN, BLUE, PURPLE = BANDS[1].color, BANDS[2].color, BANDS[3].color
local CRIT = { [15] = true, [16] = true, ["Crit chance:"] = true, ["Crit damage:"] = true }
local TO_CAP = { [12] = 12, [14] = 14, [3] = 3, ["Armor:"] = 12, ["Dodge:"] = 14, ["Speed:"] = 3 }

local function ValueColor(line, key, now)
    if CRIT[key] then
        if now >= 200 then return CAPPED end
        if now > 100 then return PURPLE end
        return WHITE
    end
    local id = TO_CAP[key]
    if not id then return WHITE end
    local cap = CapOf(line, key) or CAPS[id]
    if not cap or cap <= 0 then return WHITE end
    local share = now / cap
    if share >= 1 then return CAPPED end
    if share >= 0.75 then return PURPLE end
    if share >= 0.5 then return BLUE end
    if share >= 0.25 then return GREEN end
    return WHITE
end

-- r, g, b for one panel line (also used by the stats window).
function ns.StatColor(line, index, count)
    if not ns.db then return WHITE[1], WHITE[2], WHITE[3] end
    if not inRun then
        if not ns.db.capColors then return WHITE[1], WHITE[2], WHITE[3] end
        local now = Number(line.value:GetText())
        if not now then return WHITE[1], WHITE[2], WHITE[3] end
        local color = ValueColor(line, LineKey(line, index, count), now)
        return color[1], color[2], color[3]
    end
    if not ns.db.runColors then return WHITE[1], WHITE[2], WHITE[3] end
    local key = LineKey(line, index, count)
    local now = Number(line.value:GetText())
    if not now then return WHITE[1], WHITE[2], WHITE[3] end
    local cap = CapOf(line, key)
    if cap and now >= cap then return CAPPED[1], CAPPED[2], CAPPED[3] end
    local base = ns.db.runBaseline and ns.db.runBaseline[key]
    if not base then return WHITE[1], WHITE[2], WHITE[3] end
    local gain
    if base > 0 then
        gain = (now - base) / base * 100
    elseif now > base then
        gain = 100
    else
        gain = 0
    end
    local color = WHITE
    for _, band in ipairs(BANDS) do
        if gain >= band.min then color = band.color end
    end
    return color[1], color[2], color[3]
end

local function SetInRun(on)
    if on == inRun then return end
    inRun = on
    ns.db.runInRun = on
    if on then
        -- the stats from before the run; or the first ones seen in it
        ns.db.runBaseline = lastOutside and Copy(lastOutside) or nil
    else
        ns.db.runBaseline = nil
    end
end

-- Keep the snapshot and the character pane's colors up to date.
local function Update()
    if not ns.db then return end
    local lines = ns.HeroStatLines and ns.HeroStatLines() or {}
    local count = 0
    for _ in ipairs(lines) do count = count + 1 end
    if count == 0 then return end
    if inRun then
        if not ns.db.runBaseline then ns.db.runBaseline = Snapshot(lines, count) end
    else
        lastOutside = Snapshot(lines, count)
    end
    for i, line in ipairs(lines) do
        line.value:SetTextColor(ns.StatColor(line, i, count))
    end
end

local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + (elapsed or arg1 or 0)
    if elapsedSince < 0.25 then return end
    elapsedSince = 0
    -- only while the panel can show anything (pane open or stats window open)
    if PaperDollFrame and PaperDollFrame:IsVisible() then Update() end
end)

ns.OnLoad(function()
    -- survive a /reload in the middle of a run
    inRun = ns.db.runInRun and true or false
end)

ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not msg or string.sub(msg, 1, 5) ~= "BONK~" then return end
    if msg == "BONK~start" or string.sub(msg, 1, 11) == "BONK~start~" then
        SetInRun(true)
    elseif msg == "BONK~end" or string.sub(msg, 1, 9) == "BONK~end~" then
        SetInRun(false)
    else
        local _, _, flag = string.find(msg, "^BONK~stats~(%d)")
        if flag then SetInRun(flag == "1") end
    end
end)
