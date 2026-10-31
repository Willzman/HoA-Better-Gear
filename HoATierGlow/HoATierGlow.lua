-- HoA Tier Glow
-- Adds a quality-colored glow (oGlow style) and the item's tier number to
-- every equipment slot on the character frame, and the tier number to items
-- in the HoA bags (which already have their own quality glow).
--
-- The tier comes straight from the Hordes of Azeroth UI addon, using the same
-- lookup it uses for the "Tier N" line on item tooltips:
--   VanillaBonkUI.FoundAt("inv", slot).tier  -- rolled ("found") pieces
--   VanillaBonkUI.GearTier(itemId)           -- set / mythic / legendary gear
--
-- Written for the 1.12.1 client (Lua 5.0): no '#', select(), string.match,
-- '...' varargs or hooksecurefunc. Event handlers also accept the
-- (self, event, arg1) params used by newer clients.

local ADDON_NAME = "HoATierGlow"

local DEFAULTS = {
    glow       = true,          -- show the quality glow
    tier       = true,          -- show the tier number
    bags       = true,          -- show the tier number on bag items
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

local BAGS = { 0, 1, 2, 3, 4 }   -- the bags HoA's bag window shows
local REFRESH_DELAY = 0.1 -- after HoA finishes sending found-item data

local db
local slots = {}          -- { id = invSlotId, button = frame, glow = tex, text = fontstring }
local bagSlots = {}       -- [button] = { button = frame, text = fontstring }
local refreshIn = nil     -- seconds until a scheduled refresh, or nil

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

local function ItemIdFromLink(link)
    local _, _, id = string.find(link or "", "item:(%d+)")
    return tonumber(id)
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
    local q
    for i, c in pairs(QUALITY_COLORS) do
        if c.hex == hex then q = i break end
    end
    return r, g, b, q
end

-- Returns quality, r, g, b for an equipped item (nil if unknown)
local function GetSlotQuality(slotId, link)
    local q
    if GetInventoryItemQuality then
        q = GetInventoryItemQuality("player", slotId)
    end
    if not q then
        local id = ItemIdFromLink(link)
        if id then
            local _, _, iq = GetItemInfo(id)
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

-- Tier of an item, the same way HoA's tooltip gets it. 'bag' is "inv" for
-- equipped items (slot = inventory slot id) or a bag number.
-- Returns tier (or nil), plus where it came from (for /hoatier debug).
local function GetItemTier(bag, slot, link)
    local ui = VanillaBonkUI
    if not ui then return nil, "HoA UI not loaded" end
    local found = ui.FoundAt and ui.FoundAt(bag, slot)
    if found and found.tier then return found.tier, "found" end
    local id = ItemIdFromLink(link)
    if id and ui.GearTier then
        local tier = ui.GearTier(id)
        if tier then return tier, "gear" end
    end
    return nil, "no tier"
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

-- A font string on its own frame, so it draws above glows and cooldowns.
local function CreateTierText(button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    holder:SetFrameLevel(button:GetFrameLevel() + 5)
    local text = holder:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
    text:SetJustifyH("CENTER")
    text:Hide()
    return text
end

local function ShowTier(text, tier, r, g, b)
    if not tier then
        text:Hide()
        return
    end
    text:SetText((db.prefix and "T" or "") .. tier)
    if db.colorTier and r then
        text:SetTextColor(r, g, b)
    else
        text:SetTextColor(1, 0.82, 0)
    end
    text:Show()
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

    local s = { id = slotId, button = button, glow = glow, text = CreateTierText(button) }
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

    if db.glow and q and q >= db.minQuality then
        s.glow:SetVertexColor(r, g, b)
        s.glow:SetAlpha(db.glowAlpha)
        s.glow:Show()
    else
        s.glow:Hide()
    end

    ShowTier(s.text, db.tier and GetItemTier("inv", s.id, link), r, g, b)
end

-- HoA's bag window creates its item buttons lazily, named
-- VanillaBonkBagsItem<bag>_<slot>; decorate whichever exist.
local function UpdateBags()
    local bagFrame = VanillaBonkBags
    if not bagFrame or not bagFrame:IsShown() then return end
    for _, bag in ipairs(BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            local button = getglobal("VanillaBonkBagsItem" .. bag .. "_" .. slot)
            if button then
                local b = bagSlots[button]
                if not b then
                    b = { button = button, text = CreateTierText(button) }
                    ApplyTextStyle(b)
                    bagSlots[button] = b
                end
                local link = db.tier and db.bags and GetContainerItemLink(bag, slot)
                if link then
                    local r, g, bl = ColorFromLink(link)
                    ShowTier(b.text, GetItemTier(bag, slot, link), r, g, bl)
                else
                    b.text:Hide()
                end
            end
        end
    end
end

local function RestyleAll()
    for _, s in ipairs(slots) do ApplyTextStyle(s) end
    for _, b in pairs(bagSlots) do ApplyTextStyle(b) end
end

local function UpdateAll()
    if not db then return end
    for _, s in ipairs(slots) do
        UpdateSlot(s)
    end
    UpdateBags()
end

local function ScheduleRefresh()
    refreshIn = REFRESH_DELAY
end

-- Refresh whenever the character pane or the HoA bag window opens.
-- (Children's OnShow fires when their parent is shown.)
local function WatchShow(parent)
    if not parent then return end
    local watcher = CreateFrame("Frame", nil, parent)
    watcher:SetScript("OnShow", function() UpdateAll() end)
end
WatchShow(PaperDollFrame)

local bagsWatched = false
local function WatchBags()
    if bagsWatched or not VanillaBonkBags then return end
    bagsWatched = true
    WatchShow(VanillaBonkBags)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")

frame:SetScript("OnEvent", function(self, ev, a1)
    ev = ev or event
    a1 = a1 or arg1

    if ev == "ADDON_LOADED" then
        if a1 ~= ADDON_NAME then return end
        HoATierGlowDB = CopyDefaults(DEFAULTS, HoATierGlowDB or {})
        db = HoATierGlowDB
        db.cache = nil -- left over from 1.1
        for _, name in ipairs(SLOT_NAMES) do
            SetupSlot(name)
        end
        WatchBags()
    elseif ev == "CHAT_MSG_SYSTEM" then
        -- HoA sends rolled-gear data as "BONK~founditem~..." system messages,
        -- ending with "BONK~foundend". Refresh once its own handler has run.
        if a1 and string.sub(a1, 1, 13) == "BONK~foundend" then
            ScheduleRefresh()
        end
    elseif ev == "UNIT_INVENTORY_CHANGED" then
        if a1 == "player" then ScheduleRefresh() end
    else
        -- BAG_UPDATE, PLAYER_ENTERING_WORLD
        WatchBags()
        ScheduleRefresh()
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not refreshIn then return end
    refreshIn = refreshIn - (elapsed or arg1 or 0)
    if refreshIn > 0 then return end
    refreshIn = nil
    UpdateAll()
end)


-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function Escape(text)
    if type(text) ~= "string" then return "" end
    return (string.gsub(text, "|", "||"))
end

local function Debug()
    if not VanillaBonkUI then
        Print("Hordes of Azeroth UI addon (VanillaBonkUI) not found - tiers can't be read.")
    end
    for _, s in ipairs(slots) do
        local link = GetInventoryItemLink("player", s.id)
        if link then
            local tier, source = GetItemTier("inv", s.id, link)
            Print(s.button:GetName() .. " id " .. tostring(ItemIdFromLink(link))
                .. ": tier " .. tostring(tier) .. " (" .. source .. ")  " .. Escape(link))
        end
    end
end

local function ShowHelp()
    Print("commands:")
    Print("/hoatier glow  - toggle the quality glow (" .. (db.glow and "on" or "off") .. ")")
    Print("/hoatier tier  - toggle the tier number (" .. (db.tier and "on" or "off") .. ")")
    Print("/hoatier bags  - toggle tier numbers on bag items (" .. (db.bags and "on" or "off") .. ")")
    Print("/hoatier color - toggle quality-colored tier text (" .. (db.colorTier and "on" or "off") .. ")")
    Print("/hoatier prefix - toggle 'T10' vs '10' (" .. (db.prefix and "T10" or "10") .. ")")
    Print("/hoatier quality <0-5> - minimum quality to glow (" .. db.minQuality .. ")")
    Print("/hoatier anchor <TOPLEFT|TOP|TOPRIGHT|CENTER|BOTTOMLEFT|BOTTOM|BOTTOMRIGHT> (" .. db.anchor .. ")")
    Print("/hoatier size <8-24> - tier font size (" .. db.fontSize .. ")")
    Print("/hoatier debug - list the tier read for each equipped item")
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
    elseif cmd == "bags" then
        db.bags = not db.bags
        Print("tier numbers in bags " .. (db.bags and "on" or "off"))
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
            RestyleAll()
            Print("tier anchor set to " .. a)
        else
            Print("invalid anchor")
        end
    elseif cmd == "size" then
        local n = tonumber(rest)
        if n and n >= 8 and n <= 24 then
            db.fontSize = n
            RestyleAll()
            Print("font size set to " .. n)
        else
            Print("usage: /hoatier size <8-24>")
        end
    elseif cmd == "debug" then
        Debug()
        return
    elseif cmd == "reset" then
        for k in pairs(db) do db[k] = nil end
        CopyDefaults(DEFAULTS, db)
        RestyleAll()
        Print("settings reset")
    else
        ShowHelp()
        return
    end
    UpdateAll()
end
