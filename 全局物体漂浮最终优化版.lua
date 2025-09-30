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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
delay(3, function()
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
                -- 清理所有漂浮物体
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
                
                -- 显示死亡提示
                local deathMessage = Instance.new("Message")
                deathMessage.Text = "检测到玩家死亡，已自动关闭漂浮功能"
                deathMessage.Parent = Workspace
                delay(3, function()
                    deathMessage:Destroy()
                end)
            end
        end)
    end
    
    LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
    
    if LocalPlayer.Character then
        onCharacterAdded(LocalPlayer.Character)
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
local function ProcessPart(v)
    if isPlayerDead then return end
    
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") and not v.Parent:FindFirstChild("Head") then
        if processedParts[v] then
            local existingBV = processedParts[v].bodyVelocity
            if existingBV and existingBV.Parent then
                existingBV.Velocity = CalculateMoveDirection() * floatSpeed
                return
            else
                processedParts[v] = nil
            end
        end

        -- 清理现有物理效果
        for _, x in next, v:GetChildren() do
            if x:IsA("BodyVelocity") or x:IsA("BodyGyro") then
                x:Destroy()
            end
        end

        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Parent = v
        bodyVelocity.Velocity = CalculateMoveDirection() * floatSpeed
        bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
        
        local bodyGyro = nil
        if fixedMode then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.Parent = v
            bodyGyro.MaxTorque = Vector3.new(4000, 4000, 4000)
            bodyGyro.P = 1000
            bodyGyro.D = 100
        end
        
        processedParts[v] = { bodyVelocity = bodyVelocity, bodyGyro = bodyGyro }
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

-- 停止所有零件移动
local function StopAllParts()
    floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- 切换防旋转模式
local function ToggleRotationPrevention()
    fixedMode = not fixedMode
    
    for part, data in pairs(processedParts) do
        if fixedMode then
            if not data.bodyGyro or not data.bodyGyro.Parent then
                local bodyGyro = Instance.new("BodyGyro")
                bodyGyro.Parent = part
                bodyGyro.MaxTorque = Vector3.new(4000, 4000, 4000)
                bodyGyro.P = 1000
                bodyGyro.D = 100
                data.bodyGyro = bodyGyro
            end
        else
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

    -- 主开关按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(0, 10, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 16
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Active = true
    mainButton.Draggable = true
    mainButton.Parent = screenGui

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 200, 0, 280)
    controlPanel.Position = UDim2.new(0, 140, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.2
    controlPanel.BorderSizePixel = 2
    controlPanel.BorderColor3 = Color3.fromRGB(100, 100, 100)
    controlPanel.Visible = false
    controlPanel.Active = true
    controlPanel.Draggable = true
    controlPanel.Parent = screenGui

    -- 标题栏
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    titleBar.BorderSizePixel = 0
    titleBar.Active = true
    titleBar.Draggable = true
    titleBar.Parent = controlPanel

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 0)
    titleLabel.Text = "漂浮控制"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 25, 0, 25)
    closeButton.Position = UDim2.new(1, -25, 0, 2)
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeButton.TextSize = 12
    closeButton.Parent = titleBar

    -- 滚动框架
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 400)
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.Parent = controlPanel

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Name = "SpeedLabel"
    speedLabel.Size = UDim2.new(1, -20, 0, 25)
    speedLabel.Position = UDim2.new(0, 10, 0, 10)
    speedLabel.Text = "速度: " .. floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 14
    speedLabel.Parent = scrollFrame

    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Name = "SpeedUp"
    speedUpButton.Size = UDim2.new(0, 40, 0, 30)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 40)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 16
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = scrollFrame

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Name = "SpeedDown"
    speedDownButton.Size = UDim2.new(0, 40, 0, 30)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 40)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 16
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = scrollFrame

    local stopButton = Instance.new("TextButton")
    stopButton.Name = "Stop"
    stopButton.Size = UDim2.new(0, 80, 0, 30)
    stopButton.Position = UDim2.new(0.5, -40, 0, 80)
    stopButton.Text = "停止"
    stopButton.TextSize = 14
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = scrollFrame

    local fixButton = Instance.new("TextButton")
    fixButton.Name = "FixRotation"
    fixButton.Size = UDim2.new(0, 120, 0, 30)
    fixButton.Position = UDim2.new(0.5, -60, 0, 120)
    fixButton.Text = "防旋转: 关闭"
    fixButton.TextSize = 12
    fixButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = scrollFrame

    -- 方向按钮
    local directions = {
        {name = "向上", dir = "up", pos = UDim2.new(0.5, -25, 0, 160)},
        {name = "向下", dir = "down", pos = UDim2.new(0.5, -25, 0, 200)},
        {name = "向前", dir = "forward", pos = UDim2.new(0.5, -25, 0, 240)},
        {name = "向后", dir = "back", pos = UDim2.new(0.5, -25, 0, 280)},
        {name = "向左", dir = "left", pos = UDim2.new(0.2, -25, 0, 240)},
        {name = "向右", dir = "right", pos = UDim2.new(0.8, -25, 0, 240)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Name = dirInfo.name
        button.Size = UDim2.new(0, 50, 0, 30)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 10
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = scrollFrame

        button.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮事件
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法开启漂浮功能"
            warningMsg.Parent = Workspace
            delay(2, function() warningMsg:Destroy() end)
            return
        end
        
        anActivity = not anActivity
        
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            
            -- 处理所有现有零件
            for _, v in next, Workspace:GetDescendants() do
                ProcessPart(v)
            end
            
            -- 启动更新循环
            if updateConnection then
                updateConnection:Disconnect()
            end
            
            updateConnection = RunService.Heartbeat:Connect(function()
                UpdateAllPartsVelocity()
            end)
            
            -- 监听新添加的零件
            Workspace.DescendantAdded:Connect(function(v)
                if anActivity and not isPlayerDead then
                    ProcessPart(v)
                end
            end)
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
        floatSpeed = math.min(floatSpeed + 5, 100)
        speedLabel.Text = "速度: " .. floatSpeed
        UpdateAllPartsVelocity()
    end)

    speedDownButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        floatSpeed = math.max(floatSpeed - 5, 1)
        speedLabel.Text = "速度: " .. floatSpeed
        UpdateAllPartsVelocity()
    end)

    stopButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        StopAllParts()
    end)

    fixButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local newState = ToggleRotationPrevention()
        fixButton.Text = "防旋转: " .. (newState and "开启" or "关闭")
        fixButton.BackgroundColor3 = newState and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(100, 100, 200)
    end)

    return screenGui
end

-- 初始化
setupDeathDetection()
CreateGUI()
print("漂浮脚本加载完成")
