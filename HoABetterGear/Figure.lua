-- HoA Better Gear - missing gear on the durability figure, and moving it.
--
-- WoW's durability figure (DurabilityFrame, the little armored man under the
-- minimap) shows damaged gear yellow and broken gear red. This also shows
-- gear you're missing in red, using the same rules as the red empty-slot
-- glow (no shirt/tabard, no slots your class can't use, off hand only next
-- to a one-handed weapon). The figure has no parts for neck, back, rings or
-- trinkets, so those can't show here.
--
-- Based on the 1.12 FrameXML: DurabilityFrame_SetAlerts() colors the parts
-- named "Durability" .. INVENTORY_ALERT_STATUS_SLOTS[i].slot; body parts
-- only show when one of them has an alert, weapon parts ("showSeparate")
-- show on their own. UIParent_ManageFramePositions() re-anchors the frame
-- under the minimap with SetPoint whenever the layout changes.

local ns = HoABetterGear

local BROKEN = { r = 0.93, g = 0.07, b = 0.07 } -- the game's "broken" red

-- Figure part -> character slot
local PART_SLOTS = {
    Head = "HeadSlot", Shoulders = "ShoulderSlot", Chest = "ChestSlot",
    Waist = "WaistSlot", Legs = "LegsSlot", Feet = "FeetSlot",
    Wrists = "WristSlot", Hands = "HandsSlot",
    Weapon = "MainHandSlot", Shield = "SecondaryHandSlot", Ranged = "RangedSlot",
}
local BODY_PARTS = { "Head", "Shoulders", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands" }
local WEAPON_PARTS = { "Weapon", "Shield", "Ranged" }

local unlocked = false
local originalSetPoint

local function Part(name)
    return getglobal("Durability" .. name)
end

local function SlotEmpty(slotName)
    return not GetInventoryItemLink("player", GetInventorySlotInfo(slotName))
end

local function MissingGear(part)
    local slotName = PART_SLOTS[part]
    return slotName and SlotEmpty(slotName) and ns.SlotNeedsGear and ns.SlotNeedsGear(slotName)
end

-- Runs right after the game's DurabilityFrame_SetAlerts.
local function ShowMissing()
    if not (ns.db and DurabilityFrame) then return end

    if unlocked then
        -- While moving it, show the whole figure so there's something to drag.
        for _, part in ipairs(BODY_PARTS) do
            local t = Part(part)
            if t then t:Show() end
        end
        DurabilityFrame:Show()
        return
    end
    if not ns.db.figure then return end

    local anyBody, any = false, false
    for _, part in ipairs(BODY_PARTS) do
        if MissingGear(part) then
            local t = Part(part)
            if t then
                t:SetVertexColor(BROKEN.r, BROKEN.g, BROKEN.b, 1)
                anyBody, any = true, true
            end
        end
    end
    -- Body parts show all together (the rest dimmed white), like the game does.
    if anyBody then
        for _, part in ipairs(BODY_PARTS) do
            local t = Part(part)
            if t then t:Show() end
        end
    end
    for _, part in ipairs(WEAPON_PARTS) do
        if MissingGear(part) then
            -- An empty off hand is drawn as the shield (the game picks the
            -- shield or off-hand weapon picture from what's equipped).
            local t = Part(part)
            if t then
                if part == "Shield" and DurabilityOffWeapon then DurabilityOffWeapon:Hide() end
                t:SetVertexColor(BROKEN.r, BROKEN.g, BROKEN.b, 1)
                t:Show()
                any = true
            end
        end
    end
    if any then
        DurabilityFrame:Show()
    end
end

local function Redraw()
    if DurabilityFrame_SetAlerts then
        DurabilityFrame_SetAlerts() -- the game's update, then ours (hooked below)
    else
        ShowMissing()
    end
    -- (The figure's own OnShow re-lays out the right side of the screen.)
end

-------------------------------------------------------------------------------
-- Position
-------------------------------------------------------------------------------

-- Once moved, the saved spot wins over the game's own re-anchoring.
local function ApplyPosition()
    local pos = ns.db.figurePos
    if not (pos and DurabilityFrame and originalSetPoint) then return end
    DurabilityFrame:ClearAllPoints()
    originalSetPoint(DurabilityFrame, "TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
end

local function SetUnlocked(on)
    unlocked = on
    local f = DurabilityFrame
    f:EnableMouse(on)
    if on then
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
    end
    Redraw()
end

local function SetupFigure()
    local f = DurabilityFrame
    if not f then return end

    local original = DurabilityFrame_SetAlerts
    if original then
        DurabilityFrame_SetAlerts = function()
            original()
            ShowMissing()
        end
    end

    originalSetPoint = f.SetPoint
    f.SetPoint = function(self, a1, a2, a3, a4, a5)
        if ns.db and ns.db.figurePos then return end
        return originalSetPoint(self, a1, a2, a3, a4, a5)
    end

    f:SetScript("OnDragStart", function()
        if unlocked then f:StartMoving() end
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if not unlocked then return end
        ns.db.figurePos = { x = f:GetLeft(), y = f:GetTop() }
        ApplyPosition()
    end)

    ApplyPosition()
    Redraw()
end

ns.OnLoad(SetupFigure)
ns.OnRefresh(function()
    if DurabilityFrame and DurabilityFrame_SetAlerts then Redraw() end
end)

-------------------------------------------------------------------------------
-- Commands
-------------------------------------------------------------------------------

ns.Command("figure", function()
    ns.db.figure = not ns.db.figure
    ns.Print("missing gear on the durability figure " .. ns.OnOff(ns.db.figure))
end, function()
    return "/hbg figure - toggle missing gear on the durability figure (" .. ns.OnOff(ns.db.figure) .. ")"
end)

ns.Command("move", function(rest)
    if not DurabilityFrame then
        ns.Print("durability figure not found")
        return true
    end
    if rest == "reset" then
        ns.db.figurePos = nil
        if unlocked then SetUnlocked(false) end
        Redraw()
        -- let the game put it back under the minimap right away
        if UIParent_ManageFramePositions then UIParent_ManageFramePositions() end
        ns.Print("durability figure back in its usual place")
        return true
    end
    SetUnlocked(not unlocked)
    if unlocked then
        ns.Print("durability figure unlocked - drag it, then type /hbg move again to lock it")
    else
        ns.Print("durability figure locked")
    end
    return true
end, function()
    return "/hbg move - unlock/lock the durability figure to drag it (/hbg move reset)"
end)
