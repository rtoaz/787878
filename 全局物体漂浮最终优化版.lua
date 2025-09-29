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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖"
authorMessage.Parent = Workspace
task.delay(3, function()
    authorMessage:Destroy()
end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"
_G.fixedMode = false

-- 状态管理
if not _G.FloatingStateChanged then
    _G.FloatingStateChanged = Instance.new("BindableEvent")
end

-- 死亡检测变量
local isPlayerDead = false
local characterAddedConnection
local humanoidDiedConnection

-- 设置死亡检测
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

-- 计算移动方向
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
local updateConnection

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
    for part, data in pairs(_G.processedParts) do
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

local function ToggleRotationPrevention()
    if _G.fixedMode then
        _G.fixedMode = false
        for part, data in pairs(_G.processedParts) do
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil
            end
        end
        return false
    else
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
        return true
    end
end

-- 创建GUI
local function CreateGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主按钮
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
    controlPanel.Size = UDim2.new(0, 200, 0, 300)
    controlPanel.Position = UDim2.new(1, -210, 0, 70)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.Size = UDim2.new(1, 0, 1, -40)
    scrollFrame.Position = UDim2.new(0, 0, 0, 0)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 400)
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.Parent = controlPanel

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Name = "SpeedLabel"
    speedLabel.Size = UDim2.new(1, 0, 0, 30)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. _G.floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 18
    speedLabel.Parent = scrollFrame

    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Name = "SpeedUp"
    speedUpButton.Size = UDim2.new(0, 40, 0, 40)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 50)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 20
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = scrollFrame

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Name = "SpeedDown"
    speedDownButton.Size = UDim2.new(0, 40, 0, 40)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 50)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 20
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = scrollFrame

    local stopButton = Instance.new("TextButton")
    stopButton.Name = "Stop"
    stopButton.Size = UDim2.new(0, 80, 0, 30)
    stopButton.Position = UDim2.new(0.5, -40, 0, 100)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 12
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = scrollFrame

    local fixButton = Instance.new("TextButton")
    fixButton.Name = "FixRotation"
    fixButton.Size = UDim2.new(0, 100, 0, 30)
    fixButton.Position = UDim2.new(0.5, -50, 0, 140)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 12
    fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = scrollFrame

    local directionLabel = Instance.new("TextLabel")
    directionLabel.Name = "DirectionLabel"
    directionLabel.Size = UDim2.new(1, 0, 0, 25)
    directionLabel.Position = UDim2.new(0, 0, 0, 180)
    directionLabel.Text = "移动方向"
    directionLabel.TextColor3 = Color3.new(1, 1, 1)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextSize = 14
    directionLabel.Parent = scrollFrame

    local directions = {
        {name = "上", dir = "up", pos = UDim2.new(0.5, -20, 0, 210)},
        {name = "下", dir = "down", pos = UDim2.new(0.5, -20, 0, 250)},
        {name = "前", dir = "forward", pos = UDim2.new(0.5, -20, 0, 290)},
        {name = "后", dir = "back", pos = UDim2.new(0.5, -20, 0, 330)},
        {name = "左", dir = "left", pos = UDim2.new(0.2, -20, 0, 250)},
        {name = "右", dir = "right", pos = UDim2.new(0.8, -20, 0, 250)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Name = dirInfo.name
        button.Size = UDim2.new(0, 40, 0, 30)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 12
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = scrollFrame

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            _G.moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()
        end)
    end

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "ClosePanel"
    closeButton.Size = UDim2.new(0, 20, 0, 20)
    closeButton.Position = UDim2.new(1, -25, 0, 5)
    closeButton.Text = "X"
    closeButton.TextSize = 12
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Parent = controlPanel

    local openPanelButton = Instance.new("TextButton")
    openPanelButton.Name = "OpenPanel"
    openPanelButton.Size = UDim2.new(0, 120, 0, 30)
    openPanelButton.Position = UDim2.new(1, -130, 0, 70)
    openPanelButton.Text = "打开控制面板"
    openPanelButton.TextSize = 12
    openPanelButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    openPanelButton.TextColor3 = Color3.new(1, 1, 1)
    openPanelButton.Parent = screenGui

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法开启漂浮功能"
            warningMsg.Parent = Workspace
            task.delay(2, function() warningMsg:Destroy() end)
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

    speedUpButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 1, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)

    speedDownButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 1, 100)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)

    stopButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        StopAllParts()
        speedLabel.Text = "速度: " .. _G.floatSpeed
    end)

    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local newFixedState = ToggleRotationPrevention()
        if newFixedState then
            fixButton.Text = "防止旋转: 开启"
            fixButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        else
            fixButton.Text = "防止旋转: 关闭"
            fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
        end
    end)

    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
        openPanelButton.Visible = true
    end)

    openPanelButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = true
        openPanelButton.Visible = false
    end)
    
    _G.FloatingStateChanged.Event:Connect(function(stateInfo)
        if stateInfo.state == "disabled" and stateInfo.reason == "player_died" then
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    return screenGui
end

-- 初始化
local success, err = pcall(function()
    CreateGUI()
    setupDeathDetection()
end)

if not success then
    warn("初始化失败: " .. tostring(err))
end

print("漂浮脚本加载成功!")
