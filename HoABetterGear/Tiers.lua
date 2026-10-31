-- HoA Better Gear - tier numbers and quality glow.
--
-- Character frame: quality glow (oGlow style) + tier number on every slot.
-- HoA bag window: tier number (HoA already draws its own quality glow).
--
-- The tier comes straight from the HoA UI addon, the same lookup it uses for
-- the "Tier N" line on tooltips:
--   VanillaBonkUI.FoundAt(bag, slot).tier  -- rolled ("found") pieces
--   VanillaBonkUI.GearTier(itemId)         -- set / mythic / legendary gear

local ns = HoABetterGear

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

local slots = {}    -- { id = invSlotId, button, glow, text }
local bagSlots = {} -- [button] = { button, text }

-- 'bag' is "inv" for equipped items (slot = inventory slot id) or a bag number.
-- Returns tier (or nil), plus where it came from (for /hbg debug).
function ns.GetItemTier(bag, slot, link)
    local ui = VanillaBonkUI
    if not ui then return nil, "HoA UI not loaded" end
    local found = ui.FoundAt and ui.FoundAt(bag, slot)
    if found and found.tier then return found.tier, "found" end
    local id = ns.ItemIdFromLink(link)
    if id and ui.GearTier then
        local tier = ui.GearTier(id)
        if tier then return tier, "gear" end
    end
    return nil, "no tier"
end

-- Returns quality, r, g, b for an equipped item (nil if unknown)
local function GetSlotQuality(slotId, link)
    local q
    if GetInventoryItemQuality then
        q = GetInventoryItemQuality("player", slotId)
    end
    if not q then
        local id = ns.ItemIdFromLink(link)
        if id then
            local _, _, iq = GetItemInfo(id)
            q = iq
        end
    end
    local lr, lg, lb, lq = ns.ColorFromLink(link)
    if q == nil then q = lq end
    if q ~= nil then
        local r, g, b = ns.GetQualityColor(q)
        return q, r, g, b
    end
    if lr then
        return 99, lr, lg, lb -- unknown custom color: still glow
    end
    return nil
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------

local function ApplyTextStyle(s)
    local db = ns.db
    local text = s.text
    text:ClearAllPoints()
    local anchor = ANCHORS[db.anchor] and db.anchor or "BOTTOMRIGHT"
    local x, y = 0, 0
    if string.find(anchor, "LEFT") then x = 2 elseif string.find(anchor, "RIGHT") then x = -1 end
    if string.find(anchor, "TOP") then y = -2 elseif string.find(anchor, "BOTTOM") then y = 2 end
    text:SetPoint(anchor, s.button, anchor, x, y)
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
end

local function CreateTierText(button)
    local text = ns.Overlay(button):CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ns.db.fontSize, "OUTLINE")
    text:SetJustifyH("CENTER")
    text:Hide()
    return text
end

local function ShowTier(text, tier, r, g, b)
    if not tier then
        text:Hide()
        return
    end
    text:SetText((ns.db.prefix and "T" or "") .. tier)
    if ns.db.colorTier and r then
        text:SetTextColor(r, g, b)
    else
        text:SetTextColor(1, 0.82, 0) -- same gold as HoA's "Tier N" tooltip line
    end
    text:Show()
end

function ns.Restyle()
    for _, s in ipairs(slots) do ApplyTextStyle(s) end
    for _, b in pairs(bagSlots) do ApplyTextStyle(b) end
end

-------------------------------------------------------------------------------
-- Character frame
-------------------------------------------------------------------------------

-- Empty slots glow red, except slots that don't matter or can't be used.
local NEVER_RED = { ShirtSlot = true, TabardSlot = true, AmmoSlot = true }

-- Slots HoA locks per class (copied from its VanillaBonkSlots.lua, which keeps
-- the list private). HoA also puts a red X (button.bonkCross) on locked
-- slots, which is checked too in case the list changes.
local LOCKED_SLOTS = {
    WARRIOR = { RangedSlot = true }, PALADIN = { RangedSlot = true },
    ROGUE   = { RangedSlot = true }, PRIEST  = { RangedSlot = true },
    SHAMAN  = { RangedSlot = true }, MAGE    = { RangedSlot = true },
    WARLOCK = { RangedSlot = true },
    DRUID   = { SecondaryHandSlot = true, RangedSlot = true },
    HUNTER  = { MainHandSlot = true, SecondaryHandSlot = true },
}

local ONE_HANDED = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }

local function SlotLocked(s)
    if type(s.button.bonkCross) == "table" then return true end
    local _, class = UnitClass("player")
    local locked = class and LOCKED_SLOTS[class]
    return locked and locked[s.name] or false
end

local function MainHandOneHanded()
    local id = ns.ItemIdFromLink(GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot")))
    if not id then return false end
    local _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
    return ONE_HANDED[equipLoc or ""] or false
end

-- Should this (empty) slot glow red?
local function EmptySlotNeedsGear(s)
    if NEVER_RED[s.name] or SlotLocked(s) then return false end
    -- The off hand only matters next to a one-handed main-hand weapon.
    if s.name == "SecondaryHandSlot" then return MainHandOneHanded() end
    return true
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

    local s = { id = slotId, name = slotName, button = button, glow = glow, text = CreateTierText(button) }
    ApplyTextStyle(s)
    table.insert(slots, s)
end

local function UpdateSlot(s)
    local db = ns.db
    local link = GetInventoryItemLink("player", s.id)
    if not link then
        if db.emptyGlow and EmptySlotNeedsGear(s) then
            s.glow:SetVertexColor(1, 0.1, 0.1)
            s.glow:SetAlpha(db.glowAlpha)
            s.glow:Show()
        else
            s.glow:Hide()
        end
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

    ShowTier(s.text, db.tier and ns.GetItemTier("inv", s.id, link), r, g, b)
end

-- For other modules: should this character slot (by name, e.g. "HeadSlot")
-- have gear in it? Same rules as the red empty-slot glow.
function ns.SlotNeedsGear(slotName)
    for _, s in ipairs(slots) do
        if s.name == slotName then return EmptySlotNeedsGear(s) end
    end
    return false
end

-------------------------------------------------------------------------------
-- Bags
-------------------------------------------------------------------------------

-- Quality of an item from its link: quality, r, g, b (nil if unknown).
local function LinkQuality(link)
    local id = ns.ItemIdFromLink(link)
    local q
    if id then
        local _, _, iq = GetItemInfo(id)
        q = iq
    end
    local lr, lg, lb, lq = ns.ColorFromLink(link)
    if q == nil then q = lq end
    if q ~= nil then
        local r, g, b = ns.GetQualityColor(q)
        return q, r, g, b
    end
    if lr then return 99, lr, lg, lb end
    return nil
end

-- Bank buttons (the standard window has no quality glow; HoA's bags do).
local bankGlows = {} -- [button] = texture

local function UpdateBankGlow(button, bag, slot)
    local glow = bankGlows[button]
    if not glow then
        glow = button:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        local w = button:GetWidth()
        if not w or w == 0 then w = 37 end
        glow:SetWidth(w * 1.85)
        glow:SetHeight(w * 1.85)
        glow:SetPoint("CENTER", button, "CENTER", 0, 0)
        bankGlows[button] = glow
    end
    local link = ns.db.glow and GetContainerItemLink(bag, slot)
    local q, r, g, b
    if link then q, r, g, b = LinkQuality(link) end
    if q and q >= ns.db.minQuality then
        glow:SetVertexColor(r, g, b)
        glow:SetAlpha(ns.db.glowAlpha)
        glow:Show()
    else
        glow:Hide()
    end
end

local itemButtons = {} -- bag/bank buttons that have a tier text

local function UpdateBagButton(button, bag, slot)
    itemButtons[button] = true
    local b = bagSlots[button]
    if not b then
        b = { button = button, text = CreateTierText(button) }
        ApplyTextStyle(b)
        bagSlots[button] = b
    end
    local link = ns.db.tier and ns.db.bags and GetContainerItemLink(bag, slot)
    if link then
        local r, g, bl = ns.ColorFromLink(link)
        ShowTier(b.text, ns.GetItemTier(bag, slot, link), r, g, bl)
    else
        b.text:Hide()
    end
end

-------------------------------------------------------------------------------
-- Extraction Vault: the "Mailed to you when you leave" box
-------------------------------------------------------------------------------
-- HoA's vault window keeps those slots in VanillaBonkVault.box.slots, each
-- with a .find { entry, tier, quality } it refills as items move in and out.
-- (The cards below the box already show their tier.) While the window is
-- open, keep a tier number on each filled slot.

local vaultElapsed = 0

local function UpdateVaultSlot(slot)
    local b = bagSlots[slot]
    if not b then
        b = { button = slot, text = CreateTierText(slot) }
        ApplyTextStyle(b)
        bagSlots[slot] = b
    end
    local find = slot.find
    if not (ns.db.tier and type(find) == "table" and slot:IsShown()) then
        b.text:Hide()
        return
    end
    local tier = tonumber(find.tier)
    if not tier or tier <= 0 then
        local ui = VanillaBonkUI
        tier = ui and ui.GearTier and find.entry and ui.GearTier(find.entry)
    end
    local r, g, bl
    if find.quality then r, g, bl = ns.GetQualityColor(find.quality) end
    ShowTier(b.text, tier, r, g, bl)
end

local function UpdateVault()
    local vault = VanillaBonkVault
    local box = vault and vault:IsShown() and vault.box
    if not (box and type(box.slots) == "table") then return end
    for _, slot in pairs(box.slots) do
        if type(slot) == "table" then UpdateVaultSlot(slot) end
    end
end

local vaultWatcher = CreateFrame("Frame")
vaultWatcher:SetScript("OnUpdate", function(self, elapsed)
    vaultElapsed = vaultElapsed + (elapsed or arg1 or 0)
    if vaultElapsed < 0.2 then return end
    vaultElapsed = 0
    if ns.db then UpdateVault() end
end)

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

ns.OnLoad(function()
    for _, name in ipairs(SLOT_NAMES) do
        SetupSlot(name)
    end
end)

ns.OnRefresh(function()
    UpdateVault()
    for _, s in ipairs(slots) do
        UpdateSlot(s)
    end
    -- The game reuses its container windows for different bags, so clear
    -- anything left on buttons that weren't updated this time.
    local seen = {}
    ns.ForEachItemButton(function(button, bag, slot)
        seen[button] = true
        UpdateBagButton(button, bag, slot)
    end)
    ns.ForEachBankButton(UpdateBankGlow)
    for button in pairs(itemButtons) do
        if not seen[button] then bagSlots[button].text:Hide() end
    end
    for button, glow in pairs(bankGlows) do
        if not seen[button] then glow:Hide() end
    end
end)

ns.Toggle("glow", "glow", "quality glow (character and bank)")
ns.Toggle("emptyGlow", "empty", "red glow on empty slots")
ns.Toggle("tier", "tier", "tier numbers")
ns.Toggle("bags", "bags", "tier numbers on bag items")
ns.Toggle("colorTier", "color", "quality-colored tier text")

ns.Command("prefix", function()
    ns.db.prefix = not ns.db.prefix
    ns.Print("tier format " .. (ns.db.prefix and "T10" or "10"))
end, function() return "/hbg prefix - toggle 'T10' vs '10' (" .. (ns.db.prefix and "T10" or "10") .. ")" end)

ns.Command("quality", function(rest)
    local n = tonumber(rest)
    if n and n >= 0 and n <= 7 then
        ns.db.minQuality = n
        ns.Print("minimum glow quality set to " .. n)
    else
        ns.Print("usage: /hbg quality <0-5>")
        return true
    end
end, function() return "/hbg quality <0-5> - minimum quality to glow (" .. ns.db.minQuality .. ")" end)

ns.Command("anchor", function(rest)
    local a = string.upper(rest or "")
    if not ANCHORS[a] then
        ns.Print("invalid anchor")
        return true
    end
    ns.db.anchor = a
    ns.Restyle()
    ns.Print("tier anchor set to " .. a)
end, function() return "/hbg anchor <TOPLEFT|TOP|TOPRIGHT|CENTER|BOTTOMLEFT|BOTTOM|BOTTOMRIGHT> (" .. ns.db.anchor .. ")" end)

ns.Command("size", function(rest)
    local n = tonumber(rest)
    if not (n and n >= 8 and n <= 24) then
        ns.Print("usage: /hbg size <8-24>")
        return true
    end
    ns.db.fontSize = n
    ns.Restyle()
    ns.Print("font size set to " .. n)
end, function() return "/hbg size <8-24> - tier font size (" .. ns.db.fontSize .. ")" end)
