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

-- 定义一个静态变量来存储相机位置和朝向
local staticCameraPosition = nil
local staticCameraLookVector = nil
local staticCameraRightVector = nil

-- 捕获当前相机的位置和朝向
local function UpdateCameraData()
    local camera = workspace.CurrentCamera
    if camera then
        staticCameraPosition = camera.CFrame.Position
        staticCameraLookVector = camera.CFrame.LookVector
        staticCameraRightVector = camera.CFrame.RightVector
    end
end

-- 监听方向键的输入
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end  -- 如果输入已被游戏处理，则忽略

    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
            -- 用户按下 "W" 或 "上方向键" 时更新相机数据
            UpdateCameraData()
            _G.moveDirectionType = "forward"  -- 设置为前进方向
        elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
            -- 用户按下 "S" 或 "下方向键" 时更新相机数据
            UpdateCameraData()
            _G.moveDirectionType = "back"  -- 设置为后退方向
        elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
            -- 用户按下 "A" 或 "左方向键" 时更新相机数据
            UpdateCameraData()
            _G.moveDirectionType = "left"  -- 设置为左方向
        elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
            -- 用户按下 "D" 或 "右方向键" 时更新相机数据
            UpdateCameraData()
            _G.moveDirectionType = "right"  -- 设置为右方向
        end
    end
end)

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
    
    -- 使用静态的相机数据来计算方向
    if staticCameraPosition == nil or staticCameraLookVector == nil or staticCameraRightVector == nil then
        -- 如果没有初始化相机数据，返回默认方向
        return Vector3.new(0,1,0)
    end

    local dir = _G.moveDirectionType
    
    if dir == "forward" then
        -- 向前，基于初始时的LookVector
        return staticCameraLookVector.Unit
    elseif dir == "back" then
        -- 向后，反向LookVector
        return -staticCameraLookVector.Unit
    elseif dir == "right" then
        -- 向右，基于初始时的RightVector
        return staticCameraRightVector.Unit
    elseif dir == "left" then
        -- 向左，反向RightVector
        return -staticCameraRightVector.Unit
    end
    
    return Vector3.new(0,1,0)  -- 默认向上
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

-- 清理所有漂浮物体
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

-- 处理漂浮物体
local function ProcessPart(part)
    if isPlayerDead then return end
    if not isPartEligible(part) then return end
    local entry = _G.processedParts[part]
    if entry and entry.bodyVelocity and entry.bodyVelocity.Parent then
        entry.bodyVelocity.Velocity = CalculateMoveDirection() * _G.floatSpeed
        return
    end
    
    -- 设置网络所有权给本地玩家进行控制
    if not part:IsDescendantOf(Players.LocalPlayer.Character) then
        part:SetNetworkOwner(LocalPlayer)  -- 将网络所有权交给本地玩家
    end
    
    -- 清理之前的BodyMover组件
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("BodyMover") then pcall(function() child:Destroy() end) end
    end

    -- 创建新的BodyVelocity
    local bv = Instance.new("BodyVelocity")
    bv.Parent = part
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = CalculateMoveDirection() * _G.floatSpeed

    -- 如果启用了固定模式，添加BodyGyro
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

    -- 停止所有物体的网络所有权
    for part, data in pairs(_G.processedParts) do
        if part and part:IsDescendantOf(Workspace) then
            part:SetNetworkOwner(nil)  -- 将网络所有权交还给服务器
        end
    end
end

-- 初始化
ProcessAllParts()
print("全局物体漂浮脚本已加载")    if isPlayerDead then
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

    -- 停止所有物体的网络所有权
    for part, data in pairs(_G.processedParts) do
        if part and part:IsDescendantOf(Workspace) then
            part:SetNetworkOwner(nil)  -- 将网络所有权交还给服务器
        end
    end
end

-- 初始化
ProcessAllParts()
print("全局物体漂浮脚本已加载")
