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
local processedParts = {}
local floatSpeed = 10
local moveDirectionType = "up"
local fixedMode = false
local isPlayerDead = false
local anActivity = false
local updateConnection = nil

-- 死亡检测相关变量
local characterAddedConnection = nil
local humanoidDiedConnection = nil

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
                cleanupParts()
                
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
local function calculateMoveDirection()
    if isPlayerDead then
        return Vector3.new(0, 0, 0)
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.new(0, 1, 0) end

    if moveDirectionType == "up" then
        return Vector3.new(0, 1, 0)
    elseif moveDirectionType == "down" then
        return Vector3.new(0, -1, 0)
    elseif moveDirectionType == "forward" then
        local lookVector = camera.CFrame.LookVector
        return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif moveDirectionType == "back" then
        local lookVector = camera.CFrame.LookVector
        return -Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif moveDirectionType == "right" then
        local rightVector = camera.CFrame.RightVector
        return Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    elseif moveDirectionType == "left" then
        local rightVector = camera.CFrame.RightVector
        return -Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    else
        return Vector3.new(0, 1, 0)
    end
end

-- 清理零件
local function cleanupParts()
    for part, data in pairs(processedParts) do
        if data.bodyVelocity then
            data.bodyVelocity:Destroy()
        end
        if data.bodyGyro then
            data.bodyGyro:Destroy()
        end
    end
    processedParts = {}

    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

-- 更新所有零件速度
local function updateAllPartsVelocity()
    if isPlayerDead then
        for part, data in pairs(processedParts) do
            if data.bodyVelocity and data.bodyVelocity.Parent then
                data.bodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end
        return
    end
    
    local direction = calculateMoveDirection()
    for part, data in pairs(processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = direction * floatSpeed
        end
        
        if fixedMode and data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro.CFrame = part.CFrame
        end
    end
end

-- 处理单个零件
local function processPart(v)
    if isPlayerDead then
        return
    end
    
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") and not v.Parent:FindFirstChild("Head") then
        if processedParts[v] then
            local existingBV = processedParts[v].bodyVelocity
            local existingBG = processedParts[v].bodyGyro
            if existingBV and existingBV.Parent then
                local finalVelocity = calculateMoveDirection() * floatSpeed
                if existingBV.Velocity ~= finalVelocity then
                    existingBV.Velocity = finalVelocity
                end
                
                if fixedMode then
                    if not existingBG or not existingBG.Parent then
                        local bodyGyro = Instance.new("BodyGyro")
                        bodyGyro.Parent = v
                        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                        bodyGyro.P = 1000
                        bodyGyro.D = 100
                        processedParts[v].bodyGyro = bodyGyro
                    end
                    if existingBG then
                        existingBG.CFrame = v.CFrame
                    end
                else
                    if existingBG and existingBG.Parent then
                        existingBG:Destroy()
                        processedParts[v].bodyGyro = nil
                    end
                end
                return
            else
                processedParts[v] = nil
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
        bodyVelocity.Velocity = calculateMoveDirection() * floatSpeed
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        
        local bodyGyro = nil
        if fixedMode then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.Parent = v
            bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bodyGyro.P = 1000
            bodyGyro.D = 100
        end
        
        processedParts[v] = { 
            bodyVelocity = bodyVelocity, 
            bodyGyro = bodyGyro 
        }
    end
end

-- 处理所有零件
local function processAllParts()
    if isPlayerDead then
        if anActivity then
            anActivity = false
            cleanupParts()
        end
        return
    end
    
    if anActivity then
        for _, v in next, Workspace:GetDescendants() do
            processPart(v)
        end

        if updateConnection then
            updateConnection:Disconnect()
        end

        updateConnection = RunService.Heartbeat:Connect(function()
            updateAllPartsVelocity()
        end)
    else
        if updateConnection then
            updateConnection:Disconnect()
            updateConnection = nil
        end
    end
end

-- 停止所有零件
local function stopAllParts()
    floatSpeed = 0
    updateAllPartsVelocity()
end

-- 切换防旋转模式
local function toggleRotationPrevention()
    fixedMode = not fixedMode
    
    if fixedMode then
        for part, data in pairs(processedParts) do
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
    else
        for part, data in pairs(processedParts) do
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil
            end
        end
    end
    
    updateAllPartsVelocity()
    return fixedMode
end

-- 使GUI可拖动
local function makeDraggable(gui)
    gui.Active = true
    gui.Draggable = true
end

-- 创建GUI
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主开关按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 16
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Parent = screenGui
    makeDraggable(mainButton)

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 250, 0, 400)
    controlPanel.Position = UDim2.new(0.5, -125, 0.5, -200)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui
    makeDraggable(controlPanel)

    -- 滚动框架
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, 0, 1, -50)
    scrollFrame.Position = UDim2.new(0, 0, 0, 0)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 600)
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.Parent = controlPanel

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, 0, 0, 30)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 18
    speedLabel.Parent = scrollFrame

    -- 速度按钮
    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Size = UDim2.new(0, 50, 0, 50)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 50)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 25
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = scrollFrame

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Size = UDim2.new(0, 50, 0, 50)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 50)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 25
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = scrollFrame

    -- 停止按钮
    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(0, 100, 0, 35)
    stopButton.Position = UDim2.new(0.5, -50, 0, 110)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 14
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = scrollFrame

    -- 防旋转按钮
    local fixButton = Instance.new("TextButton")
    fixButton.Size = UDim2.new(0, 120, 0, 35)
    fixButton.Position = UDim2.new(0.5, -60, 0, 155)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 14
    fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = scrollFrame
    makeDraggable(fixButton)

    -- 方向控制
    local directionLabel = Instance.new("TextLabel")
    directionLabel.Size = UDim2.new(1, 0, 0, 30)
    directionLabel.Position = UDim2.new(0, 0, 0, 200)
    directionLabel.Text = "移动方向 (基于视角)"
    directionLabel.TextColor3 = Color3.new(1, 1, 1)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextSize = 16
    directionLabel.Parent = scrollFrame

    -- 方向按钮
    local directions = {
        {name = "向上", dir = "up", pos = UDim2.new(0.5, -25, 0, 240)},
        {name = "向下", dir = "down", pos = UDim2.new(0.5, -25, 0, 290)},
        {name = "向前", dir = "forward", pos = UDim2.new(0.2, -25, 0, 265)},
        {name = "向后", dir = "back", pos = UDim2.new(0.8, -25, 0, 265)},
        {name = "向左", dir = "left", pos = UDim2.new(0.05, -25, 0, 265)},
        {name = "向右", dir = "right", pos = UDim2.new(0.95, -25, 0, 265)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Name = dirInfo.name
        button.Size = UDim2.new(0, 50, 0, 40)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 12
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = scrollFrame

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            moveDirectionType = dirInfo.dir
            updateAllPartsVelocity()
        end)
    end

    -- 关闭按钮
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 100, 0, 35)
    closeButton.Position = UDim2.new(0.5, -50, 1, -45)
    closeButton.Text = "关闭面板"
    closeButton.TextSize = 14
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Parent = controlPanel

    -- 打开面板按钮
    local openPanelButton = Instance.new("TextButton")
    openPanelButton.Size = UDim2.new(0, 120, 0, 35)
    openPanelButton.Position = UDim2.new(1, -130, 0, 70)
    openPanelButton.Text = "打开控制面板"
    openPanelButton.TextSize = 14
    openPanelButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    openPanelButton.TextColor3 = Color3.new(1, 1, 1)
    openPanelButton.Parent = screenGui
    makeDraggable(openPanelButton)

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        processAllParts()
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            cleanupParts()
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    speedUpButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        floatSpeed = math.clamp(floatSpeed + 5, 1, 100)
        speedLabel.Text = "速度: " .. floatSpeed
        updateAllPartsVelocity()
    end)

    speedDownButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        floatSpeed = math.clamp(floatSpeed - 5, 1, 100)
        speedLabel.Text = "速度: " .. floatSpeed
        updateAllPartsVelocity()
    end)

    stopButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        stopAllParts()
        speedLabel.Text = "速度: " .. floatSpeed
    end)

    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local newState = toggleRotationPrevention()
        if newState then
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

    return screenGui
end

-- 监听新添加的零件
Workspace.DescendantAdded:Connect(function(v)
    if anActivity and not isPlayerDead then
        processPart(v)
    end
end)

-- 初始化
local success, err = pcall(function()
    createGUI()
    setupDeathDetection()
end)

if not success then
    warn("GUI创建失败: " .. tostring(err))
end

print("全局物体漂浮脚本已加载成功!")