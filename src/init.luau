--!strict
local RunService = game:GetService("RunService")

local Types = require(script.Types)
local Config = require(script.Config)
local Remote = require(script.Remote)
local Renderer = require(script.Renderer)
local ToastItem = require(script.ToastItem)
local Stack = require(script.Stack)

local isClient = RunService:IsClient()
local isServer = RunService:IsServer()

local activeConfig: Types.Config = Config

type ActiveToast = { item: ToastItem.ToastItem, position: Types.Position }
local activeToasts: { ActiveToast } = {}

local stacks: { [Types.Position]: Stack.Stack } = {}

local initialised = false

local Toast = {}

local function ensureInit()
	if initialised then
		return
	end
	initialised = true
	if isClient then
		Renderer.init(activeConfig)
	elseif isServer then
		Remote.getOrCreate()
	end
end

local function getStack(pos: Types.Position, container: Frame, isBottom: boolean): Stack.Stack
	local existing = stacks[pos]
	if existing then
		return existing
	end
	local stack = Stack.new(container, activeConfig, isBottom)
	stacks[pos] = stack
	return stack
end

local function addClient(message: Types.Message)
	local pos: Types.Position = message.position or activeConfig.defaultPosition
	local container = Renderer.getContainer(pos)
	local isBottom = Renderer.isBottom(pos)
	local slideUp = Renderer.isTop(pos)

	local stackHooks: ToastItem.StackHooks? = nil
	local stackEntry: Stack.StackEntry? = nil
	if activeConfig.stacked then
		local stack = getStack(pos, container, isBottom)
		stackHooks = {
			onMeasured = function(height: number)
				if stackEntry then
					stackEntry.height = height
					stack:add(stackEntry)
				end
			end,
			onClosed = function()
				if stackEntry then
					stack:remove(stackEntry)
				end
			end,
			onTouchTap = function()
				stack:notifyTouchTap()
			end,
		}
	end

	local item: ToastItem.ToastItem
	item = ToastItem.new(message, activeConfig, container, isBottom, slideUp, function()
		for i, v in activeToasts do
			if v.item == item then
				table.remove(activeToasts, i)
				break
			end
		end
	end, stackHooks)

	if stackHooks then
		stackEntry = {
			root = item.frame,
			height = 0,
			setPaused = function(paused: boolean)
				item:setPaused(paused)
			end,
		}
	end

	table.insert(activeToasts, { item = item, position = pos })

	local visibleAtPos = 0
	for _, v in activeToasts do
		if v.position == pos then
			visibleAtPos += 1
		end
	end
	if visibleAtPos > activeConfig.maxVisible then
		for i, v in activeToasts do
			if v.position == pos then
				v.item:destroy()
				table.remove(activeToasts, i)
				break
			end
		end
	end
end

export type Message = Types.Message
export type Severity = Types.Severity
export type Position = Types.Position
export type Config = Types.Config

function Toast.configure(overrides: { [string]: any })
	for k, v in overrides do
		if k == "themes" and typeof(v) == "table" then
			-- Merged per severity so a partial themes table does not wipe
			-- the severities it omits.
			for name, theme in v do
				activeConfig.themes[name] = theme
			end
		else
			(activeConfig :: any)[k] = v
		end
	end

	if isClient and initialised then
		for _, entry in activeToasts do
			entry.item:dispose()
		end
		table.clear(activeToasts)
		for _, stack in stacks do
			stack:destroy()
		end
		table.clear(stacks)
		initialised = false
		ensureInit()
	end
end

function Toast.add(message: Types.Message)
	ensureInit()
	if isClient then
		addClient(message)
	end
end

function Toast.addAll(messages: { Types.Message })
	for _, msg in messages do
		Toast.add(msg)
	end
end

function Toast.clear(position: Types.Position?)
	if not isClient then
		return
	end
	for i = #activeToasts, 1, -1 do
		local entry = activeToasts[i]
		if position == nil or entry.position == position then
			entry.item:destroy()
			table.remove(activeToasts, i)
		end
	end
end

local function addWithSeverity(severity: Types.Severity, summary: string, detail: string?, opts: { [string]: any }?)
	local msg: Types.Message = { severity = severity, summary = summary, detail = detail }
	if opts then
		for k, v in opts do
			(msg :: any)[k] = v
		end
	end
	Toast.add(msg)
end

function Toast.success(summary: string, detail: string?, opts: { [string]: any }?)
	addWithSeverity("success", summary, detail, opts)
end

function Toast.info(summary: string, detail: string?, opts: { [string]: any }?)
	addWithSeverity("info", summary, detail, opts)
end

function Toast.warn(summary: string, detail: string?, opts: { [string]: any }?)
	addWithSeverity("warn", summary, detail, opts)
end

function Toast.error(summary: string, detail: string?, opts: { [string]: any }?)
	addWithSeverity("error", summary, detail, opts)
end

function Toast.secondary(summary: string, detail: string?, opts: { [string]: any }?)
	addWithSeverity("secondary", summary, detail, opts)
end

-- Server API
function Toast.notify(player: Player, message: Types.Message)
	if not isServer then
		error("Toast.notify can only be called from the server; use Toast.add on the client", 2)
	end
	ensureInit()
	Remote.getOrCreate():FireClient(player, message)
end

function Toast.notifyAll(message: Types.Message)
	if not isServer then
		error("Toast.notifyAll can only be called from the server; use Toast.add on the client", 2)
	end
	ensureInit()
	Remote.getOrCreate():FireAllClients(message)
end

if isClient then
	Remote.initClient(function(message: Types.Message)
		Toast.add(message)
	end)
end

return Toast
