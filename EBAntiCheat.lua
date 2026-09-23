-- Anticheat server-side focado em Fly.
-- Usa pontuação/evidências em várias amostras para reduzir falsos positivos.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService:WaitForChild("EBServerConfig"))
local Settings = Config.AntiCheat
local FlyAuth = require(ServerScriptService:WaitForChild("EBFlyAuthorization"))

local AntiCheat = {}
local started = false
local states = {}

local function horizontalSpeed(v)
    return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function rayDistance(character, root)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = false

    local maxDistance = tonumber(Settings.MaxGroundRayDistance) or 70
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -maxDistance, 0), params)
    if not result then
        return math.huge
    end
    return math.max(0, root.Position.Y - result.Position.Y)
end

local function stateFor(player)
    local s = states[player.UserId]
    if not s then
        s = {
            score = 0,
            hoverTime = 0,
            confirmedTicks = 0,
            warned = false,
            lastPosition = nil,
            lastSample = os.clock(),
            lastEvidence = nil,
        }
        states[player.UserId] = s
    end
    return s
end

local function resetMotionState(s, root)
    s.score = math.max(0, s.score - 1.5)
    s.hoverTime = 0
    s.confirmedTicks = math.max(0, s.confirmedTicks - 1)
    s.lastPosition = root and root.Position or nil
    s.lastSample = os.clock()
end

local function exempt(player, humanoid, root)
    if FlyAuth.IsAuthorized(player) then
        return true, "AdminFly"
    end
    if FlyAuth.HasGrace(player) then
        return true, "Grace"
    end
    if root.Anchored then
        return true, "Anchored"
    end
    if humanoid.SeatPart ~= nil then
        return true, "Seated"
    end

    local hState = humanoid:GetState()
    if hState == Enum.HumanoidStateType.Dead
        or hState == Enum.HumanoidStateType.Swimming
        or hState == Enum.HumanoidStateType.Climbing then
        return true, tostring(hState)
    end

    return false
end

local function sample(player, callbacks)
    local character = player.Character
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    local s = stateFor(player)
    local t = os.clock()
    local dt = math.clamp(t - s.lastSample, 0.05, 2)
    s.lastSample = t

    local isExempt = exempt(player, humanoid, root)
    if isExempt then
        resetMotionState(s, root)
        return
    end

    local velocity = root.AssemblyLinearVelocity
    local groundDistance = rayDistance(character, root)
    local floorGrounded = humanoid.FloorMaterial ~= Enum.Material.Air
    local nearGround = floorGrounded or groundDistance <= 7
    local farFromGround = groundDistance >= (tonumber(Settings.SuspiciousGroundDistance) or 14)
    local vLimit = tonumber(Settings.HoverVerticalSpeed) or 5.5
    local hovering = farFromGround and math.abs(velocity.Y) <= vLimit

    if hovering then
        s.hoverTime += dt
    else
        s.hoverTime = math.max(0, s.hoverTime - dt * 1.75)
    end

    local movementDelta = 0
    if s.lastPosition then
        movementDelta = (root.Position - s.lastPosition).Magnitude
    end
    s.lastPosition = root.Position

    if nearGround then
        s.score = math.max(0, s.score - 2.0)
        s.confirmedTicks = math.max(0, s.confirmedTicks - 1)
    else
        s.score = math.max(0, s.score - 0.12)
    end

    if s.hoverTime >= (tonumber(Settings.HoverSecondsBeforeScore) or 2.5) then
        s.score += 1.35
    end

    local hState = humanoid:GetState()
    if farFromGround and velocity.Y > 12
        and hState ~= Enum.HumanoidStateType.Jumping
        and hState ~= Enum.HumanoidStateType.Freefall then
        s.score += 0.7
    end

    if movementDelta >= (tonumber(Settings.ImpossibleMoveStudsPerSample) or 95) and dt <= 1 then
        s.score += 0.9
    end

    local strongHover = s.hoverTime >= 4.0 and farFromGround and math.abs(velocity.Y) <= 4.0
    if strongHover then
        s.confirmedTicks += 1
    else
        s.confirmedTicks = math.max(0, s.confirmedTicks - 1)
    end

    local evidence = {
        score = string.format("%.2f", s.score),
        hoverSeconds = string.format("%.2f", s.hoverTime),
        groundDistance = groundDistance == math.huge and ">70" or string.format("%.1f", groundDistance),
        velocityY = string.format("%.1f", velocity.Y),
        horizontalSpeed = string.format("%.1f", horizontalSpeed(velocity)),
        humanoidState = tostring(hState),
        moveDelta = string.format("%.1f", movementDelta),
        flyAuthorized = "false",
    }
    s.lastEvidence = evidence

    local warnScore = tonumber(Settings.WarnScore) or 6
    if s.score >= warnScore and not s.warned then
        s.warned = true
        if callbacks.OnSuspicious then
            callbacks.OnSuspicious(player, evidence)
        end
    elseif s.score < warnScore * 0.45 then
        s.warned = false
    end

    local banScore = tonumber(Settings.BanScore) or 12
    local requiredTicks = tonumber(Settings.ConfirmedTicks) or 3
    if s.score >= banScore and s.confirmedTicks >= requiredTicks then
        if callbacks.OnConfirmed then
            callbacks.OnConfirmed(player, evidence)
        end
        -- Impede disparo repetido enquanto callback processa kick/ban.
        s.score = -1000
        s.confirmedTicks = 0
    end
end

function AntiCheat.Start(callbacks)
    if started or Settings.Enabled ~= true then
        return
    end
    started = true
    callbacks = callbacks or {}

    local spawnGrace = tonumber(Settings.SpawnGraceSeconds) or 8

    local function hookPlayer(player)
        player.CharacterAdded:Connect(function()
            FlyAuth.GrantGrace(player, spawnGrace, "Spawn")
            states[player.UserId] = nil
        end)
        if player.Character then
            FlyAuth.GrantGrace(player, spawnGrace, "Spawn")
        end
    end

    Players.PlayerAdded:Connect(hookPlayer)
    Players.PlayerRemoving:Connect(function(player)
        states[player.UserId] = nil
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayer(player)
    end

    task.spawn(function()
        local interval = math.max(0.25, tonumber(Settings.SampleInterval) or 0.5)
        while true do
            task.wait(interval)
            for _, player in ipairs(Players:GetPlayers()) do
                local ok, err = pcall(sample, player, callbacks)
                if not ok then
                    warn("[EB AntiCheat] Erro ao analisar", player.Name, err)
                end
            end
        end
    end)
end

return AntiCheat
