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

local function SkinTracker()
	local tracker = Tracker()
	if not tracker then return end
	local header = tracker.Header and (tracker.Header.Text or tracker.Header.Title)
	if header and header.SetFont then Soul:ApplyFont(header, 14) end
	if tracker.Header and tracker.Header.Background then
		tracker.Header.Background:SetAlpha(0.35)
	end
end

Q:Feature({
	key = "questSkin",
	enable = function()
		SkinTracker()
		local tracker = Tracker()
		if tracker and not tracker._soulSkin then
			tracker._soulSkin = true
			tracker:HookScript("OnShow", function()
				if DB().questSkin then SkinTracker() end
			end)
		end
	end,
})

local miniEdge
local savedMask
local hiddenMinimap = {}

local MINIMAP_FRAMES = {
	"MinimapBorder", "MinimapBackdrop", "MinimapCompassTexture",
	"MiniMapBorderTop", "MinimapNorthTag",
}

local function HideNamed(root)
	if not root or not root.GetChildren then return end
	local kids = { root:GetChildren() }
	for i = 1, #kids do
		local child = kids[i]
		local name = child.GetName and child:GetName() or ""
		if name:find("Border") or name:find("Backdrop") or name:find("Compass") then
			hiddenMinimap[child] = true
			child:Hide()
		end
	end
end

local function HideMinimapChrome()
	for i = 1, #MINIMAP_FRAMES do
		local frame = _G[MINIMAP_FRAMES[i]]
		if frame and frame.Hide then
			hiddenMinimap[frame] = true
			frame:Hide()
		end
	end
	HideNamed(Minimap)
	HideNamed(MinimapCluster)
	local cluster = MinimapCluster
	if cluster then
		if cluster.BorderTop then cluster.BorderTop:Hide() hiddenMinimap[cluster.BorderTop] = true end
		if cluster.Background then cluster.Background:Hide() hiddenMinimap[cluster.Background] = true end
	end
	if not Minimap then return end
	if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) end
	if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(0) end
	local underlay = _G.MinimapCompassTextureUnderlay
	if underlay and underlay.Hide then
		hiddenMinimap[underlay] = true
		underlay:Hide()
	end
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
					hiddenMinimap[region] = true
					region:Hide()
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
		if savedMask and Minimap and Minimap.SetMaskTexture then
			Minimap:SetMaskTexture(savedMask)
		end
	end,
})

local function SkinChat()
	local n = NUM_CHAT_WINDOWS or 10
	for i = 1, n do
		local frame = _G["ChatFrame" .. i]
		if frame then
			Soul:ApplyFont(frame, 14)
			local bg = _G["ChatFrame" .. i .. "Background"]
			if bg and bg.SetAlpha then bg:SetAlpha(0.45) end
		end
		local edit = _G["ChatFrame" .. i .. "EditBox"]
		if edit then Soul:ApplyFont(edit, 14) end
	end
end

Q:Feature({
	key = "chatSkin",
	enable = SkinChat,
})
