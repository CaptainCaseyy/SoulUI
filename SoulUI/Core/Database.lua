if SoulUI_Blocked then return end

local Soul = SoulUI

local THEME_DEFAULTS = {
	accent = { r = 0, g = 0.93, b = 1 },
	accentUseClass = false,
	font = "Friz Quadrata TT",
	fontOutline = "OUTLINE",
	statusbar = "SoulUI Flat",
	background = { r = 0.06, g = 0.06, b = 0.07, a = 0.92 },
}

local function Copy(src, seen)
	if type(src) ~= "table" then return src end
	if seen[src] then return seen[src] end
	local out = {}
	seen[src] = out
	for k, v in pairs(src) do
		out[Copy(k, seen)] = Copy(v, seen)
	end
	return out
end

function Soul:Copy(src)
	return Copy(src, {})
end

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			Merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function Strip(dst, defaults)
	for k, v in pairs(dst) do
		local keep = type(k) == "string" and k:sub(1, 1) == "_"
		if not keep then
			local defaultValue = defaults[k]
			if type(v) == "table" and type(defaultValue) == "table" then
				Strip(v, defaultValue)
				if next(v) == nil then
					dst[k] = nil
				end
			elseif defaultValue ~= nil and type(v) ~= "table" and v == defaultValue then
				dst[k] = nil
			end
		end
	end
end

function Soul:NewProfileTable()
	return {
		modules = {},
		theme = Copy(THEME_DEFAULTS, {}),
		unlock = { positions = {} },
		_migrations = {},
	}
end

function Soul:EnsureProfileShape(profile)
	if type(profile.modules) ~= "table" then profile.modules = {} end
	if type(profile.theme) ~= "table" then profile.theme = {} end
	Merge(profile.theme, THEME_DEFAULTS)
	if type(profile.unlock) ~= "table" then profile.unlock = {} end
	if type(profile.unlock.positions) ~= "table" then profile.unlock.positions = {} end
	if type(profile._migrations) ~= "table" then profile._migrations = {} end
end

function Soul:InitDB()
	if type(SoulUIDB) ~= "table" then
		SoulUIDB = {}
	end
	local db = SoulUIDB
	if type(db.profiles) ~= "table" then db.profiles = {} end
	if type(db.activeProfile) ~= "string" or db.activeProfile == "" then
		db.activeProfile = "Default"
	end
	if type(db.profileOrder) ~= "table" then db.profileOrder = {} end
	if type(db.specProfiles) ~= "table" then db.specProfiles = {} end
	if type(db.profileKeys) ~= "table" then db.profileKeys = {} end
	if type(db.lastSpecByChar) ~= "table" then db.lastSpecByChar = {} end
	if type(db.cvars) ~= "table" then db.cvars = {} end
	if type(db._migrations) ~= "table" then db._migrations = {} end
	if type(db.account) ~= "table" then db.account = {} end
	if db.account.debug == nil then db.account.debug = false end
	if db.account.panelScale == nil then db.account.panelScale = 1 end

	if type(db.profiles[db.activeProfile]) ~= "table" then
		db.profiles[db.activeProfile] = self:NewProfileTable()
	end
	self:EnsureProfileShape(db.profiles[db.activeProfile])

	local listed = false
	for i = 1, #db.profileOrder do
		if db.profileOrder[i] == db.activeProfile then
			listed = true
			break
		end
	end
	if not listed then
		db.profileOrder[#db.profileOrder + 1] = db.activeProfile
	end

	self.db = db
end

function Soul:ActiveProfile()
	local db = self.db
	local profile = db.profiles[db.activeProfile]
	if type(profile) ~= "table" then
		profile = self:NewProfileTable()
		db.profiles[db.activeProfile] = profile
	end
	return profile
end

function Soul:Theme()
	return self:ActiveProfile().theme
end

function Soul:RegisterModuleDB(key, defaults)
	self._moduleDefaults[key] = defaults
	local modules = self:ActiveProfile().modules
	if type(modules[key]) ~= "table" then
		modules[key] = {}
	end
	Merge(modules[key], defaults)
	return modules[key]
end

function Soul:ModuleDB(key)
	local modules = self:ActiveProfile().modules
	if type(modules[key]) ~= "table" then
		modules[key] = {}
	end
	local defaults = self._moduleDefaults[key]
	if defaults then
		Merge(modules[key], defaults)
	end
	return modules[key]
end

function Soul:CharKey()
	local name = UnitName("player")
	local realm = GetRealmName()
	if type(name) ~= "string" or name == "" or name == "Unknown" then return nil end
	if type(realm) ~= "string" or realm == "" then return nil end
	return name .. " - " .. realm
end

function Soul:SetProfile(name)
	local db = self.db
	if type(db.profiles[name]) ~= "table" then return false end
	db.activeProfile = name
	self:EnsureProfileShape(db.profiles[name])
	for key, defaults in pairs(self._moduleDefaults) do
		local modules = db.profiles[name].modules
		if type(modules[key]) ~= "table" then
			modules[key] = {}
		end
		Merge(modules[key], defaults)
	end
	local charKey = self:CharKey()
	if charKey then
		db.profileKeys[charKey] = name
	end
	self:Fire("ProfileChanged", name)
	return true
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Soul:CreateProfile(name, copyFrom)
	name = Trim(name or "")
	if name == "" then return false, "Enter a profile name." end
	if #name > 40 then return false, "Profile names are limited to 40 characters." end
	if self.db.profiles[name] then return false, "That profile already exists." end
	local profile
	if copyFrom and type(self.db.profiles[copyFrom]) == "table" then
		profile = self:Copy(self.db.profiles[copyFrom])
		profile._migrations = profile._migrations or {}
	else
		profile = self:NewProfileTable()
	end
	self.db.profiles[name] = profile
	self.db.profileOrder[#self.db.profileOrder + 1] = name
	return true
end

function Soul:DeleteProfile(name)
	if name == self.db.activeProfile then
		return false, "Switch to another profile before deleting this one."
	end
	if not self.db.profiles[name] then return false, "No such profile." end
	local remaining = 0
	for _ in pairs(self.db.profiles) do
		remaining = remaining + 1
	end
	if remaining <= 1 then
		return false, "Keep at least one profile."
	end
	self.db.profiles[name] = nil
	for i = #self.db.profileOrder, 1, -1 do
		if self.db.profileOrder[i] == name then
			table.remove(self.db.profileOrder, i)
		end
	end
	for spec, profileName in pairs(self.db.specProfiles) do
		if profileName == name then
			self.db.specProfiles[spec] = nil
		end
	end
	for char, profileName in pairs(self.db.profileKeys) do
		if profileName == name then
			self.db.profileKeys[char] = nil
		end
	end
	return true
end

function Soul:AssignCurrentSpec()
	local index = GetSpecialization()
	if not index then return false, "No specialization is available yet." end
	local id, specName = GetSpecializationInfo(index)
	if not id then return false, "Could not read the current specialization." end
	self.db.specProfiles[id] = self.db.activeProfile
	self:Print(specName or "This spec", "will use profile", self.db.activeProfile)
	return true
end

function Soul:ClearCurrentSpec()
	local index = GetSpecialization()
	if not index then return end
	local id = GetSpecializationInfo(index)
	if id then
		self.db.specProfiles[id] = nil
		self:Print("This spec no longer switches profiles.")
	end
end

function Soul:ApplySpecProfile()
	if not self.db then return end
	local index = GetSpecialization()
	if not index then return end
	local id = GetSpecializationInfo(index)
	if not id then return end
	local charKey = self:CharKey()
	if charKey then
		self.db.lastSpecByChar[charKey] = id
	end
	local wanted = self.db.specProfiles[id]
	if wanted and wanted ~= self.db.activeProfile and self.db.profiles[wanted] then
		self:RunAfterCombat("spec-profile", function()
			local indexNow = GetSpecialization()
			local idNow = indexNow and GetSpecializationInfo(indexNow)
			local name = idNow and Soul.db.specProfiles[idNow]
			if name and name ~= Soul.db.activeProfile and Soul.db.profiles[name] then
				Soul:SetProfile(name)
			end
		end)
	end
end

function Soul:GetUnlockPosition(key)
	return self:ActiveProfile().unlock.positions[key]
end

function Soul:ClearPositions(prefix)
	local positions = self:ActiveProfile().unlock.positions
	local length = #prefix
	for key in pairs(positions) do
		if type(key) == "string" and key:sub(1, length) == prefix then
			positions[key] = nil
		end
	end
end

function Soul:RememberCVar(name, owner)
	if self.db.cvars[name] then return end
	self.db.cvars[name] = { original = GetCVar(name), owner = owner }
end

function Soul:SetOwnedCVar(name, value, owner)
	self:RememberCVar(name, owner)
	if InCombatLockdown() then
		self:RunAfterCombat("cvar:" .. name, function()
			SetCVar(name, value)
		end)
	else
		SetCVar(name, value)
	end
end

function Soul:StripDefaults()
	local db = self.db
	if not db or type(db.profiles) ~= "table" then return end
	for _, profile in pairs(db.profiles) do
		if type(profile) == "table" then
			if type(profile.modules) == "table" then
				for key, data in pairs(profile.modules) do
					local defaults = self._moduleDefaults[key]
					if type(data) == "table" and type(defaults) == "table" then
						Strip(data, defaults)
					end
				end
			end
			if type(profile.theme) == "table" then
				Strip(profile.theme, THEME_DEFAULTS)
			end
		end
	end
end

Soul._migrations = Soul._migrations or {}

function Soul:RegisterMigration(id, fn)
	self._migrations[#self._migrations + 1] = { id = id, fn = fn }
end

function Soul:RunMigrations()
	local flags = self.db._migrations
	for i = 1, #self._migrations do
		local migration = self._migrations[i]
		if not flags[migration.id] then
			local ok, err = pcall(migration.fn, self.db)
			if ok then
				flags[migration.id] = true
			else
				self:Print("migration failed:", migration.id, err)
			end
		end
	end
end
