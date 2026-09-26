-- Bespoke options window: /bespoke, or Options > AddOns > Bespoke.
-- A standalone window rather than a Settings panel, so addon code never
-- runs inside (and taints) Blizzard's settings or keybinding UI.
local _, ns = ...

local frame
local widgets = {}
local selectedBar = 1
local refreshing = false -- ignore widget callbacks while we set their values

local function Round(step)
	return function(v) return math.floor(v / step + 0.5) * step end
end
local function Whole(v) return tostring(math.floor(v + 0.5)) end

-- The first slider counts columns or rows, depending on the bar's layout.
local COUNT = { label = "Columns", round = Round(1), format = Whole }
local SLIDERS = {
	COUNT,
	{ key = "scale",   label = "Scale",   steps = 32, round = Round(0.05), format = function(v) return math.floor(v * 100 + 0.5) .. "%" end },
	{ key = "padding", label = "Padding", steps = 22, round = Round(1),    format = Whole },
}

local function CountKey(cfg) return cfg.layoutBy == "rows" and "rows" or "columns" end

local function UsedByText(name)
	local users = ns.ProfileUsers(name)
	if #users == 0 then return "Used by: no characters" end
	local shown = {}
	for i = 1, math.min(3, #users) do shown[i] = users[i] end
	local text = "Used by: " .. table.concat(shown, ", ")
	if #users > 3 then text = text .. (" and %d more"):format(#users - 3) end
	return text
end

local function Refresh()
	if not (frame and frame:IsShown()) then return end
	refreshing = true
	local cfg = ns.GetBarConfig(selectedBar)
	widgets.usedBy:SetText(UsedByText(ns.CurrentProfile()))
	widgets.lock:SetChecked(not ns.IsLocked())
	widgets.color:SetChecked(ns.ColorButtons())
	widgets.enabled:SetChecked(cfg.enabled)
	widgets.fade:SetChecked(cfg.fade)
	-- the count slider's meaning and range depend on the bar and its layout mode
	local key = CountKey(cfg)
	local max = math.max(2, ns.ButtonCount(selectedBar))
	COUNT.label = (key == "rows") and "Rows" or "Columns"
	COUNT.text:SetText(COUNT.label)
	COUNT.slider:Init(math.min(cfg[key], max), 1, max, max - 1, { [MinimalSliderWithSteppersMixin.Label.Right] = COUNT.format })
	for _, def in ipairs(SLIDERS) do
		if def.key then def.slider:SetValue(cfg[def.key]) end
	end
	refreshing = false
	-- regenerate dropdown text next frame, never inside a dropdown's own callback
	C_Timer.After(0, function()
		for _, dd in ipairs(widgets.dropdowns) do dd:GenerateMenu() end
	end)
end
ns.OnChanged = Refresh

----------------------------------------------------------------------
-- Menus
----------------------------------------------------------------------

local function ProfileMenu(_, root)
	local current = ns.CurrentProfile()
	for _, name in ipairs(ns.GetProfiles()) do
		root:CreateRadio(name, function() return name == ns.CurrentProfile() end, function() ns.ProfileCommand("use", name) end)
	end
	root:CreateDivider()
	root:CreateButton("New profile (copy of current)...", function()
		StaticPopup_ShowCustomGenericInputBox({
			text = "Name for the new profile:",
			callback = function(text) ns.ProfileCommand("new", strtrim(text)) end,
		})
	end)
	local delete
	for _, name in ipairs(ns.GetProfiles()) do
		if name ~= "Default" and name ~= current then
			delete = delete or root:CreateButton("Delete profile")
			delete:CreateButton(name, function()
				StaticPopup_ShowCustomGenericConfirmation({
					text = "Delete profile \"%s\"? Characters using it switch to Default.",
					text_arg1 = name,
					callback = function() ns.ProfileCommand("delete", name) end,
				})
			end)
		end
	end
end

local function NewCharactersMenu(_, root)
	for _, name in ipairs(ns.GetProfiles()) do
		root:CreateRadio(name, function() return name == ns.NewCharacterProfile() end, function() ns.ProfileCommand("newchars", name) end)
	end
end

local function BarMenu(_, root)
	for _, id in ipairs(ns.BAR_IDS) do
		local text = ns.BarName(id) .. (ns.GetBarConfig(id).enabled and "" or " (hidden)")
		root:CreateRadio(text, function() return id == selectedBar end, function() selectedBar = id; Refresh() end)
	end
end

local function ChoiceMenu(key, choices)
	return function(_, root)
		for _, choice in ipairs(choices) do
			root:CreateRadio(choice.text,
				function() return ns.GetBarConfig(selectedBar)[key] == choice.value end,
				function() ns.SetBarOption(selectedBar, key, choice.value) end)
		end
	end
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

local function Text(template, text, x, y)
	local fs = frame:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Dropdown(label, generator, y)
	Text("GameFontHighlightSmall", label, 24, y - 6)
	local dd = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dd:SetWidth(200)
	dd:SetPoint("TOPLEFT", 130, y)
	dd:SetupMenu(generator)
	table.insert(widgets.dropdowns, dd)
	return dd
end

local function Checkbox(text, y, onClick)
	local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 20, y)
	cb.Text:SetText(text)
	cb:SetScript("OnClick", function(self) if not refreshing then onClick(self:GetChecked()) end end)
	return cb
end

local function Build()
	frame = CreateFrame("Frame", "BespokeOptions", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(380, 598)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText("Bespoke")
	frame:Hide()
	tinsert(UISpecialFrames, "BespokeOptions") -- Escape closes it
	widgets.dropdowns = {}

	Text("GameFontNormal", "Profile", 20, -38)
	widgets.profiles = Dropdown("Active", ProfileMenu, -58)
	widgets.usedBy = Text("GameFontDisableSmall", "", 24, -88)
	widgets.newChars = Dropdown("New characters", NewCharactersMenu, -106)
	widgets.lock = Checkbox("Unlock bars to drag them", -136, function(checked) ns.SetLocked(not checked) end)
	widgets.color = Checkbox("Color whole button when out of range or mana", -164, ns.SetColorButtons)

	Text("GameFontNormal", "Bars", 20, -208)
	widgets.bars = Dropdown("Edit", BarMenu, -228)
	widgets.enabled = Checkbox("Show this bar", -258, function(checked) ns.SetBarOption(selectedBar, "enabled", checked) end)
	widgets.fade = Checkbox("Fade out until mouseover", -286, function(checked) ns.SetBarOption(selectedBar, "fade", checked) end)
	widgets.layoutBy = Dropdown("Layout by", ChoiceMenu("layoutBy", { { text = "Columns", value = "columns" }, { text = "Rows", value = "rows" } }), -324)
	widgets.grow = Dropdown("Grow", ChoiceMenu("growUp", { { text = "Down", value = false }, { text = "Up", value = true } }), -356)

	local limits = ns.LIMITS
	for i, def in ipairs(SLIDERS) do
		local y = -396 - (i - 1) * 40
		def.text = Text("GameFontHighlightSmall", def.label, 24, y - 6)
		local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
		slider:SetWidth(200)
		slider:SetPoint("TOPLEFT", 130, y)
		if def.key then
			slider:Init(ns.GetBarConfig(selectedBar)[def.key], limits[def.key][1], limits[def.key][2], def.steps,
				{ [MinimalSliderWithSteppersMixin.Label.Right] = def.format })
		end
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			if refreshing then return end
			local key = def.key or CountKey(ns.GetBarConfig(selectedBar))
			ns.SetBarOption(selectedBar, key, def.round(value))
		end, slider)
		def.slider = slider
	end

	local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reset:SetSize(160, 24)
	reset:SetPoint("BOTTOM", 0, 16)
	reset:SetText("Reset layout")
	reset:SetScript("OnClick", function()
		StaticPopup_ShowCustomGenericConfirmation({
			text = "Reset every bar in profile \"%s\" to the default layout?",
			text_arg1 = ns.CurrentProfile(),
			callback = ns.ResetProfile,
		})
	end)

	frame:SetScript("OnShow", Refresh)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", frame.Hide) -- settings can't change in combat
end

function ns.ToggleOptions()
	if InCombatLockdown() then ns.Print("options can't open in combat.") return end
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
end

----------------------------------------------------------------------
-- Entry under Options > AddOns
----------------------------------------------------------------------

local canvas = CreateFrame("Frame")
local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
open:SetSize(200, 26)
open:SetPoint("TOPLEFT", 16, -16)
open:SetText("Open Bespoke options")
open:SetScript("OnClick", function()
	if not (frame and frame:IsShown()) then ns.ToggleOptions() end
end)
local hint = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
hint:SetText("You can also type /bespoke.")
Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(canvas, "Bespoke"))
