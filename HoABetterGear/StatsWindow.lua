-- HoA Better Gear - pop-out window with the character pane's hero stats,
-- updating live during a run.
--
-- How HoA does it: opening the character pane sends ".bonk stats on", and
-- the server then streams your run stats as "BONK~stats~..." messages until
-- the pane closes (".bonk stats off"). HoA adds your gear totals and draws
-- the result in its VanillaBonkHeroStats panel - but only refreshes while
-- PaperDollFrame:IsVisible().
--
-- This window keeps that stream on while it's open, lets HoA's panel keep
-- refreshing (PaperDollFrame:IsVisible() also answers yes while this window
-- is shown), and mirrors the panel's labels, values and hover tooltips. So
-- the numbers are HoA's own, with its caps and curves.

local ns = HoABetterGear

local ROW_HEIGHT = 13
local COLUMN_WIDTH = 112
local PADDING = 10
local TITLE_HEIGHT = 20

local window
local rows = {}
local isVisible -- PaperDollFrame's own IsVisible
local elapsedSince = 0

local function PaneReallyVisible()
    return PaperDollFrame and isVisible and isVisible(PaperDollFrame)
end

local function StatsOn()
    SendChatMessage(".bonk stats on", "SAY")
end

local function StatsOff()
    SendChatMessage(".bonk stats off", "SAY")
end

-- HoA's stat lines: frames with .label and .value inside VanillaBonkHeroStats,
-- in the order HoA created them (first column, then second).
local function SourceLines()
    local panel = VanillaBonkHeroStats
    if not (panel and panel.GetChildren) then return {} end
    local lines = {}
    local children = { panel:GetChildren() }
    for _, child in ipairs(children) do
        if type(child.label) == "table" and type(child.value) == "table" then
            table.insert(lines, child)
        end
    end
    return lines
end

local function Row(i, perColumn)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, window)
    row:SetWidth(COLUMN_WIDTH - 6)
    row:SetHeight(ROW_HEIGHT)
    local column = i <= perColumn and 0 or 1
    local index = i <= perColumn and i or i - perColumn
    row:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING + column * COLUMN_WIDTH,
        -(TITLE_HEIGHT + 4 + (index - 1) * ROW_HEIGHT))
    row:EnableMouse(true)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    -- the same tooltip HoA shows on its own stat lines
    row:SetScript("OnEnter", function()
        local src = this.source
        if not src then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(src.title or "", 1, 1, 1)
        for _, text in ipairs(src.lines or {}) do
            GameTooltip:AddLine(text, 1, 0.82, 0, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

-- Copy HoA's current labels and values into the window.
local function Mirror()
    local lines = SourceLines()
    local count = 0
    for _ in ipairs(lines) do count = count + 1 end
    local perColumn = math.ceil(count / 2)
    for i, line in ipairs(lines) do
        local row = Row(i, perColumn)
        row.label:SetText(line.label:GetText() or "")
        row.value:SetText(line.value:GetText() or "")
        row.source = line
        row:Show()
    end
    window:SetHeight(TITLE_HEIGHT + 4 + math.max(perColumn, 1) * ROW_HEIGHT + PADDING)
    if count == 0 then
        window.empty:Show()
    else
        window.empty:Hide()
    end
end

local function Refresh()
    -- HoA's public hook that re-runs its stats panel (it checks
    -- PaperDollFrame:IsVisible(), which is true while this window is open).
    if VanillaBonkUI and VanillaBonkUI.FoundRefreshed then
        VanillaBonkUI.FoundRefreshed()
    end
    Mirror()
end

local function ApplyPosition()
    window:ClearAllPoints()
    local pos = ns.db.statsPos
    if pos then
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -180)
    end
end

local function CreateWindow()
    window = CreateFrame("Frame", "HoABetterGearStatsWindow", UIParent)
    window:SetWidth(PADDING * 2 + COLUMN_WIDTH * 2 - 6)
    window:SetHeight(110)
    window:SetFrameStrata("MEDIUM")
    window:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    window:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
    window:SetBackdropBorderColor(0.6, 0.55, 0.45, 1)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function() this:StartMoving() end)
    window:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        ns.db.statsPos = { x = this:GetLeft(), y = this:GetTop() }
        ApplyPosition()
    end)

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING, -7)
    window.title:SetText("Hero Stats")

    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetWidth(24)
    window.close:SetHeight(24)
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    window.close:SetScript("OnClick", function()
        ns.db.statsShown = false
        window:Hide()
    end)

    window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.empty:SetPoint("CENTER", window, "CENTER", 0, -6)
    window.empty:SetText("Hordes of Azeroth stats not found")
    window.empty:Hide()

    window:SetScript("OnShow", function()
        if not PaneReallyVisible() then StatsOn() end
        Refresh()
    end)
    window:SetScript("OnHide", function()
        if not PaneReallyVisible() then StatsOff() end
    end)
    -- mirror a few times a second; HoA refreshes on every stats message
    window:SetScript("OnUpdate", function()
        elapsedSince = elapsedSince + (arg1 or 0)
        if elapsedSince < 0.2 then return end
        elapsedSince = 0
        Mirror()
    end)

    window:Hide()
    ApplyPosition()
end

local function ToggleWindow()
    ns.db.statsShown = not window:IsShown()
    if ns.db.statsShown then window:Show() else window:Hide() end
end

-- A small pop-out button on the character pane, just above the top-right of
-- HoA's stats block (over the bottom-right corner of the character model).
local function CreateButton()
    local button = CreateFrame("Button", "HoABetterGearStatsButton", PaperDollFrame)
    button:SetWidth(16)
    button:SetHeight(16)
    if VanillaBonkHeroStats then
        button:SetPoint("BOTTOMRIGHT", VanillaBonkHeroStats, "TOPRIGHT", -2, 2)
    else
        button:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", 280, -272)
    end
    -- above the character model, which would otherwise take the clicks
    button:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 10)
    button:SetNormalTexture("Interface\\AddOns\\HoABetterGear\\PopOutButton")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetBlendMode("ADD") end
    button:SetScript("OnClick", function()
        ToggleWindow()
        -- refresh the tooltip's "open"/"close" wording
        if GameTooltip.IsOwned and GameTooltip:IsOwned(this) then this:GetScript("OnEnter")() end
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Live stats window", 1, 1, 1)
        GameTooltip:AddLine(window:IsShown() and "Click to close it." or "Click to pop these stats out into a window that updates during your run.", 1, 0.82, 0, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if not ns.db.statsButton then button:Hide() end
    return button
end

local function Setup()
    if not PaperDollFrame then return end
    CreateWindow()
    ns.statsButton = CreateButton()

    -- Let HoA keep its stats panel up to date while this window is open.
    isVisible = PaperDollFrame.IsVisible
    PaperDollFrame.IsVisible = function(self)
        if window and window:IsShown() then return 1 end
        return isVisible(self)
    end

    -- Closing the character pane turns HoA's stats stream off; keep it on
    -- while this window is open. (Runs after HoA's own OnHide.)
    local onHide = PaperDollFrame:GetScript("OnHide")
    PaperDollFrame:SetScript("OnHide", function(a1, a2)
        if onHide then onHide(a1, a2) end
        if window:IsShown() then StatsOn() end
    end)
end

ns.OnLoad(Setup)

-- Reopen the window after logging in (not earlier: the stats request is a
-- chat command), and ask again after zoning, e.g. into a run.
ns.On("PLAYER_ENTERING_WORLD", function()
    if not window then return end
    if window:IsShown() then
        StatsOn()
        Refresh()
    elseif ns.db.statsShown then
        window:Show()
    end
end)

ns.Command("stats", function(rest)
    if not window then
        ns.Print("stats window not available")
        return true
    end
    if rest == "reset" then
        ns.db.statsPos = nil
        ApplyPosition()
        ns.Print("stats window moved back to its default place")
        return true
    end
    if rest == "button" then
        ns.db.statsButton = not ns.db.statsButton
        if ns.db.statsButton then ns.statsButton:Show() else ns.statsButton:Hide() end
        ns.Print("stats button on the character pane " .. ns.OnOff(ns.db.statsButton))
        return true
    end
    ToggleWindow()
    return true
end, function()
    return "/hbg stats - show/hide the live hero stats window (drag to move; /hbg stats reset; /hbg stats button hides the character pane button)"
end)
