local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Mouse = LocalPlayer:GetMouse()

-- 提示
local msg = Instance.new("Message")
msg.Text = "脚本已启动 / 作者：XTTT"
msg.Parent = Workspace
task.delay(3, function() msg:Destroy() end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirection = Vector3.new(0, 0, 0)
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

-- 处理零件漂浮
local function ProcessPart(v)
	if v == _G.controlledPart and v:IsA("BasePart") and not v.Anchored then
		pcall(function() v:SetNetworkOwner(LocalPlayer) end)

		if _G.processedParts[v] then
			local bv = _G.processedParts[v].bodyVelocity
			if bv and bv.Parent then
				bv.Velocity = _G.moveDirection * _G.floatSpeed
				return
			end
		end

		for _, x in pairs(v:GetChildren()) do
			if x:IsA("BodyVelocity") or x:IsA("BodyGyro") then
				x:Destroy()
			end
		end

		local bv = Instance.new("BodyVelocity", v)
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Velocity = _G.moveDirection * _G.floatSpeed

		local bg = Instance.new("BodyGyro", v)
		bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bg.P, bg.D, bg.CFrame = 1000, 100, v.CFrame

		_G.processedParts[v] = {bodyVelocity = bv, bodyGyro = bg}
	end
end

-- 清理
local function CleanupParts()
	for part, data in pairs(_G.processedParts) do
		pcall(function() part:SetNetworkOwner(nil) end)
		if data.bodyVelocity then data.bodyVelocity:Destroy() end
		if data.bodyGyro then data.bodyGyro:Destroy() end
	end
	_G.processedParts = {}
end

-- 摄像机方向计算
local function CameraDirection(forward, right, up)
	local camCF = Camera.CFrame
	local f = camCF.LookVector
	local r = camCF.RightVector
	local u = camCF.UpVector
	local dir = Vector3.new()
	if forward ~= 0 then dir += f * forward end
	if right ~= 0 then dir += r * right end
	if up ~= 0 then dir += u * up end
	return dir.Unit
end

-- 旋转
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

-- 标记控制物体
local function MarkControlledPart(part)
	if _G.controlledPart and _G.controlledPart:FindFirstChild("ControlHighlight") then
		_G.controlledPart.ControlHighlight:Destroy()
	end
	_G.controlledPart = part
	if part then
		local hl = Instance.new("SelectionBox")
		hl.Name = "ControlHighlight"
		hl.Adornee = part
		hl.Color3 = Color3.fromRGB(0, 255, 255)
		hl.LineThickness = 0.05
		hl.Parent = part
	end
end

-- 拖拽函数
local function makeDraggable(gui)
	gui.Active = true
	gui.Selectable = true
	local dragging, startPos, dragStart

	local function update(input)
		local delta = input.Position - dragStart
		gui.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end

	gui.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = gui.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
end

-- 创建GUI
local function CreateGUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FlyingControlGUI"
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- 样式函数
	local function styleButton(btn, color)
		btn.BackgroundColor3 = color or Color3.fromRGB(40, 120, 255)
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.AutoButtonColor = true
		btn.BorderSizePixel = 0
		local corner = Instance.new("UICorner", btn)
		corner.CornerRadius = UDim.new(0, 8)
	end

	-- 主开关按钮
	local main = Instance.new("TextButton")
	main.Size = UDim2.new(0, 120, 0, 50)
	main.Position = UDim2.new(1, -130, 0, 60)
	main.Text = "漂浮：关闭"
	styleButton(main, Color3.fromRGB(255, 80, 80))
	main.Parent = gui
	makeDraggable(main)

	-- 面板开关按钮
	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(0, 120, 0, 35)
	toggle.Position = UDim2.new(1, -130, 0, 120)
	toggle.Text = "控制面板"
	styleButton(toggle, Color3.fromRGB(90, 160, 255))
	toggle.Parent = gui
	makeDraggable(toggle)

	-- 控制面板
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 270, 0, 430)
	panel.Position = UDim2.new(1, -420, 0, 40)
	panel.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	panel.BackgroundTransparency = 0.15
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	makeDraggable(panel)
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

	toggle.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)

	-- 速度标签
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.85, 0, 0, 35)
	lbl.Position = UDim2.new(0.075, 0, 0, 10)
	lbl.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = "速度: " .. tostring(_G.floatSpeed)
	lbl.Parent = panel
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)

	-- 加减速
	local add = Instance.new("TextButton")
	add.Size = UDim2.new(0.4, 0, 0, 35)
	add.Position = UDim2.new(0.05, 0, 0, 55)
	add.Text = "+"
	styleButton(add)
	add.Parent = panel

	local sub = Instance.new("TextButton")
	sub.Size = UDim2.new(0.4, 0, 0, 35)
	sub.Position = UDim2.new(0.55, 0, 0, 55)
	sub.Text = "-"
	styleButton(sub)
	sub.Parent = panel

	-- 防旋转
	local fix = Instance.new("TextButton")
	fix.Size = UDim2.new(0.85, 0, 0, 35)
	fix.Position = UDim2.new(0.075, 0, 0, 100)
	fix.Text = "防旋转：关闭"
	styleButton(fix, Color3.fromRGB(255, 80, 80))
	fix.Parent = panel

	-- 方向移动按钮（基于摄像机方向）
	local dirs = {
		{"上", 0, 0, 1, 0.4, 150},
		{"下", 0, 0, -1, 0.4, 250},
		{"左", 0, -1, 0, 0.1, 200},
		{"右", 0, 1, 0, 0.7, 200},
		{"前", 1, 0, 0, 0.4, 200},
		{"后", -1, 0, 0, 0.4, 300},
	}
	for _, d in ipairs(dirs) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, 0, 0, 40)
		b.Position = UDim2.new(d[5], 0, 0, d[6])
		b.Text = d[1]
		styleButton(b, Color3.fromRGB(90, 160, 255))
		b.Parent = panel
		b.MouseButton1Click:Connect(function()
			_G.moveDirection = CameraDirection(d[2], d[3], d[4])
		end)
	end

	-- 旋转按钮
	local rots = {
		{"左翻", "Y", -15, 0.1, 350},
		{"右翻", "Y", 15, 0.7, 350},
		{"上翻", "X", -15, 0.4, 320},
		{"下翻", "X", 15, 0.4, 380},
	}
	for _, r in ipairs(rots) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, 0, 0, 35)
		b.Position = UDim2.new(r[4], 0, 0, r[5])
		b.Text = r[1]
		styleButton(b, Color3.fromRGB(255, 170, 0))
		b.Parent = panel
		b.MouseButton1Click:Connect(function()
			RotatePart(r[2], r[3])
		end)
	end

	-- 主按钮
	main.MouseButton1Click:Connect(function()
		_G.anActivity = not _G.anActivity
		if _G.anActivity then
			main.Text = "漂浮：开启"
			styleButton(main, Color3.fromRGB(80, 255, 80))
			if _G.controlledPart then ProcessPart(_G.controlledPart) end
		else
			main.Text = "漂浮：关闭"
			styleButton(main, Color3.fromRGB(255, 80, 80))
			CleanupParts()
		end
	end)

	-- 调速
	add.MouseButton1Click:Connect(function()
		_G.floatSpeed = math.clamp(_G.floatSpeed + 5, 0, 100)
		lbl.Text = "速度: " .. _G.floatSpeed
	end)
	sub.MouseButton1Click:Connect(function()
		_G.floatSpeed = math.clamp(_G.floatSpeed - 5, 0, 100)
		lbl.Text = "速度: " .. _G.floatSpeed
	end)

	-- 防旋转开关
	fix.MouseButton1Click:Connect(function()
		_G.fixedMode = not _G.fixedMode
		if _G.fixedMode then
			fix.Text = "防旋转：开启"
			styleButton(fix, Color3.fromRGB(80, 255, 80))
		else
			fix.Text = "防旋转：关闭"
			styleButton(fix, Color3.fromRGB(255, 80, 80))
		end
	end)

	-- 点击选择控制物体
	Mouse.Button1Down:Connect(function()
		local t = Mouse.Target
		if t and t:IsA("BasePart") and not t.Anchored then
			MarkControlledPart(t)
		end
	end)
end

-- 初始化
pcall(CreateGUI)

-- 主循环
RunService.Heartbeat:Connect(function()
	if _G.anActivity and _G.controlledPart then
		pcall(ProcessPart, _G.controlledPart)
	end
end)

print("控制物体飞行已加载完成😋")
