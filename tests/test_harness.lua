-- Loads the real Bespoke.lua into a stubbed WoW environment and asserts behaviour.
local ADDON_FILE = arg[1]
local pass, fail = 0, 0
local function check(cond, msg)
	if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. msg) end
end

local function NewEnv(opts)
	opts = opts or {}
	local env = { scriptErrors = {}, combat = false, bindings = opts.bindings or {}, overrides = {}, overrideCalls = 0, printed = {} }
	local frames = {}
	local Frame = {}
	Frame.__index = Frame
	local function make(ftype, name, parent, template)
		local f = setmetatable({ ftype = ftype, attrs = {}, points = {}, shown = true, scripts = {}, id = 0,
			events = {}, parent = parent, scale = 1, level = 1, state = "NORMAL" }, Frame)
		if name then
			if parent and name:find("^%$parent") then name = parent:GetName() .. name:sub(8) end
			f.name = name
			env[name] = f
		end
		if template == "BasicFrameTemplateWithInset" then f.TitleText = make("FontString") end
		if template == "UICheckButtonTemplate" then f.isCheckbox = true; f.checked = false; f.Text = make("FontString") end
		if template and template:find("ActionBarButtonTemplate") then
			f.isActionButton = true
			f.w, f.h = 45, 45
			f.attrs.type = "action"; f.attrs["useparent-actionpage"] = true
			f.UpdateHotkeys = function(self, bt) self.hotkeyType = bt end
		end
		frames[#frames + 1] = f
		return f
	end
	function Frame:GetName() return self.name end
	function Frame:SetID(i) self.id = i end
	function Frame:GetID() return self.id end
	function Frame:SetAttribute(k, v) self.attrs[k] = v end
	function Frame:GetAttribute(k) return self.attrs[k] end
	function Frame:SetPoint(p, rel, rp, x, y) self.points[1] = { p, rel, rp, x, y } end
	function Frame:GetPoint() local p = self.points[1]; return p[1], p[2], p[3], p[4], p[5] end
	function Frame:ClearAllPoints() self.points = {} end
	function Frame:SetAllPoints() end
	function Frame:SetSize(w, h) self.w, self.h = w, h end
	function Frame:SetScale(s) self.scale = s end
	-- like WoW: a script error is reported, not propagated to the caller
	local function runScript(f, name, ...)
		if f.scripts[name] then
			local ok, err = pcall(f.scripts[name], f, ...)
			if not ok then env.scriptErrors[#env.scriptErrors + 1] = err end
		end
	end
	function Frame:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
	local function visibilityChange(f, was)
		local now = f:IsVisible()
		if now and not was then runScript(f, "OnShow") elseif was and not now then runScript(f, "OnHide") end
	end
	function Frame:SetShown(s)
		local was = self:IsVisible()
		self.shown = not not s
		visibilityChange(self, was)
	end
	function Frame:GetCenter() if #self.points == 0 then return nil end return 100, 100 end
	function Frame:GetChildren()
		local kids = {}
		for _, f in ipairs(frames) do if f.parent == self then kids[#kids + 1] = f end end
		return unpack(kids)
	end
	function Frame:Show() self:SetShown(true) end
	function Frame:Hide() self.shown = false end
	function Frame:IsShown() return self.shown end
	function Frame:SetMovable() end
	function Frame:SetClampedToScreen() end
	function Frame:StartMoving() self.moving = true end
	function Frame:StopMovingOrSizing() self.moving = false end
	function Frame:EnableMouse() end
	function Frame:RegisterForDrag() end
	function Frame:RegisterForClicks(...) self.clicks = { ... } end
	function Frame:SetScript(k, fn) self.scripts[k] = fn end
	function Frame:GetScript(k) return self.scripts[k] end
	function Frame:SetFrameLevel(l) self.level = l end
	function Frame:GetFrameLevel() return self.level end
	function Frame:RegisterEvent(e) self.events[e] = true end
	function Frame:UnregisterAllEvents() self.events = {}; self.eventsCleared = true end
	function Frame:SetParent(p) local was = self:IsVisible(); self.parent = p; visibilityChange(self, was) end
	function Frame:GetParent() return self.parent end
	function Frame:GetButtonState() return self.state end
	function Frame:SetButtonState(s) self.state = s end
	function Frame:SetAlpha(a) self.alpha = a end
	function Frame:GetAlpha() return self.alpha or 1 end
	function Frame:IsMouseOver() return env.hover == self end
	function Frame:GetObjectType() return self.ftype end
	function Frame:GetWidth() return self.w or 0 end
	function Frame:GetHeight() return self.h or 0 end
	function Frame:GetScale() return self.scale end
	-- screen is 1024x768 UI units; a frame's rect is in its own (scaled) units
	local function offset(point, w, h)
		local x = point:find("LEFT") and 0 or (point:find("RIGHT") and w or w / 2)
		local y = point:find("BOTTOM") and 0 or (point:find("TOP") and h or h / 2)
		return x, y
	end
	function Frame:Rect()
		local p = self.points[1]
		if not p or p[2] ~= env.UIParent then return nil end
		local W, H = 1024 / self.scale, 768 / self.scale
		local rx, ry = offset(p[3], W, H)
		local px, py = offset(p[1], self.w, self.h)
		local left, bottom = rx + p[4] - px, ry + p[5] - py
		return left, bottom, bottom + self.h
	end
	function Frame:GetLeft() return (self:Rect()) end
	function Frame:GetBottom() local _, b = self:Rect(); return b end
	function Frame:GetTop() local _, _, t = self:Rect(); return t end
	function Frame:SetFrameStrata(v) self.strata = v end
	function Frame:SetWidth(w) self.w = w end
	function Frame:SetText(t) self.text = t end
	function Frame:SetChecked(v) self.checked = not not v end
	function Frame:GetChecked() return self.checked end
	function Frame:Click()
		if self.isCheckbox then self.checked = not self.checked end
		self.scripts.OnClick(self)
	end
	-- dropdown: store the generator; GenerateMenu runs it into a recording description
	local function Desc() local d = { items = {} }
		function d:CreateRadio(text, isSel, setSel) local e = { kind = "radio", text = text, isSel = isSel, set = setSel }; self.items[#self.items + 1] = e; return e end
		function d:CreateButton(text, cb) local e = Desc(); e.kind = "button"; e.text = text; e.cb = cb; self.items[#self.items + 1] = e; return e end
		function d:CreateDivider() self.items[#self.items + 1] = { kind = "divider" } end
		return d end
	function Frame:SetupMenu(gen) self.gen = gen; self:GenerateMenu() end
	function Frame:GenerateMenu() self.menu = Desc(); self.gen(self, self.menu) end
	-- slider: Init sets value silently; SetValue fires OnValueChanged only on change
	function Frame:Init(value, min, max, steps, fmt) self.value, self.min, self.max, self.steps = value, min, max, steps end
	function Frame:RegisterCallback(_, fn, owner) self.cb, self.cbOwner = fn, owner end
	function Frame:SetValue(v) if v ~= self.value then self.value = v; if self.cb then self.cb(self.cbOwner, v) end end end
	function Frame:CreateTexture() return { SetAllPoints = function() end, SetColorTexture = function() end } end
	function Frame:CreateFontString()
		local fs = { SetPoint = function() end, SetText = function(self, t) self.text = t end }
		env.fontStrings = env.fontStrings or {}
		env.fontStrings[#env.fontStrings + 1] = fs
		return fs
	end

	env.CreateFrame = make
	env.UIParent = make("Frame", "UIParent")
	-- Blizzard bars and buttons that the addon should hide
	for _, pair in ipairs({ { "MainActionBar", "ActionButton" }, { "MultiBarBottomLeft", "MultiBarBottomLeftButton" },
		{ "MultiBarBottomRight", "MultiBarBottomRightButton" }, { "MultiBarRight", "MultiBarRightButton" },
		{ "MultiBarLeft", "MultiBarLeftButton" }, { "MultiBar5", "MultiBar5Button" }, { "MultiBar6", "MultiBar6Button" },
		{ "MultiBar7", "MultiBar7Button" } }) do
		local bar = make("Frame", pair[1], env.UIParent)
		bar.system = 1; bar.isShownExternal = true
		for i = 1, 12 do local b = make("CheckButton", pair[2] .. i, bar); b.bar = bar end
	end
	local function sized(name, parent, w, h) local f = make("CheckButton", name, parent); f.w, f.h = w, h; return f end
	env.PetActionBar = make("Frame", "PetActionBar", env.UIParent); env.PetActionBar.actionButtons = {}
	env.StanceBar = make("Frame", "StanceBar", env.UIParent); env.StanceBar.actionButtons = {}
	for i = 1, 10 do
		env.PetActionBar.actionButtons[i] = sized("PetActionButton" .. i, env.PetActionBar, 30, 30)
		local sb = sized("StanceButton" .. i, env.StanceBar, 30, 30)
		sb:SetPoint("CENTER", env.StanceBar, "CENTER", i * 32, 0) -- Blizzard anchors each to its container
		sb.shown = false
		env.StanceBar.actionButtons[i] = sb
	end
	-- Blizzard: Edit Mode force-shows all 10; with 0 forms nothing hides them again
	env.StanceBar.EditModeForceShow = function(self)
		for _, b in ipairs(self.actionButtons) do b:SetShown(true) end
	end
	env.PetActionBar.events.UNIT_PET = true
	env.forms = 3
	env.GetNumShapeshiftForms = function() return env.forms end
	env.BagsBar = make("Frame", "BagsBar", env.UIParent)
	local bagOrder = {}
	for _, spec in ipairs({ { "MainMenuBarBackpackButton", 40, 40 }, { "CharacterBag0Slot", 30, 30 }, { "CharacterBag1Slot", 30, 30 },
		{ "CharacterBag2Slot", 30, 30 }, { "CharacterBag3Slot", 30, 30 }, { "CharacterReagentBag0Slot", 30, 30 }, { "KeyRingButton", 18, 39 } }) do
		bagOrder[#bagOrder + 1] = sized(spec[1], env.BagsBar, spec[2], spec[3])
	end
	env.BagsBar.Layout = function(self) -- Blizzard pulls bag buttons back onto its own bar
		env.blizzBagLayouts = (env.blizzBagLayouts or 0) + 1
		for _, b in ipairs(bagOrder) do b:SetParent(self); b:ClearAllPoints(); b:SetPoint("RIGHT", self, "RIGHT", 0, 0) end
	end
	env.MainMenuBarBagManager = { EnumerateBagButtons = function() return ipairs(bagOrder) end, OnExpandBarChanged = function() end }
	env.MicroMenuContainer = make("Frame", "MicroMenuContainer", env.UIParent)
	env.MicroMenu = make("Frame", "MicroMenu", env.MicroMenuContainer)
	-- Same edge logic as Blizzard's MicroMenuMixin:GetEdgeButton: compares the
	-- centers of the first and last layoutIndex children, erroring on nil.
	env.MicroMenu.Layout = function(self)
		local first, last
		for _, child in ipairs({ self:GetChildren() }) do
			if child.layoutIndex then
				if not first or child.layoutIndex < first.layoutIndex then first = child end
				if not last or child.layoutIndex > last.layoutIndex then last = child end
			end
		end
		if not first then return nil end
		local fx, lx = first:GetCenter(), last:GetCenter()
		return fx < lx and first or last
	end
	env.MicroMenuContainer.Layout = function() env.MicroMenu:Layout() end
	local added = 0
	for _, name in ipairs({ "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
		"LegacyMicroButton", "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton", "LFDMicroButton",
		"CollectionsMicroButton", "EJMicroButton", "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton" }) do
		local b = sized(name, env.MicroMenu, 32, 40)
		b.scripts.OnShow = function() env.MicroMenuContainer:Layout() end
		b.scripts.OnHide = function() env.MicroMenuContainer:Layout() end
		-- game rules: Forever leaves out Legacy, Housing and Store
		if name ~= "LegacyMicroButton" and name ~= "HousingMicroButton" and name ~= "StoreMicroButton" then
			added = added + 1; b.layoutIndex = added
			if name == "HelpMicroButton" then
				b.shown = false -- added but hidden, so Blizzard never positions it (your error's firstButton)
			else
				b:SetPoint("TOPLEFT", env.MicroMenu, "TOPLEFT", added * 30, 0) -- laid out by Blizzard
			end
		elseif name ~= "LegacyMicroButton" then
			b.shown = false -- Legacy stays "shown": the worst case, only layoutIndex excludes it
		end
	end
	env.UpdateMicroButtons = function() env.microUpdates = (env.microUpdates or 0) + 1 end
	env.hooksecurefunc = function(a, b, c)
		local t, k, fn = a, b, c
		if type(a) == "string" then t, k, fn = env, a, b end
		local orig = t[k]
		t[k] = function(...) local r = orig(...); fn(...); return r end
	end
	env.cvars = {}
	env.SetCVar = function(k, v) env.cvars[k] = v end
	env.hasPet = false
	env.blocked = {}
	env.RegisterStateDriver = function(f, state, value)
		assert(state == "visibility", "only visibility drivers are used")
		if env.combat then env.blocked[#env.blocked + 1] = "RegisterStateDriver in combat" end
		f.visDriver = value
		if value == "show" then f:Show() elseif env.hasPet then f:Show() else f:Hide() end
	end
	env.UnregisterStateDriver = function(f)
		if env.combat then env.blocked[#env.blocked + 1] = "UnregisterStateDriver in combat" end
		f.visDriver = nil
	end
	env.WorldFrame = make("Frame", "WorldFrame")
	env.GetMouseFoci = function() return { env.mouseFocus or env.WorldFrame } end
	env.InCombatLockdown = function() return env.combat end
	env.GetBindingKey = function(cmd) local k = env.bindings[cmd]; if k then return unpack(k) end end
	env.SetOverrideBindingClick = function(owner, _, key, name, button)
		env.overrides[key] = { owner = owner, name = name, button = button }; env.overrideCalls = env.overrideCalls + 1
	end
	env.ClearOverrideBindings = function(owner)
		for k, v in pairs(env.overrides) do if v.owner == owner then env.overrides[k] = nil end end
	end
	env.issecurevariable = function() return true end
	env.C_Timer = { After = function(_, fn) fn() end }
	env.tinsert = table.insert
	env.UISpecialFrames = {}
	env.MinimalSliderWithSteppersMixin = { Label = { Right = 2 }, Event = { OnValueChanged = "OnValueChanged" } }
	env.Settings = {
		RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
		RegisterAddOnCategory = function(cat) env.settingsCategory = cat end,
	}
	env.StaticPopup_ShowCustomGenericInputBox = function(data) env.popup = data end
	env.StaticPopup_ShowCustomGenericConfirmation = function(data) env.popup = data end
	env.tostring = tostring
	env.charName = opts.char or "Tester"
	env.charKey = env.charName .. " - Soulseeker"
	env.UnitName = function() return env.charName end
	env.GetRealmName = function() return "Soulseeker" end
	local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = type(v) == "table" and copy(v) or v end; return c end
	env.CopyTable = copy
	env.print = function(msg) env.printed[#env.printed + 1] = msg end
	env.strsplit = function(sep, s)
		local out = {}
		for piece in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = piece end
		return unpack(out)
	end
	env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.strlower = string.lower
	env.SlashCmdList = {}
	env.BespokeDB = opts.saved
	for _, name in ipairs({ "pairs", "ipairs", "math", "table", "tonumber", "type", "string", "unpack", "select" }) do
		env[name] = _G[name]
	end
	env._G = env
	ALL_ENVS = ALL_ENVS or {}
	ALL_ENVS[#ALL_ENVS + 1] = env
	env.frames = frames

	env.ns = {}
	for _, file in ipairs(opts.files or { ADDON_FILE }) do
		local chunk = assert(loadfile(file))
		setfenv(chunk, env)
		chunk("Bespoke", env.ns)
	end
	local events = nil
	for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then events = f end end
	env.fire = function(e) events.scripts.OnEvent(events, e) end
	env.fireAll = function(e) for _, f in ipairs(frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e) end end end
	env.slash = function(msg) env.SlashCmdList.BESPOKE(msg) end
	-- Blizzard's SecureActionButtonMixin:CalculateAction for an ID > 0 button
	env.slotOf = function(b) return b:GetID() + ((b:GetAttribute("actionpage") - 1) * 12) end
	return env
end

local function P(e) local db = e.BespokeDB; return db.profiles[db.chars[e.charKey]].bars end
local function last(e) return e.printed[#e.printed] or "" end
local function printed(e, pattern, back)
	for i = #e.printed, math.max(1, #e.printed - (back or 3) + 1), -1 do
		if e.printed[i]:find(pattern) then return true end
	end
end

local EXPECTED_SLOTS = { 0, 60, 48, 24, 36, 144, 156, 168 }   -- first slot - 1, per Blizzard bar

------------------------------------------------------------------ login
local env = NewEnv({ bindings = { ACTIONBUTTON1 = { "1" }, MULTIACTIONBAR1BUTTON2 = { "CTRL-2", "F2" } } })
env.fire("PLAYER_LOGIN")
for id = 1, 5 do check(env["BespokeBar" .. id] ~= nil, "bar " .. id .. " created") end
for id = 6, 8 do check(env["BespokeBar" .. id] == nil, "bar " .. id .. " not created while disabled") end

-- action slots: visible button (Blizzard calc) == key button == Blizzard's own bar
for id = 1, 5 do
	for i = 1, 12 do
		local b = env[("BespokeBar%dButton%d"):format(id, i)]
		local expected = EXPECTED_SLOTS[id] + i
		check(env.slotOf(b) == expected, ("bar %d button %d slot %d, want %d"):format(id, i, env.slotOf(b), expected))
		check(b.key:GetAttribute("action") == expected, ("bar %d button %d key slot"):format(id, i))
		check(b.key:GetAttribute("type") == "action", "key type action")
		check(b.key.clicks[1] == "AnyUp" and b.key.clicks[2] == "AnyDown", "key registered for down+up")
	end
end

-- layout
local b1, b4 = env.BespokeBar1, env.BespokeBar4
check(b1.w == 12 * 47 - 2 and b1.h == 45, "bar 1 horizontal size " .. tostring(b1.w) .. "x" .. tostring(b1.h))
check(b4.w == 45 and b4.h == 12 * 47 - 2, "bar 4 vertical size")
local _, _, _, x7, y7 = env.BespokeBar1Button8:GetPoint()
check(x7 == 7 * 47 + 22.5 and y7 == -22.5, "button 8 centered in its cell")

-- Blizzard bars hidden
check(env.MainActionBar.parent ~= env.UIParent and not env.MainActionBar.shown, "MainActionBar hidden")
check(not env.MainActionBar.eventsCleared, "MainActionBar keeps its events")
check(env.MultiBarBottomLeft.eventsCleared, "MultiBar events cleared")
check(env.MainActionBar.isShownExternal == nil, "isShownExternal purged")
check(not env.ActionButton1.shown and env.ActionButton1:GetAttribute("statehidden"), "Blizzard button hidden")

-- keybinds
check(env.overrides["1"] and env.overrides["1"].name == "BespokeBar1Button1Key", "key 1 -> bar1 button1")
check(env.overrides["1"].button == "LeftButton", "binding clicks LeftButton")
check(env.overrides["CTRL-2"] and env.overrides["F2"] and env.overrides["F2"].name == "BespokeBar2Button2Key", "multi-key binding on bar 2")
check(env.BespokeBar1Button1.commandName == "ACTIONBUTTON1" and env.BespokeBar1Button1.hotkeyType == "ACTIONBUTTON", "hotkey label wiring")
local calls = env.overrideCalls
env.fire("UPDATE_BINDINGS")
check(env.overrideCalls == calls, "UPDATE_BINDINGS with no changes does not re-bind (no loop)")
env.bindings.ACTIONBUTTON2 = { "2" }
env.fire("UPDATE_BINDINGS")
check(env.overrides["2"] and env.overrides["2"].name == "BespokeBar1Button2Key", "new binding picked up")

-- key press mirrors on the visible button
local key = env.BespokeBar1Button1.key
key.scripts.PreClick(key, "LeftButton", true)
check(env.BespokeBar1Button1.state == "PUSHED", "key down pushes visible button")
key.scripts.PreClick(key, "LeftButton", false)
check(env.BespokeBar1Button1.state == "NORMAL", "key up releases visible button")

------------------------------------------------------------------ slash commands
env.slash("bar 6 on")
check(env.BespokeBar6 and env.BespokeBar6.shown, "bar 6 enabled on demand")
check(env.slotOf(env.BespokeBar6Button1) == 145, "bar 6 uses MultiBar5 slots")
env.slash("bar 2 cols 6")
check(env.BespokeBar2.w == 6 * 47 - 2 and env.BespokeBar2.h == 2 * 47 - 2, "cols 6 -> 2 rows")
env.slash("bar 1 scale 5")
check(P(env)[1].scale == 2 and env.BespokeBar1.scale == 2, "scale clamped to 2")
env.slash("bar 2 off")
check(not env.BespokeBar2.shown, "bar 2 hidden")
check(env.overrides["F2"] == nil and env.overrides["CTRL-2"] == nil, "disabled bar releases its keys")
env.slash("bar 9 on")
check(env.printed[#env.printed]:find("1%-8"), "invalid bar rejected")

------------------------------------------------------------------ unlock, drag, combat
env.slash("unlock")
check(env.BespokeBar1.overlay.shown and not env.BespokeBar2.overlay.shown, "overlays only on enabled bars")
local bar3 = env.BespokeBar3
bar3.overlay.scripts.OnDragStart()
bar3:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 300, 400)
bar3.overlay.scripts.OnDragStop()
local c3 = P(env)[3]
check(c3.point == "TOPLEFT" and c3.relPoint == "BOTTOMLEFT" and c3.x == 300 and c3.y == 445, "drag saves the growth corner (top-left when growing down)")
env.fire("PLAYER_REGEN_DISABLED")
check(env.BespokeDB.locked and not env.BespokeBar1.overlay.shown, "entering combat locks bars")
env.combat = true
env.slash("unlock")
check(env.BespokeDB.locked, "cannot unlock in combat")
env.slash("bar 1 cols 3")
check(P(env)[1].columns == 12, "settings frozen in combat")
env.combat = false

env.slash("reset")
check(P(env)[3].x == 0 and P(env)[1].scale == 1 and P(env)[2].enabled, "reset restores defaults")
check(not env.BespokeBar6.shown, "reset disables bar 6 again")

------------------------------------------------------------------ login during combat
local env2 = NewEnv()
env2.combat = true
env2.fire("PLAYER_LOGIN")
check(env2.BespokeBar1 == nil and env2.MainActionBar.shown, "nothing touched while in combat")
env2.combat = false
env2.fire("PLAYER_REGEN_ENABLED")
check(env2.BespokeBar1 ~= nil and not env2.MainActionBar.shown, "deferred init runs after combat")

------------------------------------------------------------------ saved settings carry over and gain new defaults
local env3 = NewEnv({ saved = { locked = true, bars = { [1] = { enabled = true, point = "CENTER", relPoint = "CENTER", x = 11, y = 22, columns = 4 } } } })
env3.fire("PLAYER_LOGIN")
local s = P(env3)[1]
check(s.x == 11 and s.columns == 4 and s.padding == 2 and s.scale == 1, "1.0.0 layout migrated into Default, missing keys filled")
check(P(env3)[8] and P(env3)[8].enabled == false, "new bars added with defaults")
check(env3.BespokeDB.bars == nil and env3.BespokeDB.chars[env3.charKey] == "Default", "old top-level layout removed after migration")
check(env3.BespokeDB.locked == true, "lock state kept")

------------------------------------------------------------------ profiles
local A = NewEnv({ char = "Tester" })
A.fire("PLAYER_LOGIN")
check(A.BespokeDB.chars[A.charKey] == "Default", "new character starts on Default")
A.slash("bar 1 cols 6")
A.slash("profile new PvP")
local db = A.BespokeDB
check(db.chars[A.charKey] == "PvP" and db.profiles.PvP, "new creates and switches; name keeps its case")
check(P(A)[1].columns == 6, "new copies the current layout")
A.slash("bar 1 cols 3")
A.slash("bar 6 on")
check(db.profiles.Default.bars[1].columns == 6 and db.profiles.Default.bars[6].enabled == false, "editing PvP leaves Default untouched")
A.slash("profile use Default")
check(db.chars[A.charKey] == "Default" and A.BespokeBar1.w == 6 * 47 - 2, "use switches and re-applies layout")
check(not A.BespokeBar6.shown, "bar only in the other profile is hidden after switching")
A.slash("profile new PvP")
check(last(A):find("already exists"), "duplicate profile rejected")
A.slash("profile use Nope")
check(last(A):find("no profile named") and db.chars[A.charKey] == "Default", "unknown profile rejected")
A.slash("profile")
check(printed(A, "Default %(current%)") and printed(A, "PvP"), "list shows profiles and marks current")
A.combat = true
A.slash("profile use PvP")
check(db.chars[A.charKey] == "Default", "profile switch blocked in combat")
A.slash("profile")
check(printed(A, "profiles:"), "listing still works in combat")
A.combat = false
A.slash("profile delete Default")
check(db.profiles.Default and last(A):find("can't delete"), "Default can't be deleted")

-- second character shares the saved file
local B = NewEnv({ char = "Alt", saved = db })
B.fire("PLAYER_LOGIN")
check(db.chars[B.charKey] == "Default" and P(B)[1].columns == 6, "second character starts on the shared Default")
B.slash("profile use PvP")
check(db.chars[B.charKey] == "PvP" and db.chars[A.charKey] == "Default", "each character keeps its own choice")
B.slash("profile delete PvP")
check(db.profiles.PvP and last(B):find("can't delete"), "can't delete the profile in use")
B.slash("profile use Default")
A.slash("profile use PvP")
B.slash("profile delete PvP")
check(db.profiles.PvP == nil and db.chars[A.charKey] == "Default", "delete moves its characters back to Default")

-- a character pointing at a missing profile recovers
local C = NewEnv({ char = "Tester", saved = { chars = { ["Tester - Soulseeker"] = "Gone" }, profiles = {} } })
C.fire("PLAYER_LOGIN")
check(C.BespokeDB.chars[C.charKey] == "Default" and C.BespokeBar1, "missing profile falls back to Default")


------------------------------------------------------------------ options window
local OPTIONS_FILE = ADDON_FILE:gsub("Bespoke%.lua$", "Options.lua")
local function item(menu, text)
	for _, e in ipairs(menu.items) do if e.text == text then return e end end
end
local function selectedRadio(menu)
	for _, e in ipairs(menu.items) do if e.kind == "radio" and e.isSel() then return e.text end end
end

local U = NewEnv({ files = { ADDON_FILE, OPTIONS_FILE } })
check(U.settingsCategory and U.settingsCategory.name == "Bespoke", "entry registered under Options > AddOns")
U.fire("PLAYER_LOGIN")
U.slash("")
local win = U.BespokeOptions
check(win and win.shown and win.strata == "DIALOG", "/bespoke opens the window")
check(U.UISpecialFrames[1] == "BespokeOptions", "Escape closes the window")
U.slash("")
check(not win.shown, "/bespoke again closes it")

-- the Options > AddOns button opens it too
local openButton
for _, f in ipairs(U.frames) do if f.text == "Open Bespoke options" then openButton = f end end
openButton:Click()
check(win.shown, "settings entry button opens the window")

-- find widgets
local dds, checks, sliders = {}, {}, {}
for _, f in ipairs(U.frames) do
	if f.gen then dds[#dds + 1] = f end
	if f.isCheckbox then checks[f.Text.text] = f end
	if f.cb then sliders[#sliders + 1] = f end
end
local profileDD, newCharDD, barDD, layoutDD, growDD = dds[1], dds[2], dds[3], dds[4], dds[5]
local lockBox, showBox = checks["Unlock bars to drag them"], checks["Show this bar"]
local cols, scale, pad = sliders[1], sliders[2], sliders[3]
check(profileDD and barDD and lockBox and showBox and cols and scale and pad, "all widgets built")
check(cols.min == 1 and cols.max == 12 and cols.steps == 11 and scale.min == 0.4 and scale.max == 2, "count and scale ranges")
check(pad.min == -2 and pad.max == 20 and pad.steps == 22, "padding goes down to -2")

-- initial state reflects settings
check(not lockBox.checked and showBox.checked and cols.value == 12, "widgets show current settings")
check(selectedRadio(profileDD.menu) == "Default" and selectedRadio(barDD.menu) == "Bar 1", "dropdowns show current profile and bar")

-- no write-back while refreshing
local writes = 0
local realSet = U.ns.SetBarOption
U.ns.SetBarOption = function(...) writes = writes + 1; return realSet(...) end
item(barDD.menu, "Bar 4").set()
check(writes == 0, "switching bar in the UI writes nothing back")
check(cols.value == 1 and showBox.checked, "bar 4 values shown (1 column)")

-- sliders write rounded values and re-layout
cols:SetValue(6.4)
check(P(U)[4].columns == 6 and U.BespokeBar4.w == 6 * 47 - 2, "columns slider rounds and re-lays out bar 4")
scale:SetValue(1.234)
check(math.abs(P(U)[4].scale - 1.25) < 1e-9, "scale slider rounds to 5% steps")
check(writes == 2, "one write per slider change")

-- checkboxes
showBox:Click()
check(P(U)[4].enabled == false and not U.BespokeBar4.shown, "Show this bar unchecked hides bar 4")
check(item(barDD.menu, "Bar 4 (hidden)"), "bar list marks hidden bars")
lockBox:Click()
check(U.BespokeDB.locked == false and U.BespokeBar1.overlay.shown, "unlock checkbox unlocks bars")
lockBox:Click()
check(U.BespokeDB.locked == true, "and locks them again")

-- slash changes while the window is open are reflected
item(barDD.menu, "Bar 1").set()
U.slash("bar 1 cols 4")
check(cols.value == 4, "slash change updates the open window")

-- profiles through the UI
item(profileDD.menu, "New profile (copy of current)...").cb()
U.popup.callback("  Raid  ")
check(U.BespokeDB.chars[U.charKey] == "Raid" and selectedRadio(profileDD.menu) == "Raid", "new profile via popup, trimmed, selected")
check(item(profileDD.menu, "Delete profile") == nil, "nothing deletable while on the only other profile")
item(profileDD.menu, "Default").set()
check(U.BespokeDB.chars[U.charKey] == "Default", "profile radio switches profile")
local del = item(profileDD.menu, "Delete profile")
check(del and item(del, "Raid") and not item(del, "Default"), "delete menu lists only deletable profiles")
item(del, "Raid").cb()
check(U.popup.text:find("%%s") and U.popup.text_arg1 == "Raid", "profile name passed as format argument, not spliced into text")
U.popup.callback()
check(U.BespokeDB.profiles.Raid == nil and item(profileDD.menu, "Raid") == nil, "confirmed delete removes the profile")

-- reset button
U.slash("bar 1 cols 2")
local resetButton
for _, f in ipairs(U.frames) do if f.text == "Reset layout" then resetButton = f end end
resetButton:Click()
check(U.popup.text_arg1 == "Default", "reset asks with the profile name")
U.popup.callback()
check(P(U)[1].columns == 12 and cols.value == 12, "reset applied and shown")

-- combat
U.fireAll("PLAYER_REGEN_DISABLED")
check(not win.shown, "window hides when combat starts")
U.combat = true
U.slash("")
check(not win.shown and last(U):find("combat"), "window can't open in combat")
U.combat = false

------------------------------------------------------------------ 1.3: layout options
local G = NewEnv()
G.fire("PLAYER_LOGIN")
local g1 = G.BespokeBar1
G.slash("bar 1 padding -2")
check(P(G)[1].padding == -2 and g1.w == 12 * 43 + 2, "padding -2 overlaps buttons (" .. tostring(g1.w) .. ")")
G.slash("bar 1 padding -9")
check(P(G)[1].padding == -2, "padding clamps at -2")
G.slash("bar 1 padding 2")

G.slash("bar 1 rows 2")
check(P(G)[1].layoutBy == "rows" and P(G)[1].rows == 2 and g1.w == 6 * 47 - 2 and g1.h == 2 * 47 - 2, "rows 2 -> 6 columns x 2 rows")
G.slash("bar 1 rows 5")
check(g1.rows == 4 and g1.cols == 3, "rows 5 on 12 buttons gives 3 columns x 4 rows (like Bartender)")
local w, h = g1.w, g1.h
G.ns.SetBarOption(1, "layoutBy", "columns")
check(P(G)[1].columns == 3 and g1.w == w and g1.h == h, "switching to columns keeps the same shape")
G.ns.SetBarOption(1, "layoutBy", "rows")
check(P(G)[1].rows == 4 and g1.w == w, "switching back to rows keeps the same shape")
G.slash("bar 1 cols 12")

-- growth: the edge opposite the growth direction stays fixed on screen
local left0, bottom0 = g1:GetLeft(), g1:GetBottom()
G.slash("bar 1 grow up")
check(math.abs(g1:GetLeft() - left0) < 1e-6 and math.abs(g1:GetBottom() - bottom0) < 1e-6, "switching growth doesn't move the bar")
G.slash("bar 1 rows 3")
check(math.abs(g1:GetBottom() - bottom0) < 1e-6 and g1:GetTop() > bottom0 + 100, "growing up: bottom edge fixed, rows extend upward")
local p1 = G.BespokeBar1Button1.points[1]
check(p1[3] == "BOTTOMLEFT" and p1[5] > 0, "growing up: button 1 sits in the bottom row")
local top0 = g1:GetTop()
G.slash("bar 1 grow down")
G.slash("bar 1 rows 6")
check(math.abs(g1:GetTop() - top0) < 1e-6 and g1:GetBottom() < top0 - 200, "growing down: top edge fixed, rows extend downward")
local ui0 = g1:GetLeft() * g1:GetScale()
G.slash("bar 1 scale 1.5")
check(math.abs(g1:GetLeft() * g1:GetScale() - ui0) < 1e-6 and math.abs(g1:GetTop() * 1.5 - top0) < 1e-6, "scaling keeps the anchored corner in place")

-- 1.2 profiles stored positions in the bar's own scale: migrated once
local M = NewEnv({ saved = { chars = {}, profiles = { Default = { bars = { [1] = { enabled = true, point = "BOTTOM", relPoint = "BOTTOM", x = 10, y = 20, scale = 2, columns = 12 } } } } } })
M.fire("PLAYER_LOGIN")
check(P(M)[1].x == 20 and P(M)[1].y == 40 and M.BespokeDB.profiles.Default.version == 2, "1.2 positions migrated to screen units")
check(P(M).pet and P(M).stance and P(M).bags and P(M).micro, "new bars added to old profiles")
M.fire("PLAYER_LOGIN")
check(P(M)[1].x == 20, "migration runs only once")

------------------------------------------------------------------ 1.3: pet, stance, bags, micro
local B = NewEnv()
B.fire("PLAYER_LOGIN")
local pet = B.BespokePetBar or B.Bespokepet or B["BespokeBarpet"]
check(pet ~= nil, "pet bar created")
check(B.PetActionButton1.parent == pet and B.PetActionButton10.parent == pet, "pet buttons reused and moved into our bar")
check(B.PetActionBar.parent ~= B.UIParent and B.PetActionBar.events.UNIT_PET, "Blizzard pet bar hidden but still receiving events")
check(pet.visDriver == "[@pet,exists,nopossessbar] show; hide" and not pet.shown, "pet bar shows only with a pet")
B.slash("unlock")
check(pet.visDriver == "show" and pet.shown and pet.overlay.shown, "unlocked: pet bar shown so it can be placed")
B.slash("lock")
B.slash("bar pet off")
check(pet.visDriver == nil and not pet.shown, "disabled pet bar has no driver and stays hidden")
B.slash("bar pet on")
check(pet.w == 10 * 32 - 2 and pet.h == 30, "10 pet buttons in a row")

local stance = B["BespokeBarstance"]
check(stance and stance.w == 3 * 32 - 2, "stance bar sized to 3 forms")
check(B.StanceButton3.parent == stance and B.StanceButton10.parent ~= stance, "stance buttons you have are on our bar; the rest wait out of sight")
B.forms = 5
B.fire("UPDATE_SHAPESHIFT_FORMS")
check(stance.w == 5 * 32 - 2, "new form learned: stance bar grows")
B.combat = true
B.forms = 6
B.fire("UPDATE_SHAPESHIFT_FORMS")
check(stance.w == 5 * 32 - 2, "stance re-layout waits for combat to end")
B.combat = false
B.fire("PLAYER_REGEN_ENABLED")
check(stance.w == 6 * 32 - 2, "and happens after combat")

local bags = B["BespokeBarbags"]
check(B.cvars.expandBagBar == 1, "bags kept expanded (collapse arrow is gone)")
local function xOf(b) return b.points[1][4] end
check(B.MainMenuBarBackpackButton.parent == bags and xOf(B.KeyRingButton) < xOf(B.CharacterBag3Slot)
	and xOf(B.CharacterBag0Slot) < xOf(B.MainMenuBarBackpackButton), "bag order matches Blizzard: key ring ... bag 0, backpack")
B.CharacterReagentBag0Slot.shown = false
B.BagsBar:Layout()
check(B.MainMenuBarBackpackButton.parent == bags and B.MainMenuBarBackpackButton.points[1][2] == bags, "Blizzard bag re-layout is undone")
check(bags.cols == 6 and bags.w == 6 * 42 - 2 and B.CharacterReagentBag0Slot.points[1][2] ~= bags, "hidden reagent slot left out (6 buttons in 40px cells)")
B.combat = true
B.BagsBar:Layout()
check(B.CharacterBag0Slot.parent == bags, "bag bar re-layout also works in combat (not protected)")
B.combat = false

local micro = B["BespokeBarmicro"]
check(micro.cols == 10 and B.CharacterMicroButton.parent == micro, "10 shown micro buttons laid out")
check(#B.scriptErrors == 0, "no Blizzard micro menu errors while taking the buttons (" .. tostring(B.scriptErrors[1]) .. ")")
check(B.HelpMicroButton.parent == micro, "added-but-hidden Help button taken too")
local leftover = 0
for _, child in ipairs({ B.MicroMenu:GetChildren() }) do if child.layoutIndex then leftover = leftover + 1 end end
check(leftover == 0, "Blizzard's micro menu is left with no layout buttons")
local ok, err = pcall(B.MicroMenuContainer.Layout, B.MicroMenuContainer)
check(ok, "Edit Mode-style micro menu re-layout is safe afterwards (" .. tostring(err) .. ")")
check(B.StoreMicroButton.parent ~= micro and B.HousingMicroButton.parent ~= micro and B.LegacyMicroButton.parent ~= micro, "buttons the game rules left out are untouched, even if flagged shown")
check(xOf(B.CharacterMicroButton) < xOf(B.SpellbookMicroButton) and xOf(B.CollectionsMicroButton) < xOf(B.MainMenuMicroButton), "micro order follows Blizzard")
B.GuildMicroButton.shown = false
B.UpdateMicroButtons()
check(micro.cols == 9, "micro menu re-laid out when Blizzard hides a button")
B.HelpMicroButton.shown = true
B.UpdateMicroButtons()
check(micro.cols == 10 and B.HelpMicroButton.points[1][2] == micro, "hidden button that appears later is laid out in order")
B.slash("bar micro rows 2")
check(micro.rows == 2 and micro.cols == 5, "micro menu in 2 rows")
B.slash("bar foo on")
check(last(B):find("pet, stance, bags or micro"), "unknown bar name rejected")

------------------------------------------------------------------ 1.3: profile for new characters
local N = NewEnv({ char = "Main" })
N.fire("PLAYER_LOGIN")
N.slash("profile new Mine")
N.slash("profile newchars Mine")
local ndb = N.BespokeDB
check(ndb.newCharProfile == "Mine", "new-character profile set")
local N2 = NewEnv({ char = "Fresh", saved = ndb })
N2.fire("PLAYER_LOGIN")
check(ndb.chars[N2.charKey] == "Mine", "a brand-new character starts on the chosen profile")
local users = N2.ns.ProfileUsers("Mine")
check(#users == 2 and users[1] == "Fresh - Soulseeker", "profile lists every character using it")
N2.slash("profile use Default")
N.slash("profile use Default")
N.slash("profile delete Mine")
check(ndb.newCharProfile == "Default", "deleting the new-character profile falls back to Default")

------------------------------------------------------------------ 1.3: options window
local W = NewEnv({ files = { ADDON_FILE, OPTIONS_FILE } })
W.fire("PLAYER_LOGIN")
W.slash("")
local wd, wc, ws = {}, {}, {}
for _, f in ipairs(W.frames) do
	if f.gen then wd[#wd + 1] = f end
	if f.cb then ws[#ws + 1] = f end
end
local wProfiles, wNewChars, wBars, wLayout, wGrow = wd[1], wd[2], wd[3], wd[4], wd[5]
check(item(wBars.menu, "Pet bar") and item(wBars.menu, "Stance bar") and item(wBars.menu, "Bag bar") and item(wBars.menu, "Micro menu"), "bar list includes pet, stance, bags and micro")
item(wBars.menu, "Pet bar").set()
check(ws[1].max == 10 and ws[1].value == 10, "count slider range follows the pet bar's 10 buttons")
item(wLayout.menu, "Rows").set()
check(P(W).pet.layoutBy == "rows" and selectedRadio(wLayout.menu) == "Rows", "layout-by dropdown switches to rows")
local labels = {}
for _, fs in ipairs(W.fontStrings) do labels[fs.text or ""] = true end
check(labels.Rows and not labels.Columns, "count slider label reads Rows")
ws[1]:SetValue(2)
check(P(W).pet.rows == 2 and W.BespokeBarpet.cols == 5, "rows slider sets rows")
item(wGrow.menu, "Up").set()
check(P(W).pet.growUp == true and selectedRadio(wGrow.menu) == "Up", "grow dropdown sets growth")
item(wNewChars.menu, "Default").set()
check(W.BespokeDB.newCharProfile == "Default", "new-characters dropdown works")

------------------------------------------------------------------ 1.3.2: edit pet/stance bars on any character
local function ghostsShown(bar)
	local n = 0
	for _, g in ipairs(bar.ghosts or {}) do if g.shown and g.parent == bar.overlay then n = n + 1 end end
	return n
end
local Mage = NewEnv({ char = "Mage" })
Mage.forms, Mage.hasPet = 0, false
Mage.fire("PLAYER_LOGIN")
local mStance, mPet = Mage.BespokeBarstance, Mage.BespokeBarpet
check(not mPet.shown and mStance.w == 30, "locked: no pet bar, empty stance bar")
Mage.slash("unlock")
check(mStance.w == 10 * 32 - 2 and mStance.h == 30 and ghostsShown(mStance) == 10, "unlocked: stance bar previews 10 slots on a class without forms")
check(mPet.shown and ghostsShown(mPet) == 10 and mPet.w == 10 * 32 - 2, "unlocked: pet bar previews 10 slots without a pet")
Mage.slash("bar stance cols 5")
check(mStance.w == 5 * 32 - 2 and mStance.h == 2 * 32 - 2 and ghostsShown(mStance) == 10, "layout changes show in the preview")
Mage.slash("lock")
check(ghostsShown(mStance) == 0 and not mStance.overlay.shown and mStance.w == 30, "locking hides the preview")
check(mPet.visDriver == "[@pet,exists,nopossessbar] show; hide" and not mPet.shown, "and the pet bar goes back to pet-only")

-- options window on the mage: stance and pet ranges cover all 10 slots
local MW = NewEnv({ char = "Mage2", files = { ADDON_FILE, OPTIONS_FILE } })
MW.forms = 0
MW.fire("PLAYER_LOGIN")
MW.slash("")
local mwBars, mwCount
for _, f in ipairs(MW.frames) do
	if f.gen and item(f.menu or { items = {} }, "Stance bar") then mwBars = f end
	if f.cb and not mwCount then mwCount = f end
end
item(mwBars.menu, "Stance bar").set()
check(mwCount.max == 10, "options: stance count slider spans 10 slots on a class without forms")

-- a warrior's real stance buttons don't move when the preview appears
local War = NewEnv({ char = "Warrior" })
War.forms = 3
War.fire("PLAYER_LOGIN")
local wStance = War.BespokeBarstance
local sp = War.StanceButton1.points[1]
local left, top = wStance:GetLeft(), wStance:GetTop()
War.slash("unlock")
local sp2 = War.StanceButton1.points[1]
check(math.abs(wStance:GetLeft() - left) < 1e-6 and math.abs(wStance:GetTop() - top) < 1e-6, "preview keeps the bar's top-left corner in place")
check(sp2[2] == sp[2] and sp2[3] == sp[3] and sp2[4] == sp[4] and sp2[5] == sp[5], ("stance button 1 stays in the same spot (%s %s,%s -> %s %s,%s)"):format(sp[3], sp[4], sp[5], sp2[3], sp2[4], sp2[5]))
check(ghostsShown(wStance) == 10 and wStance.w == 10 * 32 - 2, "real stances plus placeholder slots")
War.slash("lock")
check(wStance.w == 3 * 32 - 2 and math.abs(wStance:GetTop() - top) < 1e-6, "locking returns to the 3 real stances, same corner")

-- locking during combat must not touch protected state
local Cmb = NewEnv({ char = "Hunter" })
Cmb.hasPet = true
Cmb.fire("PLAYER_LOGIN")
Cmb.slash("unlock")
Cmb.combat = true
Cmb.slash("lock")
check(#Cmb.blocked == 0 and not Cmb.BespokeBarpet.overlay.shown, "lock in combat: overlays hide, nothing protected touched")
check(Cmb.BespokeBarstance.w == 10 * 32 - 2, "preview size waits for combat to end")
Cmb.combat = false
Cmb.fire("PLAYER_REGEN_ENABLED")
check(Cmb.BespokeBarpet.visDriver == "[@pet,exists,nopossessbar] show; hide" and Cmb.BespokeBarstance.w == 3 * 32 - 2, "after combat: pet-only again, stance back to real size")

------------------------------------------------------------------ 1.4: scale 40%, fade, which
local F = NewEnv({ files = { ADDON_FILE, OPTIONS_FILE } })
F.fire("PLAYER_LOGIN")
F.slash("bar 2 scale 0.4")
check(P(F)[2].scale == 0.4 and F.BespokeBar2.scale == 0.4, "scale goes down to 40%")
F.slash("bar 2 scale 0.1")
check(P(F)[2].scale == 0.4, "scale clamps at 40%")

local function tick(dt)
	for _, f in ipairs(F.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end end
end
local fb = F.BespokeBar2
F.slash("bar 2 fade on")
check(P(F)[2].fade == true, "fade setting saved")
tick(0.05)
check(fb:GetAlpha() < 1 and fb:GetAlpha() > 0, "fading out, not instant-hidden (" .. fb:GetAlpha() .. ")")
tick(0.2)
check(fb:GetAlpha() == 0, "fully faded within 0.2s")
check(F.BespokeBar1:GetAlpha() == 1, "other bars unaffected")
F.hover = fb
tick(0.01)
check(fb:GetAlpha() == 1, "mouseover shows the bar at once")
F.hover = nil
tick(0.1)
check(fb:GetAlpha() > 0 and fb:GetAlpha() < 1, "leaving starts a quick fade")
tick(0.2)
check(fb:GetAlpha() == 0, "gone again")
F.slash("unlock")
tick(0.01)
check(math.abs(fb:GetAlpha() - 0.4) < 1e-9, "unlocking brings a faded bar straight up to 40% (visible, placeable, clearly faded)")
tick(0.5)
check(math.abs(fb:GetAlpha() - 0.4) < 1e-9, "and it stays at 40% while unlocked")
F.hover = fb
tick(0.01)
check(fb:GetAlpha() == 1, "unlocked: hovering shows it fully")
F.hover = nil
F.slash("lock")
tick(0.5)
F.combat = true
F.hover = fb
tick(0.01)
check(fb:GetAlpha() == 1 and #F.blocked == 0, "fade works in combat without touching protected state")
F.combat = false
F.hover = nil
tick(0.5)
check(fb:GetAlpha() == 0, "faded out before switching fade off")
F.slash("bar 2 fade off")
local polling = false
for _, f in ipairs(F.frames) do if f.scripts.OnUpdate then polling = true end end
check(fb:GetAlpha() == 1 and not polling, "fade off: bar opaque and no polling left running")

-- options window: fade checkbox, 40% scale floor
F.slash("")
local fadeBox, scaleSlider
for _, f in ipairs(F.frames) do
	if f.isCheckbox and f.Text.text == "Fade out until mouseover" then fadeBox = f end
	if f.cb and f.min == 0.4 then scaleSlider = f end
end
check(fadeBox and scaleSlider and scaleSlider.steps == 32, "options: fade checkbox and scale from 40%")
fadeBox:Click()
check(P(F)[1].fade == true, "options fade checkbox sets fade on the selected bar")

-- /bespoke which
F.mouseFocus = F.BespokeBar2Button5
F.slash("which")
check(printed(F, "BespokeBar2Button5 < BespokeBar2") and printed(F, "Bespoke's Bar 2"), "which names a Bespoke button and its bar")
F.mouseFocus = F.MultiBarBottomLeftButton3
F.slash("which")
check(printed(F, "MultiBarBottomLeftButton3") and printed(F, "not a Bespoke bar"), "which recognises other frames")
F.mouseFocus = nil
F.slash("which")
check(printed(F, "nothing clickable"), "which handles an empty spot")

------------------------------------------------------------------ 1.4.1: stray stance buttons after Edit Mode
local S0 = NewEnv({ char = "NoForms" })
S0.forms = 0
S0.fire("PLAYER_LOGIN")
S0.StanceBar:EditModeForceShow()
local strays = 0
for i = 1, 10 do if S0["StanceButton" .. i]:IsVisible() then strays = strays + 1 end end
check(strays == 0, "Edit Mode force-show leaves no visible stance buttons on a class without forms (" .. strays .. " visible)")
S0.slash("bar stance off"); S0.slash("bar stance on")
strays = 0
for i = 1, 10 do if S0["StanceButton" .. i]:IsVisible() then strays = strays + 1 end end
check(strays == 0, "toggling the stance bar doesn't bring them back")

local S3 = NewEnv({ char = "ThreeForms" })
S3.forms = 3
S3.fire("PLAYER_LOGIN")
S3.StanceButton1.shown, S3.StanceButton2.shown, S3.StanceButton3.shown = true, true, true
S3.StanceBar:EditModeForceShow()
local visible = {}
for i = 1, 10 do if S3["StanceButton" .. i]:IsVisible() then visible[#visible + 1] = i end end
check(#visible == 3 and visible[3] == 3, "only your 3 stances are visible after Edit Mode")
check(S3.StanceButton2.points[1][2] == S3.BespokeBarstance, "and they're in Bespoke's stance bar")
S3.forms = 4
S3.fire("UPDATE_SHAPESHIFT_FORMS")
check(S3.StanceButton4.parent == S3.BespokeBarstance and S3.StanceButton4.points[1][2] == S3.BespokeBarstance, "a newly learned form moves into the bar")

------------------------------------------------------------------ 1.4.2: fade Bar 4 while unlocked (reported)
local R = NewEnv()
R.fire("PLAYER_LOGIN")
local function rtick(dt) for _, f in ipairs(R.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end end end
R.slash("unlock")
R.slash("bar 4 fade on")
rtick(0.5)
check(math.abs(R.BespokeBar4:GetAlpha() - 0.4) < 1e-9, "fade on while unlocked gives visible feedback (dims to 40%)")
R.mouseFocus = R.BespokeBar4Button2
R.slash("which")
check(printed(R, "Bespoke's Bar 4: fade on, bars unlocked"), "which explains why the bar isn't fully faded")
R.slash("lock")
rtick(0.5)
check(R.BespokeBar4:GetAlpha() == 0, "once locked, Bar 4 fades out completely")
R.slash("which")
check(printed(R, "fade on, bars locked, opacity 0%%"), "which reports the faded state")

for i, e in ipairs(ALL_ENVS) do
	local stray
	for _, f in ipairs(e.frames) do
		local parent = f.parent
		if parent and parent.name and parent.name:find("^BespokeBar") and f:IsVisible() and #f.points > 0
			and f.points[1][2] ~= parent then
			stray = f.name or "unnamed frame"
		end
	end
	check(stray == nil, ("scenario %d: nothing on a Bespoke bar is left at Blizzard's position (%s)"):format(i, tostring(stray)))
	check(#e.blocked == 0, ("scenario %d had no blocked actions (%s)"):format(i, tostring(e.blocked[1])))
	check(#e.scriptErrors == 0, ("scenario %d finished without script errors (%s)"):format(i, tostring(e.scriptErrors[1])))
end
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
