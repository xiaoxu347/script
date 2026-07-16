-- Roblox 可调跳高 GUI
-- 独立执行脚本；重复执行会替换旧窗口。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local GUI_NAME = "AdjustableJumpGUI"
local MIN_VALUE = 0
local MAX_VALUE = 1000
local DEFAULT_VALUE = 50

local oldGui = LP:WaitForChild("PlayerGui"):FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local character
local humanoid
local enabled = true
local targetValue = DEFAULT_VALUE
local originalValue
local activeProperty = "JumpPower"
local connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function cleanup()
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function clampValue(value)
    value = tonumber(value) or targetValue
    return math.clamp(math.floor(value * 100 + 0.5) / 100, MIN_VALUE, MAX_VALUE)
end

local gui = create("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, LP.PlayerGui)

local panel = create("Frame", {
    Size = UDim2.fromOffset(310, 210),
    Position = UDim2.new(0.5, -155, 0.5, -105),
    BackgroundColor3 = Color3.fromRGB(17, 19, 26),
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)
addCorner(panel, 8)
create("UIStroke", {
    Color = Color3.fromRGB(64, 151, 226),
    Thickness = 1.5,
}, panel)

local titleBar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = Color3.fromRGB(25, 76, 139),
    BorderSizePixel = 0,
    Active = true,
}, panel)

create("TextLabel", {
    Size = UDim2.new(1, -48, 1, 0),
    Position = UDim2.fromOffset(11, 0),
    BackgroundTransparency = 1,
    Text = "可调跳高",
    TextColor3 = Color3.fromRGB(248, 250, 255),
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local closeButton = create("TextButton", {
    Size = UDim2.fromOffset(26, 26),
    Position = UDim2.new(1, -32, 0, 6),
    BackgroundColor3 = Color3.fromRGB(45, 54, 73),
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = Color3.fromRGB(235, 239, 247),
    TextSize = 12,
    Font = Enum.Font.GothamBold,
}, titleBar)
addCorner(closeButton, 5)

local statusLabel = create("TextLabel", {
    Size = UDim2.new(1, -22, 0, 26),
    Position = UDim2.fromOffset(11, 45),
    BackgroundTransparency = 1,
    Text = "正在等待角色...",
    TextColor3 = Color3.fromRGB(145, 169, 202),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local valueBox = create("TextBox", {
    Size = UDim2.fromOffset(120, 38),
    Position = UDim2.new(0.5, -60, 0, 73),
    BackgroundColor3 = Color3.fromRGB(27, 31, 42),
    BorderSizePixel = 0,
    Text = tostring(targetValue),
    PlaceholderText = "输入跳高数值",
    ClearTextOnFocus = false,
    TextColor3 = Color3.fromRGB(239, 243, 250),
    PlaceholderColor3 = Color3.fromRGB(110, 122, 143),
    TextSize = 18,
    Font = Enum.Font.Code,
}, panel)
addCorner(valueBox, 6)

local function makeAdjustButton(text, x, delta)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(62, 30),
        Position = UDim2.fromOffset(x, 119),
        BackgroundColor3 = Color3.fromRGB(38, 47, 64),
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(225, 232, 244),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, panel)
    addCorner(button, 5)
    button.MouseButton1Click:Connect(function()
        targetValue = clampValue(targetValue + delta)
        valueBox.Text = tostring(targetValue)
    end)
end

makeAdjustButton("-10", 11, -10)
makeAdjustButton("-1", 86, -1)
makeAdjustButton("+1", 161, 1)
makeAdjustButton("+10", 236, 10)

local toggleButton = create("TextButton", {
    Size = UDim2.fromOffset(138, 36),
    Position = UDim2.fromOffset(11, 160),
    BackgroundColor3 = Color3.fromRGB(47, 155, 93),
    BorderSizePixel = 0,
    Text = "持续锁定：开启",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 12,
    Font = Enum.Font.GothamMedium,
}, panel)
addCorner(toggleButton, 5)

local restoreButton = create("TextButton", {
    Size = UDim2.fromOffset(138, 36),
    Position = UDim2.fromOffset(161, 160),
    BackgroundColor3 = Color3.fromRGB(55, 65, 86),
    BorderSizePixel = 0,
    Text = "恢复原始数值",
    TextColor3 = Color3.fromRGB(235, 239, 247),
    TextSize = 12,
    Font = Enum.Font.GothamMedium,
}, panel)
addCorner(restoreButton, 5)

local function detectProperty(currentHumanoid)
    local ok, useJumpPower = pcall(function()
        return currentHumanoid.UseJumpPower
    end)
    if ok and useJumpPower == false then
        return "JumpHeight"
    end
    return "JumpPower"
end

local function applyValue()
    if not humanoid or not humanoid.Parent then return end
    pcall(function()
        humanoid[activeProperty] = targetValue
    end)
end

local function updateStatus()
    if not humanoid or not humanoid.Parent then
        statusLabel.Text = "正在等待角色..."
        return
    end
    local current = 0
    pcall(function() current = humanoid[activeProperty] end)
    statusLabel.Text = string.format(
        "%s | 当前 %.2f | 目标 %.2f%s",
        activeProperty,
        current,
        targetValue,
        enabled and " | 已锁定" or ""
    )
end

local function bindCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    if not humanoid then
        statusLabel.Text = "角色中未找到 Humanoid"
        return
    end

    activeProperty = detectProperty(humanoid)
    pcall(function()
        originalValue = humanoid[activeProperty]
    end)
    if originalValue == nil then originalValue = DEFAULT_VALUE end

    applyValue()
    updateStatus()
end

local function commitTextValue()
    targetValue = clampValue(valueBox.Text)
    valueBox.Text = tostring(targetValue)
    applyValue()
    updateStatus()
end

connect(valueBox.FocusLost, function()
    commitTextValue()
end)

connect(valueBox:GetPropertyChangedSignal("Text"), function()
    local filtered = valueBox.Text:gsub("[^%d%.%-]", "")
    if filtered ~= valueBox.Text then valueBox.Text = filtered end
end)

connect(toggleButton.MouseButton1Click, function()
    enabled = not enabled
    toggleButton.Text = enabled and "持续锁定：开启" or "持续锁定：关闭"
    toggleButton.BackgroundColor3 = enabled
        and Color3.fromRGB(47, 155, 93)
        or Color3.fromRGB(95, 70, 58)
    if enabled then applyValue() end
    updateStatus()
end)

connect(restoreButton.MouseButton1Click, function()
    if humanoid and humanoid.Parent and originalValue ~= nil then
        targetValue = clampValue(originalValue)
        valueBox.Text = tostring(targetValue)
        pcall(function()
            humanoid[activeProperty] = originalValue
        end)
    end
    enabled = false
    toggleButton.Text = "持续锁定：关闭"
    toggleButton.BackgroundColor3 = Color3.fromRGB(95, 70, 58)
    updateStatus()
end)

-- 标题栏拖动
local dragging = false
local dragStart
local startPosition

connect(titleBar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = panel.Position
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

connect(UserInputService.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

connect(closeButton.MouseButton1Click, function()
    cleanup()
    gui:Destroy()
end)

connect(LP.CharacterAdded, function(newCharacter)
    task.spawn(bindCharacter, newCharacter)
end)

connect(RunService.Heartbeat, function()
    if not gui.Parent then return end
    if enabled then applyValue() end
    updateStatus()
end)

task.spawn(bindCharacter, LP.Character or LP.CharacterAdded:Wait())