--!strict
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Types)

-- Pixels of edge left visible for each toast peeking behind the front one
-- while the pile is collapsed.
local PEEK_OFFSET = 10

-- Scale reduction per depth level while collapsed.
local PEEK_SCALE_STEP = 0.05

-- Lower bound for the depth scale.
local MIN_PEEK_SCALE = 0.7

-- Number of visible layers (front toast + peeking edges) while collapsed;
-- anything deeper is fully transparent (in reserve).
local PEEK_MAX_LAYERS = 3

-- Seconds to wait after the mouse leaves the pile before collapsing.
local COLLAPSE_GRACE = 0.25

-- What init.luau registers for each toast. `setPaused` freezes/resumes the
-- toast's auto-dismiss timer. `height` is the natural (unscaled) pixel
-- height measured by ToastItem.
export type StackEntry = {
	root: Frame,
	height: number,
	setPaused: (paused: boolean) -> (),
}

-- Internal per-toast record. `scale` is the UIScale driving the depth
-- effect, `fade` is the toast's Body CanvasGroup, `hidden` tracks whether
-- the Stack last faded the toast to full transparency.
type Item = {
	entry: StackEntry,
	scale: UIScale,
	fade: CanvasGroup,
	hidden: boolean,
}

local Stack = {}
Stack.__index = Stack

export type Stack = typeof(setmetatable(
	{} :: {
		_container: Frame,
		_config: Types.Config,
		_isBottom: boolean,
		_items: { Item },
		_pointerCount: number,
		_touchExpanded: boolean,
		_expanded: boolean,
		_collapseGen: number,
		_destroyed: boolean,
		_hoverZone: Frame,
		_connections: { RBXScriptConnection },
	},
	Stack
))

function Stack.new(container: Frame, config: Types.Config, isBottom: boolean): Stack
	local self = setmetatable({
		_container = container,
		_config = config,
		_isBottom = isBottom,
		_items = {},
		_pointerCount = 0,
		_touchExpanded = false,
		_expanded = false,
		_collapseGen = 0,
		_destroyed = false,
		_hoverZone = nil :: any, -- assigned below
		_connections = {},
	}, Stack)

	-- Invisible, non-Active frame stretched over the pile's current bounds
	-- (resized on every re-layout). Mouse hover over this zone expands the
	-- pile; clicks pass through to the toasts beneath it.
	local zone = Instance.new("Frame")
	zone.Name = "StackHoverZone"
	zone.BackgroundTransparency = 1
	zone.Active = false
	zone.ZIndex = 0 -- behind every toast root (they get ZIndex >= 1)
	zone.AnchorPoint = if isBottom then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
	zone.Position = if isBottom then UDim2.fromScale(0.5, 1) else UDim2.fromScale(0.5, 0)
	zone.Size = UDim2.fromScale(1, 0)
	zone.Parent = container
	self._hoverZone = zone

	table.insert(
		self._connections,
		zone.MouseEnter:Connect(function()
			self:_notifyPointer(1)
		end)
	)
	table.insert(
		self._connections,
		zone.MouseLeave:Connect(function()
			self:_notifyPointer(-1)
		end)
	)

	-- Touch: tapping the pile expands it (via notifyTouchTap); a touch that
	-- begins outside the pile (gameProcessed = false) collapses it.
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if not self._touchExpanded or gameProcessed then
				return
			end
			self._touchExpanded = false
			self:_updateExpanded()
		end)
	)

	return self
end

-- Registers a freshly measured toast at the front of the pile (depth 0) and
-- re-layouts.
function Stack.add(self: Stack, entry: StackEntry)
	if self._destroyed then
		return
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = entry.root

	local fade = entry.root:FindFirstChild("Body") :: CanvasGroup

	entry.root.AnchorPoint = if self._isBottom then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
	entry.root.Position = if self._isBottom then UDim2.fromScale(0.5, 1) else UDim2.fromScale(0.5, 0)

	table.insert(self._items, 1, { entry = entry, scale = scale, fade = fade, hidden = false })

	-- A toast born while the pile is held open must not start counting down.
	entry.setPaused(self._expanded)

	self:_relayout(true)
end

-- Removes a toast once its exit animation has fully completed (wired to the
-- onClosed hook), then re-layouts: the pile glides into the freed spot and
-- reveals a reserve toast, if any.
function Stack.remove(self: Stack, entry: StackEntry)
	if self._destroyed then
		return
	end

	for i, item in self._items do
		if item.entry == entry then
			table.remove(self._items, i)
			break
		end
	end

	if #self._items == 0 then
		self._touchExpanded = false
	end

	self:_relayout(true)
	self:_updateExpanded()
end

-- Touch entry point (relayed from any toast's PointerRegion): a tap on the
-- pile expands it and keeps it open until a touch lands outside the pile.
function Stack.notifyTouchTap(self: Stack)
	if self._destroyed then
		return
	end

	self._touchExpanded = true
	self:_updateExpanded()
end

-- Disconnects everything this Stack owns. Called when Toast.configure()
-- rebuilds the renderer.
function Stack.destroy(self: Stack)
	self._destroyed = true
	self._collapseGen += 1
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._items)
end

function Stack._notifyPointer(self: Stack, delta: number)
	self._pointerCount = math.max(0, self._pointerCount + delta)
	self:_updateExpanded()
end

-- Reconciles the expanded state with the current inputs (mouse hover count
-- and sticky touch flag). Expansion is immediate; collapsing is deferred by
-- COLLAPSE_GRACE and cancelled if the pointer returns in the meantime.
function Stack._updateExpanded(self: Stack)
	local shouldExpand = self._pointerCount > 0 or self._touchExpanded
	self._collapseGen += 1 -- invalidate any pending deferred collapse

	if shouldExpand then
		if not self._expanded then
			self:_setExpanded(true)
		end
	elseif self._expanded then
		local gen = self._collapseGen
		task.delay(COLLAPSE_GRACE, function()
			if gen == self._collapseGen and self._expanded and self._pointerCount == 0 and not self._touchExpanded then
				self:_setExpanded(false)
			end
		end)
	end
end

-- Pauses or resumes every timer in the pile, then animates the layout.
function Stack._setExpanded(self: Stack, expanded: boolean)
	self._expanded = expanded
	for _, item in self._items do
		item.entry.setPaused(expanded)
	end
	self:_relayout(true)
end

--[[
	Layout math. Depth d = 0 is the newest (front) toast. All `y` values are
	offsets from the container's screen edge (mirrored for bottom piles).

	Collapsed: each toast's far edge sits PEEK_OFFSET px beyond the previous
	layer's, scaled down by PEEK_SCALE_STEP per level:

	    y_d = frontHeight + d * PEEK_OFFSET - height_d * scale_d

	Expanded: a vertical list of cumulative heights plus config.gap.

	Toasts beyond the visible count (PEEK_MAX_LAYERS collapsed, expandedCount
	expanded) are parked at the last visible slot and faded to full
	transparency; they re-emerge from there when closer toasts are dismissed.
]]
function Stack._relayout(self: Stack, animated: boolean)
	local config = self._config
	local items = self._items
	local count = #items
	local expanded = self._expanded

	local visibleCount = if expanded then config.expandedCount else PEEK_MAX_LAYERS
	local info = TweenInfo.new(config.animationDuration, config.animationEasing, Enum.EasingDirection.Out)

	local frontHeight = if count > 0 then items[1].entry.height else 0
	local listAccum = 0 -- running y for the expanded list
	local lastVisibleY = 0 -- hidden toasts park at the last visible slot...
	local lastVisibleScale = 1 -- ...at its scale, so they re-emerge from there
	local pileExtent = 0 -- total pixel span of the pile, for the hover zone

	for i, item in items do
		local depth = i - 1
		local visible = depth < visibleCount

		local targetScale: number
		local y: number
		if visible then
			if expanded then
				targetScale = 1
				y = listAccum
				pileExtent = y + item.entry.height
			else
				targetScale = math.max(MIN_PEEK_SCALE, 1 - depth * PEEK_SCALE_STEP)
				y = frontHeight + depth * PEEK_OFFSET - item.entry.height * targetScale
				pileExtent = frontHeight + depth * PEEK_OFFSET
			end
			lastVisibleY = y
			lastVisibleScale = targetScale
		else
			y = lastVisibleY
			targetScale = lastVisibleScale
		end
		listAccum += item.entry.height + config.gap

		-- Newest in front. ZIndex is not tweenable, so it is applied instantly.
		item.entry.root.ZIndex = count - depth

		local targetPos = if self._isBottom then UDim2.new(0.5, 0, 1, -y) else UDim2.new(0.5, 0, 0, y)

		if animated then
			TweenService:Create(item.entry.root, info, { Position = targetPos }):Play()
			TweenService:Create(item.scale, info, { Scale = targetScale }):Play()
		else
			item.entry.root.Position = targetPos
			item.scale.Scale = targetScale
		end

		-- GroupTransparency is only touched when a toast crosses the
		-- visible/hidden boundary, never on ordinary re-layouts.
		if visible == item.hidden then
			item.hidden = not visible
			local targetTransparency = if visible then 0 else 1
			if animated then
				TweenService:Create(item.fade, info, { GroupTransparency = targetTransparency }):Play()
			else
				item.fade.GroupTransparency = targetTransparency
			end
		end
	end

	-- Resize the hover zone to hug the pile (instant, not tweened).
	self._hoverZone.Size = UDim2.new(1, 0, 0, pileExtent)
end

return Stack
