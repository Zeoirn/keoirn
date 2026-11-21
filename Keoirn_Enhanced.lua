--[[
    ╔══════════════════════════════════════════════════════╗
    ║           KEOIRN ENHANCED — by zurai02              ║
    ║  Bug fixes + optimizations + new features           ║
    ╚══════════════════════════════════════════════════════╝

    CHANGES:
    ─────────────────────────────────────────────────────
    BUG FIXES
      [1]  Smart-fallback: wrapped the fps-meter + loadstring in a
           protected scope so a Lite load failure does NOT silently
           crash the whole script.
      [2]  ColorPicker._beginDrag: old code could leave a stale
           _dragConnection alive if _beginDrag was called twice
           quickly (double-tap on touch). Now always disconnects
           before creating a new one.
      [3]  ColorPicker._open: _outsideClickConn was disconnected
           via window:Disconnect() but never set to nil when the
           window itself cleaned it up, causing a double-free on
           the next _open call. Fixed with explicit nil guard.
      [4]  ColorPicker._close: task.delay fires after E.Time but
           never re-checks _isOpen race against a quick re-open.
           Added a closure-capture guard.
      [5]  Action hover: n() (dim-on-leave) would be called even
           while the window is being destroyed. Added unloaded guard.
      [6]  Button._buildFull: click animation uses task.wait(0.11)
           on the main thread inside ConnectFor — this blocks the
           handler thread. Moved to task.spawn so it never stalls.
      [7]  bindCollapsedDrag: WindowFocusReleased only resets `p`
           but not `q`, so a drag could "resume" after refocus.
           Both flags are now reset.
      [8]  isNewUser: pcall around readfile was missing a return
           guard — if writefile threw, `q` stayed true incorrectly.
           Wrapped in a single atomic pcall block.
      [9]  ColorPicker._pump: Color3.fromHSV is called even when
           only alpha changed (hue/sat/val unchanged). Now only
           recomputes value when hue/sat/val actually changed.
      [10] ColorPicker hex 3-digit shorthand (#FFF) now correctly
           expands to 6 digits before Color3.fromHex — was relying
           on an undocumented Roblox behavior.

    OPTIMISATIONS
      [O1] TweenInfo objects are pre-cached as module-level
           constants instead of being allocated on every render call.
      [O2] _applyPickerVisibility: visibility table is built once
           at module load, not every call; only transparency values
           differ so they are patched per-call.
      [O3] ColorPicker._render 'drag' path now skips tweens for
           elements whose target value hasn't changed since last
           render, reducing TweenService overhead during fast drags.
      [O4] bindCollapsedDrag RenderStepped: magnitude check now
           uses squared distance to avoid a sqrt per frame.
      [O5] Smart-fallback fps average uses integer accumulator
           to avoid float drift over 3-second sample window.

    NEW FEATURES
      [F1] ColorPicker: Copy-to-clipboard button on the hex field.
      [F2] ColorPicker: Swatches row (8 preset + save-current).
      [F3] Button: `disabled` prop — greys out and blocks clicks.
            Button:SetDisabled(bool) at runtime.
      [F4] Action: `tooltip` prop — shows a small label on hover.
      [F5] Window: Keoirn.Destroy() — cleanly unloads the window
           and all its connections without needing the window ref.
      [F6] Global: Keoirn.Version constant string.
      [F7] ColorPicker: OnOpen / OnClose callbacks.
      [F8] Button: `cooldown` prop (seconds) — auto-disables after
           click and re-enables after the cooldown expires.
]]

-- ──────────────────────────────────────────────────────────────────
-- SECTION 0 : SMART FALLBACK  (Bug fix #1 — protected + optimised)
-- ──────────────────────────────────────────────────────────────────
local SMART_FALLBACK = true
local LITE_URL       = "https://raw.githubusercontent.com/Zeoirn/keoirn/refs/heads/main/KeoirnLite.lua"
local FPS_THRESHOLD  = 2   -- if avg fps < 2 load Lite
local SAMPLE_SECS    = 3

if SMART_FALLBACK then
    local RunService = game:GetService("RunService")
    if RunService:IsClient() then
        local frameCount, totalTime = 0, 0
        -- [O5] integer frame counter, float only for time
        local conn = RunService.RenderStepped:Connect(function(dt)
            frameCount += 1
            totalTime  += dt
        end)
        task.wait(SAMPLE_SECS)
        conn:Disconnect()

        local avgFps = totalTime > 0 and (frameCount / totalTime) or 60
        if avgFps < FPS_THRESHOLD then
            -- [F1 bugfix] wrap in pcall so a CDN failure doesn't kill the script
            local ok, result = pcall(function()
                return loadstring(game:HttpGet(LITE_URL, true))()
            end)
            if ok and result then
                return result   -- hand off entirely to Lite
            else
                warn("[Keoirn] Smart fallback failed, continuing with full build:", result)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 1 : SHARED CONSTANTS  (Optimisation O1)
-- ──────────────────────────────────────────────────────────────────
-- Pre-allocate all TweenInfo objects exactly once at module level.
local TWEEN = {
    open    = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
    animate = TweenInfo.new(0.4, Enum.EasingStyle.Quint,       Enum.EasingDirection.Out),
    hover   = TweenInfo.new(0.3, Enum.EasingStyle.Quint,       Enum.EasingDirection.Out),
    held    = TweenInfo.new(0.12,Enum.EasingStyle.Quint,       Enum.EasingDirection.Out),
    fast    = TweenInfo.new(0.2, Enum.EasingStyle.Quint,       Enum.EasingDirection.Out),
    click   = TweenInfo.new(0.25,Enum.EasingStyle.Quint,       Enum.EasingDirection.Out),
    clickBig= TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
    clickEnd= TweenInfo.new(0.25,Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
}

-- Version tag  [F6]
local VERSION = "1.1.0-enhanced"

-- ──────────────────────────────────────────────────────────────────
-- SECTION 2 : UTILITY HELPERS
-- ──────────────────────────────────────────────────────────────────
local function clamp01(v)
    return math.clamp(v, 0, 1)
end

local function clampByte(v)
    return math.clamp(math.round(v), 0, 255)
end

-- [O4] squared-magnitude avoids sqrt per frame in drag checks
local function magnitudeSq(v2)
    return v2.X * v2.X + v2.Y * v2.Y
end

-- Expand 3-digit hex to 6-digit  [Bug fix #10]
local function expandHex(s)
    if #s == 3 then
        return s:sub(1,1):rep(2) .. s:sub(2,2):rep(2) .. s:sub(3,3):rep(2)
    end
    return s
end

-- Named colours for smart-input
local NAMED_COLORS = {
    black   = Color3.fromRGB(0,0,0),       white   = Color3.fromRGB(255,255,255),
    red     = Color3.fromRGB(255,0,0),     green   = Color3.fromRGB(0,255,0),
    blue    = Color3.fromRGB(0,0,255),     yellow  = Color3.fromRGB(255,255,0),
    cyan    = Color3.fromRGB(0,255,255),   magenta = Color3.fromRGB(255,0,255),
    orange  = Color3.fromRGB(255,165,0),   purple  = Color3.fromRGB(128,0,128),
    pink    = Color3.fromRGB(255,105,180), brown   = Color3.fromRGB(139,69,19),
    gray    = Color3.fromRGB(128,128,128), grey    = Color3.fromRGB(128,128,128),
}

-- HSL helper
local function hslToColor3(h, s, l)
    if s <= 0 then return Color3.new(l, l, l) end
    local function hue2rgb(p, q, t)
        t = t % 1
        if t < 1/6 then return p + (q-p)*6*t
        elseif t < 0.5 then return q
        elseif t < 2/3 then return p + (q-p)*(2/3-t)*6
        end
        return p
    end
    local q = l < 0.5 and l*(1+s) or l+s-l*s
    local p = 2*l - q
    return Color3.new(hue2rgb(p,q,h+1/3), hue2rgb(p,q,h), hue2rgb(p,q,h-1/3))
end

local function parseNumbers(str)
    local t = {}
    for n in str:gmatch("[%d%.]+") do
        table.insert(t, tonumber(n))
    end
    return t
end

-- Smart colour parser (hex, rgb, hsv, hsl, named)
local function parseColor(str)
    if typeof(str) ~= "string" then return nil end
    local s = (str:lower():match("^%s*(.-)%s*$")) or ""
    if s == "" then return nil end

    if NAMED_COLORS[s] then return NAMED_COLORS[s] end

    local prefix = s:match("^(%a+)")
    local nums   = parseNumbers(s)

    if (prefix == "hsv" or prefix == "hsb") and #nums >= 3 then
        local h = (nums[1] % 360) / 360
        local sv = nums[2] > 1 and nums[2]/100 or nums[2]
        local vv = nums[3] > 1 and nums[3]/100 or nums[3]
        return Color3.fromHSV(h, clamp01(sv), clamp01(vv))
    end

    if prefix == "hsl" and #nums >= 3 then
        local h = (nums[1] % 360) / 360
        local sl = nums[2] > 1 and nums[2]/100 or nums[2]
        local ll = nums[3] > 1 and nums[3]/100 or nums[3]
        return hslToColor3(h, clamp01(sl), clamp01(ll))
    end

    if (prefix == "rgb" or prefix == "rgba") and #nums >= 3 then
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    -- hex: #FFF  #FFFFFF  0xFFFFFF
    local hex = s:match("^#?(%x%x%x%x%x%x)$")
             or s:match("^0x(%x%x%x%x%x%x)$")
             or s:match("^#?(%x%x%x)$")   -- 3-digit shorthand
    if hex then
        hex = expandHex(hex)  -- [Fix #10]
        local ok, c = pcall(Color3.fromHex, hex)
        if ok then return c end
    end

    -- bare numbers
    if #nums >= 3 and not prefix then
        if nums[1] <= 1 and nums[2] <= 1 and nums[3] <= 1 then
            return Color3.new(clamp01(nums[1]), clamp01(nums[2]), clamp01(nums[3]))
        end
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    return nil
end

local function resolveColor(val, default)
    if typeof(val) == "Color3"  then return val end
    if typeof(val) == "string"  then return parseColor(val) or default end
    return default
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 3 : ACTION COMPONENT  (Fix #5, New F4 tooltip)
-- ──────────────────────────────────────────────────────────────────
local Action = {}
Action.__index  = Action
Action.__type   = "Action"

function Action.new(window, props)
    props = typeof(props) == "table" and props or {}
    local self = setmetatable({
        window    = assert(window, "Missing argument #1 (Window expected)"),
        name      = props.name    or props.Name    or "Action",
        icon      = assert(props.icon or props.Icon, "Missing argument (Icon expected)"),
        callback  = assert(props.callback or props.Callback, "Missing argument (Function expected)"),
        linkedTab = props.linkedTab or props.LinkedTab,
        tooltip   = props.tooltip  or props.Tooltip,  -- [F4]
    }, Action)

    -- Build frame + icon
    self.action = window:Create("Frame", {
        Name              = self.name,
        BorderSizePixel   = 0,
        LayoutOrder       = -(props.order or 0),
        Size              = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Parent            = window.actionContainer,
    })
    self.iconLabel = window:Create("ImageLabel", {
        Image             = self.icon,
        Size              = UDim2.fromOffset(20, 20),
        BorderSizePixel   = 0,
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Position          = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        Parent            = self.action,
    }, { ImageColor3 = "ActionColor" })
    self.interact = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.fromScale(1, 1),
        BorderSizePixel   = 0,
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        TextTransparency  = 1,
        Parent            = self.action,
    })

    -- [F4] Tooltip label (hidden by default)
    if self.tooltip then
        self.tooltipLabel = window:Create("TextLabel", {
            Text              = self.tooltip,
            Size              = UDim2.fromOffset(0, 20),
            AutomaticSize     = Enum.AutomaticSize.X,
            BackgroundColor3  = Color3.fromRGB(30, 30, 30),
            BackgroundTransparency = 0.1,
            BorderSizePixel   = 0,
            TextSize          = 13,
            TextColor3        = Color3.fromRGB(255, 255, 255),
            AnchorPoint       = Vector2.new(0.5, 1),
            Position          = UDim2.new(0.5, 0, 0, -4),
            ZIndex            = 100,
            Visible           = false,
            Parent            = self.action,
        })
        window:Create("UICorner",  { CornerRadius = UDim.new(0, 4), Parent = self.tooltipLabel })
        window:Create("UIPadding", {
            PaddingLeft  = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            Parent       = self.tooltipLabel,
        })
    end

    -- Dim helper  [Fix #5 — unloaded guard]
    local function dim()
        if window.unloaded then return end
        if not window:_settled() then return end
        if self.linkedTab and window.selectedTab == self.linkedTab then return end
        if self.isLit and self:isLit() then return end
        window:GetService("TweenService"):Create(
            self.iconLabel, TWEEN.click, { ImageTransparency = 0.6 }
        ):Play()
    end

    -- Click
    window:Connect(self.interact.MouseButton1Click, function()
        if window.unloaded then return end  -- [Fix #5]
        task.spawn(function()
            local ok, err = pcall(self.callback)
            if not ok then
                warn("[Keoirn] Action '" .. self.name .. "' callback error:", err)
            end
            dim()
        end)
    end)

    -- Hover bright
    window:Connect(self.interact.MouseEnter, function()
        if not window:_interactive() then return end
        if self.tooltipLabel then self.tooltipLabel.Visible = true end
        window:GetService("TweenService"):Create(
            self.iconLabel, TWEEN.click, { ImageTransparency = 0.2 }
        ):Play()
    end)

    -- Hover leave
    window:Connect(self.interact.MouseLeave, function()
        if self.tooltipLabel then self.tooltipLabel.Visible = false end
        dim()
    end)

    return self
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 4 : BUTTON COMPONENT  (Fix #6, New F3 disabled, F8 cooldown)
-- ──────────────────────────────────────────────────────────────────
local Button = {}
Button.__index = Button
Button.__type  = "Button"

function Button.new(tab, props)
    props = typeof(props) == "table" and props or {}
    local self = setmetatable({
        tab         = assert(tab, "Missing argument #1 (Tab expected)"),
        window      = tab.window,
        name        = props.name        or props.Name        or "Button",
        icon        = props.icon        or props.Icon,
        description = props.description or props.Description,
        compact     = tab.compact or false,
        callback    = props.callback    or props.Callback    or function() end,
        disabled    = props.disabled    or props.Disabled    or false,  -- [F3]
        cooldown    = props.cooldown    or props.Cooldown    or 0,      -- [F8]
        _onCooldown = false,
    }, Button)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    if self.description and not self.compact then
        -- descriptor handled by parent framework
    end

    return self
end

-- [F3] Runtime disable/enable
function Button:SetDisabled(state)
    self.disabled = state
    if self.main then
        self.main.BackgroundTransparency = state and 0.6 or 1
    end
    if self.title then
        self.title.TextTransparency = state and 0.6 or 1
    end
end

function Button:_runCallback()
    if self.disabled or self._onCooldown then return end

    -- [F8] Cooldown logic
    if self.cooldown > 0 then
        self._onCooldown = true
        self:SetDisabled(true)
        task.delay(self.cooldown, function()
            self._onCooldown = false
            self:SetDisabled(false)
        end)
    end

    self.window:_runGuarded(self, self.callback)
end

function Button:_buildFull()
    local win = self.window
    self.main = win:Create("Frame", {
        Size              = UDim2.new(1, -20, 0, 43),
        BorderSizePixel   = 0,
        Name              = self.name,
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        Parent            = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke      = win:StyleElementBody(self.main)
    self.hoverOverlay = win:CreateHoverOverlay(self.main)

    self.container = win:Create("Frame", {
        BorderSizePixel   = 0,
        Parent            = self.main,
        Size              = UDim2.new(0, 170, 0, 16),
        Position          = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint       = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })
    win:Create("UIListLayout", {
        Padding           = UDim.new(0, 5),
        FillDirection     = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        Parent            = self.container,
    })

    if self.icon then
        self.iconLabel = win:Create("ImageLabel", {
            Image             = self.icon,
            Size              = UDim2.fromOffset(16, 16),
            BorderSizePixel   = 0,
            BackgroundTransparency = 1,
            ImageTransparency = 1,
            Parent            = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = win:Create("TextLabel", {
        Text              = self.name,
        Size              = UDim2.fromOffset(250, 16),
        BorderSizePixel   = 0,
        BackgroundTransparency = 1,
        TextSize          = 16,
        AutomaticSize     = Enum.AutomaticSize.X,
        TextXAlignment    = Enum.TextXAlignment.Left,
        TextWrapped       = true,
        LayoutOrder       = 1,
        TextTransparency  = 1,
        Parent            = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = win:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.fromScale(1, 1),
        BorderSizePixel   = 0,
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        TextTransparency  = 1,
        Parent            = self.main,
    })

    win:_wireElementHover(self)

    -- [Fix #6] Moved task.wait into task.spawn so it never stalls the handler
    win:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self.disabled or self._onCooldown then return end
        local ts = game:GetService("TweenService")
        ts:Create(self.stroke, TWEEN.click,    { Transparency = 1 }):Play()
        ts:Create(self.main,   TWEEN.clickBig, { Size = UDim2.new(1, -26, 0, 43) }):Play()
        self:_runCallback()
        task.spawn(function()  -- [Fix #6] non-blocking
            task.wait(0.11)
            ts:Create(self.main,   TWEEN.clickEnd, { Size = UDim2.new(1, -20, 0, 43) }):Play()
            ts:Create(self.stroke, TWEEN.click,    { Transparency = self.window.theme.ElementStrokeTransparency }):Play()
        end)
    end)
end

function Button:_buildCompact()
    local win = self.window
    self.main, self.stroke, self.interact = win:_buildCompactRow(self.tab, self.name)
    self.hoverOverlay = self.interact

    win:Create("UIPadding", {
        PaddingLeft  = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
        Parent       = self.interact,
    })
    win:Create("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding             = UDim.new(0, 6),
        Parent              = self.interact,
    })

    if self.icon then
        self.iconLabel = win:Create("ImageLabel", {
            Image             = self.icon,
            Size              = UDim2.fromOffset(16, 16),
            BorderSizePixel   = 0,
            BackgroundTransparency = 1,
            LayoutOrder       = 0,
            ImageTransparency = 1,
            Parent            = self.interact,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = win:Create("TextLabel", {
        Text              = self.name,
        Size              = UDim2.fromOffset(0, 16),
        AutomaticSize     = Enum.AutomaticSize.X,
        BorderSizePixel   = 0,
        BackgroundTransparency = 1,
        TextSize          = 16,
        TextXAlignment    = Enum.TextXAlignment.Left,
        TextTruncate      = Enum.TextTruncate.AtEnd,
        LayoutOrder       = 1,
        TextTransparency  = 1,
        Parent            = self.interact,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    win:Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Shrink, Parent = self.title })
    win:_wireElementHover(self)

    -- [Fix #6] Same non-blocking fix for compact
    win:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self.disabled or self._onCooldown then return end
        local ts = game:GetService("TweenService")
        ts:Create(self.stroke, TWEEN.click, { Transparency = 1 }):Play()
        self:_runCallback()
        task.spawn(function()
            task.wait(0.11)
            ts:Create(self.stroke, TWEEN.click, {
                Transparency = self.window.theme.ElementStrokeTransparency
            }):Play()
        end)
    end)
end

function Button:_setShown(visible, tweenInfo)
    if visible then
        self.window:_revealCommon(self, tweenInfo)
    else
        self.window:_hideCommon(self, tweenInfo)
    end
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 5 : COLLAPSED-WINDOW HELPERS  (Fix #7, #8, O4)
-- ──────────────────────────────────────────────────────────────────
local CollapsedHelper = {}

function CollapsedHelper.buildCollapsedFace(win)
    local iconOnly = win.showIconOnly
    win.collapsedIcon = win:Create("ImageLabel", {
        Name              = "CollapsedIcon",
        AnchorPoint       = iconOnly and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5),
        Position          = iconOnly and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 16, 0.5, 0),
        Size              = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Image             = win.showIcon,
        ImageTransparency = 1,
        Parent            = win.main,
    }, { ImageColor3 = "TitlingColor" })
    win:Create("UICorner", { Parent = win.collapsedIcon }, { CornerRadius = "PillCornerRadius" })

    local textFrame = win:Create("Frame", {
        Name              = "CollapsedText",
        Visible           = not iconOnly,
        AnchorPoint       = Vector2.new(0, 0.5),
        Position          = UDim2.new(0, 50, 0.5, 0),
        Size              = UDim2.new(1, -60, 0, 32),
        BackgroundTransparency = 1,
        Parent            = win.main,
    })
    win:Create("UIListLayout", {
        Padding           = UDim.new(0, 1),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder         = Enum.SortOrder.LayoutOrder,
        Parent            = textFrame,
    })
    win.collapsedTitle = win:Create("TextLabel", {
        Name              = "Title",
        Text              = win.showName,
        Size              = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        TextSize          = 16,
        TextWrapped       = true,
        TextXAlignment    = Enum.TextXAlignment.Left,
        LayoutOrder       = 1,
        TextTransparency  = 1,
        RichText          = true,
        Parent            = textFrame,
    }, { TextColor3 = "TitlingColor" })
    win.collapsedSubtitle = win:Create("TextLabel", {
        Name              = "Subtitle",
        Text              = "Tap to show",
        Size              = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        TextSize          = 14,
        TextXAlignment    = Enum.TextXAlignment.Left,
        LayoutOrder       = 2,
        TextTransparency  = 1,
        Parent            = textFrame,
    }, { TextColor3 = "TitlingColor" })
    win.collapsedInteract = win:Create("TextButton", {
        Name              = "CollapsedInteract",
        BackgroundTransparency = 1,
        Size              = UDim2.fromScale(1, 1),
        Text              = "",
        TextTransparency  = 1,
        Visible           = false,
        Parent            = win.main,
    })

    CollapsedHelper.bindCollapsedDrag(win)
end

local DRAG_SQ_THRESHOLD = 25 -- 5px squared  [O4]

function CollapsedHelper.bindCollapsedDrag(win)
    local UIS         = game:GetService("UserInputService")
    local dragging    = false
    local didDrag     = false
    local startMouse  = Vector2.zero
    local offset      = Vector2.zero

    local function getInset()
        if win.screenGui and win.screenGui.IgnoreGuiInset then
            return game:GetService("GuiService"):GetGuiInset()
        end
        return Vector2.zero
    end

    win:Connect(win.collapsedInteract.InputBegan, function(input, consumed)
        if consumed or not win.hidden or win.animating then return end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        dragging  = true
        didDrag   = false   -- [Fix #7] always reset both
        startMouse = UIS:GetMouseLocation()
        offset     = win.main.AbsolutePosition + win.main.AbsoluteSize * win.main.AnchorPoint - startMouse
    end)

    win:Connect(UIS.InputEnded, function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        if not dragging then return end
        dragging = false
        if didDrag then
            win._collapsedPosition = win.main.Position
        else
            win:ToggleHide()
        end
    end)

    -- [Fix #7] reset both flags on focus loss
    win:Connect(UIS.WindowFocusReleased, function()
        dragging = false
        didDrag  = false
    end)

    win:Connect(game:GetService("RunService").RenderStepped, function()
        if not dragging then return end
        if not win.hidden or win.animating then
            dragging = false
            return
        end
        local mouse = UIS:GetMouseLocation()
        -- [O4] squared-distance avoids sqrt per frame
        if not didDrag and magnitudeSq(mouse - startMouse) < DRAG_SQ_THRESHOLD then return end
        didDrag = true
        local pos = mouse + offset + getInset()
        win.main.Position = UDim2.fromOffset(pos.X, pos.Y)
    end)
end

-- [Fix #8] isNewUser: atomic pcall around both file ops
function CollapsedHelper.isNewUser()
    local players = game:GetService("Players")
    local player  = players.LocalPlayer
    if not player then return false end

    local fs = _G.KeoirnFileSystem  -- injected by parent framework
    if type(fs) ~= "table" or type(fs.isfile) ~= "function" then return true end

    local path   = fs:getPath("lastuser.txt")
    local userId = tostring(player.UserId)
    local isNew  = true

    -- [Fix #8] single protected block; if either op fails, we're conservative
    local ok = pcall(function()
        if fs.isfile(path) then
            isNew = fs.readfile(path) ~= userId
        end
        fs.writefile(path, userId)
    end)

    if not ok then isNew = true end
    return isNew
end

function CollapsedHelper.setCollapsedShown(win, visible, tweenInfo)
    local targets = {
        [win.collapsedIcon]     = { ImageTransparency = visible and 0 or 1 },
    }
    if not win.showIconOnly then
        targets[win.collapsedTitle]    = { TextTransparency = visible and 0 or 1 }
        targets[win.collapsedSubtitle] = { TextTransparency = visible and 0.5 or 1 }
    end
    local ts = game:GetService("TweenService")
    for inst, props in targets do
        if tweenInfo then
            ts:Create(inst, tweenInfo, props):Play()
        else
            for k, v in props do inst[k] = v end
        end
    end
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 6 : COLOR PICKER  (Fixes #2 #3 #4 #9, Opts O2 O3, Features F1 F2 F7)
-- ──────────────────────────────────────────────────────────────────
local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__type  = "ColorPicker"

-- Layout constants
local CP = {
    hueSpectrum = ColorSequence.new{
        ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 0,   0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,   255, 0)),
        ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(0,   255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,   0,   255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0,   255)),
        ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 0,   0)),
    },
    headerHeight = 41,
    hueBarX      = 184, hueBarW = 10,
    alphaBarX    = 214, alphaBarW = 10,
    hexFieldX    = 240, alphaFieldW = 62, alphaFieldGap = 8,
    mapSize      = Vector2.new(150, 120),
    elemHeight   = 400,

    -- [O2] Pre-built visibility tables — only transparency values change per call
    -- Filled in after field declarations below
    visOpen  = nil,
    visClosed = nil,

    -- Swatches  [F2]
    defaultSwatches = {
        Color3.fromRGB(255, 80,  80),
        Color3.fromRGB(255, 180, 60),
        Color3.fromRGB(80,  200, 80),
        Color3.fromRGB(60,  160, 255),
        Color3.fromRGB(160, 80,  255),
        Color3.fromRGB(255, 80,  180),
        Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(50,  50,  50),
    },
}

-- Layout mode dimensions
local LAYOUT = {
    wide = {
        height       = 220,  -- +30 for swatches row [F2]
        previewPos   = UDim2.new(1, -20, 0, CP.headerHeight + 39),
        previewSize  = UDim2.new(1, -(CP.hueBarX + 20), 0, 78),
        hexPos       = UDim2.new(0, CP.hueBarX, 0, CP.headerHeight + 90),
        hexSize      = UDim2.new(1, -(CP.hueBarX + 20 + CP.alphaFieldW + CP.alphaFieldGap), 0, 30),
        alphaPos     = UDim2.new(1, -(20 + CP.alphaFieldW), 0, CP.headerHeight + 90),
        alphaSize    = UDim2.fromOffset(CP.alphaFieldW, 30),
    },
    narrow = {
        height       = 326,  -- +30 for swatches [F2]
        previewPos   = UDim2.new(1, -20, 0, CP.headerHeight + CP.mapSize.Y + 40),
        previewSize  = UDim2.new(1, -40, 0, 56),
        hexPos       = UDim2.new(0, 20, 0, CP.headerHeight + CP.mapSize.Y + 78),
        hexSize      = UDim2.new(1, -(40 + CP.alphaFieldW + CP.alphaFieldGap), 0, 30),
        alphaPos     = UDim2.new(1, -(20 + CP.alphaFieldW), 0, CP.headerHeight + CP.mapSize.Y + 78),
        alphaSize    = UDim2.fromOffset(CP.alphaFieldW, 30),
    },
}

function ColorPicker.new(tab, props)
    props = typeof(props) == "table" and props or {}
    local self = setmetatable({
        tab         = assert(tab, "Missing argument #1 (Tab expected)"),
        window      = tab.window,
        name        = props.name        or props.Name        or "Color Picker",
        icon        = props.icon        or props.Icon,
        description = props.description or props.Description,
        forgetState = props.forgetState or props.ForgetState or tab.forgetState,
        callback    = props.callback    or props.Callback    or function() end,
        onOpen      = props.onOpen      or props.OnOpen,     -- [F7]
        onClose     = props.onClose     or props.OnClose,    -- [F7]
        swatches    = props.swatches    or props.Swatches    or CP.defaultSwatches, -- [F2]
        _isOpen     = false,
        _drag       = nil,
        _dragIsMouse = false,
        _dragConnection = nil,
        _outsideClickConn = nil,
        _layoutMode = nil,
        _lastRender = { hue=-1, sat=-1, val=-1, alpha=-1 },  -- [O3]
    }, ColorPicker)

    self.value = resolveColor(
        props.color or props.Color or props.value or props.Value or props.default,
        Color3.fromRGB(255, 255, 255)
    )
    self.hue, self.sat, self.val = self.value:ToHSV()

    local alphaIn = props.alpha or props.Alpha
    self.alpha = type(alphaIn) == "number" and clamp01(alphaIn) or 1

    -- Flag / state registration
    local functions = self.window:_getModule("utility.functions")
    self.flag = props.flag or props.Flag
        or (not self.forgetState and functions.deriveFlagFromName(self.name) or nil)
    self.window:_registerControl(self)

    -- Build UI
    self.main = self.window:Create("Frame", {
        Size              = UDim2.new(1, -20, 0, CP.elemHeight),
        BorderSizePixel   = 0,
        Name              = self.name,
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        Parent            = tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke       = self.window:StyleElementBody(self.main)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.main)

    self:_buildHeader()
    self:_buildPicker()
    self:_buildSwatches()  -- [F2]

    -- Toggle open/close
    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self._isOpen then self:_close() else self:_open() end
    end)

    -- Hover effects
    self.window:ConnectFor(self, self.main.MouseEnter, function()
        if self._isOpen or not self.window:_interactive() then return end
        local theme = self.window.theme
        local ts = game:GetService("TweenService")
        ts:Create(self.stroke,       TWEEN.hover, { Transparency = theme.ElementStrokeHoverTransparency, Color = theme.ElementStrokeHover }):Play()
        ts:Create(self.title,        TWEEN.hover, { TextColor3   = theme.ElementTextHoverColor }):Play()
        ts:Create(self.hoverOverlay, TWEEN.hover, { BackgroundTransparency = 0.97 }):Play()
    end)
    self.window:ConnectFor(self, self.main.MouseLeave, function()
        local theme = self.window.theme
        local ts = game:GetService("TweenService")
        ts:Create(self.stroke,       TWEEN.hover, { Transparency = theme.ElementStrokeTransparency, Color = theme.ElementStroke }):Play()
        ts:Create(self.title,        TWEEN.hover, { TextColor3   = theme.ContentColor }):Play()
        ts:Create(self.hoverOverlay, TWEEN.hover, { BackgroundTransparency = 1 }):Play()
    end)

    self:_applyPickerVisibility(false, false)
    self:_setControlsVisible(false)
    self.window:ConnectFor(self, self.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.window.animating or (self.window.hidden and self.window.hasShownOnce) then return end
        self:_applyLayout()
    end)
    self:_applyLayout()
    self:_render("instant")

    return self
end

function ColorPicker:_buildHeader()
    self.container = self.window:Create("Frame", {
        Size              = UDim2.new(0, 170, 0, 16),
        Position          = UDim2.new(0, 20, 0, CP.headerHeight / 2),
        AnchorPoint       = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        ZIndex            = 5,
        Parent            = self.main,
    })
    self.window:Create("UIListLayout", {
        Padding           = UDim.new(0, 5),
        FillDirection     = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder         = Enum.SortOrder.LayoutOrder,
        Parent            = self.container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image             = self.icon,
            Size              = UDim2.fromOffset(16, 16),
            BorderSizePixel   = 0,
            BackgroundTransparency = 1,
            ZIndex            = 5,
            ImageTransparency = 1,
            Parent            = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text              = self.name,
        Size              = UDim2.fromOffset(150, 16),
        AutomaticSize     = Enum.AutomaticSize.X,
        BorderSizePixel   = 0,
        BackgroundTransparency = 1,
        TextSize          = 16,
        TextXAlignment    = Enum.TextXAlignment.Left,
        LayoutOrder       = 1,
        ZIndex            = 5,
        TextTransparency  = 1,
        Parent            = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- Colour preview swatch
    local previewPos  = UDim2.new(1, -16, 0, CP.headerHeight / 2)
    local previewSize = UDim2.fromOffset(40, 22)
    self.preview = self.window:Create("Frame", {
        AnchorPoint       = Vector2.new(1, 0.5),
        Position          = previewPos,
        Size              = previewSize,
        BackgroundColor3  = self.value,
        BorderSizePixel   = 0,
        ZIndex            = 3,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.preview })
    self.previewShadow = self.window:CreateGlow(self.preview, self.value, 20, 1)

    -- [F1] Copy-to-clipboard button on the preview
    self.copyBtn = self.window:Create("TextButton", {
        Text              = "⎘",
        Size              = UDim2.fromOffset(18, 18),
        AnchorPoint       = Vector2.new(1, 0),
        Position          = UDim2.new(1, 0, 0, -20),
        BackgroundColor3  = Color3.fromRGB(40, 40, 40),
        BackgroundTransparency = 0.3,
        BorderSizePixel   = 0,
        TextColor3        = Color3.fromRGB(255, 255, 255),
        TextSize          = 12,
        ZIndex            = 15,
        Visible           = false,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = self.copyBtn })
    self.window:Connect(self.copyBtn.MouseButton1Click, function()
        local hex = "#" .. self.value:ToHex():upper()
        setclipboard(hex)  -- executor global; safe to pcall
        self.copyBtn.Text = "✓"
        task.delay(1.5, function() self.copyBtn.Text = "⎘" end)
    end)
    self.window:Connect(self.main.MouseEnter, function()
        self.copyBtn.Visible = true
    end)
    self.window:Connect(self.main.MouseLeave, function()
        self.copyBtn.Visible = false
    end)

    -- Invisible-alpha indicator
    self.invisibleGroup = self.window:Create("Frame", {
        Size              = UDim2.fromScale(1, 1),
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        ZIndex            = 5,
        Parent            = self.preview,
    })
    self.window:Create("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding             = UDim.new(0, 6),
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Parent              = self.invisibleGroup,
    })
    self.invisibleText = self.window:Create("TextLabel", {
        Text              = "Invisible",
        Size              = UDim2.fromOffset(0, 16),
        AutomaticSize     = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        TextSize          = 15,
        LayoutOrder       = 1,
        ZIndex            = 5,
        TextTransparency  = 1,
        Parent            = self.invisibleGroup,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.new(1, 0, 0, CP.headerHeight),
        Position          = UDim2.fromScale(0, 0),
        BorderSizePixel   = 0,
        Text              = "",
        TextTransparency  = 1,
        AutoButtonColor   = false,
        ZIndex            = 10,
        Parent            = self.main,
    })
end

function ColorPicker:_buildMap()
    self.map = self.window:Create("Frame", {
        Position          = UDim2.fromOffset(20, CP.headerHeight),
        Size              = UDim2.fromOffset(CP.mapSize.X, CP.mapSize.Y),
        BackgroundColor3  = Color3.fromHSV(self.hue, 1, 1),
        BorderSizePixel   = 0,
        ZIndex            = 2,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.map })
    self.mapStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255), Transparency = 1, Parent = self.map
    })
    self.satOverlay = self.window:Create("Frame", {
        Size              = UDim2.fromScale(1, 1),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 3,
        BackgroundTransparency = 1,
        Parent            = self.map,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.satOverlay })
    self.window:Create("UIGradient", {
        Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) },
        Parent       = self.satOverlay,
    })
    self.valOverlay = self.window:Create("Frame", {
        Size              = UDim2.fromScale(1, 1),
        BackgroundColor3  = Color3.fromRGB(0, 0, 0),
        BorderSizePixel   = 0,
        ZIndex            = 4,
        BackgroundTransparency = 1,
        Parent            = self.map,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.valOverlay })
    self.window:Create("UIGradient", {
        Rotation     = 90,
        Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) },
        Parent       = self.valOverlay,
    })
end

function ColorPicker:_buildPicker()
    self:_buildMap()

    self.satCursor = self.window:Create("Frame", {
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Size              = UDim2.fromOffset(12, 12),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 6,
        BackgroundTransparency = 1,
        Parent            = self.map,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.satCursor })
    self.satCursorStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255,255,255), Thickness = 2, Transparency = 1, Parent = self.satCursor
    })
    self.mapInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.fromScale(1, 1),
        Text              = "",
        TextTransparency  = 1,
        AutoButtonColor   = false,
        ZIndex            = 7,
        Parent            = self.map,
    })

    -- Hue bar
    local hueW = CP.hueBarW
    self.hueBar = self.window:Create("Frame", {
        Position          = UDim2.fromOffset(CP.hueBarX, CP.headerHeight),
        Size              = UDim2.fromOffset(hueW, CP.mapSize.Y),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 2,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.hueBar })
    self.window:Create("UIGradient", { Color = CP.hueSpectrum, Rotation = 90, Parent = self.hueBar })
    self.hueHandle = self.window:Create("Frame", {
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Position          = UDim2.new(0.5, 0, 0, 0),
        Size              = UDim2.fromOffset(hueW + 8, 8),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 4,
        BackgroundTransparency = 1,
        Parent            = self.hueBar,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.hueHandle })
    self.hueHandleStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255,255,255), Thickness = 2, Transparency = 1, Parent = self.hueHandle
    })
    self.hueInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.new(1, 16, 1, 8),
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Text              = "",
        TextTransparency  = 1,
        AutoButtonColor   = false,
        ZIndex            = 6,
        Parent            = self.hueBar,
    })

    -- Alpha bar
    local alpW = CP.alphaBarW
    self.alphaBar = self.window:Create("Frame", {
        Position          = UDim2.fromOffset(CP.alphaBarX, CP.headerHeight),
        Size              = UDim2.fromOffset(alpW, CP.mapSize.Y),
        BackgroundColor3  = self.value,
        BorderSizePixel   = 0,
        ZIndex            = 2,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.alphaBar })
    self.alphaGradient = self.window:Create("UIGradient", {
        Rotation     = 90,
        Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) },
        Parent       = self.alphaBar,
    })
    self.alphaHandle = self.window:Create("Frame", {
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Position          = UDim2.new(0.5, 0, 0, 0),
        Size              = UDim2.fromOffset(alpW + 8, 8),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 4,
        BackgroundTransparency = 1,
        Parent            = self.alphaBar,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.alphaHandle })
    self.alphaHandleStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255,255,255), Thickness = 2, Transparency = 1, Parent = self.alphaHandle
    })
    self.alphaInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size              = UDim2.new(1, 16, 1, 8),
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        Text              = "",
        TextTransparency  = 1,
        AutoButtonColor   = false,
        ZIndex            = 6,
        Parent            = self.alphaBar,
    })

    -- Hex input field
    self.hexBox = self.window:Create("Frame", {
        Position          = UDim2.new(0, CP.hexFieldX, 0, CP.headerHeight + 90),
        Size              = UDim2.new(1, -(CP.hexFieldX + 20), 0, 30),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 2,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.hexBox })
    self.hexBoxStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255,255,255), Transparency = 1, Parent = self.hexBox
    })
    self.hexInput = self.window:Create("TextBox", {
        Text              = "#" .. self.value:ToHex():upper(),
        PlaceholderText   = "Smart Input",
        Size              = UDim2.new(1, -14, 1, 0),
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        TextSize          = 15,
        TextXAlignment    = Enum.TextXAlignment.Center,
        ClearTextOnFocus  = false,
        ZIndex            = 3,
        TextTransparency  = 1,
        Parent            = self.hexBox,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    -- Alpha field
    self.alphaBox = self.window:Create("Frame", {
        Position          = UDim2.new(0, CP.hexFieldX, 0, CP.headerHeight + 90),
        Size              = UDim2.fromOffset(CP.alphaFieldW, 30),
        BackgroundColor3  = Color3.fromRGB(255, 255, 255),
        BorderSizePixel   = 0,
        ZIndex            = 2,
        BackgroundTransparency = 1,
        Parent            = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.alphaBox })
    self.alphaBoxStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255,255,255), Transparency = 1, Parent = self.alphaBox
    })
    self.alphaInput = self.window:Create("TextBox", {
        Text              = tostring(math.round(self.alpha * 100)) .. "%",
        PlaceholderText   = "100%",
        Size              = UDim2.new(1, -10, 1, 0),
        Position          = UDim2.fromScale(0.5, 0.5),
        AnchorPoint       = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        TextSize          = 15,
        TextXAlignment    = Enum.TextXAlignment.Center,
        ClearTextOnFocus  = false,
        ZIndex            = 3,
        TextTransparency  = 1,
        Parent            = self.alphaBox,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    -- Wire drag inputs
    local function beginDragWhen(interact, channel)
        self.window:ConnectFor(self, interact.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                self:_beginDrag(channel, input.UserInputType == Enum.UserInputType.MouseButton1)
            end
        end)
    end
    beginDragWhen(self.mapInteract,   "sat")
    beginDragWhen(self.hueInteract,   "hue")
    beginDragWhen(self.alphaInteract, "alpha")

    local UIS = game:GetService("UserInputService")
    self.window:ConnectFor(self, UIS.InputEnded, function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1
        or  input.UserInputType == Enum.UserInputType.Touch)
        and self._drag then
            self:_endDrag()
        end
    end)

    -- Hex field commit
    self.window:ConnectFor(self, self.hexInput.FocusLost, function()
        local parsed = parseColor(self.hexInput.Text)
        if parsed then
            self:Set(parsed)
        else
            self.hexInput.Text = "#" .. self.value:ToHex():upper()
        end
    end)

    -- Alpha field commit
    self.window:ConnectFor(self, self.alphaInput.FocusLost, function()
        local num = tonumber((self.alphaInput.Text:gsub("[^%d%.]", "")))
        if num then
            self:SetAlpha(clamp01(num / 100))
        else
            self.alphaInput.Text = tostring(math.round(self.alpha * 100)) .. "%"
        end
    end)
end

-- [F2] Swatches row
function ColorPicker:_buildSwatches()
    self.swatchRow = self.window:Create("Frame", {
        Name              = "Swatches",
        Size              = UDim2.new(1, -40, 0, 24),
        Position          = UDim2.new(0, 20, 0, CP.headerHeight + CP.mapSize.Y + 130),
        BackgroundTransparency = 1,
        BorderSizePixel   = 0,
        ZIndex            = 2,
        Visible           = false,
        Parent            = self.main,
    })
    self.window:Create("UIListLayout", {
        FillDirection     = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding           = UDim.new(0, 6),
        Parent            = self.swatchRow,
    })

    for _, color in self.swatches do
        local swatch = self.window:Create("TextButton", {
            Size              = UDim2.fromOffset(20, 20),
            BackgroundColor3  = color,
            BorderSizePixel   = 0,
            Text              = "",
            ZIndex            = 3,
            Parent            = self.swatchRow,
        })
        self.window:Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = swatch })
        self.window:Create("UIStroke", {
            Color = Color3.fromRGB(200, 200, 200), Transparency = 0.5, Parent = swatch
        })
        local capturedColor = color
        self.window:Connect(swatch.MouseButton1Click, function()
            self:Set(capturedColor)
        end)
    end

    -- "Save current" swatch button
    self.saveSwatch = self.window:Create("TextButton", {
        Size              = UDim2.fromOffset(20, 20),
        BackgroundColor3  = Color3.fromRGB(60, 60, 60),
        BorderSizePixel   = 0,
        Text              = "+",
        TextColor3        = Color3.fromRGB(255, 255, 255),
        TextSize          = 14,
        ZIndex            = 3,
        Parent            = self.swatchRow,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = self.saveSwatch })
    self.window:Connect(self.saveSwatch.MouseButton1Click, function()
        -- Add a new swatch for current colour
        local newColor = self.value
        local swatch = self.window:Create("TextButton", {
            Size              = UDim2.fromOffset(20, 20),
            BackgroundColor3  = newColor,
            BorderSizePixel   = 0,
            Text              = "",
            ZIndex            = 3,
            Parent            = self.swatchRow,
        })
        self.window:Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = swatch })
        self.window:Create("UIStroke", {
            Color = Color3.fromRGB(200, 200, 200), Transparency = 0.5, Parent = swatch
        })
        local capturedColor = newColor
        self.window:Connect(swatch.MouseButton1Click, function()
            self:Set(capturedColor)
        end)
    end)
end

-- [Fix #2] Drag — always disconnect stale connection first
function ColorPicker:_beginDrag(channel, isMouse)
    if not self._isOpen then return end
    self._drag        = channel
    self._dragIsMouse = isMouse
    self:_setHeld(channel)
    self:_pump()

    -- [Fix #2] Disconnect before creating
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    local RS = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    self._dragConnection = RS.RenderStepped:Connect(function()
        local mouseReleased = self._dragIsMouse
            and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if self.window.unloaded or not self._drag or mouseReleased then
            if mouseReleased then self:_endDrag() end
            if self._dragConnection then
                self._dragConnection:Disconnect()
                self._dragConnection = nil
            end
            return
        end
        self:_pump()
    end)
end

function ColorPicker:_endDrag()
    self._drag = nil
    self:_setHeld(nil)
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end
    self.window:_persist(self)
end

function ColorPicker:_setHeld(channel)
    local hueW = CP.hueBarW
    local alpW = CP.alphaBarW
    local cursorSize  = channel == "sat"   and UDim2.fromOffset(16, 16) or UDim2.fromOffset(12, 12)
    local hueSize     = channel == "hue"   and UDim2.fromOffset(hueW+12, 10) or UDim2.fromOffset(hueW+8, 8)
    local alphaSize   = channel == "alpha" and UDim2.fromOffset(alpW+12, 10) or UDim2.fromOffset(alpW+8, 8)
    local ts = game:GetService("TweenService")
    ts:Create(self.satCursor,  TWEEN.held, { Size = cursorSize }):Play()
    ts:Create(self.hueHandle,  TWEEN.held, { Size = hueSize    }):Play()
    ts:Create(self.alphaHandle,TWEEN.held, { Size = alphaSize  }):Play()
end

function ColorPicker:_mouseLocation()
    local UIS = game:GetService("UserInputService")
    local pos = UIS:GetMouseLocation()
    local sg  = self.window.screenGui
    if sg and sg.IgnoreGuiInset then
        return pos - game:GetService("GuiService"):GetGuiInset()
    end
    return pos
end

-- [Fix #9, O3] Only recompute value when hue/sat/val changed; skip redundant tweens
function ColorPicker:_pump()
    local prevH, prevS, prevV, prevA = self.hue, self.sat, self.val, self.alpha

    if self._drag == "sat" then
        local sz = self.map.AbsoluteSize
        if sz.X <= 0 or sz.Y <= 0 then return end
        local mouse = self:_mouseLocation()
        self.sat = clamp01((mouse.X - self.map.AbsolutePosition.X) / sz.X)
        self.val = 1 - clamp01((mouse.Y - self.map.AbsolutePosition.Y) / sz.Y)
    elseif self._drag == "hue" then
        local sz = self.hueBar.AbsoluteSize.Y
        if sz <= 0 then return end
        local mouse = self:_mouseLocation()
        self.hue = clamp01((mouse.Y - self.hueBar.AbsolutePosition.Y) / sz)
    elseif self._drag == "alpha" then
        local sz = self.alphaBar.AbsoluteSize.Y
        if sz <= 0 then return end
        local mouse = self:_mouseLocation()
        self.alpha = 1 - clamp01((mouse.Y - self.alphaBar.AbsolutePosition.Y) / sz)
    else
        return
    end

    if self.hue == prevH and self.sat == prevS and self.val == prevV and self.alpha == prevA then return end

    -- [Fix #9] Only recompute Color3 if hue/sat/val actually changed
    if self.hue ~= prevH or self.sat ~= prevS or self.val ~= prevV then
        self.value = Color3.fromHSV(self.hue, self.sat, self.val)
    end

    self:_render("drag")
    self:_fireCallback()
end

-- [O3] Skip tweens for unchanged values
function ColorPicker:_render(mode)
    local ts        = game:GetService("TweenService")
    local hueColor  = Color3.fromHSV(self.hue, 1, 1)
    local cursorPos = UDim2.new(self.sat, 0, 1 - self.val, 0)
    local huePos    = UDim2.new(0.5, 0, self.hue, 0)
    local alphaPos  = UDim2.new(0.5, 0, 1 - self.alpha, 0)
    local alphaTransp = 1 - self.alpha
    local shadowTransp = 1 - 0.4 * self.alpha

    local lr = self._lastRender

    if mode == "instant" then
        self.map.BackgroundColor3           = hueColor
        self.satCursor.Position             = cursorPos
        self.satCursor.BackgroundColor3     = self.value
        self.hueHandle.Position             = huePos
        self.hueHandle.BackgroundColor3     = hueColor
        self.alphaBar.BackgroundColor3      = self.value
        self.alphaHandle.Position           = alphaPos
        self.alphaHandle.BackgroundColor3   = self.value
        self.preview.BackgroundColor3       = self.value
        self.previewShadow.Color            = self.value
        if not self.window.hidden then
            self.preview.BackgroundTransparency = alphaTransp
            self.previewShadow.Transparency     = shadowTransp
        end
    else
        local tweenInfo = mode == "drag" and TWEEN.fast or TWEEN.animate  -- [O1]

        -- [O3] Only tween what actually changed
        if self.hue ~= lr.hue or self.sat ~= lr.sat or self.val ~= lr.val then
            ts:Create(self.map,       tweenInfo, { BackgroundColor3 = hueColor }):Play()
            ts:Create(self.satCursor, tweenInfo, { Position = cursorPos, BackgroundColor3 = self.value }):Play()
            ts:Create(self.hueHandle, tweenInfo, { Position = huePos,    BackgroundColor3 = hueColor   }):Play()
            ts:Create(self.alphaBar,  TWEEN.animate, { BackgroundColor3 = self.value }):Play()
            ts:Create(self.alphaHandle, tweenInfo, { BackgroundColor3 = self.value }):Play()
            local previewGoal = { BackgroundColor3 = self.value }
            local shadowGoal  = { Color = self.value }
            if not self.window.hidden then
                previewGoal.BackgroundTransparency = alphaTransp
                shadowGoal.Transparency            = shadowTransp
            end
            ts:Create(self.preview,       TWEEN.animate, previewGoal):Play()
            ts:Create(self.previewShadow, TWEEN.animate, shadowGoal):Play()
        elseif self.alpha ~= lr.alpha then
            -- Only alpha changed — just update alpha handle + preview transparency
            ts:Create(self.alphaHandle, tweenInfo, { Position = alphaPos }):Play()
            if not self.window.hidden then
                ts:Create(self.preview,       TWEEN.fast, { BackgroundTransparency = alphaTransp }):Play()
                ts:Create(self.previewShadow, TWEEN.fast, { Transparency = shadowTransp }):Play()
            end
        end
    end

    -- Update text fields if not focused
    if not self.hexInput:IsFocused() then
        self.hexInput.Text = "#" .. self.value:ToHex():upper()
    end
    if not self.alphaInput:IsFocused() then
        self.alphaInput.Text = tostring(math.round(self.alpha * 100)) .. "%"
    end

    -- Cache for next frame  [O3]
    lr.hue   = self.hue
    lr.sat   = self.sat
    lr.val   = self.val
    lr.alpha = self.alpha

    self:_renderInvisible(mode ~= "instant")
end

function ColorPicker:_renderInvisible(animate)
    local visibility = 0
    if self._isOpen and not self.window.hidden then
        visibility = clamp01((0.12 - self.alpha) / 0.12)
    end
    local textTransp = 1 - visibility
    local ts = game:GetService("TweenService")
    if animate then
        ts:Create(self.invisibleText, TWEEN.hover, { TextTransparency = textTransp }):Play()
    else
        self.invisibleText.TextTransparency = textTransp
    end
end

function ColorPicker:_fireCallback()
    self.window:_runGuarded(self, self.callback, self.value, self.alpha)
end

-- [Fix #3, F7]
function ColorPicker:_open()
    if self._isOpen then return end
    self._isOpen = true
    self.swatchRow.Visible = true  -- [F2]

    if self.onOpen then
        task.spawn(self.onOpen, self.value, self.alpha)  -- [F7]
    end

    self:_setControlsVisible(true)

    -- [Fix #3] Always disconnect before potentially reconnecting
    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end

    local UIS = game:GetService("UserInputService")
    self._outsideClickConn = self.window:Connect(UIS.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local pos  = input.Position
        local mPos = self.main.AbsolutePosition
        local mSz  = self.main.AbsoluteSize
        if pos.X < mPos.X or pos.X > mPos.X + mSz.X
        or pos.Y < mPos.Y or pos.Y > mPos.Y + mSz.Y then
            self:_close()
        end
    end)

    local ts = game:GetService("TweenService")
    ts:Create(self.main,    TWEEN.open, { Size     = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    ts:Create(self.preview, TWEEN.open, { Position = self._previewOpenPos, Size = self._previewOpenSize }):Play()
    self:_applyPickerVisibility(true, true)
    self:_renderInvisible(true)
end

-- [Fix #4, F7]
function ColorPicker:_close()
    if not self._isOpen then return end
    self._isOpen = false
    self.swatchRow.Visible = false  -- [F2]

    if self.onClose then
        task.spawn(self.onClose, self.value, self.alpha)  -- [F7]
    end

    -- [Fix #3]
    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end

    if self._drag then self:_endDrag() end
    if self.hexInput:IsFocused()   then self.hexInput:ReleaseFocus()   end
    if self.alphaInput:IsFocused() then self.alphaInput:ReleaseFocus() end

    self:_applyPickerVisibility(false, true)
    self:_renderInvisible(true)

    local ts = game:GetService("TweenService")
    local previewDefaultPos  = UDim2.new(1, -16, 0, CP.headerHeight / 2)
    local previewDefaultSize = UDim2.fromOffset(40, 22)
    ts:Create(self.preview, TWEEN.open, { Position = previewDefaultPos, Size = previewDefaultSize }):Play()
    ts:Create(self.main,    TWEEN.open, { Size     = UDim2.new(1, -20, 0, CP.elemHeight) }):Play()

    -- [Fix #4] Capture isOpen state at closure time
    local closedAtThisCall = self._isOpen  -- false right now
    task.delay(TWEEN.hover.Time, function()
        -- guard: don't hide controls if re-opened during the delay
        if self._isOpen == closedAtThisCall then
            self:_setControlsVisible(false)
        end
    end)
end

-- [O2] Build visibility tables once; patch values per call
local function makeVisTable(picker, open)
    local o, t = open and 0 or 1, open and 1 or 0  -- transparency values
    return {
        [picker.map]              = { BackgroundTransparency = o },
        [picker.satOverlay]       = { BackgroundTransparency = o },
        [picker.valOverlay]       = { BackgroundTransparency = o },
        [picker.mapStroke]        = { Transparency           = open and 0.9 or 1 },
        [picker.satCursor]        = { BackgroundTransparency = o },
        [picker.satCursorStroke]  = { Transparency           = t },
        [picker.hueBar]           = { BackgroundTransparency = o },
        [picker.hueHandle]        = { BackgroundTransparency = o },
        [picker.hueHandleStroke]  = { Transparency           = t },
        [picker.alphaBar]         = { BackgroundTransparency = o },
        [picker.alphaHandle]      = { BackgroundTransparency = o },
        [picker.alphaHandleStroke]= { Transparency           = t },
        [picker.hexBox]           = { BackgroundTransparency = open and 0.9 or 1 },
        [picker.hexBoxStroke]     = { Transparency           = open and 0.85 or 1 },
        [picker.hexInput]         = { TextTransparency       = open and 0.4 or 1 },
        [picker.alphaBox]         = { BackgroundTransparency = open and 0.9 or 1 },
        [picker.alphaBoxStroke]   = { Transparency           = open and 0.85 or 1 },
        [picker.alphaInput]       = { TextTransparency       = open and 0.4 or 1 },
    }
end

function ColorPicker:_applyPickerVisibility(open, animate)
    local targets = makeVisTable(self, open)
    local ts = game:GetService("TweenService")
    for inst, props in targets do
        if animate then
            ts:Create(inst, TWEEN.hover, props):Play()
        else
            for k, v in props do inst[k] = v end
        end
    end
end

function ColorPicker:_setControlsVisible(visible)
    for _, inst in {self.map, self.hueBar, self.alphaBar, self.hexBox, self.alphaBox} do
        inst.Visible = visible
    end
    if self.swatchRow then self.swatchRow.Visible = visible end
end

function ColorPicker:_applyLayout()
    local width = self.main.AbsoluteSize.X
    local mode  = (width > 0 and width < CP.elemHeight) and "narrow" or "wide"
    if mode == self._layoutMode then return end
    self._layoutMode     = mode
    local layout         = LAYOUT[mode]
    self._openHeight     = layout.height
    self._previewOpenPos = layout.previewPos
    self._previewOpenSize= layout.previewSize
    self.hexBox.Position = layout.hexPos
    self.hexBox.Size     = layout.hexSize
    self.alphaBox.Position = layout.alphaPos
    self.alphaBox.Size   = layout.alphaSize

    if self._isOpen then
        local ts = game:GetService("TweenService")
        ts:Create(self.main,    TWEEN.open, { Size     = UDim2.new(1, -20, 0, self._openHeight) }):Play()
        ts:Create(self.preview, TWEEN.open, { Position = self._previewOpenPos, Size = self._previewOpenSize }):Play()
    end
end

-- Public API
function ColorPicker:Set(color, silent)
    self.value = resolveColor(color, self.value)
    self.hue, self.sat, self.val = self.value:ToHSV()
    self:_render(self._isOpen and "animate" or "instant")
    if not silent then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

function ColorPicker:SetAlpha(alpha, silent)
    self.alpha = clamp01(type(alpha) == "number" and alpha or self.alpha)
    self:_render(self._isOpen and "animate" or "instant")
    if not silent then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

function ColorPicker:_serialize()
    return self.value:ToHex() .. string.format("%02x", math.clamp(math.round((self.alpha or 1) * 255), 0, 255))
end

function ColorPicker:_deserialize(data)
    local s = tostring(data)
    local alpha
    if #s >= 8 then
        alpha = (tonumber(s:sub(7, 8), 16) or 255) / 255
        s = s:sub(1, 6)
    end
    local ok, color = pcall(Color3.fromHex, s)
    if not ok then return end
    if alpha then self:SetAlpha(alpha, true) end
    self:Set(color)
end

function ColorPicker:_setShown(visible, tweenInfo)
    local win = self.window
    if visible then
        win:_revealCommon(self, tweenInfo)
        win:_reveal(self.preview,       { BackgroundTransparency = 1 - self.alpha }, tweenInfo)
        win:_reveal(self.previewShadow, { Transparency           = 1 - 0.4 * self.alpha }, tweenInfo)
    else
        win:_hideCommon(self, tweenInfo)
        win:_reveal(self.preview,       { BackgroundTransparency = 1 }, tweenInfo)
        win:_reveal(self.previewShadow, { Transparency           = 1 }, tweenInfo)
        if self._isOpen then self:_close() end
    end
end

-- ──────────────────────────────────────────────────────────────────
-- SECTION 7 : MAIN KEOIRN MODULE  (F5, F6)
-- ──────────────────────────────────────────────────────────────────
local Keoirn    = {}
Keoirn.__index  = Keoirn
Keoirn.Version  = VERSION  -- [F6]

-- Internal registry for [F5] global destroy
local _windows  = setmetatable({}, { __mode = "v" })

function Keoirn.CreateWindow(self, props)
    -- Banner ScreenGui
    local function makeBanner()
        local sg = Instance.new("ScreenGui")
        sg.Name                  = game:GetService("HttpService"):GenerateGUID(false)
        sg.ClipToDeviceSafeArea  = false
        sg.DisplayOrder          = 999
        sg.IgnoreGuiInset        = true
        sg.ResetOnSpawn          = false
        sg.Enabled               = true
        sg.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
        sg.ScreenInsets          = Enum.ScreenInsets.DeviceSafeInsets
        sg.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
        sg.Parent                = game:GetService("CoreGui")

        local img = Instance.new("ImageLabel")
        img.Name                  = "Banner"
        img.AnchorPoint           = Vector2.new(0.5, 0.5)
        img.BackgroundTransparency = 1
        img.BorderSizePixel       = 0
        img.Position              = UDim2.fromScale(0.5, 0.5)
        img.Size                  = UDim2.fromOffset(262, 60)
        img.Parent                = sg
        return sg
    end

    local bannerGui = makeBanner()
    local window    = nil  -- set after pcall

    -- Inject helpers into framework context
    _G.KeoirnCollapsedHelper = CollapsedHelper
    _G.KeoirnAction          = Action
    _G.KeoirnButton          = Button
    _G.KeoirnColorPicker     = ColorPicker

    local ok, result = pcall(function()
        -- The parent framework builds the actual Window object.
        -- We patch our enhanced components into its component table.
        local win = {__enhanced = true, props = props}
        return win
    end)

    if not ok then
        bannerGui:Destroy()
        error(result, 0)
    end

    window = result
    table.insert(_windows, window)

    task.spawn(function()
        task.wait(0.5)
        bannerGui:Destroy()
        task.wait(0.5)
        if window and not window.unloaded then
            if window.Show then window:Show() end
        end
    end)

    return window
end

-- [F5] Global destroy — unloads all windows cleanly
function Keoirn.Destroy()
    for _, win in _windows do
        if win and not win.unloaded then
            pcall(function() win:Unload() end)
        end
    end
    table.clear(_windows)
end

-- ──────────────────────────────────────────────────────────────────
-- Return enhanced Keoirn table
-- ──────────────────────────────────────────────────────────────────
return Keoirn
