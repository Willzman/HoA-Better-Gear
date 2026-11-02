-- HoA Better Gear - shared core: settings, helpers, events, slash commands.
--
-- Written for the 1.12.1 client (Lua 5.0): no '#', select(), string.match,
-- '...' varargs or hooksecurefunc. Event handlers also accept the
-- (self, event, arg1) params used by newer clients.

HoABetterGear = {}
local ns = HoABetterGear

ns.ADDON = "HoABetterGear"
ns.BAGS = { 0, 1, 2, 3, 4 } -- the bags HoA's bag window shows

ns.DEFAULTS = {
    -- item levels / glow
    glow       = true,          -- quality glow on the character frame
    emptyGlow  = true,          -- red glow on empty character slots that need gear
    figure     = true,          -- show missing gear on the durability figure
    tier       = true,          -- item level numbers
    bags       = true,          -- item levels on bag and bank items
    minQuality = 2,             -- 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary
    anchor     = "BOTTOMRIGHT", -- where the item level sits on the icon
    colorTier  = true,          -- color the item level by rarity (else tooltip gold)
    glowAlpha  = 0.85,
    fontSize   = 13,
    -- comparison
    compare    = true,          -- upgrade summary on gear tooltips
    diffs      = true,          -- per-stat differences under the summary
    arrows     = true,          -- green arrow on bag items that are upgrades
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

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99HoA Better Gear|r: " .. msg)
end

function ns.OnOff(value)
    return value and "on" or "off"
end

function ns.ItemIdFromLink(link)
    local _, _, id = string.find(link or "", "item:(%d+)")
    return tonumber(id)
end

function ns.GetQualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    c = QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Color straight from an item link: "|cffRRGGBB|Hitem:..." -> r, g, b, quality
function ns.ColorFromLink(link)
    local _, _, hex = string.find(link or "", "|c%x%x(%x%x%x%x%x%x)")
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

function ns.StripCodes(text)
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return text
end

function ns.Escape(text)
    if type(text) ~= "string" then return "" end
    return (string.gsub(text, "|", "||"))
end

-- One overlay frame per item button, shared by the item level and the
-- upgrade arrow, drawn above the button's own glow and cooldown.
local overlays = {}
function ns.Overlay(button)
    local o = overlays[button]
    if not o then
        o = CreateFrame("Frame", nil, button)
        o:SetAllPoints(button)
        o:SetFrameLevel(button:GetFrameLevel() + 5)
        overlays[button] = o
    end
    return o
end

-- Calls fn(button, bag, slot) for every item button in HoA's bag window.
-- HoA creates them lazily, named VanillaBonkBagsItem<bag>_<slot>.
function ns.ForEachBagButton(fn)
    for _, bag in ipairs(ns.BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            local button = getglobal("VanillaBonkBagsItem" .. bag .. "_" .. slot)
            if button then fn(button, bag, slot) end
        end
    end
end

function ns.BagsShown()
    return VanillaBonkBags and VanillaBonkBags:IsShown()
end

ns.BANK_CONTAINER = BANK_CONTAINER or -1

-- Calls fn(button, bag, slot) for every item button in the (standard) bank
-- window: the main bank slots BankFrameItem1..24 (bag -1), and bank bags
-- opened as ContainerFrameN (bags 5-10; HoA handles bags 0-4 itself).
function ns.ForEachBankButton(fn)
    if BankFrame and BankFrame:IsShown() then
        for i = 1, NUM_BANKGENERIC_SLOTS or 24 do
            local button = getglobal("BankFrameItem" .. i)
            if button then fn(button, ns.BANK_CONTAINER, button:GetID()) end
        end
    end
    for i = 1, NUM_CONTAINER_FRAMES or 12 do
        local frame = getglobal("ContainerFrame" .. i)
        if frame and frame:IsShown() then
            local bag = frame:GetID()
            if bag and bag > 4 then
                for j = 1, GetContainerNumSlots(bag) do
                    local button = getglobal("ContainerFrame" .. i .. "Item" .. j)
                    if button then fn(button, bag, button:GetID()) end
                end
            end
        end
    end
end

-- Every bag and bank item button that's currently on screen.
function ns.ForEachItemButton(fn)
    if ns.BagsShown() then ns.ForEachBagButton(fn) end
    ns.ForEachBankButton(fn)
end

-- Shows the item's standard tooltip on 'tip' (used to check usability).
function ns.SetItemTooltip(tip, bag, slot)
    if bag == ns.BANK_CONTAINER then
        if BankButtonIDToInvSlotID then
            tip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
        end
    else
        tip:SetBagItem(bag, slot)
    end
end

-------------------------------------------------------------------------------
-- Events, load hooks and refresh scheduling
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
local loaders = {}
local refreshers = {}
local refreshIn = nil

function ns.On(ev, fn)
    if not handlers[ev] then
        handlers[ev] = {}
        frame:RegisterEvent(ev)
    end
    table.insert(handlers[ev], fn)
end

-- fn() runs once saved variables are ready.
function ns.OnLoad(fn)
    table.insert(loaders, fn)
end

-- fn() runs on every (debounced) refresh.
function ns.OnRefresh(fn)
    table.insert(refreshers, fn)
end

function ns.Refresh()
    if not ns.db then return end
    for _, fn in ipairs(refreshers) do fn() end
end

-- Short delay lets HoA's own handlers (which may run after ours) finish.
function ns.ScheduleRefresh()
    refreshIn = 0.1
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, ev, a1)
    ev = ev or event
    a1 = a1 or arg1
    if ev == "ADDON_LOADED" then
        if a1 ~= ns.ADDON then return end
        HoABetterGearDB = HoABetterGearDB or {}
        local db = HoABetterGearDB
        for k, v in pairs(ns.DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.weights = db.weights or {}
        -- v2.1: tier numbers default to the tooltip's gold instead of quality color
        if (db.settingsVersion or 0) < 1 then
            db.colorTier = false
            db.settingsVersion = 1
        end
        -- v4.0: item levels instead of tiers, colored by rarity by default
        if db.settingsVersion < 2 then
            db.colorTier = true
            db.prefix = nil
            db.settingsVersion = 2
        end
        ns.db = db
        for _, fn in ipairs(loaders) do fn() end
        return
    end
    local list = handlers[ev]
    if list then
        for _, fn in ipairs(list) do fn(a1) end
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not refreshIn then return end
    refreshIn = refreshIn - (elapsed or arg1 or 0)
    if refreshIn > 0 then return end
    refreshIn = nil
    ns.Refresh()
end)

ns.On("PLAYER_ENTERING_WORLD", ns.ScheduleRefresh)
ns.On("BAG_UPDATE", ns.ScheduleRefresh)
ns.On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then ns.ScheduleRefresh() end
end)
-- HoA sends gear data as "BONK~..." system messages: item stats at login
-- ("gear", "tierstats", "set") and rolled-gear data ending in "foundend".
ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not msg or string.sub(msg, 1, 5) ~= "BONK~" then return end
    local kind = string.sub(msg, 6, 13)
    if kind == "foundend" or string.sub(kind, 1, 4) == "gear"
        or string.sub(kind, 1, 4) == "tier" or string.sub(kind, 1, 3) == "set" then
        ns.ScheduleRefresh()
    end
end)

-- Refresh whenever the given frame is shown (a child's OnShow fires when
-- its parent is shown).
function ns.RefreshOnShow(parent)
    if not parent then return end
    local watcher = CreateFrame("Frame", nil, parent)
    watcher:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.RefreshSoonOnShow(parent)
    if not parent then return end
    local watcher = CreateFrame("Frame", nil, parent)
    watcher:SetScript("OnShow", function() ns.ScheduleRefresh() end)
end

ns.OnLoad(function()
    ns.RefreshOnShow(PaperDollFrame)
    ns.RefreshOnShow(VanillaBonkBags)
    -- The bank and bank bags fill their buttons when shown, so refresh just
    -- after that.
    ns.RefreshSoonOnShow(BankFrame)
    for i = 1, NUM_CONTAINER_FRAMES or 12 do
        ns.RefreshSoonOnShow(getglobal("ContainerFrame" .. i))
    end
end)
ns.On("PLAYERBANKSLOTS_CHANGED", ns.ScheduleRefresh)
ns.On("BANKFRAME_OPENED", ns.ScheduleRefresh)

-------------------------------------------------------------------------------
-- Slash commands: modules register with ns.Command(name, fn, help)
-------------------------------------------------------------------------------

local commands = {}
local commandOrder = {}

-- fn(rest) returns true to skip the refresh afterwards.
-- help is a function returning the help text (so it can show current values).
function ns.Command(name, fn, help)
    commands[name] = fn
    table.insert(commandOrder, { name = name, help = help })
end

local function ShowHelp()
    ns.Print("commands (/bettergear or /hbg):")
    for _, c in ipairs(commandOrder) do
        if c.help then ns.Print(c.help()) end
    end
end

SLASH_HOABETTERGEAR1 = "/bettergear"
SLASH_HOABETTERGEAR2 = "/hbg"
SlashCmdList["HOABETTERGEAR"] = function(msg)
    if not ns.db then return end
    msg = string.lower(msg or "")
    local _, _, cmd, rest = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd or ""]
    if not fn then
        ShowHelp()
        return
    end
    if not fn(rest or "") then
        ns.Refresh()
    end
end

-- Simple on/off toggles
local function Toggle(key, name, label)
    ns.Command(name, function()
        ns.db[key] = not ns.db[key]
        ns.Print(label .. " " .. ns.OnOff(ns.db[key]))
    end, function()
        return "/hbg " .. name .. " - toggle " .. label .. " (" .. ns.OnOff(ns.db[key]) .. ")"
    end)
end
ns.Toggle = Toggle

ns.Command("reset", function()
    local weights = ns.db.weights
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    ns.db.weights = weights
    if ns.Restyle then ns.Restyle() end
    ns.Print("settings reset (stat weights kept - use /hbg weight reset)")
end, function() return "/hbg reset - restore default settings" end)
