-- HoA Better Gear - exact shield amount on the player frame.
--
-- The HoA server sends your current shield as a "BONK~shield~<amount>"
-- system message whenever it changes; HoA only draws it as a cyan bar over
-- your health (VanillaBonkShieldBar). This prints the amount itself at the
-- right end of the player frame's health bar, in HoA's shield color and
-- number font, while you have a shield.

local ns = HoABetterGear

local SHIELD_COLOR = { 0.45, 0.9, 1 }                -- HoA's UI.SHIELD_COLOR
local HOA_FONT = "Interface\\AddOns\\HordesOfAzeroth\\Fonts\\Barlow-Bold.ttf"
local FONT_SIZE = 9                                   -- HoA's health numbers size

local shield = 0
local text

-- 12345 -> "12,345"
local function Grouped(n)
    local s = tostring(math.floor(n + 0.5))
    local out = ""
    while string.len(s) > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    return s .. out
end

local function Update()
    if not text then return end
    if not (ns.db and ns.db.shield) or shield <= 0 then
        text:Hide()
        return
    end
    local label = "+" .. Grouped(shield)
    if ns.db.shieldPct then
        local maxHealth = UnitHealthMax("player")
        if maxHealth and maxHealth > 0 then
            label = label .. " (" .. math.floor(shield / maxHealth * 100 + 0.5) .. "%)"
        end
    end
    text:SetText(label)
    text:Show()
end

ns.OnLoad(function()
    local bar = PlayerFrameHealthBar
    if not bar then return end
    -- above HoA's shield bar (+1) and health numbers (+3)
    local layer = CreateFrame("Frame", nil, PlayerFrame)
    layer:SetAllPoints(bar)
    layer:SetFrameLevel(bar:GetFrameLevel() + 4)
    text = layer:CreateFontString(nil, "OVERLAY")
    local font = VanillaBonkUI and HOA_FONT or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    text:SetFont(font, FONT_SIZE, "OUTLINE")
    text:SetTextColor(SHIELD_COLOR[1], SHIELD_COLOR[2], SHIELD_COLOR[3])
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    text:Hide()
    Update()
end)

ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not msg or string.sub(msg, 1, 12) ~= "BONK~shield~" then return end
    local _, _, amount = string.find(msg, "^BONK~shield~([%d%.%-]+)")
    shield = tonumber(amount) or 0
    Update()
end)

ns.On("UNIT_MAXHEALTH", function(unit)
    if unit == "player" then Update() end
end)

ns.OnRefresh(Update)

ns.Toggle("shield", "shield", "shield amount on the player frame")
ns.Command("shieldpct", function()
    ns.db.shieldPct = not ns.db.shieldPct
    ns.Print("shield as % of max health " .. ns.OnOff(ns.db.shieldPct))
end, function()
    return "/hbg shieldpct - also show the shield as % of max health (" .. ns.OnOff(ns.db.shieldPct) .. ")"
end)
