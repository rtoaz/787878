local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
delay(3, function() authorMessage:Destroy() end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10
_G.moveDirectionType = "up"
local anActivity = false
local updateConnection = nil
local screenGui -- GUI 容器

-- 防止旋转
local function PreventRotation(v)
    if not v:FindFirstChildOfClass("BodyGyro") then
        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
        bodyGyro.D = 5000
        bodyGyro.CFrame = v.CFrame
        bodyGyro.Parent = v
    end
end

-- 计算方向
local function CalculateMoveDirection()
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.new(0, 1, 0) end
    local lookVector, rightVector = camera.CFrame.LookVector, camera.CFrame.RightVector
    if _G.moveDirectionType == "up" then
        return Vector3.new(0, 1, 0)
    elseif _G.moveDirectionType == "down" then
        return Vector3.new(0, -1, 0)
    elseif _G.moveDirectionType == "forward" then
        return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "back" then
        return -Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    elseif _G.moveDirectionType == "right" then
        return Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    elseif _G.moveDirectionType == "left" then
        return -Vector3.new(rightVector.X, 0, rightVector.Z).Unit
    end
    return Vector3.new(0, 1, 0)
end

-- 处理零件
local function ProcessPart(v)
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") then
        if not _G.processedParts[v] then
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Velocity = CalculateMoveDirection() * _G.floatSpeed
            bv.Parent = v
            _G.processedParts[v] = { bodyVelocity = bv }
            PreventRotation(v)
        end
    end
end

-- 更新速度
local function UpdateAllPartsVelocity()
    local dir = CalculateMoveDirection()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = dir * _G.floatSpeed
        end
    end
end

-- 清理零件
local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity then data.bodyVelocity:Destroy() end
    end
    _G.processedParts = {}
    if updateConnection then updateConnection:Disconnect() updateConnection=nil end
end

-- 主开关
local function ProcessAllParts()
    if anActivity then
        for _, v in pairs(Workspace:GetDescendants()) do
            ProcessPart(v)
        end
        if updateConnection then updateConnection:Disconnect() end
        updateConnection = RunService.Heartbeat:Connect(UpdateAllPartsVelocity)
    else
        CleanupParts()
    end
end

-- 停止所有零件
local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- GUI 拖动
local function MakeDraggable(gui)
    gui.Active = true
    gui.Draggable = true
end

-- GUI 创建
local function CreateMobileGUI()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileFloatingControl"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- 主按钮
    local mainButton = Instance.new("TextButton")
    mainButton.Name = "MainToggle"
    mainButton.Size = UDim2.new(0, 120, 0, 50)
    mainButton.Position = UDim2.new(1, -130, 0, 10)
    mainButton.Text = "漂浮: 关闭"
    mainButton.TextSize = 16
    mainButton.BackgroundColor3 = Color3.fromRGB(255,0,0)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = screenGui
    MakeDraggable(mainButton)

    -- 控制面板
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0, 300, 0, 450)
    controlPanel.Position = UDim2.new(0.5, -150, 0.5, -225)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.BorderSizePixel = 0
    controlPanel.Visible = false
    controlPanel.Parent = screenGui
    MakeDraggable(controlPanel)

    -- 打开/关闭面板按钮
    local openPanelButton = Instance.new("TextButton")
    openPanelButton.Name = "OpenPanel"
    openPanelButton.Size = UDim2.new(0, 120, 0, 40)
    openPanelButton.Position = UDim2.new(1, -130, 0, 70)
    openPanelButton.Text = "打开控制面板"
    openPanelButton.BackgroundColor3 = Color3.fromRGB(100,100,200)
    openPanelButton.TextColor3 = Color3.new(1,1,1)
    openPanelButton.Parent = screenGui

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "ClosePanel"
    closeButton.Size = UDim2.new(0, 100, 0, 40)
    closeButton.Position = UDim2.new(0.5, -50, 0, 380)
    closeButton.Text = "关闭面板"
    closeButton.BackgroundColor3 = Color3.fromRGB(200,100,100)
    closeButton.TextColor3 = Color3.new(1,1,1)
    closeButton.Parent = controlPanel

    -- 速度显示
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, 0, 0, 40)
    speedLabel.Position = UDim2.new(0, 0, 0, 10)
    speedLabel.Text = "速度: " .. _G.floatSpeed
    speedLabel.TextColor3 = Color3.new(1,1,1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextSize = 20
    speedLabel.Parent = controlPanel

    -- 速度按钮
    local speedUpButton = Instance.new("TextButton")
    speedUpButton.Size = UDim2.new(0,60,0,60)
    speedUpButton.Position = UDim2.new(0.7,0,0,60)
    speedUpButton.Text = "+"
    speedUpButton.TextSize = 30
    speedUpButton.BackgroundColor3 = Color3.fromRGB(0,200,0)
    speedUpButton.TextColor3 = Color3.new(1,1,1)
    speedUpButton.Parent = controlPanel

    local speedDownButton = Instance.new("TextButton")
    speedDownButton.Size = UDim2.new(0,60,0,60)
    speedDownButton.Position = UDim2.new(0.3,0,0,60)
    speedDownButton.Text = "-"
    speedDownButton.TextSize = 30
    speedDownButton.BackgroundColor3 = Color3.fromRGB(200,0,0)
    speedDownButton.TextColor3 = Color3.new(1,1,1)
    speedDownButton.Parent = controlPanel

    -- 停止按钮
    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(0,100,0,40)
    stopButton.Position = UDim2.new(0.5,-50,0,130)
    stopButton.Text = "停止移动"
    stopButton.BackgroundColor3 = Color3.fromRGB(200,100,100)
    stopButton.TextColor3 = Color3.new(1,1,1)
    stopButton.Parent = controlPanel

    -- 方向按钮
    local directions = {
        {name = "向上", dir = "up", pos = UDim2.new(0.5,-30,0,230)},
        {name = "向下", dir = "down", pos = UDim2.new(0.5,-30,0,300)},
        {name = "向前", dir = "forward", pos = UDim2.new(0.2,-30,0,265)},
        {name = "向后", dir = "back", pos = UDim2.new(0.8,-30,0,265)},
        {name = "向左", dir = "left", pos = UDim2.new(0.05,-30,0,265)},
        {name = "向右", dir = "right", pos = UDim2.new(0.95,-30,0,265)},
    }
    for _,info in pairs(directions) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0,60,0,60)
        b.Position = info.pos
        b.Text = info.name
        b.BackgroundColor3 = Color3.fromRGB(100,100,200)
        b.TextColor3 = Color3.new(1,1,1)
        b.Parent = controlPanel
        b.MouseButton1Click:Connect(function()
            if not screenGui.Enabled then return end
            _G.moveDirectionType = info.dir
            UpdateAllPartsVelocity()
        end)
    end

    -- 主开关功能
    mainButton.MouseButton1Click:Connect(function()
        if not screenGui.Enabled then return end
        anActivity = not anActivity
        ProcessAllParts()
        if anActivity then
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0,255,0)
        else
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255,0,0)
        end
    end)

    -- 面板按钮功能
    openPanelButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = true
        openPanelButton.Visible = false
    end)
    closeButton.MouseButton1Click:Connect(function()
        controlPanel.Visible = false
        openPanelButton.Visible = true
    end)

    -- 速度调节
    speedUpButton.MouseButton1Click:Connect(function()
        if not screenGui.Enabled then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed + 5, 1, 50)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)
    speedDownButton.MouseButton1Click:Connect(function()
        if not screenGui.Enabled then return end
        _G.floatSpeed = math.clamp(_G.floatSpeed - 5, 1, 50)
        speedLabel.Text = "速度: " .. _G.floatSpeed
        UpdateAllPartsVelocity()
    end)
    stopButton.MouseButton1Click:Connect(function()
        if not screenGui.Enabled then return end
        StopAllParts()
        speedLabel.Text = "速度: " .. _G.floatSpeed
    end)
end

-- 玩家死亡/复活监听
local function HookCharacter(char)
    local hum = char:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        anActivity = false
        CleanupParts()
        if screenGui then screenGui.Enabled = false end
    end)
    hum:GetPropertyChangedSignal("Health"):Connect(function()
        if hum.Health > 0 then
            if screenGui then screenGui.Enabled = true end
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(HookCharacter)
if LocalPlayer.Character then HookCharacter(LocalPlayer.Character) end

-- 初始化 GUI
CreateMobileGUI()

print("全局物体漂浮脚本已加载成功!")
