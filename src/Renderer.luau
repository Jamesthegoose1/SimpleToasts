--!strict
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local Types = require(script.Parent.Types)

type ContainerMap = { [Types.Position]: Frame }

local POSITIONS: { Types.Position } = {
	"top-left",
	"top-center",
	"top-right",
	"bottom-left",
	"bottom-center",
	"bottom-right",
}

-- Pixels between a container and the screen edges.
local SCREEN_MARGIN = 16

local containers: ContainerMap = {}

local preloadedAssets: { [string]: boolean } = {}

local function getAnchorAndPosition(pos: Types.Position): (Vector2, UDim2)
	if pos == "top-left" then
		return Vector2.new(0, 0), UDim2.fromOffset(SCREEN_MARGIN, SCREEN_MARGIN)
	elseif pos == "top-center" then
		return Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, SCREEN_MARGIN)
	elseif pos == "top-right" then
		return Vector2.new(1, 0), UDim2.new(1, -SCREEN_MARGIN, 0, SCREEN_MARGIN)
	elseif pos == "bottom-left" then
		return Vector2.new(0, 1), UDim2.new(0, SCREEN_MARGIN, 1, -SCREEN_MARGIN)
	elseif pos == "bottom-center" then
		return Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -SCREEN_MARGIN)
	else -- bottom-right
		return Vector2.new(1, 1), UDim2.new(1, -SCREEN_MARGIN, 1, -SCREEN_MARGIN)
	end
end

local function isBottom(pos: Types.Position): boolean
	return pos == "bottom-left" or pos == "bottom-center" or pos == "bottom-right"
end

local function buildContainers(gui: ScreenGui, config: Types.Config)
	for _, pos: Types.Position in POSITIONS do
		local anchor, udimPos = getAnchorAndPosition(pos)

		local frame = Instance.new("Frame")
		frame.Name = "ToastContainer_" .. pos
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = anchor
		frame.Position = udimPos
		frame.Size = UDim2.new(0, config.toastWidth, 1, -(SCREEN_MARGIN * 2))
		frame.ClipsDescendants = false
		frame.Parent = gui

		if config.stacked == false then
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = if isBottom(pos)
				then Enum.VerticalAlignment.Bottom
				else Enum.VerticalAlignment.Top
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, config.gap)
			layout.Parent = frame
		end

		containers[pos] = frame
	end
end

local Renderer = {}

function Renderer.init(config: Types.Config)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local existing = playerGui:FindFirstChild("ToastScreenGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ToastScreenGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = config.displayOrder
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	buildContainers(gui, config)

	-- Preload icon and sound assets not preloaded by an earlier init.
	task.spawn(function()
		local assets: { string } = {}
		local function collect(assetId: string?)
			if assetId and not preloadedAssets[assetId] then
				preloadedAssets[assetId] = true
				table.insert(assets, assetId)
			end
		end
		for _, theme in config.themes do
			collect(theme.iconAssetId)
			collect(theme.soundAssetId)
		end
		collect(config.closeIconAssetId)
		if #assets > 0 then
			ContentProvider:PreloadAsync(assets)
		end
	end)
end

function Renderer.getContainer(pos: Types.Position): Frame
	return containers[pos]
end

Renderer.isBottom = isBottom

function Renderer.isTop(pos: Types.Position): boolean
	return not isBottom(pos)
end

return Renderer
