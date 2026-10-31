-- HoA Tier Glow
-- Adds a quality-colored glow (oGlow style) and the item's tier number to
-- every equipment slot on the character frame.
--
-- Written to run on the old 1.12 (Lua 5.0) client API as well as newer ones:
--   * no '#', table.getn, select(), string.match, '...' varargs or hooksecurefunc
--   * event handlers read both the (self, event, arg1) params and the
--     legacy 'event' / 'arg1' globals

local ADDON_NAME = "HoATierGlow"

local DEFAULTS = {
    glow       = true,          -- show the quality glow
    tier       = true,          -- show the tier number
    minQuality = 2,             -- 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary
    anchor     = "BOTTOMRIGHT", -- where the tier number sits on the icon
    colorTier  = true,          -- color the tier number by item quality (else gold)
    prefix     = false,         -- show "T10" instead of "10"
    glowAlpha  = 0.85,
    fontSize   = 13,
}

-- Fallback quality colors in case ITEM_QUALITY_COLORS is missing / incomplete.
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "9d9d9d" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "1eff00" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "a335ee" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "ff8000" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "e6cc80" },
    [7] = { r = 0.00, g = 0.80, b = 1.00, hex = "00ccff" },
}

local SLOT_NAMES = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
    "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
    "RangedSlot", "AmmoSlot",
}

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local db
local slots = {}          -- { id = invSlotId, button = frame, glow = tex, text = fontstring }
local pending = false     -- some slot had an item we couldn't read yet
local elapsedSince = 0

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99HoA Tier Glow|r: " .. msg)
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
    return dst
end

local function GetQualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    c = QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Read the color straight from an item link: "|cffRRGGBB|Hitem:..."
local function ColorFromLink(link)
    local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)")
    if not hex then return nil end
    hex = string.lower(hex)
    local r = tonumber(string.sub(hex, 1, 2), 16) / 255
    local g = tonumber(string.sub(hex, 3, 4), 16) / 255
    local b = tonumber(string.sub(hex, 5, 6), 16) / 255
    -- map back to a quality index if it is a known color
    local q
    for i, c in pairs(QUALITY_COLORS) do
        if c.hex == hex then q = i break end
    end
    return r, g, b, q
end

-- Returns quality, r, g, b for an equipped slot (or nil if empty / unknown)
local function GetSlotQuality(slotId, link)
    local q
    if GetInventoryItemQuality then
        q = GetInventoryItemQuality("player", slotId)
    end
    if not q then
        local _, _, itemId = string.find(link, "item:(%d+)")
        if itemId then
            local _, _, iq = GetItemInfo(tonumber(itemId))
            q = iq
        end
    end
    local lr, lg, lb, lq = ColorFromLink(link)
    if q == nil then q = lq end
    if q ~= nil then
        local r, g, b = GetQualityColor(q)
        return q, r, g, b
    end
    if lr then
        -- unknown custom color: still glow, treat as high quality
        return 99, lr, lg, lb
    end
    return nil
end

-------------------------------------------------------------------------------
-- Tooltip scanning for "Tier N"
-------------------------------------------------------------------------------

local scanTip = CreateFrame("GameTooltip", "HoATierGlowScanTip", nil, "GameTooltipTemplate")

local function FindTier(text)
    if not text then return nil end
    local _, _, n = string.find(text, "^%s*[Tt]ier%s+(%d+)%s*$")
    if n then return tonumber(n) end
    return nil
end

-- Returns tier number, or nil if none; second return is true when the
-- tooltip came back empty (item data not cached yet -> retry later).
local function GetSlotTier(slotId)
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotId)

    local numLines = scanTip:NumLines() or 0
    if numLines == 0 then
        scanTip:Hide()
        return nil, true
    end

    local tier
    -- The tier is normally on the right side of the first line, but check
    -- every line on both sides just in case.
    for i = 1, numLines do
        local right = getglobal("HoATierGlowScanTipTextRight" .. i)
        tier = FindTier(right and right:IsShown() and right:GetText())
        if tier then break end
        local left = getglobal("HoATierGlowScanTipTextLeft" .. i)
        tier = FindTier(left and left:GetText())
        if tier then break end
    end
    scanTip:Hide()
    return tier, false
end

-------------------------------------------------------------------------------
-- Slot decoration
-------------------------------------------------------------------------------

local function ApplyTextStyle(s)
    local text = s.text
    text:ClearAllPoints()
    local anchor = ANCHORS[db.anchor] and db.anchor or "BOTTOMRIGHT"
    local x, y = 0, 0
    if string.find(anchor, "LEFT") then x = 2 elseif string.find(anchor, "RIGHT") then x = -1 end
    if string.find(anchor, "TOP") then y = -2 elseif string.find(anchor, "BOTTOM") then y = 2 end
    text:SetPoint(anchor, s.button, anchor, x, y)
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
end

local function SetupSlot(slotName)
    local button = getglobal("Character" .. slotName)
    if not button then return end
    local slotId = GetInventorySlotInfo(slotName)
    if not slotId then return end

    -- oGlow-style glow: the action-button border texture in ADD blend mode,
    -- scaled up so the soft edge sits around the icon.
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    local w = button:GetWidth()
    if not w or w == 0 then w = 37 end
    glow:SetWidth(w * 1.85)
    glow:SetHeight(w * 1.85)
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    glow:Hide()

    -- Text lives on its own frame so it draws above the glow and cooldowns.
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    holder:SetFrameLevel(button:GetFrameLevel() + 5)
    local text = holder:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
    text:SetJustifyH("CENTER")
    text:Hide()

    local s = { id = slotId, button = button, glow = glow, text = text }
    ApplyTextStyle(s)
    table.insert(slots, s)
end

local function UpdateSlot(s)
    local link = GetInventoryItemLink("player", s.id)
    if not link then
        s.glow:Hide()
        s.text:Hide()
        return
    end

    local q, r, g, b = GetSlotQuality(s.id, link)

    -- glow
    if db.glow and q and q >= db.minQuality then
        s.glow:SetVertexColor(r, g, b)
        s.glow:SetAlpha(db.glowAlpha)
        s.glow:Show()
    else
        s.glow:Hide()
    end

    -- tier
    if db.tier then
        local tier, notReady = GetSlotTier(s.id)
        if notReady then pending = true end
        if tier then
            if db.prefix then
                s.text:SetText("T" .. tier)
            else
                s.text:SetText(tostring(tier))
            end
            if db.colorTier and r then
                s.text:SetTextColor(r, g, b)
            else
                s.text:SetTextColor(1, 0.82, 0)
            end
            s.text:Show()
        else
            s.text:Hide()
        end
    else
        s.text:Hide()
    end
end

local function UpdateAll()
    if not db then return end
    pending = false
    for _, s in ipairs(slots) do
        UpdateSlot(s)
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")

frame:SetScript("OnEvent", function(self, ev, a1)
    ev = ev or event
    a1 = a1 or arg1

    if ev == "ADDON_LOADED" then
        if a1 ~= ADDON_NAME then return end
        HoATierGlowDB = CopyDefaults(DEFAULTS, HoATierGlowDB or {})
        db = HoATierGlowDB
        for _, name in ipairs(SLOT_NAMES) do
            SetupSlot(name)
        end
    elseif ev == "UNIT_INVENTORY_CHANGED" then
        if a1 == "player" then UpdateAll() end
    else
        UpdateAll()
    end
end)

-- A watcher parented to the paper doll: OnShow fires whenever the character
-- pane opens, and OnUpdate retries slots whose item data wasn't cached yet.
if PaperDollFrame then
    local watcher = CreateFrame("Frame", nil, PaperDollFrame)
    watcher:SetScript("OnShow", function() UpdateAll() end)
    watcher:SetScript("OnUpdate", function(self, elapsed)
        if not pending then return end
        elapsedSince = elapsedSince + (elapsed or arg1 or 0)
        if elapsedSince < 0.5 then return end
        elapsedSince = 0
        UpdateAll()
    end)
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function ShowHelp()
    Print("commands:")
    Print("/hoatier glow  - toggle the quality glow (" .. (db.glow and "on" or "off") .. ")")
    Print("/hoatier tier  - toggle the tier number (" .. (db.tier and "on" or "off") .. ")")
    Print("/hoatier color - toggle quality-colored tier text (" .. (db.colorTier and "on" or "off") .. ")")
    Print("/hoatier prefix - toggle 'T10' vs '10' (" .. (db.prefix and "T10" or "10") .. ")")
    Print("/hoatier quality <0-5> - minimum quality to glow (" .. db.minQuality .. ")")
    Print("/hoatier anchor <TOPLEFT|TOP|TOPRIGHT|CENTER|BOTTOMLEFT|BOTTOM|BOTTOMRIGHT> (" .. db.anchor .. ")")
    Print("/hoatier size <8-24> - tier font size (" .. db.fontSize .. ")")
    Print("/hoatier reset - restore defaults")
end

SLASH_HOATIERGLOW1 = "/hoatier"
SLASH_HOATIERGLOW2 = "/hoatierglow"
SlashCmdList["HOATIERGLOW"] = function(msg)
    if not db then return end
    msg = string.lower(msg or "")
    local _, _, cmd, rest = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd or ""

    if cmd == "glow" then
        db.glow = not db.glow
        Print("glow " .. (db.glow and "on" or "off"))
    elseif cmd == "tier" then
        db.tier = not db.tier
        Print("tier number " .. (db.tier and "on" or "off"))
    elseif cmd == "color" then
        db.colorTier = not db.colorTier
        Print("quality-colored tier " .. (db.colorTier and "on" or "off"))
    elseif cmd == "prefix" then
        db.prefix = not db.prefix
        Print("tier format " .. (db.prefix and "T10" or "10"))
    elseif cmd == "quality" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 7 then
            db.minQuality = n
            Print("minimum glow quality set to " .. n)
        else
            Print("usage: /hoatier quality <0-5>")
        end
    elseif cmd == "anchor" then
        local a = string.upper(rest or "")
        if ANCHORS[a] then
            db.anchor = a
            for _, s in ipairs(slots) do ApplyTextStyle(s) end
            Print("tier anchor set to " .. a)
        else
            Print("invalid anchor")
        end
    elseif cmd == "size" then
        local n = tonumber(rest)
        if n and n >= 8 and n <= 24 then
            db.fontSize = n
            for _, s in ipairs(slots) do ApplyTextStyle(s) end
            Print("font size set to " .. n)
        else
            Print("usage: /hoatier size <8-24>")
        end
    elseif cmd == "reset" then
        for k in pairs(db) do db[k] = nil end
        CopyDefaults(DEFAULTS, db)
        for _, s in ipairs(slots) do ApplyTextStyle(s) end
        Print("settings reset")
    else
        ShowHelp()
        return
    end
    UpdateAll()
end
