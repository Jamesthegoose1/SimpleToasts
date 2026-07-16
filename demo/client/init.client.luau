--!strict
--[[
	Toast demo, keyboard-driven.

	Controls:
		1 = success   2 = info   3 = warn   4 = error   5 = secondary   6 = custom theme

		Shift = target the top-right corner (default)
		Ctrl  = target the bottom-right corner
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Toast = require(ReplicatedStorage.SimpleToasts)

-- Where the next toasts appear. Starts at top-right.
-- Shift/Ctrl switch between the two demoed corners.
local TOP_POSITION: Toast.Position = "top-right"
local BOTTOM_POSITION: Toast.Position = "bottom-right"

local currentPosition: Toast.Position = TOP_POSITION

-- One toast per number key (1-6, in order).
local SEVERITY_ACTIONS: { (Toast.Position) -> () } = {
	function(position)
		Toast.success("Success", "The operation completed successfully.", { position = position })
	end,
	function(position)
		Toast.warn("Warning", "A situation requires your attention.", { position = position })
	end,
	function(position)
		Toast.error("Error", "An unexpected error has occurred.", { position = position })
	end,
	function(position)
		Toast.info("Information", "Here is an informational message.", { position = position })
	end,
	function(position)
		Toast.secondary("Secondary", "A neutral informational message.", { position = position })
	end,
	function(position)
		Toast.add({
			severity = "info",
			summary = "Custom Theme",
			detail = "Fully custom colours and icon.",
			position = position,
			customTheme = {
				backgroundColor = Color3.fromRGB(249, 219, 159),
				accentColor = Color3.fromRGB(209, 152, 38),
				iconAssetId = "rbxassetid://136442373648528",
			},
		})
	end,
}

local NUMBER_ROW_KEYS =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
local KEYPAD_KEYS = {
	Enum.KeyCode.KeypadOne,
	Enum.KeyCode.KeypadTwo,
	Enum.KeyCode.KeypadThree,
	Enum.KeyCode.KeypadFour,
	Enum.KeyCode.KeypadFive,
	Enum.KeyCode.KeypadSix,
}

local keyToAction: { [Enum.KeyCode]: (Toast.Position) -> () } = {}
for index, action in SEVERITY_ACTIONS do
	keyToAction[NUMBER_ROW_KEYS[index]] = action
	keyToAction[KEYPAD_KEYS[index]] = action
end

local POSITION_KEYS: { [Enum.KeyCode]: Toast.Position } = {
	[Enum.KeyCode.LeftShift] = TOP_POSITION,
	[Enum.KeyCode.RightShift] = TOP_POSITION,
	[Enum.KeyCode.LeftControl] = BOTTOM_POSITION,
	[Enum.KeyCode.RightControl] = BOTTOM_POSITION,
}

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	local newPosition: Toast.Position? = POSITION_KEYS[input.KeyCode]
	if newPosition then
		currentPosition = newPosition
		return
	end

	local action = keyToAction[input.KeyCode]
	if action then
		action(currentPosition)
	end
end)
