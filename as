local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenSvc   = game:GetService("TweenService")
local LocalPlayer= Players.LocalPlayer

-- ══════════════════════════════════════
--  状态变量
-- ══════════════════════════════════════
local speedMultiplier = 1.0   -- 当前倍速
local enabled         = false -- 是否启用
local hookedTracks    = {}    -- 已 hook 的 track → 原速映射
local heartbeatConn   = nil

-- ══════════════════════════════════════
--  核心：持续刷新所有动画速度
-- ══════════════════════════════════════
local function getAnimator(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return hum:FindFirstChildOfClass("Animator")
end

local function applySpeed()
    local character = LocalPlayer.Character
    local animator  = getAnimator(character)
    if not animator then return end

    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok then return end

    for _, track in ipairs(tracks) do
        pcall(function()
            track:AdjustSpeed(enabled and speedMultiplier or 1.0)
        end)
    end
end

local function startLoop()
    if heartbeatConn then return end
    heartbeatConn = RunService.Heartbeat:Connect(applySpeed)
end

local function stopLoop()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    -- 恢复所有动画为正常速度
    local character = LocalPlayer.Character
    local animator  = getAnimator(character)
    if animator then
        local ok, tracks = pcall(function()
            return animator:GetPlayingAnimationTracks()
        end)
        if ok then
            for _, track in ipairs(tracks) do
                pcall(function() track:AdjustSpeed(1.0) end)
            end
        end
    end
end

-- 角色重生时重新挂钩
LocalPlayer.CharacterAdded:Connect(function()
    if enabled then
        task.wait(0.5)
        startLoop()
    end
end)

-- ══════════════════════════════════════
--  GUI
-- ══════════════════════════════════════
local gui = Instance.new("ScreenGui", game:GetService("CoreGui"))
gui.Name           = "AnimSpeedGUI"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- 主面板
local panel = Instance.new("Frame", gui)
panel.Size                = UDim2.new(0, 260, 0, 220)
panel.Position            = UDim2.new(0, 20, 0, 200)
panel.BackgroundColor3    = Color3.fromRGB(15, 15, 20)
panel.BorderSizePixel     = 0
panel.Active              = true
panel.Draggable           = true
do local c = Instance.new("UICorner", panel); c.CornerRadius = UDim.new(0, 12) end
do local s = Instance.new("UIStroke", panel)
   s.Color = Color3.fromRGB(100, 180, 255); s.Thickness = 1.5 end

-- 标题栏
local titleBar = Instance.new("Frame", panel)
titleBar.Size             = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(20, 80, 180)
titleBar.BorderSizePixel  = 0
do local c = Instance.new("UICorner", titleBar); c.CornerRadius = UDim.new(0, 12) end
-- 填补下圆角
do local f = Instance.new("Frame", titleBar)
   f.Size = UDim2.new(1, 0, 0, 12); f.Position = UDim2.new(0, 0, 1, -12)
   f.BackgroundColor3 = Color3.fromRGB(20, 80, 180); f.BorderSizePixel = 0 end

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size                = UDim2.new(1, -44, 1, 0)
titleLbl.Position            = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text                = "⚡  动画加速器"
titleLbl.TextColor3          = Color3.fromRGB(255, 255, 255)
titleLbl.Font                = Enum.Font.GothamBold
titleLbl.TextSize             = 14
titleLbl.TextXAlignment       = Enum.TextXAlignment.Left

-- 收起按钮
local colBtn = Instance.new("TextButton", titleBar)
colBtn.Size             = UDim2.new(0, 28, 0, 28)
colBtn.Position         = UDim2.new(1, -32, 0, 4)
colBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
colBtn.Text             = "─"
colBtn.TextColor3       = Color3.fromRGB(200, 200, 200)
colBtn.Font             = Enum.Font.GothamBold
colBtn.TextSize          = 14
colBtn.BorderSizePixel  = 0
do local c = Instance.new("UICorner", colBtn); c.CornerRadius = UDim.new(0, 6) end

-- 内容区
local content = Instance.new("Frame", panel)
content.Size                = UDim2.new(1, -20, 1, -46)
content.Position            = UDim2.new(0, 10, 0, 42)
content.BackgroundTransparency = 1
do local l = Instance.new("UIListLayout", content)
   l.FillDirection = Enum.FillDirection.Vertical
   l.Padding = UDim.new(0, 10) end

-- ── 当前倍速显示 ──
local speedDisplay = Instance.new("TextLabel", content)
speedDisplay.Size                = UDim2.new(1, 0, 0, 28)
speedDisplay.BackgroundColor3    = Color3.fromRGB(22, 22, 32)
speedDisplay.TextColor3          = Color3.fromRGB(100, 210, 255)
speedDisplay.Font                = Enum.Font.GothamBold
speedDisplay.TextSize             = 16
speedDisplay.Text                = "倍速：1.0×"
speedDisplay.BorderSizePixel     = 0
do local c = Instance.new("UICorner", speedDisplay); c.CornerRadius = UDim.new(0, 8) end

-- ── 滑条区 ──
local sliderFrame = Instance.new("Frame", content)
sliderFrame.Size                = UDim2.new(1, 0, 0, 22)
sliderFrame.BackgroundTransparency = 1

-- 轨道
local track = Instance.new("Frame", sliderFrame)
track.Size             = UDim2.new(1, 0, 0, 6)
track.Position         = UDim2.new(0, 0, 0.5, -3)
track.BackgroundColor3 = Color3.fromRGB(50, 55, 80)
track.BorderSizePixel  = 0
do local c = Instance.new("UICorner", track); c.CornerRadius = UDim.new(1, 0) end

-- 已填充部分
local fill = Instance.new("Frame", track)
fill.Size             = UDim2.new(0, 0, 1, 0)  -- 初始0%
fill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
fill.BorderSizePixel  = 0
do local c = Instance.new("UICorner", fill); c.CornerRadius = UDim.new(1, 0) end

-- 拖拽按钮（手柄）
local knob = Instance.new("TextButton", sliderFrame)
knob.Size             = UDim2.new(0, 18, 0, 18)
knob.Position         = UDim2.new(0, -9, 0.5, -9)  -- 初始最左
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.Text             = ""
knob.BorderSizePixel  = 0
do local c = Instance.new("UICorner", knob); c.CornerRadius = UDim.new(1, 0) end
do local s = Instance.new("UIStroke", knob)
   s.Color = Color3.fromRGB(80, 160, 255); s.Thickness = 2 end

-- 滑条范围：1× ~ 10×，映射到 [0,1]
local SPEED_MIN, SPEED_MAX = 1.0, 10.0

local function setSliderRatio(ratio)
    ratio = math.clamp(ratio, 0, 1)
    speedMultiplier = SPEED_MIN + ratio * (SPEED_MAX - SPEED_MIN)
    speedMultiplier = math.floor(speedMultiplier * 10 + 0.5) / 10  -- 保留1位小数

    -- 更新UI
    local trackAbsSize = track.AbsoluteSize.X
    knob.Position = UDim2.new(0, ratio * trackAbsSize - 9, 0.5, -9)
    fill.Size     = UDim2.new(ratio, 0, 1, 0)
    speedDisplay.Text = string.format("倍速：%.1f×", speedMultiplier)
end

-- 初始化到 1×（ratio=0）
setSliderRatio(0)

-- 拖拽逻辑
local dragging = false
knob.MouseButton1Down:Connect(function()
    dragging = true
end)
game:GetService("UserInputService").InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
game:GetService("UserInputService").InputChanged:Connect(function(inp)
    if not dragging then return end
    if inp.UserInputType ~= Enum.UserInputType.MouseMovement
    and inp.UserInputType ~= Enum.UserInputType.Touch then return end

    local trackPos  = track.AbsolutePosition.X
    local trackSize = track.AbsoluteSize.X
    local mouseX    = inp.Position.X
    local ratio     = (mouseX - trackPos) / trackSize
    setSliderRatio(ratio)
end)

-- 点击轨道直接跳转
track.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        local trackPos  = track.AbsolutePosition.X
        local trackSize = track.AbsoluteSize.X
        local ratio     = (inp.Position.X - trackPos) / trackSize
        setSliderRatio(ratio)
    end
end)

-- ── 快捷倍速按钮行 ──
local presetRow = Instance.new("Frame", content)
presetRow.Size                = UDim2.new(1, 0, 0, 28)
presetRow.BackgroundTransparency = 1
do local l = Instance.new("UIListLayout", presetRow)
   l.FillDirection = Enum.FillDirection.Horizontal
   l.Padding       = UDim.new(0, 6) end

local presets = {1, 2, 3, 5, 10}
for _, v in ipairs(presets) do
    local btn = Instance.new("TextButton", presetRow)
    btn.Size             = UDim2.new(0, 38, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
    btn.TextColor3       = Color3.fromRGB(180, 210, 255)
    btn.Text             = v .. "×"
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize          = 13
    btn.BorderSizePixel  = 0
    do local c = Instance.new("UICorner", btn); c.CornerRadius = UDim.new(0, 6) end
    btn.MouseButton1Click:Connect(function()
        setSliderRatio((v - SPEED_MIN) / (SPEED_MAX - SPEED_MIN))
    end)
    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(50, 70, 120)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
    end)
end

-- ── 开关按钮 ──
local toggleBtn = Instance.new("TextButton", content)
toggleBtn.Size             = UDim2.new(1, 0, 0, 34)
toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
toggleBtn.TextColor3       = Color3.fromRGB(160, 200, 255)
toggleBtn.Text             = "▶  启用加速"
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize          = 14
toggleBtn.BorderSizePixel  = 0
do local c = Instance.new("UICorner", toggleBtn); c.CornerRadius = UDim.new(0, 8) end
do local s = Instance.new("UIStroke", toggleBtn)
   s.Color = Color3.fromRGB(60, 120, 220); s.Thickness = 1.2 end

local function refreshToggle()
    if enabled then
        toggleBtn.Text             = "⏸  已启用（点击关闭）"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 100, 50)
        toggleBtn.TextColor3       = Color3.fromRGB(120, 255, 160)
    else
        toggleBtn.Text             = "▶  启用加速"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
        toggleBtn.TextColor3       = Color3.fromRGB(160, 200, 255)
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    if enabled then
        startLoop()
    else
        stopLoop()
    end
    refreshToggle()
end)

toggleBtn.MouseEnter:Connect(function()
    if not enabled then
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 120)
    end
end)
toggleBtn.MouseLeave:Connect(function()
    refreshToggle()
end)

-- ── 收起/展开 ──
local collapsed = false
colBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    TweenSvc:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
        Size = collapsed and UDim2.new(0, 260, 0, 36) or UDim2.new(0, 260, 0, 220)
    }):Play()
    content.Visible = not collapsed
    colBtn.Text = collapsed and "□" or "─"
end)
