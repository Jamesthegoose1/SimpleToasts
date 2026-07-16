--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)

local REMOTE_NAME = "ToastRemote"

local Remote = {}

local VALID_SEVERITIES: { [string]: boolean } = {
	success = true,
	info = true,
	warn = true,
	error = true,
	secondary = true,
}

local VALID_POSITIONS: { [string]: boolean } = {
	["top-left"] = true,
	["top-center"] = true,
	["top-right"] = true,
	["bottom-left"] = true,
	["bottom-center"] = true,
	["bottom-right"] = true,
}

-- Validates a server-sent payload. Returns a well-formed Message, or nil
-- when the payload is not displayable; invalid optional fields are dropped.
local function sanitize(payload: any): Types.Message?
	if typeof(payload) ~= "table" or typeof(payload.summary) ~= "string" then
		return nil
	end

	local message: Types.Message = {
		severity = if VALID_SEVERITIES[payload.severity] then payload.severity else "info",
		summary = payload.summary,
	}

	if typeof(payload.detail) == "string" then
		message.detail = payload.detail
	end
	if typeof(payload.life) == "number" then
		message.life = payload.life
	end
	if typeof(payload.sticky) == "boolean" then
		message.sticky = payload.sticky
	end
	if typeof(payload.closable) == "boolean" then
		message.closable = payload.closable
	end
	if VALID_POSITIONS[payload.position] then
		message.position = payload.position
	end
	if typeof(payload.id) == "string" then
		message.id = payload.id
	end
	if typeof(payload.sound) == "string" then
		message.sound = payload.sound
	end
	if typeof(payload.silent) == "boolean" then
		message.silent = payload.silent
	end
	if typeof(payload.volume) == "number" then
		message.volume = payload.volume
	end

	local theme = payload.customTheme
	if
		typeof(theme) == "table"
		and typeof(theme.backgroundColor) == "Color3"
		and typeof(theme.accentColor) == "Color3"
	then
		message.customTheme = {
			backgroundColor = theme.backgroundColor,
			accentColor = theme.accentColor,
			detailTextColor = if typeof(theme.detailTextColor) == "Color3" then theme.detailTextColor else nil,
			iconAssetId = if typeof(theme.iconAssetId) == "string" then theme.iconAssetId else nil,
			soundAssetId = if typeof(theme.soundAssetId) == "string" then theme.soundAssetId else nil,
		}
	end

	return message
end

-- Returns the shared RemoteEvent, creating it if needed. Server only.
function Remote.getOrCreate(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = REMOTE_NAME
	event.Parent = ReplicatedStorage
	return event
end

function Remote.initClient(add: (message: Types.Message) -> ())
	local function connect(event: RemoteEvent)
		event.OnClientEvent:Connect(function(payload: any)
			local message = sanitize(payload)
			if message then
				add(message)
			end
		end)
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		connect(existing)
		return
	end

	local childAdded: RBXScriptConnection
	childAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == REMOTE_NAME and child:IsA("RemoteEvent") then
			childAdded:Disconnect()
			connect(child)
		end
	end)
end

return Remote
