local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

--=============== 加载与初始化 ===============
if not game:IsLoaded() then game.Loaded:Wait() end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--=============== 作者提示信息 ===============
local authorMessage = Instance.new("Message")
authorMessage.Text = "全局物体漂浮脚本 - 作者: XTTT\n此脚本为免费脚本，禁止贩卖\n由Star_Skater53帮忙优化"
authorMessage.Parent = Workspace
task.delay(3, function() authorMessage:Destroy() end)

--=============== 全局变量与状态 ===============
_G.processedParts = {}               -- 被控制的部件记录表
_G.floatSpeed = 10                   -- 默认漂浮速度
_G.moveDirectionType = "up"          -- 当前移动方向（初始为向上）
_G.fixedMode = false                 -- 是否防止旋转

local isPlayerDead = false           -- 玩家死亡状态
local anActivity = false             -- 是否处于漂浮模式
local updateConnection = nil         -- 更新连接引用
local lockedDirection = nil          -- 锁定的漂浮方向
local cameraListener = nil           -- 相机监听引用

-- 手动点击时即时记录的相机方向
local manualCameraCFrame = nil
local manualCameraTime = 0
local MANUAL_TIMEOUT = 0.6           -- 手动方向优先时长（秒）

--=============== 模拟半径设置（保证控制全局物体） ===============
RunService.Heartbeat:Connect(function()
    pcall(function()
        sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
        sethiddenproperty(LocalPlayer, "MaxSimulationRadius", math.huge)
    end)
end)

--=============== 相机监听（降低频率防卡顿） ===============
local lastCameraDir = Vector3.new(0, 1, 0)
local function startCameraTracking()
    if cameraListener then return end
    local lastUpdate = 0
    cameraListener = RunService.Heartbeat:Connect(function()
        if tick() - lastUpdate >= 0.2 then -- 每 0.2 秒更新一次
            lastUpdate = tick()
            local cam = workspace.CurrentCamera
            if cam then
                local v = cam.CFrame.LookVector
                lastCameraDir = Vector3.new(v.X, 0, v.Z).Unit
            end
        end
    end)
end

local function stopCameraTracking()
    if cameraListener then
        cameraListener:Disconnect()
        cameraListener = nil
    end
end

--=============== 计算移动方向（修正版） ===============
local function CalculateMoveDirection()
    local dir = _G.moveDirectionType
    if dir == "up" then return Vector3.new(0, 1, 0) end
    if dir == "down" then return Vector3.new(0, -1, 0) end

    local cam = workspace.CurrentCamera
    if not cam then return Vector3.new(0,1,0) end

    local now = tick()
    local camCF = cam.CFrame

    -- 未漂浮时优先使用手动记录的相机方向（例如点击前/后/左/右时）
    if not anActivity then
        if manualCameraCFrame and now - manualCameraTime < MANUAL_TIMEOUT then
            camCF = manualCameraCFrame
        end
    end

    -- 前方向：漂浮时锁定，未漂浮时实时
    local forward = (anActivity and lockedDirection)
        或 Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit

    -- ✅ Roblox 坐标系修正版：
    --   Forward = LookVector
    --   Back    = -LookVector
    --   Right   = (Z, 0, -X)
    --   Left    = (-Z, 0, X)
    if dir == "forward" then
        return forward
    elseif dir == "back" then
        return -forward
    elseif dir == "right" then
        local right = Vector3.new(forward.Z, 0, -forward.X).Unit
        return right
    elseif dir == "left" then
        local right = Vector3.new(forward.Z, 0, -forward.X).Unit
        return -right
    end

    return Vector3.new(0,1,0)
end

--=============== 部件控制核心函数 ===============
local function CleanupParts()
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity then data.bodyVelocity:Destroy() end
        if data.bodyGyro then data.bodyGyro:Destroy() end
    end
    _G.processedParts = {}
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

local function UpdateAllPartsVelocity()
    local dir = CalculateMoveDirection()
    for _, data in pairs(_G.processedParts) do
        if data.bodyVelocity then
            data.bodyVelocity.Velocity = dir * _G.floatSpeed
        end
        if _G.fixedMode and data.bodyGyro then
            data.bodyGyro.CFrame = data.bodyGyro.Parent.CFrame
        end
    end
end

local function ProcessPart(part)
    if not part:IsA("BasePart") or part.Anchored then return end
    if part:IsDescendantOf(LocalPlayer.Character) then return end
    if part.Parent and (part.Parent:FindFirstChildOfClass("Humanoid") or part.Parent:FindFirstChild("Head")) then return end

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = CalculateMoveDirection() * _G.floatSpeed
    bv.Parent = part

    local bg = nil
    if _G.fixedMode then
        bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.P, bg.D = 1000, 100
        bg.Parent = part
    end

    _G.processedParts[part] = {bodyVelocity=bv, bodyGyro=bg}
end

local function ProcessAllParts()
    CleanupParts()
    for _, v in ipairs(workspace:GetDescendants()) do
        pcall(ProcessPart, v)
    end
    updateConnection = RunService.Heartbeat:Connect(UpdateAllPartsVelocity)
end

local function StopAllParts()
    CleanupParts()
end

--=============== 玩家死亡/重生处理 ===============
local mainButton, controlPanel
local function SyncGuiToOff()
    if mainButton then
        mainButton.Text = "漂浮: 关闭"
        mainButton.BackgroundColor3 = Color3.fromRGB(255,0,0)
    end
    if controlPanel then controlPanel.Visible = false end
end

local function onCharacterAdded(char)
    isPlayerDead = false
    anActivity = false
    CleanupParts()
    SyncGuiToOff()
    startCameraTracking()
    local hum = char:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        isPlayerDead = true
        anActivity = false
        CleanupParts()
        lockedDirection = nil
        SyncGuiToOff()
        startCameraTracking()
    end)
end
Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if Players.LocalPlayer.Character then onCharacterAdded(Players.LocalPlayer.Character) end

--=============== 可拖动 GUI 功能 ===============
local function makeDraggable(gui)
    local dragging, dragStart, startPos
    gui.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = gui.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging=false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local delta = i.Position - dragStart
            gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

--=============== 创建主界面与控制面板 ===============
local function CreateMobileGUI()
    local gui = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
    gui.Name = "MobileFloatingControl"
    gui.ResetOnSpawn = false

    -- 漂浮开关按钮
    mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(0,120,0,50)
    mainButton.Position = UDim2.new(1,-130,0,50)
    mainButton.Text = "漂浮: 关闭"
    mainButton.BackgroundColor3 = Color3.fromRGB(255,0,0)
    mainButton.TextColor3 = Color3.new(1,1,1)
    mainButton.Parent = gui
    makeDraggable(mainButton)

    -- 控制面板
    controlPanel = Instance.new("Frame")
    controlPanel.Size = UDim2.new(0,220,0,320)
    controlPanel.Position = UDim2.new(1,-360,0,10)
    controlPanel.BackgroundColor3 = Color3.fromRGB(60,60,60)
    controlPanel.BackgroundTransparency = 0.3
    controlPanel.Visible = false
    controlPanel.Parent = gui

    -- 控制面板按钮（开关）
    local panelToggle = Instance.new("TextButton", gui)
    panelToggle.Size = UDim2.new(0,120,0,30)
    panelToggle.Position = UDim2.new(1,-130,0,120)
    panelToggle.Text = "控制面板"
    panelToggle.BackgroundColor3 = Color3.fromRGB(0,150,255)
    panelToggle.TextColor3 = Color3.new(1,1,1)
    makeDraggable(panelToggle)
    panelToggle.MouseButton1Click:Connect(function() controlPanel.Visible = not controlPanel.Visible end)

    -- 十字控制按钮布局
    local dirs = {
        {n="上",d="up",x=0.35,y=190},
        {n="下",d="down",x=0.35,y=260},
        {n="左",d="left",x=0.05,y=225},
        {n="右",d="right",x=0.65,y=225},
        {n="前",d="forward",x=0.2,y=225},
        {n="后",d="back",x=0.5,y=225},
    }

    for _,v in ipairs(dirs) do
        local b = Instance.new("TextButton", controlPanel)
        b.Size = UDim2.new(0.15,0,0,35)
        b.Position = UDim2.new(v.x,0,0,v.y)
        b.Text = v.n
        b.BackgroundColor3 = Color3.fromRGB(0,150,255)
        b.TextColor3 = Color3.new(1,1,1)
        b.MouseButton1Click:Connect(function()
            _G.moveDirectionType = v.d
            local cam = workspace.CurrentCamera
            if cam then
                manualCameraCFrame = cam.CFrame
                manualCameraTime = tick()
            end
            UpdateAllPartsVelocity()
        end)
    end

    -- 漂浮开关逻辑
    mainButton.MouseButton1Click:Connect(function()
        if isPlayerDead then return end
        anActivity = not anActivity
        if anActivity then
            -- 锁定当前相机方向
            local cam = workspace.CurrentCamera
            if cam then
                local look = cam.CFrame.LookVector
                lockedDirection = Vector3.new(look.X,0,look.Z).Unit
            else
                lockedDirection = Vector3.new(0,1,0)
            end
            stopCameraTracking()
            mainButton.Text = "漂浮: 开启"
            mainButton.BackgroundColor3 = Color3.fromRGB(0,255,0)
            ProcessAllParts()
        else
            lockedDirection = nil
            CleanupParts()
            startCameraTracking()
            mainButton.Text = "漂浮: 关闭"
            mainButton.BackgroundColor3 = Color3.fromRGB(255,0,0)
            controlPanel.Visible = false
        end
    end)
end

--=============== 初始化 ===============
CreateMobileGUI()
startCameraTracking()
print("✅ 全局物体漂浮脚本已加载")
