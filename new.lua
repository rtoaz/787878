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
local authorMessage = Instance.new("TextLabel")
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n由Star_Skater53帮忙优化"
authorMessage.Size = UDim2.new(0, 400, 0, 100)
authorMessage.Position = UDim2.new(0.5, -200, 0, 10)
authorMessage.TextColor3 = Color3.fromRGB(255, 255, 255)
authorMessage.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
authorMessage.BackgroundTransparency = 0.5
authorMessage.Parent = Workspace
task.delay(3, function() authorMessage:Destroy() end)

-- ================= 全局状态 =================
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"  -- 设置初始漂浮方向为向上
_G.fixedMode = false  -- 默认允许旋转

local isPlayerDead = false
local anActivity = false
local updateConnection = nil

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

-- GUI 引用
local mainButton
local controlPanel
local speedLabel

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

local function CalculateMoveDirection()
    if isPlayerDead then return Vector3.new(0,0,0) end
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.new(0,1,0) end
    local dir = _G.moveDirectionType
    if dir == "up" then return Vector3.new(0,1,0) end
    if dir == "down" then return Vector3.new(0,-1,0) end
    if dir == "forward" then
        local v = Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new()
    end
    if dir == "back" then
        local v = -Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new()
    end
    if dir == "right" then
        local v = Vector3.new(camera.CFrame.RightVector.X,0,camera.CFrame.RightVector.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new()
    end
    if dir == "left" then
        local v = -Vector3.new(camera.CFrame.RightVector.X,0,camera.CFrame.RightVector.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new()
    end
    return Vector3.new(0,1,0)
end

local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        pcall(function() if data.bodyVelocity then data.bodyVelocity:Destroy() end end)
        pcall(function() if data.bodyGyro then data.bodyGyro:Destroy() end end)
    end
    _G.processedParts = {}
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

local function UpdateAllPartsVelocity()
    if isPlayerDead then
        for _, data in pairs(_G.processedParts) do
            if data.bodyVelocity and data.bodyVelocity.Parent then
                data.bodyVelocity.Velocity = Vector3.new(0,0,0)
            end
        end
        return
    end
    local dir = CalculateMoveDirection()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = dir * _G.floatSpeed
        end
        if _G.fixedMode and data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro.CFrame = part.CFrame
        end
    end
end

local function ProcessPart(part)
    if isPlayerDead then return end
    if not isPartEligible(part) then return end
    local entry = _G.processedParts[part]
    if entry and entry.bodyVelocity and entry.bodyVelocity.Parent then
        entry.bodyVelocity.Velocity = CalculateMoveDirection() * _G.floatSpeed
        return
    end
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("BodyMover") then pcall(function() child:Destroy() end) end
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
    _G.processedParts[part] = {bodyVelocity = bv, bodyGyro = bg}
end

local function ProcessAllParts()
    if isPlayerDead then
        anActivity = false
        CleanupParts()
        return
    end
    if updateConnection then updateConnection:Disconnect() end
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

local function ToggleRotationPrevention()
    if _G.fixedMode then
        -- 禁用防止旋转，允许物体自由旋转
        _G.fixedMode = false
        for _, data in pairs(_G.processedParts) do
            if data.bodyGyro then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil  -- 设置为 nil
            end
        end
        return false
    else
        -- 启用防止旋转
        _G.fixedMode = true
        for part, data in pairs(_G.processedParts) do
            if not data.bodyGyro then
                -- 如果没有 BodyGyro，添加一个
                data.bodyGyro = Instance.new("BodyGyro")
                data.bodyGyro.Parent = part
                data.bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                data.bodyGyro.P = 1000
                data.bodyGyro.D = 100
            end
        end
        return true
    end
end

-- 死亡/重生
local humanoidDiedConnection = nil
local function onCharacterAdded(char)
    isPlayerDead = false
    anActivity = false
    CleanupParts()
    if mainButton then
        mainButton.Text = "漂浮: 关闭"
        mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
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
                    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
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

-- GUI 创建
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false

    -- 主开关按钮
    mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 50)  -- 向上偏移
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui

    -- 控制面板按钮
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 120)  -- 向上偏移
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)  -- 更亮的蓝色
    panelToggle.TextColor3 = Color3.new(1,1,1)
    panelToggle.Parent = screenGui

    -- 控制面板
    controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 220, 0, 360)
    controlPanel.Position = UDim2.new(1, -360, 0, 10)
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
    speedUp.BackgroundColor3 = Color3.fromRGB(0, 150, 255)  -- 更亮的蓝色
    speedUp.TextColor3 = Color3.new(1,1,1)
    speedUp.Parent = content

    -- 减速按钮（-）
    local speedDown = Instance.new("TextButton")
    speedDown.Size = UDim2.new(0.4,0,0,30)
    speedDown.Position = UDim2.new(0.55,0,0,50)
    speedDown.Text = "-"
    speedDown.BackgroundColor3 = Color3.fromRGB(0, 150, 255)  -- 更亮的蓝色
    speedDown.TextColor3 = Color3.new(1,1,1)
    speedDown.Parent = content

    -- 停止移动按钮
    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.85,0,0,30)
    stopBtn.Position = UDim2.new(0.075,0,0,100)
    stopBtn.Text = "停止移动"
    stopBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
    stopBtn.TextColor3 = Color3.new(1,1,1)
    stopBtn.Parent = content

    -- 防旋转按钮
    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85,0,0,30)
    fixBtn.Position = UDim2.new(0.075,0,0,140)
    fixBtn.Text = "防止旋转: 关闭"
    fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
    fixBtn.TextColor3 = Color3.new(1,1,1)
    fixBtn.Parent = content

    -- 十字架方向按钮
    local dirButtons = {
        {name="上", dir="up", pos=UDim2.new(0.35,0,0,190)},
        {name="下", dir="down", pos=UDim2.new(0.35,0,0,260)},
        {name="左", dir="left", pos=UDim2.new(0.2,0,0,225)},
        {name="右", dir="right", pos=UDim2.new(0.5,0,0,225)},
        {name="前", dir="forward", pos=UDim2.new(0.05,0,0,225)}, -- 左的左边
        {name="后", dir="back", pos=UDim2.new(0.65,0,0,225)},    -- 右的右边
    }

    for _,info in ipairs(dirButtons) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.15,0,0,35)
        b.Position = info.pos
        b.Text = info.name
        b.BackgroundColor3 = Color3.fromRGB(0, 150, 255)  -- 更亮的蓝色
        b.TextColor3 = Color3.new(1,1,1)
        b.Parent = content
        b.MouseButton1Click:Connect(function()
            _G.moveDirectionType = info.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)  -- 纯绿色
            ProcessAllParts()
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
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
            fixBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)  -- 纯绿色
        else
            fixBtn.Text = "防止旋转: 关闭"
            fixBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- 纯红色
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

-- 初始化
CreateMobileGUI()
print("全局物体漂浮脚本已加载")
