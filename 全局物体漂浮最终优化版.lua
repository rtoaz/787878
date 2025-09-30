local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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

-- 显示作者信息
local authorMessage = Instance.new("Message")
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
task.delay(3, function()
    authorMessage:Destroy()
end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"
_G.moveDirection = Vector3.new(0, 1, 0)
_G.fixedMode = false

-- 添加状态管理事件
if not _G.FloatingStateChanged then
    _G.FloatingStateChanged = Instance.new("BindableEvent")
    _G.FloatingStateChanged.Name = "FloatingStateChanged"
end

-- 死亡状态检测变量
local isPlayerDead = false
local characterAddedConnection = nil
local humanoidDiedConnection = nil

-- 玩家死亡状态检测函数
local function setupDeathDetection()
    local function onCharacterAdded(character)
        isPlayerDead = false
        
        local humanoid = character:WaitForChild("Humanoid")
        
        if humanoidDiedConnection then
            humanoidDiedConnection:Disconnect()
        end
        
        humanoidDiedConnection = humanoid.Died:Connect(function()
            isPlayerDead = true
            print("玩家死亡，自动关闭漂浮功能")
            
            if anActivity then
                anActivity = false
                CleanupParts()
                
                _G.FloatingStateChanged:Fire({
                    state = "disabled",
                    reason = "player_died"
                })
                
                local deathMessage = Instance.new("Message")
                deathMessage.Text = "检测到玩家死亡，已自动关闭漂浮功能"
                deathMessage.Parent = Workspace
                task.delay(3, function()
                    deathMessage:Destroy()
                end)
            end
        end)
    end
    
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
    end
    
    characterAddedConnection = LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
    
    if LocalPlayer.Character then
        task.spawn(onCharacterAdded, LocalPlayer.Character)
    end
end

-- 根据视角计算移动方向
local function CalculateMoveDirection()
    if isPlayerDead then
        return Vector3.new(0, 0, 0)
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.new(0, 1, 0) end

    if _G.moveDirectionType == "up" then
        return Vector3.new(0, 1, 0)
    elseif _G.moveDirectionType == "down" then
        return Vector3.new(0, -1, 0)
    elseif _G.moveDirectionType == "forward" then
        local lookVector = camera.CFrame.LookVector
        return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "back" then
        local lookVector = camera.CFrame.LookVector
        return -Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "right" then
        local rightVector = camera.CFrame.RightVector
        return Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    elseif _G.moveDirectionType == "left" then
        local rightVector = camera.CFrame.RightVector
        return -Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    else
        return Vector3.new(0, 1, 0)
    end
end

-- 处理零件函数
local function ProcessPart(v)
    if isPlayerDead then
        return
    end
    
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") and not v.Parent:FindFirstChild("Head") then
        if _G.processedParts[v] then
            local existingBV = _G.processedParts[v].bodyVelocity
            local existingBG = _G.processedParts[v].bodyGyro
            if existingBV and existingBV.Parent then
                local finalVelocity = CalculateMoveDirection() * _G.floatSpeed
                if existingBV.Velocity ~= finalVelocity then
                    existingBV.Velocity = finalVelocity
                end
                
                if _G.fixedMode then
                    if not existingBG or not existingBG.Parent then
                        local bodyGyro = Instance.new("BodyGyro")
                        bodyGyro.Parent = v
                        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                        bodyGyro.P = 1000
                        bodyGyro.D = 100
                        _G.processedParts[v].bodyGyro = bodyGyro
                    end
                    if existingBG then
                        existingBG.CFrame = v.CFrame
                    end
                else
                    if existingBG and existingBG.Parent then
                        existingBG:Destroy()
                        _G.processedParts[v].bodyGyro = nil
                    end
                end
                return
            else
                _G.processedParts[v] = nil
            end
        end

        for _, x in next, v:GetChildren() do
            if x:IsA("BodyAngularVelocity") or x:IsA("BodyForce") or x:IsA("BodyGyro") or 
               x:IsA("BodyPosition") or x:IsA("BodyThrust") or x:IsA("BodyVelocity") then
                x:Destroy()
            end
        end

        if v:FindFirstChild("Torque") then
            v.Torque:Destroy()
        end

        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Parent = v
        bodyVelocity.Velocity = CalculateMoveDirection() * _G.floatSpeed
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        
        local bodyGyro = nil
        if _G.fixedMode then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.Parent = v
            bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bodyGyro.P = 1000
            bodyGyro.D = 100
        end
        
        _G.processedParts[v] = { 
            bodyVelocity = bodyVelocity, 
            bodyGyro = bodyGyro 
        }
    end
end

local anActivity = false
local updateConnection = nil

local function ProcessAllParts()
    if isPlayerDead then
        if anActivity then
            anActivity = false
            CleanupParts()
        end
        return
    end
    
    if anActivity then
        for _, v in next, Workspace:GetDescendants() do
            ProcessPart(v)
        end

        if updateConnection then
            updateConnection:Disconnect()
        end

        updateConnection = RunService.Heartbeat:Connect(function()
            UpdateAllPartsVelocity()
        end)
    else
        if updateConnection then
            updateConnection:Disconnect()
            updateConnection = nil
        end
    end
end

Workspace.DescendantAdded:Connect(function(v)
    if anActivity and not isPlayerDead then
        ProcessPart(v)
    end
end)

local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity then
            data.bodyVelocity:Destroy()
        end
        if data.bodyGyro then
            data.bodyGyro:Destroy()
        end
    end
    _G.processedParts = {}

    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

local function UpdateAllPartsVelocity()
    if isPlayerDead then
        for part, data in pairs(_G.processedParts) do
            if data.bodyVelocity and data.bodyVelocity.Parent then
                data.bodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end
        return
    end
    
    local direction = CalculateMoveDirection()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = direction * _G.floatSpeed
        end
        
        if _G.fixedMode and data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro.CFrame = part.CFrame
        end
    end
end

local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
end

local function PreventRotation()
    _G.fixedMode = true
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            if not data.bodyGyro or not data.bodyGyro.Parent then
                local bodyGyro = Instance.new("BodyGyro")
                bodyGyro.Parent = part
                bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bodyGyro.P = 1000
                bodyGyro.D = 100
                data.bodyGyro = bodyGyro
            end
        end
    end
    UpdateAllPartsVelocity()
end

local function AllowRotation()
    _G.fixedMode = false
    for part, data in pairs(_G.processedParts) do
        if data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro:Destroy()
            data.bodyGyro = nil
        end
    end
    UpdateAllPartsVelocity()
end

local function ToggleRotationPrevention()
    if _G.fixedMode then
        AllowRotation()
        return false
    else
        PreventRotation()
        return true
    end
end

-- 创建GUI
local function CreateMobileGUI()
    print("开始创建GUI...")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 漂浮开关按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 16
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Parent = screenGui

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 200, 0, 280)
    controlPanel.Position = UDim2.new(1, -210, 0, 70)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    -- 面板标题栏（可拖动）
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    titleBar.BorderSizePixel = 0
    titleBar.Active = true
    titleBar.Draggable = true
    titleBar.Parent = controlPanel

    local titleText = Instance.new("TextLabel")
    titleText.Name = "TitleText"
    titleText.Size = UDim2.new(1, -40, 1, 0)
    titleText.Position = UDim2.new(0, 5, 0, 0)
    titleText.Text = "漂浮控制面板"
    titleText.TextColor3 = Color3.new(1, 1, 1)
    titleText.BackgroundTransparency = 1
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 30, 0, 30)
    closeButton.Position = UDim2.new(1, -30, 0, 0)
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeButton.BorderSizePixel = 0
    closeButton.Parent = titleBar

    -- 控制面板内容区域
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 1, -30)
    contentFrame.Position = UDim2.new(0, 0, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = controlPanel

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Name = "SpeedLabel"
    speedLabel.Size = UDim2.new(1, -20, 0, 30)
    speedLabel.Position = UDim2.new(0, 10, 0, 10)
    speedLabel.Text = "速度: " .. _G.floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 14
    speedLabel.Parent = contentFrame

    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Name = "SpeedUp"
    speedUpButton.Size = UDim2.new(0, 40, 0, 30)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 50)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 20
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = contentFrame

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Name = "SpeedDown"
    speedDownButton.Size = UDim2.new(0, 40, 0, 30)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 50)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 20
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = contentFrame

    local stopButton = Instance.new("TextButton")
    stopButton.Name = "Stop"
    stopButton.Size = UDim2.new(0.8, 0, 0, 30)
    stopButton.Position = UDim2.new(0.1, 0, 0, 90)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 14
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = contentFrame

    local fixButton = Instance.new("TextButton")
    fixButton.Name = "FixRotation"
    fixButton.Size = UDim2.new(0.8, 0, 0, 30)
    fixButton.Position = UDim2.new(0.1, 0, 0, 130)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 12
    fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = contentFrame

    -- 方向控制标题
    local directionLabel = Instance.new("TextLabel")
    directionLabel.Name = "DirectionLabel"
    directionLabel.Size = UDim2.new(1, -20, 0, 20)
    directionLabel.Position = UDim2.new(0, 10, 0, 170)
    directionLabel.Text = "移动方向"
    directionLabel.TextColor3 = Color3.new(1, 1, 1)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextSize = 12
    directionLabel.Parent = contentFrame

    -- 方向按钮
    local directions = {
        {name = "上", dir = "up", pos = UDim2.new(0.5, -20, 0, 200)},
        {name = "下", dir = "down", pos = UDim2.new(0.5, -20, 0, 240)},
        {name = "前", dir = "forward", pos = UDim2.new(0.2, -15, 0, 220)},
        {name = "后", dir = "back", pos = UDim2.new(0.8, -15, 0, 220)},
        {name = "左", dir = "left", pos = UDim2.new(0.05, -15, 0, 220)},
        {name = "右", dir = "right", pos = UDim2.new(0.95, -15, 0, 220)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Name = dirInfo.name
        button.Size = UDim2.new(0, 30, 0, 30)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 10
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = contentFrame

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then
                local warningMsg = Instance.new("Message")
                warningMsg.Text = "玩家死亡时无法更改漂浮方向"
                warningMsg.Parent = Workspace
                task.delay(2, function()
                    warningMsg:Destroy()
                end)
                return
            end
            
            _G.moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()

            local originalColor = button.BackgroundColor3
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
            task.delay(0.2, function()
                button.BackgroundColor3 = originalColor
            end)
        end)
    end

    -- 面板开关按钮（放在漂浮按钮下方）
    local panelToggleButton = Instance.new("TextButton")
    panelToggleButton.Name = "PanelToggle"
    panelToggleButton.Size = UDim2.new(0, 120, 0, 30)
    panelToggleButton.Position = UDim2.new(1, -130, 0, 70)
    panelToggleButton.Text = "打开控制面板"
    panelToggleButton.TextSize = 12
    panelToggleButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    panelToggleButton.TextColor3 = Color3.new(1, 1, 1)
    panelToggleButton.Parent = screenGui

    -- 速度按钮功能
    speedUpButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法更改漂浮速度"
            warningMsg.Parent = Workspace
            task.delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 1, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()

        local originalColor = speedUpButton.BackgroundColor3
        speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        task.delay(0.2, function()
            speedUpButton.BackgroundColor3 = originalColor
        end)
    end)

    speedDownButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法更改漂浮速度"
            warningMsg.Parent = Workspace
            task.delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 1, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()

        local originalColor = speedDownButton.BackgroundColor3
        speedDownButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        task.delay(0.2, function()
            speedDownButton.BackgroundColor3 = originalColor
        end)
    end)

    stopButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法操作漂浮功能"
            warningMsg.Parent = Workspace
            task.delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        StopAllParts()
        speedLabel.Text = "速度: " .. _G.floatSpeed

        local originalColor = stopButton.BackgroundColor3
        stopButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        task.delay(0.2, function()
            stopButton.BackgroundColor3 = originalColor
        end)
    end)

    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法操作防旋转功能"
            warningMsg.Parent = Workspace
            task.delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        local newFixedState = ToggleRotationPrevention()
        if newFixedState then
            fixButton.Text = "防止旋转: 开启"
            fixButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        else
            fixButton.Text = "防止旋转: 关闭"
            fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
        end
    end)

    -- 漂浮开关功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法开启漂浮功能"
            warningMsg.Parent = Workspace
            task.delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        anActivity = not anActivity
        ProcessAllParts()
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            UpdateAllPartsVelocity()
        else
            CleanupParts()
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    -- 面板开关功能
    panelToggleButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
        if controlPanel.Visible then
            panelToggleButton.Text = "关闭控制面板"
        else
            panelToggleButton.Text = "打开控制面板"
        end
    end)

    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
        panelToggleButton.Text = "打开控制面板"
    end)
    
    -- 监听漂浮状态变化
    _G.FloatingStateChanged.Event:Connect(function(stateInfo)
        if stateInfo.state == "disabled" and stateInfo.reason == "player_died" then
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    print("GUI创建完成")
    return screenGui
end

-- 设置死亡检测
setupDeathDetection()

-- 创建GUI
local success, err = pcall(function()
    CreateMobileGUI()
end)

if not success then
    warn("GUI创建失败: " .. tostring(err))
    
    local errorMsg = Instance.new("Message")
    errorMsg.Text = "漂浮控制GUI初始化失败: " .. tostring(err)
    errorMsg.Parent = Workspace
    task.delay(5, function()
        errorMsg:Destroy()
    end)
end

print("全局物体漂浮脚本已加载成功!")
