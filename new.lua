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

-- 全局配置
_G.processedParts = _G.processedParts or {}
_G.floatSpeed = _G.floatSpeed or 10
_G.moveDirectionType = "up"  -- 设置初始漂浮方向为向上
_G.cachedMoveVector = Vector3.new(0,1,0)  -- 缓存的移动方向（点击时更新）
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
        warn("设置 SimulationRadius 失败: ", err)
    end
end

-- 判断部件是否可处理
local function isPartEligible(part)
    if not part or not part:IsA("BasePart") then return false end
    if part.Locked then return false end
    if part.CanCollide == false then return false end
    if part.Anchored then return false end
    if part:IsDescendantOf(LocalPlayer.Character or {}) then return false end
    local parent = part.Parent
    if not parent then return true end
    if parent:FindFirstChildOfClass("Humanoid") then return false end
    if parent:FindFirstChild("Head") then return false end
    return true
end

-- ================ 缓存相机方向的函数 ================
-- 点击方向按钮时调用，缓存一次方向
local function CacheMoveDirection(dirType)
    local camera = workspace.CurrentCamera
    if not camera then return end
    if dirType == "up" then
        _G.cachedMoveVector = Vector3.new(0,1,0)
        return
    end
    if dirType == "down" then
        _G.cachedMoveVector = Vector3.new(0,-1,0)
        return
    end

    -- 前/后/左/右 使用摄像机的平面向量（y=0），并单位化
    if dirType == "forward" then
        local v = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0,0,0)
        return
    end
    if dirType == "back" then
        local v = -Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0,0,0)
        return
    end
    if dirType == "right" then
        local v = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0,0,0)
        return
    end
    if dirType == "left" then
        local v = -Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
        _G.cachedMoveVector = (v.Magnitude > 0) and v.Unit or Vector3.new(0,0,0)
        return
    end
end

-- 替换原 CalculateMoveDirection：直接返回缓存的向量（点击时会更新缓存）
local function CalculateMoveDirection()
    if isPlayerDead then return Vector3.new(0,0,0) end
    return _G.cachedMoveVector or Vector3.new(0,1,0)
end

-- ================ 修改点结束 ================
local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        pcall(function() if data.bodyVelocity then data.bodyVelocity:Destroy() end end)
        pcall(function() if data.bodyGyro then data.bodyGyro:Destroy() end end)
    end
    _G.processedParts = {}
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

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e8, 1e8, 1e8)
    bv.Velocity = CalculateMoveDirection() * _G.floatSpeed
    bv.P = 1e4
    bv.Parent = part

    local bg = nil
    if _G.fixedMode then
        bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(1e8, 1e8, 1e8)
        bg.Parent = part
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

    -- 在批量处理前，根据当前的 moveDirectionType 缓存一次相机方向（这样第一次开启就能生效）
    CacheMoveDirection(_G.moveDirectionType)

    for _, v in ipairs(Workspace:GetDescendants()) do
        pcall(function() ProcessPart(v) end)
    end
    updateConnection = RunService.Heartbeat:Connect(UpdateAllPartsVelocity)
end

local function StopAllParts()
    _G.floatSpeed = 0
    CleanupParts()
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
    anActivity = false
end

local function onCharacterAdded(char)
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        isPlayerDead = true
        StopAllParts()
    end)
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

-- GUI 创建
local function CreateMobileGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FloatControlUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0, 60, 0, 60)
    mainButton.Position = UDim2.new(0, 10, 1, -70)
    mainButton.Text = "漂浮"
    mainButton.Parent = screenGui

    local controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0, 300, 0, 420)
    controlPanel.Position = UDim2.new(0, 10, 1, -500)
    controlPanel.Visible = false
    controlPanel.Parent = screenGui

    makeDraggable(controlPanel)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -10, 1, -10)
    content.Position = UDim2.new(0, 5, 0, 5)
    content.Parent = controlPanel

    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(0.85,0,0,30)
    speedLabel.Position = UDim2.new(0.075,0,0,10)
    speedLabel.Text = "速度: " .. tostring(_G.floatSpeed)
    speedLabel.BackgroundTransparency = 1
    speedLabel.TextColor3 = Color3.new(1,1,1)
    speedLabel.Parent = content

    local speedUp = Instance.new("TextButton")
    speedUp.Size = UDim2.new(0.4,0,0,30)
    speedUp.Position = UDim2.new(0.05,0,0,50)
    speedUp.Text = "速度+"
    speedUp.Parent = content

    local speedDown = Instance.new("TextButton")
    speedDown.Size = UDim2.new(0.4,0,0,30)
    speedDown.Position = UDim2.new(0.55,0,0,50)
    speedDown.Text = "速度-"
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
        {name="左", dir="left", pos=UDim2.new(0.05,0,0,225)},
        {name="右", dir="right", pos=UDim2.new(0.65,0,0,225)},
        {name="前", dir="forward", pos=UDim2.new(0.2,0,0,225)},
        {name="后", dir="back", pos=UDim2.new(0.5,0,0,225)},
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
            CacheMoveDirection(info.dir)      -- 点击时把当前相机方向缓存下来（只执行一次）
            UpdateAllPartsVelocity()
        end)
    end

    -- 按钮功能
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        controlPanel.Visible = anActivity
        if anActivity then
            ProcessAllParts()
        else
            controlPanel.Visible = false
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        StopAllParts()
    end)

    local function ToggleRotationPrevention()
        _G.fixedMode = not _G.fixedMode
        if _G.fixedMode then
            return true
        else
            return false
        end
    end

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
