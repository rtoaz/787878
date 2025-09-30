-- 全局物体漂浮 脚本 - 最终修复版
-- 功能：全局漂浮（速度/方向/防旋转控制）、手机/鼠标友好GUI、死亡/重生自动清理与断开、性能优化

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- 等待加载与本地玩家
if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- 作者提示（第一版内容）
local authorMessage = Instance.new("Message")
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
task.delay(3, function()
    authorMessage:Destroy()
end)

-- ================= 全局状态 =================
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"
_G.fixedMode = false

if not _G.FloatingStateChanged then
    _G.FloatingStateChanged = Instance.new("BindableEvent")
    _G.FloatingStateChanged.Name = "FloatingStateChanged"
end

local isPlayerDead = false
local anActivity = false
local updateConnection = nil
local simulationHeartbeat = nil

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
    if _G.moveDirectionType == "up" then
        return Vector3.new(0,1,0)
    elseif _G.moveDirectionType == "down" then
        return Vector3.new(0,-1,0)
    elseif _G.moveDirectionType == "forward" then
        local lv = camera.CFrame.LookVector
        local v = Vector3.new(lv.X,0,lv.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new(0,0,0)
    elseif _G.moveDirectionType == "back" then
        local lv = camera.CFrame.LookVector
        local v = -Vector3.new(lv.X,0,lv.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new(0,0,0)
    elseif _G.moveDirectionType == "right" then
        local rv = camera.CFrame.RightVector
        local v = Vector3.new(rv.X,0,rv.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new(0,0,0)
    elseif _G.moveDirectionType == "left" then
        local rv = camera.CFrame.RightVector
        local v = -Vector3.new(rv.X,0,rv.Z)
        return (v.Magnitude > 0 and v.Unit) or Vector3.new(0,0,0)
    else
        return Vector3.new(0,1,0)
    end
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

local function PreventRotation()
    _G.fixedMode = true
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            if not data.bodyGyro or not data.bodyGyro.Parent then
                local bg = Instance.new("BodyGyro")
                bg.Parent = part
                bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bg.P = 1000
                bg.D = 100
                data.bodyGyro = bg
            end
        end
    end
end

local function AllowRotation()
    _G.fixedMode = false
    for _, data in pairs(_G.processedParts) do
        if data.bodyGyro and data.bodyGyro.Parent then
            data.bodyGyro:Destroy()
            data.bodyGyro = nil
        end
    end
end

local function ToggleRotationPrevention()
    if _G.fixedMode then
        AllowRotation()
        return false
    else
        PreventRotation()
        return true
    end
end

-- SimulationRadius 设置（优化）
local function setupSimulationRadius()
    if not syn and not sethiddenproperty then return end
    local attempts = 0
    simulationHeartbeat = RunService.Heartbeat:Connect(function()
        attempts += 1
        local ok = pcall(function()
            sethiddenproperty(LocalPlayer,"SimulationRadius",math.huge)
            sethiddenproperty(LocalPlayer,"MaxSimulationRadius",math.huge)
        end)
        if ok or attempts >= 10 then
            simulationHeartbeat:Disconnect()
            simulationHeartbeat = nil
        end
    end)
end

-- 死亡/重生
local humanoidDiedConnection = nil
local function onCharacterAdded(char)
    isPlayerDead = false
    anActivity = false
    CleanupParts()
    local humanoid = char:WaitForChild("Humanoid")
    if humanoid then
        if humanoidDiedConnection then humanoidDiedConnection:Disconnect() end
        humanoidDiedConnection = humanoid.Died:Connect(function()
            isPlayerDead = true
            if anActivity then
                anActivity = false
                CleanupParts()
                _G.FloatingStateChanged:Fire({state="disabled",reason="player_died"})
            end
        end)
    end
end

local function setupDeathDetection()
    LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
    if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end
end

Workspace.DescendantAdded:Connect(function(v)
    if anActivity and not isPlayerDead then
        pcall(function() ProcessPart(v) end)
    end
end)

-- GUI 创建
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("MobileFloatingControl") then return end
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = playerGui
    screenGui.ResetOnSpawn = false

    -- 主开关按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(200,50,50)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 220, 0, 320)
    controlPanel.Position = UDim2.new(1, -360, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    -- 标题栏（拖动）
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.BackgroundColor3 = Color3.fromRGB(40,40,40)
    titleBar.Parent = controlPanel

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -40, 1, 0)
    titleText.Position = UDim2.new(0, 8, 0, 0)
    titleText.Text = "漂浮控制面板"
    titleText.TextColor3 = Color3.new(1,1,1)
    titleText.BackgroundTransparency = 1
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,30,0,30)
    closeBtn.Position = UDim2.new(1, -34, 0, 0)
    closeBtn.Text = "X"
    closeBtn.Parent = titleBar

    -- 拖动逻辑
    local dragStart, panelStart
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragStart = input.Position
            panelStart = controlPanel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragStart = nil
                end
            end)
        end
    end)
    titleBar.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and dragStart then
            local delta = input.Position - dragStart
            controlPanel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X, panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
        end
    end)

    -- 面板开关按钮
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 70)
    panelToggle.Text = "控制面板"
    panelToggle.Parent = screenGui
    panelToggle.MouseButton1Click:Connect(function() controlPanel.Visible = not controlPanel.Visible end)
    closeBtn.MouseButton1Click:Connect(function() controlPanel.Visible = false end)

    -- 内容
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -30)
    content.Position = UDim2.new(0,0,0,30)
    content.BackgroundTransparency = 1
    content.Parent = controlPanel

    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, -20, 0, 24)
    speedLabel.Position = UDim2.new(0, 10, 0, 8)
    speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextColor3 = Color3.new(1,1,1)
    speedLabel.Parent = content

    local speedUp = Instance.new("TextButton")
    speedUp.Size = UDim2.new(0, 40, 0, 36)
    speedUp.Position = UDim2.new(0.7, 0, 0, 36)
    speedUp.Text = "+"
    speedUp.Parent = content

    local speedDown = Instance.new("TextButton")
    speedDown.Size = UDim2.new(0, 40, 0, 36)
    speedDown.Position = UDim2.new(0.2, 0, 0, 36)
    speedDown.Text = "-"
    speedDown.Parent = content

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.85, 0, 0, 30)
    stopBtn.Position = UDim2.new(0.075, 0, 0, 84)
    stopBtn.Text = "停止移动"
    stopBtn.Parent = content

    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85, 0, 0, 30)
    fixBtn.Position = UDim2.new(0.075, 0, 0, 124)
    fixBtn.Text = "防止旋转: 关闭"
    fixBtn.Parent = content

    local dirLabel = Instance.new("TextLabel")
    dirLabel.Size = UDim2.new(1, -20, 0, 20)
    dirLabel.Position = UDim2.new(0,10,0,170)
    dirLabel.Text = "移动方向"
    dirLabel.BackgroundTransparency = 1
    dirLabel.TextColor3 = Color3.new(1,1,1)
    dirLabel.Parent = content

    local directions = {
        {name="向上", dir="up", pos=UDim2.new(0.5,-20,0,200)},
        {name="向下", dir="down", pos=UDim2.new(0.5,-20,0,240)},
        {name="向前", dir="forward", pos=UDim2.new(0.18,-20,0,220)},
        {name="向后", dir="back", pos=UDim2.new(0.82,-20,0,220)},
        {name="向左", dir="left", pos=UDim2.new(0.03,-20,0,220)},
        {name="向右", dir="right", pos=UDim2.new(0.97,-20,0,220)},
    }
    for _, d in ipairs(directions) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 46, 0, 28)
        b.Position = d.pos
        b.Text = d.name
        b.Parent = content
        b.MouseButton1Click:Connect(function()
            if isPlayerDead then return end
            _G.moveDirectionType = d.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(50,200,50)
            ProcessAllParts()
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(200,50,50)
            CleanupParts()
        end
    end)

    speedUp.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 1, 200)
        speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
        UpdateAllPartsVelocity()
    end)

    speedDown.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 0, 200)
        speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
        UpdateAllPartsVelocity()
    end)

    stopBtn.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        StopAllParts()
    end)

    fixBtn.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        local on = ToggleRotationPrevention()
        if on then
            fixBtn.Text = "防止旋转: 开启"
        else
            fixBtn.Text = "防止旋转: 关闭"
        end
    end)
end

-- 初始化
pcall(function()
    setupSimulationRadius()
    setupDeathDetection()
    CreateMobileGUI()
end)

print("全局物体漂浮脚本（最终修复版）已加载")
