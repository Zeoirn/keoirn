--[[
	KeoirnLite — Lightweight fallback for Keoirn
	Drop-in replacement with the identical public API.
	Designed for low-end devices: no tweens, minimal Instance count,
	simple solid-colour style, zero asset loads.

	Auto-switching usage (put at the top of your script):
	────────────────────────────────────────────────────
		local FPS_THRESHOLD   = 30   -- below this → use Lite
		local SAMPLE_SECONDS  = 2    -- how long to sample FPS

		local function averageFPS(secs)
			local t, n = 0, 0
			local conn
			conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
				t += dt; n += 1
			end)
			task.wait(secs)
			conn:Disconnect()
			return n / t
		end

		local fps  = averageFPS(SAMPLE_SECONDS)
		local Lib  = if fps >= FPS_THRESHOLD
		             then loadstring(game:HttpGet("https://raw.githubusercontent.com/Zeoirn/keoirn/refs/heads/main/Keoirn.lua"))()
		             else loadstring(game:HttpGet("YOUR_RAW_KEOIRNLITE_URL"))()

		-- From here, use Lib exactly the same as Keoirn:
		local Window = Lib:CreateWindow({ Title = "My GUI" })
		...
	────────────────────────────────────────────────────
--]]

-- ─── Services ────────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")  -- kept for 0-time snaps (no actual tweening)

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")

-- ─── Palette (token → Color3) ─────────────────────────────────────────────
local PALETTE = {
	Background     = Color3.fromRGB(18,  18,  22),
	Surface        = Color3.fromRGB(26,  26,  32),
	Panel          = Color3.fromRGB(32,  32,  40),
	Stroke         = Color3.fromRGB(55,  55,  70),
	Content        = Color3.fromRGB(220, 220, 230),
	ContentDim     = Color3.fromRGB(140, 140, 160),
	Accent         = Color3.fromRGB(100, 149, 237),
	AccentDim      = Color3.fromRGB(70,  110, 200),
	Error          = Color3.fromRGB(220,  80,  80),
	White          = Color3.fromRGB(255, 255, 255),
	Black          = Color3.fromRGB(0,    0,   0),
	Transparent    = Color3.fromRGB(0,    0,   0),  -- paired with Transparency=1
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r, parent)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function pad(l, r, t, b, parent)
	make("UIPadding", {
		PaddingLeft   = UDim.new(0, l),
		PaddingRight  = UDim.new(0, r),
		PaddingTop    = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b),
	}, parent)
end

local function listLayout(dir, halign, valign, spacing, parent)
	make("UIListLayout", {
		FillDirection      = dir or Enum.FillDirection.Vertical,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment  = valign  or Enum.VerticalAlignment.Top,
		SortOrder          = Enum.SortOrder.LayoutOrder,
		Padding            = UDim.new(0, spacing or 4),
	}, parent)
end

local function label(text, size, color, halign, parent)
	return make("TextLabel", {
		Text                = tostring(text),
		TextSize            = size or 14,
		TextColor3          = color or PALETTE.Content,
		Font                = Enum.Font.GothamMedium,
		BackgroundTransparency = 1,
		BorderSizePixel     = 0,
		TextXAlignment      = halign or Enum.TextXAlignment.Left,
		TextWrapped         = true,
		AutomaticSize       = Enum.AutomaticSize.Y,
		Size                = UDim2.new(1, 0, 0, 0),
	}, parent)
end

local function button(text, color, parent)
	local btn = make("TextButton", {
		Text            = tostring(text),
		TextSize        = 14,
		TextColor3      = PALETTE.White,
		Font            = Enum.Font.GothamMedium,
		BackgroundColor3 = color or PALETTE.Accent,
		BorderSizePixel = 0,
		AutomaticSize   = Enum.AutomaticSize.XY,
		AutoButtonColor = false,
	}, parent)
	corner(6, btn)
	pad(12, 12, 6, 6, btn)
	return btn
end

local function stroke(color, thick, parent)
	return make("UIStroke", {
		Color     = color or PALETTE.Stroke,
		Thickness = thick or 1,
	}, parent)
end

-- ─── Shared connection management ────────────────────────────────────────────
local function newConnPool()
	local pool = {}
	pool._list = {}
	function pool:add(conn)  table.insert(self._list, conn) end
	function pool:cleanAll()
		for _, c in self._list do pcall(c.Disconnect, c) end
		table.clear(self._list)
	end
	return pool
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Element classes
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Button ──────────────────────────────────────────────────────────────────
local Button = {}
Button.__index = Button
Button.__type  = "Button"

function Button.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab      = tab,
		window   = tab.window,
		name     = props.name or props.Name or "Button",
		icon     = props.icon or props.Icon,
		callback = props.callback or props.Callback or function() end,
		_shown   = true,
		_pool    = newConnPool(),
	}, Button)

	-- Frame
	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)

	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	local interact = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 5,
	}, self.main)

	self._pool:add(interact.MouseButton1Click:Connect(function()
		pcall(self.callback)
	end))

	return self
end

function Button:Set() end  -- no-op (buttons have no state)

function Button:_setShown(shown)
	self.main.Visible = shown
	self._shown = shown
end

function Button:Remove()
	self._pool:cleanAll()
	self.main:Destroy()
end

-- ─── Toggle ──────────────────────────────────────────────────────────────────
local Toggle = {}
Toggle.__index = Toggle
Toggle.__type  = "Toggle"

function Toggle.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab      = tab,
		window   = tab.window,
		name     = props.name or props.Name or "Toggle",
		value    = props.value or props.Value or props.default or false,
		callback = props.callback or props.Callback or function() end,
		flag     = props.flag or props.Flag,
		_pool    = newConnPool(),
	}, Toggle)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)

	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	-- Pill indicator
	self.pill = make("Frame", {
		Size            = UDim2.fromOffset(34, 18),
		BackgroundColor3 = PALETTE.Stroke,
		BorderSizePixel = 0,
		AnchorPoint     = Vector2.new(1, 0.5),
		Position        = UDim2.new(1, -12, 0.5, 0),
	}, self.main)
	corner(9, self.pill)

	self.knob = make("Frame", {
		Size            = UDim2.fromOffset(12, 12),
		AnchorPoint     = Vector2.new(0, 0.5),
		Position        = UDim2.fromOffset(3, 9),
		BackgroundColor3 = PALETTE.White,
		BorderSizePixel = 0,
	}, self.pill)
	corner(6, self.knob)

	self:_render()

	local interact = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 5,
	}, self.main)

	self._pool:add(interact.MouseButton1Click:Connect(function()
		self:Set(not self.value)
	end))

	return self
end

function Toggle:_render()
	if self.value then
		self.pill.BackgroundColor3 = PALETTE.Accent
		self.knob.Position = UDim2.fromOffset(34 - 15, 9)
	else
		self.pill.BackgroundColor3 = PALETTE.Stroke
		self.knob.Position = UDim2.fromOffset(3, 9)
	end
end

function Toggle:Set(v, silent)
	self.value = v == true
	self:_render()
	if not silent then
		pcall(self.callback, self.value)
		self.window:_persist(self)
	end
end

function Toggle:_setShown(shown)  self.main.Visible = shown  end
function Toggle:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── Slider ──────────────────────────────────────────────────────────────────
local Slider = {}
Slider.__index = Slider
Slider.__type  = "Slider"

function Slider.new(tab, props)
	props = props or {}
	local range = props.range or props.Range or {0, 100}
	local self = setmetatable({
		tab      = tab,
		window   = tab.window,
		name     = props.name or props.Name or "Slider",
		min      = range[1] or 0,
		max      = range[2] or 100,
		value    = props.value or props.Value or props.default or range[1] or 0,
		callback = props.callback or props.Callback or function() end,
		flag     = props.flag or props.Flag,
		_drag    = false,
		_pool    = newConnPool(),
	}, Slider)

	self.value = math.clamp(self.value, self.min, self.max)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)

	-- Header row
	local header = make("Frame", {
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 4, header)
	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, header)

	self.valLabel = make("TextLabel", {
		Text            = tostring(self.value),
		TextSize        = 13,
		TextColor3      = PALETTE.ContentDim,
		Font            = Enum.Font.GothamMedium,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Right,
		Size            = UDim2.new(0, 60, 1, 0),
		AnchorPoint     = Vector2.new(1, 0),
		Position        = UDim2.new(1, 0, 0, 0),
	}, header)

	-- Track
	self.track = make("Frame", {
		Size            = UDim2.new(1, -24, 0, 6),
		Position        = UDim2.new(0, 12, 1, -16),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
	}, self.main)
	corner(3, self.track)

	self.fill = make("Frame", {
		Size            = UDim2.new(self:_ratio(), 0, 1, 0),
		BackgroundColor3 = PALETTE.Accent,
		BorderSizePixel = 0,
	}, self.track)
	corner(3, self.fill)

	-- Invisible interact over the track
	local interact = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 20),
		Position = UDim2.new(0, 0, 0, -10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 5,
	}, self.track)

	local function fromMouse()
		local mx = UserInputService:GetMouseLocation().X
		local abs = self.track.AbsolutePosition.X
		local w   = self.track.AbsoluteSize.X
		local r   = math.clamp((mx - abs) / math.max(w, 1), 0, 1)
		local raw = self.min + r * (self.max - self.min)
		-- snap to integer if range is integer
		if props.integer or props.Integer then raw = math.round(raw) end
		return math.clamp(raw, self.min, self.max)
	end

	self._pool:add(interact.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or
		   i.UserInputType == Enum.UserInputType.Touch then
			self._drag = true
			self:Set(fromMouse())
		end
	end))

	self._pool:add(UserInputService.InputChanged:Connect(function(i)
		if self._drag and (i.UserInputType == Enum.UserInputType.MouseMovement or
		                   i.UserInputType == Enum.UserInputType.Touch) then
			self:Set(fromMouse())
		end
	end))

	self._pool:add(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or
		   i.UserInputType == Enum.UserInputType.Touch then
			self._drag = false
		end
	end))

	return self
end

function Slider:_ratio()
	local range = self.max - self.min
	return if range <= 0 then 1 else (self.value - self.min) / range
end

function Slider:Set(v, silent)
	self.value = math.clamp(tonumber(v) or self.min, self.min, self.max)
	self.fill.Size = UDim2.new(self:_ratio(), 0, 1, 0)
	self.valLabel.Text = tostring(math.round(self.value * 100) / 100)
	if not silent then
		pcall(self.callback, self.value)
		self.window:_persist(self)
	end
end

function Slider:_setShown(shown)  self.main.Visible = shown  end
function Slider:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── Dropdown ────────────────────────────────────────────────────────────────
local Dropdown = {}
Dropdown.__index = Dropdown
Dropdown.__type  = "Dropdown"

function Dropdown.new(tab, props)
	props = props or {}
	local rawOpts = props.options or props.Options or {}
	local opts = {}
	for _, v in rawOpts do if type(v) == "string" then table.insert(opts, v) end end

	local multi = props.multiSelect or props.MultiSelect or false

	local self = setmetatable({
		tab         = tab,
		window      = tab.window,
		name        = props.name or props.Name or "Dropdown",
		options     = opts,
		multiSelect = multi,
		value       = {},
		callback    = props.callback or props.Callback or function() end,
		flag        = props.flag or props.Flag,
		_open       = false,
		_pool       = newConnPool(),
		_optFrames  = {},
	}, Dropdown)

	-- Seed initial value
	local seed = props.value or props.Value or props.currentOption or props.CurrentOption
	if type(seed) == "string" then seed = {seed}
	elseif type(seed) ~= "table" then seed = {}
	end
	for _, s in seed do
		if table.find(self.options, s) then
			table.insert(self.value, s)
			if not multi then break end
		end
	end

	-- ── Build ──
	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
		ClipsDescendants = true,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)

	-- Header
	local header = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 4,
	}, self.main)

	pad(12, 12, 0, 0, header)
	local hinner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, header)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, hinner)
	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, hinner)

	self.selectedLbl = make("TextLabel", {
		Text            = self:_displayText(),
		TextSize        = 13,
		TextColor3      = PALETTE.ContentDim,
		Font            = Enum.Font.GothamMedium,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Right,
		Size            = UDim2.new(0, 120, 1, 0),
		AnchorPoint     = Vector2.new(1, 0),
		Position        = UDim2.new(1, 0, 0, 0),
		TextTruncate    = Enum.TextTruncate.AtEnd,
	}, hinner)

	-- Options container (hidden until open)
	self.optContainer = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 0),
		Position        = UDim2.fromOffset(0, 36),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		AutomaticSize   = Enum.AutomaticSize.Y,
	}, self.main)

	listLayout(nil, nil, nil, 2, self.optContainer)
	pad(6, 6, 4, 4, self.optContainer)

	for _, opt in self.options do self:_buildOpt(opt) end

	self._pool:add(header.MouseButton1Click:Connect(function()
		if self._open then self:_close() else self:_openDrop() end
	end))

	return self
end

function Dropdown:_displayText()
	if #self.value == 0 then return "None"
	elseif #self.value == 1 then return self.value[1]
	else return "Various" end
end

function Dropdown:_buildOpt(name)
	local selected = table.find(self.value, name) ~= nil
	local row = make("TextButton", {
		Name            = name,
		Size            = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = if selected then PALETTE.AccentDim else PALETTE.Surface,
		BorderSizePixel = 0,
		Text            = "",
		AutoButtonColor = false,
	}, self.optContainer)
	corner(4, row)

	local lbl = label(name, 13, PALETTE.Content, Enum.TextXAlignment.Left, row)
	lbl.AutomaticSize = Enum.AutomaticSize.None
	lbl.Size = UDim2.new(1, -24, 1, 0)
	lbl.Position = UDim2.fromOffset(8, 0)
	lbl.TextYAlignment = Enum.TextYAlignment.Center

	local entry = {name = name, row = row, label = lbl}
	table.insert(self._optFrames, entry)

	self._pool:add(row.MouseButton1Click:Connect(function()
		if not self.multiSelect then
			table.clear(self.value)
			table.insert(self.value, name)
			self:_close()
		else
			local idx = table.find(self.value, name)
			if idx then table.remove(self.value, idx)
			else        table.insert(self.value, name) end
			self:_refreshOptColors()
		end
		self.selectedLbl.Text = self:_displayText()
		pcall(self.callback, self:_callbackValue())
		self.window:_persist(self)
	end))

	return entry
end

function Dropdown:_refreshOptColors()
	for _, e in self._optFrames do
		e.row.BackgroundColor3 = if table.find(self.value, e.name)
		                         then PALETTE.AccentDim else PALETTE.Surface
	end
end

function Dropdown:_callbackValue()
	return if self.multiSelect then table.clone(self.value) else self.value[1]
end

function Dropdown:_openDrop()
	self._open = true
	self.optContainer.Visible = true
	-- expand main to fit options
	local optH = #self.options * 30 + 8
	self.main.Size = UDim2.new(1, 0, 0, 36 + math.min(optH, 150))
	self.main.ClipsDescendants = true
end

function Dropdown:_close()
	self._open = false
	self.optContainer.Visible = false
	self.main.Size = UDim2.new(1, 0, 0, 36)
end

function Dropdown:Set(v, silent)
	if type(v) == "string" then v = {v}
	elseif type(v) ~= "table" then v = {}
	end
	table.clear(self.value)
	for _, s in v do
		if table.find(self.options, s) then
			table.insert(self.value, s)
			if not self.multiSelect then break end
		end
	end
	self.selectedLbl.Text = self:_displayText()
	self:_refreshOptColors()
	if not silent then
		pcall(self.callback, self:_callbackValue())
		self.window:_persist(self)
	end
end

function Dropdown:Refresh(newOpts)
	self.options = {}
	for _, v in (newOpts or {}) do
		if type(v) == "string" then table.insert(self.options, v) end
	end
	-- destroy old opt frames
	for _, e in self._optFrames do e.row:Destroy() end
	table.clear(self._optFrames)
	-- rebuild
	for _, opt in self.options do self:_buildOpt(opt) end
	-- re-validate value
	local filtered = {}
	for _, s in self.value do
		if table.find(self.options, s) then table.insert(filtered, s) end
	end
	self.value = filtered
	self.selectedLbl.Text = self:_displayText()
end

function Dropdown:Add(name)
	if type(name) ~= "string" or name == "" then return end
	if table.find(self.options, name) then return end
	table.insert(self.options, name)
	self:_buildOpt(name)
end

function Dropdown:Remove(name)
	local idx = table.find(self.options, name)
	if not idx then return end
	table.remove(self.options, idx)
	for i, e in self._optFrames do
		if e.name == name then
			e.row:Destroy()
			table.remove(self._optFrames, i)
			break
		end
	end
	local vi = table.find(self.value, name)
	if vi then
		table.remove(self.value, vi)
		self.selectedLbl.Text = self:_displayText()
		pcall(self.callback, self:_callbackValue())
		self.window:_persist(self)
	end
end

function Dropdown:_setShown(shown)  self.main.Visible = shown  end
function Dropdown:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── Input ───────────────────────────────────────────────────────────────────
local Input = {}
Input.__index = Input
Input.__type  = "Input"

function Input.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab         = tab,
		window      = tab.window,
		name        = props.name or props.Name or "Input",
		value       = tostring(props.value or props.Value or props.currentValue or ""),
		placeholder = props.placeholder or props.Placeholder or "",
		numeric     = props.numeric or props.Numeric or false,
		callback    = props.callback or props.Callback or function() end,
		flag        = props.flag or props.Flag,
		_pool       = newConnPool(),
	}, Input)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)

	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	self.box = make("Frame", {
		Size            = UDim2.fromOffset(100, 28),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		AnchorPoint     = Vector2.new(1, 0.5),
		Position        = UDim2.new(1, 0, 0.5, 0),
	}, inner)
	corner(6, self.box)
	stroke(PALETTE.Stroke, 1, self.box)

	self.input = make("TextBox", {
		Text            = self.value,
		PlaceholderText = self.placeholder,
		TextSize        = 13,
		TextColor3      = PALETTE.Content,
		PlaceholderColor3 = PALETTE.ContentDim,
		Font            = Enum.Font.GothamMedium,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Center,
		Size            = UDim2.new(1, -10, 1, 0),
		Position        = UDim2.fromOffset(5, 0),
		ClearTextOnFocus = props.clearOnFocus or false,
		TextTruncate    = Enum.TextTruncate.AtEnd,
	}, self.box)

	self._pool:add(self.input.FocusLost:Connect(function()
		local v = self.input.Text
		if self.numeric then
			local n = tonumber(v)
			if not n then self.input.Text = self.value; return end
			v = tostring(n)
		end
		if v == self.value then return end
		self.value = v
		pcall(self.callback, v)
		self.window:_persist(self)
	end))

	return self
end

function Input:Set(v, silent)
	self.value = tostring(v)
	self.input.Text = self.value
	if not silent then
		pcall(self.callback, self.value)
		self.window:_persist(self)
	end
end

function Input:_setShown(shown)  self.main.Visible = shown  end
function Input:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── Keybind ─────────────────────────────────────────────────────────────────
local Keybind = {}
Keybind.__index = Keybind
Keybind.__type  = "Keybind"

local MB_NAMES = {
	[Enum.UserInputType.MouseButton1] = "MB1",
	[Enum.UserInputType.MouseButton2] = "MB2",
	[Enum.UserInputType.MouseButton3] = "MB3",
}

local function keyName(k)
	if typeof(k) ~= "EnumItem" or k == Enum.KeyCode.Unknown then return "None" end
	return MB_NAMES[k] or k.Name
end

local function parseKey(raw)
	if typeof(raw) == "EnumItem" then return raw end
	if type(raw) == "string" then
		local ok, v = pcall(function() return Enum.KeyCode[raw] end)
		if ok and v then return v end
		local ok2, v2 = pcall(function() return Enum.UserInputType[raw] end)
		if ok2 and v2 and MB_NAMES[v2] then return v2 end
	end
	return Enum.KeyCode.Unknown
end

function Keybind.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab        = tab,
		window     = tab.window,
		name       = props.name or props.Name or "Keybind",
		value      = parseKey(props.value or props.Value or props.default),
		callback   = props.callback or props.Callback or function() end,
		onChanged  = props.onChanged or props.OnChanged or function() end,
		flag       = props.flag or props.Flag,
		recording  = false,
		_pool      = newConnPool(),
	}, Keybind)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)
	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	self.keyBtn = make("TextButton", {
		Text            = keyName(self.value),
		TextSize        = 13,
		TextColor3      = PALETTE.Content,
		Font            = Enum.Font.GothamMedium,
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size            = UDim2.fromOffset(60, 26),
		AnchorPoint     = Vector2.new(1, 0.5),
		Position        = UDim2.new(1, 0, 0.5, 0),
	}, self.main)
	corner(5, self.keyBtn)
	stroke(PALETTE.Stroke, 1, self.keyBtn)

	self._pool:add(self.keyBtn.MouseButton1Click:Connect(function()
		if self.recording then
			self.recording = false
			self.keyBtn.Text = keyName(self.value)
		else
			self.recording = true
			self.keyBtn.Text = "..."
		end
	end))

	self._pool:add(UserInputService.InputBegan:Connect(function(inp, gp)
		if gp then return end
		if self.recording then
			local k = if inp.UserInputType == Enum.UserInputType.Keyboard
			          then inp.KeyCode
			          else (MB_NAMES[inp.UserInputType] and inp.UserInputType or nil)
			if k then
				self.value = k
				self.recording = false
				self.keyBtn.Text = keyName(self.value)
				pcall(self.onChanged, self.value)
				self.window:_persist(self)
			end
		else
			if typeof(self.value) == "EnumItem" and self.value ~= Enum.KeyCode.Unknown then
				local match = (self.value.EnumType == Enum.KeyCode and inp.KeyCode == self.value) or
				              (self.value.EnumType == Enum.UserInputType and inp.UserInputType == self.value)
				if match then pcall(self.callback, self.value) end
			end
		end
	end))

	return self
end

function Keybind:Set(v, silent)
	self.value = parseKey(v)
	self.keyBtn.Text = keyName(self.value)
	if not silent then
		pcall(self.onChanged, self.value)
		self.window:_persist(self)
	end
end

function Keybind:_setShown(shown)  self.main.Visible = shown  end
function Keybind:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── ColorPicker ─────────────────────────────────────────────────────────────
-- Lite version: shows a simple hex TextBox + live preview swatch
local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__type  = "ColorPicker"

function ColorPicker.new(tab, props)
	props = props or {}
	local defColor = props.color or props.Color or props.value or props.Value or Color3.fromRGB(255,255,255)
	if type(defColor) == "string" then
		local ok, c = pcall(Color3.fromHex, defColor:gsub("^#", ""))
		defColor = if ok then c else Color3.fromRGB(255,255,255)
	end

	local self = setmetatable({
		tab      = tab,
		window   = tab.window,
		name     = props.name or props.Name or "Color",
		value    = defColor,
		alpha    = props.alpha or props.Alpha or 1,
		callback = props.callback or props.Callback or function() end,
		flag     = props.flag or props.Flag,
		_pool    = newConnPool(),
	}, ColorPicker)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)
	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	-- Swatch
	self.swatch = make("Frame", {
		Size            = UDim2.fromOffset(22, 22),
		BackgroundColor3 = self.value,
		BorderSizePixel = 0,
		AnchorPoint     = Vector2.new(1, 0.5),
		Position        = UDim2.new(1, -90, 0.5, 0),
	}, self.main)
	corner(4, self.swatch)

	-- Hex box
	self.hexInput = make("TextBox", {
		Text            = "#" .. self.value:ToHex():upper(),
		PlaceholderText = "#FFFFFF",
		TextSize        = 12,
		TextColor3      = PALETTE.Content,
		PlaceholderColor3 = PALETTE.ContentDim,
		Font            = Enum.Font.Code,
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Center,
		Size            = UDim2.fromOffset(80, 26),
		AnchorPoint     = Vector2.new(1, 0.5),
		Position        = UDim2.new(1, 0, 0.5, 0),
		ClearTextOnFocus = false,
	}, self.main)
	corner(5, self.hexInput)
	stroke(PALETTE.Stroke, 1, self.hexInput)

	self._pool:add(self.hexInput.FocusLost:Connect(function()
		local raw = self.hexInput.Text:gsub("^#", ""):gsub("^0x", "")
		local ok, c = pcall(Color3.fromHex, raw)
		if ok then
			self:Set(c)
		else
			self.hexInput.Text = "#" .. self.value:ToHex():upper()
		end
	end))

	return self
end

function ColorPicker:Set(color, silent)
	if typeof(color) == "Color3" then
		self.value = color
		self.swatch.BackgroundColor3 = color
		if not self.hexInput:IsFocused() then
			self.hexInput.Text = "#" .. color:ToHex():upper()
		end
		if not silent then
			pcall(self.callback, color, self.alpha)
			self.window:_persist(self)
		end
	end
end

function ColorPicker:SetAlpha(a, silent)
	self.alpha = math.clamp(tonumber(a) or 1, 0, 1)
	if not silent then
		pcall(self.callback, self.value, self.alpha)
		self.window:_persist(self)
	end
end

function ColorPicker:_setShown(shown)  self.main.Visible = shown  end
function ColorPicker:Remove()  self._pool:cleanAll(); self.main:Destroy()  end

-- ─── Stat ────────────────────────────────────────────────────────────────────
local Stat = {}
Stat.__index = Stat
Stat.__type  = "Stat"

function Stat.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab    = tab,
		window = tab.window,
		name   = props.name or props.Name or "Stat",
		value  = tostring(props.value or props.Value or "—"),
	}, Stat)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(12, 12, 0, 0, self.main)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.main)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)
	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

	self.valLbl = make("TextLabel", {
		Text            = self.value,
		TextSize        = 14,
		TextColor3      = PALETTE.Accent,
		Font            = Enum.Font.GothamMedium,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Right,
		Size            = UDim2.new(0, 120, 1, 0),
		AnchorPoint     = Vector2.new(1, 0),
		Position        = UDim2.new(1, 0, 0, 0),
		TextTruncate    = Enum.TextTruncate.AtEnd,
	}, inner)

	return self
end

function Stat:Set(v)
	self.value = tostring(v)
	self.valLbl.Text = self.value
end

function Stat:_setShown(shown)  self.main.Visible = shown  end
function Stat:Remove()  self.main:Destroy()  end

-- ─── Progress ────────────────────────────────────────────────────────────────
local Progress = {}
Progress.__index = Progress
Progress.__type  = "Progress"

function Progress.new(tab, props)
	props = props or {}
	local range = props.range or props.Range or {0, 1}
	local self = setmetatable({
		tab   = tab,
		window = tab.window,
		name  = props.name or props.Name or "Progress",
		min   = range[1] or 0,
		max   = range[2] or 1,
		value = props.value or props.Value or range[1] or 0,
	}, Progress)

	self.value = math.clamp(self.value, self.min, self.max)

	self.main = make("Frame", {
		Name            = self.name,
		Size            = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)

	label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, self.main).Position = UDim2.fromOffset(12, 10)

	self.track = make("Frame", {
		Size            = UDim2.new(1, -24, 0, 6),
		Position        = UDim2.new(0, 12, 1, -14),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
	}, self.main)
	corner(3, self.track)

	self.fill = make("Frame", {
		Size            = UDim2.new(self:_ratio(), 0, 1, 0),
		BackgroundColor3 = PALETTE.Accent,
		BorderSizePixel = 0,
	}, self.track)
	corner(3, self.fill)

	return self
end

function Progress:_ratio()
	local r = self.max - self.min
	return if r <= 0 then 1 else (self.value - self.min) / r
end

function Progress:Set(v)
	self.value = math.clamp(tonumber(v) or self.min, self.min, self.max)
	self.fill.Size = UDim2.new(self:_ratio(), 0, 1, 0)
end

function Progress:_setShown(shown)  self.main.Visible = shown  end
function Progress:Remove()  self.main:Destroy()  end

-- ─── Console ─────────────────────────────────────────────────────────────────
local Console = {}
Console.__index = Console
Console.__type  = "Console"

function Console.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab      = tab,
		window   = tab.window,
		name     = props.name or props.Name,
		height   = math.max(tonumber(props.height or props.Height) or 120, 48),
		maxLines = math.max(tonumber(props.maxLines or props.MaxLines) or 200, 1),
		follow   = props.follow or props.Follow or false,
		lines    = {},
	}, Console)

	self.main = make("Frame", {
		Name            = self.name or "Console",
		Size            = UDim2.new(1, 0, 0, self.height + (self.name and 28 or 0) + 16),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(6, self.main)
	stroke(PALETTE.Stroke, 1, self.main)

	if self.name then
		label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, self.main).Position = UDim2.fromOffset(12, 8)
	end

	local panel = make("Frame", {
		Size            = UDim2.new(1, -16, 0, self.height),
		Position        = UDim2.new(0, 8, 1, -(self.height + 8)),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, self.main)
	corner(5, panel)

	self.scroll = make("ScrollingFrame", {
		Size            = UDim2.new(1, -10, 1, -10),
		Position        = UDim2.fromOffset(5, 5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize      = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)

	listLayout(nil, nil, nil, 1, self.scroll)

	if props.text or props.Text then
		self:Set(props.text or props.Text)
	end

	return self
end

function Console:_makeLabel(text)
	return make("TextLabel", {
		Text            = text == "" and " " or text,
		TextSize        = 12,
		TextColor3      = PALETTE.ContentDim,
		Font            = Enum.Font.Code,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Left,
		Size            = UDim2.new(1, 0, 0, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		TextWrapped     = true,
		RichText        = false,
	}, self.scroll)
end

function Console:_trim()
	while #self.lines > self.maxLines do
		table.remove(self.lines, 1)
	end
end

function Console:_flush()
	for _, c in self.scroll:GetChildren() do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for _, line in self.lines do
		self:_makeLabel(line)
	end
	if self.follow then
		task.defer(function()
			self.scroll.CanvasPosition = Vector2.new(0, self.scroll.AbsoluteCanvasSize.Y)
		end)
	end
end

function Console:Set(text)
	table.clear(self.lines)
	for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(self.lines, line)
	end
	self:_trim()
	self:_flush()
end

function Console:Append(text)
	for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(self.lines, line)
	end
	self:_trim()
	-- append incrementally
	if #self.lines > 0 then
		self:_makeLabel(self.lines[#self.lines])
	end
	if self.follow then
		task.defer(function()
			self.scroll.CanvasPosition = Vector2.new(0, self.scroll.AbsoluteCanvasSize.Y)
		end)
	end
end

function Console:Clear()
	table.clear(self.lines)
	self:_flush()
end

function Console:Get()
	return table.concat(self.lines, "\n")
end

function Console:_setShown(shown)  self.main.Visible = shown  end
function Console:Remove()  self.main:Destroy()  end

-- ─── Text / Divider ──────────────────────────────────────────────────────────
local Text = {}
Text.__index = Text
Text.__type  = "Text"

function Text.new(tab, props)
	props = props or {}
	local self = setmetatable({ tab = tab, window = tab.window }, Text)
	self.main = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	pad(8, 8, 4, 4, self.main)
	self.lbl = label(props.text or props.Text or "", props.textSize or props.TextSize or 14,
	                 PALETTE.ContentDim, Enum.TextXAlignment.Left, self.main)
	return self
end

function Text:Set(text)  self.lbl.Text = tostring(text)  end
function Text:_setShown(shown)  self.main.Visible = shown  end
function Text:Remove()  self.main:Destroy()  end

local Divider = {}
Divider.__index = Divider
Divider.__type  = "Divider"

function Divider.new(tab, props)
	props = props or {}
	local self = setmetatable({ tab = tab, window = tab.window }, Divider)
	local spacing = props.spacing or props.Spacing or 8
	self.main = make("Frame", {
		Size            = UDim2.new(1, -24, 0, spacing * 2 + 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	if props.line ~= false and props.Line ~= false then
		make("Frame", {
			Size            = UDim2.new(1, 0, 0, 1),
			Position        = UDim2.fromOffset(0, spacing),
			BackgroundColor3 = PALETTE.Stroke,
			BorderSizePixel = 0,
		}, self.main)
	end
	return self
end

function Divider:_setShown(shown)  self.main.Visible = shown  end
function Divider:Remove()  self.main:Destroy()  end

-- ─── Section ─────────────────────────────────────────────────────────────────
local Section = {}
Section.__index = Section
Section.__type  = "Section"

function Section.new(tab, props)
	props = props or {}
	local self = setmetatable({
		tab    = tab,
		window = tab.window,
		elements = {},
	}, Section)

	self.main = make("Frame", {
		Name            = props.name or props.Name or "Section",
		Size            = UDim2.new(1, 0, 0, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder     = 0,
	}, tab.tabPage)
	corner(8, self.main)
	stroke(PALETTE.Stroke, 1, self.main)
	pad(8, 8, 8, 8, self.main)

	-- Header label
	if props.name or props.Name then
		make("TextLabel", {
			Text            = props.name or props.Name,
			TextSize        = 12,
			TextColor3      = PALETTE.ContentDim,
			Font            = Enum.Font.GothamBold,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			TextXAlignment  = Enum.TextXAlignment.Left,
			Size            = UDim2.new(1, 0, 0, 16),
			LayoutOrder     = 0,
		}, self.main)
	end

	self.tabPage = self.main  -- so sub-elements parent here
	listLayout(nil, nil, nil, 4, self.main)

	return self
end

-- Sections proxy the same element creator methods as Tab
function Section:_proxyTab()
	return setmetatable({ tabPage = self.main, window = self.window, forgetState = false, compact = false }, {
		__index = self.tab
	})
end

function Section:CreateButton(props)    return Button.new(self:_proxyTab(), props) end
function Section:CreateToggle(props)    return Toggle.new(self:_proxyTab(), props) end
function Section:CreateSlider(props)    return Slider.new(self:_proxyTab(), props) end
function Section:CreateDropdown(props)  return Dropdown.new(self:_proxyTab(), props) end
function Section:CreateInput(props)     return Input.new(self:_proxyTab(), props) end
function Section:CreateKeybind(props)   return Keybind.new(self:_proxyTab(), props) end
function Section:CreateColorPicker(props) return ColorPicker.new(self:_proxyTab(), props) end
function Section:CreateStat(props)      return Stat.new(self:_proxyTab(), props) end
function Section:CreateProgress(props)  return Progress.new(self:_proxyTab(), props) end
function Section:CreateConsole(props)   return Console.new(self:_proxyTab(), props) end
function Section:CreateText(props)      return Text.new(self:_proxyTab(), props) end
function Section:CreateDivider(props)   return Divider.new(self:_proxyTab(), props) end

function Section:_setShown(shown)  self.main.Visible = shown  end
function Section:Remove()  self.main:Destroy()  end

-- ═══════════════════════════════════════════════════════════════════════════
-- Tab
-- ═══════════════════════════════════════════════════════════════════════════
local Tab = {}
Tab.__index = Tab

function Tab.new(window, props)
	props = props or {}
	local self = setmetatable({
		window     = window,
		name       = props.name or props.Name or "Tab",
		elements   = {},
		forgetState = false,
		compact    = false,
	}, Tab)

	-- Tab button
	self.btn = make("TextButton", {
		Text            = self.name,
		TextSize        = 14,
		TextColor3      = PALETTE.ContentDim,
		Font            = Enum.Font.GothamMedium,
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		AutomaticSize   = Enum.AutomaticSize.X,
		Size            = UDim2.fromOffset(0, 28),
	}, window.tabBar)
	corner(6, self.btn)
	pad(12, 12, 0, 0, self.btn)

	-- Content page
	self.tabPage = make("ScrollingFrame", {
		Size            = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize      = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible         = false,
	}, window.content)
	listLayout(nil, nil, nil, 6, self.tabPage)
	pad(8, 8, 8, 8, self.tabPage)

	self.btn.MouseButton1Click:Connect(function()
		window:_selectTab(self)
	end)

	return self
end

function Tab:_setActive(active)
	self.btn.TextColor3 = if active then PALETTE.Content else PALETTE.ContentDim
	self.btn.BackgroundColor3 = if active then PALETTE.Accent else PALETTE.Surface
	self.tabPage.Visible = active
end

-- ── Element creators ────────────────────────────────────────────────────────
function Tab:CreateButton(props)    local e = Button.new(self, props);    table.insert(self.elements, e); return e end
function Tab:CreateToggle(props)    local e = Toggle.new(self, props);    table.insert(self.elements, e); return e end
function Tab:CreateSwitch(props)    return self:CreateToggle(props) end
function Tab:CreateSlider(props)    local e = Slider.new(self, props);    table.insert(self.elements, e); return e end
function Tab:CreateDropdown(props)  local e = Dropdown.new(self, props);  table.insert(self.elements, e); return e end
function Tab:CreateInput(props)     local e = Input.new(self, props);     table.insert(self.elements, e); return e end
function Tab:CreateKeybind(props)   local e = Keybind.new(self, props);   table.insert(self.elements, e); return e end
function Tab:CreateColorPicker(props) local e = ColorPicker.new(self, props); table.insert(self.elements, e); return e end
function Tab:CreateStat(props)      local e = Stat.new(self, props);      table.insert(self.elements, e); return e end
function Tab:CreateProgress(props)  local e = Progress.new(self, props);  table.insert(self.elements, e); return e end
function Tab:CreateConsole(props)   local e = Console.new(self, props);   table.insert(self.elements, e); return e end
function Tab:CreateText(props)      local e = Text.new(self, props);      table.insert(self.elements, e); return e end
function Tab:CreateDivider(props)   local e = Divider.new(self, props);   table.insert(self.elements, e); return e end
function Tab:CreateSection(props)   local e = Section.new(self, props);   table.insert(self.elements, e); return e end

-- ═══════════════════════════════════════════════════════════════════════════
-- Window
-- ═══════════════════════════════════════════════════════════════════════════
local Window = {}
Window.__index = Window
Window.__type  = "Window"

function Window.new(lib, props)
	props = props or {}
	local self = setmetatable({
		lib          = lib,
		name         = props.Title or props.title or props.Name or props.name or "KeoirnLite",
		tabs         = {},
		_selectedTab = nil,
		hidden       = false,
		unloaded     = false,
		theme        = {},        -- stub; Keoirn API compat
		settings     = { toggleKeybind = props.toggleKeybind or props.ToggleKeybind or Enum.KeyCode.RightShift },
		_flags       = {},
		_connections = newConnPool(),
	}, Window)

	-- ScreenGui
	self.screenGui = make("ScreenGui", {
		Name            = "KeoirnLite_" .. self.name,
		ResetOnSpawn    = false,
		IgnoreGuiInset  = true,
		ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
		Enabled         = true,
		Parent          = PlayerGui,
	})

	-- Root frame
	self.main = make("Frame", {
		Name            = "Window",
		Size            = UDim2.fromOffset(props.Size and props.Size.X.Offset or 380,
		                                   props.Size and props.Size.Y.Offset or 460),
		Position        = UDim2.fromOffset(props.X or 80, props.Y or 80),
		BackgroundColor3 = PALETTE.Background,
		BorderSizePixel = 0,
		Active          = true,
		Draggable       = true,
	}, self.screenGui)
	corner(10, self.main)
	stroke(PALETTE.Stroke, 1, self.main)

	-- Title bar
	local titleBar = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
	}, self.main)
	corner(10, titleBar)
	-- mask bottom corners
	make("Frame", {
		Size            = UDim2.new(1, 0, 0, 10),
		Position        = UDim2.new(0, 0, 1, -10),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
	}, titleBar)

	make("TextLabel", {
		Text            = self.name,
		TextSize        = 15,
		TextColor3      = PALETTE.Content,
		Font            = Enum.Font.GothamBold,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment  = Enum.TextXAlignment.Left,
		Size            = UDim2.new(1, -80, 1, 0),
		Position        = UDim2.fromOffset(14, 0),
	}, titleBar)

	-- Close / hide buttons
	local closeBtn = button("✕", PALETTE.Error, titleBar)
	closeBtn.Position = UDim2.new(1, -34, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	closeBtn.Size = UDim2.fromOffset(22, 22)
	closeBtn.TextSize = 12

	local hideBtn = button("—", PALETTE.Stroke, titleBar)
	hideBtn.Position = UDim2.new(1, -60, 0.5, 0)
	hideBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	hideBtn.Size = UDim2.fromOffset(22, 22)
	hideBtn.TextSize = 12

	-- Tab bar
	self.tabBar = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 32),
		Position        = UDim2.fromOffset(0, 36),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, self.main)
	pad(6, 6, 4, 4, self.tabBar)
	listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 4, self.tabBar)

	-- Content area
	self.content = make("Frame", {
		Size            = UDim2.new(1, 0, 1, -68),
		Position        = UDim2.fromOffset(0, 68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, self.main)

	-- Notification container
	self.notifications = make("Frame", {
		Size            = UDim2.fromOffset(320, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		AnchorPoint     = Vector2.new(1, 1),
		Position        = UDim2.new(1, -10, 1, -10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex          = 100,
	}, self.screenGui)
	listLayout(nil, Enum.HorizontalAlignment.Right, nil, 6, self.notifications)

	-- Restore frame (shown when hidden)
	self.restoreFrame = make("TextButton", {
		Size            = UDim2.fromOffset(160, 32),
		Position        = UDim2.fromOffset(props.X or 80, props.Y or 80),
		BackgroundColor3 = PALETTE.Background,
		BorderSizePixel = 0,
		Text            = "▶ " .. self.name,
		TextColor3      = PALETTE.Content,
		TextSize        = 13,
		Font            = Enum.Font.GothamMedium,
		AutoButtonColor = false,
		Visible         = false,
		ZIndex          = 50,
	}, self.screenGui)
	corner(8, self.restoreFrame)
	stroke(PALETTE.Stroke, 1, self.restoreFrame)

	-- Wire close / hide
	self._connections:add(closeBtn.MouseButton1Click:Connect(function()
		self:Destroy()
	end))

	self._connections:add(hideBtn.MouseButton1Click:Connect(function()
		self:ToggleHide()
	end))

	self._connections:add(self.restoreFrame.MouseButton1Click:Connect(function()
		self:ToggleHide()
	end))

	-- Toggle keybind
	self._connections:add(UserInputService.InputBegan:Connect(function(inp, gp)
		if gp then return end
		if inp.KeyCode == self.settings.toggleKeybind then
			self:ToggleHide()
		end
	end))

	return self
end

function Window:_selectTab(tab)
	for _, t in self.tabs do t:_setActive(false) end
	tab:_setActive(true)
	self._selectedTab = tab
end

function Window:_persist(element)
	if element and element.flag then
		self._flags[element.flag] = element.value
	end
end

function Window:GetFlag(flag)
	return self._flags[flag]
end

function Window:Show()
	self.screenGui.Enabled = true
	self.hidden = false
	self.main.Visible = true
	self.restoreFrame.Visible = false
end

function Window:ToggleHide()
	self.hidden = not self.hidden
	self.main.Visible = not self.hidden
	self.restoreFrame.Visible = self.hidden
end

function Window:Destroy()
	self.unloaded = true
	self._connections:cleanAll()
	if self.screenGui and self.screenGui.Parent then
		self.screenGui:Destroy()
	end
end

-- Notification (lightweight — no tweens)
function Window:Notify(props)
	props = props or {}
	local frame = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
		LayoutOrder     = #self.notifications:GetChildren(),
	}, self.notifications)
	corner(8, frame)
	stroke(PALETTE.Stroke, 1, frame)
	pad(12, 12, 8, 8, frame)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, frame)
	listLayout(nil, nil, nil, 3, inner)

	if props.title or props.Title then
		label(props.title or props.Title, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)
	end
	if props.content or props.Content then
		label(props.content or props.Content, 13, PALETTE.ContentDim, Enum.TextXAlignment.Left, inner)
	end

	local duration = props.duration or props.Duration or 5
	task.delay(duration, function()
		if frame and frame.Parent then frame:Destroy() end
	end)
end

-- Toast is an alias for Notify in Lite
function Window:Toast(props)  self:Notify(props)  end

-- Popup (simple blocking modal)
function Window:Popup(props)
	props = props or {}
	local opts = props.options or props.Options or {{ text = "Okay" }}

	local gui = make("ScreenGui", {
		Name            = "KeoirnLite_Popup",
		ResetOnSpawn    = false,
		IgnoreGuiInset  = true,
		ZIndexBehavior  = Enum.ZIndexBehavior.Global,
		DisplayOrder    = 100,
		Parent          = PlayerGui,
	})

	-- Backdrop
	make("Frame", {
		Size            = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active          = true,
	}, gui)

	local card = make("Frame", {
		Size            = UDim2.fromOffset(360, 0),
		AutomaticSize   = Enum.AutomaticSize.Y,
		AnchorPoint     = Vector2.new(0.5, 0.5),
		Position        = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = PALETTE.Surface,
		BorderSizePixel = 0,
	}, gui)
	corner(10, card)
	stroke(PALETTE.Stroke, 1, card)
	pad(20, 20, 16, 16, card)
	listLayout(nil, Enum.HorizontalAlignment.Center, nil, 10, card)

	if props.title or props.Title then
		label(props.title or props.Title, 16, PALETTE.Content, Enum.TextXAlignment.Left, card)
	end
	if props.content or props.Content then
		label(props.content or props.Content, 14, PALETTE.ContentDim, Enum.TextXAlignment.Left, card)
	end

	local btnRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, card)
	listLayout(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 8, btnRow)

	for _, opt in opts do
		opt = if type(opt) == "table" then opt else { text = tostring(opt) }
		local style = opt.style or opt.Style or "neutral"
		local color = if style == "primary" then PALETTE.Accent
		              elseif style == "danger" then PALETTE.Error
		              else PALETTE.Panel
		local b2 = button(opt.text or opt.Text or "Okay", color, btnRow)
		b2.MouseButton1Click:Connect(function()
			if opt.callback or opt.Callback then
				pcall(opt.callback or opt.Callback)
			end
			gui:Destroy()
		end)
	end

	return { Close = function() gui:Destroy() end }
end

-- Theme stubs (API compat)
function Window:ChangeTheme(t)  end
function Window:SetTheme(t)     end

-- CreateTab
function Window:CreateTab(props)
	if type(props) == "string" then props = { Name = props } end
	props = props or {}
	local t = Tab.new(self, props)
	table.insert(self.tabs, t)
	if #self.tabs == 1 then self:_selectTab(t) end
	return t
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Library root  (Keoirn public surface)
-- ═══════════════════════════════════════════════════════════════════════════
local Lib = {}
Lib.__index = Lib
Lib._isLite = true   -- sentinel: let your code detect which version is active

function Lib:CreateWindow(props)
	if type(props) == "string" then props = { Title = props } end
	return Window.new(self, props or {})
end

-- ── Auto-switch helper (call this instead of loading either version directly)
-- Returns the real Keoirn lib on good hardware, KeoirnLite on poor hardware.
--
--   local Keoirn = require(path_or_loadstring)
--   local Lib    = Keoirn.AutoLoad({
--       fullUrl  = "https://raw.githubusercontent.com/Zeoirn/keoirn/refs/heads/main/Keoirn.lua",
--       liteUrl  = "YOUR_RAW_KEOIRNLITE_URL",   -- can omit; uses this module
--       threshold = 30,   -- FPS threshold (default 30)
--       sample    = 2,    -- seconds to measure (default 2)
--   })
--
-- If you loadstring this file directly, Lib.AutoLoad is still available so
-- your bootstrap only needs to load KeoirnLite and call AutoLoad from it.
function Lib.AutoLoad(cfg)
	cfg = cfg or {}
	local threshold = cfg.threshold or 30
	local sample    = cfg.sample    or 2
	local fullUrl   = cfg.fullUrl

	-- measure average FPS
	local frames, time_ = 0, 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		frames += 1; time_ += dt
	end)
	task.wait(sample)
	conn:Disconnect()
	local fps = if time_ > 0 then frames / time_ else 60

	if fps >= threshold and fullUrl then
		local ok, result = pcall(function()
			return loadstring(game:HttpGet(fullUrl, true))()
		end)
		if ok and result then return result end
		-- fall through to Lite on any error
	end

	return Lib  -- return this lightweight module
end

return Lib
