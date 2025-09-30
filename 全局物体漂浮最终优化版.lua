local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- 作者提示
local authorMessage = Instance.new("Message")
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n注意：此脚本的控制按键最好不要短时间内连续点击并长按，会出现颜色故障\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
task.delay(3, function() authorMessage:Destroy() end)

-- ================= 全局状态 =================
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"
_G.fixedMode = false

local isPlayerDead = false
local anActivity = false
local updateConnection = nil
local simulationHeartbeat = nil

-- GUI 引用
local mainButton
local controlPanel
local notifyLabel

-- ================= 辅助函数 =================
local function showNotify(msg)
    if not notifyLabel then return end
    notifyLabel.Text = msg
    notifyLabel.Visible = true
    task.delay(2, function()
        notifyLabel.Visible = false
    end)
end

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
        _G.fixedMode = false
        for _, data in pairs(_G.processedParts) do
            if data.bodyGyro and data.bodyGyro.Parent then
                data.bodyGyro:Destroy()
                data.bodyGyro = nil
            end
        end
        return false
    else
        _G.fixedMode = true
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
        mainButton.BackgroundColor3 = Color3.fromRGB(200,50,50)
    end
    if controlPanel then controlPanel.Visible = false end
    showNotify("漂浮已关闭")
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
                    mainButton.BackgroundColor3 = Color3.fromRGB(200,50,50)
                end
                if controlPanel then controlPanel.Visible = false end
                showNotify("漂浮已关闭")
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

    -- 通知标签
    notifyLabel = Instance.new("TextLabel")
    notifyLabel.Size = UDim2.new(0, 200, 0, 40)
    notifyLabel.Position = UDim2.new(0.5, -100, 0.5, -20)
    notifyLabel.BackgroundColor3 = Color3.fromRGB(0,0,0)
    notifyLabel.BackgroundTransparency = 0.3
    notifyLabel.TextColor3 = Color3.new(1,1,1)
    notifyLabel.TextScaled = true
    notifyLabel.Visible = false
    notifyLabel.Parent = screenGui

    -- 主开关按钮
    mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(200,50,50)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui

    -- 控制面板按钮（蓝色）
    local panelToggle = Instance.new("TextButton")
    panelToggle.Size = UDim2.new(0, 120, 0, 30)
    panelToggle.Position = UDim2.new(1, -130, 0, 70)
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(50,120,220)
    panelToggle.TextColor3 = Color3.new(1,1,1)
    panelToggle.Parent = screenGui

    -- 控制面板
    controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 220, 0, 320)
    controlPanel.Position = UDim2.new(1, -360, 0, 10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    panelToggle.MouseButton1Click:Connect(function() controlPanel.Visible = not controlPanel.Visible end)

    -- 内容
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,0,1,0)
    content.BackgroundTransparency = 1
    content.Parent = controlPanel

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.85,0,0,30)
    stopBtn.Position = UDim2.new(0.075,0,0,20)
    stopBtn.Text = "停止移动"
    stopBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
    stopBtn.TextColor3 = Color3.new(1,1,1)
    stopBtn.Parent = content

    local fixBtn = Instance.new("TextButton")
    fixBtn.Size = UDim2.new(0.85,0,0,30)
    fixBtn.Position = UDim2.new(0.075,0,0,60)
    fixBtn.Text = "防止旋转: 关闭"
    fixBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
    fixBtn.TextColor3 = Color3.new(1,1,1)
    fixBtn.Parent = content

    local directions = {"up","down","forward","back","left","right"}
    for i,dir in ipairs(directions) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.4,0,0,28)
        b.Position = UDim2.new(0.05 + 0.45*((i-1)%2),0,0,110+35*math.floor((i-1)/2))
        b.Text = dir
        b.BackgroundColor3 = Color3.fromRGB(50,120,220)
        b.TextColor3 = Color3.new(1,1,1)
        b.Parent = content
        b.MouseButton1Click:Connect(function()
            _G.moveDirectionType = dir
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
            controlPanel.Visible = false
            showNotify("漂浮已关闭")
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        StopAllParts()
        showNotify("漂浮已关闭")
    end)

    fixBtn.MouseButton1Click:Connect(function()
        local on = ToggleRotationPrevention()
        if on then
            fixBtn.Text = "防止旋转: 开启"
        else
            fixBtn.Text = "防止旋转: 关闭"
        end
    end)
end

-- 初始化
CreateMobileGUI()
print("全局物体漂浮脚本已加载")
