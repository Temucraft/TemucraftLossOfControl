-- TemucraftLossOfControl: a retail-style alert when you lose control of your character (3.3.5a).
-- The spell list (Data.lua) is made from the Temucraft Spell.dbc, so our own spells are covered too.

local addonName, ns = ...
local GetTime, UnitDebuff, UnitBuff, UnitGUID, GetSpellInfo = GetTime, UnitDebuff, UnitBuff, UnitGUID, GetSpellInfo
local format, floor, pairs, bit_band = string.format, math.floor, pairs, bit.band

-- Label codes match tools/gen_loc_data.py
local LABELS = {
	[1] = "Charmed", [2] = "Stunned", [3] = "Sapped", [4] = "Incapacitated", [5] = "Feared", [6] = "Horrified",
	[7] = "Polymorphed", [8] = "Disoriented", [9] = "Asleep", [10] = "Banished", [11] = "Shackled",
	[12] = "Silenced", [13] = "Pacified", [14] = "Silenced and pacified", [15] = "Disarmed", [16] = "Rooted",
	[17] = "Frozen", [18] = "Confused",
}
local PRIORITY = {
	[1] = 100, [2] = 90, [3] = 90, [4] = 90, [9] = 85, [10] = 85, [5] = 80, [6] = 80, [7] = 80, [8] = 80,
	[11] = 80, [18] = 80, [14] = 70, [12] = 60, [13] = 55, [15] = 40, [16] = 30, [17] = 30,
}
local INTERRUPT_PRIORITY = 65
local GROUP = { [15] = "disarm", [16] = "root", [17] = "root" }
local SCHOOLS = { { 1, "Physical" }, { 2, "Holy" }, { 4, "Fire" }, { 8, "Nature" }, { 16, "Frost" }, { 32, "Shadow" }, { 64, "Arcane" } }

local defaults = {
	enabled = true,
	root = true,
	disarm = true,
	interrupt = true,
	sound = false,
	scale = 1,
	point = { "CENTER", "UIParent", "CENTER", 0, 120 },
}

local db, frame, current, lockout
local preview = false

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function schoolText(mask)
	local names = {}
	for _, s in pairs(SCHOOLS) do if mask and bit_band(mask, s[1]) ~= 0 then names[#names + 1] = s[2] end end
	if #names == 0 then return "All schools" end
	return table.concat(names, ", ")
end

local function allowed(code)
	local group = GROUP[code]
	return not group or db[group]
end

-- The strongest control effect on you right now, or nil.
local function scan()
	local best
	local function consider(name, icon, duration, expires, id, caster)
		local code = id and ns.spells[id]
		if not code or not allowed(code) then return end
		local p = PRIORITY[code]
		if not best or p > best.priority or (p == best.priority and (expires or 0) > (best.expires or 0)) then
			best = best or {}
			best.code, best.priority, best.icon, best.name, best.duration, best.expires = code, p, icon, name, duration, expires
		end
	end
	for i = 1, 40 do
		local name, _, icon, _, _, duration, expires, caster, _, _, id = UnitDebuff("player", i)
		if not name then break end
		consider(name, icon, duration, expires, id, caster)
	end
	for i = 1, 40 do
		local name, _, icon, _, _, duration, expires, caster, _, _, id = UnitBuff("player", i)
		if not name then break end
		if caster ~= "player" then consider(name, icon, duration, expires, id, caster) end
	end
	if lockout and lockout.expires > GetTime() and db.interrupt then
		if not best or INTERRUPT_PRIORITY > best.priority then return lockout end
	end
	return best
end

local function show(info)
	current = info
	if not info then
		frame:Hide()
		return
	end
	frame.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	frame.title:SetText(info.text or LABELS[info.code] or "")
	if info.duration and info.duration > 0 and info.expires and info.expires > 0 then
		frame.cooldown:SetCooldown(info.expires - info.duration, info.duration)
		frame.cooldown:Show()
	else
		frame.cooldown:Hide()
	end
	if not frame:IsShown() and db.sound then PlaySoundFile("Sound\\Interface\\RaidWarning.wav") end
	frame:Show()
	frame.t = 1
	frame:GetScript("OnUpdate")(frame, 0)
end

local function update()
	if not db.enabled or preview then return end
	local info = scan()
	if info ~= current or (info and current and (info.code ~= current.code or info.expires ~= current.expires)) then
		show(info)
	end
end

local function onUpdate(self, elapsed)
	self.t = (self.t or 0) + elapsed
	if self.t < 0.05 then return end
	self.t = 0
	if preview then return end
	local info = current
	if not info then self:Hide() return end
	local left = info.expires and info.expires > 0 and info.expires - GetTime()
	if left and left <= 0 then
		current = nil
		update()
		return
	end
	if info.school then
		self.sub:SetText(format("%s locked  |cffffffff%.1f|r", info.school, left or 0))
	elseif left then
		self.sub:SetText(format("%.1f seconds", left))
	else
		self.sub:SetText("")
	end
end

local function createFrame()
	frame = CreateFrame("Frame", "TemucraftLossOfControlFrame", UIParent)
	frame:SetSize(330, 74)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if preview then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.point = { point, "UIParent", relPoint, x, y }
	end)

	-- dark band with red edges, like retail: each half fades out to the side
	local function half(layer, left, top, bottom, height, r, g, b, a)
		local t = frame:CreateTexture(nil, layer)
		t:SetTexture("Interface\\Buttons\\WHITE8X8")
		if height then t:SetHeight(height) end
		t:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", frame, left and (top and "TOPLEFT" or "BOTTOMLEFT") or (top and "TOP" or "BOTTOM"), 0, top and -8 or 8)
		t:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT", frame, left and (top and "TOP" or "BOTTOM") or (top and "TOPRIGHT" or "BOTTOMRIGHT"), 0, top and -8 or 8)
		if left then t:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a) else t:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0) end
		return t
	end
	for _, left in pairs({ true, false }) do
		half("BACKGROUND", left, true, nil, 58, 0, 0, 0, 0.75)
		half("BORDER", left, true, nil, 2, 0.9, 0.1, 0.1, 1)
		half("BORDER", left, false, nil, 2, 0.9, 0.1, 0.1, 1)
	end

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(48, 48)
	frame.icon:SetPoint("LEFT", 60, 0)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -2)
	frame.title:SetTextColor(1, 0.82, 0)
	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.sub:SetPoint("BOTTOMLEFT", frame.icon, "BOTTOMRIGHT", 10, 4)

	local p = db.point
	frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	frame:SetScale(db.scale)
	frame:SetScript("OnUpdate", onUpdate)
	frame:Hide()
end

local function setPreview(on)
	preview = on
	frame:EnableMouse(on)
	if on then
		current = nil
		frame.icon:SetTexture("Interface\\Icons\\Spell_Frost_Stun")
		frame.title:SetText("Stunned")
		frame.sub:SetText("Drag to move, /tloc lock when done")
		frame.cooldown:Hide()
		frame:Show()
	else
		frame:Hide()
		update()
	end
end

-- Options -----------------------------------------------------------------

local panel
local function buildOptions()
	panel = CreateFrame("Frame", "TemucraftLossOfControlOptions", UIParent)
	panel.name = "Temucraft Loss of Control"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Temucraft Loss of Control")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", 16, -40)
	sub:SetText("Shows what is controlling your character and for how long. /tloc")
	local rows = {
		{ "enabled", "Show the alert" },
		{ "root", "Include roots" },
		{ "disarm", "Include disarms" },
		{ "interrupt", "Include interrupts (school lockouts)" },
		{ "sound", "Play a sound" },
	}
	for i, r in pairs(rows) do
		local cb = CreateFrame("CheckButton", "TemucraftLossOfControlOpt_" .. r[1], panel, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, -36 - i * 28)
		_G[cb:GetName() .. "Text"]:SetText(r[2])
		cb:SetScript("OnShow", function(self) self:SetChecked(db[r[1]]) end)
		cb:SetScript("OnClick", function(self)
			db[r[1]] = self:GetChecked() and true or false
			current = nil
			if db.enabled then update() else frame:Hide() end
		end)
	end
	local s = CreateFrame("Slider", "TemucraftLossOfControlOpt_scale", panel, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", 24, -230)
	s:SetWidth(200)
	s:SetMinMaxValues(0.5, 2)
	s:SetValueStep(0.05)
	_G[s:GetName() .. "Low"]:SetText("0.5")
	_G[s:GetName() .. "High"]:SetText("2")
	s:SetScript("OnShow", function(self) self:SetValue(db.scale) end)
	s:SetScript("OnValueChanged", function(self, v)
		v = floor((tonumber(v) or db.scale) * 20 + 0.5) / 20
		db.scale = v
		_G[self:GetName() .. "Text"]:SetText(format("Scale: %.2f", v))
		frame:SetScale(v)
	end)
	local move = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	move:SetSize(140, 22)
	move:SetPoint("TOPLEFT", 16, -280)
	move:SetText("Move the alert")
	move:SetScript("OnClick", function() setPreview(not preview) end)
	InterfaceOptions_AddCategory(panel)
end

-- Events ------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= addonName then return end
		TemucraftLossOfControlDB = TemucraftLossOfControlDB or {}
		db = TemucraftLossOfControlDB
		copyDefaults(defaults, db)
		createFrame()
		buildOptions()
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("UNIT_AURA")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	elseif event == "UNIT_AURA" then
		if ... == "player" then update() end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, sub, _, _, _, destGUID, _, _, spellId, spellName, _, _, _, school = ...
		if sub == "SPELL_INTERRUPT" and destGUID == UnitGUID("player") then
			local ms = ns.interrupts[spellId]
			if not ms then return end
			local now = GetTime()
			local _, _, icon = GetSpellInfo(spellId)
			lockout = { text = "Interrupted", school = schoolText(school), icon = icon, priority = INTERRUPT_PRIORITY,
				duration = ms / 1000, expires = now + ms / 1000, code = 0 }
			current = nil
			update()
		end
	else
		current = nil
		update()
	end
end)

SLASH_TEMUCRAFTLOC1 = "/tloc"
SlashCmdList.TEMUCRAFTLOC = function(msg)
	msg = (msg or ""):lower()
	if msg == "unlock" or msg == "move" then setPreview(true)
	elseif msg == "lock" then setPreview(false)
	elseif msg == "reset" then
		db.point = { "CENTER", "UIParent", "CENTER", 0, 120 }
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	else
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
