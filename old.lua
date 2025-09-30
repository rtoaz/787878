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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n注意2：死亡前请关闭此脚本开启的所有按钮不然会出故障\n（我有尝试修复这个故障但是失败了）"
authorMessage.Parent = Workspace
delay(3, function()
    authorMessage:Destroy()
end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10 -- 默认漂浮速度
_G.moveDirectionType = "up" -- 默认移动方向类型
_G.moveDirection = Vector3.new(0, 1, 0) -- 默认向上移动
_G.fixedMode = false -- 固定模式开关（防止旋转）

-- 死亡状态检测变量
local isPlayerDead = false
local characterAddedConnection = nil
local humanoidDiedConnection = nil

-- 设置模拟半径
local function setupSimulationRadius()
    local success, err = pcall(function()
        RunService.Heartbeat:Connect(function()
            pcall(function()
                sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
                sethiddenproperty(LocalPlayer, "MaxSimulationRadius", math.huge)
            end)
        end)
    end)

    if not success then
        warn("模拟半径设置失败: " .. tostring(err))
    end
end

setupSimulationRadius()

-- 玩家死亡状态检测函数
local function setupDeathDetection()
    local function onCharacterAdded(character)
        -- 重置死亡状态
        isPlayerDead = false

        -- 等待Humanoid加载
        local humanoid = character:WaitForChild("Humanoid")

        -- 监听死亡事件
        if humanoidDiedConnection then
            humanoidDiedConnection:Disconnect()
        end

        humanoidDiedConnection = humanoid.Died:Connect(function()
            isPlayerDead = true
            print("玩家死亡，自动关闭漂浮功能")
            
            -- 自动关闭漂浮功能
            if anActivity then
                anActivity = false
                CleanupParts()

                -- 更新GUI状态
                if mainButton then
                    mainButton.Text = "漂浮: 关闭"
                    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
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

    -- 监听角色添加事件
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
    end
    
    characterAddedConnection = LocalPlayer.CharacterAdded:Connect(function(character)
        -- 重生时关闭漂浮功能并更新GUI
        if anActivity then
            anActivity = false
            CleanupParts()
            if mainButton then
                mainButton.Text = "漂浮: 关闭"
                mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            end
        end
        onCharacterAdded(character) -- 调用角色添加函数
    end)

    -- 如果已经有角色，立即设置检测
    if LocalPlayer.Character then
        onCharacterAdded(LocalPlayer.Character)
    end
end

-- 根据视角计算移动方向
local function CalculateMoveDirection()
    -- 如果玩家死亡，返回零向量
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
        -- 基于摄像机的前方向（忽略Y轴）
        local lookVector = camera.CFrame.LookVector
        return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "back" then
        -- 基于摄像机的后方向（忽略Y轴）
        local lookVector = camera.CFrame.LookVector
        return -Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "right" then
        -- 基于摄像机的右方向（忽略Y轴）
        local rightVector = camera.CFrame.RightVector
        return Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    elseif _G.moveDirectionType == "left" then
        -- 基于摄像机的左方向（忽略Y轴）
        local rightVector = camera.CFrame.RightVector
        return -Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    else
        return Vector3.new(0, 1, 0)
    end
end

-- 处理零件函数
local function ProcessPart(v)
    -- 如果玩家死亡，不处理任何零件
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
                
                -- 更新BodyGyro状态
                if _G.fixedMode then
                    if not existingBG or not existingBG.Parent then
                        -- 创建BodyGyro来防止旋转
                        local bodyGyro = Instance.new("BodyGyro")
                        bodyGyro.Parent = v
                        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                        bodyGyro.P = 1000
                        bodyGyro.D = 100
                        _G.processedParts[v].bodyGyro = bodyGyro
                    end
                    -- 每帧更新BodyGyro的目标朝向，保持当前朝向
                    if existingBG then
                        existingBG.CFrame = v.CFrame
                    end
                else
                    -- 固定模式关闭时移除BodyGyro
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
        
        -- 如果固定模式开启，添加BodyGyro防止旋转
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
    -- 如果玩家死亡，不处理任何零件
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

        -- 启动每帧更新
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
    -- 如果玩家死亡，停止所有移动
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
        
        -- 如果固定模式开启，更新BodyGyro来防止旋转
        if _G.fixedMode and data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro.CFrame = part.CFrame
        end
    end
end

-- 停止所有零件移动
local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- 防止物体旋转
local function PreventRotation()
    _G.fixedMode = true
    -- 为所有已处理的零件添加BodyGyro
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

-- 允许物体旋转
local function AllowRotation()
    _G.fixedMode = false
    -- 移除所有BodyGyro
    for part, data in pairs(_G.processedParts) do
        if data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro:Destroy()
            data.bodyGyro = nil
        end
    end
    UpdateAllPartsVelocity()
end

-- 切换防旋转模式
local function ToggleRotationPrevention()
    if _G.fixedMode then
        AllowRotation()
        return false
    else
        PreventRotation()
        return true
    end
end

-- 使GUI元素可拖动的函数
local function MakeDraggable(gui)
    gui.Active = true
    gui.Draggable = true

    local dragHandle = Instance.new("Frame")
    dragHandle.Name = "DragHandle"
    dragHandle.Size = UDim2.new(0, 20, 0, 20)
    dragHandle.Position = UDim2.new(1, -20, 0, 0)
    dragHandle.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
    dragHandle.BorderSizePixel = 0
    dragHandle.Parent = gui

    local gripIcon = Instance.new("TextLabel")
    gripIcon.Name = "GripIcon"
    gripIcon.Size = UDim2.new(1, 0, 1, 0)
    gripIcon.Position = UDim2.new(0, 0, 0, 0)
    gripIcon.Text = "≡"
    gripIcon.TextColor3 = Color3.new(1, 1, 1)
    gripIcon.BackgroundTransparency = 1
    gripIcon.TextSize = 14
    gripIcon.Parent = dragHandle

    dragHandle.Active = true
    dragHandle.Draggable = true
end

-- 创建手机友好的GUI
local function CreateMobileGUI()
    print("开始创建GUI...")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主开关按钮 - 移动到右上角
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10) -- 右上角位置
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 16
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1, 1, 1)
    mainButton.Parent = screenGui

    MakeDraggable(mainButton)
    print("主按钮创建完成")

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 300, 0, 500) -- 增加高度以容纳新按钮
    controlPanel.Position = UDim2.new(0.5, -150, 0.5, -250)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    MakeDraggable(controlPanel)
    print("控制面板创建完成")

    -- 速度控制
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Name = "SpeedLabel"
    speedLabel.Size = UDim2.new(1, 0, 0, 40)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. _G.floatSpeed
    speedLabel.TextColor3 = Color3.new(1, 1, 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 20
    speedLabel.Parent = controlPanel

    -- 速度增加按钮
    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Name = "SpeedUp"
    speedUpButton.Size = UDim2.new(0, 60, 0, 60)
    speedUpButton.Position = UDim2.new(0.7, 0, 0, 60)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 30
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    speedUpButton.TextColor3 = Color3.new(1, 1, 1)
    speedUpButton.Parent = controlPanel

    -- 速度减少按钮
    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Name = "SpeedDown"
    speedDownButton.Size = UDim2.new(0, 60, 0, 60)
    speedDownButton.Position = UDim2.new(0.3, 0, 0, 60)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 30
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    speedDownButton.TextColor3 = Color3.new(1, 1, 1)
    speedDownButton.Parent = controlPanel

    -- 停止按钮
    local stopButton = Instance.new("TextButton")
    stopButton.Name = "Stop"
    stopButton.Size = UDim2.new(0, 100, 0, 40)
    stopButton.Position = UDim2.new(0.5, -50, 0, 130)
    stopButton.Text = "停止移动"
    stopButton.TextSize = 16
    stopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    stopButton.TextColor3 = Color3.new(1, 1, 1)
    stopButton.Parent = controlPanel

    -- 防止旋转按钮
    local fixButton = Instance.new("TextButton")
    fixButton.Name = "FixRotation"
    fixButton.Size = UDim2.new(0, 120, 0, 40)
    fixButton.Position = UDim2.new(0.5, -60, 0, 180)
    fixButton.Text = "防止旋转: 关闭"
    fixButton.TextSize = 16
    fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    fixButton.TextColor3 = Color3.new(1, 1, 1)
    fixButton.Parent = controlPanel

    MakeDraggable(fixButton)

    -- 方向控制标题
    local directionLabel = Instance.new("TextLabel")
    directionLabel.Name = "DirectionLabel"
    directionLabel.Size = UDim2.new(1, 0, 0, 40)
    directionLabel.Position = UDim2.new(0, 0, 0, 230) -- 调整位置
    directionLabel.Text = "移动方向 (基于视角)"
    directionLabel.TextColor3 = Color3.new(1, 1, 1)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextSize = 20
    directionLabel.Parent = controlPanel

    -- 方向按钮网格 - 现在基于视角方向
    local directions = {
        {name = "向上", dir = "up", pos = UDim2.new(0.5, -30, 0, 280)},
        {name = "向下", dir = "down", pos = UDim2.new(0.5, -30, 0, 350)},
        {name = "向前", dir = "forward", pos = UDim2.new(0.2, -30, 0, 315)},
        {name = "向后", dir = "back", pos = UDim2.new(0.8, -30, 0, 315)},
        {name = "向左", dir = "left", pos = UDim2.new(0.05, -30, 0, 315)},
        {name = "向右", dir = "right", pos = UDim2.new(0.95, -30, 0, 315)}
    }

    for i, dirInfo in ipairs(directions) do
        local button = Instance.new("TextButton")
        button.Name = dirInfo.name
        button.Size = UDim2.new(0, 60, 0, 60)
        button.Position = dirInfo.pos
        button.Text = dirInfo.name
        button.TextSize = 14
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Parent = controlPanel

        button.MouseButton1Click:Connect(function()
            -- 如果玩家死亡，不允许更改方向
            if isPlayerDead then
                local warningMsg = Instance.new("Message")
                warningMsg.Text = "玩家死亡时无法更改漂浮方向"
                warningMsg.Parent = Workspace
                delay(2, function()
                    warningMsg:Destroy()
                end)
                return
            end
            
            _G.moveDirectionType = dirInfo.dir
            UpdateAllPartsVelocity()

            local originalColor = button.BackgroundColor3
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
            delay(0.2, function()
                button.BackgroundColor3 = originalColor
            end)
        end)
    end

    -- 关闭面板按钮
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "ClosePanel"
    closeButton.Size = UDim2.new(0, 100, 0, 40)
    closeButton.Position = UDim2.new(0.5, -50, 0, 430) -- 调整位置
    closeButton.Text = "关闭面板"
    closeButton.TextSize = 16
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Parent = controlPanel

    -- 速度按钮功能
    speedUpButton.MouseButton1Click:Connect(function()
        -- 如果玩家死亡，不允许更改速度
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法更改漂浮速度"
            warningMsg.Parent = Workspace
            delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 1, 100) -- 最大速度增加到100
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()

        local originalColor = speedUpButton.BackgroundColor3
        speedUpButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        delay(0.2, function()
            speedUpButton.BackgroundColor3 = originalColor
        end)
    end)

    -- 修复减速度按钮的bug
    speedDownButton.MouseButton1Click:Connect(function()
        -- 如果玩家死亡，不允许更改速度
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法更改漂浮速度"
            warningMsg.Parent = Workspace
            delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 1, 100) -- 最大速度增加到100
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()

        local originalColor = speedDownButton.BackgroundColor3
        speedDownButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        delay(0.2, function()
            speedDownButton.BackgroundColor3 = originalColor
        end)
    end)

    -- 停止按钮功能
    stopButton.MouseButton1Click:Connect(function()
        -- 如果玩家死亡，不允许操作
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法操作漂浮功能"
            warningMsg.Parent = Workspace
            delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        StopAllParts()
        speedLabel.Text = "速度: " .. _G.floatSpeed

        local originalColor = stopButton.BackgroundColor3
        stopButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        delay(0.2, function()
            stopButton.BackgroundColor3 = originalColor
        end)
    end)

    -- 防止旋转按钮功能
    fixButton.MouseButton1Click:Connect(function()
        -- 如果玩家死亡，不允许操作
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法操作防旋转功能"
            warningMsg.Parent = Workspace
            delay(2, function()
                warningMsg:Destroy()
            end)
            return
        end
        
        local newFixedState = ToggleRotationPrevention()
        if newFixedState then
            fixButton.Text = "防止旋转: 开启"
            fixButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            print("防旋转模式已开启")
        else
            fixButton.Text = "防止旋转: 关闭"
            fixButton.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
            print("防旋转模式已关闭")
        end
    end)

    -- 打开面板按钮 - 移动到右上角，在主按钮下方
    local openPanelButton = Instance.new("TextButton")
    openPanelButton.Name = "OpenPanel"
    openPanelButton.Size = UDim2.new(0, 120, 0, 40)
    openPanelButton.Position = UDim2.new(1, -130, 0, 70) -- 右上角位置，在主按钮下方
    openPanelButton.Text = "打开控制面板"
    openPanelButton.TextSize = 14
    openPanelButton.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
    openPanelButton.TextColor3 = Color3.new(1, 1, 1)
    openPanelButton.Visible = true  -- 初始状态为可见
    openPanelButton.Parent = screenGui

    MakeDraggable(openPanelButton)

    -- 主开关功能
    mainButton.MouseButton1Click:Connect(function()
        -- 如果玩家死亡，不允许开启漂浮
        if isPlayerDead then
            local warningMsg = Instance.new("Message")
            warningMsg.Text = "玩家死亡时无法开启漂浮功能"
            warningMsg.Parent = Workspace
            delay(2, function()
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
            print("漂浮功能已开启")
        else
            CleanupParts()
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            print("漂浮功能已关闭")
        end
    end)

    -- 关闭面板功能
    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
        openPanelButton.Visible = true
        print("控制面板已关闭")
    end)

    -- 打开面板功能
    openPanelButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = true
        openPanelButton.Visible = false
        print("控制面板已打开")
    end)

    print("GUI创建完成")
    return screenGui
end

-- 添加错误处理
local success, err = pcall(function()
    CreateMobileGUI()
    -- 设置死亡检测
    setupDeathDetection()
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

print("全局物体漂浮脚本已加载成功!")
