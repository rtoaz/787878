local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n由Star_Skater53帮忙优化"
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
_G.FloatingStateChanged = Instance.new("BindableEvent")

-- 死亡检测变量
local isPlayerDead = false
local characterAddedConnection
local humanoidDiedConnection

-- 漂浮功能变量
local anActivity = false
local updateConnection

-- 死亡检测设置
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
                _G.FloatingStateChanged:Fire({state = "disabled", reason = "player_died"})
                
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

-- 处理零件
local function ProcessPart(v)
    if isPlayerDead then return end
    
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

-- 清理零件
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

-- 更新所有零件速度
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

-- 处理所有零件
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

-- 停止所有零件
local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- 防旋转切换
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
local function CreateMobileGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
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
    controlPanel.Size = UDim2.new(0, 200, 0, 280)
    controlPanel.Position = UDim2.new(0.5, -100, 0.5, -140)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.2
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Active = true
    controlPanel.Draggable = true
    controlPanel.Parent = screenGui

    -- 标题栏
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    titleBar.BorderSizePixel = 0
    titleBar.Active = true
    titleBar.Draggable = true
    titleBar.Parent = controlPanel

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 0)
    titleLabel.Text = "漂浮控制面板"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextSize = 14
    titleLabel.Parent = titleBar

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 30, 0, 30)
    closeButton.Position = UDim2.new(1, -30, 0, 0)
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeButton.TextSize = 14
    closeButton.Parent = titleBar

    -- 内容区域
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, 0, 1, -30)
    contentFrame.Position = UDim2.new(0, 0, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = controlPanel

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, 0, 0, 30)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. _G.floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 16
    speedLabel.Parent = contentFrame

    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Size = UDim2.new(0, 50, 0, 30)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 50)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 20
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = contentFrame

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Size = UDim2.new(0, 50, 0, 30)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 50)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 20
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = contentFrame

    -- 停止按钮
    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(0, 100, 0, 30)
    stopButton.Position = UDim2.new(0.5, -50, 0, 90)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 14
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = contentFrame

    -- 防旋转按钮
    local fixButton = Instance.new("TextButton")
    fixButton.Size = UDim2.new(0, 120, 0, 30)
    fixButton.Position = UDim2.new(0.5, -60, 0, 130)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 12
    fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = contentFrame

    -- 方向按钮
    local directions = {
        {name = "向上", dir = "up", pos = UDim2.new(0.5, -25, 0, 170)},
        {name = "向下", dir = "down", pos = UDim2.new(0.5, -25, 0, 210)},
        {name = "向前", dir = "forward", pos = UDim2.new(0.2, -25, 0, 190)},
        {name = "向后", dir = "back", pos = UDim2.new(0.8, -25, 0, 190)},
        {name = "向左", dir = "left", pos = UDim2.new(0.05, -25, 0, 190)},
        {name = "向右", dir = "right", pos = UDim2.new(0.95, -25, 0, 190)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 50, 0, 30)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 10
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = contentFrame

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            _G.moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        ProcessAllParts()
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            CleanupParts()
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    mainButton.MouseButton2Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
    end)

    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
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
    end)

    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local newState = ToggleRotationPrevention()
        if newState then
            fixButton.Text = "防止旋转: 开启"
            fixButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        else
            fixButton.Text = "防止旋转: 关闭"
            fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
        end
    end)

    -- 监听状态变化
    _G.FloatingStateChanged.Event:Connect(function(stateInfo)
        if stateInfo.state == "disabled" and stateInfo.reason == "player_died" then
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    return screenGui
end

-- 初始化
Workspace.DescendantAdded:Connect(function(v)
    if anActivity and not isPlayerDead then
        ProcessPart(v)
    end
end)

setupDeathDetection()
CreateMobileGUI()

print("全局物体漂浮脚本已加载成功!")
