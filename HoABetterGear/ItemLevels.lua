-- HoA Better Gear - item levels and quality glow.
--
-- Character frame: quality glow (oGlow style) + item level on every slot.
-- HoA bag window, bank, Extraction Vault: item level (plus a glow in the
-- bank; HoA's bags draw their own).
--
-- The item level is worked out exactly like HoA's tooltip "ilvl N": the
-- item's tier (VanillaBonkUI.FoundAt(bag, slot).tier for rolled "found"
-- pieces, else VanillaBonkUI.GearTier(itemId)) and its quality, through
-- VanillaBonkUI.ItemLevel(tier, quality).

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

-- The quality HoA uses for an item's level (GetItemInfo, else the link color).
local function ItemQuality(link)
    local id = ns.ItemIdFromLink(link)
    local q
    if id then
        local _, _, iq = GetItemInfo(id)
        q = iq
    end
    if q == nil then
        local _, _, _, lq = ns.ColorFromLink(link)
        q = lq
    end
    return q
end

-- An item's level, the same way HoA's tooltip gets its "ilvl N":
--   tier    = VanillaBonkUI.FoundAt(bag, slot).tier  (rolled "found" pieces)
--             or VanillaBonkUI.GearTier(itemId)      (0 = no level)
--   level   = VanillaBonkUI.ItemLevel(tier, quality)
-- 'bag' is "inv" for equipped items (slot = inventory slot id) or a bag
-- number; 'tier'/'quality' can be passed directly (the vault knows them).
-- Returns the level (or nil), plus where it came from (for /hbg debug).
-- With an older HoA that has no item levels, the tier itself is returned.
function ns.ItemLevelFor(tier, quality)
    tier = tonumber(tier)
    if not tier or tier <= 0 then return nil end
    local ui = VanillaBonkUI
    if ui and ui.ItemLevel then return ui.ItemLevel(tier, quality) end
    return tier
end

function ns.GetItemLevel(bag, slot, link)
    local ui = VanillaBonkUI
    if not ui then return nil, "HoA UI not loaded" end
    local quality = ItemQuality(link)
    local found = ui.FoundAt and ui.FoundAt(bag, slot)
    if found and tonumber(found.tier) and found.tier > 0 then
        return ns.ItemLevelFor(found.tier, quality), "found"
    end
    local id = ns.ItemIdFromLink(link)
    local tier = id and ui.GearTier and ui.GearTier(id)
    if tier and tier > 0 then
        return ns.ItemLevelFor(tier, quality), "gear"
    end
    return nil, "no item level"
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

local function ShowLevel(text, level, r, g, b)
    if not level then
        text:Hide()
        return
    end
    text:SetText(level)
    if ns.db.colorTier and r then
        text:SetTextColor(r, g, b) -- the item's rarity color
    else
        text:SetTextColor(1, 0.82, 0) -- the gold of HoA's "ilvl N" tooltip line
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

    ShowLevel(s.text, db.tier and ns.GetItemLevel("inv", s.id, link), r, g, b)
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
        ShowLevel(b.text, ns.GetItemLevel(bag, slot, link), r, g, bl)
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
    -- HoA's vault cards take the quality from GetItemInfo, else find.quality
    local quality
    if find.entry then
        local _, _, iq = GetItemInfo(find.entry)
        quality = iq
    end
    quality = quality or find.quality
    local r, g, bl
    if quality then r, g, bl = ns.GetQualityColor(quality) end
    ShowLevel(b.text, ns.ItemLevelFor(tier, quality), r, g, bl)
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

-------------------------------------------------------------------------------
-- Average item level, on the character pane just above the stats
-------------------------------------------------------------------------------
-- Like retail: every slot your class uses (no shirt, tabard, ammo or slots
-- HoA locks), an empty slot that needs gear counts as 0, a two-hander counts
-- twice (it fills both hands), and items without an item level are left out.
-- The number is colored by the average rarity of the same slots (an empty
-- slot counts as poor), rounded to the nearest quality.

local averageLabel, averageValue

local function IsTwoHander(link)
    local id = ns.ItemIdFromLink(link)
    if not id then return false end
    local _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
    return equipLoc == "INVTYPE_2HWEAPON"
end

-- Returns the average item level and the average quality (or nil).
function ns.AverageItemLevel()
    local total, count = 0, 0
    local qualityTotal = 0
    local offHandLocked = false
    for _, s in ipairs(slots) do
        if s.name == "SecondaryHandSlot" then offHandLocked = SlotLocked(s) end
    end
    for _, s in ipairs(slots) do
        if not NEVER_RED[s.name] and not SlotLocked(s) then
            local link = GetInventoryItemLink("player", s.id)
            if link then
                local level = ns.GetItemLevel("inv", s.id, link)
                if level then
                    local quality = LinkQuality(link) or 0
                    if quality > 7 then quality = 0 end -- unknown custom color
                    local times = 1
                    if s.name == "MainHandSlot" and not offHandLocked and IsTwoHander(link) then
                        times = 2
                    end
                    total, count = total + level * times, count + times
                    qualityTotal = qualityTotal + quality * times
                end
            elseif EmptySlotNeedsGear(s) then
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return total / count, qualityTotal / count
end

local function CreateAverage()
    if not PaperDollFrame then return end
    local holder = CreateFrame("Frame", nil, PaperDollFrame)
    holder:SetWidth(104)
    holder:SetHeight(11)
    if VanillaBonkHeroStats then
        -- the stat lines start 6px in; sit just above "Power:"
        holder:SetPoint("BOTTOMLEFT", VanillaBonkHeroStats, "TOPLEFT", 6, 2)
    else
        holder:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", 73, -278)
    end
    holder:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 10)
    averageLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    averageLabel:SetPoint("LEFT", holder, "LEFT", 0, 0)
    averageLabel:SetText("Item level:")
    averageValue = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    averageValue:SetPoint("LEFT", averageLabel, "RIGHT", 4, 0)
    ns.averageHolder = holder
end

local function UpdateAverage()
    if not ns.averageHolder then return end
    local average, quality
    if ns.db.avgIlvl then average, quality = ns.AverageItemLevel() end
    if not average then
        ns.averageHolder:Hide()
        return
    end
    averageValue:SetText(string.format("%.1f", average))
    if ns.db.colorTier and quality then
        averageValue:SetTextColor(ns.GetQualityColor(math.floor(quality + 0.5)))
    else
        averageValue:SetTextColor(1, 1, 1)
    end
    ns.averageHolder:Show()
end

ns.OnLoad(function()
    for _, name in ipairs(SLOT_NAMES) do
        SetupSlot(name)
    end
    CreateAverage()
end)

ns.OnRefresh(function()
    UpdateVault()
    for _, s in ipairs(slots) do
        UpdateSlot(s)
    end
    UpdateAverage()
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
ns.Toggle("tier", "ilvl", "item level numbers")
-- old name, still works (not listed in the help)
ns.Command("tier", function()
    ns.db.tier = not ns.db.tier
    ns.Print("item level numbers " .. ns.OnOff(ns.db.tier))
end)
ns.Toggle("bags", "bags", "item levels on bag and bank items")
ns.Toggle("colorTier", "color", "rarity-colored item levels (off = gold)")
ns.Toggle("avgIlvl", "avgilvl", "average item level on the character pane")

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
    ns.Print("item level position set to " .. a)
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
end, function() return "/hbg size <8-24> - item level font size (" .. ns.db.fontSize .. ")" end)
