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

-- 作者提示
pcall(function()
    local authorMessage = Instance.new("Message")
    authorMessage.Text = "全局物体漂浮脚本（NetworkOwner 分支） - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n由Star_Skater53帮忙优化，这个版本别人应该能看到"
    authorMessage.Parent = Workspace
    task.delay(3, function() if authorMessage and authorMessage.Parent then authorMessage:Destroy() end end)
end)

-- ================= 全局状态 =================
_G.processedParts = _G.processedParts or {}
_G.floatSpeed = _G.floatSpeed or 10
_G.moveDirectionType = _G.moveDirectionType or "up"  -- 初始方向
_G.fixedMode = _G.fixedMode or false
_G.cachedMoveVector = _G.cachedMoveVector or Vector3.new(0, 1, 0) -- 缓存方向（点击时更新）
_G.useNetworkOwnership = _G.useNetworkOwnership or false -- 新增：是否使用网络所有权

local isPlayerDead = false
local anActivity = false
local updateConnection = nil

-- GUI 引用
local mainButton
local controlPanel
local speedLabel
local networkBtn

-- 设置模拟半径
local function setupSimulationRadius()
    local success, err = pcall(function()
        RunService.Heartbeat:Connect(function()
            pcall(function()
                if LocalPlayer then
                    sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
                    sethiddenproperty(LocalPlayer, "MaxSimulationRadius", math.huge)
                end
            end)
        end)
    end)
    if not success then
        warn("模拟半径设置失败: " .. tostring(err))
    end
end
setupSimulationRadius()

-- ================= 辅助函数 =================
local function isPartEligible(part)
    if not part or not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if part:IsDescendantOf(LocalPlayer.Character or {}) then return false end
    local parent = part.Parent
    if not parent then return true end
    if parent:FindFirstChildOfClass("Humanoid") then return false end
    if parent:FindFirstChild("Head") then return false end
    return true
end

-- ================ 只在点击时缓存相机方向 ================
local function CacheMoveDirection(dirType)
    local camera = workspace.CurrentCamera
    if not camera then
        -- 如果没有相机，保留原缓存
        return
    end

    if dirType == "up" then
        _G.cachedMoveVector = Vector3.new(0, 1, 0)
        return
    elseif dirType == "down" then
        _G.cachedMoveVector = Vector3.new(0, -1, 0)
        return
    end

    local look = camera.CFrame.LookVector
    local right = camera.CFrame.RightVector

    if dirType == "forward" then
        local v = Vector3.new(look.X, 0, look.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0, 0, 0)
    elseif dirType == "back" then
        local v = -Vector3.new(look.X, 0, look.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0, 0, 0)
    elseif dirType == "right" then
        local v = Vector3.new(right.X, 0, right.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0, 0, 0)
    elseif dirType == "left" then
        local v = -Vector3.new(right.X, 0, right.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0, 0, 0)
    end
end

-- ================ 使用缓存方向 ================
local function CalculateMoveDirection()
    if isPlayerDead then return Vector3.new(0, 0, 0) end
    -- 优先使用缓存（由点击更新）；如果没有缓存则退回默认向上
    return _G.cachedMoveVector or Vector3.new(0, 1, 0)
end

local function ReleaseNetworkOwnershipForPart(part)
    if not part or not part:IsA("BasePart") then return end
    -- 设为 nil 释放网络所有权；使用 pcall 避免在某些环境报错
    pcall(function()
        if part.SetNetworkOwner then
            part:SetNetworkOwner(nil)
        end
    end)
end

local function AssignNetworkOwnershipToPart(part)
    if not part or not part:IsA("BasePart") then return end
    pcall(function()
        if part.SetNetworkOwner then
            part:SetNetworkOwner(LocalPlayer)
        end
    end)
end

local function CleanupParts()
    for part, data in pairs(_G.processedParts) do
        pcall(function() if data.bodyVelocity then data.bodyVelocity:Destroy() end end)
        pcall(function() if data.bodyGyro then data.bodyGyro:Destroy() end end)
        -- 释放网络所有权
        pcall(function() ReleaseNetworkOwnershipForPart(part) end)
    end
    _G.processedParts = {}
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

-- ✅ 修复防旋转逻辑
local function UpdateAllPartsVelocity()
    if isPlayerDead then
        for _, data in pairs(_G.processedParts) do
            if data.bodyVelocity and data.bodyVelocity.Parent then
                data.bodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end
        return
    end
    local dir = CalculateMoveDirection()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = dir * _G.floatSpeed
        end
        if _G.fixedMode then
            -- 完全锁死旋转
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

local function ProcessPart(part)
    if isPlayerDead then return end
    if not isPartEligible(part) then return end

    local entry = _G.processedParts[part]
    if entry and entry.bodyVelocity and entry.bodyVelocity.Parent then
        entry.bodyVelocity.Velocity = CalculateMoveDirection() * _G.floatSpeed
        -- 如果启用了网络所有权，确保已经赋予
        if _G.useNetworkOwnership then
            pcall(function() AssignNetworkOwnershipToPart(part) end)
        end
        return
    end

    -- 清除已有 BodyMover（避免冲突）
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("BodyMover") then
            pcall(function() child:Destroy() end)
        end
    end

    local bv = Instance.new("BodyVelocity")
    bv.Parent = part
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = CalculateMoveDirection() * _G.floatSpeed

    local bg = nil
    if _G.fixedMode then
        bg = Instance.new("BodyGyro")
        bg.Parent = part
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.P = 1000
        bg.D = 100
    end

    -- 如果开启网络所有权，则尝试把该部件的网络所有权分配给本地玩家
    if _G.useNetworkOwnership then
        pcall(function() AssignNetworkOwnershipToPart(part) end)
    end

    _G.processedParts[part] = { bodyVelocity = bv, bodyGyro = bg }
end

local function ProcessAllParts()
    if isPlayerDead then
        anActivity = false
        CleanupParts()
        return
    end
    if updateConnection then updateConnection:Disconnect() end

    -- 启动/批量处理前，先缓存一次当前方向（确保首次开启即以当时相机朝向为准）
    CacheMoveDirection(_G.moveDirectionType)

    for _, v in ipairs(Workspace:GetDescendants()) do
        pcall(function() ProcessPart(v) end)
    end
    updateConnection = RunService.Heartbeat:Connect(UpdateAllPartsVelocity)
end

local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
    CleanupParts()
end

-- 切换防旋转
local function ToggleRotationPrevention()
    if _G.fixedMode then
        _G.fixedMode = false
        for _, data in pairs(_G.processedParts) do
            if data.bodyGyro then
                pcall(function() data.bodyGyro:Destroy() end)
                data.bodyGyro = nil
            end
        end
        return false
    else
        _G.fixedMode = true
        for part, data in pairs(_G.processedParts) do
            if not data.bodyGyro then
                local bg = Instance.new("BodyGyro")
                bg.Parent = part
                bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bg.P = 1000
                bg.D = 100
                data.bodyGyro = bg
            end
        end
        return true
    end
end

-- 切换网络所有权（按钮调用）
local function ToggleNetworkOwnership()
    _G.useNetworkOwnership = not _G.useNetworkOwnership
    -- 如果开启则为现有 processed parts 赋权；如果关闭则释放
    for part, data in pairs(_G.processedParts) do
        if _G.useNetworkOwnership then
            pcall(function() AssignNetworkOwnershipToPart(part) end)
        else
            pcall(function() ReleaseNetworkOwnershipForPart(part) end)
        end
    end
    return _G.useNetworkOwnership
end

-- 死亡/重生处理
local humanoidDiedConnection = nil
local function onCharacterAdded(char)
    isPlayerDead = false
    anActivity = false
    CleanupParts()
    if mainButton then
        mainButton.Text = "漂浮: 关闭"
        mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    end
    if controlPanel then
        controlPanel.Visible = false
    end
    local humanoid = char:WaitForChild("Humanoid")
    if humanoid then
        if humanoidDiedConnection then humanoidDiedConnection:Disconnect() end
        humanoidDiedConnection = humanoid.Died:Connect(function()
            isPlayerDead = true
            if anActivity then
                anActivity = false
                CleanupParts()
                if mainButton then
                    mainButton.Text = "漂浮: 关闭"
                    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
                end
                if controlPanel then
                    controlPanel.Visible = false
                end
            end
        end)
    end
end
Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if Players.LocalPlayer.Character then onCharacterAdded(Players.LocalPlayer.Character) end

-- ================ 可拖动辅助（支持鼠标与触控） ================
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

-- ================ GUI  ================
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false

    -- 主开关按钮
    mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 50)
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui

    -- 使主按钮可拖动
    makeDraggable(mainButton)

    -- 打开和关闭控制面板按钮
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 120)
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    panelToggle.TextColor3 = Color3.new(1,1,1)
    panelToggle.Parent = screenGui
    makeDraggable(panelToggle)

    -- 控制面板
    controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 260, 0, 420)
    controlPanel.Position = UDim2.new(1, -400, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.Active = true
    controlPanel.Draggable = true
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    panelToggle.MouseButton1Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
    end)

    -- 内容
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,0,1,0)
    content.BackgroundTransparency = 1
    content.Parent = controlPanel

    -- 速度显示
    speedLabel = Instance.new("TextLabel")
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

    -- 防旋转按钮
    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85,0,0,30)
    fixBtn.Position = UDim2.new(0.075,0,0,140)
    fixBtn.Text = "防止旋转: 关闭"
    fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    fixBtn.TextColor3 = Color3.new(1,1,1)
    fixBtn.Parent = content

    -- 网络所有权按钮
    networkBtn = Instance.new("TextButton")
    networkBtn.Size = UDim2.new(0.85,0,0,30)
    networkBtn.Position = UDim2.new(0.075,0,0,180)
    networkBtn.Text = "网络所有权: 关闭"
    networkBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    networkBtn.TextColor3 = Color3.new(1,1,1)
    networkBtn.Parent = content

    -- 十字架方向按钮
    local dirButtons = {
        {name="上", dir="up", pos=UDim2.new(0.35,0,0,230)},
        {name="下", dir="down", pos=UDim2.new(0.35,0,0,300)},
        {name="左", dir="left", pos=UDim2.new(0.05,0,0,265)},
        {name="右", dir="right", pos=UDim2.new(0.65,0,0,265)},
        {name="前", dir="forward", pos=UDim2.new(0.2,0,0,265)},
        {name="后", dir="back", pos=UDim2.new(0.5,0,0,265)},
    }

    for _, info in ipairs(dirButtons) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.15,0,0,35)
        b.Position = info.pos
        b.Text = info.name
        b.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
        b.TextColor3 = Color3.new(1,1,1)
        b.Parent = content

        -- 仅在点击时缓存当前相机方向
        b.MouseButton1Click:Connect(function()
            _G.moveDirectionType = info.dir
            CacheMoveDirection(info.dir)   -- 这里是关键：单次缓存，不会每帧变化
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            ProcessAllParts()
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            CleanupParts()
            controlPanel.Visible = false
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        StopAllParts()
    end)

    fixBtn.MouseButton1Click:Connect(function()
        local on = ToggleRotationPrevention()
        if on then
            fixBtn.Text = "防止旋转: 开启"
            fixBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            fixBtn.Text = "防止旋转: 关闭"
            fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    networkBtn.MouseButton1Click:Connect(function()
        local on = ToggleNetworkOwnership()
        if on then
            networkBtn.Text = "网络所有权: 开启"
            networkBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        else
            networkBtn.Text = "网络所有权: 关闭"
            networkBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
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
end

-- 初始化 GUI
CreateMobileGUI()
print("全局物体漂浮脚本（NetworkOwner 分支）已加载😋")
