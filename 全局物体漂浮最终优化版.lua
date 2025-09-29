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

-- 全局变量
local processedParts = {}
local floatSpeed = 10
local moveDirectionType = "up"
local fixedMode = false
local anActivity = false
local updateConnection = nil
local isPlayerDead = false

-- 显示作者信息
local authorMessage = Instance.new("Message")
authorMessage.Text = "全局物体漂浮脚本 - 修复版"
authorMessage.Parent = Workspace
task.delay(3, function()
    authorMessage:Destroy()
end)

-- 死亡检测设置
local function setupDeathDetection()
    local function onCharacterAdded(character)
        isPlayerDead = false
        
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.Died:Connect(function()
            isPlayerDead = true
            print("玩家死亡，自动关闭漂浮功能")
            
            if anActivity then
                anActivity = false
                CleanupParts()
                
                -- 显示死亡提示
                local deathMessage = Instance.new("Message")
                deathMessage.Text = "检测到玩家死亡，已自动关闭漂浮功能"
                deathMessage.Parent = Workspace
                task.delay(3, function()
                    deathMessage:Destroy()
                end)
            end
        end)
    end
    
    LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
    
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

-- 处理零件
local function ProcessPart(part)
    if isPlayerDead then
        return
    end
    
    if part:IsA("Part") and not part.Anchored and not part.Parent:FindFirstChild("Humanoid") then
        -- 清理现有的物理效果
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("BodyVelocity") or child:IsA("BodyGyro") then
                child:Destroy()
            end
        end

        -- 创建BodyVelocity
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Velocity = CalculateMoveDirection() * floatSpeed
        bodyVelocity.MaxForce = Vector3.new(400000, 400000, 400000)
        bodyVelocity.Parent = part
        
        -- 如果固定模式开启，添加BodyGyro
        local bodyGyro = nil
        if fixedMode then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
            bodyGyro.P = 1000
            bodyGyro.D = 100
            bodyGyro.Parent = part
        end
        
        processedParts[part] = {
            bodyVelocity = bodyVelocity,
            bodyGyro = bodyGyro
        }
    end
end

-- 清理所有零件
local function CleanupParts()
    for part, data in pairs(processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity:Destroy()
        end
        if data.bodyGyro and data.bodyGyro.Parent then
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
local function UpdateAllPartsVelocity()
    if isPlayerDead then
        for part, data in pairs(processedParts) do
            if data.bodyVelocity and data.bodyVelocity.Parent then
                data.bodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end
        return
    end
    
    local direction = CalculateMoveDirection()
    for part, data in pairs(processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = direction * floatSpeed
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
        -- 处理现有零件
        for _, part in ipairs(Workspace:GetDescendants()) do
            if part:IsA("Part") and not part.Anchored and not part.Parent:FindFirstChild("Humanoid") then
                ProcessPart(part)
            end
        end
        
        -- 启动更新循环
        if updateConnection then
            updateConnection:Disconnect()
        end
        
        updateConnection = RunService.Heartbeat:Connect(function()
            UpdateAllPartsVelocity()
        end)
    else
        CleanupParts()
    end
end

-- 监听新零件添加
Workspace.DescendantAdded:Connect(function(descendant)
    if anActivity and not isPlayerDead and descendant:IsA("Part") then
        task.wait(0.1) -- 稍等确保零件完全加载
        ProcessPart(descendant)
    end
end)

-- 停止所有零件
local function StopAllParts()
    floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- 防旋转功能
local function ToggleRotationPrevention()
    fixedMode = not fixedMode
    
    for part, data in pairs(processedParts) do
        if fixedMode then
            -- 开启防旋转
            if not data.bodyGyro or not data.bodyGyro.Parent then
                local bodyGyro = Instance.new("BodyGyro")
                bodyGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
                bodyGyro.P = 1000
                bodyGyro.D = 100
                bodyGyro.Parent = part
                data.bodyGyro = bodyGyro
            end
        else
            -- 关闭防旋转
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil
            end
        end
    end
    
    return fixedMode
end

-- 创建GUI
local function CreateGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主漂浮按钮 - 放在屏幕左上角
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 100, 0, 40)
    mainButton.Position = UDim2.new(0, 10, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 14
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Parent = screenGui

    -- 控制面板 - 放在主按钮右边，尺寸更小
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 180, 0, 280)
    controlPanel.Position = UDim2.new(0, 120, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.2
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    -- 关闭按钮 - 放在面板右上角
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 20, 0, 20)
    closeButton.Position = UDim2.new(1, -25, 0, 5)
    closeButton.Text = "X"
    closeButton.TextSize = 12
    closeButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Parent = controlPanel

    -- 速度标签
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, -10, 0, 30)
    speedLabel.Position = UDim2.new(0, 5, 0, 30)
    speedLabel.Text = "速度: " .. floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 16
    speedLabel.Parent = controlPanel

    -- 速度控制按钮
    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Size = UDim2.new(0, 40, 0, 30)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 70)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 18
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.Parent = controlPanel

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Size = UDim2.new(0, 40, 0, 30)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 70)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 18
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.Parent = controlPanel

    -- 停止按钮
    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(0, 80, 0, 30)
    stopButton.Position = UDim2.new(0.5, -40, 0, 110)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 14
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.Parent = controlPanel

    -- 防旋转按钮
    local fixButton = Instance.new("TextButton")
    fixButton.Size = UDim2.new(0, 100, 0, 30)
    fixButton.Position = UDim2.new(0.5, -50, 0, 150)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 12
    fixButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    fixButton.Parent = controlPanel

    -- 方向控制
    local directionLabel = Instance.new("TextLabel")
    directionLabel.Size = UDim2.new(1, -10, 0, 20)
    directionLabel.Position = UDim2.new(0, 5, 0, 190)
    directionLabel.Text = "移动方向:"
    directionLabel.TextColor3 = Color3.new(1, 1, 1)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextSize = 14
    directionLabel.Parent = controlPanel

    -- 方向按钮
    local directions = {
        {name = "上", dir = "up", pos = UDim2.new(0.2, -15, 0, 220)},
        {name = "下", dir = "down", pos = UDim2.new(0.8, -15, 0, 220)},
        {name = "前", dir = "forward", pos = UDim2.new(0.5, -15, 0, 220)},
        {name = "后", dir = "back", pos = UDim2.new(0.5, -15, 0, 250)}
    }

    for _, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 30, 0, 25)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 12
        button.BackgroundColor3 = Color3.fromRGB(80, 80, 180)
        button.Parent = controlPanel

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 主按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local msg = Instance.new("Message")
            msg.Text = "玩家死亡时无法开启漂浮"
            msg.Parent = Workspace
            task.delay(2, function() msg:Destroy() end)
            return
        end
        
        anActivity = not anActivity
        ProcessAllParts()
        
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    -- 速度控制
    speedUpButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        floatSpeed = math.min(floatSpeed + 5, 50)
        speedLabel.Text = "速度: " .. floatSpeed
        UpdateAllPartsVelocity()
    end)

    speedDownButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        floatSpeed = math.max(floatSpeed - 5, 1)
        speedLabel.Text = "速度: " .. floatSpeed
        UpdateAllPartsVelocity()
    end)

    -- 停止功能
    stopButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        StopAllParts()
        speedLabel.Text = "速度: 0"
    end)

    -- 防旋转功能
    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local newState = ToggleRotationPrevention()
        if newState then
            fixButton.Text = "防止旋转: 开启"
            fixButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        else
            fixButton.Text = "防止旋转: 关闭"
            fixButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        end
    end)

    -- 面板开关功能
    mainButton.MouseButton2Click:Connect(function() -- 右键切换面板
        controlPanel.Visible = not controlPanel.Visible
    end)

    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
    end)

    return screenGui
end

-- 初始化
setupDeathDetection()
CreateGUI()
print("漂浮脚本加载完成 - 左键点击开关漂浮，右键点击开关控制面板")
