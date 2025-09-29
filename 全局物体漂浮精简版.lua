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
authorMessage.Text = "全局物体漂浮脚本 - 修复版"
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

-- 状态管理事件
local FloatingStateChanged = Instance.new("BindableEvent")

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
                cleanupParts()
                FloatingStateChanged:Fire({state = "disabled", reason = "player_died"})
            end
        end)
    end
    
    LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
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
    end
end

-- 处理单个零件
local function processPart(v)
    if isPlayerDead then return end
    
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") then
        if processedParts[v] then
            local existingBV = processedParts[v].bodyVelocity
            if existingBV and existingBV.Parent then
                existingBV.Velocity = calculateMoveDirection() * floatSpeed
                return
            else
                processedParts[v] = nil
            end
        end

        -- 清理现有物理效果
        for _, x in ipairs(v:GetChildren()) do
            if x:IsA("BodyVelocity") or x:IsA("BodyGyro") then
                x:Destroy()
            end
        end

        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Parent = v
        bodyVelocity.Velocity = calculateMoveDirection() * floatSpeed
        bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
        
        processedParts[v] = {bodyVelocity = bodyVelocity}
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
        for _, v in ipairs(Workspace:GetDescendants()) do
            processPart(v)
        end

        if updateConnection then
            updateConnection:Disconnect()
        end

        updateConnection = RunService.Heartbeat:Connect(function()
            updateAllPartsVelocity()
        end)
    else
        cleanupParts()
    end
end

-- 停止所有零件
local function stopAllParts()
    floatSpeed = 0
    updateAllPartsVelocity()
end

-- 创建GUI
local function createMobileGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主控制按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 100, 0, 40)
    mainButton.Position = UDim2.new(1, -110, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 14
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Parent = screenGui

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 200, 0, 300)
    controlPanel.Position = UDim2.new(0.5, -100, 0.5, -150)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.2
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, 0, 0, 30)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 16
    speedLabel.Parent = controlPanel

    -- 速度按钮
    local speedUp = Instance.new("TextButton")
    speedUp.Size = UDim2.new(0, 40, 0, 40)
    speedUp.Position = UDim2.new(0.7, 0, 0, 50)
    speedUp.Text = "+"
    speedUp.TextSize = 20
    speedUp.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUp.Parent = controlPanel

    local speedDown = Instance.new("TextButton")
    speedDown.Size = UDim2.new(0, 40, 0, 40)
    speedDown.Position = UDim2.new(0.3, 0, 0, 50)
    speedDown.Text = "-"
    speedDown.TextSize = 20
    speedDown.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDown.Parent = controlPanel

    -- 方向按钮
    local directions = {
        {name = "上", dir = "up", pos = UDim2.new(0.5, -20, 0, 100)},
        {name = "下", dir = "down", pos = UDim2.new(0.5, -20, 0, 150)},
        {name = "前", dir = "forward", pos = UDim2.new(0.5, -20, 0, 200)},
        {name = "后", dir = "back", pos = UDim2.new(0.5, -20, 0, 250)}
    }

    for _, dir in ipairs(directions) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 40, 0, 30)
        btn.Position = dir.pos
        btn.Text = dir.name
        btn.TextSize = 12
        btn.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        btn.Parent = controlPanel
        
        btn.MouseButton1Click:Connect(function()
            if not isPlayerDead then
                moveDirectionType = dir.dir
                updateAllPartsVelocity()
            end
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
        processAllParts()
        
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    -- 速度按钮功能
    speedUp.MouseButton1Click:Connect(function()
        if not isPlayerDead then
            floatSpeed = math.min(floatSpeed + 5, 100)
            speedLabel.Text = "速度: " .. floatSpeed
            updateAllPartsVelocity()
        end
    end)

    speedDown.MouseButton1Click:Connect(function()
        if not isPlayerDead then
            floatSpeed = math.max(floatSpeed - 5, 1)
            speedLabel.Text = "速度: " .. floatSpeed
            updateAllPartsVelocity()
        end
    end)

    -- 显示/隐藏面板
    local togglePanel = Instance.new("TextButton")
    togglePanel.Size = UDim2.new(0, 100, 0, 30)
    togglePanel.Position = UDim2.new(1, -110, 0, 60)
    togglePanel.Text = "控制面板"
    togglePanel.TextSize = 12
    togglePanel.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    togglePanel.Parent = screenGui

    togglePanel.MouseButton1Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
    end)

    return screenGui
end

-- 初始化
setupDeathDetection()
createMobileGUI()

-- 监听新添加的零件
Workspace.DescendantAdded:Connect(function(descendant)
    if anActivity and not isPlayerDead then
        processPart(descendant)
    end
end)

print("物体漂浮脚本加载成功!")