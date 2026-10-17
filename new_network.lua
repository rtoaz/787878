--[[
===============================================================================
  全局物体漂浮脚本 · Global Object Float
-------------------------------------------------------------------------------
  原作者 : ciTiy
  修改者 : Star_Skater53
  界面   : WindUI  (https://github.com/Footagesus/WindUI)
  说明   : 本脚本免费，禁止贩卖
===============================================================================
--]]

--=============================================================================
-- 1. 服务
--=============================================================================
local cloneref = cloneref or clonereference or function(obj) return obj end

local Players    = cloneref(game:GetService("Players"))
local Workspace  = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

--=============================================================================
-- 2. 常量与状态
--=============================================================================
local HUGE_VEC       = Vector3.new(math.huge, math.huge, math.huge)
local ZERO_VEC       = Vector3.new(0, 0, 0)
local NET_THROTTLE   = 0.5   -- 网络所有权最小切换间隔（秒）
local SWEEP_INTERVAL = 2     -- 清理已销毁部件的间隔（秒）
local SPEED_MIN      = 1
local SPEED_MAX      = 200
local WINDUI_URL     = "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"

-- 全部运行状态集中在一张表里，不再污染 _G
local State = {
    active           = false,               -- 漂浮总开关
    moving           = true,                -- 是否允许位移
    speed            = 10,                  -- 速度 0 ~ 200
    direction        = "up",                -- 当前方向 key
    vector           = Vector3.new(0, 1, 0),-- 缓存的移动方向（只在切换方向时更新）
    fixedRotation    = false,               -- 防止旋转
    networkOwnership = false,               -- 网络所有权
    dead             = false,               -- 玩家是否死亡
    destroyed        = false,               -- 脚本是否已卸载

    -- 导航模式（定位棒）
    navToolEnabled   = true,                -- 是否在背包里生成定位棒
    navTarget        = nil,                 -- 导航目标点 Vector3
    navRadius        = 6,                   -- 到达半径
    navScope         = "all",               -- "all" = 全部漂浮物 / "nearest" = 最近的一个
    navShowMarker    = true,                -- 显示目标标记
}

-- [BasePart] = { bv, bg, netOwned, lastNet, nav }
local processed = {}

local heartbeatConn          -- RunService.Heartbeat 连接
local sweepTimer = 0         -- 距离下次清理累计的时间
local simLoopRunning = false -- 模拟半径协程是否在跑

-- GUI 构建后注入的钩子，用来让界面状态跟随脚本状态
local UIHooks = {
    setActive = nil,
    notify    = nil,
}

local suppressToggleCallback = false -- 程序化改开关时不重复触发回调

local function notify(title, content, duration)
    if UIHooks.notify then
        pcall(UIHooks.notify, title, content, duration)
    end
end

local DIRECTIONS = {
    { label = "向上",     key = "up"      },
    { label = "向下",     key = "down"    },
    { label = "向前",     key = "forward" },
    { label = "向后",     key = "back"    },
    { label = "向左",     key = "left"    },
    { label = "向右",     key = "right"   },
    { label = "跟随视角", key = "camera"  },
}

local DIR_LABEL_TO_KEY = {}
local DIR_LABELS = {}
for i = 1, #DIRECTIONS do
    DIR_LABEL_TO_KEY[DIRECTIONS[i].label] = DIRECTIONS[i].key
    DIR_LABELS[i] = DIRECTIONS[i].label
end

--=============================================================================
-- 3. 辅助函数
--=============================================================================

-- 复用同一个函数做 pcall，避免每帧创建闭包
local function zeroAngularVelocity(part)
    part.AssemblyAngularVelocity = ZERO_VEC
end

local function isEligible(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end

    local char = LocalPlayer.Character
    if char and part:IsDescendantOf(char) then return false end

    local parent = part.Parent
    if parent then
        -- 排除玩家 / NPC 模型
        if parent:FindFirstChildOfClass("Humanoid") or parent:FindFirstChild("Head") then
            return false
        end
    end
    return true
end

-- 只在用户切换方向时调用，缓存一次相机方向
local function cacheDirection(dir)
    if dir == "up" then
        State.vector = Vector3.new(0, 1, 0)
        return
    elseif dir == "down" then
        State.vector = Vector3.new(0, -1, 0)
        return
    end

    local cam = Workspace.CurrentCamera
    if not cam then return end

    local cf = cam.CFrame
    local look, right = cf.LookVector, cf.RightVector

    -- 跟随视角：直接朝相机正前方（含俯仰），心跳里每帧重新取
    if dir == "camera" then
        State.vector = look
        return
    end

    local v
    if dir == "forward" then
        v = Vector3.new(look.X, 0, look.Z)
    elseif dir == "back" then
        v = -Vector3.new(look.X, 0, look.Z)
    elseif dir == "right" then
        v = Vector3.new(right.X, 0, right.Z)
    elseif dir == "left" then
        v = -Vector3.new(right.X, 0, right.Z)
    end

    if v and v.Magnitude > 0 then
        State.vector = v.Unit
    end
end

-- 当前应该施加的速度（速度/方向/开关任意一项变化才会变）
local function currentVelocity()
    if State.dead or not State.active or not State.moving then
        return ZERO_VEC
    end
    return State.vector * State.speed
end

-- 网络所有权切换：带节流，且只有状态真的变了才调用
local function setNetworkOwnership(part, data, toLocal)
    if not part.SetNetworkOwner then return end
    if data.netOwned == toLocal then return end

    local now = os.clock()
    if data.lastNet and (now - data.lastNet) < NET_THROTTLE then return end

    local ok = pcall(function()
        part:SetNetworkOwner(toLocal and LocalPlayer or nil)
    end)
    if ok then
        data.netOwned = toLocal
        data.lastNet  = now
    end
end

local function destroyMovers(data)
    if data.bv then pcall(function() data.bv:Destroy() end) end
    if data.bg then pcall(function() data.bg:Destroy() end) end
    data.bv, data.bg = nil, nil
end

--=============================================================================
-- 4. 部件处理
--=============================================================================
local function processPart(part)
    if State.dead or State.destroyed then return end
    if not isEligible(part) then return end

    local data = processed[part]
    if data and data.bv and data.bv.Parent then
        if not data.nav then
            data.bv.Velocity = currentVelocity()
        end
        if State.networkOwnership then
            setNetworkOwnership(part, data, true)
        end
        return
    end

    -- 清掉部件上已有的 BodyMover，避免速度叠加
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("BodyMover") then
            pcall(function() child:Destroy() end)
        end
    end

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = HUGE_VEC
    bv.Velocity = currentVelocity()
    bv.Parent   = part

    local bg
    if State.fixedRotation then
        bg = Instance.new("BodyGyro")
        bg.MaxTorque = HUGE_VEC
        bg.P    = 1000
        bg.D    = 100
        bg.CFrame = part.CFrame -- 只设一次目标朝向，之后不再覆盖
        bg.Parent = part
        pcall(zeroAngularVelocity, part)
    end

    data = { bv = bv, bg = bg, netOwned = false, lastNet = 0 }
    -- 导航进行中才加入的部件，按当前范围决定要不要一起走
    if State.navTarget and State.navScope == "all" then
        data.nav = true
    end
    processed[part] = data

    if State.networkOwnership then
        setNetworkOwnership(part, data, true)
    end
end

local function processAllParts()
    if State.dead or State.destroyed then return end

    -- 开启/重扫前缓存一次当前方向
    cacheDirection(State.direction)

    local descendants = Workspace:GetDescendants()
    for i = 1, #descendants do
        local obj = descendants[i]
        -- 先过滤类型，避免为大量非 BasePart 对象走一遍 pcall
        if obj:IsA("BasePart") then
            local ok, err = pcall(processPart, obj)
            if not ok then
                warn("[GlobalFloat] 处理部件失败: " .. tostring(err))
            end
        end
    end
end

-- 把所有 BodyMover 的速度刷新为当前值
-- 正在导航的部件由导航逻辑接管，这里跳过
local function refreshVelocities()
    local v = currentVelocity()
    for _, data in pairs(processed) do
        if not data.nav then
            local bv = data.bv
            if bv and bv.Parent then
                bv.Velocity = v
            end
        end
    end
end

-- 清理已被销毁的部件，防止 processed 表无限增长
local function sweepDestroyedParts()
    for part, data in pairs(processed) do
        if part.Parent == nil then
            destroyMovers(data)
            processed[part] = nil
        end
    end
end

local function cleanupAll(releaseNetwork)
    for part, data in pairs(processed) do
        destroyMovers(data)
        if releaseNetwork and data.netOwned then
            pcall(function() part:SetNetworkOwner(nil) end)
        end
    end
    table.clear(processed)
end

--=============================================================================
-- 5. 导航模式（定位棒）
--=============================================================================
local AVOID_LOOKAHEAD = 8   -- 避障探测距离（studs）
local AVOID_INTERVAL  = 0.1 -- 单个部件的避障射线刷新间隔（秒）

local navParams = RaycastParams.new()
navParams.FilterType = Enum.RaycastFilterType.Exclude
navParams.IgnoreWater = true
navParams.FilterDescendantsInstances = {}

local targetMarker -- 目标点标记

-- 导航射线要忽略玩家、目标标记和所有漂浮物，否则部件会互相挡路
local function refreshNavFilter()
    local list = {}
    local char = LocalPlayer.Character
    if char then
        list[#list + 1] = char
    end
    if targetMarker then
        list[#list + 1] = targetMarker
    end
    for part in pairs(processed) do
        list[#list + 1] = part
    end
    navParams.FilterDescendantsInstances = list
end

local function destroyMarker()
    if not targetMarker then return end
    local m = targetMarker
    targetMarker = nil
    pcall(function() m:Destroy() end)
end

local function ensureMarker()
    if not State.navShowMarker then
        destroyMarker()
        return nil
    end
    if targetMarker and targetMarker.Parent then
        return targetMarker
    end

    local m = Instance.new("Part")
    m.Name         = "FloatNavTarget"
    m.Shape        = Enum.PartType.Ball
    m.Size         = Vector3.new(1.6, 1.6, 1.6)
    m.Anchored     = true
    m.CanCollide   = false
    m.CanQuery     = false
    m.CanTouch     = false
    m.CastShadow   = false
    m.Material     = Enum.Material.Neon
    m.Color        = Color3.fromRGB(90, 200, 255)
    m.Transparency = 0.25
    m.Parent       = Workspace

    targetMarker = m
    return m
end

local function clearNavTarget()
    if not State.navTarget then return end
    State.navTarget = nil
    for _, data in pairs(processed) do
        data.nav = false
    end
    destroyMarker()
    refreshVelocities()
end

-- 返回 true 表示该部件已经就位
local function steerTowards(part, data)
    local bv = data.bv
    if not bv or not bv.Parent then return true end

    local target = State.navTarget
    if not target then return true end

    if not State.moving then
        bv.Velocity = ZERO_VEC
        return false
    end

    local offset = target - part.Position
    local dist = offset.Magnitude
    if dist <= State.navRadius then
        bv.Velocity = ZERO_VEC
        return true
    end

    local dir = offset / dist

    -- 最简避障：正前方被挡住时，贴着障碍表面切向绕行
    -- 射线按部件错峰刷新，避免部件一多就变成每帧几百次 Raycast
    local now = os.clock()
    if not data.navNext then
        data.navNext = now + AVOID_INTERVAL * math.random()
    end
    if now >= data.navNext then
        data.navNext = now + AVOID_INTERVAL
        local hit = Workspace:Raycast(part.Position, dir * AVOID_LOOKAHEAD, navParams)
        data.navNormal = hit and hit.Normal or nil
    end

    if data.navNormal then
        local n = data.navNormal
        local slide = dir - n * dir:Dot(n)
        dir = slide.Magnitude > 0.05 and slide.Unit or n
        dir = (dir + Vector3.new(0, 0.3, 0)).Unit
    end

    -- 快到时减速，避免在目标点附近来回抖
    local speed = State.speed
    local slowRadius = math.max(State.navRadius * 2, 8)
    if dist < slowRadius then
        speed = speed * (dist / slowRadius)
    end

    bv.Velocity = dir * speed
    return false
end

-- 按当前范围选定参与导航的部件
local function selectNavTargets()
    for _, data in pairs(processed) do
        data.nav       = false
        data.navNormal = nil
        data.navNext   = nil
    end

    if State.navScope == "nearest" then
        -- 「最近的一个」= 离本地玩家最近的漂浮物（不是离目标点最近）
        local char = LocalPlayer.Character
        if not char then return end

        local origin
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            origin = root.Position
        else
            local ok, pivot = pcall(function() return char:GetPivot().Position end)
            if ok then origin = pivot end
        end
        if not origin then return end

        local best, bestDist
        for part in pairs(processed) do
            local d = (part.Position - origin).Magnitude
            if not bestDist or d < bestDist then
                best, bestDist = part, d
            end
        end
        if best and processed[best] then
            processed[best].nav = true
        end
    else
        for _, data in pairs(processed) do
            data.nav = true
        end
    end
end

local function setNavTarget(position)
    if not State.active then
        notify("无法导航", "请先打开「启用漂浮」", 2)
        return false
    end
    if next(processed) == nil then
        notify("无法导航", "场景里还没有漂浮物", 2)
        return false
    end

    State.navTarget = position

    local marker = ensureMarker()
    if marker then
        marker.Position = position
    end

    selectNavTargets()
    refreshNavFilter()
    return true
end

local function setNavScope(scope)
    State.navScope = scope
    if State.navTarget then
        selectNavTargets()
        -- 不再参与导航的部件立刻恢复原来的漂移方向
        refreshVelocities()
    end
end

local function setNavRadius(radius)
    State.navRadius = math.clamp(radius, 2, 30)
end

local function setMarkerVisible(visible)
    State.navShowMarker = visible
    if not visible then
        destroyMarker()
    elseif State.navTarget then
        local marker = ensureMarker()
        if marker then
            marker.Position = State.navTarget
        end
        refreshNavFilter()
    end
end

--=============================================================================
-- 6. 心跳循环
--=============================================================================
local function onHeartbeat(dt)
    if State.dead then return end

    -- 跟随视角：相机方向每帧都在变，只能逐帧重取并刷新速度
    if State.direction == "camera" and State.active and State.moving then
        cacheDirection("camera")
        refreshVelocities()
    end

    -- 防止旋转：清零角速度，让 BodyGyro 更稳
    if State.fixedRotation then
        for part in pairs(processed) do
            pcall(zeroAngularVelocity, part)
        end
    end

    -- 导航：逐帧转向，全部就位后自动结束
    if State.navTarget then
        local total, pending = 0, 0
        for part, data in pairs(processed) do
            if data.nav then
                total += 1
                if not steerTowards(part, data) then
                    pending += 1
                end
            end
        end
        if total > 0 and pending == 0 then
            notify("导航完成", "漂浮物已到达目标点", 2)
            clearNavTarget()
        end
    end

    -- 定时清掉已销毁的部件，并兜底刷新一次速度
    -- （原版是每帧刷新，这里降到每 2 秒一次，开销小了两个数量级）
    sweepTimer += dt
    if sweepTimer >= SWEEP_INTERVAL then
        sweepTimer = 0
        sweepDestroyedParts()
        refreshVelocities()
        if State.navTarget then
            refreshNavFilter()
        end
    end
end

local function setHeartbeat(enabled)
    if enabled then
        if not heartbeatConn then
            sweepTimer = 0
            heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
        end
    elseif heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
end

--=============================================================================
-- 7. 对外动作
--=============================================================================
local function startFloat()
    if State.dead or State.destroyed then return false end
    State.active = true
    -- 不改 moving，「允许移动」开关说了算
    processAllParts()
    setHeartbeat(true)
    return true
end

local function stopFloat(releaseNetwork)
    State.active = false
    clearNavTarget()
    cleanupAll(releaseNetwork)
    setHeartbeat(false)
    return true
end

local function rescan()
    if not State.active or State.destroyed then return end
    processAllParts()
end

local function setSpeed(speed)
    State.speed = math.clamp(speed, SPEED_MIN, SPEED_MAX)
    -- 注意：这里不改 moving，否则「允许移动」关着调速度会让物体动起来
    refreshVelocities()
end

local function setMoving(moving)
    State.moving = moving
    refreshVelocities()
end

local function setDirection(dirKey)
    State.direction = dirKey
    cacheDirection(dirKey)
    refreshVelocities()
end

local function setFixedRotation(enabled)
    State.fixedRotation = enabled
    if not State.active then return end

    for part, data in pairs(processed) do
        if enabled then
            if not (data.bg and data.bg.Parent) then
                local bg = Instance.new("BodyGyro")
                bg.MaxTorque = HUGE_VEC
                bg.P = 1000
                bg.D = 100
                bg.CFrame = part.CFrame
                bg.Parent = part
                data.bg = bg
            end
            pcall(zeroAngularVelocity, part)
        else
            if data.bg then
                pcall(function() data.bg:Destroy() end)
                data.bg = nil
            end
        end
    end
end

local function setNetworkOwnershipEnabled(enabled)
    State.networkOwnership = enabled
    if not State.active then return end

    for part, data in pairs(processed) do
        data.lastNet = 0 -- 用户主动切换时不受节流限制
        setNetworkOwnership(part, data, enabled)
    end
end

--=============================================================================
-- 8. 模拟半径（原版每帧调用两次，这里改成 1 秒一次）
--=============================================================================
local function startSimulationRadius()
    if type(sethiddenproperty) ~= "function" then
        warn("[GlobalFloat] 当前执行器不支持 sethiddenproperty，已跳过模拟半径设置")
        return
    end
    if simLoopRunning then return end
    simLoopRunning = true

    task.spawn(function()
        while simLoopRunning and not State.destroyed do
            pcall(function()
                sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
                sethiddenproperty(LocalPlayer, "MaxSimulationRadius", math.huge)
            end)
            task.wait(1)
        end
    end)
end

--=============================================================================
-- 9. 定位棒（导航工具）
--=============================================================================
local NAV_TOOL_NAME = "定位棒"

local function findNavTool()
    local char = LocalPlayer.Character
    if char then
        local t = char:FindFirstChild(NAV_TOOL_NAME)
        if t then return t end
    end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        return backpack:FindFirstChild(NAV_TOOL_NAME)
    end
    return nil
end

local function removeNavTool()
    local existing = findNavTool()
    if existing then
        pcall(function() existing:Destroy() end)
    end
end

-- 用鼠标位置打一条射线取世界坐标
local function mouseTargetPosition()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end

    local mouse = LocalPlayer:GetMouse()
    local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)

    local params = RaycastParams.new()
    params.FilterType  = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    -- 必须排除所有漂浮物：否则射线打在物体表面上，目标点几乎贴着物体，
    -- 选「最近的一个」时会瞬间判定到达，看起来就像什么都没动
    local filter = {}
    local char = LocalPlayer.Character
    if char then filter[#filter + 1] = char end
    if targetMarker then filter[#filter + 1] = targetMarker end
    for part in pairs(processed) do
        filter[#filter + 1] = part
    end
    params.FilterDescendantsInstances = filter

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
    if result then
        return result.Position
    end
    -- 没打到东西就落在相机正前方
    return ray.Origin + ray.Direction * 500
end

local function giveNavTool()
    if not State.navToolEnabled or State.destroyed then return end
    if findNavTool() then return end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return end

    local tool = Instance.new("Tool")
    tool.Name           = NAV_TOOL_NAME
    tool.RequiresHandle = false
    tool.CanBeDropped   = false
    tool.ToolTip        = "手持后左键点击地面，漂浮物会自动飞向该点"
    tool.Parent         = backpack

    -- Destroy 时会自动断开连接，不需要额外保存
    tool.Activated:Connect(function()
        local pos = mouseTargetPosition()
        if pos then
            setNavTarget(pos)
        end
    end)
end

-- 背包在重生后会重建，所以这里每次都用 WaitForChild 兜底
local function refreshNavTool()
    if not State.navToolEnabled or State.destroyed then
        removeNavTool()
        return
    end

    task.spawn(function()
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if not backpack then
            backpack = LocalPlayer:WaitForChild("Backpack", 10)
        end
        if backpack then
            giveNavTool()
        end
    end)
end

local function setNavToolEnabled(enabled)
    State.navToolEnabled = enabled
    if enabled then
        refreshNavTool()
        notify("定位棒", "已放入背包，手持后左键点击即可设置目标", 3)
    else
        removeNavTool()
        notify("定位棒", "已从背包移除", 2)
    end
end

--=============================================================================
-- 10. 死亡 / 重生
--=============================================================================
local humanoidDiedConn

local function syncActive(enabled)
    if not UIHooks.setActive then return end
    suppressToggleCallback = true
    pcall(UIHooks.setActive, enabled)
    suppressToggleCallback = false
end

local function onCharacterAdded(char)
    State.dead = false

    if State.active then
        stopFloat(true)
        syncActive(false)
    end

    if humanoidDiedConn then
        humanoidDiedConn:Disconnect()
        humanoidDiedConn = nil
    end

    -- 重生后背包会重建，这里重新放回定位棒
    task.delay(0.5, refreshNavTool)

    local humanoid = char:WaitForChild("Humanoid", 10)
    if not humanoid then return end

    humanoidDiedConn = humanoid.Died:Connect(function()
        State.dead = true
        if State.active then
            stopFloat(true)
            syncActive(false)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
    task.spawn(onCharacterAdded, LocalPlayer.Character)
end

-- 模拟半径常驻（1 秒一次，比原版每帧两次轻得多）
startSimulationRadius()

-- 首次放入定位棒
refreshNavTool()

--=============================================================================
-- 11. 界面（WindUI）
--=============================================================================
local Window             -- 当前窗口
local uiToggleActive     -- 「启用漂浮」开关
local uiToggleMove       -- 「允许移动」开关
local uiToggleFixed      -- 「防止旋转」开关
local uiToggleNetwork    -- 「网络所有权」开关
local uiSliderSpeed      -- 「漂浮速度」滑块
local uiDropdownDir      -- 「移动方向」下拉
local uiToggleNavTool    -- 「启用定位棒」开关
local uiDropdownNavScope -- 「导航对象」下拉
local uiSliderNavRadius  -- 「到达半径」滑块
local uiToggleNavMarker  -- 「显示目标标记」开关

-- 卸载：停循环、清漂浮物、销毁界面
local function teardown()
    if State.destroyed then return end
    State.destroyed = true

    stopFloat(true)
    removeNavTool()
    simLoopRunning = false

    if humanoidDiedConn then
        humanoidDiedConn:Disconnect()
        humanoidDiedConn = nil
    end

    if Window then
        local w = Window
        Window = nil
        pcall(function() w:Destroy() end)
    end
end

local function resetSettings()
    if uiToggleActive and State.active then
        suppressToggleCallback = true
        uiToggleActive:Set(false)
        suppressToggleCallback = false
    end
    stopFloat(true)

    if uiSliderSpeed then uiSliderSpeed:Set(10) end
    if uiDropdownDir then uiDropdownDir:Select({ "向上" }) end
    if uiToggleMove then uiToggleMove:Set(true) end
    if uiToggleFixed then uiToggleFixed:Set(false) end
    if uiToggleNetwork then uiToggleNetwork:Set(false) end
    if uiDropdownNavScope then uiDropdownNavScope:Select({ "全部漂浮物" }) end
    if uiSliderNavRadius then uiSliderNavRadius:Set(6) end
    if uiToggleNavMarker then uiToggleNavMarker:Set(true) end
end

local function createInterface()
    local ok, WindUI = pcall(function()
        return loadstring(game:HttpGet(WINDUI_URL))()
    end)
    if not ok or type(WindUI) ~= "table" then
        warn("[GlobalFloat] WindUI 加载失败：" .. tostring(WindUI))
        return
    end

    Window = WindUI:CreateWindow({
        Title       = "全局漂浮",
        Author      = "by Star_Skater53",
        Folder      = "GlobalFloat",
        Icon        = "box",
        Theme       = "Dark",
        Size        = UDim2.fromOffset(620, 470),
        MinSize     = Vector2.new(520, 380),
        MaxSize     = Vector2.new(900, 620),
        ToggleKey   = Enum.KeyCode.RightShift,
        Resizable   = true,
        NewElements = true,
        OpenButton  = {
            Title     = "漂浮",
            Enabled   = true,
            Draggable = true,
        },
        User = {
            Enabled = true,
        },
    })

    if not Window then
        warn("[GlobalFloat] 创建窗口失败，请重进服务器后重新执行")
        return
    end

    UIHooks.notify = function(title, content, duration)
        WindUI:Notify({
            Title    = title,
            Content  = content,
            Icon     = "solar:bell-bold",
            Duration = duration or 3,
        })
    end

    Window:OnDestroy(function()
        teardown()
    end)

    --=========================== 控制页 ===========================
    local MainTab = Window:Tab({ Title = "控制", Icon = "gamepad-2" })

    MainTab:Section({ Title = "总开关", TextSize = 16, TextTransparency = 0.35 })

    uiToggleActive = MainTab:Toggle({
        Title = "启用漂浮",
        Desc  = "开启后处理场景内所有符合条件的部件",
        Value = false,
        Callback = function(state)
            if suppressToggleCallback then return end

            if state then
                if startFloat() then
                    notify("已启用", "速度 " .. State.speed .. " · 方向 " .. State.direction)
                else
                    syncActive(false)
                end
            else
                stopFloat(true)
                notify("已关闭", "漂浮物已恢复原状", 2)
            end
        end,
    })

    UIHooks.setActive = function(state)
        if uiToggleActive then
            uiToggleActive:Set(state)
        end
    end

    MainTab:Space()

    uiToggleMove = MainTab:Toggle({
        Title = "允许移动",
        Desc  = "关闭后部件保持漂浮但不再位移",
        Value = true,
        Callback = function(state)
            setMoving(state)
        end,
    })

    MainTab:Space()
    MainTab:Section({ Title = "运动参数", TextSize = 16, TextTransparency = 0.35 })

    uiSliderSpeed = MainTab:Slider({
        Title = "漂浮速度",
        Desc  = "数值越大移动越快",
        Step  = 5,
        Value = { Min = SPEED_MIN, Max = SPEED_MAX, Default = State.speed },
        Callback = function(value)
            setSpeed(value)
        end,
    })

    MainTab:Space()

    uiDropdownDir = MainTab:Dropdown({
        Title    = "移动方向",
        Desc     = "前后左右按切换时的相机朝向；「跟随视角」会实时朝相机前方飞",
        Values   = DIR_LABELS,
        Value    = "向上",
        Callback = function(selected)
            local key = DIR_LABEL_TO_KEY[selected]
            if key then
                setDirection(key)
            end
        end,
    })

    MainTab:Space()

    MainTab:Button({
        Title = "重新扫描场景",
        Desc  = "把后出现的部件也加入漂浮",
        Icon  = "refresh-cw",
        Callback = function()
            if not State.active then
                notify("未启用", "请先打开「启用漂浮」", 2)
                return
            end
            rescan()
            notify("扫描完成", "符合条件的部件均已加入漂浮", 2)
        end,
    })

    MainTab:Space()

    MainTab:Button({
        Title = "清除全部漂浮物",
        Desc  = "停止漂浮并移除所有 BodyMover",
        Icon  = "trash-2",
        Color = Color3.fromHex("#e5484d"),
        Callback = function()
            suppressToggleCallback = true
            if uiToggleActive then uiToggleActive:Set(false) end
            suppressToggleCallback = false

            stopFloat(true)
            notify("已清除", "所有漂浮物已恢复原状", 2)
        end,
    })

    --=========================== 高级页 ===========================
    local AdvTab = Window:Tab({ Title = "高级", Icon = "sliders-horizontal" })

    AdvTab:Section({ Title = "物理行为", TextSize = 16, TextTransparency = 0.35 })

    uiToggleFixed = AdvTab:Toggle({
        Title = "防止旋转",
        Desc  = "用 BodyGyro 锁住朝向，避免部件翻滚",
        Value = false,
        Callback = function(state)
            setFixedRotation(state)
        end,
    })

    AdvTab:Space()

    uiToggleNetwork = AdvTab:Toggle({
        Title = "网络所有权",
        Desc  = "把部件物理计算交给本地客户端",
        Value = false,
        Callback = function(state)
            setNetworkOwnershipEnabled(state)
        end,
    })

    AdvTab:Space()

    AdvTab:Section({
        Title            = "说明",
        Desc             = "网络所有权会明显改变同步表现；若出现回弹或抖动，关掉它即可。",
        TextSize         = 14,
        TextTransparency = 0.5,
    })

    --=========================== 导航页 ===========================
    local NavTab = Window:Tab({ Title = "导航", Icon = "navigation" })

    NavTab:Section({ Title = "定位棒", TextSize = 16, TextTransparency = 0.35 })

    uiToggleNavTool = NavTab:Toggle({
        Title = "启用定位棒",
        Desc  = "在背包中生成「定位棒」，手持后左键点击即可设置导航目标",
        Value = true,
        Callback = function(state)
            setNavToolEnabled(state)
        end,
    })

    NavTab:Space()
    NavTab:Section({ Title = "导航设置", TextSize = 16, TextTransparency = 0.35 })

    uiDropdownNavScope = NavTab:Dropdown({
        Title  = "导航对象",
        Desc   = "「最近的一个」指离你最近的漂浮物",
        Values = { "全部漂浮物", "最近的一个" },
        Value  = "全部漂浮物",
        Callback = function(selected)
            setNavScope(selected == "最近的一个" and "nearest" or "all")
        end,
    })

    NavTab:Space()

    uiSliderNavRadius = NavTab:Slider({
        Title = "到达半径",
        Desc  = "距离目标小于该值就停下",
        Step  = 1,
        Value = { Min = 2, Max = 30, Default = State.navRadius },
        Callback = function(value)
            setNavRadius(value)
        end,
    })

    NavTab:Space()

    uiToggleNavMarker = NavTab:Toggle({
        Title = "显示目标标记",
        Desc  = "在目标点生成一个蓝色光球",
        Value = true,
        Callback = function(state)
            setMarkerVisible(state)
        end,
    })

    NavTab:Space()

    NavTab:Button({
        Title = "清除导航目标",
        Desc  = "漂浮物就地停下，恢复原来的漂浮方向",
        Icon  = "circle-slash",
        Callback = function()
            if not State.navTarget then
                notify("无目标", "当前没有正在进行的导航", 2)
                return
            end
            clearNavTarget()
            notify("已清除", "漂浮物已恢复原方向", 2)
        end,
    })

    NavTab:Space()

    NavTab:Section({
        Title            = "说明",
        Desc             = "导航会让漂浮物自动绕开障碍飞向目标点；若中途关掉「启用漂浮」，导航会一并结束。",
        TextSize         = 14,
        TextTransparency = 0.5,
    })

    --=========================== 设置页 ===========================
    local SetTab = Window:Tab({ Title = "设置", Icon = "settings" })

    SetTab:Section({ Title = "界面", TextSize = 16, TextTransparency = 0.35 })

    local themeNames = {}
    for name in pairs(WindUI:GetThemes()) do
        table.insert(themeNames, name)
    end
    table.sort(themeNames)

    SetTab:Dropdown({
        Title    = "界面主题",
        Values   = themeNames,
        Value    = WindUI:GetCurrentTheme(),
        Callback = function(selected)
            WindUI:SetTheme(selected)
        end,
    })

    SetTab:Space()

    SetTab:Keybind({
        Title = "打开/关闭面板",
        Desc  = "支持键盘按键与鼠标左右键",
        Value = "RightShift",
        Callback = function(keyName)
            local keyCode = Enum.KeyCode[keyName]
            if keyCode then
                Window:SetToggleKey(keyCode)
            else
                notify("不支持", "该按键无法用作面板开关", 2)
            end
        end,
    })

    SetTab:Space()
    SetTab:Section({ Title = "操作", TextSize = 16, TextTransparency = 0.35 })

    SetTab:Button({
        Title = "重置所有设置",
        Desc  = "速度、方向、物理与导航选项恢复默认",
        Icon  = "rotate-ccw",
        Callback = function()
            resetSettings()
            notify("已重置", "所有设置已恢复默认值", 2)
        end,
    })

    SetTab:Space()

    SetTab:Button({
        Title = "卸载脚本",
        Desc  = "清理漂浮物并关闭界面",
        Icon  = "power",
        Color = Color3.fromHex("#e5484d"),
        Callback = function()
            teardown()
        end,
    })

    WindUI:Notify({
        Title    = "全局漂浮已加载",
        Content  = "按 RightShift 可随时开关面板",
        Icon     = "solar:bell-bold",
        Duration = 4,
    })
end

--=============================================================================
-- 12. 启动
--=============================================================================
-- 重复执行时先清理上一次的残留
if _G.__GlobalFloat then
    pcall(_G.__GlobalFloat)
    _G.__GlobalFloat = nil
end
_G.__GlobalFloat = teardown

createInterface()
print("全局物体漂浮脚本已加载")
