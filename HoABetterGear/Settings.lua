-- HoA Better Gear - settings window (/hbg, or right-click the stats button
-- on the character pane).
--
-- Every setting the slash commands have, as checkboxes, sliders and
-- buttons, plus the stat weights. Built the first time it's opened, in HoA's
-- own window style when the HoA UI addon is there. Changes apply at once,
-- through the same functions the slash commands use.

local ns = HoABetterGear

local WIDTH, HEIGHT = 580, 600 -- height is fitted to the contents
local COLUMN = { 24, 300 }      -- x of the two columns
local ROW = 22                  -- checkbox row height
local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local ANCHOR_ORDER = { "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "TOPLEFT", "TOP", "TOPRIGHT", "CENTER" }
local ANCHOR_NAMES = {
    BOTTOMRIGHT = "Bottom right", BOTTOM = "Bottom", BOTTOMLEFT = "Bottom left",
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", CENTER = "Center",
}

local mod = math.mod or math.fmod -- math.mod on the 1.12 client

local function Count(t)
    local n = 0
    for _ in ipairs(t) do n = n + 1 end
    return n
end

local frame
local controls = {}   -- each has :sync() to show the current setting
local syncing = false
local count = 0

local function NextName()
    count = count + 1
    return "HoABetterGearOption" .. count
end

-- Re-apply everything after a change (cheap: a refresh of what's on screen).
local function Apply()
    if ns.Restyle then ns.Restyle() end
    if ns.ApplyStatsButton then ns.ApplyStatsButton() end
    if ns.ApplyStatsAlpha then ns.ApplyStatsAlpha() end
    ns.Refresh()
end

local function SyncAll()
    syncing = true
    for _, c in ipairs(controls) do c.sync() end
    syncing = false
end

local function Tooltip(owner, title, text)
    owner:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, 1, 0.82, 0, 1) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

local function Header(parent, column, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN[column], y)
    label:SetText(text)
    if VanillaBonkUI and VanillaBonkUI.Divider then
        local line = VanillaBonkUI.Divider(parent, 250)
        line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    end
    return y - 22
end

-- A checkbox for a true/false setting. get() / set(value); after() runs
-- after the change (on top of the usual refresh).
local function Check(parent, column, y, label, tip, get, set, after)
    local cb = CreateFrame("CheckButton", NextName(), parent, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN[column] - 4, y + 2)
    local text = getglobal(cb:GetName() .. "Text")
    if text then
        text:SetText(label)
        text:SetFontObject(GameFontHighlightSmall)
    end
    cb:SetScript("OnClick", function()
        set(this:GetChecked() and true or false)
        if after then after() end
        Apply()
    end)
    Tooltip(cb, label, tip)
    table.insert(controls, { sync = function() cb:SetChecked(get() and 1 or nil) end })
    return y - ROW
end

-- A setting stored in ns.db.
local function DbCheck(parent, column, y, key, label, tip, after)
    return Check(parent, column, y, label, tip,
        function() return ns.db[key] end,
        function(v) ns.db[key] = v end, after)
end

-- A slider. format(value) gives the text shown above it.
local function Slider(parent, column, y, label, low, high, step, get, set, format, lowText, highText)
    local name = NextName()
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(220)
    s:SetHeight(16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN[column] + 4, y - 14)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    local text = getglobal(name .. "Text")
    local lowLabel = getglobal(name .. "Low")
    local highLabel = getglobal(name .. "High")
    if lowLabel then lowLabel:SetText(lowText or low) end
    if highLabel then highLabel:SetText(highText or high) end
    local function Label(v)
        if text then text:SetText(label .. ": |cffffffff" .. format(v) .. "|r") end
    end
    s:SetScript("OnValueChanged", function()
        local v = math.floor(this:GetValue() / step + 0.5) * step
        Label(v)
        if syncing then return end
        set(v)
        Apply()
    end)
    table.insert(controls, { sync = function()
        local v = get()
        s:SetValue(v)
        Label(v)
    end })
    return y - 44
end

local function Button(parent, column, y, width, text, onClick, x)
    local b
    if VanillaBonkUI and VanillaBonkUI.Button then
        b = VanillaBonkUI.Button(parent, width, text, onClick)
    else
        b = CreateFrame("Button", NextName(), parent, "UIPanelButtonTemplate")
        b:SetWidth(width)
        b:SetHeight(22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
    end
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN[column] + (x or 0), y)
    return b
end

-------------------------------------------------------------------------------
-- Sections
-------------------------------------------------------------------------------

local function ItemLevelSection(f, y)
    y = Header(f, 1, y, "Item levels")
    y = DbCheck(f, 1, y, "tier", "Show item levels on icons",
        "The item's level, worked out like HoA's tooltip, on the character pane, bags, bank and vault.")
    y = DbCheck(f, 1, y, "bags", "...on bag and bank items too")
    y = DbCheck(f, 1, y, "colorTier", "Color them by rarity",
        "Off: the gold of the tooltip's \"ilvl\" text.")
    y = DbCheck(f, 1, y, "avgIlvl", "Average item level on the character pane",
        "Shown just above Power. Empty slots that need gear count as 0; a two-hander counts twice.")
    local position = Button(f, 1, y - 2, 220, "", function()
        local i = 1
        for n, a in ipairs(ANCHOR_ORDER) do
            if a == ns.db.anchor then i = n end
        end
        ns.db.anchor = ANCHOR_ORDER[mod(i, Count(ANCHOR_ORDER)) + 1]
        SyncAll()
        Apply()
    end)
    Tooltip(position, "Item level position", "Click to move the number to the next corner of the icon.")
    table.insert(controls, { sync = function()
        position:SetText("Position: " .. (ANCHOR_NAMES[ns.db.anchor] or ns.db.anchor))
    end })
    y = y - 30
    y = Slider(f, 1, y, "Text size", 8, 24, 1,
        function() return ns.db.fontSize end,
        function(v) ns.db.fontSize = v end,
        function(v) return v end)
    return y
end

local function GlowSection(f, y)
    y = Header(f, 1, y, "Glows")
    y = DbCheck(f, 1, y, "glow", "Quality glow (character pane and bank)")
    y = Slider(f, 1, y, "Glow from quality", 0, 5, 1,
        function() return ns.db.minQuality end,
        function(v) ns.db.minQuality = v end,
        function(v) return QUALITY_NAMES[v] or v end, "Poor", "Legendary")
    y = DbCheck(f, 1, y, "emptyGlow", "Red glow on empty slots",
        "Skips shirt, tabard, ammo and slots your class can't use; the off hand only next to a one-handed weapon.")
    return y
end

local function CompareSection(f, y)
    y = Header(f, 1, y, "Gear comparison")
    y = DbCheck(f, 1, y, "compare", "Better Gear section on tooltips")
    y = DbCheck(f, 1, y, "diffs", "Stat differences and scores")
    y = DbCheck(f, 1, y, "arrows", "Upgrade arrows",
        "Bags, bank, Quartermaster and the loot window.")
    return y
end

local function FigureSection(f, y)
    y = Header(f, 2, y, "Durability figure")
    y = DbCheck(f, 2, y, "figure", "Show missing gear in red",
        "Also adds the necklace, rings, trinkets and cloak to the figure.")
    local move = Button(f, 2, y - 2, 120, "", function()
        if ns.SetFigureUnlocked then ns.SetFigureUnlocked(not ns.FigureUnlocked()) end
        SyncAll()
    end)
    Tooltip(move, "Move the figure", "Unlock it, drag it where you want, then lock it again.")
    table.insert(controls, { sync = function()
        move:SetText(ns.FigureUnlocked and ns.FigureUnlocked() and "Lock" or "Unlock to move")
    end })
    Button(f, 2, y - 2, 110, "Reset position", function()
        if ns.ResetFigurePosition then ns.ResetFigurePosition() end
        SyncAll()
    end, 126)
    return y - 32
end

local function ShieldSection(f, y)
    y = Header(f, 2, y, "Shield")
    y = DbCheck(f, 2, y, "shield", "Shield amount on the player frame")
    y = DbCheck(f, 2, y, "shieldPct", "...with its % of max health")
    return y
end

local function StatsSection(f, y)
    y = Header(f, 2, y, "Live stats window")
    y = Check(f, 2, y, "Show the stats window", "Your character pane stats, updating live during a run.",
        function() return ns.StatsWindowShown and ns.StatsWindowShown() end,
        function(v) if ns.SetStatsWindowShown then ns.SetStatsWindowShown(v) end end)
    y = DbCheck(f, 2, y, "statsButton", "Pop-out button on the character pane")
    local colors = Button(f, 2, y - 2, 236, "", function()
        local nextMode = { value = "run", run = "off", off = "value" }
        ns.db.statColors = nextMode[ns.db.statColors] or "value"
        SyncAll()
        Apply()
    end)
    Tooltip(colors, "Stat colors (click to change)",
        "By value: every stat by its own value, in and out of runs - e.g. Crit purple above 100%, orange at 200%; Armor, Dodge, Speed towards their caps; Power orange above 1500%; Luck orange above 60.\n\n"
        .. "By run growth: during a run, by how much each stat has grown since it started (green +5%, blue +15%, purple +30%, orange when capped); white outside runs.\n\nOff: all white.")
    table.insert(controls, { sync = function()
        local names = { value = "By value", run = "By run growth", off = "Off" }
        colors:SetText("Stat colors: " .. (names[ns.db.statColors] or "By value"))
    end })
    y = y - 30
    y = Slider(f, 2, y, "Background opacity", 0, 100, 5,
        function() return math.floor(ns.db.statsAlpha * 100 + 0.5) end,
        function(v) ns.db.statsAlpha = v / 100 end,
        function(v) return v .. "%" end, "0%", "100%")
    Button(f, 2, y - 2, 110, "Reset position", function()
        if ns.ResetStatsPosition then ns.ResetStatsPosition() end
    end)
    return y - 32
end

-- HoA's own short names (its stats panel uses these), so labels fit.
local SHORT_NAMES = {
    ["Critical strike chance"] = "Crit chance", ["Critical strike damage"] = "Crit damage",
    ["Dodge chance"] = "Dodge", ["Movement speed"] = "Speed", ["Poison damage"] = "Poison dmg",
}
local function ShortStatName(name)
    return SHORT_NAMES[name] or name
end

-- One small box per stat; Enter or clicking away saves it.
local function WeightsSection(f, y)
    y = Header(f, 1, y, "Stat weights")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", COLUMN[1], y)
    hint:SetText("Score points per point of each stat. The comparison and arrows use these.")
    y = y - 16
    local list = ns.StatList and ns.StatList() or {}
    if not list[1] then
        local none = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        none:SetPoint("TOPLEFT", f, "TOPLEFT", COLUMN[1], y)
        none:SetText("Stat names aren't available yet (is the Hordes of Azeroth UI loaded?).")
        return y - 20
    end
    local perRow, cellWidth = 4, 132
    for i, stat in ipairs(list) do
        local col = mod(i - 1, perRow)
        local row = math.floor((i - 1) / perRow)
        local x = COLUMN[1] + col * cellWidth
        local cy = y - row * 22
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", x, cy - 4)
        label:SetWidth(84)
        label:SetJustifyH("LEFT")
        label:SetText(ShortStatName(stat.name))
        local box = CreateFrame("EditBox", NextName(), f, "InputBoxTemplate")
        box:SetWidth(36)
        box:SetHeight(18)
        box:SetAutoFocus(false)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", x + 88, cy)
        local id = stat.id
        local function Show()
            local w = ns.Weight(id)
            local shown = string.gsub(string.format("%.2f", w), "%.?0+$", "")
            box:SetText(shown)
            if ns.db.weights[id] then
                box:SetTextColor(1, 0.82, 0) -- changed from the default
            else
                box:SetTextColor(1, 1, 1)
            end
        end
        local function Save()
            local v = tonumber(box:GetText())
            if v then
                ns.SetWeight(id, v)
                Apply()
            end
            Show()
        end
        box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        box:SetScript("OnEscapePressed", function() Show(); this:ClearFocus() end)
        box:SetScript("OnEditFocusLost", Save)
        Tooltip(box, stat.name, "Default " .. (ns.DEFAULT_WEIGHTS[id] or 0.5) .. ". Gold = changed.")
        table.insert(controls, { sync = Show })
    end
    local rows = math.ceil(Count(list) / perRow)
    y = y - rows * 22 - 4
    Button(f, 1, y, 150, "Reset stat weights", function()
        ns.db.weights = {}
        SyncAll()
        Apply()
    end)
    return y - 28
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local function CreateSettings()
    local ui = VanillaBonkUI
    if ui and ui.GoldWindow then
        frame = ui.GoldWindow("HoABetterGearSettings", WIDTH, HEIGHT)
        frame.title:SetText("HoA Better Gear")
    else
        frame = CreateFrame("Frame", "HoABetterGearSettings", UIParent)
        frame:SetWidth(WIDTH)
        frame:SetHeight(HEIGHT)
        frame:SetFrameStrata("DIALOG")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function() this:StartMoving() end)
        frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", 0, -16)
        title:SetText("HoA Better Gear")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        tinsert(UISpecialFrames, "HoABetterGearSettings") -- Escape closes it
        frame:Hide()
    end
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)

    local left = -40
    left = ItemLevelSection(frame, left)
    left = GlowSection(frame, left - 6)
    left = CompareSection(frame, left - 6)

    local right = -40
    right = FigureSection(frame, right)
    right = ShieldSection(frame, right - 6)
    right = StatsSection(frame, right - 6)

    local bottom = math.min(left, right) - 8
    bottom = WeightsSection(frame, bottom)
    -- WeightsSection ends with its reset button's row; put this beside it.
    local buttonRow = bottom + 28
    local defaults = Button(frame, 2, buttonRow, 150, "Restore defaults", function()
        local weights, baseline, inRun = ns.db.weights, ns.db.runBaseline, ns.db.runInRun
        for k in pairs(ns.db) do ns.db[k] = nil end
        for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
        ns.db.weights = weights
        ns.db.runBaseline, ns.db.runInRun = baseline, inRun -- keep the current run's start
        ns.db.settingsVersion = 3
        if ns.ResetStatsPosition then ns.ResetStatsPosition() end
        SyncAll()
        Apply()
        ns.Print("settings restored to defaults (stat weights kept)")
    end, 106)
    Tooltip(defaults, "Restore defaults", "Every setting back to how it started. Your stat weights are kept.")

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", frame, "TOPLEFT", COLUMN[1], bottom - 2)
    help:SetText("/hbg help lists the chat commands.")

    -- fit the window to its contents
    frame:SetHeight(-bottom + 34)

    frame:SetScript("OnShow", SyncAll)
end

function ns.OpenSettings()
    if not ns.db then return end
    if not frame then CreateSettings() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        SyncAll()
    end
end
