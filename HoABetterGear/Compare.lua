-- HoA Better Gear - Pawn-style gear comparison.
--
-- Every stat has a weight; an item's score is the sum of weight * value over
-- its stats. Gear tooltips get a summary of how the item compares with what
-- you have equipped in that slot (the weaker one, for rings and trinkets),
-- plus the difference in each stat. Bag items that would be an upgrade get a
-- green arrow.
--
-- Stats are read exactly as HoA shows them: the HoA UI addon writes lines
-- like "+19.5% Power" onto item tooltips (VanillaBonkUI.AddGearLines), so
-- for a hovered item we read GameTooltip, and for equipped / bag items we
-- have AddGearLines write onto a hidden tooltip and read that.

local ns = HoABetterGear

-- Default weights by HoA stat id: score points per point of the stat.
-- Guesses for a damage-focused build; tune them with /hbg weight.
ns.DEFAULT_WEIGHTS = {
    [0]  = 1.0,  -- Power
    [1]  = 1.0,  -- Haste
    [2]  = 10,   -- Count (extra bolts - whole numbers, so weighted high)
    [3]  = 0.25, -- Movement speed
    [4]  = 0.5,  -- Max health
    [5]  = 2.0,  -- Regen (% of max health per sec - small numbers)
    [6]  = 0.1,  -- Gold
    [7]  = 0.2,  -- Experience
    [8]  = 0.1,  -- Pickup range
    [9]  = 0.5,  -- Leech
    [10] = 0.5,  -- Area
    [11] = 0.5,  -- Duration
    [12] = 0.5,  -- Armor
    [14] = 0.75, -- Dodge chance
    [15] = 1.0,  -- Critical strike chance
    [16] = 0.5,  -- Critical strike damage
    [17] = 0.5,  -- Shield
    [18] = 0.5,  -- Luck
    [19] = 0.5,  -- Poison damage
}
local UNKNOWN_WEIGHT = 0.5
local MAX_STAT_ID = 30

local SLOTS_BY_EQUIP_LOC = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

local ARROW_TEXTURE = "Interface\\AddOns\\HoABetterGear\\UpgradeArrow"

-------------------------------------------------------------------------------
-- Stat names <-> ids
-------------------------------------------------------------------------------

local statNames   -- [id] = "Power"
local statIdByKey -- [lower name] = id

local function BuildStatNames()
    if statNames then return end
    local ui = VanillaBonkUI
    if not (ui and ui.StatText) then return end
    statNames, statIdByKey = {}, {}
    for id = 0, MAX_STAT_ID do
        local _, _, name = string.find(ui.StatText(id, 1) or "", "^%+[%d%.]+%%? (.+)$")
        if name then
            statNames[id] = name
            statIdByKey[string.lower(name)] = id
        end
    end
end

-- Stat key: the HoA stat id when we know the name, else the name itself.
local function StatKey(name)
    BuildStatNames()
    return (statIdByKey and statIdByKey[string.lower(name)]) or name
end

function ns.Weight(key)
    local w = ns.db.weights[key]
    if w then return w end
    w = ns.DEFAULT_WEIGHTS[key]
    if w then return w end
    return UNKNOWN_WEIGHT
end

-------------------------------------------------------------------------------
-- Reading stats off tooltips
-------------------------------------------------------------------------------

-- Returns { values = {[key] = n}, order = {key...}, names = {[key] = s},
--           pct = {[key] = bool}, count = n }
local function ParseTooltip(tip)
    local stats = { values = {}, order = {}, names = {}, pct = {}, count = 0 }
    local name = tip:GetName()
    for i = 1, tip:NumLines() or 0 do
        local line = getglobal(name .. "TextLeft" .. i)
        local text = line and line:GetText()
        if type(text) == "string" then
            local _, _, sign, num, pct, statName =
                string.find(ns.StripCodes(text), "^([%+%-])([%d%.]+)(%%?) (.+)$")
            local value = tonumber(num or "")
            if value then
                if sign == "-" then value = -value end
                local key = StatKey(statName)
                if not stats.values[key] then
                    table.insert(stats.order, key)
                    stats.names[key] = statName
                    stats.pct[key] = pct == "%"
                    stats.values[key] = 0
                end
                stats.values[key] = stats.values[key] + value
                stats.count = stats.count + 1
            end
        end
    end
    return stats
end

-- Blizzard colors requirement lines it can't meet (e.g. "Classes: Mage")
-- red; treat any red line as "you can't use this".
local function TooltipUnusable(tip)
    local name = tip:GetName()
    for i = 2, tip:NumLines() or 0 do
        local line = getglobal(name .. "TextLeft" .. i)
        if line and line.GetTextColor and line:IsShown() then
            local r, g, b = line:GetTextColor()
            if r and r > 0.95 and g < 0.2 and b < 0.2 then return true end
        end
    end
    return false
end

local scanTip = CreateFrame("GameTooltip", "HoABetterGearScanTip", nil, "GameTooltipTemplate")

-- Stats of an item as HoA would show them. 'setBase' optionally fills in the
-- standard tooltip first (used to check usability).
local function ScanStats(link, found, setBase)
    local ui = VanillaBonkUI
    if not (link and ui and ui.AddGearLines) then return nil end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    local unusable = false
    if setBase then
        setBase(scanTip)
        unusable = TooltipUnusable(scanTip)
        scanTip:ClearLines()
    end
    ui.AddGearLines(scanTip, link, found)
    local stats = ParseTooltip(scanTip)
    scanTip:Hide()
    stats.unusable = unusable
    return stats
end

local function EquippedStats(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return nil end
    local found = VanillaBonkUI and VanillaBonkUI.FoundAt and VanillaBonkUI.FoundAt("inv", slot)
    local stats = ScanStats(link, found)
    if stats then
        stats.link = link
        stats.itemName = GetItemInfo(ns.ItemIdFromLink(link) or 0)
    end
    return stats
end

function ns.Score(stats)
    local score = 0
    for key, value in pairs(stats.values) do
        score = score + ns.Weight(key) * value
    end
    return score
end

local function SlotsFor(link)
    local id = ns.ItemIdFromLink(link)
    if not id then return nil end
    local _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
    return equipLoc and SLOTS_BY_EQUIP_LOC[equipLoc]
end

-- Compares candidate stats with what's equipped in the item's slot(s).
-- Returns nil if the item isn't gear we can compare, else a table:
--   { score, empty = bool, other = equipped stats, otherScore }
-- 'equippedCache' (optional) memoizes equipped stats within one pass.
local function Compare(stats, link, equippedCache)
    if not stats or stats.count == 0 then return nil end
    local slots = SlotsFor(link)
    if not slots then return nil end
    local result = { score = ns.Score(stats) }
    for _, slot in ipairs(slots) do
        local eq
        if equippedCache then
            eq = equippedCache[slot]
            if eq == nil then
                eq = EquippedStats(slot) or false
                equippedCache[slot] = eq
            end
        else
            eq = EquippedStats(slot) or false
        end
        if not eq then
            -- an empty slot: anything is an upgrade
            result.empty = true
            result.other, result.otherScore = nil, 0
            return result
        end
        local score = ns.Score(eq)
        if not result.other or score < result.otherScore then
            result.other, result.otherScore = eq, score
        end
    end
    return result
end

-------------------------------------------------------------------------------
-- Tooltip summary
-------------------------------------------------------------------------------

local function Round1(n)
    local s = string.format("%.1f", n)
    s = string.gsub(s, "%.0$", "")
    if s == "-0" then s = "0" end
    return s
end

local function Signed(n, pct)
    return (n > 0 and "+" or "") .. Round1(n) .. (pct and "%" or "")
end

local function AddComparison(tip, link)
    if not ns.db or not ns.db.compare or not link then return end
    local stats = ParseTooltip(tip)
    if stats.count == 0 or TooltipUnusable(tip) then return end
    local cmp = Compare(stats, link)
    if not cmp then return end

    -- Don't compare an item with itself (e.g. hovering an equipped piece
    -- through a hyperlink).
    if cmp.other and cmp.other.link == link and math.abs(cmp.score - cmp.otherScore) < 0.001 then
        return
    end

    tip:AddLine(" ")
    if cmp.empty then
        tip:AddDoubleLine("Better Gear: upgrade", "empty slot", 0.2, 1, 0.2, 0.6, 0.6, 0.6)
    else
        local diff = cmp.score - cmp.otherScore
        local headline, r, g, b
        if math.abs(diff) < 0.05 then
            headline, r, g, b = "Better Gear: same score", 1, 1, 1
        else
            local pctText
            if cmp.otherScore > 0 then
                pctText = Signed(diff / cmp.otherScore * 100, true)
            else
                pctText = Signed(diff, false) .. " score"
            end
            if diff > 0 then
                headline, r, g, b = "Better Gear: " .. pctText .. " upgrade", 0.2, 1, 0.2
            else
                headline, r, g, b = "Better Gear: " .. pctText .. " downgrade", 1, 0.3, 0.3
            end
        end
        tip:AddDoubleLine(headline, "vs " .. (cmp.other.itemName or "equipped"), r, g, b, 0.6, 0.6, 0.6)
    end

    if ns.db.diffs then
        local other = cmp.other or { values = {}, order = {}, names = {}, pct = {} }
        local seen = {}
        local function DiffLine(key)
            if seen[key] then return end
            seen[key] = true
            local d = (stats.values[key] or 0) - (other.values[key] or 0)
            if math.abs(d) < 0.05 then return end
            local name = stats.names[key] or other.names[key] or tostring(key)
            local pct = stats.pct[key]
            if pct == nil then pct = other.pct[key] end
            if d > 0 then
                tip:AddLine("   " .. Signed(d, pct) .. " " .. name, 0.2, 1, 0.2)
            else
                tip:AddLine("   " .. Signed(d, pct) .. " " .. name, 1, 0.3, 0.3)
            end
        end
        for _, key in ipairs(stats.order) do DiffLine(key) end
        for _, key in ipairs(other.order) do DiffLine(key) end
        tip:AddDoubleLine("   Score", Round1(cmp.score) .. "  vs  " .. Round1(cmp.otherScore),
            0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    tip:Show()
end

-- Wrap GameTooltip methods. HoA's own wrappers (which add the stat lines)
-- were installed when it loaded, before us, so ours run after them.
local function HookTooltip(method, linkOf)
    local original = GameTooltip[method]
    if not original then return end
    GameTooltip[method] = function(self, a1, a2, a3)
        local r1, r2, r3 = original(self, a1, a2, a3)
        AddComparison(self, linkOf(a1, a2, a3))
        return r1, r2, r3
    end
end

HookTooltip("SetBagItem", function(bag, slot) return GetContainerItemLink(bag, slot) end)
HookTooltip("SetMerchantItem", function(index) return GetMerchantItemLink(index) end)
HookTooltip("SetLootItem", function(slot) return GetLootSlotLink(slot) end)
HookTooltip("SetHyperlink", function(link) return link end)
if GetBuybackItemLink then
    HookTooltip("SetBuybackItem", function(index) return GetBuybackItemLink(index) end)
end

-------------------------------------------------------------------------------
-- Upgrade arrows (bags and Quartermaster)
-------------------------------------------------------------------------------

local arrows = {} -- [button] = texture

local function Arrow(button)
    local a = arrows[button]
    if not a then
        a = ns.Overlay(button):CreateTexture(nil, "OVERLAY")
        a:SetTexture(ARROW_TEXTURE)
        a:SetWidth(16)
        a:SetHeight(16)
        a:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        a:Hide()
        arrows[button] = a
    end
    return a
end

local function SetArrow(button, show)
    if show then
        Arrow(button):Show()
    elseif arrows[button] then
        arrows[button]:Hide()
    end
end

-- True if the item would be an upgrade over what's equipped.
local function IsUpgrade(link, found, setBase, equippedCache)
    if not (link and SlotsFor(link)) then return false end
    local stats = ScanStats(link, found, setBase)
    if not stats or stats.unusable then return false end
    local cmp = Compare(stats, link, equippedCache)
    return cmp and (cmp.empty or cmp.score > cmp.otherScore + 0.05) or false
end

local function UpdateBagArrows()
    if not ns.BagsShown() then return end
    local equipped = {}
    ns.ForEachBagButton(function(button, bag, slot)
        local link = ns.db.arrows and GetContainerItemLink(bag, slot)
        local found = link and VanillaBonkUI and VanillaBonkUI.FoundAt and VanillaBonkUI.FoundAt(bag, slot)
        SetArrow(button, link and IsUpgrade(link, found, function(tip) tip:SetBagItem(bag, slot) end, equipped))
    end)
end

-- HoA's Quartermaster window draws its items as cards (frames with .item,
-- .slot and .price) that it reuses as you change tabs and pages, so while the
-- window is open we watch each card's item and update its arrow when it
-- changes. Cards on the Upgrade tab are your own pieces (HoA puts its own
-- arrow on those) and are skipped.

local epoch = 0         -- bumped on every refresh (gear or weight changes)
local cardSeen = {}     -- [card] = { item = item, epoch = n }
local qmElapsed = 0

local function CollectCards(f, out, depth)
    local children = { f:GetChildren() }
    for _, child in ipairs(children) do
        if type(child.slot) == "table" and type(child.price) == "table" and type(child.name) == "table" then
            table.insert(out, child)
        elseif depth > 0 then
            CollectCards(child, out, depth - 1)
        end
    end
end

local function UpdateQuartermasterArrows(force)
    local qmFrame = VanillaBonkQuartermasterFrame
    if not (qmFrame and qmFrame:IsShown() and qmFrame.GetChildren) then return end
    local cards = {}
    CollectCards(qmFrame, cards, 3)
    local equipped
    for _, card in ipairs(cards) do
        local item = card.item
        if type(item) ~= "table" then item = nil end
        local seen = cardSeen[card]
        if force or not seen or seen.item ~= item or seen.epoch ~= epoch then
            cardSeen[card] = { item = item, epoch = epoch }
            local upgrade = false
            if ns.db.arrows and item and card:IsShown() and not item.upgrade and item.usable ~= false then
                equipped = equipped or {}
                upgrade = type(item.link) == "string" and IsUpgrade(item.link, nil, nil, equipped)
            end
            SetArrow(card.slot, upgrade)
        end
    end
end

ns.OnRefresh(function()
    epoch = epoch + 1
    UpdateBagArrows()
    UpdateQuartermasterArrows()
end)

local qmWatcher = CreateFrame("Frame")
qmWatcher:SetScript("OnUpdate", function(self, elapsed)
    qmElapsed = qmElapsed + (elapsed or arg1 or 0)
    if qmElapsed < 0.2 then return end
    qmElapsed = 0
    if ns.db then UpdateQuartermasterArrows() end
end)

-------------------------------------------------------------------------------
-- Commands
-------------------------------------------------------------------------------

ns.Toggle("compare", "compare", "upgrade summary on tooltips")
ns.Toggle("diffs", "diffs", "per-stat differences on tooltips")
ns.Toggle("arrows", "arrows", "upgrade arrows (bags and Quartermaster)")

local gmatch = string.gmatch or string.gfind -- gfind on Lua 5.0

local ABBREVIATIONS = { dmg = "damage", hp = "health", ms = "movement", xp = "experience", exp = "experience" }

local function Words(text)
    local words = {}
    for w in gmatch(string.lower(text), "%S+") do table.insert(words, w) end
    return words
end

-- True if every typed word starts some word of the stat name, in order:
-- "crit chance" -> "Critical strike chance", "health" -> "Max health".
local function WordsMatch(typed, name)
    local nameWords = Words(name)
    local j = 1
    for _, w in ipairs(typed) do
        while nameWords[j] and string.find(nameWords[j], w, 1, true) ~= 1 do
            j = j + 1
        end
        if not nameWords[j] then return false end
        j = j + 1
    end
    return true
end

local function FindStat(text)
    BuildStatNames()
    local n = tonumber(text)
    if n then return n end
    if not statNames then return nil end
    if statIdByKey[string.lower(text)] then return statIdByKey[string.lower(text)] end
    local typed = Words(text)
    if not typed[1] then return nil end
    for i, w in ipairs(typed) do typed[i] = ABBREVIATIONS[w] or w end
    for id = 0, MAX_STAT_ID do
        local name = statNames[id]
        if name and WordsMatch(typed, name) then return id end
    end
    return nil
end

local function ListWeights()
    BuildStatNames()
    if not statNames then
        ns.Print("stat names not available yet - is the HoA UI addon loaded?")
        return
    end
    ns.Print("stat weights (score per point):")
    for id = 0, MAX_STAT_ID do
        if statNames[id] then
            local custom = ns.db.weights[id] and " |cffffd100(custom)|r" or ""
            ns.Print("  " .. statNames[id] .. ": " .. ns.Weight(id) .. custom)
        end
    end
end

ns.Command("weights", function()
    ListWeights()
    return true
end, function() return "/hbg weights - list stat weights" end)

ns.Command("weight", function(rest)
    if rest == "reset" then
        ns.db.weights = {}
        ns.Print("stat weights reset to defaults")
        return
    end
    -- "<stat name> <number>"; the name can have spaces
    local _, _, statText, num = string.find(rest, "^(.-)%s+(%-?[%d%.]+)$")
    local value = tonumber(num or "")
    local id = statText and FindStat(statText)
    if not (id and value) then
        ns.Print("usage: /hbg weight <stat> <number>, e.g. /hbg weight crit chance 1.5")
        ns.Print("       /hbg weight reset")
        return true
    end
    ns.db.weights[id] = value
    ns.Print((statNames and statNames[id] or ("stat " .. id)) .. " weight set to " .. value)
end, function() return "/hbg weight <stat> <number> - set a stat weight (/hbg weight reset)" end)

ns.Command("debug", function()
    if not VanillaBonkUI then
        ns.Print("Hordes of Azeroth UI addon (VanillaBonkUI) not found.")
        return true
    end
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local tier, source = ns.GetItemTier("inv", slot, link)
            local stats = EquippedStats(slot)
            ns.Print("slot " .. slot .. " id " .. tostring(ns.ItemIdFromLink(link))
                .. ": tier " .. tostring(tier) .. " (" .. source .. "), "
                .. (stats and stats.count or 0) .. " stat lines, score "
                .. Round1(stats and ns.Score(stats) or 0) .. "  " .. ns.Escape(link))
        end
    end
    return true
end, function() return "/hbg debug - list tier, stats and score of equipped items" end)
