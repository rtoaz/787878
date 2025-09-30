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
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
delay(3, function()
    authorMessage:Destroy()
end)

-- 全局变量
_G.processedParts = {}
_G.floatSpeed = 10 -- 默认漂浮速度
_G.moveDirectionType = "up" -- 默认移动方向类型
_G.moveDirection = Vector3.new(0, 1, 0) -- 默认向上移动

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

-- 根据视角计算移动方向
local function CalculateMoveDirection()
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
    if v:IsA("Part") and not v.Anchored and not v.Parent:FindFirstChild("Humanoid") and not v.Parent:FindFirstChild("Head") then
        if _G.processedParts[v] then
            local existingBV = _G.processedParts[v].bodyVelocity
            if existingBV and existingBV.Parent then
                local finalVelocity = CalculateMoveDirection() * _G.floatSpeed
                if existingBV.Velocity ~= finalVelocity then
                    existingBV.Velocity = finalVelocity
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
        _G.processedParts[v] = { bodyVelocity = bodyVelocity }
        
        -- 防止旋转
        PreventRotation(v)
    end
end

local anActivity = false
local updateConnection = nil

local function ProcessAllParts()
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
    if anActivity then
        ProcessPart(v)
    end
end)

local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity then
            data.bodyVelocity:Destroy()
        end
    end
    _G.processedParts = {}
    
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

local function UpdateAllPartsVelocity()
    local direction = CalculateMoveDirection()
    for part, data in pairs(_G.processedParts) do
        if data.bodyVelocity and data.bodyVelocity.Parent then
            data.bodyVelocity.Velocity = direction * _G.floatSpeed
        end
    end
end

-- 停止所有零件移动
local function StopAllParts()
    _G.floatSpeed = 0
    UpdateAllPartsVelocity()
end

-- 监听玩家死亡事件，关闭漂浮并隐藏GUI
local function onPlayerDeath()
    anActivity = false
    CleanupParts()
    -- 隐藏GUI
    -- 这里可以添加隐藏GUI的代码
end

-- 监听玩家复活事件，重新开启漂浮
local function onPlayerRespawn()
    -- 显示GUI并重新开启漂浮
    anActivity = true
    ProcessAllParts()
end

-- 监听玩家死亡和复活
LocalPlayer.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid").Died:Connect(onPlayerDeath)
    character:WaitForChild("Humanoid").Respawned:Connect(onPlayerRespawn)
end)

-- 创建GUI和按钮交互代码

-- 此部分代码保持不变，添加 GUI 显示和控制逻辑...

print("全局物体漂浮脚本已加载成功!")