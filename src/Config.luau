--!strict
local Types = require(script.Parent.Types)

local Config: Types.Config = {
	defaultLife = 3000,
	defaultPosition = "top-right",
	defaultClosable = true,
	maxVisible = 5,
	displayOrder = 1000,
	stacked = true,
	expandedCount = 3,

	toastWidth = 320,
	toastMinHeight = 64,
	cornerRadius = 8,
	padding = 12,
	gap = 8,
	backgroundTransparency = 0.08,

	fontSize = 14,
	fontFace = Font.fromEnum(Enum.Font.Gotham),
	animationDuration = 0.25,
	animationEasing = Enum.EasingStyle.Quint,
	closeIconAssetId = "rbxassetid://75619674955521",

	soundEnabled = false,
	defaultVolume = 0.5,

	themes = {
		success = {
			backgroundColor = Color3.fromRGB(211, 251, 223),
			accentColor = Color3.fromRGB(34, 197, 94),
			iconAssetId = "rbxassetid://112862263029717",
			soundAssetId = "rbxassetid://90577351513883",
		},
		info = {
			backgroundColor = Color3.fromRGB(202, 222, 247),
			accentColor = Color3.fromRGB(96, 165, 250),
			iconAssetId = "rbxassetid://124589464820386",
			soundAssetId = "rbxassetid://131039887376992",
		},
		warn = {
			backgroundColor = Color3.fromRGB(245, 236, 199),
			accentColor = Color3.fromRGB(245, 158, 11),
			iconAssetId = "rbxassetid://98907282266965",
			soundAssetId = "rbxassetid://128187340772806",
		},
		error = {
			backgroundColor = Color3.fromRGB(247, 208, 208),
			accentColor = Color3.fromRGB(239, 68, 68),
			iconAssetId = "rbxassetid://98206585758365",
			soundAssetId = "rbxassetid://87519554692663",
		},
		secondary = {
			backgroundColor = Color3.fromRGB(194, 201, 209),
			accentColor = Color3.fromRGB(93, 98, 106),
			iconAssetId = "rbxassetid://124589464820386",
			soundAssetId = "rbxassetid://131039887376992",
		},
	},
}

return Config
