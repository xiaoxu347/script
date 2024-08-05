local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or game:GetService("Players"):GetPlayerFromCharacter(Players.LocalPlayer.Character)
local Character = LocalPlayer.Character or LocalPlayer.Character:FindFirstChild("HumanoidRootPart").Parent
 
local MT = getrawmetatable(game)
local OldIndex = MT. __index
local OldNamecall = MT.__namecall
 
setreadonly(MT, false)
MT.__index = newcclosure(function(H, HP, T, D) --Bypasses some anti FTI checks. (uBlubble, Xelvidant, etc.)
	if not checkcaller() and getnamecallmethod() then
		if tostring(H) == "Humanoid" and tostring(HP) == "Health" then
			return 0
		end
		if tostring(T) == "Position" and tostring(D) == "Magnitude" then
			return 0
		end
	end
	return OldIndex(H, HP)
end)
 
local StarterGui = game:GetService("StarterGui")
local DevConsoleHook --Bypasses all dev console disablers.
DevConsoleHook = hookfunc(StarterGui.SetCore, newcclosure(function(Self, ...)
	local Args = table.pack(...)
	if Self == StarterGui then
		if Args[1] == "DevConsoleVisible" then
			Args[1] = nil
		end
	end
end))
 
--Bypasses script execution.
for _,v in next, getconnections(game:GetService("LogService").MessageOut) do
	v:Disable()
end
for _,v in next, getconnections(game:GetService("ScriptContext").Error) do
	v:Disable()
end
 
game:GetService("ScriptContext"):SetTimeout(0.1)
setreadonly(MT, true) 
 
local UNIATTEMPT = true
local VisualizerTransparencyAmount = 0.4
local UIS = game:GetService("UserInputService")
 
-----------------------------
--bypass 2
local customtheme = "Dark"
local reachsize = 5
local dmgEnabled = true
local multiplier = 0
local visualizerEnabled
local reachType = "Sphere"
 
local Material = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()
local UI = Material.Load({
	Title = "Sebs Darkside",
	Style = 0,
	SizeX = 471,
	SizeY = 269,
	Theme = customtheme
})
--page bypass stuffj
 
UIS.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.X then
		game:GetService("CoreGui")["Sebs Darkside"].Enabled = not game:GetService("CoreGui")["Sebs Darkside"].Enabled
	end	
end)
 
--new page which is gonna be circle reach & stuffghj
 
local Page2 = UI.New({
	Title = "Reach/Circle"
})
local Page3 = UI.New({
	Title = "Auto Clicker"
})
local Page4 = UI.New({
	Title = "Themes"
})
 
local Page5 = UI.New({
	Title = "Visuaizer"
})
 
 
 
local ThemePage = Page4.Dropdown({
	Text = "Themes",
	Callback = function(value)
		customtheme = value
		Text = customtheme
	end,
	Options = {"Dark", "Light", "Mocha", "Aqua", "Jester"}
})
local ac_on
local ac_off
local AcOnText = Page3.TextField({
	Text = "Keybind for autoclicker on",
	Callback = function(value)
		print(ac_on)
		ac_on = value
	end,
})
local AcOffText = Page3.TextField({
	Text = "Keybind for autoclicker off ",
	Callback = function(value)
		print(ac_off)
		ac_off = value
	end,
})
 
local Mouse = game.Players.LocalPlayer:GetMouse()
Mouse.KeyDown:Connect(function(key)
	if key == ac_on then
		_G.AutoClicker = true
		while _G.AutoClicker do
			wait()
			pcall(function()
				local Sword = game:GetService'Players'.LocalPlayer.Character:FindFirstChildOfClass'Tool'
				Sword:Activate()
			end)
		end
	end
end)
local Mouse = game.Players.LocalPlayer:GetMouse()
Mouse.KeyDown:Connect(function(key)
	if key == ac_off then
		_G.AutoClicker = false
		while _G.AutoClicker do
			wait()
			pcall(function()
				local Sword = game:GetService'Players'.LocalPlayer.Character:FindFirstChildOfClass'Tool'
				Sword:Activate()
			end)
		end
	end
end)
 
local CircleSize = Page2.Slider({
	Text = "Circle Size",
	Callback = function(value)
		reachsize = value
		reachsize = tonumber(value)
	end,
	Min = 0,
	Max = 50,
	Def = 4
})
local sparemultiplier = 1
local dmgEnabled = Page2.Toggle({
	Text = "Enable DMG",
	Callback = function(value)
		dmgEnabled = value
	end,
})
local dmgSlider = Page2.Slider({
	Text = "DMG Amount",
	Callback = function(value)
		multiplier = value
		multiplier = tonumber(value)
		sparemultiplier = value
		sparemultiplier = tonumber(value)
	end,
	Min = 0.4,
	Max = 20,
	Def = 1,
 
})
local ShapeDropdown = Page5.Dropdown({
	Text = "Visualizer Shape",
	Callback = function(value)
		reachType = value
	end,
	Options = {"Sphere", "Block"}
})
local ve = Page5.Toggle({
	Text = "Visualizer",
	Callback = function(value)
		visualizerEnabled = value
	end,
})
 
 
local visualizer = Instance.new("Part")
 
visualizer.Color = Color3.new(1, 0.968627, 0)
visualizer.Transparency = VisualizerTransparencyAmount
visualizer.Anchored = true
visualizer.CanCollide = false
visualizer.CastShadow = false
visualizer.Size = Vector3.new(0.5,0.5,0.5)
visualizer.BottomSurface = Enum.SurfaceType.Glue
visualizer.TopSurface = Enum.SurfaceType.Glue
local TweenService = game:GetService("TweenService")
local part = visualizer
local TweeningInformation = TweenInfo.new(
	1,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	753475938457843579348573,
	true,
	0
)
 
local PartProperties = {
	Color = Color3.fromRGB(255,0,0)
}
 
local Tween = TweenService:Create(part,TweeningInformation,PartProperties)
Tween:Play()
local Red = Color3.new(1, 0, 0.0156863)
local Blue = Color3.new(0, 0.180392, 1)
local Black = Color3.new(0, 0, 0)
local White = Color3.new(1, 1, 1)
local config = "Reset"
local colorrvalue = 0
local colorgvalue = 0
local colorbvalue = 0
 
 
 
local VConfigs = Page5.Dropdown({
	Text = "Configs For Visualizer",
	Callback = function(value)
		config = value
	end,
	Options = {"Sebs Config", "CWare Config", "Blizzy Config", "Reset"}
})
--fti script
local plr = game.Players.LocalPlayer
local function onHit(hit,handle)
	local victim = hit.Parent:FindFirstChildOfClass("Humanoid")
	if victim and victim.Parent.Name ~= game.Players.LocalPlayer.Name then
		if dmgEnabled then
 
			for _,v in pairs(hit.Parent:GetChildren()) do
				if v:IsA("BasePart") then
					for i = 1, multiplier do
						firetouchinterest(v,handle,0)
						firetouchinterest(v,handle,1)
						firetouchinterest(v,handle,0)
					end
				end
			end
		else
			firetouchinterest(hit,handle,0)
			firetouchinterest(hit,handle,1)
		end
	end
end
 
local function getWhiteList()
	local wl = {}
	for _,v in pairs(game.Players:GetPlayers()) do
		if v ~= plr then
			local char = v.Character
			if char then
				for _,q in pairs(char:GetChildren()) do
					if q:IsA("BasePart") then
						table.insert(wl,q)
					end
				end
			end
		end
	end
	return wl
end
 
game:GetService("RunService").RenderStepped:connect(function()
	local s = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
	if not s then visualizer.Parent = nil end
	if s then
		local handle = s:FindFirstChild("Handle") or s:FindFirstChildOfClass("Part")
		if handle then
			if visualizerEnabled then
				visualizer.Parent = workspace
			else
				visualizer.Parent = nil
			end
			local reach = tonumber(reachsize)
 
			if reach then
				if reachType == "Sphere" then
					if config == "CWare Config" then
						visualizer.Shape = Enum.PartType.Ball
						visualizer.Material = Enum.Material.Plastic
						visualizer.Color = Color3.new(1, 0, 0)
						visualizer.Transparency = 0.005459344392
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Reset" then
						visualizer.Shape = Enum.PartType.Ball
						visualizer.Material = Enum.Material.ForceField
						visualizer.Color = Color3.new(1, 0.933333, 0)
						visualizer.Transparency = VisualizerTransparencyAmount
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Blizzy Config" then
						visualizer.Shape = Enum.PartType.Ball
						visualizer.Material = Enum.Material.SmoothPlastic
						visualizer.Color = Color3.new(0.00784314, 0.454902, 1)
						visualizer.Transparency = 0.4
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Sebs Config" then
						visualizer.Shape = Enum.PartType.Ball
						visualizer.Material = Enum.Material.Asphalt
						visualizer.Color = Color3.new(0.105882, 0.745098, 0.0313725)
						visualizer.Transparency = 0.8
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					end
					for _,v in pairs(game.Players:GetPlayers()) do
						local hrp = v.Character and v.Character:FindFirstChild("HumanoidRootPart")
						if hrp and handle then
							local mag = (hrp.Position-handle.Position).magnitude
							if mag <= reach then
								onHit(hrp,handle)
							end
						end
					end
				elseif reachType == "Block" then
					local origin = (handle.CFrame*CFrame.new(0,0,-2)).p
					local ray = Ray.new(origin,handle.CFrame.lookVector*-reach)
					local p,pos = workspace:FindPartOnRayWithWhitelist(ray,getWhiteList())
					visualizer.Shape = Enum.PartType.Block
					visualizer.Size = Vector3.new(reach,reach,reach)
					visualizer.CFrame = handle.CFrame
					visualizer.CastShadow = false
					visualizer.Name = math.random()
					visualizer.Color = Color3.new(colorrvalue,colorgvalue,colorbvalue)
					visualizer.Transparency = VisualizerTransparencyAmount
					if config == "CWare Config" then
						visualizer.Shape = Enum.PartType.Block
						visualizer.Material = Enum.Material.Plastic
						visualizer.Color = Color3.new(1, 0, 0)
						visualizer.Transparency = 0
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Reset" then
						visualizer.Shape = Enum.PartType.Block
						visualizer.Material = Enum.Material.ForceField
						visualizer.Color = Color3.new(0.984314, 1, 0)
						visualizer.Transparency = VisualizerTransparencyAmount
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Blizzy Config" then
						visualizer.Shape = Enum.PartType.Block
						visualizer.Material = Enum.Material.SmoothPlastic
						visualizer.Color = Color3.new(0.00784314, 0.454902, 1)
						visualizer.Transparency = 0.4
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					elseif config == "Sebs Config" then
						visualizer.Shape = Enum.PartType.Block
						visualizer.Material = Enum.Material.Asphalt
						visualizer.Color = Color3.new(0.105882, 0.745098, 0.0313725)
						visualizer.Transparency = 0.8
						visualizer.Size = Vector3.new(reach,reach,reach)
						visualizer.CFrame = handle.CFrame
						visualizer.CastShadow = false
						visualizer.Name = math.random()
					end
					if p then
						onHit(p,handle)
					else
						for _,v in pairs(handle:GetTouchingParts()) do
							onHit(v,handle)
						end
					end
 
 
				end
			end
		end
	end
end)
