local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- 显示启动消息
local message = Instance.new("Message")
message.Text = "脚本已启动/创作者XTTT\n该版本为分支"
message.Parent = Workspace
delay(3, function()
    message:Destroy()
end)

-- 等待游戏加载完成
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- 等待本地玩家加载
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10 -- 默认漂浮速度
_G.moveDirection = Vector3.new(0, 1, 0) -- 默认向上移动
_G.controlledPart = nil -- 当前控制的零件
_G.controlMode = false -- 控制模式状态
_G.anActivity = false -- 漂浮功能状态
_G.useAlternativeMethod = false -- 是否使用替代方法
_G.fixedMode = _G.fixedMode or false

-- 设置模拟半径
local function setupSimulationRadius()
    local success, err = pcall(function()
        RunService.Heartbeat:Connect(function()
            pcall(function()
                sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
                sethiddenproperty(LocalPlayer, "MaxSimulationRadius", 1000)
            end)
        end)
    end)
    
    if not success then
        warn("模拟半径设置失败: " .. tostring(err))
    end
end

setupSimulationRadius()

-- 替代方法：使用TweenService进行移动（适用于某些限制BodyVelocity的游戏）
local function ProcessPartWithTween(v)
    if v == _G.controlledPart and v:IsA("Part") and not v.Anchored then
        -- 清除现有的Tween
        if _G.processedParts[v] and _G.processedParts[v].tween then
            _G.processedParts[v].tween:Cancel()
        end
        
        -- 创建新的Tween
        local targetPosition = v.Position + (_G.moveDirection.Unit * _G.floatSpeed * 0.1)
        local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        local tween = TweenService:Create(v, tweenInfo, {Position = targetPosition})
        tween:Play()
        
        _G.processedParts[v] = {
            tween = tween,
            lastUpdate = tick()
        }
    end
end

-- 处理零件函数
local function ProcessPart(v)
    if _G.useAlternativeMethod then
        ProcessPartWithTween(v)
        return
    end
    
    if v == _G.controlledPart and v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") and not v.Parent:FindFirstChild("Head") then
        -- 设置网络所有权给本地玩家，以允许客户端模拟物理
        pcall(function()
            v:SetNetworkOwner(LocalPlayer)
        end)
        
        if _G.processedParts[v] then
            local existingBV = _G.processedParts[v].bodyVelocity
            if existingBV and existingBV.Parent then
                local finalVelocity = _G.moveDirection.Unit * _G.floatSpeed
                if existingBV.Velocity ~= finalVelocity then
                    existingBV.Velocity = finalVelocity
                end
                return
            else
                _G.processedParts[v] = nil
            end
        end
        
        for _, x in next, v:GetChildren() do
            if x:IsA("BodyAngularVelocity") or x:IsA("BodyForce") or x:IsA("BodyGyro") or 
               x:IsA("BodyPosition") or x:IsA("BodyThrust") or x:IsA("BodyVelocity") or
               x:IsA("Torque") then
                x:Destroy()
            end
        end
        
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Parent = v
        bodyVelocity.Velocity = _G.moveDirection.Unit * _G.floatSpeed
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)  -- 增加MaxForce以处理更大零件
        
        -- 添加固定旋转的陀螺仪（在需要时由GUI开关控制）
        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Parent = v
        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)  -- 增加MaxTorque
        bodyGyro.P = 1000
        bodyGyro.D = 100
        bodyGyro.CFrame = v.CFrame
        
        _G.processedParts[v] = { 
            bodyVelocity = bodyVelocity,
            bodyGyro = bodyGyro
        }
    end
end

local function ProcessAllParts()
    if _G.anActivity and _G.controlledPart then
        ProcessPart(_G.controlledPart)
    end
end

-- 清理所有零件
local function CleanupParts()
    for part, data in pairs(_G.processedParts) do
        -- 恢复网络所有权给服务器
        pcall(function()
            part:SetNetworkOwner(nil)
        end)
        if data.bodyVelocity then
            data.bodyVelocity:Destroy()
        end
        if data.bodyGyro then
            data.bodyGyro:Destroy()
        end
        if data.tween then
            data.tween:Cancel()
        end
    end
    _G.processedParts = {}
end

-- 更新零件速度
local function UpdateAllPartsVelocity()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = _G.moveDirection.Unit * _G.floatSpeed
        end
        if _G.fixedMode and part and part.Parent then
            pcall(function()
                part.RotVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end)
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro.CFrame = part.CFrame
                data.bodyGyro.P = 5000
                data.bodyGyro.D = 500
                data.bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            end
        end
    end
end

-- 旋转控制函数
local function RotatePart(axis, angle)
    if _G.controlledPart and _G.processedParts[_G.controlledPart] then
        local data = _G.processedParts[_G.controlledPart]
        if data.bodyGyro and data.bodyGyro.Parent then
            local currentCFrame = _G.controlledPart.CFrame
            local rotationCFrame
            
            if axis == "X" then
                rotationCFrame = CFrame.Angles(math.rad(angle), 0, 0)
            elseif axis == "Y" then
                rotationCFrame = CFrame.Angles(0, math.rad(angle), 0)
            elseif axis == "Z" then
                rotationCFrame = CFrame.Angles(0, 0, math.rad(angle))
            end
            
            data.bodyGyro.CFrame = currentCFrame * rotationCFrame
        end
    end
end

-- 标记控制的零件
local function MarkControlledPart(part)
    -- 移除旧标记
    if _G.controlledPart and _G.controlledPart:FindFirstChild("ControlHighlight") then
        _G.controlledPart.ControlHighlight:Destroy()
    end
    
    -- 清理旧零件的物理效果
    if _G.controlledPart and _G.processedParts[_G.controlledPart] then
        local data = _G.processedParts[_G.controlledPart]
        if data.bodyVelocity then
            data.bodyVelocity:Destroy()
        end
        if data.bodyGyro then
            data.bodyGyro:Destroy()
        end
        if data.tween then
            data.tween:Cancel()
        end
        -- 恢复网络所有权
        pcall(function()
            _G.controlledPart:SetNetworkOwner(nil)
        end)
        _G.processedParts[_G.controlledPart] = nil
    end
    
    -- 设置新控制的零件
    _G.controlledPart = part
    
    -- 添加新标记
    if part then
        local highlight = Instance.new("SelectionBox")
        highlight.Name = "ControlHighlight"
        highlight.Adornee = part
        highlight.Color3 = Color3.fromRGB(0, 0, 255) -- 蓝色
        highlight.LineThickness = 0.05
        highlight.Parent = part
        
        print("已控制: " .. part:GetFullName())
        
        -- 如果漂浮功能开启，为新零件添加物理效果
        if _G.anActivity then
            ProcessPart(part)
        end
    else
        print("已取消控制")
    end
end

-- 更稳健的可拖动实现（来自 new.lua 风格）
local function makeDraggable(guiObject)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    local function update(input)
        local delta = input.Position - dragStart
        guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    guiObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
            dragInput = input

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    guiObject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

-- 创建手机/屏幕友好的 GUI（改成 new.lua 风格）
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false

    -- 主开关按钮（右上）
    local mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 50)
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui

    makeDraggable(mainButton)

    -- 打开控制面板按钮（靠主按钮下方）
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 120)
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    panelToggle.TextColor3 = Color3.new(1,1,1)
    panelToggle.Parent = screenGui
    makeDraggable(panelToggle)

    -- 控制面板（侧边）
    local controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 220, 0, 360)
    controlPanel.Position = UDim2.new(1, -360, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.Active = true
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    panelToggle.MouseButton1Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
    end)

    -- 内容容器
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,0,1,0)
    content.BackgroundTransparency = 1
    content.Parent = controlPanel

    -- 速度显示
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(0.85,0,0,30)
    speedLabel.Position = UDim2.new(0.075,0,0,10)
    speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
    speedLabel.BackgroundColor3 = Color3.fromRGB(80,80,80)
    speedLabel.TextColor3 = Color3.new(1,1,1)
    speedLabel.TextScaled = true
    speedLabel.Parent = content

    -- 加速按钮（+）
    local speedUp = Instance.new("TextButton")
    speedUp.Size = UDim2.new(0.4,0,0,30)
    speedUp.Position = UDim2.new(0.05,0,0,50)
    speedUp.Text = "+"
    speedUp.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    speedUp.TextColor3 = Color3.new(1,1,1)
    speedUp.Parent = content

    -- 减速按钮（-）
    local speedDown = Instance.new("TextButton")
    speedDown.Size = UDim2.new(0.4,0,0,30)
    speedDown.Position = UDim2.new(0.55,0,0,50)
    speedDown.Text = "-"
    speedDown.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    speedDown.TextColor3 = Color3.new(1,1,1)
    speedDown.Parent = content

    -- 停止移动按钮
    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.85,0,0,30)
    stopBtn.Position = UDim2.new(0.075,0,0,100)
    stopBtn.Text = "停止移动"
    stopBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    stopBtn.TextColor3 = Color3.new(1,1,1)
    stopBtn.Parent = content

    -- 防旋转按钮（控制 _G.fixedMode）
    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85,0,0,30)
    fixBtn.Position = UDim2.new(0.075,0,0,140)
    fixBtn.Text = "防止旋转: 关闭"
    fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    fixBtn.TextColor3 = Color3.new(1,1,1)
    fixBtn.Parent = content

    -- 方向按钮（十字 / 前后左右，上下）
    local dirButtons = {
        {name="上", vec=Vector3.new(0,1,0), pos=UDim2.new(0.35,0,0,190)},
        {name="下", vec=Vector3.new(0,-1,0), pos=UDim2.new(0.35,0,0,260)},
        {name="左", vec=Vector3.new(-1,0,0), pos=UDim2.new(0.05,0,0,225)},
        {name="右", vec=Vector3.new(1,0,0), pos=UDim2.new(0.65,0,0,225)},
        {name="前", vec=Vector3.new(0,0,1), pos=UDim2.new(0.2,0,0,225)},
        {name="后", vec=Vector3.new(0,0,-1), pos=UDim2.new(0.5,0,0,225)},
    }

    for _, info in ipairs(dirButtons) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.15,0,0,35)
        b.Position = info.pos
        b.Text = info.name
        b.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
        b.TextColor3 = Color3.new(1,1,1)
        b.Parent = content

        b.MouseButton1Click:Connect(function()
            _G.moveDirection = info.vec
            UpdateAllPartsVelocity()
            -- 小反馈
            local original = b.BackgroundColor3
            b.BackgroundColor3 = Color3.fromRGB(255,255,0)
            delay(0.15, function() if b then b.BackgroundColor3 = original end end)
        end)
    end

    -- 连接按钮功能
    mainButton.MouseButton1Click:Connect(function()
        _G.anActivity = not _G.anActivity
        if _G.anActivity then
            if _G.controlledPart then
                mainButton.Text = "漂浮: 开启"
                mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                ProcessPart(_G.controlledPart)
                UpdateAllPartsVelocity()
            else
                warn("请先选择一个物体进行控制")
                _G.anActivity = false
                return
            end
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            CleanupParts()
            controlPanel.Visible = false
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        _G.floatSpeed = 0
        speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
        UpdateAllPartsVelocity()
    end)

    fixBtn.MouseButton1Click:Connect(function()
        _G.fixedMode = not _G.fixedMode
        if _G.fixedMode then
            fixBtn.Text = "防止旋转: 开启"
            fixBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            -- 为现有部件添加 BodyGyro
            for part, data in pairs(_G.processedParts) do
                if part and part.Parent and (not data.bodyGyro) then
                    local bg = Instance.new("BodyGyro")
                    bg.Parent = part
                    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                    bg.P = 1000
                    bg.D = 100
                    data.bodyGyro = bg
                end
            end
        else
            fixBtn.Text = "防止旋转: 关闭"
            fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            for _, data in pairs(_G.processedParts) do
                if data.bodyGyro then
                    pcall(function() data.bodyGyro:Destroy() end)
                    data.bodyGyro = nil
                end
            end
        end
    end)

    speedUp.MouseButton1Click:Connect(function()
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 0, 100)
        speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
        UpdateAllPartsVelocity()
    end)

    speedDown.MouseButton1Click:Connect(function()
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 0, 100)
        speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
        UpdateAllPartsVelocity()
    end)

    -- 鼠标选择逻辑（保持原有控制模式）
    LocalPlayer:GetMouse().Button1Down:Connect(function()
        if _G.controlMode then
            local target = LocalPlayer:GetMouse().Target
            if target and target:IsA("BasePart") and not target.Anchored and not target.Parent:FindFirstChild("Humanoid") and not target.Parent:FindFirstChild("Head") then
                MarkControlledPart(target)
            end
        end
    end)

    -- 触摸支持（移动设备）
    UserInputService.TouchStarted:Connect(function(touch, processed)
        if not processed and _G.controlMode then
            local target = LocalPlayer:GetMouse().Target
            if target and target:IsA("BasePart") and not target.Anchored and not target.Parent:FindFirstChild("Humanoid") and not target.Parent:FindFirstChild("Head") then
                MarkControlledPart(target)
            end
        end
    end)

    return screenGui
end

-- 添加错误处理
local success, err = pcall(function()
    CreateMobileGUI()
end)

if not success then
    warn("GUI创建失败: " .. tostring(err))
    
    -- 显示错误信息
    local errorMsg = Instance.new("Message")
    errorMsg.Text = "漂浮控制GUI初始化失败: " .. tostring(err)
    errorMsg.Parent = Workspace
    delay(5, function()
        errorMsg:Destroy()
    end)
end

-- 创建并启动核心循环，这是让物体持续飞行的关键
local HeartbeatConnection
HeartbeatConnection = RunService.Heartbeat:Connect(function()
    pcall(function() -- 使用pcall防止循环中的错误导致整个脚本停止
        -- 持续处理所有受控零件
        ProcessAllParts()
    end)
end)

-- 添加一个关闭时清理循环的步骤（可选但推荐）
game:GetService("UserInputService").WindowFocused:Connect(function()
    -- 当窗口获得焦点时确保循环运行
    if not HeartbeatConnection then
        HeartbeatConnection = RunService.Heartbeat:Connect(function()
            pcall(ProcessAllParts)
        end)
    end
end)

game:GetService("UserInputService").WindowFocusReleased:Connect(function()
    -- 当窗口失去焦点时暂停循环以节省资源
    if HeartbeatConnection then
        HeartbeatConnection:Disconnect()
        HeartbeatConnection = nil
    end
end)

print("漂浮控制脚本已加载成功!")
