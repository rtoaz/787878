local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- 初始化提示
local msg = Instance.new("Message")
msg.Text = "脚本已启动 / 作者：XTTT\n该版本为分支"
msg.Parent = Workspace
task.delay(3, function() msg:Destroy() end)

-- 等待加载
repeat task.wait() until game:IsLoaded()
local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirection = Vector3.new(0, 1, 0)
_G.controlledPart = nil
_G.anActivity = false
_G.fixedMode = false

-- 设置模拟半径
RunService.Heartbeat:Connect(function()
    pcall(function()
        sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
        sethiddenproperty(LocalPlayer, "MaxSimulationRadius", 1000)
    end)
end)

-- 主处理函数
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

        for _, x in next, v:GetChildren() do
            if x:IsA("BodyVelocity") or x:IsA("BodyGyro") or x:IsA("BodyForce") then
                x:Destroy()
            end
        end

        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bodyVelocity.Velocity = _G.moveDirection.Unit * _G.floatSpeed
        bodyVelocity.Parent = v

        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bodyGyro.P = 1000
        bodyGyro.D = 100
        bodyGyro.CFrame = v.CFrame
        bodyGyro.Parent = v

        _G.processedParts[v] = {bodyVelocity = bodyVelocity, bodyGyro = bodyGyro}
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
        if _G.fixedMode and data.bodyGyro then
            data.bodyGyro.CFrame = part.CFrame
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
        hl.Name = "ControlHighlight"
        hl.Adornee = part
        hl.Color3 = Color3.fromRGB(0, 0, 255)
        hl.LineThickness = 0.05
        hl.Parent = part
    end
end

-- 拖动函数
local function makeDraggable(guiObject)
    local dragging, dragInput, dragStart, startPos
    local function update(input)
        local delta = input.Position - dragStart
        guiObject.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
    guiObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement) then
            update(input)
        end
    end)
end

-- GUI创建函数
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "FlyingControlGUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    -- 主开关按钮
    local mainBtn = Instance.new("TextButton")
    mainBtn.Size = UDim2.new(0, 120, 0, 50)
    mainBtn.Position = UDim2.new(1, -130, 0, 50)
    mainBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainBtn.Text = "漂浮：关闭"
    mainBtn.TextColor3 = Color3.new(1, 1, 1)
    mainBtn.Parent = gui
    makeDraggable(mainBtn)

    -- 面板开关按钮
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 110)
    panelToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    panelToggle.Text = "控制面板"
    panelToggle.TextColor3 = Color3.new(1, 1, 1)
    panelToggle.Parent = gui
    makeDraggable(panelToggle)

    -- 控制面板
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 220, 0, 360)
    panel.Position = UDim2.new(1, -360, 0, 10)
    panel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    panel.BackgroundTransparency = 0.3
    panel.Active = true
    panel.Visible = false
    panel.Parent = gui
    makeDraggable(panel)

    panelToggle.MouseButton1Click:Connect(function()
        panel.Visible = not panel.Visible
    end)

    -- 内容框
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(0.85, 0, 0, 30)
    speedLabel.Position = UDim2.new(0.075, 0, 0, 10)
    speedLabel.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
    speedLabel.Parent = panel

    -- 加速/减速
    local upBtn = Instance.new("TextButton")
    upBtn.Size = UDim2.new(0.4, 0, 0, 30)
    upBtn.Position = UDim2.new(0.05, 0, 0, 50)
    upBtn.Text = "+"
    upBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    upBtn.TextColor3 = Color3.new(1, 1, 1)
    upBtn.Parent = panel

    local downBtn = Instance.new("TextButton")
    downBtn.Size = UDim2.new(0.4, 0, 0, 30)
    downBtn.Position = UDim2.new(0.55, 0, 0, 50)
    downBtn.Text = "-"
    downBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    downBtn.TextColor3 = Color3.new(1, 1, 1)
    downBtn.Parent = panel

    -- 防旋转开关
    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85, 0, 0, 30)
    fixBtn.Position = UDim2.new(0.075, 0, 0, 100)
    fixBtn.Text = "防旋转: 关闭"
    fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    fixBtn.TextColor3 = Color3.new(1, 1, 1)
    fixBtn.Parent = panel

    -- 按钮事件
    mainBtn.MouseButton1Click:Connect(function()
        _G.anActivity = not _G.anActivity
        if _G.anActivity then
            mainBtn.Text = "漂浮：开启"
            mainBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            if _G.controlledPart then ProcessPart(_G.controlledPart) end
        else
            mainBtn.Text = "漂浮：关闭"
            mainBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            CleanupParts()
        end
    end)

    upBtn.MouseButton1Click:Connect(function()
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 0, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)
    downBtn.MouseButton1Click:Connect(function()
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 0, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)

    fixBtn.MouseButton1Click:Connect(function()
        _G.fixedMode = not _G.fixedMode
        if _G.fixedMode then
            fixBtn.Text = "防旋转: 开启"
            fixBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            fixBtn.Text = "防旋转: 关闭"
            fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    -- 鼠标点击选中物体
    local mouse = LocalPlayer:GetMouse()
    mouse.Button1Down:Connect(function()
        local t = mouse.Target
        if t and t:IsA("BasePart") and not t.Anchored then
            MarkControlledPart(t)
        end
    end)
end

-- 运行GUI
pcall(CreateMobileGUI)

-- 循环漂浮逻辑
RunService.Heartbeat:Connect(function()
    if _G.anActivity and _G.controlledPart then
        pcall(ProcessPart, _G.controlledPart)
    end
end)

print("控制物体飞行已加载😋")
