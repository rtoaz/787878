local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Mouse = LocalPlayer:GetMouse()

-- 提示
local msg = Instance.new("Message")
msg.Text = "脚本已启动 / 原作者：XTTT\n该版本为分支"
msg.Parent = Workspace
task.delay(3, function() msg:Destroy() end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirection = Vector3.new(0, 1, 0)
_G.controlledPart = nil
_G.anActivity = false
_G.fixedMode = false

-- 模拟半径
RunService.Heartbeat:Connect(function()
	pcall(function()
		sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
		sethiddenproperty(LocalPlayer, "MaxSimulationRadius", 1000)
	end)
end)

-- 控制函数
local function ProcessPart(v)
	if v == _G.controlledPart and v:IsA("BasePart") and not v.Anchored then
		pcall(function() v:SetNetworkOwner(LocalPlayer) end)
		if _G.processedParts[v] then
			local bv = _G.processedParts[v].bodyVelocity
			if bv and bv.Parent then
				bv.Velocity = _G.moveDirection.Unit * _G.floatSpeed
				return
			end
		end
		for _, x in pairs(v:GetChildren()) do
			if x:IsA("BodyVelocity") or x:IsA("BodyGyro") then x:Destroy() end
		end
		local bv = Instance.new("BodyVelocity", v)
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Velocity = _G.moveDirection.Unit * _G.floatSpeed

		local bg = Instance.new("BodyGyro", v)
		bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bg.P, bg.D, bg.CFrame = 1000, 100, v.CFrame

		_G.processedParts[v] = {bodyVelocity = bv, bodyGyro = bg}
	end
end

local function CleanupParts()
	for part, data in pairs(_G.processedParts) do
		pcall(function() part:SetNetworkOwner(nil) end)
		if data.bodyVelocity then data.bodyVelocity:Destroy() end
		if data.bodyGyro then data.bodyGyro:Destroy() end
	end
	_G.processedParts = {}
end

local function UpdateAllPartsVelocity()
	for part, data in pairs(_G.processedParts) do
		if data.bodyVelocity then
			data.bodyVelocity.Velocity = _G.moveDirection.Unit * _G.floatSpeed
		end
	end
end

local function RotatePart(axis, angle)
	if _G.controlledPart and _G.processedParts[_G.controlledPart] then
		local data = _G.processedParts[_G.controlledPart]
		if data.bodyGyro then
			local cf = _G.controlledPart.CFrame
			if axis == "X" then
				data.bodyGyro.CFrame = cf * CFrame.Angles(math.rad(angle), 0, 0)
			elseif axis == "Y" then
				data.bodyGyro.CFrame = cf * CFrame.Angles(0, math.rad(angle), 0)
			elseif axis == "Z" then
				data.bodyGyro.CFrame = cf * CFrame.Angles(0, 0, math.rad(angle))
			end
		end
	end
end

local function MarkControlledPart(part)
	if _G.controlledPart and _G.controlledPart:FindFirstChild("ControlHighlight") then
		_G.controlledPart.ControlHighlight:Destroy()
	end
	_G.controlledPart = part
	if part then
		local hl = Instance.new("SelectionBox")
		hl.Adornee = part
		hl.Color3 = Color3.fromRGB(0, 255, 255)
		hl.LineThickness = 0.05
		hl.Name = "ControlHighlight"
		hl.Parent = part
	end
end

-- 拖拽函数
local function makeDraggable(gui)
	local dragging, dragStart, startPos
	gui.Active = true
	gui.Selectable = true
	gui.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = gui.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			gui.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- GUI 创建
local function CreateGUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FlyingControlGUI"
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	gui.ResetOnSpawn = false

	-- 主按钮
	local main = Instance.new("TextButton")
	main.Size = UDim2.new(0, 120, 0, 50)
	main.Position = UDim2.new(1, -140, 0, 60)
	main.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	main.Text = "漂浮：关闭"
	main.TextColor3 = Color3.new(1, 1, 1)
	main.TextScaled = true
	main.Parent = gui
	makeDraggable(main)

	-- 面板开关
	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(0, 120, 0, 30)
	toggle.Position = UDim2.new(1, -140, 0, 120)
	toggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	toggle.Text = "控制面板"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.TextScaled = true
	toggle.Parent = gui
	makeDraggable(toggle)

	-- 控制面板
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 260, 0, 430)
	panel.Position = UDim2.new(1, -420, 0, 30)
	panel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	panel.BackgroundTransparency = 0.25
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	makeDraggable(panel)

	toggle.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)

	-- 速度显示
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.85, 0, 0, 30)
	lbl.Position = UDim2.new(0.075, 0, 0, 10)
	lbl.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextScaled = true
	lbl.Text = "速度: " .. tostring(_G.floatSpeed)
	lbl.Parent = panel

	-- 加速/减速
	local add = Instance.new("TextButton")
	add.Size = UDim2.new(0.4, 0, 0, 30)
	add.Position = UDim2.new(0.05, 0, 0, 50)
	add.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	add.Text = "+"
	add.TextColor3 = Color3.new(1, 1, 1)
	add.TextScaled = true
	add.Parent = panel

	local sub = Instance.new("TextButton")
	sub.Size = UDim2.new(0.4, 0, 0, 30)
	sub.Position = UDim2.new(0.55, 0, 0, 50)
	sub.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	sub.Text = "-"
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextScaled = true
	sub.Parent = panel

	-- 防旋转
	local fix = Instance.new("TextButton")
	fix.Size = UDim2.new(0.85, 0, 0, 30)
	fix.Position = UDim2.new(0.075, 0, 0, 90)
	fix.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	fix.Text = "防旋转：关闭"
	fix.TextColor3 = Color3.new(1, 1, 1)
	fix.TextScaled = true
	fix.Parent = panel

	-- 方向控制（上/下/前/后/左/右）
	local dirs = {
		{"上", Vector3.new(0, 1, 0), 0.4, 140},
		{"下", Vector3.new(0, -1, 0), 0.4, 210},
		{"左", Vector3.new(-1, 0, 0), 0.1, 175},
		{"右", Vector3.new(1, 0, 0), 0.7, 175},
		{"前", Vector3.new(0, 0, 1), 0.4, 175},
		{"后", Vector3.new(0, 0, -1), 0.4, 245},
	}
	for _, info in ipairs(dirs) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, 0, 0, 35)
		b.Position = UDim2.new(info[3], 0, 0, info[4])
		b.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		b.Text = info[1]
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextScaled = true
		b.Parent = panel
		b.MouseButton1Click:Connect(function()
			_G.moveDirection = info[2]
			UpdateAllPartsVelocity()
		end)
	end

	-- 旋转控制（左翻/右翻/上翻/下翻）
	local rots = {
		{"左翻", "Y", -15, 0.1, 300},
		{"右翻", "Y", 15, 0.7, 300},
		{"上翻", "X", -15, 0.4, 260},
		{"下翻", "X", 15, 0.4, 340},
	}
	for _, info in ipairs(rots) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, 0, 0, 35)
		b.Position = UDim2.new(info[4], 0, 0, info[5])
		b.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
		b.Text = info[1]
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextScaled = true
		b.Parent = panel
		b.MouseButton1Click:Connect(function()
			RotatePart(info[2], info[3])
		end)
	end

	-- 功能按钮逻辑
	main.MouseButton1Click:Connect(function()
		_G.anActivity = not _G.anActivity
		if _G.anActivity then
			main.Text = "漂浮：开启"
			main.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
			if _G.controlledPart then ProcessPart(_G.controlledPart) end
		else
			main.Text = "漂浮：关闭"
			main.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			CleanupParts()
		end
	end)

	add.MouseButton1Click:Connect(function()
		_G.floatSpeed = math.clamp(_G.floatSpeed + 5, 0, 100)
		lbl.Text = "速度: " .. _G.floatSpeed
		UpdateAllPartsVelocity()
	end)
	sub.MouseButton1Click:Connect(function()
		_G.floatSpeed = math.clamp(_G.floatSpeed - 5, 0, 100)
		lbl.Text = "速度: " .. _G.floatSpeed
		UpdateAllPartsVelocity()
	end)
	fix.MouseButton1Click:Connect(function()
		_G.fixedMode = not _G.fixedMode
		if _G.fixedMode then
			fix.Text = "防旋转：开启"
			fix.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		else
			fix.Text = "防旋转：关闭"
			fix.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		end
	end)

	-- 选中物体
	Mouse.Button1Down:Connect(function()
		local t = Mouse.Target
		if t and t:IsA("BasePart") and not t.Anchored then
			MarkControlledPart(t)
		end
	end)
end

-- 初始化
pcall(CreateGUI)

-- 心跳循环
RunService.Heartbeat:Connect(function()
	if _G.anActivity and _G.controlledPart then
		pcall(ProcessPart, _G.controlledPart)
	end
end)

print("控制物体飞行已加载完成😋")
