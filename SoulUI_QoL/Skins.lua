if SoulUI_Blocked or not SoulUI then return end

-- Light skins. They restyle Blizzard's own quest tracker, minimap and chat.
-- They do not replace those frames, and they never read combat text.

local Soul = SoulUI
local UI = Soul.UI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB

local function Tracker()
	return ObjectiveTrackerFrame or QuestObjectiveTracker
end

-- Original header font and background alpha, kept so turning the skin off
-- puts them back. Nothing is stored on Blizzard's frames.
local trackerSaved = {}
local trackerHooked = false

local function TrackerParts()
	local tracker = Tracker()
	local header = tracker and tracker.Header
	if not header then return nil end
	return header.Text or header.Title, header.Background
end

local function SkinTracker()
	local text, background = TrackerParts()
	if text and text.SetFont and text.GetFont then
		if not trackerSaved.font then trackerSaved.font = { text:GetFont() } end
		Soul:ApplyFont(text, 14)
	end
	if background and background.SetAlpha then
		if not trackerSaved.alpha then trackerSaved.alpha = background:GetAlpha() end
		background:SetAlpha(0.35)
	end
end

local function UnskinTracker()
	local text, background = TrackerParts()
	local font = trackerSaved.font
	if text and font and font[1] then text:SetFont(font[1], font[2], font[3] or "") end
	if background and trackerSaved.alpha then background:SetAlpha(trackerSaved.alpha) end
end

Q:Feature({
	key = "questSkin",
	refresh = function() SkinTracker() end,
	enable = function()
		SkinTracker()
		local tracker = Tracker()
		if tracker and not trackerHooked then
			trackerHooked = true
			tracker:HookScript("OnShow", function()
				if Q.on.questSkin then SkinTracker() end
			end)
		end
	end,
	disable = UnskinTracker,
})

local miniEdge
local savedMask
local hiddenMinimap = {}

local MINIMAP_FRAMES = {
	"MinimapBorder", "MinimapBackdrop", "MinimapCompassTexture",
	"MiniMapBorderTop", "MinimapNorthTag",
}

-- Hides one piece of minimap chrome and remembers it, but only when it is
-- shown: turning the skin off must not show something Blizzard had hidden.
local function Stash(object)
	if not object or not object.Hide or not object.IsShown then return end
	if object:IsShown() then
		hiddenMinimap[object] = true
		object:Hide()
	end
end

local function HideNamed(root)
	if not root or not root.GetChildren then return end
	local kids = { root:GetChildren() }
	for i = 1, #kids do
		local child = kids[i]
		local name = child.GetName and child:GetName() or ""
		if type(name) == "string" and (name:find("Border") or name:find("Backdrop") or name:find("Compass")) then
			Stash(child)
		end
	end
end

local function HideMinimapChrome()
	for i = 1, #MINIMAP_FRAMES do
		Stash(_G[MINIMAP_FRAMES[i]])
	end
	HideNamed(Minimap)
	HideNamed(MinimapCluster)
	local cluster = MinimapCluster
	if cluster then
		Stash(cluster.BorderTop)
		Stash(cluster.Background)
	end
	if not Minimap then return end
	if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) end
	if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(0) end
	Stash(_G.MinimapCompassTextureUnderlay)
	local function hideRing(root)
		if not root or not root.GetRegions then return end
		local regions = { root:GetRegions() }
		for i = 1, #regions do
			local region = regions[i]
			if region and region.GetObjectType and region:GetObjectType() == "Texture" then
				local atlas = region.GetAtlas and region:GetAtlas() or ""
				local name = region.GetName and region:GetName() or ""
				local label = (type(atlas) == "string" and atlas or "") .. (type(name) == "string" and name or "")
				if label:find("Circle") or label:find("Compass") or label:find("Ring") or label:find("Border") then
					Stash(region)
				end
			end
		end
	end
	hideRing(Minimap)
	hideRing(MinimapCluster)
end

local function ApplySquareMask()
	if DB().minimapSquare and Minimap and Minimap.SetMaskTexture then
		Minimap:SetMaskTexture(130937)
	end
end

local function ShowMinimapChrome()
	for frame in pairs(hiddenMinimap) do
		if frame.Show then frame:Show() end
	end
	wipe(hiddenMinimap)
end

Q:Feature({
	key = "minimapSquare",
	enable = function()
		if not Minimap then return end
		HideMinimapChrome()
		if not miniEdge then
			miniEdge = CreateFrame("Frame", nil, Minimap)
			miniEdge:SetPoint("TOPLEFT", -1, 1)
			miniEdge:SetPoint("BOTTOMRIGHT", 1, -1)
			UI.Edge(miniEdge, 0, 0, 0, 1, "OVERLAY")
			miniEdge:EnableMouse(false)
			Minimap:HookScript("OnShow", function()
				if DB().minimapSquare then
					HideMinimapChrome()
					ApplySquareMask()
				end
			end)
		end
		miniEdge:Show()
		if Minimap.GetMaskTexture and not savedMask then
			savedMask = Minimap:GetMaskTexture()
		end
		-- 130937 is the client's square white texture. A file path leaves the
		-- round mask in place on this client, which is why the circle stayed.
		if Minimap.SetMaskTexture then
			Minimap:SetMaskTexture(130937)
		end
		C_Timer.After(0, function()
			if DB().minimapSquare then
				HideMinimapChrome()
				ApplySquareMask()
			end
		end)
		C_Timer.After(1, function()
			if DB().minimapSquare then
				HideMinimapChrome()
				ApplySquareMask()
			end
		end)
	end,
	disable = function()
		if miniEdge then miniEdge:Hide() end
		ShowMinimapChrome()
		if Minimap and Minimap.SetMaskTexture then
			-- GetMaskTexture can come back empty; the round mask is the default.
			Minimap:SetMaskTexture(savedMask or "Interface\\Masks\\CircleMaskScalable")
		end
	end,
})

-- Chat font and background. The original font (size included: the player
-- sets it per window) and alpha are kept, and come back when this is off.
local chatSaved = {} -- object -> { path, size, flags } or alpha

local function SaveFont(object)
	if chatSaved[object] or not object.GetFont then return end
	local path, size, flags = object:GetFont()
	if path then chatSaved[object] = { path, size, flags } end
end

local function SkinChat()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then
			SaveFont(frame)
			local saved = chatSaved[frame]
			-- Keep the size the player chose for that window.
			Soul:ApplyFont(frame, saved and saved[2] or 14)
			local bg = _G["ChatFrame" .. i .. "Background"]
			if bg and bg.SetAlpha then
				if chatSaved[bg] == nil then chatSaved[bg] = bg:GetAlpha() end
				bg:SetAlpha(0.45)
			end
		end
		local edit = _G["ChatFrame" .. i .. "EditBox"]
		if edit then
			SaveFont(edit)
			Soul:ApplyFont(edit, 14)
		end
	end
end

local function UnskinChat()
	for object, saved in pairs(chatSaved) do
		if type(saved) == "table" then
			object:SetFont(saved[1], saved[2], saved[3] or "")
		elseif type(saved) == "number" then
			object:SetAlpha(saved)
		end
	end
end

Q:Feature({
	key = "chatSkin",
	enable = SkinChat,
	refresh = SkinChat, -- follows General > Look font changes
	disable = UnskinChat,
})
