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
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil  -- 将销毁后的 bodyGyro 设置为 nil
            end
        end
        return false
    else
        -- 启用防止旋转，禁止物体旋转
        _G.fixedMode = true
        for _, data in pairs(_G.processedParts) do
            if data.bodyGyro and not data.bodyGyro.Parent then
                -- 添加或恢复旋转防止机制
                data.bodyGyro = Instance.new("BodyGyro")
                data.bodyGyro.Parent = data.part
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

    -- 使漂浮按钮可拖动 (移动端)
    local dragStartPos
    local function startDrag(input)
        dragStartPos = input.Position
    end

    mainButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            startDrag(input)
        end
    end)

    mainButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch and dragStartPos then
            local delta = input.Position - dragStartPos
            mainButton.Position = UDim2.new(0, mainButton.Position.X.Offset + delta.X, 0, mainButton.Position.Y.Offset + delta.Y)
            dragStartPos = input.Position
        end
    end)

    -- 控制面板按钮
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 120)  -- 向上偏移
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 255)  -- 更亮的蓝色
    panelToggle.TextColor3 = Color3.new(1,1,1)
    panelToggle.Parent = screenGui

    -- 使控制面板按钮可拖动 (移动端)
    controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 220, 0, 360)
    controlPanel.Position = UDim2.new(1, -360, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.Active = true
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    panelToggle.MouseButton1Click:Connect(function()
        controlPanel.Visible = not controlPanel.Visible
    end)

    -- 使控制面板可拖动
    local dragStartPosPanel
    local function startDragPanel(input)
        dragStartPosPanel = input.Position
    end

    controlPanel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            startDragPanel(input)
        end
    end)

    controlPanel.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch and dragStartPosPanel then
            local delta = input.Position - dragStartPosPanel
            controlPanel.Position = UDim2.new(0, controlPanel.Position.X.Offset + delta.X, 0, controlPanel.Position.Y.Offset + delta.Y)
            dragStartPosPanel = input.Position
        end
    end)
end

-- 初始化
CreateMobileGUI()
print("全局物体漂浮脚本已加载")
