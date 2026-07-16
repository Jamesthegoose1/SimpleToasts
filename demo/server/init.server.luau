--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Toast = require(ReplicatedStorage.SimpleToasts)

-- Demonstration: fire a welcome toast to each player when they join.
Players.PlayerAdded:Connect(function(player: Player)
	task.wait(1)
	Toast.notify(player, {
		severity = "success",
		summary = "Welcome!",
		detail = "SimpleToasts is working from the server.",
		life = 5000,
	})
end)
