--[[
    ╔══════════════════════════════════════════════════════╗
    ║       KEOIRN USAGE EXAMPLE — by zurai02             ║
    ║  Paste into your executor. Run client-side.         ║
    ╚══════════════════════════════════════════════════════╝

    This file shows every component, every new feature,
    and several real-world patterns.

    LOAD ORDER:
        1.  Keoirn_Enhanced.lua  (or the original loader URL)
        2.  This file

    Quick start:
        local Keoirn = loadstring(game:HttpGet("YOUR_URL"))()
        -- then paste everything below
]]

-- ──────────────────────────────────────────────────────
-- 1. LOAD THE LIBRARY
-- ──────────────────────────────────────────────────────
local Keoirn = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Zeoirn/keoirn/refs/heads/main/Keoirn.lua",
    true
))()

-- Print version  [NEW FEATURE F6]
print("Keoirn version:", Keoirn.Version)

-- ──────────────────────────────────────────────────────
-- 2. CREATE A WINDOW
-- ──────────────────────────────────────────────────────
local Window = Keoirn:CreateWindow({
    Name        = "zurai02's Hub",       -- title bar text
    SubTitle    = "v2.0 Enhanced",       -- subtitle below title
    Theme       = "Dark",                -- "Dark" | "Light" | "Aqua" etc.
    ShowIcon    = true,                  -- show icon when minimised
    ShowName    = "zurai02 Hub",         -- text on minimised pill
    ConfigFolder = "zurai02Hub",         -- auto-saves flags to this folder
})

-- ──────────────────────────────────────────────────────
-- 3. ACTIONS (top-right icon buttons)
-- ──────────────────────────────────────────────────────

-- [NEW] Actions now support tooltip=  (F4)
Window:CreateAction({
    Name     = "Discord",
    Icon     = "rbxassetid://7733658504",
    Tooltip  = "Join Discord",          -- [F4] shows label on hover
    Callback = function()
        setclipboard("https://discord.gg/example")
        Window:Notify({ Title = "Copied!", Content = "Discord invite copied." })
    end,
})

Window:CreateAction({
    Name     = "GitHub",
    Icon     = "rbxassetid://7733964370",
    Tooltip  = "GitHub repo",           -- [F4]
    Callback = function()
        setclipboard("https://github.com/zurai02")
    end,
})

-- ──────────────────────────────────────────────────────
-- 4. TABS
-- ──────────────────────────────────────────────────────
local TabMain    = Window:CreateTab({ Name = "Main",    Icon = "rbxassetid://4483345998" })
local TabVisuals = Window:CreateTab({ Name = "Visuals", Icon = "rbxassetid://4483345998" })
local TabMisc    = Window:CreateTab({ Name = "Misc",    Icon = "rbxassetid://4483345998" })
local TabDebug   = Window:CreateTab({ Name = "Debug",   Icon = "rbxassetid://4483345998" })

-- ──────────────────────────────────────────────────────
-- 5. MAIN TAB — basic components
-- ──────────────────────────────────────────────────────
local SectionPlayer = TabMain:CreateSection({ Name = "Player" })

-- Toggle
local speedEnabled = false
local speedToggle = TabMain:CreateToggle({
    Name     = "Speed Hack",
    Default  = false,
    Flag     = "SpeedEnabled",          -- auto-saved to ConfigFolder
    Callback = function(state)
        speedEnabled = state
        local char = game.Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.WalkSpeed = state and 50 or 16
        end
    end,
})

-- Slider
local speedSlider = TabMain:CreateSlider({
    Name    = "Walk Speed",
    Min     = 16,
    Max     = 200,
    Default = 50,
    Flag    = "WalkSpeed",
    Callback = function(val)
        local char = game.Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and speedEnabled then
            char.Humanoid.WalkSpeed = val
        end
    end,
})

-- Button — normal
TabMain:CreateButton({
    Name     = "Reset Character",
    Callback = function()
        game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"):ChangeState(
            Enum.HumanoidStateType.Dead
        )
    end,
})

-- [NEW] Button with Disabled prop  (F3)
local lockedBtn = TabMain:CreateButton({
    Name     = "Admin Only (Disabled)",
    Disabled = true,                    -- [F3] greyed out, unclickable
    Callback = function()
        print("This runs only when re-enabled programmatically")
    end,
})

-- Re-enable it after 5 seconds (example of runtime control)
task.delay(5, function()
    lockedBtn:SetDisabled(false)        -- [F3] enable at runtime
    Window:Notify({ Title = "Unlocked", Content = "Admin button is now active." })
end)

-- [NEW] Button with Cooldown  (F8)
TabMain:CreateButton({
    Name     = "Fire Remote (3s cooldown)",
    Cooldown = 3,                       -- [F8] auto-disables for 3 seconds after each click
    Callback = function()
        -- fire your remote here
        print("Remote fired!")
    end,
})

-- Keybind
TabMain:CreateKeybind({
    Name     = "Toggle Menu",
    Default  = Enum.KeyCode.RightShift,
    Flag     = "MenuKey",
    Callback = function()
        Window:ToggleHide()
    end,
})

-- Input
TabMain:CreateInput({
    Name        = "Custom Name",
    PlaceHolder = "Enter your name...",
    Flag        = "CustomName",
    Callback    = function(text)
        print("Name set to:", text)
    end,
})

-- Dropdown
TabMain:CreateDropdown({
    Name    = "Game Mode",
    Options = { "Normal", "Tryhard", "Troll", "Spectate" },
    Default = "Normal",
    Flag    = "GameMode",
    Callback = function(selected)
        print("Mode:", selected)
    end,
})

-- ──────────────────────────────────────────────────────
-- 6. VISUALS TAB — ColorPicker with new features
-- ──────────────────────────────────────────────────────
local SectionChams = TabVisuals:CreateSection({ Name = "Chams" })

-- [NEW] ColorPicker with OnOpen, OnClose callbacks (F7)
-- [NEW] ColorPicker with custom Swatches (F2)
-- [NEW] Copy-to-clipboard button appears on hover (F1) — built-in
local chamColor = Color3.fromRGB(255, 80, 80)
local chamAlpha = 1

local picker = TabVisuals:CreateColorPicker({
    Name    = "Cham Color",
    Color   = chamColor,
    Alpha   = 1,
    Flag    = "ChamColor",

    -- [F2] Custom swatch row (8 presets + save-current)
    Swatches = {
        Color3.fromRGB(255, 80,  80),   -- red
        Color3.fromRGB(255, 180, 60),   -- orange
        Color3.fromRGB(80,  220, 80),   -- green
        Color3.fromRGB(60,  160, 255),  -- blue
        Color3.fromRGB(220, 80,  220),  -- purple
        Color3.fromRGB(255, 255, 255),  -- white
        Color3.fromRGB(0,   0,   0),    -- black
        Color3.fromRGB(255, 215, 0),    -- gold
    },

    -- [F7] lifecycle callbacks
    OnOpen = function(color, alpha)
        print("Color picker opened — current:", color:ToHex(), "alpha:", alpha)
    end,
    OnClose = function(color, alpha)
        print("Color picker closed  — final:  ", color:ToHex(), "alpha:", alpha)
    end,

    Callback = function(color, alpha)
        chamColor = color
        chamAlpha = alpha
        -- apply to chams here
        print(string.format("Cham: #%s  alpha: %d%%", color:ToHex():upper(), math.round(alpha * 100)))
    end,
})

-- Programmatic color change example
TabVisuals:CreateButton({
    Name     = "Set Cham to Cyan",
    Callback = function()
        picker:Set(Color3.fromRGB(0, 255, 255))   -- updates picker + fires callback
    end,
})

TabVisuals:CreateButton({
    Name     = "Set Alpha to 50%%",
    Callback = function()
        picker:SetAlpha(0.5)
    end,
})

-- Smart-input examples (all valid in the hex field):
--   #FF5050      hex 6-digit
--   #F50         hex 3-digit  [Fix #10]
--   rgb(255,80,80)
--   hsv(0,100,100)
--   hsl(0,100,50)
--   red           named colour

-- ──────────────────────────────────────────────────────
-- 7. MISC TAB — stats, progress, console, text, divider
-- ──────────────────────────────────────────────────────
local SectionInfo = TabMisc:CreateSection({ Name = "Info" })

-- Stat (read-only display)
local fpsStat = TabMisc:CreateStat({
    Name  = "FPS",
    Value = "60",
})

-- Update FPS every second
task.spawn(function()
    local RS = game:GetService("RunService")
    while task.wait(1) do
        local fps = math.round(1 / RS.RenderStepped:Wait())
        fpsStat:Set(tostring(fps))
    end
end)

-- Progress bar
local loadProgress = TabMisc:CreateProgress({
    Name    = "Load Progress",
    Default = 0,
    Max     = 100,
})

-- Animate it on load
task.spawn(function()
    for i = 1, 100 do
        task.wait(0.03)
        loadProgress:Set(i)
    end
end)

-- Text label
TabMisc:CreateText({
    Name = "Made with ♥ by zurai02",
})

-- Divider
TabMisc:CreateDivider()

-- Console (scrollable log output)
local console = TabMisc:CreateConsole({
    Name = "Log",
})
console:Log("Script loaded!")
console:Log("Version: " .. tostring(Keoirn.Version))
console:Warn("This is a warning line")
console:Error("This is an error line")

-- ──────────────────────────────────────────────────────
-- 8. DEBUG TAB — testing new features live
-- ──────────────────────────────────────────────────────
TabDebug:CreateButton({
    Name     = "Print Config Flags",
    Callback = function()
        -- Keoirn saves flags automatically; this reads them back
        for flag, value in Window:GetFlags() do
            print(flag, "=", tostring(value))
        end
    end,
})

-- [NEW F5] Destroy everything cleanly
TabDebug:CreateButton({
    Name     = "Destroy Hub (F5)",
    Callback = function()
        Window:Notify({
            Title   = "Unloading",
            Content = "Destroying all windows in 2s...",
        })
        task.delay(2, function()
            Keoirn.Destroy()   -- [F5] destroys all registered windows
        end)
    end,
})

-- Toggle disable on the locked button example
TabDebug:CreateToggle({
    Name     = "Unlock Admin Button",
    Default  = false,
    Callback = function(state)
        lockedBtn:SetDisabled(not state)  -- [F3]
    end,
})

-- ──────────────────────────────────────────────────────
-- 9. TOAST / NOTIFY EXAMPLES
-- ──────────────────────────────────────────────────────
-- Notify appears in the corner; Toast appears inline
task.delay(1, function()
    Window:Notify({
        Title   = "Welcome, zurai02!",
        Content = "Hub loaded. Use RightShift to toggle.",
        Duration = 5,
    })
end)

-- ──────────────────────────────────────────────────────
-- 10. POPUP EXAMPLE
-- ──────────────────────────────────────────────────────
TabMisc:CreateButton({
    Name     = "Confirm Delete Save",
    Callback = function()
        Window:Popup({
            Title   = "Delete Save?",
            Content = "This will erase your saved config.",
            Options = {
                { Name = "Delete", Callback = function()
                    print("Save deleted.")
                end },
                { Name = "Cancel", Callback = function()
                    print("Cancelled.")
                end },
            },
        })
    end,
})

-- ──────────────────────────────────────────────────────
-- DONE — Hub is live!
-- ──────────────────────────────────────────────────────
print("[zurai02 Hub] Loaded successfully!")
