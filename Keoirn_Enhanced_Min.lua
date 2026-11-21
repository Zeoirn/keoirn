--[[
    ╔══════════════════════════════════════════════════════╗
    ║           KEOIRN ENHANCED — by zurai02              ║
    ║   Fully standalone, bug-free, high-performance UI    ║
    ╚══════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local function getGuiContainer()
    if gethui then
        local ok, res = pcall(gethui)
        if ok and res then return res end
    end
    local ok, res = pcall(function() return game:GetService("CoreGui") end)
    if ok and res then return res end
    return LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")
end

local PALETTE = {
    Background = Color3.fromRGB(18, 18, 22),
    Surface    = Color3.fromRGB(26, 26, 32),
    Panel      = Color3.fromRGB(32, 32, 40),
    Stroke     = Color3.fromRGB(55, 55, 70),
    Content    = Color3.fromRGB(220, 220, 230),
    ContentDim = Color3.fromRGB(140, 140, 160),
    Accent     = Color3.fromRGB(100, 149, 237),
    AccentDim  = Color3.fromRGB(70, 110, 200),
    Success    = Color3.fromRGB(60, 180, 100),
    Warning    = Color3.fromRGB(220, 160, 50),
    Error      = Color3.fromRGB(220, 70, 70),
    White      = Color3.fromRGB(255, 255, 255),
    Black      = Color3.fromRGB(0, 0, 0),
}

local TWEEN = {
    open  = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
    fast  = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
    hover = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

local function make(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        inst[k] = v
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(r, parent)
    return make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function pad(l, r, t, b, parent)
    return make("UIPadding", {
        PaddingLeft   = UDim.new(0, l),
        PaddingRight  = UDim.new(0, r),
        PaddingTop    = UDim.new(0, t),
        PaddingBottom = UDim.new(0, b),
    }, parent)
end

local function listLayout(dir, halign, valign, spacing, parent)
    return make("UIListLayout", {
        FillDirection        = dir or Enum.FillDirection.Vertical,
        HorizontalAlignment  = halign or Enum.HorizontalAlignment.Left,
        VerticalAlignment    = valign or Enum.VerticalAlignment.Top,
        SortOrder            = Enum.SortOrder.LayoutOrder,
        Padding              = UDim.new(0, spacing or 4),
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
        Text             = tostring(text),
        TextSize         = 13,
        TextColor3       = PALETTE.White,
        Font             = Enum.Font.GothamMedium,
        BackgroundColor3 = color or PALETTE.Accent,
        BorderSizePixel  = 0,
        AutomaticSize    = Enum.AutomaticSize.XY,
        AutoButtonColor  = false,
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

local function newConnPool()
    local pool = {}
    pool._list = {}
    function pool:add(conn)
        table.insert(self._list, conn)
        return conn
    end
    function pool:cleanAll()
        for _, c in ipairs(self._list) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(self._list)
    end
    return pool
end

local function parseColorInput(str)
    if typeof(str) ~= "string" then return nil end
    str = str:lower():match("^%s*(.-)%s*$") or ""
    if str == "" then return nil end
    local named = {
        black   = Color3.fromRGB(0, 0, 0),
        white   = Color3.fromRGB(255, 255, 255),
        red     = Color3.fromRGB(255, 0, 0),
        green   = Color3.fromRGB(0, 255, 0),
        blue    = Color3.fromRGB(0, 0, 255),
        yellow  = Color3.fromRGB(255, 255, 0),
        cyan    = Color3.fromRGB(0, 255, 255),
        magenta = Color3.fromRGB(255, 0, 255),
        orange  = Color3.fromRGB(255, 165, 0),
        purple  = Color3.fromRGB(128, 0, 128),
        pink    = Color3.fromRGB(255, 105, 180),
        gold    = Color3.fromRGB(255, 215, 0),
        grey    = Color3.fromRGB(128, 128, 128),
        gray    = Color3.fromRGB(128, 128, 128),
    }
    if named[str] then return named[str] end
    local hx = str:match("^#?([%da-f]+)$")
    if hx then
        if #hx == 3 then
            hx = hx:sub(1,1):rep(2) .. hx:sub(2,2):rep(2) .. hx:sub(3,3):rep(2)
        end
        if #hx == 6 then
            local ok, c = pcall(Color3.fromHex, hx)
            if ok and c then return c end
        end
    end
    local r, g, b = str:match("rgba?%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if r and g and b then
        return Color3.fromRGB(math.clamp(tonumber(r) or 0, 0, 255), math.clamp(tonumber(g) or 0, 0, 255), math.clamp(tonumber(b) or 0, 0, 255))
    end
    local h, s, v = str:match("hsv%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if h and s and v then
        return Color3.fromHSV((tonumber(h) or 0)/360, math.clamp((tonumber(s) or 0)/100, 0, 1), math.clamp((tonumber(v) or 0)/100, 0, 1))
    end
    return nil
end

-- ====================================================================
-- BUTTON COMPONENT
-- ====================================================================
local Button = {}
Button.__index = Button
Button.__type  = "Button"

function Button.new(tab, props)
    props = props or {}
    local self = setmetatable({
        tab         = tab,
        window      = tab.window,
        name        = props.name or props.Name or "Button",
        icon        = props.icon or props.Icon,
        callback    = props.callback or props.Callback or function() end,
        disabled    = props.disabled or props.Disabled or false,
        cooldown    = props.cooldown or props.Cooldown or 0,
        _onCooldown = false,
        _shown      = true,
        _pool       = newConnPool(),
    }, Button)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    self.stroke = stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)

    if self.icon then
        self.iconLabel = make("ImageLabel", {
            Image                  = self.icon,
            Size                   = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            ImageColor3            = PALETTE.Content,
        }, inner)
    end

    self.titleLabel = label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    local interact = make("TextButton", {
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Text                   = "",
        ZIndex                 = 5,
    }, self.main)

    self._pool:add(interact.MouseButton1Click:Connect(function()
        if self.disabled or self._onCooldown then return end
        if self.cooldown > 0 then
            self._onCooldown = true
            self:SetDisabled(true)
            task.delay(self.cooldown, function()
                self._onCooldown = false
                self:SetDisabled(false)
            end)
        end
        TweenService:Create(self.main, TweenInfo.new(0.08), { BackgroundColor3 = PALETTE.Panel }):Play()
        task.delay(0.1, function()
            if self.main and self.main.Parent then
                TweenService:Create(self.main, TweenInfo.new(0.15), { BackgroundColor3 = PALETTE.Surface }):Play()
            end
        end)
        pcall(self.callback)
    end))

    if self.disabled then
        self:SetDisabled(true)
    end

    return self
end

function Button:SetDisabled(state)
    self.disabled = state
    if self.main then
        self.main.BackgroundTransparency = state and 0.5 or 0
    end
    if self.titleLabel then
        self.titleLabel.TextTransparency = state and 0.6 or 0
    end
    if self.iconLabel then
        self.iconLabel.ImageTransparency = state and 0.6 or 0
    end
end

function Button:Set(cb)
    if type(cb) == "function" then self.callback = cb end
end

function Button:_setShown(shown)
    self.main.Visible = shown
    self._shown = shown
end

function Button:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- TOGGLE COMPONENT
-- ====================================================================
local Toggle = {}
Toggle.__index = Toggle
Toggle.__type  = "Toggle"

function Toggle.new(tab, props)
    props = props or {}
    local defVal = props.value
    if defVal == nil then defVal = props.Value end
    if defVal == nil then defVal = props.default end
    if defVal == nil then defVal = props.Default end
    if defVal == nil then defVal = false end

    local self = setmetatable({
        tab      = tab,
        window   = tab.window,
        name     = props.name or props.Name or "Toggle",
        value    = defVal == true,
        callback = props.callback or props.Callback or function() end,
        flag     = props.flag or props.Flag,
        _pool    = newConnPool(),
    }, Toggle)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    self.pill = make("Frame", {
        Size             = UDim2.fromOffset(36, 20),
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, 0, 0.5, 0),
        BackgroundColor3 = self.value and PALETTE.Accent or PALETTE.Panel,
        BorderSizePixel  = 0,
    }, self.main)
    corner(10, self.pill)

    self.knob = make("Frame", {
        Size             = UDim2.fromOffset(14, 14),
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = self.value and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        BackgroundColor3 = PALETTE.White,
        BorderSizePixel  = 0,
    }, self.pill)
    corner(7, self.knob)

    local interact = make("TextButton", {
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Text                   = "",
        ZIndex                 = 5,
    }, self.main)

    self._pool:add(interact.MouseButton1Click:Connect(function()
        self:Set(not self.value)
    end))

    if self.flag then
        self.window:_persist(self)
    end

    return self
end

function Toggle:_render()
    local targetPos = self.value and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
    local targetCol = self.value and PALETTE.Accent or PALETTE.Panel
    TweenService:Create(self.knob, TWEEN.fast, { Position = targetPos }):Play()
    TweenService:Create(self.pill, TWEEN.fast, { BackgroundColor3 = targetCol }):Play()
end

function Toggle:Set(v, silent)
    self.value = v == true
    self:_render()
    if not silent then
        pcall(self.callback, self.value)
        self.window:_persist(self)
    end
end

function Toggle:_setShown(shown)
    self.main.Visible = shown
end

function Toggle:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- SLIDER COMPONENT
-- ====================================================================
local Slider = {}
Slider.__index = Slider
Slider.__type  = "Slider"

function Slider.new(tab, props)
    props = props or {}
    local r1 = props.min or props.Min or (props.range and props.range[1]) or (props.Range and props.Range[1]) or 0
    local r2 = props.max or props.Max or (props.range and props.range[2]) or (props.Range and props.Range[2]) or 100
    local defVal = props.value or props.Value or props.default or props.Default or r1

    local self = setmetatable({
        tab      = tab,
        window   = tab.window,
        name     = props.name or props.Name or "Slider",
        min      = r1,
        max      = r2,
        value    = math.clamp(defVal, r1, r2),
        callback = props.callback or props.Callback or function() end,
        flag     = props.flag or props.Flag,
        _drag    = false,
        _pool    = newConnPool(),
    }, Slider)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)

    local header = make("Frame", {
        Size                   = UDim2.new(1, -24, 0, 20),
        Position               = UDim2.fromOffset(12, 8),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, header)

    self.valLbl = make("TextLabel", {
        Text                = tostring(self.value),
        TextSize            = 13,
        TextColor3          = PALETTE.ContentDim,
        Font                = Enum.Font.GothamMedium,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Right,
        Size                = UDim2.new(1, 0, 1, 0),
    }, header)

    self.track = make("Frame", {
        Size             = UDim2.new(1, -24, 0, 6),
        Position         = UDim2.new(0, 12, 0, 36),
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
    }, self.main)
    corner(3, self.track)

    local ratio = ((self.max - self.min) <= 0) and (1) or ((self.value - self.min) / (self.max - self.min))
    self.fill = make("Frame", {
        Size             = UDim2.new(ratio, 0, 1, 0),
        BackgroundColor3 = PALETTE.Accent,
        BorderSizePixel  = 0,
    }, self.track)
    corner(3, self.fill)

    local interact = make("TextButton", {
        Size                   = UDim2.new(1, 0, 1, 20),
        Position               = UDim2.new(0, 0, 0, -10),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Text                   = "",
        ZIndex                 = 5,
    }, self.track)

    local function fromMouse()
        local mx = UserInputService:GetMouseLocation().X
        local abs = self.track.AbsolutePosition.X
        local w = self.track.AbsoluteSize.X
        local r = math.clamp((mx - abs) / math.max(w, 1), 0, 1)
        local raw = self.min + r * (self.max - self.min)
        if props.integer or props.Integer or true then
            raw = math.round(raw)
        end
        return math.clamp(raw, self.min, self.max)
    end

    self._pool:add(interact.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            self._drag = true
            self:Set(fromMouse())
        end
    end))

    self._pool:add(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            self._drag = false
        end
    end))

    self._pool:add(UserInputService.InputChanged:Connect(function(i)
        if self._drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            self:Set(fromMouse())
        end
    end))

    if self.flag then
        self.window:_persist(self)
    end

    return self
end

function Slider:Set(v, silent)
    self.value = math.clamp(tonumber(v) or self.min, self.min, self.max)
    local range = self.max - self.min
    local ratio = (range <= 0) and (1) or ((self.value - self.min) / range)
    self.fill.Size = UDim2.new(ratio, 0, 1, 0)
    self.valLbl.Text = tostring(self.value)
    if not silent then
        pcall(self.callback, self.value)
        self.window:_persist(self)
    end
end

function Slider:_setShown(shown)
    self.main.Visible = shown
end

function Slider:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- DROPDOWN COMPONENT
-- ====================================================================
local Dropdown = {}
Dropdown.__index = Dropdown
Dropdown.__type  = "Dropdown"

function Dropdown.new(tab, props)
    props = props or {}
    local rawOpts = props.options or props.Options or {}
    local opts = {}
    for _, v in ipairs(rawOpts) do
        table.insert(opts, tostring(v))
    end

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

    local seed = props.value or props.Value or props.default or props.Default or props.currentOption or props.CurrentOption
    if type(seed) == "string" then
        seed = { seed }
    elseif type(seed) ~= "table" then
        seed = {}
    end
    for _, s in ipairs(seed) do
        if table.find(self.options, s) then
            table.insert(self.value, s)
        end
    end
    if not multi and #self.value == 0 and #self.options > 0 then
        table.insert(self.value, self.options[1])
    end

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 36),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)

    local header = make("TextButton", {
        Size                   = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Text                   = "",
        AutoButtonColor        = false,
    }, self.main)
    pad(12, 12, 0, 0, header)

    local hinner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, header)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, hinner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, hinner)

    self.displayLbl = make("TextLabel", {
        Text                = self:_displayText(),
        TextSize            = 13,
        TextColor3          = PALETTE.ContentDim,
        Font                = Enum.Font.GothamMedium,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Right,
        Size                = UDim2.new(1, -24, 1, 0),
    }, header)

    self.arrowLbl = make("TextLabel", {
        Text                = "▼",
        TextSize            = 10,
        TextColor3          = PALETTE.ContentDim,
        Font                = Enum.Font.GothamBold,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        AnchorPoint         = Vector2.new(1, 0.5),
        Position            = UDim2.new(1, 0, 0.5, 0),
        Size                = UDim2.fromOffset(16, 16),
    }, header)

    self.optContainer = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        Position               = UDim2.fromOffset(0, 36),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Visible                = false,
    }, self.main)
    pad(6, 6, 4, 6, self.optContainer)
    listLayout(nil, nil, nil, 3, self.optContainer)

    self:_buildOpt()

    self._pool:add(header.MouseButton1Click:Connect(function()
        if self._open then self:_close() else self:_openDrop() end
    end))

    if self.flag then
        self.window:_persist(self)
    end

    return self
end

function Dropdown:_displayText()
    if #self.value == 0 then
        return "None"
    elseif #self.value == 1 then
        return self.value[1]
    else
        return self.value[1] .. " (+" .. (#self.value - 1) .. ")"
    end
end

function Dropdown:_buildOpt()
    for _, f in pairs(self._optFrames) do f:Destroy() end
    table.clear(self._optFrames)

    for _, opt in ipairs(self.options) do
        local isSel = table.find(self.value, opt) ~= nil
        local row = make("TextButton", {
            Size             = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = isSel and PALETTE.Panel or PALETTE.Surface,
            BorderSizePixel  = 0,
            Text             = "  " .. opt,
            TextSize         = 13,
            TextColor3       = isSel and PALETTE.Accent or PALETTE.Content,
            Font             = Enum.Font.GothamMedium,
            TextXAlignment   = Enum.TextXAlignment.Left,
            AutoButtonColor  = false,
        }, self.optContainer)
        corner(4, row)

        self._pool:add(row.MouseButton1Click:Connect(function()
            if self.multiSelect then
                local idx = table.find(self.value, opt)
                if idx then table.remove(self.value, idx) else table.insert(self.value, opt) end
            else
                self.value = { opt }
                self:_close()
            end
            self.displayLbl.Text = self:_displayText()
            self:_refreshOptColors()
            pcall(self.callback, self:_callbackValue())
            self.window:_persist(self)
        end))

        table.insert(self._optFrames, row)
    end
end

function Dropdown:_refreshOptColors()
    for i, opt in ipairs(self.options) do
        local row = self._optFrames[i]
        if row then
            local isSel = table.find(self.value, opt) ~= nil
            row.BackgroundColor3 = isSel and PALETTE.Panel or PALETTE.Surface
            row.TextColor3 = isSel and PALETTE.Accent or PALETTE.Content
        end
    end
end

function Dropdown:_callbackValue()
    if self.multiSelect then return self.value end
    return self.value[1] or ""
end

function Dropdown:_openDrop()
    self._open = true
    self.optContainer.Visible = true
    self.arrowLbl.Text = "▲"
end

function Dropdown:_close()
    self._open = false
    self.optContainer.Visible = false
    self.arrowLbl.Text = "▼"
end

function Dropdown:Set(val, silent)
    if type(val) == "string" then val = { val } elseif type(val) ~= "table" then val = {} end
    self.value = val
    self.displayLbl.Text = self:_displayText()
    self:_refreshOptColors()
    if not silent then
        pcall(self.callback, self:_callbackValue())
        self.window:_persist(self)
    end
end

function Dropdown:Refresh(newOpts)
    self.options = newOpts or {}
    self.value = {}
    self.displayLbl.Text = self:_displayText()
    self:_buildOpt()
end

function Dropdown:_setShown(shown)
    self.main.Visible = shown
end

function Dropdown:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- INPUT COMPONENT
-- ====================================================================
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
        placeholder = props.placeholder or props.Placeholder or props.PlaceHolder or "Type here...",
        callback    = props.callback or props.Callback or function() end,
        flag        = props.flag or props.Flag,
        _pool       = newConnPool(),
    }, Input)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    self.box = make("TextBox", {
        Text                = self.value,
        PlaceholderText     = self.placeholder,
        TextSize            = 13,
        TextColor3          = PALETTE.Content,
        PlaceholderColor3   = PALETTE.ContentDim,
        Font                = Enum.Font.GothamMedium,
        BackgroundColor3    = PALETTE.Panel,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Left,
        Size                = UDim2.new(0, 140, 0, 26),
        AnchorPoint         = Vector2.new(1, 0.5),
        Position            = UDim2.new(1, 0, 0.5, 0),
        ClearTextOnFocus    = false,
    }, self.main)
    corner(5, self.box)
    stroke(PALETTE.Stroke, 1, self.box)
    pad(6, 6, 0, 0, self.box)

    self._pool:add(self.box.FocusLost:Connect(function()
        self.value = self.box.Text
        pcall(self.callback, self.value)
        self.window:_persist(self)
    end))

    if self.flag then
        self.window:_persist(self)
    end

    return self
end

function Input:Set(text, silent)
    self.value = tostring(text)
    self.box.Text = self.value
    if not silent then
        pcall(self.callback, self.value)
        self.window:_persist(self)
    end
end

function Input:_setShown(shown)
    self.main.Visible = shown
end

function Input:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- KEYBIND COMPONENT
-- ====================================================================
local Keybind = {}
Keybind.__index = Keybind
Keybind.__type  = "Keybind"

local function keyName(key)
    if typeof(key) == "EnumItem" then return key.Name end
    return tostring(key or "None")
end

function Keybind.new(tab, props)
    props = props or {}
    local defKey = props.value or props.Value or props.default or props.Default or Enum.KeyCode.RightShift
    local self = setmetatable({
        tab       = tab,
        window    = tab.window,
        name      = props.name or props.Name or "Keybind",
        value     = defKey,
        callback  = props.callback or props.Callback or function() end,
        flag      = props.flag or props.Flag,
        recording = false,
        _pool     = newConnPool(),
    }, Keybind)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    self.btn = make("TextButton", {
        Text             = keyName(self.value),
        TextSize         = 12,
        TextColor3       = PALETTE.Content,
        Font             = Enum.Font.GothamBold,
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.fromOffset(80, 24),
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, 0, 0.5, 0),
        AutoButtonColor  = false,
    }, self.main)
    corner(5, self.btn)
    stroke(PALETTE.Stroke, 1, self.btn)

    self._pool:add(self.btn.MouseButton1Click:Connect(function()
        self.recording = true
        self.btn.Text = "..."
        self.btn.TextColor3 = PALETTE.Accent
    end))

    self._pool:add(UserInputService.InputBegan:Connect(function(inp, gp)
        if self.recording and inp.UserInputType == Enum.UserInputType.Keyboard then
            self.recording = false
            self.value = inp.KeyCode
            self.btn.Text = keyName(inp.KeyCode)
            self.btn.TextColor3 = PALETTE.Content
            self.window:_persist(self)
        elseif not gp and inp.KeyCode == self.value then
            pcall(self.callback)
        end
    end))

    if self.flag then
        self.window:_persist(self)
    end

    return self
end

function Keybind:Set(key)
    self.value = key
    self.btn.Text = keyName(key)
    self.window:_persist(self)
end

function Keybind:_setShown(shown)
    self.main.Visible = shown
end

function Keybind:Remove()
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- COLOR PICKER COMPONENT (ENHANCED)
-- ====================================================================
local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__type  = "ColorPicker"

function ColorPicker.new(tab, props)
    props = props or {}
    local defColor = props.color or props.Color or props.value or props.Value or props.default or props.Default or Color3.fromRGB(255, 255, 255)
    if type(defColor) == "string" then
        defColor = parseColorInput(defColor) or Color3.fromRGB(255, 255, 255)
    end

    local swatches = props.swatches or props.Swatches
    local hasSwatches = type(swatches) == "table" and #swatches > 0

    local self = setmetatable({
        tab         = tab,
        window      = tab.window,
        name        = props.name or props.Name or "Color",
        value       = defColor,
        alpha       = props.alpha or props.Alpha or 1,
        callback    = props.callback or props.Callback or function() end,
        onOpen      = props.onOpen or props.OnOpen,
        onClose     = props.onClose or props.OnClose,
        flag        = props.flag or props.Flag,
        swatches    = swatches,
        _pool       = newConnPool(),
    }, ColorPicker)

    local mainHeight = hasSwatches and 72 or 42
    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, mainHeight),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local topRow = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, -160, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, topRow)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 8, inner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    self.hexInput = make("TextBox", {
        Text                = "#" .. self.value:ToHex():upper(),
        PlaceholderText     = "#HEX",
        TextSize            = 12,
        TextColor3          = PALETTE.Content,
        PlaceholderColor3   = PALETTE.ContentDim,
        Font                = Enum.Font.Code,
        BackgroundColor3    = PALETTE.Panel,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Center,
        Size                = UDim2.fromOffset(70, 24),
        AnchorPoint         = Vector2.new(1, 0.5),
        Position            = UDim2.new(1, 0, 0.5, 0),
        ClearTextOnFocus    = false,
    }, topRow)
    corner(5, self.hexInput)
    stroke(PALETTE.Stroke, 1, self.hexInput)

    local copyBtn = make("TextButton", {
        Text             = "⎘",
        Size             = UDim2.fromOffset(24, 24),
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -76, 0.5, 0),
        BackgroundColor3 = PALETTE.Panel,
        TextColor3       = PALETTE.Content,
        TextSize         = 13,
        Font             = Enum.Font.GothamMedium,
        BorderSizePixel  = 0,
        AutoButtonColor  = false,
    }, topRow)
    corner(5, copyBtn)
    stroke(PALETTE.Stroke, 1, copyBtn)

    self.swatch = make("Frame", {
        Size             = UDim2.fromOffset(24, 24),
        BackgroundColor3 = self.value,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -106, 0.5, 0),
    }, topRow)
    corner(5, self.swatch)
    stroke(PALETTE.Stroke, 1, self.swatch)

    self._pool:add(copyBtn.MouseButton1Click:Connect(function()
        local hex = "#" .. self.value:ToHex():upper()
        if setclipboard then
            pcall(setclipboard, hex)
        end
        copyBtn.Text = "✓"
        task.delay(1.2, function()
            if copyBtn and copyBtn.Parent then
                copyBtn.Text = "⎘"
            end
        end)
    end))

    self._pool:add(self.hexInput.FocusLost:Connect(function()
        local parsed = parseColorInput(self.hexInput.Text)
        if parsed then
            self:Set(parsed)
        else
            self.hexInput.Text = "#" .. self.value:ToHex():upper()
        end
    end))

    -- Swatches row
    if hasSwatches then
        self.swatchRow = make("Frame", {
            Name                   = "Swatches",
            Size                   = UDim2.new(1, 0, 0, 24),
            Position               = UDim2.new(0, 0, 0, 42),
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
        }, self.main)
        listLayout(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center, 6, self.swatchRow)

        for _, col in ipairs(swatches) do
            local swBtn = make("TextButton", {
                Size             = UDim2.fromOffset(20, 20),
                BackgroundColor3 = col,
                BorderSizePixel  = 0,
                Text             = "",
                AutoButtonColor  = false,
            }, self.swatchRow)
            corner(4, swBtn)
            stroke(PALETTE.Stroke, 1, swBtn)

            local c = col
            self._pool:add(swBtn.MouseButton1Click:Connect(function()
                self:Set(c)
            end))
        end
    end

    if self.onOpen then
        pcall(self.onOpen, self.value, self.alpha)
    end

    if self.flag then
        self.window:_persist(self)
    end

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

function ColorPicker:_setShown(shown)
    self.main.Visible = shown
end

function ColorPicker:Remove()
    if self.onClose then
        pcall(self.onClose, self.value, self.alpha)
    end
    self._pool:cleanAll()
    self.main:Destroy()
end

-- ====================================================================
-- STAT COMPONENT
-- ====================================================================
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
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(12, 12, 0, 0, self.main)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.main)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, inner)
    label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)

    self.valLbl = make("TextLabel", {
        Text                = self.value,
        TextSize            = 13,
        TextColor3          = PALETTE.Accent,
        Font                = Enum.Font.GothamBold,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Right,
        Size                = UDim2.new(1, 0, 1, 0),
    }, self.main)

    return self
end

function Stat:Set(v)
    self.value = tostring(v)
    self.valLbl.Text = self.value
end

function Stat:_setShown(shown)
    self.main.Visible = shown
end

function Stat:Remove()
    self.main:Destroy()
end

-- ====================================================================
-- PROGRESS COMPONENT
-- ====================================================================
local Progress = {}
Progress.__index = Progress
Progress.__type  = "Progress"

function Progress.new(tab, props)
    props = props or {}
    local range = props.range or props.Range
    local r1 = props.min or props.Min or (range and range[1]) or 0
    local r2 = props.max or props.Max or (range and range[2]) or 100
    local defVal = props.value or props.Value or props.default or props.Default or r1

    local self = setmetatable({
        tab    = tab,
        window = tab.window,
        name   = props.name or props.Name or "Progress",
        min    = r1,
        max    = r2,
        value  = math.clamp(defVal, r1, r2),
    }, Progress)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)

    local lbl = label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, self.main)
    lbl.Position = UDim2.fromOffset(12, 10)

    self.pctLbl = make("TextLabel", {
        Text                = tostring(self.value) .. " / " .. tostring(self.max),
        TextSize            = 12,
        TextColor3          = PALETTE.ContentDim,
        Font                = Enum.Font.GothamMedium,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Right,
        AnchorPoint         = Vector2.new(1, 0),
        Position            = UDim2.new(1, -12, 0, 10),
        Size                = UDim2.fromOffset(100, 16),
    }, self.main)

    self.track = make("Frame", {
        Size             = UDim2.new(1, -24, 0, 6),
        Position         = UDim2.new(0, 12, 0, 32),
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
    }, self.main)
    corner(3, self.track)

    local ratio = ((self.max - self.min) <= 0) and (1) or ((self.value - self.min) / (self.max - self.min))
    self.fill = make("Frame", {
        Size             = UDim2.new(ratio, 0, 1, 0),
        BackgroundColor3 = PALETTE.Accent,
        BorderSizePixel  = 0,
    }, self.track)
    corner(3, self.fill)

    return self
end

function Progress:Set(v)
    self.value = math.clamp(tonumber(v) or self.min, self.min, self.max)
    local range = self.max - self.min
    local ratio = (range <= 0) and (1) or ((self.value - self.min) / range)
    self.fill.Size = UDim2.new(ratio, 0, 1, 0)
    self.pctLbl.Text = tostring(self.value) .. " / " .. tostring(self.max)
end

function Progress:_setShown(shown)
    self.main.Visible = shown
end

function Progress:Remove()
    self.main:Destroy()
end

-- ====================================================================
-- CONSOLE COMPONENT
-- ====================================================================
local Console = {}
Console.__index = Console
Console.__type  = "Console"

function Console.new(tab, props)
    props = props or {}
    local self = setmetatable({
        tab      = tab,
        window   = tab.window,
        name     = props.name or props.Name or "Log",
        height   = math.max(tonumber(props.height or props.Height) or 120, 60),
        maxLines = math.max(tonumber(props.maxLines or props.MaxLines) or 200, 1),
        follow   = props.follow or props.Follow or true,
        lines    = {},
    }, Console)

    self.main = make("Frame", {
        Name             = self.name,
        Size             = UDim2.new(1, 0, 0, self.height + 36),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(6, self.main)
    stroke(PALETTE.Stroke, 1, self.main)

    local h = label(self.name, 14, PALETTE.Content, Enum.TextXAlignment.Left, self.main)
    h.Position = UDim2.fromOffset(12, 8)

    local panel = make("Frame", {
        Size             = UDim2.new(1, -16, 0, self.height),
        Position         = UDim2.new(0, 8, 1, -(self.height + 8)),
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
        ClipsDescendants = true,
    }, self.main)
    corner(5, panel)

    self.scroll = make("ScrollingFrame", {
        Size                    = UDim2.new(1, -10, 1, -10),
        Position                = UDim2.fromOffset(5, 5),
        BackgroundTransparency  = 1,
        BorderSizePixel         = 0,
        AutomaticCanvasSize     = Enum.AutomaticSize.Y,
        CanvasSize              = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness      = 3,
        ScrollingDirection      = Enum.ScrollingDirection.Y,
    }, panel)
    listLayout(nil, nil, nil, 2, self.scroll)

    return self
end

function Console:_makeLabel(text, color)
    return make("TextLabel", {
        Text                = tostring(text),
        TextSize            = 12,
        TextColor3          = color or PALETTE.Content,
        Font                = Enum.Font.Code,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        TextXAlignment      = Enum.TextXAlignment.Left,
        TextWrapped         = true,
        AutomaticSize       = Enum.AutomaticSize.Y,
        Size                = UDim2.new(1, 0, 0, 0),
    }, self.scroll)
end

function Console:_trim()
    while #self.lines > self.maxLines do
        table.remove(self.lines, 1)
    end
end

function Console:Append(text, color)
    table.insert(self.lines, text)
    self:_trim()
    self:_makeLabel(text, color)
    if self.follow then
        task.defer(function()
            if self.scroll and self.scroll.Parent then
                self.scroll.CanvasPosition = Vector2.new(0, self.scroll.AbsoluteCanvasSize.Y)
            end
        end)
    end
end

function Console:Log(text)
    self:Append(text, PALETTE.Content)
end

function Console:Warn(text)
    self:Append("[WARN] " .. tostring(text), PALETTE.Warning)
end

function Console:Error(text)
    self:Append("[ERROR] " .. tostring(text), PALETTE.Error)
end

function Console:Clear()
    table.clear(self.lines)
    for _, c in ipairs(self.scroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
end

function Console:Get()
    return table.concat(self.lines, "\n")
end

function Console:_setShown(shown)
    self.main.Visible = shown
end

function Console:Remove()
    self.main:Destroy()
end

-- ====================================================================
-- TEXT COMPONENT
-- ====================================================================
local Text = {}
Text.__index = Text
Text.__type  = "Text"

function Text.new(tab, props)
    props = props or {}
    local self = setmetatable({ tab = tab, window = tab.window }, Text)
    self.main = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        LayoutOrder            = 0,
    }, tab.tabPage)
    pad(8, 8, 4, 4, self.main)
    self.lbl = label(props.name or props.Name or props.text or props.Text or "", props.textSize or props.TextSize or 13, PALETTE.ContentDim, Enum.TextXAlignment.Left, self.main)
    return self
end

function Text:Set(t)
    self.lbl.Text = tostring(t)
end

function Text:_setShown(shown)
    self.main.Visible = shown
end

function Text:Remove()
    self.main:Destroy()
end

-- ====================================================================
-- DIVIDER COMPONENT
-- ====================================================================
local Divider = {}
Divider.__index = Divider
Divider.__type  = "Divider"

function Divider.new(tab, props)
    props = props or {}
    local self = setmetatable({ tab = tab, window = tab.window }, Divider)
    self.main = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 10),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        LayoutOrder            = 0,
    }, tab.tabPage)
    local line = make("Frame", {
        Size             = UDim2.new(1, -16, 0, 1),
        Position         = UDim2.new(0, 8, 0.5, 0),
        BackgroundColor3 = PALETTE.Stroke,
        BorderSizePixel  = 0,
    }, self.main)
    return self
end

function Divider:_setShown(shown)
    self.main.Visible = shown
end

function Divider:Remove()
    self.main:Destroy()
end

-- ====================================================================
-- SECTION COMPONENT
-- ====================================================================
local Section = {}
Section.__index = Section
Section.__type  = "Section"

function Section.new(tab, props)
    props = props or {}
    local self = setmetatable({
        tab      = tab,
        window   = tab.window,
        elements = {},
    }, Section)

    self.main = make("Frame", {
        Name             = props.name or props.Name or "Section",
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
        LayoutOrder      = 0,
    }, tab.tabPage)
    corner(8, self.main)
    stroke(PALETTE.Stroke, 1, self.main)
    pad(8, 8, 8, 8, self.main)
    listLayout(nil, nil, nil, 6, self.main)

    if props.name or props.Name then
        make("TextLabel", {
            Text                = props.name or props.Name,
            TextSize            = 12,
            TextColor3          = PALETTE.ContentDim,
            Font                = Enum.Font.GothamBold,
            BackgroundTransparency = 1,
            BorderSizePixel     = 0,
            TextXAlignment      = Enum.TextXAlignment.Left,
            Size                = UDim2.new(1, 0, 0, 16),
            LayoutOrder         = 0,
        }, self.main)
    end

    self.tabPage = self.main
    return self
end

function Section:CreateButton(p)      return Button.new(self, p) end
function Section:CreateToggle(p)      return Toggle.new(self, p) end
function Section:CreateSlider(p)      return Slider.new(self, p) end
function Section:CreateDropdown(p)    return Dropdown.new(self, p) end
function Section:CreateInput(p)       return Input.new(self, p) end
function Section:CreateKeybind(p)     return Keybind.new(self, p) end
function Section:CreateColorPicker(p) return ColorPicker.new(self, p) end
function Section:CreateStat(p)        return Stat.new(self, p) end
function Section:CreateProgress(p)    return Progress.new(self, p) end
function Section:CreateConsole(p)     return Console.new(self, p) end
function Section:CreateText(p)        return Text.new(self, p) end
function Section:CreateDivider(p)     return Divider.new(self, p) end
function Section:_setShown(s)         self.main.Visible = s end
function Section:Remove()             self.main:Destroy() end

-- ====================================================================
-- TAB COMPONENT
-- ====================================================================
local Tab = {}
Tab.__index = Tab
Tab.__type  = "Tab"

function Tab.new(win, props)
    props = props or {}
    local self = setmetatable({
        window   = win,
        name     = props.name or props.Name or "Tab",
        icon     = props.icon or props.Icon,
        elements = {},
        _pool    = newConnPool(),
    }, Tab)

    self.tabBtn = make("TextButton", {
        Name             = self.name,
        Size             = UDim2.fromOffset(0, 26),
        AutomaticSize    = Enum.AutomaticSize.X,
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel  = 0,
        Text             = "",
        AutoButtonColor  = false,
    }, win.tabBar)
    corner(5, self.tabBtn)
    pad(10, 10, 0, 0, self.tabBtn)

    local btnInner = make("Frame", {
        Size                   = UDim2.new(0, 0, 1, 0),
        AutomaticSize          = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, self.tabBtn)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, btnInner)

    if self.icon then
        self.tabIcon = make("ImageLabel", {
            Image                  = self.icon,
            Size                   = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            ImageColor3            = PALETTE.ContentDim,
        }, btnInner)
    end

    self.tabLabel = make("TextLabel", {
        Text                = self.name,
        TextSize            = 12,
        TextColor3          = PALETTE.ContentDim,
        Font                = Enum.Font.GothamMedium,
        BackgroundTransparency = 1,
        BorderSizePixel     = 0,
        AutomaticSize       = Enum.AutomaticSize.X,
        Size                = UDim2.new(0, 0, 1, 0),
    }, btnInner)

    self.tabPage = make("ScrollingFrame", {
        Name                   = self.name .. "_Page",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness     = 3,
        ScrollBarImageColor3   = PALETTE.Stroke,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
        Visible                = false,
    }, win.content)
    pad(10, 10, 8, 8, self.tabPage)
    listLayout(nil, nil, nil, 6, self.tabPage)

    self._pool:add(self.tabBtn.MouseButton1Click:Connect(function()
        win:_selectTab(self)
    end))

    return self
end

function Tab:_setActive(active)
    self.tabPage.Visible = active
    self.tabBtn.BackgroundColor3 = active and PALETTE.Accent or PALETTE.Panel
    self.tabLabel.TextColor3 = active and PALETTE.White or PALETTE.ContentDim
    if self.tabIcon then
        self.tabIcon.ImageColor3 = active and PALETTE.White or PALETTE.ContentDim
    end
end

function Tab:CreateButton(p)      return Button.new(self, p) end
function Tab:CreateToggle(p)      return Toggle.new(self, p) end
function Tab:CreateSwitch(p)      return self:CreateToggle(p) end
function Tab:CreateSlider(p)      return Slider.new(self, p) end
function Tab:CreateDropdown(p)    return Dropdown.new(self, p) end
function Tab:CreateInput(p)       return Input.new(self, p) end
function Tab:CreateKeybind(p)     return Keybind.new(self, p) end
function Tab:CreateColorPicker(p) return ColorPicker.new(self, p) end
function Tab:CreateStat(p)        return Stat.new(self, p) end
function Tab:CreateProgress(p)    return Progress.new(self, p) end
function Tab:CreateConsole(p)     return Console.new(self, p) end
function Tab:CreateText(p)        return Text.new(self, p) end
function Tab:CreateDivider(p)     return Divider.new(self, p) end
function Tab:CreateSection(p)     return Section.new(self, p) end

-- ====================================================================
-- WINDOW CLASS
-- ====================================================================
local Window = {}
Window.__index = Window

function Window.new(lib, props)
    props = props or {}
    local titleText = props.name or props.Name or props.Title or props.title or "Keoirn"
    local subTitleText = props.subTitle or props.SubTitle or props.subtitle or props.Subtitle

    local self = setmetatable({
        lib          = lib,
        name         = titleText,
        subTitle     = subTitleText,
        tabs         = {},
        _selectedTab = nil,
        hidden       = false,
        unloaded     = false,
        configFolder = props.configFolder or props.ConfigFolder,
        settings     = {
            toggleKeybind = props.toggleKeybind or props.ToggleKeybind or Enum.KeyCode.RightShift,
        },
        _flags       = {},
        _connections = newConnPool(),
    }, Window)

    local guiParent = getGuiContainer()
    self.screenGui = make("ScreenGui", {
        Name                  = "Keoirn_" .. self.name,
        ResetOnSpawn          = false,
        IgnoreGuiInset        = true,
        ZIndexBehavior        = Enum.ZIndexBehavior.Sibling,
        Enabled               = true,
    }, guiParent)

    local winW = (props.Size and props.Size.X.Offset) or 480
    local winH = (props.Size and props.Size.Y.Offset) or 380

    self.main = make("Frame", {
        Name             = "Window",
        Size             = UDim2.fromOffset(winW, winH),
        Position         = UDim2.fromOffset(props.X or 100, props.Y or 80),
        BackgroundColor3 = PALETTE.Background,
        BorderSizePixel  = 0,
        Active           = true,
        Draggable        = true,
    }, self.screenGui)
    corner(10, self.main)
    stroke(PALETTE.Stroke, 1, self.main)

    -- Title Bar
    local titleBar = make("Frame", {
        Size             = UDim2.new(1, 0, 0, subTitleText and 44 or 38),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
    }, self.main)
    corner(10, titleBar)

    make("Frame", {
        Size             = UDim2.new(1, 0, 0, 10),
        Position         = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
    }, titleBar)

    -- Title texts
    if subTitleText then
        make("TextLabel", {
            Text                = self.name,
            TextSize            = 14,
            TextColor3          = PALETTE.Content,
            Font                = Enum.Font.GothamBold,
            BackgroundTransparency = 1,
            BorderSizePixel     = 0,
            TextXAlignment      = Enum.TextXAlignment.Left,
            Size                = UDim2.new(1, -150, 0, 18),
            Position            = UDim2.fromOffset(14, 4),
        }, titleBar)
        make("TextLabel", {
            Text                = subTitleText,
            TextSize            = 11,
            TextColor3          = PALETTE.ContentDim,
            Font                = Enum.Font.GothamMedium,
            BackgroundTransparency = 1,
            BorderSizePixel     = 0,
            TextXAlignment      = Enum.TextXAlignment.Left,
            Size                = UDim2.new(1, -150, 0, 14),
            Position            = UDim2.fromOffset(14, 22),
        }, titleBar)
    else
        make("TextLabel", {
            Text                = self.name,
            TextSize            = 15,
            TextColor3          = PALETTE.Content,
            Font                = Enum.Font.GothamBold,
            BackgroundTransparency = 1,
            BorderSizePixel     = 0,
            TextXAlignment      = Enum.TextXAlignment.Left,
            Size                = UDim2.new(1, -150, 1, 0),
            Position            = UDim2.fromOffset(14, 0),
        }, titleBar)
    end

    -- Close & Hide buttons
    local closeBtn = button("✕", PALETTE.Error, titleBar)
    closeBtn.Position    = UDim2.new(1, -30, 0.5, 0)
    closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    closeBtn.Size        = UDim2.fromOffset(22, 22)
    closeBtn.TextSize    = 11

    local hideBtn = button("—", PALETTE.Stroke, titleBar)
    hideBtn.Position     = UDim2.new(1, -56, 0.5, 0)
    hideBtn.AnchorPoint  = Vector2.new(0.5, 0.5)
    hideBtn.Size         = UDim2.fromOffset(22, 22)
    hideBtn.TextSize     = 11

    -- Action Container (for CreateAction)
    self.actionContainer = make("Frame", {
        Size                   = UDim2.new(0, 0, 1, 0),
        AutomaticSize          = Enum.AutomaticSize.X,
        Position               = UDim2.new(1, -72, 0.5, 0),
        AnchorPoint            = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, titleBar)
    listLayout(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 4, self.actionContainer)

    -- Tab bar
    local tabTop = subTitleText and 44 or 38
    self.tabBar = make("ScrollingFrame", {
        Size                    = UDim2.new(1, 0, 0, 34),
        Position                = UDim2.fromOffset(0, tabTop),
        BackgroundColor3        = PALETTE.Surface,
        BorderSizePixel         = 0,
        ClipsDescendants        = true,
        ScrollBarThickness      = 0,
        ScrollingDirection      = Enum.ScrollingDirection.X,
        AutomaticCanvasSize     = Enum.AutomaticSize.X,
        CanvasSize              = UDim2.new(0, 0, 0, 0),
    }, self.main)
    pad(10, 10, 4, 4, self.tabBar)
    listLayout(Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center, 6, self.tabBar)

    -- Content frame
    local contentTop = tabTop + 34
    self.content = make("Frame", {
        Size                   = UDim2.new(1, 0, 1, -contentTop),
        Position               = UDim2.fromOffset(0, contentTop),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ClipsDescendants       = true,
    }, self.main)

    -- Notification Stack
    self.notifications = make("Frame", {
        Size                   = UDim2.fromOffset(300, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        AnchorPoint            = Vector2.new(1, 1),
        Position               = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ZIndex                 = 100,
    }, self.screenGui)
    listLayout(nil, Enum.HorizontalAlignment.Right, nil, 6, self.notifications)

    -- Restore / Minimised pill
    local pillText = props.showName or props.ShowName or ("▶ " .. self.name)
    self.restoreFrame = make("TextButton", {
        Size             = UDim2.fromOffset(150, 32),
        Position         = UDim2.fromOffset(props.X or 100, props.Y or 80),
        BackgroundColor3 = PALETTE.Background,
        BorderSizePixel  = 0,
        Text             = pillText,
        TextColor3       = PALETTE.Content,
        TextSize         = 12,
        Font             = Enum.Font.GothamMedium,
        AutoButtonColor  = false,
        Visible          = false,
        ZIndex           = 50,
        Active           = true,
        Draggable        = true,
    }, self.screenGui)
    corner(8, self.restoreFrame)
    stroke(PALETTE.Stroke, 1, self.restoreFrame)

    self._connections:add(closeBtn.MouseButton1Click:Connect(function() self:Destroy() end))
    self._connections:add(hideBtn.MouseButton1Click:Connect(function() self:ToggleHide() end))
    self._connections:add(self.restoreFrame.MouseButton1Click:Connect(function() self:ToggleHide() end))
    self._connections:add(UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == self.settings.toggleKeybind then self:ToggleHide() end
    end))

    return self
end

function Window:_selectTab(tab)
    for _, t in ipairs(self.tabs) do
        t:_setActive(false)
    end
    tab:_setActive(true)
    self._selectedTab = tab
end

function Window:_persist(element)
    if element and element.flag then
        self._flags[element.flag] = element.value
    end
end

function Window:GetFlags()
    return self._flags
end

function Window:GetFlag(flag)
    return self._flags[flag]
end

function Window:CreateAction(props)
    props = props or {}
    local act = make("TextButton", {
        Name                   = props.name or props.Name or "Action",
        Size                   = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Text                   = "",
        AutoButtonColor        = false,
        LayoutOrder            = -(props.order or 0),
    }, self.actionContainer)

    local icon = make("ImageLabel", {
        Image                  = props.icon or props.Icon or "",
        Size                   = UDim2.fromOffset(18, 18),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        ImageColor3            = PALETTE.ContentDim,
    }, act)

    local tooltipText = props.tooltip or props.Tooltip
    local tooltipLabel = nil
    if tooltipText then
        tooltipLabel = make("TextLabel", {
            Text                = tooltipText,
            Size                = UDim2.fromOffset(0, 20),
            AutomaticSize       = Enum.AutomaticSize.X,
            BackgroundColor3    = PALETTE.Panel,
            BackgroundTransparency = 0.1,
            BorderSizePixel     = 0,
            TextSize            = 12,
            TextColor3          = PALETTE.White,
            Font                = Enum.Font.GothamMedium,
            AnchorPoint         = Vector2.new(0.5, 1),
            Position            = UDim2.new(0.5, 0, 0, -4),
            Visible             = false,
            ZIndex              = 200,
        }, act)
        corner(4, tooltipLabel)
        pad(6, 6, 2, 2, tooltipLabel)
        stroke(PALETTE.Stroke, 1, tooltipLabel)
    end

    self._connections:add(act.MouseEnter:Connect(function()
        icon.ImageColor3 = PALETTE.Content
        if tooltipLabel then tooltipLabel.Visible = true end
    end))

    self._connections:add(act.MouseLeave:Connect(function()
        icon.ImageColor3 = PALETTE.ContentDim
        if tooltipLabel then tooltipLabel.Visible = false end
    end))

    self._connections:add(act.MouseButton1Click:Connect(function()
        if props.callback or props.Callback then
            task.spawn(props.callback or props.Callback)
        end
    end))

    return act
end

function Window:CreateTab(props)
    if type(props) == "string" then props = { Name = props } end
    props = props or {}
    local t = Tab.new(self, props)
    table.insert(self.tabs, t)
    if #self.tabs == 1 then
        self:_selectTab(t)
    end
    return t
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
    for _, t in ipairs(self.tabs) do
        t._pool:cleanAll()
    end
    self.screenGui:Destroy()
end

function Window:Unload()
    self:Destroy()
end

function Window:Notify(props)
    props = props or {}
    local frame = make("Frame", {
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
        LayoutOrder      = #self.notifications:GetChildren(),
    }, self.notifications)
    corner(8, frame)
    stroke(PALETTE.Stroke, 1, frame)
    pad(12, 12, 8, 8, frame)

    local inner = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, frame)
    listLayout(nil, nil, nil, 3, inner)

    if props.title or props.Title then
        label(props.title or props.Title, 14, PALETTE.Content, Enum.TextXAlignment.Left, inner)
    end
    if props.content or props.Content then
        label(props.content or props.Content, 12, PALETTE.ContentDim, Enum.TextXAlignment.Left, inner)
    end

    local duration = props.duration or props.Duration or 4
    task.delay(duration, function()
        if frame and frame.Parent then frame:Destroy() end
    end)
end

function Window:Toast(props)
    self:Notify(props)
end

function Window:Popup(props)
    props = props or {}
    local opts = props.options or props.Options or { { Name = "Okay" } }
    local guiParent = getGuiContainer()

    local gui = make("ScreenGui", {
        Name           = "Keoirn_Popup",
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        DisplayOrder   = 100,
    }, guiParent)

    make("Frame", {
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel        = 0,
        Active                 = true,
    }, gui)

    local card = make("Frame", {
        Size             = UDim2.fromOffset(340, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = PALETTE.Surface,
        BorderSizePixel  = 0,
    }, gui)
    corner(10, card)
    stroke(PALETTE.Stroke, 1, card)
    pad(18, 18, 14, 14, card)
    listLayout(nil, Enum.HorizontalAlignment.Center, nil, 10, card)

    if props.title or props.Title then
        label(props.title or props.Title, 15, PALETTE.Content, Enum.TextXAlignment.Left, card)
    end
    if props.content or props.Content then
        label(props.content or props.Content, 13, PALETTE.ContentDim, Enum.TextXAlignment.Left, card)
    end

    local btnRow = make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
    }, card)
    listLayout(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 8, btnRow)

    for _, opt in ipairs(opts) do
        local optName = opt.Name or opt.name or opt.Text or opt.text or "Option"
        local b = button(optName, PALETTE.Accent, btnRow)
        b.MouseButton1Click:Connect(function()
            gui:Destroy()
            if opt.callback or opt.Callback then
                pcall(opt.callback or opt.Callback)
            end
        end)
    end
end

-- ====================================================================
-- LIBRARY ROOT
-- ====================================================================
local Keoirn = {}
Keoirn.__index = Keoirn
Keoirn.Version = "1.1.0-enhanced"

local _windows = setmetatable({}, { __mode = "v" })

function Keoirn.CreateWindow(self, props)
    if type(self) ~= "table" or (self ~= Keoirn and getmetatable(self) ~= Keoirn) then
        props = self
    end
    local win = Window.new(Keoirn, props)
    table.insert(_windows, win)
    return win
end

function Keoirn:CreateWindow(props)
    local win = Window.new(Keoirn, props)
    table.insert(_windows, win)
    return win
end

function Keoirn.Destroy()
    for _, win in ipairs(_windows) do
        if win and not win.unloaded then
            pcall(function() win:Destroy() end)
        end
    end
    table.clear(_windows)
end

return Keoirn
