-- Roblox 客户端加速 / 防僵直 GUI
-- Studio：将全文放进 StarterPlayer > StarterPlayerScripts 的 LocalScript。
-- 默认速度 32；RightShift 显示/隐藏；标题右侧按钮折叠；× 彻底关闭。
-- v2：手机使用底部“备用移动”摇杆；输入恢复与角色状态恢复独立于游戏摇杆。
-- 客户端只能尝试修复本地状态，不能保证解除服务器或自定义控制器的锁定。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
assert(player, "请在 Roblox 客户端的 LocalScript 中运行")
local playerGui = player:WaitForChild("PlayerGui")
local GUI_NAME = "LocalSpeedRecoveryGui"
local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then
	local shutdown = oldGui:FindFirstChild("Shutdown")
	if shutdown and shutdown:IsA("BindableFunction") then
		shutdown:Invoke() -- 同步清理旧实例，避免重复执行后叠加更新循环。
	else
		oldGui:Destroy()
	end
end

local speed = 32
local speedEnabled = true
local recoveryEnabled = true
local inputRecoveryEnabled = true
local blockActions = false
local closed = false
local current = nil
local pendingCharacter = nil
local generation = 0
local connections = {}
local windowFocused = true
local touchDirection = Vector3.zero
local stickInput = nil
local renderBinding = GUI_NAME .. "Movement"

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local background = Color3.fromRGB(23, 27, 38)
local muted = Color3.fromRGB(162, 173, 194)
local foreground = Color3.fromRGB(239, 243, 252)
local accent = Color3.fromRGB(35, 126, 100)
local inactive = Color3.fromRGB(47, 55, 74)

local gui = make("ScreenGui", {
	Name = GUI_NAME, ResetOnSpawn = false, DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local shutdown = make("BindableFunction", { Name = "Shutdown" }, gui)
local host = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, gui)
local panel = make("Frame", {
	Size = UDim2.fromOffset(320, 438), Position = UDim2.fromOffset(20, 60),
	BackgroundColor3 = background, BorderSizePixel = 0,
}, host)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
local scale = make("UIScale", { Scale = 1 }, panel)
local title = make("TextLabel", {
	Size = UDim2.new(1, -88, 0, 44), Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1, Text = "加速 · 防僵直 v2", TextSize = 18,
	TextColor3 = foreground, Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left, Active = true,
}, panel)
local body = make("Frame", {
	Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 378),
	BackgroundTransparency = 1,
}, panel)

local function label(text, y, height)
	return make("TextLabel", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1, Text = text, TextSize = 13,
		TextColor3 = muted, Font = Enum.Font.Gotham, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
end

local function button(text, parent, position, size)
	local control = make("TextButton", {
		Text = text, Position = position, Size = size,
		BackgroundColor3 = inactive, BorderSizePixel = 0,
		TextColor3 = foreground, TextSize = 15, Font = Enum.Font.Gotham,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, control)
	return control
end

local minimize = button("−", panel, UDim2.new(1, -76, 0, 8), UDim2.fromOffset(30, 28))
local closeButton = button("×", panel, UDim2.new(1, -40, 0, 8), UDim2.fromOffset(30, 28))
label("移动速度（1–150 studs/s）", 0, 22)
local minus = button("−", body, UDim2.fromOffset(0, 28), UDim2.fromOffset(42, 36))
local speedBox = make("TextBox", {
	Position = UDim2.fromOffset(50, 28), Size = UDim2.new(1, -100, 0, 36),
	BackgroundColor3 = inactive, BorderSizePixel = 0, Text = tostring(speed),
	TextColor3 = foreground, TextSize = 18, Font = Enum.Font.Gotham,
	ClearTextOnFocus = false,
}, body)
make("UICorner", { CornerRadius = UDim.new(0, 7) }, speedBox)
local plus = button("+", body, UDim2.new(1, -42, 0, 28), UDim2.fromOffset(42, 36))
local speedButton = button("", body, UDim2.fromOffset(0, 76), UDim2.new(1, 0, 0, 36))
local recoveryButton = button("", body, UDim2.fromOffset(0, 120), UDim2.new(1, 0, 0, 36))
local inputButton = button("", body, UDim2.fromOffset(0, 164), UDim2.new(1, 0, 0, 36))
local animationButton = button("", body, UDim2.fromOffset(0, 208), UDim2.new(1, 0, 0, 36))
label("手机卡住时拖动底部「备用移动」。\n动作屏蔽会中断技能动画，默认关闭。", 250, 40)
local status = label("等待角色加载…", 292, 54)
label("拖动标题移动 · 顶部 − 折叠面板", 350, 24)

-- 不依赖 PlayerModule / 游戏自定义摇杆；多点触摸时只追踪本摇杆的手指。
local stick = make("Frame", {
	Name = "RecoveryJoystick", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(112, 112),
	BackgroundColor3 = inactive, BackgroundTransparency = 0.2,
	BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 5,
}, host)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, stick)
local stickKnob = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(42, 42), BackgroundColor3 = accent,
	BorderSizePixel = 0, ZIndex = 6,
}, stick)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, stickKnob)
local stickLabel = make("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	Text = "备用\n移动", TextColor3 = foreground, TextSize = 12,
	Font = Enum.Font.Gotham, ZIndex = 7,
}, stickKnob)

local function resetStick()
	stickInput = nil
	touchDirection = Vector3.zero
	stickKnob.Position = UDim2.fromScale(0.5, 0.5)
end

local function updateStick(input)
	local center = stick.AbsolutePosition + stick.AbsoluteSize / 2
	local delta = Vector2.new(input.Position.X, input.Position.Y) - center
	local radius = math.max(1, stick.AbsoluteSize.X / 2 - 21)
	local offset = delta.Magnitude > radius and delta.Unit * radius or delta
	stickKnob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	touchDirection = offset.Magnitude < 6 and Vector3.zero
		or Vector3.new(offset.X / radius, 0, offset.Y / radius)
end

local function startStick(input)
	if input.UserInputType == Enum.UserInputType.Touch and not stickInput
		and windowFocused and recoveryEnabled and inputRecoveryEnabled
		and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox() then
		stickInput = input
		updateStick(input)
	end
end
connect(stick.InputBegan, startStick)
connect(stickKnob.InputBegan, startStick)
connect(stickLabel.InputBegan, startStick)
connect(UserInputService.InputChanged, function(input)
	if input == stickInput then updateStick(input) end
end)
connect(UserInputService.InputEnded, function(input)
	if input == stickInput then resetStick() end
end)

local function refreshButtons()
	for _, entry in ipairs({
		{ speedButton, "加速", speedEnabled },
		{ recoveryButton, "防僵直 / 本地解锁", recoveryEnabled },
		{ inputButton, "独立输入 / 备用摇杆", inputRecoveryEnabled },
		{ animationButton, "屏蔽动作动画", blockActions },
	}) do
		entry[1].Text = entry[2] .. (entry[3] and "：开启" or "：关闭")
		entry[1].BackgroundColor3 = entry[3] and accent or inactive
	end
	stick.Visible = UserInputService.TouchEnabled and recoveryEnabled and inputRecoveryEnabled
	if not stick.Visible then resetStick() end
end

-- Core 的枚举值是 1000，不能用 Priority.Value >= Action.Value 判断！
local actionPriorities = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}
local recoveryStates = {
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Seated] = true,
}

local function releaseMovement(record)
	if record and record.injectedInput then
		if record.humanoid.Parent then record.humanoid:Move(Vector3.zero, false) end
		record.injectedInput = false
	end
end

local function movementInput()
	if not windowFocused or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end
	if stickInput then return touchDirection end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	local direction = Vector3.new(x, 0, z)
	return direction.Magnitude > 1 and direction.Unit or direction
end

local function applyMovement()
	local record = current
	if closed or not record then return end
	local humanoid = record.humanoid
	if not recoveryEnabled or not inputRecoveryEnabled or not humanoid.Parent
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
		or humanoid.SeatPart ~= nil or not workspace.CurrentCamera then
		releaseMovement(record)
		return
	end
	local direction = movementInput()
	if direction.Magnitude > 0 then
		humanoid:Move(direction, true)
		record.injectedInput = true
	else
		-- 只清除本脚本留下的移动命令，平时保留游戏原摇杆。
		releaseMovement(record)
	end
end

local function stopActions()
	if not blockActions or not current or current.humanoid.Health <= 0 then
		return
	end
	local animator = current.humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if actionPriorities[track.Priority] and track.IsPlaying then
				track:Stop(0.1) -- 短暂淡出，保留 Core / Idle / Movement。
			end
		end
	end
end

local function restoreSpeed(record)
	if record and record.humanoid.Parent and record.lastSpeed ~= nil then
		-- 其他脚本已经修改的数值不再用旧值覆盖。
		if record.humanoid.WalkSpeed == record.lastSpeed then
			record.humanoid.WalkSpeed = record.baseSpeed
		end
		record.lastSpeed = nil
	end
end

local function restoreRecovery(record)
	releaseMovement(record)
	if record and record.humanoid.Parent and record.savedRotation ~= nil then
		if record.humanoid.AutoRotate then
			record.humanoid.AutoRotate = record.savedRotation
		end
		record.savedRotation = nil
	end
	if record and record.humanoid.Parent then
		if record.savedEvaluation ~= nil then
			if record.humanoid.EvaluateStateMachine then
				record.humanoid.EvaluateStateMachine = record.savedEvaluation
			end
			record.savedEvaluation = nil
		end
		for state, wasEnabled in pairs(record.savedStates) do
			if record.humanoid:GetStateEnabled(state) then
				record.humanoid:SetStateEnabled(state, wasEnabled)
			end
		end
		table.clear(record.savedStates)
	end
end

local function attachCharacter(character)
	if closed then return end
	generation += 1
	local token = generation
	pendingCharacter = character
	restoreSpeed(current)
	restoreRecovery(current)
	resetStick()
	current = nil
	status.Text = "等待角色加载…"
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if closed or token ~= generation or player.Character ~= character then
		return
	end
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		status.Text = "未找到标准角色；自定义角色需要单独适配。"
		return
	end
	current = {
		character = character, humanoid = humanoid, root = root,
		baseSpeed = humanoid.WalkSpeed, lastSpeed = nil,
		savedRotation = nil,
		savedEvaluation = nil, savedStates = {}, injectedInput = false,
		stuckTime = 0,
		parts = root:GetConnectedParts(true), partsTimer = 0,
		lastRepair = "就绪", lastRepairTime = 0,
	}
end

local function setSpeed(value)
	if value and value == value and math.abs(value) < math.huge then
		speed = math.clamp(math.floor(value + 0.5), 1, 150)
	end
	speedBox.Text = tostring(speed)
end
connect(speedBox.FocusLost, function() setSpeed(tonumber(speedBox.Text)) end)
connect(minus.Activated, function() setSpeed(speed - 4) end)
connect(plus.Activated, function() setSpeed(speed + 4) end)
connect(speedButton.Activated, function()
	speedEnabled = not speedEnabled
	if not speedEnabled then restoreSpeed(current) end
	refreshButtons()
end)
connect(recoveryButton.Activated, function()
	recoveryEnabled = not recoveryEnabled
	if not recoveryEnabled then
		restoreRecovery(current)
		if not speedEnabled then restoreSpeed(current) end
	end
	refreshButtons()
end)
connect(inputButton.Activated, function()
	inputRecoveryEnabled = not inputRecoveryEnabled
	if not inputRecoveryEnabled then releaseMovement(current) end
	refreshButtons()
end)
connect(animationButton.Activated, function()
	blockActions = not blockActions
	stopActions()
	refreshButtons()
end)

local function cleanup(destroyGui)
	if closed then return end
	closed = true
	generation += 1
	RunService:UnbindFromRenderStep(renderBinding)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	restoreSpeed(current)
	restoreRecovery(current)
	current = nil
	-- 解除固定/倒地属于即时恢复，不会在退出时重新固定或击倒角色。
	if destroyGui then gui:Destroy() end
end
shutdown.OnInvoke = function() cleanup(true) end
connect(closeButton.Activated, function() cleanup(true) end)
connect(gui.Destroying, function() cleanup(false) end)
if typeof(script) == "Instance" then
	connect(script.Destroying, function() cleanup(true) end)
end

local function clampPanel()
	local available = host.AbsoluteSize
	scale.Scale = math.min(1, math.max(0.1, (available.X - 16) / 320), math.max(0.1, (available.Y - 16) / 438))
	local width = 320 * scale.Scale
	local height = (body.Visible and 438 or 44) * scale.Scale
	panel.Position = UDim2.fromOffset(
		math.clamp(panel.Position.X.Offset, 0, math.max(0, available.X - width)),
		math.clamp(panel.Position.Y.Offset, 0, math.max(0, available.Y - height))
	)
end
connect(minimize.Activated, function()
	body.Visible = not body.Visible
	panel.Size = UDim2.fromOffset(320, body.Visible and 438 or 44)
	minimize.Text = body.Visible and "−" or "+"
	clampPanel()
end)
connect(host:GetPropertyChangedSignal("AbsoluteSize"), clampPanel)

local dragInput, dragStart, panelStart
connect(title.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragInput, dragStart, panelStart = input, input.Position, panel.Position
	end
end)
connect(UserInputService.InputChanged, function(input)
	if not dragInput then return end
	local mouseDrag = dragInput.UserInputType == Enum.UserInputType.MouseButton1
	if (mouseDrag and input.UserInputType == Enum.UserInputType.MouseMovement) or input == dragInput then
		local delta = input.Position - dragStart
		panel.Position = UDim2.fromOffset(panelStart.X.Offset + delta.X, panelStart.Y.Offset + delta.Y)
		clampPanel()
	end
end)
connect(UserInputService.InputEnded, function(input)
	if input == dragInput then dragInput = nil end
end)
connect(UserInputService.WindowFocusReleased, function()
	windowFocused = false
	dragInput = nil
	resetStick()
	releaseMovement(current)
end)
connect(UserInputService.WindowFocused, function() windowFocused = true end)
connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), function()
	if GuiService.MenuIsOpen then resetStick(); releaseMovement(current) end
end)
connect(UserInputService.TextBoxFocused, function() resetStick(); releaseMovement(current) end)
connect(UserInputService.InputBegan, function(input, processed)
	if not processed and not UserInputService:GetFocusedTextBox() and input.KeyCode == Enum.KeyCode.RightShift then
		gui.Enabled = not gui.Enabled
		dragInput = nil
		resetStick()
	end
end)

connect(player.CharacterAdded, attachCharacter)
connect(player.CharacterRemoving, function(character)
	if pendingCharacter == character then
		generation += 1
		pendingCharacter = nil
	end
	if current and current.character == character then
		restoreSpeed(current)
		restoreRecovery(current)
		resetStick()
		current = nil
		status.Text = "等待重生…"
	end
end)

local animationTimer = 0
local statusTimer = 0

local function repair(record, reason)
	record.lastRepair = reason
	record.lastRepairTime = os.clock()
end

-- 晚于默认控制器发送一次；物理模拟前再发送一次，减少移动被其他本地脚本覆盖。
RunService:BindToRenderStep(renderBinding, Enum.RenderPriority.Last.Value + 1, applyMovement)
connect(RunService.PreSimulation, function(dt)
	local record = current
	if not record or not record.humanoid.Parent or not record.root.Parent then return end
	local humanoid = record.humanoid
	local state = humanoid:GetState()
	if humanoid.Health <= 0 or state == Enum.HumanoidStateType.Dead then
		releaseMovement(record)
		resetStick()
		status.Text = "角色已死亡，等待重生…"
		return
	end
	-- 记录未受本脚本控制时的正常速度，供关闭加速后恢复。
	if not speedEnabled and record.lastSpeed == nil and humanoid.WalkSpeed > 0 then
		record.baseSpeed = humanoid.WalkSpeed
	end
	if speedEnabled then
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
			record.lastSpeed = speed
		end
	end
	if recoveryEnabled and humanoid.SeatPart == nil then
		-- 技能可能只设置 Sit=true，并没有真正坐在座位上。
		if humanoid.Sit then humanoid.Sit = false; repair(record, "解除坐姿锁定") end
		if humanoid.WalkSpeed <= 0 then
			local fallback = record.baseSpeed > 0 and record.baseSpeed or 16
			humanoid.WalkSpeed = speedEnabled and speed or fallback
			record.lastSpeed = humanoid.WalkSpeed
			repair(record, "恢复移动速度")
		end
		if humanoid.PlatformStand then
			humanoid.PlatformStand = false
			repair(record, "解除平台站立")
		end
		if not humanoid.EvaluateStateMachine then
			if record.savedEvaluation == nil then record.savedEvaluation = false end
			humanoid.EvaluateStateMachine = true
			repair(record, "恢复角色物理状态机")
		end
		if not humanoid.AutoRotate then
			if record.savedRotation == nil then record.savedRotation = humanoid.AutoRotate end
			humanoid.AutoRotate = true
		end
		-- 身体其他刚性连接部件被 Anchored 也会固定整个人。
		record.partsTimer += dt
		if record.partsTimer >= 0.25 then
			record.partsTimer = 0
			record.parts = record.root:GetConnectedParts(true)
		end
		if record.root.Anchored then
			record.root.Anchored = false
			repair(record, "解除根部件固定")
		end
		for _, part in ipairs(record.parts) do
			if part:IsDescendantOf(record.character) and part.Anchored then
				part.Anchored = false
				repair(record, "解除身体部件固定")
			end
		end
		for _, nextState in ipairs({ Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Freefall }) do
			if not humanoid:GetStateEnabled(nextState) then
				if record.savedStates[nextState] == nil then record.savedStates[nextState] = false end
				humanoid:SetStateEnabled(nextState, true)
				repair(record, "重新启用移动状态")
			end
		end
		if recoveryStates[state] then
			local nextState = humanoid.FloorMaterial == Enum.Material.Air
				and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Running
			humanoid:ChangeState(nextState)
			repair(record, "退出 " .. state.Name)
		end
	end
	applyMovement()
	local velocity = record.root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if record.injectedInput and horizontalSpeed < 0.75 and humanoid.SeatPart == nil then
		record.stuckTime += dt
	else
		record.stuckTime = 0
	end
	-- 限频检查也能捕获 Play() 之后才设置 Priority 的动画。
	animationTimer += dt
	if animationTimer >= 0.1 then
		animationTimer = 0
		stopActions()
	end
	statusTimer += dt
	if statusTimer >= 0.25 then
		statusTimer = 0
		local detail = os.clock() - record.lastRepairTime < 2 and record.lastRepair or "本地状态正常"
		if record.stuckTime > 0.75 then
			detail = "输入已送达仍不动：可能碰撞或游戏锁定"
		elseif record.injectedInput then
			detail = "独立输入已送达 · " .. detail
		end
		status.Text = string.format("设定 %.0f / 实际 %.1f · %s\n%s", humanoid.WalkSpeed, horizontalSpeed, humanoid:GetState().Name, detail)
	end
end)

refreshButtons()
clampPanel()
if player.Character then task.spawn(attachCharacter, player.Character) end
