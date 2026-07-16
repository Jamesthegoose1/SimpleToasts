--!strict
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Types = require(script.Parent.Types)

-- Layout constants
local CLOSE_BTN_SIZE = 16
local CLOSE_BTN_GAP = 4
local ICON_SIZE = 18
local ICON_TEXT_GAP = 8
local DETAIL_TEXT_SIZE_OFFSET = 1

-- Fallback when the theme does not set detailTextColor.
local DEFAULT_DETAIL_TEXT_COLOR = Color3.fromRGB(30, 30, 30)

-- Fraction of animationDuration used for the slot-collapse phase on exit.
local SLOT_COLLAPSE_FACTOR = 0.6

-- Frames to wait for AutomaticSize to propagate through nested chains.
local MAX_MEASURE_FRAMES = 6

local HOVER_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Multiplier applied to the accent colour while the close button is hovered.
local HOVER_DARKEN_FACTOR = 0.65

-- Seconds after which a sound is destroyed even if Ended never fires.
local SOUND_CLEANUP_TIMEOUT = 10

local MILLISECONDS_PER_SECOND = 1000

-- Monotonic sequence number giving toasts a stable insertion order.
local nextToastNumber = 0

export type ToastItem = {
	frame: Frame,
	destroy: (self: ToastItem) -> (),
	-- Removes the toast instantly, without animations or callbacks.
	dispose: (self: ToastItem) -> (),
	-- Freezes/resumes the auto-dismiss countdown.
	setPaused: (self: ToastItem, paused: boolean) -> (),
}

export type StackHooks = {
	onMeasured: (height: number) -> (),
	onClosed: () -> (),
	onTouchTap: () -> (),
}

-- Waits up to MAX_MEASURE_FRAMES Heartbeats for AutomaticSize to settle and
-- returns root's natural pixel height.
local function measureHeight(root: Frame): number
	for _ = 1, MAX_MEASURE_FRAMES do
		RunService.Heartbeat:Wait()
		local h = root.AbsoluteSize.Y
		if h > 0 then
			return h
		end
	end
	return root.AbsoluteSize.Y
end

-- Slide from the nearest screen edge + fade, in a single tween.
-- Yields until the animation completes.
local function animateIn(body: CanvasGroup, slideUp: boolean, config: Types.Config)
	local info = TweenInfo.new(config.animationDuration, config.animationEasing, Enum.EasingDirection.Out)

	local restPosition = if slideUp then UDim2.fromScale(0.5, 0) else UDim2.fromScale(0.5, 1)

	local tween = TweenService:Create(body, info, {
		Position = restPosition,
		GroupTransparency = 0,
	})
	tween:Play()
	tween.Completed:Wait()
end

-- Exit animation, in two phases:
--   1. Visual exit: slide back toward the screen edge + fade out.
--   2. Slot collapse: root.Size shrinks to 0 so neighbours reflow. Skipped
--      in stacked mode (skipSlotCollapse = true), where the Stack controller
--      re-layouts the pile itself.
-- callback() is invoked once the toast is fully gone.
local function animateOut(
	root: Frame,
	body: CanvasGroup,
	slideUp: boolean,
	config: Types.Config,
	skipSlotCollapse: boolean,
	callback: () -> ()
)
	local dur = config.animationDuration
	local easing = config.animationEasing

	local info = TweenInfo.new(dur, easing, Enum.EasingDirection.In)
	local exitPosition = if slideUp
		then UDim2.new(0.5, 0, 0, -body.Size.Y.Offset)
		else UDim2.new(0.5, 0, 1, body.Size.Y.Offset)
	local fadeTween = TweenService:Create(body, info, {
		Position = exitPosition,
		GroupTransparency = 1,
	})
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		if skipSlotCollapse then
			callback()
			return
		end

		root.AutomaticSize = Enum.AutomaticSize.None
		root.Size = UDim2.new(1, 0, 0, root.AbsoluteSize.Y)

		local collapseDur = dur * SLOT_COLLAPSE_FACTOR
		local infoPhase2 = TweenInfo.new(collapseDur, easing, Enum.EasingDirection.Out)
		local sizeTween = TweenService:Create(root, infoPhase2, {
			Size = UDim2.fromScale(1, 0),
		})
		sizeTween:Play()
		sizeTween.Completed:Connect(callback)
	end)
end

-- Plays this toast's sound once, when it appears. Asset ID resolution order:
-- message.sound (per-message override), then theme.soundAssetId (only when
-- config.soundEnabled is true).
local function playSound(message: Types.Message, theme: Types.SeverityTheme, config: Types.Config)
	if message.silent then
		return
	end

	local assetId: string? = message.sound or (if config.soundEnabled then theme.soundAssetId else nil)
	if not assetId then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = message.volume or config.defaultVolume
	sound.RollOffMaxDistance = 0

	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(SOUND_CLEANUP_TIMEOUT, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)

	SoundService:PlayLocalSound(sound)
end

local ToastItem = {}

function ToastItem.new(
	message: Types.Message,
	config: Types.Config,
	container: Frame,
	isBottom: boolean,
	slideUp: boolean,
	onClose: () -> (),
	stackHooks: StackHooks?
): ToastItem
	local theme = message.customTheme or config.themes[message.severity] or config.themes["info"]
	local closable = if message.closable ~= nil then message.closable else config.defaultClosable

	nextToastNumber += 1
	local toastNumber = nextToastNumber

	-- Root is the invisible layout slot managed by the UIListLayout (list
	-- mode) or the Stack controller (stacked mode).
	local root = Instance.new("Frame")
	root.Name = "Toast_" .. (message.id or tostring(toastNumber))
	root.Size = UDim2.fromScale(1, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.LayoutOrder = if isBottom then -toastNumber else toastNumber

	-- Body carries all visible styling and is the element that slides and
	-- fades during animations (root stays put).
	local body = Instance.new("CanvasGroup")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundColor3 = theme.backgroundColor
	body.BackgroundTransparency = config.backgroundTransparency
	body.BorderSizePixel = 0
	body.GroupTransparency = 1 -- hidden; animateIn reveals it
	body.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, config.cornerRadius)
	corner.Parent = body

	local pad = config.padding

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = body

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, pad)
	contentPadding.PaddingBottom = UDim.new(0, pad)
	contentPadding.PaddingLeft = UDim.new(0, pad)
	contentPadding.PaddingRight = UDim.new(0, pad + (if closable then CLOSE_BTN_SIZE + CLOSE_BTN_GAP else 0))
	contentPadding.Parent = content

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 0)
	contentLayout.Parent = content

	-- Title row: icon + summary.
	local iconOffset = if theme.iconAssetId then ICON_SIZE + ICON_TEXT_GAP else 0

	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.Size = UDim2.fromScale(1, 0)
	titleRow.AutomaticSize = Enum.AutomaticSize.Y
	titleRow.BackgroundTransparency = 1
	titleRow.LayoutOrder = 1
	titleRow.Parent = content

	if theme.iconAssetId then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		icon.BackgroundTransparency = 1
		icon.Image = theme.iconAssetId
		icon.ImageColor3 = theme.accentColor
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = titleRow
	end

	local summary = Instance.new("TextLabel")
	summary.Name = "Summary"
	summary.Text = message.summary
	summary.FontFace = Font.new(config.fontFace.Family, Enum.FontWeight.Bold, config.fontFace.Style)
	summary.TextSize = config.fontSize
	summary.TextColor3 = theme.accentColor
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.TextWrapped = true
	summary.BackgroundTransparency = 1
	summary.Size = UDim2.new(1, -iconOffset, 0, 0)
	summary.Position = UDim2.fromOffset(iconOffset, 0)
	summary.AutomaticSize = Enum.AutomaticSize.Y
	summary.Parent = titleRow

	if message.detail and message.detail ~= "" then
		local detail = Instance.new("TextLabel")
		detail.Name = "Detail"
		detail.Text = message.detail
		detail.FontFace = config.fontFace
		detail.TextSize = config.fontSize - DETAIL_TEXT_SIZE_OFFSET
		detail.TextColor3 = theme.detailTextColor or DEFAULT_DETAIL_TEXT_COLOR
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextWrapped = true
		detail.BackgroundTransparency = 1
		detail.Size = UDim2.fromScale(1, 0)
		detail.AutomaticSize = Enum.AutomaticSize.Y
		detail.LayoutOrder = 2
		if iconOffset > 0 then
			local detailPadding = Instance.new("UIPadding")
			detailPadding.PaddingLeft = UDim.new(0, iconOffset)
			detailPadding.Parent = detail
		end
		detail.Parent = content
	end

	local destroyed = false

	local pointerCount = 0

	local lifeTimerConn: RBXScriptConnection? = nil

	-- Pile-wide pause driven from outside via setPaused.
	local externallyPaused = false

	local function pointerEnter()
		pointerCount += 1
	end

	local function pointerLeave()
		pointerCount = math.max(0, pointerCount - 1)
	end

	local function doClose()
		if destroyed then
			return
		end
		destroyed = true
		if lifeTimerConn then
			lifeTimerConn:Disconnect()
			lifeTimerConn = nil
		end
		animateOut(root, body, slideUp, config, stackHooks ~= nil, function()
			if stackHooks then
				stackHooks.onClosed()
			end
			root:Destroy()
			onClose()
		end)
	end

	if closable then
		local closeBtn = Instance.new("ImageButton")
		closeBtn.Name = "CloseBtn"
		closeBtn.Size = UDim2.fromOffset(CLOSE_BTN_SIZE, CLOSE_BTN_SIZE)
		closeBtn.Position = UDim2.new(1, -(pad + CLOSE_BTN_SIZE / 2), 0, pad + (ICON_SIZE - CLOSE_BTN_SIZE) / 2)
		closeBtn.AnchorPoint = Vector2.new(0.5, 0)
		closeBtn.BackgroundTransparency = 1
		closeBtn.Image = config.closeIconAssetId
		closeBtn.ImageColor3 = theme.accentColor
		closeBtn.ScaleType = Enum.ScaleType.Fit
		closeBtn.ZIndex = 2
		closeBtn.Parent = body

		local hoverColour = Color3.new(
			theme.accentColor.R * HOVER_DARKEN_FACTOR,
			theme.accentColor.G * HOVER_DARKEN_FACTOR,
			theme.accentColor.B * HOVER_DARKEN_FACTOR
		)
		closeBtn.MouseButton1Click:Connect(doClose)
		closeBtn.MouseEnter:Connect(function()
			pointerEnter()
			TweenService:Create(closeBtn, HOVER_TWEEN, { ImageColor3 = hoverColour }):Play()
		end)
		closeBtn.MouseLeave:Connect(function()
			pointerLeave()
			TweenService:Create(closeBtn, HOVER_TWEEN, { ImageColor3 = theme.accentColor }):Play()
		end)
	end

	-- Invisible full-size button covering the toast surface. It detects
	-- pointer presence to pause the auto-dismiss timer and, in stacked mode,
	-- reports touch taps to the Stack controller.
	local pointerRegion = Instance.new("TextButton")
	pointerRegion.Name = "PointerRegion"
	pointerRegion.Size = UDim2.fromScale(1, 1)
	pointerRegion.BackgroundTransparency = 1
	pointerRegion.Text = ""
	pointerRegion.ZIndex = 1
	pointerRegion.Parent = body

	pointerRegion.MouseEnter:Connect(pointerEnter)
	pointerRegion.MouseLeave:Connect(pointerLeave)
	-- Touch: in list mode press-and-hold pauses this toast's timer; in
	-- stacked mode a tap expands the pile and the Stack handles pausing.
	pointerRegion.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if stackHooks then
			stackHooks.onTouchTap()
		else
			pointerEnter()
		end
	end)
	pointerRegion.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and not stackHooks then
			pointerLeave()
		end
	end)

	root.Parent = container

	task.spawn(function()
		-- Step 1: measure the natural height based on the real layout width.
		local naturalH = measureHeight(root)
		if naturalH <= 0 then
			naturalH = config.toastMinHeight
		end

		-- A close may have been requested during the measurement frames
		-- (e.g. Toast.clear()).
		if destroyed then
			return
		end

		-- Step 2: freeze layout in fixed pixels.
		body.AutomaticSize = Enum.AutomaticSize.None
		body.Size = UDim2.new(1, 0, 0, naturalH)
		root.AutomaticSize = Enum.AutomaticSize.None

		-- Step 3: set the slide pivot edge.
		body.AnchorPoint = if slideUp then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)

		-- Step 4: open the slot to its full height and offset the body
		-- toward the screen edge (the slide start).
		root.Size = UDim2.new(1, 0, 0, naturalH)
		body.Position = if slideUp then UDim2.new(0.5, 0, 0, -naturalH) else UDim2.new(0.5, 0, 1, naturalH)

		-- Step 5 (stacked mode): hand the measured toast to the Stack
		-- controller, which places it in the front slot and re-layouts.
		if stackHooks then
			stackHooks.onMeasured(naturalH)
		end

		-- Step 6: play the sound and the enter animation.
		playSound(message, theme, config)
		animateIn(body, slideUp, config)

		-- Step 7: schedule auto-dismiss. `life` is the fully-visible
		-- duration: the countdown starts after the enter animation and does
		-- not tick while a pointer is on the toast or the pile is expanded.
		if not message.sticky and not destroyed then
			local life = message.life or config.defaultLife
			local remaining = life / MILLISECONDS_PER_SECOND
			lifeTimerConn = RunService.Heartbeat:Connect(function(dt: number)
				if pointerCount > 0 or externallyPaused then
					return
				end
				remaining -= dt
				if remaining <= 0 then
					doClose()
				end
			end)
		end
	end)

	local self: ToastItem = {
		frame = root,
		destroy = function(_self: ToastItem)
			doClose()
		end,
		dispose = function(_self: ToastItem)
			if destroyed then
				return
			end
			destroyed = true
			if lifeTimerConn then
				lifeTimerConn:Disconnect()
				lifeTimerConn = nil
			end
			root:Destroy()
		end,
		setPaused = function(_self: ToastItem, paused: boolean)
			externallyPaused = paused
		end,
	}

	return self
end

return ToastItem
