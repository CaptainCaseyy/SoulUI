if SoulUI_Blocked then return end

local Soul = SoulUI

local function PlainCopy(src, seen)
	local kind = type(src)
	if kind == "function" or kind == "userdata" or kind == "thread" then
		return nil
	end
	if kind ~= "table" then return src end
	if seen[src] then return seen[src] end
	local out = {}
	seen[src] = out
	for k, v in pairs(src) do
		local ck, cv = PlainCopy(k, seen), PlainCopy(v, seen)
		if ck ~= nil and cv ~= nil then
			out[ck] = cv
		end
	end
	return out
end

local function EncodePayload(payload)
	if not C_EncodingUtil or not C_EncodingUtil.SerializeCBOR then
		return nil, "Profile export needs the 12.1 encoding API."
	end
	local cbor = C_EncodingUtil.SerializeCBOR(payload)
	local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
	if not method then return nil, "Deflate compression is unavailable." end
	local level = Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize
	local compressed
	if level then
		compressed = C_EncodingUtil.CompressString(cbor, method, level)
	else
		compressed = C_EncodingUtil.CompressString(cbor, method)
	end
	local variant = Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe
	local encoded
	if variant then
		encoded = C_EncodingUtil.EncodeBase64(compressed, variant)
	else
		encoded = C_EncodingUtil.EncodeBase64(compressed)
	end
	return "!SOUL1:" .. encoded
end

local function DecodePayload(text)
	if type(text) ~= "string" then return nil, "Paste a SoulUI profile string." end
	text = text:gsub("%s+", "")
	if text:sub(1, 7) ~= "!SOUL1:" then
		return nil, "That string is not a SoulUI profile."
	end
	if not C_EncodingUtil or not C_EncodingUtil.DecodeBase64 then
		return nil, "Profile import needs the 12.1 encoding API."
	end
	local body = text:sub(8)
	local variant = Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe
	local compressed
	if variant then
		compressed = C_EncodingUtil.DecodeBase64(body, variant)
	else
		compressed = C_EncodingUtil.DecodeBase64(body)
	end
	if type(compressed) ~= "string" then return nil, "Could not read that profile string." end
	local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
	local cbor = C_EncodingUtil.DecompressString(compressed, method)
	if type(cbor) ~= "string" then return nil, "Could not decompress that profile string." end
	local payload = C_EncodingUtil.DeserializeCBOR(cbor)
	if type(payload) ~= "table" or type(payload.profile) ~= "table" then
		return nil, "That profile string has no profile data."
	end
	if payload.v ~= 1 then
		return nil, "That profile was exported by a newer SoulUI."
	end
	return payload
end

function Soul:ExportProfile(profileKey)
	local name = profileKey or self.db.activeProfile
	local profile = self.db.profiles[name]
	if type(profile) ~= "table" then return nil end
	local ok, encoded, err = pcall(EncodePayload, {
		v = 1,
		kind = "profile",
		name = name,
		profile = PlainCopy(profile, {}),
	})
	if not ok then
		self:Print("Export failed:", encoded)
		return nil
	end
	if not encoded then
		self:Print(err or "Export failed.")
		return nil
	end
	return encoded
end

function Soul:DecodeProfileString(text)
	local payload, err = DecodePayload(text)
	if not payload then return nil, err end
	return payload
end

function Soul:ImportProfile(text, profileKey)
	local payload, err = DecodePayload(text)
	if not payload then
		return false, err
	end
	local name = profileKey
	if type(name) ~= "string" or name == "" then
		name = payload.name or "Imported"
	end
	if self.db.profiles[name] then
		self.db.profiles[name] = payload.profile
	else
		local created, createErr = self:CreateProfile(name)
		if not created then return false, createErr end
		self.db.profiles[name] = payload.profile
	end
	self:EnsureProfileShape(self.db.profiles[name])
	self:SetProfile(name)
	return true
end

function Soul:GetProfileKeys()
	local keys = {}
	for name in pairs(self.db.profiles) do
		keys[name] = true
	end
	return keys
end

function Soul:GetProfileAssignments()
	return self:Copy(self.db.profileKeys)
end

function Soul:GetCurrentProfileKey()
	return self.db.activeProfile
end

function Soul:OpenConfig()
	self:OpenOptions()
end

function Soul:CloseConfig()
	self:CloseOptions()
end

-- Same object the Wago installer looks up. Methods above are the contract.
SoulUIAPI = SoulUI
