-- Bespoke: light, stateless bars for WoW: Forever.
--
-- Action buttons are Blizzard's own ActionBarButtonTemplate with a fixed
-- "actionpage", so Blizzard's secure code resolves the slot and draws
-- everything. There is no paging and no state, so no secure snippets.
-- Pet, stance, bag and micro menu bars reuse Blizzard's own buttons.
local ADDON, ns = ...

local ACTION_BUTTONS = 12
local PET_VISIBILITY = "[@pet,exists,nopossessbar] show; hide"

-- Action bar N matches Blizzard's "Action Bar N": same slots, same keybindings.
local ACTION = {
	{ page = 1,  binding = "ACTIONBUTTON",          blizzBar = "MainActionBar",       blizzButton = "ActionButton" },
	{ page = 6,  binding = "MULTIACTIONBAR1BUTTON", blizzBar = "MultiBarBottomLeft",  blizzButton = "MultiBarBottomLeftButton" },
	{ page = 5,  binding = "MULTIACTIONBAR2BUTTON", blizzBar = "MultiBarBottomRight", blizzButton = "MultiBarBottomRightButton" },
	{ page = 3,  binding = "MULTIACTIONBAR3BUTTON", blizzBar = "MultiBarRight",       blizzButton = "MultiBarRightButton" },
	{ page = 4,  binding = "MULTIACTIONBAR4BUTTON", blizzBar = "MultiBarLeft",        blizzButton = "MultiBarLeftButton" },
	{ page = 13, binding = "MULTIACTIONBAR5BUTTON", blizzBar = "MultiBar5",           blizzButton = "MultiBar5Button" },
	{ page = 14, binding = "MULTIACTIONBAR6BUTTON", blizzBar = "MultiBar6",           blizzButton = "MultiBar6Button" },
	{ page = 15, binding = "MULTIACTIONBAR7BUTTON", blizzBar = "MultiBar7",           blizzButton = "MultiBar7Button" },
}

-- Every bar Bespoke owns, in display order.
local BAR_IDS = { 1, 2, 3, 4, 5, 6, 7, 8, "pet", "stance", "bags", "micro" }
local NAMES = { pet = "Pet bar", stance = "Stance bar", bags = "Bag bar", micro = "Micro menu" }
-- Bags and micro buttons aren't protected, so those bars may re-layout in combat.
local UNPROTECTED = { bags = true, micro = true }

local DEFAULTS = {
	{ enabled = true,  point = "BOTTOM", x = 0,   y = 20,  columns = 12 },
	{ enabled = true,  point = "BOTTOM", x = 0,   y = 69,  columns = 12 },
	{ enabled = true,  point = "BOTTOM", x = 0,   y = 118, columns = 12 },
	{ enabled = true,  point = "RIGHT",  x = -5,  y = 0,   columns = 1 },
	{ enabled = true,  point = "RIGHT",  x = -54, y = 0,   columns = 1 },
	{ enabled = false, point = "BOTTOM", x = 0,   y = 167, columns = 12 },
	{ enabled = false, point = "BOTTOM", x = 0,   y = 216, columns = 12 },
	{ enabled = false, point = "BOTTOM", x = 0,   y = 265, columns = 12 },
	pet    = { enabled = true, point = "BOTTOM",      x = 160,  y = 167, columns = 10 },
	stance = { enabled = true, point = "BOTTOM",      x = -200, y = 167, columns = 10 },
	bags   = { enabled = true, point = "BOTTOMRIGHT", x = -5,   y = 5,   columns = 14 },
	micro  = { enabled = true, point = "BOTTOMRIGHT", x = -5,   y = 55,  columns = 14 },
}
local SHARED_DEFAULTS = { scale = 1, padding = 2, growUp = false, layoutBy = "columns", rows = 1, fade = false }
local PROFILE_VERSION = 2 -- 2: positions stored in screen units

local db        -- saved root: profiles, character -> profile, lock state
local profile   -- this character's active profile
local charKey
local bars = {}
local pending = {}   -- work deferred until combat ends
local lastBindingSig

local function Print(msg)
	print("|cff33ff99Bespoke|r: " .. msg)
end

----------------------------------------------------------------------
-- Saved settings: named profiles, account-wide.
----------------------------------------------------------------------

local function BarDefaults(id)
	local d = {}
	for k, v in pairs(SHARED_DEFAULTS) do d[k] = v end
	for k, v in pairs(DEFAULTS[id]) do d[k] = v end
	d.relPoint = d.point
	return d
end

local function FillDefaults(p)
	p.bars = p.bars or {}
	if (p.version or 1) < 2 then -- 1.2.0 stored positions in the bar's own scale
		for _, cfg in pairs(p.bars) do
			if cfg.x and cfg.scale then cfg.x, cfg.y = cfg.x * cfg.scale, cfg.y * cfg.scale end
		end
	end
	p.version = PROFILE_VERSION
	for _, id in ipairs(BAR_IDS) do
		p.bars[id] = p.bars[id] or {}
		for k, v in pairs(BarDefaults(id)) do
			if p.bars[id][k] == nil then p.bars[id][k] = v end
		end
	end
	return p
end

local function LoadSettings()
	BespokeDB = BespokeDB or {}
	db = BespokeDB
	db.profiles = db.profiles or {}
	db.chars = db.chars or {}
	if db.bars then -- 1.0.0 kept a single layout at the top level
		db.profiles.Default = db.profiles.Default or { bars = db.bars }
		db.bars = nil
	end
	if db.locked == nil then db.locked = true end
	db.newCharProfile = db.newCharProfile or "Default"
	charKey = UnitName("player") .. " - " .. GetRealmName()
	local name = db.chars[charKey]
	if not (name and db.profiles[name]) then
		name = db.profiles[db.newCharProfile] and db.newCharProfile or "Default"
	end
	db.chars[charKey] = name
	db.profiles[name] = FillDefaults(db.profiles[name] or {})
	profile = db.profiles[name]
end

----------------------------------------------------------------------
-- Take over Blizzard's bars
----------------------------------------------------------------------

local hider = CreateFrame("Frame")
hider:Hide()

-- Setting a key to nil from addon code leaves it tainted; nudge the table
-- until the key is secure again so Edit Mode can read it safely.
local function PurgeKey(t, k)
	t[k] = nil
	local c = 42
	repeat
		if t[c] == nil then t[c] = nil end
		c = c + 1
	until issecurevariable(t, k)
end

local function HideBlizzardBar(frame, clearEvents)
	if not frame then return end
	if clearEvents then frame:UnregisterAllEvents() end
	if frame.system then PurgeKey(frame, "isShownExternal") end
	if frame.HideBase then frame:HideBase() else frame:Hide() end
	frame:SetParent(hider)
end

local Relayout -- defined below

local function HideBlizzard()
	for id, info in ipairs(ACTION) do
		HideBlizzardBar(_G[info.blizzBar], id ~= 1)
		for i = 1, ACTION_BUTTONS do
			local button = _G[info.blizzButton .. i]
			if button then
				button:Hide()
				button:UnregisterAllEvents()
				button:SetAttribute("statehidden", true)
				button.bar = nil
			end
		end
	end
	-- Pet and stance bars keep their events: Blizzard still refreshes the buttons we reuse.
	HideBlizzardBar(PetActionBar, false)
	HideBlizzardBar(StanceBar, false)
	HideBlizzardBar(BagsBar, false)
	HideBlizzardBar(MicroMenuContainer, false)
	-- Blizzard re-lays out bag and micro buttons; put them back in our bars afterwards.
	if BagsBar then hooksecurefunc(BagsBar, "Layout", function() Relayout("bags") end) end
	if MainMenuBarBagManager then hooksecurefunc(MainMenuBarBagManager, "OnExpandBarChanged", function() Relayout("bags") end) end
	if UpdateMicroButtons then hooksecurefunc("UpdateMicroButtons", function() Relayout("micro") end) end
	-- The collapse arrow lived on Blizzard's bag bar, so keep bags expanded.
	SetCVar("expandBagBar", 1)
end

----------------------------------------------------------------------
-- Buttons for each bar
----------------------------------------------------------------------

-- Keybinds click a hidden plain secure button, which honours the
-- "cast on key down" setting; mirror the press on the visible button.
local function KeyPreClick(self, _, down)
	local owner = self:GetParent()
	if down then
		if owner:GetButtonState() == "NORMAL" then owner:SetButtonState("PUSHED") end
	elseif owner:GetButtonState() == "PUSHED" then
		owner:SetButtonState("NORMAL")
	end
end

local function CreateActionButton(bar, info, i)
	local button = CreateFrame("CheckButton", ("%sBar%dButton%d"):format(ADDON, bar.id, i), bar, "ActionBarButtonTemplate")
	button:SetID(i)
	button.buttonType = info.binding
	button.commandName = info.binding .. i          -- lets Quick Keybind mode bind this button
	button:SetAttribute("actionpage", info.page)    -- fixed page: the whole "no state" design
	button:UpdateHotkeys(button.buttonType)

	local key = CreateFrame("Button", "$parentKey", button, "SecureActionButtonTemplate")
	key:SetAttribute("type", "action")
	key:SetAttribute("typerelease", "actionrelease")
	key:SetAttribute("action", (info.page - 1) * ACTION_BUTTONS + i)
	for _, attr in ipairs({ "checkselfcast", "checkfocuscast", "checkmouseovercast", "unit", "pressAndHoldAction" }) do
		key:SetAttribute("useparent-" .. attr, true)
	end
	key:RegisterForClicks("AnyUp", "AnyDown")
	key:SetScript("PreClick", KeyPreClick)
	button.key = key
	return button
end

-- Pet and stance bars preview this many slots while unlocked.
local PREVIEW_SLOTS = { pet = 10, stance = 10 }

local function BlizzardButtons(bar, prefix, count)
	local list = {}
	for i = 1, count do
		local button = (bar and bar.actionButtons and bar.actionButtons[i]) or _G[prefix .. i]
		if button then list[#list + 1] = button end
	end
	return list
end

-- Every button a pet or stance bar can hold, shown or not.
local function CapacityButtons(bar)
	if bar.id == "pet" then return BlizzardButtons(PetActionBar, "PetActionButton", 10) end
	return BlizzardButtons(StanceBar, "StanceButton", 10)
end

-- Buttons currently laid out on a bar, in order.
local function GetButtons(bar)
	local id = bar.id
	if type(id) == "number" then
		return bar.buttons
	elseif id == "pet" then
		return BlizzardButtons(PetActionBar, "PetActionButton", 10)
	elseif id == "stance" then
		return BlizzardButtons(StanceBar, "StanceButton", GetNumShapeshiftForms() or 0)
	elseif id == "bags" then
		-- Blizzard shows bags right to left from the backpack; keep that look.
		local all = { MainMenuBarBackpackButton }
		if MainMenuBarBagManager then
			for _, button in MainMenuBarBagManager:EnumerateBagButtons() do
				if button ~= MainMenuBarBackpackButton then all[#all + 1] = button end
			end
		end
		local list = {}
		for i = #all, 1, -1 do
			if all[i] and all[i]:IsShown() then list[#list + 1] = all[i] end
		end
		return list
	elseif id == "micro" then
		local list = {}
		for _, button in ipairs(bar.micro) do
			if button:IsShown() then list[#list + 1] = button end
		end
		return list
	end
end

-- Take every button Blizzard's micro menu lays out (layoutIndex marks the ones
-- Forever's game rules added), hidden ones first. Blizzard's menu re-lays itself
-- out each time a shown button leaves, and errors (GetEdgeButton) if only
-- unpositioned hidden buttons remain. Moving hidden buttons fires no OnShow, and
-- once the menu is empty GetEdgeButton safely returns nil. Unlike clearing
-- layoutIndex, this writes nothing into Blizzard's tables.
local function AdoptMicroButtons(bar)
	bar.micro = bar.micro or {}
	bar.microSet = bar.microSet or {}
	if not MicroMenu then return end
	local found = {}
	for _, child in ipairs({ MicroMenu:GetChildren() }) do
		if child.layoutIndex and not bar.microSet[child] then found[#found + 1] = child end
	end
	for pass = 1, 2 do
		for _, button in ipairs(found) do
			if button:IsShown() == (pass == 2) then
				button:SetParent(bar)
				bar.microSet[button] = true
				bar.micro[#bar.micro + 1] = button
			end
		end
	end
	table.sort(bar.micro, function(a, b) return a.layoutIndex < b.layoutIndex end)
end

local function AdoptAll(bar)
	if bar.id == "stance" then
		-- Buttons beyond your forms wait out of sight. Blizzard can still show them
		-- (Edit Mode force-shows all 10, and with 0 forms nothing hides them again),
		-- and on our bar they'd appear where Blizzard's hidden stance bar sits.
		local forms = GetNumShapeshiftForms() or 0
		for i, button in ipairs(BlizzardButtons(StanceBar, "StanceButton", 10)) do
			button:SetParent(i <= forms and bar or hider)
		end
	elseif bar.id == "micro" then
		AdoptMicroButtons(bar)
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

local function Grid(cfg, n)
	n = math.max(n, 1)
	local cols
	if cfg.layoutBy == "rows" then
		cols = math.ceil(n / math.max(1, math.min(cfg.rows, n)))
	else
		cols = math.max(1, math.min(cfg.columns, n))
	end
	return cols, math.ceil(n / cols)
end

-- Anchor the bar at the corner its growth moves away from, in screen units,
-- so extra rows extend in the chosen direction and scaling doesn't drift.
local function SavePosition(bar)
	local cfg = profile.bars[bar.id]
	local left = bar:GetLeft()
	if not left then return end
	local s = bar:GetScale()
	cfg.point = cfg.growUp and "BOTTOMLEFT" or "TOPLEFT"
	cfg.relPoint = "BOTTOMLEFT"
	cfg.x = left * s
	cfg.y = (cfg.growUp and bar:GetBottom() or bar:GetTop()) * s
end

local function CreateOverlay(bar)
	local overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(bar:GetFrameLevel() + 20)
	overlay:EnableMouse(true)
	overlay:RegisterForDrag("LeftButton")
	local bg = overlay:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.2, 0.6, 1, 0.45)
	local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(ns.BarName(bar.id))
	overlay:SetScript("OnDragStart", function() if not InCombatLockdown() then bar:StartMoving() end end)
	overlay:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); SavePosition(bar) end)
	overlay:Hide()
	return overlay
end

local function UpdateVisibility(bar)
	local cfg = profile.bars[bar.id]
	if bar.id == "pet" then
		-- Visibility only, not paging: Blizzard's state manager shows/hides the
		-- frame directly, with no secure snippet involved.
		if cfg.enabled then
			RegisterStateDriver(bar, "visibility", db.locked and PET_VISIBILITY or "show")
		else
			UnregisterStateDriver(bar, "visibility")
			bar:Hide()
		end
	else
		bar:SetShown(cfg.enabled)
	end
	bar.overlay:SetShown(cfg.enabled and not db.locked)
end

-- Numbered placeholder slots, drawn in the unlock overlay (plain frames, nothing secure).
local function UpdateGhosts(bar, count, cw, ch, place)
	bar.ghosts = bar.ghosts or {}
	for i = 1, math.max(count, #bar.ghosts) do
		local ghost = bar.ghosts[i]
		if i <= count then
			if not ghost then
				ghost = CreateFrame("Frame", nil, bar.overlay)
				local tex = ghost:CreateTexture(nil, "ARTWORK")
				tex:SetAllPoints()
				tex:SetColorTexture(0, 0, 0, 0.4)
				local label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				label:SetPoint("CENTER")
				label:SetText(i)
				bar.ghosts[i] = ghost
			end
			ghost:SetSize(cw, ch)
			place(ghost, i)
			ghost:Show()
		elseif ghost then
			ghost:Hide()
		end
	end
end

local function LayoutBar(bar)
	local cfg = profile.bars[bar.id]
	AdoptAll(bar)
	local buttons = GetButtons(bar)
	-- Pet and stance bars size their cells from all 10 Blizzard buttons, and while
	-- unlocked preview all 10 slots, so they can be arranged on any character.
	local capacity = PREVIEW_SLOTS[bar.id]
	local sizing = capacity and CapacityButtons(bar) or buttons
	local cw, ch = 1, 1
	for _, button in ipairs(sizing) do
		cw = math.max(cw, button:GetWidth())
		ch = math.max(ch, button:GetHeight())
	end
	if #sizing == 0 then cw, ch = 30, 30 end -- keep an empty bar grabbable while unlocked
	local preview = capacity and not db.locked
	local slots = preview and capacity or #buttons
	local cols, rows = Grid(cfg, slots)
	bar.cols, bar.rows = cols, rows
	local stepX, stepY = cw + cfg.padding, ch + cfg.padding
	local function place(frame, i)
		local cx = ((i - 1) % cols) * stepX + cw / 2
		local cy = math.floor((i - 1) / cols) * stepY + ch / 2
		frame:ClearAllPoints()
		if cfg.growUp then
			frame:SetPoint("CENTER", bar, "BOTTOMLEFT", cx, cy)
		else
			frame:SetPoint("CENTER", bar, "TOPLEFT", cx, -cy)
		end
	end
	for i, button in ipairs(buttons) do
		button:SetParent(bar)
		place(button, i)
	end
	if capacity then UpdateGhosts(bar, preview and slots or 0, cw, ch, place) end
	bar:SetSize(math.max(1, cols * stepX - cfg.padding), math.max(1, rows * stepY - cfg.padding))
	bar:SetScale(cfg.scale)
	bar:ClearAllPoints()
	bar:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x / cfg.scale, cfg.y / cfg.scale)
	UpdateVisibility(bar)
end

local function GetBar(id)
	if not bars[id] then
		local bar = CreateFrame("Frame", ADDON .. "Bar" .. id, UIParent)
		bar.id = id
		bar:SetMovable(true)
		bar:SetClampedToScreen(true)
		if type(id) == "number" then
			bar.buttons = {}
			for i = 1, ACTION_BUTTONS do
				bar.buttons[i] = CreateActionButton(bar, ACTION[id], i)
			end
		end
		bar.overlay = CreateOverlay(bar)
		bars[id] = bar
	end
	return bars[id]
end

function Relayout(id)
	local bar = bars[id]
	if not (bar and profile.bars[id].enabled) then return end
	if InCombatLockdown() and not UNPROTECTED[id] then pending.layout = true return end
	LayoutBar(bar)
end

----------------------------------------------------------------------
-- Keybindings: action bars reuse whatever is bound to Blizzard's
-- Action Bar N. Pet and stance buttons are Blizzard's, so theirs just work.
----------------------------------------------------------------------

local function UpdateBindings()
	if InCombatLockdown() then pending.bindings = true return end
	-- SetOverrideBinding fires UPDATE_BINDINGS; skip when nothing changed
	local wanted, sig = {}, {}
	for id, bar in pairs(bars) do
		if type(id) == "number" then
			for _, button in ipairs(bar.buttons) do
				wanted[button] = profile.bars[id].enabled and { GetBindingKey(button.commandName) } or {}
				sig[#sig + 1] = button:GetName() .. "=" .. table.concat(wanted[button], ",")
			end
		end
	end
	table.sort(sig)
	local signature = table.concat(sig, ";")
	if signature == lastBindingSig then return end
	lastBindingSig = signature
	for button, keys in pairs(wanted) do
		ClearOverrideBindings(button.key)
		for _, key in ipairs(keys) do
			SetOverrideBindingClick(button.key, false, key, button.key:GetName(), "LeftButton")
		end
	end
end

----------------------------------------------------------------------
-- Settings API, shared by the slash commands and the options window
----------------------------------------------------------------------

local LIMITS = { columns = { 1, 14 }, rows = { 1, 14 }, scale = { 0.4, 2 }, padding = { -2, 20 } }
ns.LIMITS = LIMITS
ns.BAR_IDS = BAR_IDS
ns.Print = Print

function ns.BarName(id) return NAMES[id] or ("Bar " .. id) end

local function Changed()
	if ns.OnChanged then ns.OnChanged() end
end

----------------------------------------------------------------------
-- Fade: a faded bar is invisible until the mouse is over it, then fades out
-- quickly. Alpha isn't protected, so this also works in combat; keybinds and
-- clicks keep working while a bar is faded out.
----------------------------------------------------------------------

local FADE_OUT_SECONDS = 0.2
local UNLOCKED_FADE_ALPHA = 0.4 -- while unlocked, faded bars dim instead of vanishing, so you can see and place them
local fader = CreateFrame("Frame")

local function FadeTick(_, elapsed)
	for id, bar in pairs(bars) do
		local cfg = profile.bars[id]
		local target = 1
		if cfg.fade and not bar:IsMouseOver() then
			target = db.locked and 0 or UNLOCKED_FADE_ALPHA
		end
		local alpha = bar:GetAlpha()
		if target > alpha then
			alpha = target -- appear at once
		elseif target < alpha then
			alpha = math.max(target, alpha - elapsed / FADE_OUT_SECONDS)
		end
		if alpha ~= bar:GetAlpha() then bar:SetAlpha(alpha) end
	end
end

-- Only poll while some bar fades; otherwise make sure every bar is opaque.
local function UpdateFader()
	for id in pairs(bars) do
		if profile.bars[id].enabled and profile.bars[id].fade then
			fader:SetScript("OnUpdate", FadeTick)
			return
		end
	end
	fader:SetScript("OnUpdate", nil)
	for _, bar in pairs(bars) do bar:SetAlpha(1) end
end

local function ApplyAll()
	if InCombatLockdown() then pending.layout = true return end
	for _, id in ipairs(BAR_IDS) do
		if profile.bars[id].enabled or bars[id] then LayoutBar(GetBar(id)) end
	end
	UpdateBindings()
	UpdateFader()
	Changed()
end

local function CanChange()
	if InCombatLockdown() then Print("settings can't change in combat.") return false end
	return true
end

function ns.GetBarConfig(id) return profile.bars[id] end
function ns.IsLocked() return db.locked end
function ns.CurrentProfile() return db.chars[charKey] end
function ns.NewCharacterProfile() return db.newCharProfile end

-- How many buttons the bar lays out right now (sets the slider range).
function ns.ButtonCount(id)
	if PREVIEW_SLOTS[id] then return PREVIEW_SLOTS[id] end -- arrange for capacity, whatever this character has
	return bars[id] and #GetButtons(bars[id]) or (type(id) == "number" and ACTION_BUTTONS or 1)
end

function ns.GetProfiles()
	local names = {}
	for name in pairs(db.profiles) do names[#names + 1] = name end
	table.sort(names)
	return names
end

function ns.ProfileUsers(name)
	local users = {}
	for char, p in pairs(db.chars) do
		if p == name then users[#users + 1] = char end
	end
	table.sort(users)
	return users
end

local SIZE_KEYS = { columns = true, rows = true, layoutBy = true, padding = true, scale = true, growUp = true }

function ns.SetBarOption(id, key, value)
	if not CanChange() then return end
	local cfg, bar = profile.bars[id], bars[id]
	if key == "enabled" or key == "growUp" or key == "fade" then
		cfg[key] = not not value
	elseif key == "layoutBy" then
		-- keep the bar looking the same when switching what you count
		if value == "rows" and bar and bar.rows then cfg.rows = bar.rows end
		if value == "columns" and bar and bar.cols then cfg.columns = bar.cols end
		cfg.layoutBy = (value == "rows") and "rows" or "columns"
	else
		cfg[key] = math.max(LIMITS[key][1], math.min(LIMITS[key][2], value))
	end
	if SIZE_KEYS[key] and bar and cfg.enabled then SavePosition(bar) end
	ApplyAll()
end

function ns.ResetProfile()
	if not CanChange() then return end
	for _, id in ipairs(BAR_IDS) do profile.bars[id] = BarDefaults(id) end
	ApplyAll()
	Print("layout reset.")
end

function ns.SetLocked(locked)
	if not locked and InCombatLockdown() then Print("can't unlock in combat.") return end
	db.locked = locked
	for id, bar in pairs(bars) do
		if locked then bar:StopMovingOrSizing() end
		if not profile.bars[id].enabled then
			-- nothing to show or hide
		elseif InCombatLockdown() then
			-- locking mid-combat: overlays are plain frames and can hide now; the
			-- pet driver and preview sizes change once combat ends
			bar.overlay:Hide()
			pending.layout = true
		elseif PREVIEW_SLOTS[id] then
			SavePosition(bar) -- pin the growth corner so the preview doesn't shift real buttons
			LayoutBar(bar)
		else
			UpdateVisibility(bar)
		end
	end
	Changed()
end

local function UseProfile(name)
	db.profiles[name] = FillDefaults(db.profiles[name] or {})
	db.chars[charKey] = name
	profile = db.profiles[name]
	ApplyAll()
end

-- use | new | delete | newchars; returns true on success
function ns.ProfileCommand(action, name)
	local current = db.chars[charKey]
	if not CanChange() then return end
	if name == "" then Print("give a profile name, e.g. /bespoke profile " .. action .. " Raid") return end
	if action == "use" then
		if not db.profiles[name] then Print(("no profile named %q; create it with /bespoke profile new %s"):format(name, name)) return end
		UseProfile(name)
		Print(("now using %q."):format(name))
	elseif action == "new" then
		if db.profiles[name] then Print(("%q already exists."):format(name)) return end
		db.profiles[name] = CopyTable(profile)
		UseProfile(name)
		Print(("created %q from %q and switched to it."):format(name, current))
	elseif action == "delete" then
		if not db.profiles[name] then Print(("no profile named %q."):format(name)) return end
		if name == "Default" or name == current then Print("can't delete Default or the profile you're using.") return end
		db.profiles[name] = nil
		for char, p in pairs(db.chars) do
			if p == name then db.chars[char] = "Default" end
		end
		if db.newCharProfile == name then db.newCharProfile = "Default" end
		Print(("deleted %q; characters using it now use Default."):format(name))
		Changed()
	elseif action == "newchars" then
		if not db.profiles[name] then Print(("no profile named %q."):format(name)) return end
		db.newCharProfile = name
		Print(("new characters will start on %q."):format(name))
		Changed()
	else
		Print("profile commands: use, new, delete, newchars")
		return
	end
	return true
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

-- Name the frame under the mouse and say whether Bespoke owns it.
local function Which()
	local focus = GetMouseFoci and GetMouseFoci()[1]
	if not focus or focus == WorldFrame then
		Print("nothing clickable under the mouse: hover it, then press Enter on /bespoke which.")
		return
	end
	local chain, ownerId, frame = {}, nil, focus
	while frame and #chain < 6 do
		chain[#chain + 1] = frame:GetName() or ("unnamed " .. frame:GetObjectType())
		for id, bar in pairs(bars) do
			if frame == bar then ownerId = id end
		end
		frame = frame:GetParent()
	end
	Print(table.concat(chain, " < "))
	if not ownerId then Print("that's not a Bespoke bar.") return end
	local cfg = profile.bars[ownerId]
	Print(("that's Bespoke's %s: fade %s, bars %s, opacity %d%%."):format(ns.BarName(ownerId),
		cfg.fade and "on" or "off", db.locked and "locked" or "unlocked (fade only dims)",
		math.floor(bars[ownerId]:GetAlpha() * 100 + 0.5)))
end

local HELP = {
	"/bespoke  - open the options window",
	"/bespoke unlock | lock  - drag bars while unlocked",
	"/bespoke bar <1-8 | pet | stance | bags | micro> on | off",
	"/bespoke bar <bar> cols <n> | rows <n>  - lay out by columns or by rows",
	"/bespoke bar <bar> grow up | down",
	"/bespoke bar <bar> scale <0.4-2> | padding <-2-20>",
	"/bespoke bar <bar> fade on | off  - hide until mouseover",
	"/bespoke reset  - restore the default layout in the current profile",
	"/bespoke which  - hover something and type this to see what it is",
	"/bespoke profile  - list profiles and who uses them",
	"/bespoke profile use | new | delete <name>  - new copies the current profile",
	"/bespoke profile newchars <name>  - profile new characters start on",
}

local function ShowHelp()
	for _, line in ipairs(HELP) do Print(line) end
end

local function ParseBarId(s)
	local n = tonumber(s)
	if n and profile.bars[n] then return n end
	if s and NAMES[s] then return s end
end

SLASH_BESPOKE1 = "/bespoke"
SlashCmdList.BESPOKE = function(msg)
	local first, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	first = strlower(first)
	if first == "" then
		if ns.ToggleOptions then ns.ToggleOptions() else ShowHelp() end
	elseif first == "profile" then
		local action, name = rest:match("^(%S*)%s*(.-)$")
		if action == "" then
			local current, list = ns.CurrentProfile(), {}
			for _, n in ipairs(ns.GetProfiles()) do
				local users = #ns.ProfileUsers(n)
				list[#list + 1] = ("%s%s [%d char%s]"):format(n, n == current and " (current)" or "", users, users == 1 and "" or "s")
			end
			Print("profiles: " .. table.concat(list, ", "))
			Print(("new characters start on %q."):format(db.newCharProfile))
		else
			ns.ProfileCommand(strlower(action), strtrim(name)) -- names keep their case
		end
	elseif first == "unlock" or first == "lock" then
		ns.SetLocked(first == "lock")
	elseif first == "which" then
		Which()
	elseif first == "reset" then
		ns.ResetProfile()
	elseif first == "bar" then
		local a, b, c = strsplit(" ", strlower(rest))
		local id = ParseBarId(a)
		if not id then Print("bar must be 1-8, pet, stance, bags or micro.") return end
		if b == "on" or b == "off" then
			ns.SetBarOption(id, "enabled", b == "on")
		elseif b == "grow" and (c == "up" or c == "down") then
			ns.SetBarOption(id, "growUp", c == "up")
		elseif (b == "cols" or b == "rows") and tonumber(c) then
			local key = (b == "cols") and "columns" or "rows"
			ns.SetBarOption(id, "layoutBy", key) -- switch mode first; switching copies the current count
			ns.SetBarOption(id, key, tonumber(c))
		elseif b == "fade" and (c == "on" or c == "off") then
			ns.SetBarOption(id, "fade", c == "on")
		elseif (b == "scale" or b == "padding") and tonumber(c) then
			ns.SetBarOption(id, b, tonumber(c))
		else
			ShowHelp()
		end
	else
		ShowHelp()
	end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local function Init()
	HideBlizzard()
	ApplyAll()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		LoadSettings()
		if InCombatLockdown() then pending.init = true else Init() end
	elseif not db or pending.init and event ~= "PLAYER_REGEN_ENABLED" then
		return
	elseif event == "PLAYER_REGEN_DISABLED" then
		if not db.locked then ns.SetLocked(true) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending.init then pending.init = nil; Init() end
		if pending.layout then pending.layout = nil; ApplyAll() end
		if pending.bindings then pending.bindings = nil; UpdateBindings() end
	elseif event == "UPDATE_BINDINGS" then
		UpdateBindings()
	elseif event == "UPDATE_SHAPESHIFT_FORMS" then
		Relayout("stance")
	end
end)
