--[[
    EB // SISTEMA COMPLETO V7 - LOGS DISCORD + ANTICHEAT
    Dono configurado: UserId 468762368
    Sub-Dono fixo: UserId 2887861665

    Execute UMA VEZ na Command Bar, fora do Play.
    O instalador recria o StarterGui e instala:
      - Menu gráfico militar (PC + Mobile)
      - Painel administrativo arrastável (mouse + touch)
      - Sistema de cargos, punições, logs e DataStore
      - Comandos em outros jogadores, em todos e no próprio administrador
      - Dono automático para o UserId configurado
      - Integração SERVER-SIDE com bot de logs do Discord
      - Anticheat de Fly integrado ao Fly/Unfly/FlyAll/UnflyAll
]]

local OWNER_USER_ID = 468762368
local SUB_OWNER_USER_ID = 2887861665
local ALLOW_MULTIPLE_OWNERS = false
local ADMIN_AUTO_JOIN_SUPPORT = true

-- ============================================================
-- BOT DE LOGS / BACKEND
-- Preencha após publicar o backend no Railway.
-- O segredo fica SOMENTE em ServerScriptService.
-- ============================================================
local LOG_BACKEND_URL = "https://SEU-PROJETO.up.railway.app"
local LOG_SHARED_SECRET = "55uxhXUuOGXeYctHc8jAExIEWWkt_yZMKLQ9qzG5hud20GcKD_tWRKrWlT-vHfHv"

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")

-- Garante que o Team Suporte exista para o painel administrativo.
local supportTeam = Teams:FindFirstChild("Suporte")
if not supportTeam then
    supportTeam = Instance.new("Team")
    supportTeam.Name = "Suporte"
    supportTeam.AutoAssignable = false
    supportTeam.TeamColor = BrickColor.new("Earth green")
    supportTeam.Parent = Teams
end

-- ============================================================
-- LIMPEZA SEGURA / REINSTALAÇÃO
-- ============================================================
for _, child in ipairs(StarterGui:GetChildren()) do
    child:Destroy()
end

for _, info in ipairs({
    {ReplicatedStorage, "EBAdminSystem"},
    {ServerScriptService, "EBAdminServer"},
    {ServerScriptService, "EBServerConfig"},
    {ServerScriptService, "EBLogBridge"},
    {ServerScriptService, "EBFlyAuthorization"},
    {ServerScriptService, "EBAntiCheat"},
}) do
    local old = info[1]:FindFirstChild(info[2])
    if old then old:Destroy() end
end

local function make(className, name, parent)
    local obj = Instance.new(className)
    obj.Name = name
    obj.Parent = parent
    return obj
end

-- ============================================================
-- REPLICATEDSTORAGE > EBAdminSystem
-- ============================================================
local adminFolder = make("Folder", "EBAdminSystem", ReplicatedStorage)
local actionRemote = make("RemoteEvent", "Action", adminFolder)
local queryRemote = make("RemoteFunction", "Query", adminFolder)

local configModule = make("ModuleScript", "Config", adminFolder)
configModule.Source = string.format([==[
local Config = {}

Config.OWNER_USER_ID = %d
Config.SUB_OWNER_USER_ID = %d
Config.ALLOW_MULTIPLE_OWNERS = %s
Config.ADMIN_AUTO_JOIN_SUPPORT = %s

Config.RankLevels = {
    ["Nenhum"] = 0,
    ["Suporte"] = 1,
    ["Moderador"] = 2,
    ["Administrador"] = 3,
    ["Supervisor"] = 4,
    ["Sub-Dono"] = 5,
    ["Dono"] = 6,
}

Config.RankOrder = {
    "Nenhum",
    "Suporte",
    "Moderador",
    "Administrador",
    "Supervisor",
    "Sub-Dono",
    "Dono",
}

Config.TempBanDurations = {
    600, 1800, 3600, 21600, 43200, 86400, 259200, 604800,
}

Config.MaxWarningsPerPlayer = 50
Config.MaxGlobalLogs = 250
Config.GlobalLogRetentionSeconds = 7 * 24 * 60 * 60
Config.RemoteCooldown = 0.25
Config.FlySpeed = 72

return Config
]==], OWNER_USER_ID, SUB_OWNER_USER_ID, tostring(ALLOW_MULTIPLE_OWNERS), tostring(ADMIN_AUTO_JOIN_SUPPORT))

-- ============================================================
-- SERVER-ONLY CONFIG + LOGS + ANTICHEAT
-- ============================================================
local serverConfigModule = make("ModuleScript", "EBServerConfig", ServerScriptService)
serverConfigModule.Source = string.format([====[
return {
    Logging = {
        Enabled = true,
        ApiBaseUrl = %q,
        SharedSecret = %q,
        BatchSeconds = 2.5,
        MaxBatch = 10,
        MaxQueue = 120,
        HeartbeatSeconds = 20,
    },
    AntiCheat = {
        Enabled = true,
        AutoBan = true,
        SampleInterval = 0.5,
        SpawnGraceSeconds = 8,
        AdminTeleportGraceSeconds = 5,
        MaxGroundRayDistance = 70,
        SuspiciousGroundDistance = 14,
        HoverVerticalSpeed = 5.5,
        HoverSecondsBeforeScore = 2.5,
        WarnScore = 6,
        BanScore = 12,
        ConfirmedTicks = 3,
        ImpossibleMoveStudsPerSample = 95,
    },
}
]====], LOG_BACKEND_URL, LOG_SHARED_SECRET)

local flyAuthModule = make("ModuleScript", "EBFlyAuthorization", ServerScriptService)
flyAuthModule.Source = [====[
-- Autorizações de voo controladas SOMENTE pelo servidor.
-- O anticheat nunca confia em atributo criado pelo cliente.

local Players = game:GetService("Players")

local FlyAuthorization = {}
local authorized = {}
local grace = {}

local function now()
    return os.clock()
end

function FlyAuthorization.Grant(player, source, byUserId, durationSeconds)
    if not player or not player:IsA("Player") then
        return false
    end

    local expiresAt = nil
    if type(durationSeconds) == "number" and durationSeconds > 0 then
        expiresAt = now() + durationSeconds
    end

    authorized[player.UserId] = {
        source = tostring(source or "Admin"),
        byUserId = tonumber(byUserId) or 0,
        grantedAt = now(),
        expiresAt = expiresAt,
    }

    -- Apenas espelho visual/depuração. O anticheat NÃO usa este atributo como fonte de verdade.
    player:SetAttribute("AdminFlyAuthorized", true)
    return true
end

function FlyAuthorization.Revoke(player)
    if not player or not player:IsA("Player") then
        return false
    end
    authorized[player.UserId] = nil
    player:SetAttribute("AdminFlyAuthorized", false)
    return true
end

function FlyAuthorization.IsAuthorized(player)
    if not player or not player:IsA("Player") then
        return false
    end

    local info = authorized[player.UserId]
    if not info then
        return false
    end

    if info.expiresAt and now() >= info.expiresAt then
        authorized[player.UserId] = nil
        player:SetAttribute("AdminFlyAuthorized", false)
        return false
    end

    return true, info
end

function FlyAuthorization.GrantGrace(player, seconds, reason)
    if not player or not player:IsA("Player") then
        return
    end
    seconds = math.clamp(tonumber(seconds) or 0, 0, 30)
    grace[player.UserId] = {
        untilTime = now() + seconds,
        reason = tostring(reason or "Grace"),
    }
end

function FlyAuthorization.HasGrace(player)
    if not player or not player:IsA("Player") then
        return false
    end
    local info = grace[player.UserId]
    if not info then
        return false
    end
    if now() >= info.untilTime then
        grace[player.UserId] = nil
        return false
    end
    return true, info
end

function FlyAuthorization.GetInfo(player)
    local ok, info = FlyAuthorization.IsAuthorized(player)
    if ok then
        return info
    end
    return nil
end

Players.PlayerRemoving:Connect(function(player)
    authorized[player.UserId] = nil
    grace[player.UserId] = nil
end)

return FlyAuthorization

]====]

local logBridgeModule = make("ModuleScript", "EBLogBridge", ServerScriptService)
logBridgeModule.Source = [====[
-- Ponte SERVER-SIDE Roblox -> backend -> Discord.
-- Usa fila/batch para evitar spam HTTP e envia heartbeat dos servidores ativos.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService:WaitForChild("EBServerConfig"))
local Settings = Config.Logging

local LogBridge = {}
local queue = {}
local started = false
local warnedConfig = false

local function configured()
    if Settings.Enabled ~= true then
        return false
    end
    if type(Settings.ApiBaseUrl) ~= "string" or not Settings.ApiBaseUrl:match("^https://") then
        if not warnedConfig then
            warnedConfig = true
            warn("[EB Logs] ApiBaseUrl inválida. Use URL HTTPS do Railway.")
        end
        return false
    end
    if type(Settings.SharedSecret) ~= "string" or #Settings.SharedSecret < 20 or Settings.SharedSecret:find("TROQUE", 1, true) then
        if not warnedConfig then
            warnedConfig = true
            warn("[EB Logs] Configure SharedSecret em ServerScriptService > EBServerConfig.")
        end
        return false
    end
    return true
end

local function baseUrl()
    return Settings.ApiBaseUrl:gsub("/+$", "")
end

local function authHeaders()
    return {
        ["Content-Type"] = "application/json",
        ["X-EB-Token"] = Settings.SharedSecret,
        ["X-EB-Timestamp"] = tostring(os.time()),
        ["X-EB-Nonce"] = HttpService:GenerateGUID(false),
    }
end

local function request(path, body)
    if not configured() then
        return false, "not_configured"
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = baseUrl() .. path,
            Method = "POST",
            Headers = authHeaders(),
            Body = HttpService:JSONEncode(body),
        })
    end)

    if not ok then
        return false, tostring(response)
    end

    if not response.Success then
        return false, tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage)
    end

    return true
end

local function playerInfo(player)
    if not player then
        return nil
    end
    return {
        userId = player.UserId,
        username = player.Name,
        displayName = player.DisplayName,
        rank = tostring(player:GetAttribute("AdminRank") or "Nenhum"),
    }
end

local function serverInfo()
    return {
        jobId = game.JobId,
        placeId = game.PlaceId,
        universeId = game.GameId,
        privateServerId = game.PrivateServerId,
        playerCount = #Players:GetPlayers(),
    }
end

function LogBridge.Push(data)
    if type(data) ~= "table" then
        return
    end

    data.id = data.id or HttpService:GenerateGUID(false)
    data.timestamp = data.timestamp or os.time()
    data.server = data.server or serverInfo()

    table.insert(queue, data)
    while #queue > (tonumber(Settings.MaxQueue) or 120) do
        table.remove(queue, 1)
    end
end

local function categoryForAction(actionName)
    actionName = string.upper(tostring(actionName or ""))
    if actionName == "WARN" or actionName == "KICK" or actionName == "TEMPBAN" or actionName == "BAN" or actionName == "UNBAN" or actionName == "MUTE" or actionName == "UNMUTE" then
        return "punishment"
    elseif actionName == "CARGO" then
        return "rank"
    elseif actionName:find("ANTICHEAT", 1, true) then
        return "anticheat"
    elseif actionName == "JOIN" or actionName == "LEAVE" then
        return "general"
    end
    return "admin"
end

function LogBridge.PushAdmin(admin, actionName, target, detail, reason)
    local targetInfo
    if typeof(target) == "Instance" and target:IsA("Player") then
        targetInfo = playerInfo(target)
    elseif type(target) == "table" then
        targetInfo = target
    elseif target ~= nil then
        targetInfo = {name = tostring(target)}
    end

    LogBridge.Push({
        category = categoryForAction(actionName),
        action = tostring(actionName),
        admin = playerInfo(admin),
        target = targetInfo,
        detail = detail,
        reason = reason,
    })
end

function LogBridge.PushPlayerEvent(actionName, player)
    LogBridge.Push({
        category = "general",
        action = actionName,
        target = playerInfo(player),
    })
end

function LogBridge.PushAntiCheat(actionName, player, evidence, detail)
    LogBridge.Push({
        category = "anticheat",
        action = actionName,
        target = playerInfo(player),
        detail = detail,
        extra = evidence,
    })
end

local function flush()
    if #queue == 0 or not configured() then
        return
    end

    local maxBatch = math.max(1, math.min(25, tonumber(Settings.MaxBatch) or 10))
    local batch = {}
    for _ = 1, math.min(maxBatch, #queue) do
        table.insert(batch, table.remove(queue, 1))
    end

    local ok, err = request("/api/roblox/logs/batch", {logs = batch})
    if not ok then
        -- Recoloca na frente para tentar de novo depois, sem travar o servidor.
        for i = #batch, 1, -1 do
            table.insert(queue, 1, batch[i])
        end
        while #queue > (tonumber(Settings.MaxQueue) or 120) do
            table.remove(queue)
        end
        warn("[EB Logs] Falha no envio:", err)
    end
end

local function heartbeat()
    if not configured() then
        return
    end

    local players = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(players, playerInfo(player))
    end

    local payload = serverInfo()
    payload.players = players
    payload.timestamp = os.time()

    local ok, err = request("/api/roblox/heartbeat", payload)
    if not ok and not RunService:IsStudio() then
        warn("[EB Logs] Heartbeat falhou:", err)
    end
end

function LogBridge.Start()
    if started then
        return
    end
    started = true

    task.spawn(function()
        while true do
            task.wait(math.max(1, tonumber(Settings.BatchSeconds) or 2.5))
            flush()
        end
    end)

    task.spawn(function()
        task.wait(2)
        while true do
            heartbeat()
            task.wait(math.max(10, tonumber(Settings.HeartbeatSeconds) or 20))
        end
    end)
end

return LogBridge

]====]

local antiCheatModule = make("ModuleScript", "EBAntiCheat", ServerScriptService)
antiCheatModule.Source = [====[
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

]====]

-- ============================================================
-- SERVER SCRIPT
-- ============================================================
local server = make("Script", "EBAdminServer", ServerScriptService)
server.Source = [==[
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ServerScriptService = game:GetService("ServerScriptService")

local Root = ReplicatedStorage:WaitForChild("EBAdminSystem")
local Action = Root:WaitForChild("Action")
local Query = Root:WaitForChild("Query")
local Config = require(Root:WaitForChild("Config"))
local ServerConfig = require(ServerScriptService:WaitForChild("EBServerConfig"))
local ExternalLogger = require(ServerScriptService:WaitForChild("EBLogBridge"))
local FlyAuth = require(ServerScriptService:WaitForChild("EBFlyAuthorization"))
local AntiCheat = require(ServerScriptService:WaitForChild("EBAntiCheat"))

ExternalLogger.Start()

local RankStore = DataStoreService:GetDataStore("EB_AdminRanks_V2")
local BanStore = DataStoreService:GetDataStore("EB_AdminBans_V2")
local WarnStore = DataStoreService:GetDataStore("EB_AdminWarnings_V2")
local GlobalLogStore = DataStoreService:GetDataStore("EB_AdminGlobalLogs_V3")

-- Fallback apenas para testes no Studio quando API Services estiver desligado.
local StudioMemory = {Ranks = {}, Bans = {}, Warnings = {}, GlobalLogs = {}}
local Muted = {}
local LastCall = {}

local function validUserId(value)
    return type(value) == "number" and value > 0 and value < 1e15 and value % 1 == 0
end

local function rankExists(name)
    return type(name) == "string" and Config.RankLevels[name] ~= nil
end

local function levelOfRank(name)
    return Config.RankLevels[name] or 0
end

local function supportTeam()
    return Teams:FindFirstChild("Suporte")
end

local function isSupport(player)
    local team = supportTeam()
    return team ~= nil and player.Team == team
end

local function currentRank(player)
    if player.UserId == Config.OWNER_USER_ID then
        return "Dono"
    end
    if player.UserId == Config.SUB_OWNER_USER_ID then
        return "Sub-Dono"
    end
    local rank = player:GetAttribute("AdminRank")
    return rankExists(rank) and rank or "Nenhum"
end

local function currentLevel(player)
    return levelOfRank(currentRank(player))
end

local function notify(player, ok, message)
    if player and player.Parent == Players then
        Action:FireClient(player, "Result", {
            success = ok == true,
            message = tostring(message or ""),
        })
    end
end

local function refreshAll(kind, userId)
    Action:FireAllClients("Refresh", {kind = kind, userId = userId})
end

local function pruneGlobalLogs(logs)
    local clean = {}
    local cutoff = os.time() - Config.GlobalLogRetentionSeconds

    if type(logs) ~= "table" then
        return clean
    end

    for _, log in ipairs(logs) do
        if type(log) == "table" and (tonumber(log.Time) or 0) >= cutoff then
            table.insert(clean, log)
            if #clean >= Config.MaxGlobalLogs then
                break
            end
        end
    end

    return clean
end

local function readGlobalLogs()
    local ok, value = pcall(function()
        return GlobalLogStore:GetAsync("GLOBAL")
    end)

    if ok then
        return pruneGlobalLogs(value)
    end

    warn("[EB Admin] Falha ao ler histórico global:", value)

    if RunService:IsStudio() then
        return pruneGlobalLogs(StudioMemory.GlobalLogs)
    end

    return {}
end

local function addLog(admin, actionName, targetName, detail, targetUserId)
    local entry = {
        Time = os.time(),
        AdminName = admin and admin.Name or "Sistema",
        AdminUserId = admin and admin.UserId or 0,
        Action = tostring(actionName or "AÇÃO"),
        TargetName = tostring(targetName or "-"),
        TargetUserId = tonumber(targetUserId) or 0,
        Detail = tostring(detail or ""),
    }

    local ok, err = pcall(function()
        GlobalLogStore:UpdateAsync("GLOBAL", function(old)
            local logs = pruneGlobalLogs(old)
            table.insert(logs, 1, entry)
            while #logs > Config.MaxGlobalLogs do
                table.remove(logs)
            end
            return logs
        end)
    end)

    if not ok then
        warn("[EB Admin] Falha ao salvar histórico global:", err)
        if RunService:IsStudio() then
            local logs = pruneGlobalLogs(StudioMemory.GlobalLogs)
            table.insert(logs, 1, entry)
            while #logs > Config.MaxGlobalLogs do
                table.remove(logs)
            end
            StudioMemory.GlobalLogs = logs
        end
    end

    -- O DataStore continua sendo a fonte do histórico dentro do jogo.
    -- Em paralelo, envia o mesmo evento para o backend/Discord sem bloquear o admin.
    local punishmentAction = entry.Action == "WARN"
        or entry.Action == "KICK"
        or entry.Action == "TEMPBAN"
        or entry.Action == "BAN"
        or entry.Action == "UNBAN"

    ExternalLogger.PushAdmin(
        admin,
        entry.Action,
        {
            name = entry.TargetName,
            username = entry.TargetName,
            displayName = entry.TargetName,
            userId = entry.TargetUserId,
        },
        punishmentAction and nil or entry.Detail,
        punishmentAction and entry.Detail or nil
    )

    refreshAll("Logs", entry.AdminUserId)
end

local function rateLimit(player, bucket, cooldown)
    local id = player.UserId
    LastCall[id] = LastCall[id] or {}
    local now = os.clock()
    local last = LastCall[id][bucket] or 0
    if now - last < (cooldown or Config.RemoteCooldown) then
        return false
    end
    LastCall[id][bucket] = now
    return true
end

local function trimReason(value)
    if type(value) ~= "string" then
        return nil, "Motivo inválido."
    end
    local text = value:match("^%s*(.-)%s*$") or ""
    if #text < 3 then
        return nil, "Informe um motivo com pelo menos 3 caracteres."
    end
    if #text > 200 then text = text:sub(1, 200) end
    return text
end

-- ============================================================
-- WRAPPERS DE DATASTORE COM FALLBACK DE STUDIO
-- ============================================================
local function storeGet(store, key, memory)
    local ok, value = pcall(function()
        return store:GetAsync(key)
    end)
    if ok then return value, true end
    warn("[EB Admin] GetAsync falhou:", value)
    if RunService:IsStudio() then
        return memory[key], true
    end
    return nil, false
end

local function storeSet(store, key, value, memory)
    local ok, err = pcall(function()
        store:UpdateAsync(key, function()
            return value
        end)
    end)
    if ok then return true end
    warn("[EB Admin] UpdateAsync falhou:", err)
    if RunService:IsStudio() then
        memory[key] = value
        return true
    end
    return false
end

local function storeRemove(store, key, memory)
    local ok, err = pcall(function()
        store:RemoveAsync(key)
    end)
    if ok then return true end
    warn("[EB Admin] RemoveAsync falhou:", err)
    if RunService:IsStudio() then
        memory[key] = nil
        return true
    end
    return false
end

-- ============================================================
-- CARGOS
-- ============================================================
local function loadRankByUserId(userId)
    if userId == Config.OWNER_USER_ID then
        return "Dono", true
    end
    if userId == Config.SUB_OWNER_USER_ID then
        return "Sub-Dono", true
    end

    local value, ok = storeGet(RankStore, "u_" .. userId, StudioMemory.Ranks)
    if not ok then return "Nenhum", false end
    if not rankExists(value) then return "Nenhum", true end

    if value == "Dono" and not Config.ALLOW_MULTIPLE_OWNERS then
        return "Nenhum", true
    end

    return value, true
end

local function moveToSupportIfAdmin(player, rank)
    if not Config.ADMIN_AUTO_JOIN_SUPPORT then
        return
    end

    if levelOfRank(rank or currentRank(player)) <= 0 then
        return
    end

    local team = supportTeam()
    if team then
        player.Team = team
        player.Neutral = false
    end
end

local function loadPlayerRank(player)
    local rank, ok = loadRankByUserId(player.UserId)
    player:SetAttribute("AdminRank", rank)
    player:SetAttribute("AdminRankLoaded", ok)

    if ok then
        moveToSupportIfAdmin(player, rank)
    end

    return ok
end

local function saveRank(userId, rank)
    if not validUserId(userId) or not rankExists(rank) then
        return false, "Cargo inválido."
    end

    if userId == Config.OWNER_USER_ID then
        return false, "O cargo do Dono principal é fixo e não pode ser alterado."
    end

    if userId == Config.SUB_OWNER_USER_ID then
        return false, "O cargo do Sub-Dono principal é fixo e não pode ser alterado."
    end

    local key = "u_" .. userId
    local ok

    if rank == "Nenhum" then
        ok = storeRemove(RankStore, key, StudioMemory.Ranks)
    else
        ok = storeSet(RankStore, key, rank, StudioMemory.Ranks)
    end

    if not ok then
        return false, "Falha ao salvar o cargo."
    end

    local online = Players:GetPlayerByUserId(userId)
    if online then
        online:SetAttribute("AdminRank", rank)
        online:SetAttribute("AdminRankLoaded", true)
        if rank ~= "Nenhum" then
            moveToSupportIfAdmin(online, rank)
        end
    end

    return true
end

-- ============================================================
-- BANIMENTOS
-- ============================================================
local function getBan(userId)
    local data, ok = storeGet(BanStore, "u_" .. userId, StudioMemory.Bans)
    if not ok or type(data) ~= "table" then return nil, ok end

    if data.Permanent ~= true then
        local expires = tonumber(data.ExpiresAt) or 0
        if expires <= os.time() then
            storeRemove(BanStore, "u_" .. userId, StudioMemory.Bans)
            return nil, true
        end
    end
    return data, true
end

local function saveBan(userId, data)
    return storeSet(BanStore, "u_" .. userId, data, StudioMemory.Bans)
end

local function removeBan(userId)
    return storeRemove(BanStore, "u_" .. userId, StudioMemory.Bans)
end

local function durationText(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds % 86400 == 0 and seconds >= 86400 then
        local n = seconds / 86400
        return n .. (n == 1 and " dia" or " dias")
    elseif seconds % 3600 == 0 and seconds >= 3600 then
        local n = seconds / 3600
        return n .. (n == 1 and " hora" or " horas")
    elseif seconds % 60 == 0 and seconds >= 60 then
        local n = seconds / 60
        return n .. (n == 1 and " minuto" or " minutos")
    end
    return seconds .. " segundos"
end

local function kickForBan(player, ban)
    local duration = ban.Permanent == true and "Permanente"
        or durationText((tonumber(ban.ExpiresAt) or os.time()) - os.time())
    player:Kick(
        "Você foi banido deste jogo.\n\nMotivo: " .. tostring(ban.Reason or "Não informado")
        .. "\nAdministrador: " .. tostring(ban.AdminName or "Sistema")
        .. "\nDuração: " .. duration
    )
end

-- ============================================================
-- ADVERTÊNCIAS
-- ============================================================
local function getWarnings(userId)
    local value, ok = storeGet(WarnStore, "u_" .. userId, StudioMemory.Warnings)
    if not ok or type(value) ~= "table" then return {} end
    return value
end

local function addWarning(targetUserId, admin, reason)
    local key = "u_" .. targetUserId
    local current = getWarnings(targetUserId)
    table.insert(current, 1, {
        Reason = reason,
        AdminName = admin.Name,
        AdminUserId = admin.UserId,
        At = os.time(),
    })
    while #current > Config.MaxWarningsPerPlayer do
        table.remove(current)
    end
    local ok = storeSet(WarnStore, key, current, StudioMemory.Warnings)
    return ok
end

-- ============================================================
-- HIERARQUIA / ALVOS
-- ============================================================
local function onlineTarget(payload)
    if type(payload) ~= "table" or not validUserId(payload.targetUserId) then
        return nil, "Jogador inválido."
    end
    local target = Players:GetPlayerByUserId(payload.targetUserId)
    if not target then return nil, "O jogador não está mais no servidor." end
    return target
end

local function canActOn(admin, target)
    if admin == target then return false, "Você não pode usar essa ação em si mesmo." end
    if target.UserId == Config.OWNER_USER_ID then return false, "O Dono principal está protegido." end
    if target:GetAttribute("AdminRankLoaded") ~= true then
        return false, "O cargo do alvo ainda está carregando."
    end
    if currentLevel(admin) <= currentLevel(target) then
        return false, "Você só pode administrar cargos inferiores ao seu."
    end
    return true
end

local function requireLevel(player, level)
    if currentLevel(player) < level then
        return false, "Você não possui permissão para essa ação."
    end
    return true
end

-- ============================================================
-- MUTE NO TEXTCHATSERVICE
-- ============================================================
local hookedChannels = setmetatable({}, {__mode = "k"})

local function hookChannel(channel)
    if not channel:IsA("TextChannel") or hookedChannels[channel] then return end
    hookedChannels[channel] = true

    pcall(function()
        local previous = channel.ShouldDeliverCallback
        channel.ShouldDeliverCallback = function(message, targetTextSource)
            local source = message and message.TextSource
            if source and Muted[source.UserId] then
                return false
            end
            if type(previous) == "function" then
                local ok, result = pcall(previous, message, targetTextSource)
                if ok and result == false then return false end
            end
            return true
        end
    end)
end

for _, obj in ipairs(TextChatService:GetDescendants()) do
    hookChannel(obj)
end
TextChatService.DescendantAdded:Connect(function(obj)
    task.defer(hookChannel, obj)
end)

-- ============================================================
-- RESUMO DOS JOGADORES
-- ============================================================
local function playerInfo(player)
    return {
        Name = player.Name,
        DisplayName = player.DisplayName,
        UserId = player.UserId,
        Rank = currentRank(player),
        Level = currentLevel(player),
        RankLoaded = player.UserId == Config.OWNER_USER_ID or player.UserId == Config.SUB_OWNER_USER_ID or player:GetAttribute("AdminRankLoaded") == true,
        Muted = Muted[player.UserId] == true,
    }
end

local function playerList()
    local result = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(result, playerInfo(player))
    end
    table.sort(result, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    return result
end

-- ============================================================
-- CONSULTAS DO CLIENTE
-- ============================================================
Query.OnServerInvoke = function(player, request, payload)
    if not rateLimit(player, "query", 0.08) then
        return {success = false, message = "Aguarde um instante."}
    end
    if type(request) ~= "string" then
        return {success = false, message = "Consulta inválida."}
    end

    if request == "Bootstrap" then
        return {
            success = true,
            teamSupport = isSupport(player),
            rank = currentRank(player),
            level = currentLevel(player),
            players = isSupport(player) and playerList() or {},
            allowMultipleOwners = Config.ALLOW_MULTIPLE_OWNERS,
        }
    end

    if request == "Players" then
        if not isSupport(player) then
            return {success = false, message = "Você não está no Team Suporte."}
        end
        return {success = true, players = playerList()}
    end

    if request == "Warnings" then
        if currentLevel(player) < 1 then
            return {success = false, message = "Sem permissão."}
        end
        if type(payload) ~= "table" or not validUserId(payload.targetUserId) then
            return {success = false, message = "UserId inválido."}
        end
        return {success = true, warnings = getWarnings(payload.targetUserId)}
    end

    if request == "Logs" then
        if currentLevel(player) < 4 then
            return {success = false, message = "Supervisor ou superior necessário."}
        end

        return {
            success = true,
            logs = readGlobalLogs(),
            global = true,
            retentionDays = 7,
        }
    end

    return {success = false, message = "Consulta desconhecida."}
end

-- ============================================================
-- AÇÕES ADMINISTRATIVAS
-- ============================================================
Action.OnServerEvent:Connect(function(admin, actionName, payload)
    if not rateLimit(admin, "action", Config.RemoteCooldown) then
        notify(admin, false, "Aguarde um instante antes da próxima ação.")
        return
    end
    if type(actionName) ~= "string" or type(payload) ~= "table" then
        notify(admin, false, "Dados inválidos.")
        return
    end

    -- WARN
    if actionName == "Warn" then
        local ok, err = requireLevel(admin, 1)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        local hierarchy, hierarchyErr = canActOn(admin, target)
        if not hierarchy then notify(admin, false, hierarchyErr) return end
        local reason, reasonErr = trimReason(payload.reason)
        if not reason then notify(admin, false, reasonErr) return end
        if not addWarning(target.UserId, admin, reason) then
            notify(admin, false, "Não foi possível salvar a advertência.") return
        end
        addLog(admin, "WARN", target.Name, reason, target.UserId)
        notify(admin, true, "Advertência aplicada em " .. target.Name .. ".")
        refreshAll("Warnings", target.UserId)
        return
    end

    -- KICK
    if actionName == "Kick" then
        local ok, err = requireLevel(admin, 2)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        local hierarchy, hierarchyErr = canActOn(admin, target)
        if not hierarchy then notify(admin, false, hierarchyErr) return end
        local reason, reasonErr = trimReason(payload.reason)
        if not reason then notify(admin, false, reasonErr) return end
        addLog(admin, "KICK", target.Name, reason, target.UserId)
        notify(admin, true, target.Name .. " foi expulso.")
        task.delay(0.15, function()
            if target.Parent == Players then
                target:Kick("Você foi expulso.\n\nMotivo: " .. reason .. "\nAdministrador: " .. admin.Name)
            end
        end)
        return
    end

    -- MUTE / UNMUTE
    if actionName == "Mute" or actionName == "Unmute" then
        local ok, err = requireLevel(admin, 2)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        local hierarchy, hierarchyErr = canActOn(admin, target)
        if not hierarchy then notify(admin, false, hierarchyErr) return end
        local mute = actionName == "Mute"
        Muted[target.UserId] = mute or nil
        target:SetAttribute("AdminMuted", mute)
        addLog(admin, mute and "MUTE" or "UNMUTE", target.Name, mute and "Chat silenciado" or "Chat liberado", target.UserId)
        notify(admin, true, target.Name .. (mute and " foi mutado." or " foi desmutado."))
        refreshAll("Players", target.UserId)
        return
    end

    -- TEMPBAN
    if actionName == "TempBan" then
        local ok, err = requireLevel(admin, 3)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        local hierarchy, hierarchyErr = canActOn(admin, target)
        if not hierarchy then notify(admin, false, hierarchyErr) return end
        local reason, reasonErr = trimReason(payload.reason)
        if not reason then notify(admin, false, reasonErr) return end

        local duration = tonumber(payload.duration)
        local durationAllowed = false
        for _, allowed in ipairs(Config.TempBanDurations) do
            if duration == allowed then durationAllowed = true break end
        end
        if not durationAllowed then notify(admin, false, "Duração inválida.") return end

        local ban = {
            Permanent = false,
            ExpiresAt = os.time() + duration,
            Reason = reason,
            AdminName = admin.Name,
            AdminUserId = admin.UserId,
            At = os.time(),
        }
        if not saveBan(target.UserId, ban) then
            notify(admin, false, "Falha ao salvar o TempBan.") return
        end
        addLog(admin, "TEMPBAN", target.Name, reason .. " • " .. durationText(duration), target.UserId)
        notify(admin, true, target.Name .. " recebeu TempBan de " .. durationText(duration) .. ".")
        task.delay(0.15, function()
            if target.Parent == Players then kickForBan(target, ban) end
        end)
        return
    end

    -- BAN PERMANENTE
    if actionName == "Ban" then
        local ok, err = requireLevel(admin, 5)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        local hierarchy, hierarchyErr = canActOn(admin, target)
        if not hierarchy then notify(admin, false, hierarchyErr) return end
        local reason, reasonErr = trimReason(payload.reason)
        if not reason then notify(admin, false, reasonErr) return end

        local ban = {
            Permanent = true,
            ExpiresAt = 0,
            Reason = reason,
            AdminName = admin.Name,
            AdminUserId = admin.UserId,
            At = os.time(),
        }
        if not saveBan(target.UserId, ban) then
            notify(admin, false, "Falha ao salvar o banimento.") return
        end
        addLog(admin, "BAN", target.Name, reason, target.UserId)
        notify(admin, true, target.Name .. " foi banido permanentemente.")
        task.delay(0.15, function()
            if target.Parent == Players then kickForBan(target, ban) end
        end)
        return
    end

    -- UNBAN OFFLINE POR USERID
    if actionName == "Unban" then
        local ok, err = requireLevel(admin, 3)
        if not ok then notify(admin, false, err) return end
        local targetUserId = payload.targetUserId
        if not validUserId(targetUserId) then notify(admin, false, "UserId inválido.") return end
        if targetUserId == Config.OWNER_USER_ID then notify(admin, false, "O Dono principal está protegido.") return end

        local rank, loaded = loadRankByUserId(targetUserId)
        if not loaded then notify(admin, false, "Não foi possível verificar o cargo do alvo.") return end
        if levelOfRank(rank) >= currentLevel(admin) then
            notify(admin, false, "O alvo possui cargo igual ou superior ao seu.") return
        end
        if not removeBan(targetUserId) then notify(admin, false, "Falha ao remover o banimento.") return end
        addLog(admin, "UNBAN", "UserId " .. targetUserId, "Banimento removido", targetUserId)
        notify(admin, true, "Banimento removido do UserId " .. targetUserId .. ".")
        return
    end

    -- ========================================================
    -- COMANDOS DE JOGO
    -- Todos são validados novamente pelo servidor.
    -- ========================================================
    if actionName == "Command" then
        local command = payload.command

        if type(command) ~= "string" then
            notify(admin, false, "Comando inválido.")
            return
        end

        local permissions = {
            Fly = 3,
            Unfly = 3,
            Heal = 3,
            Respawn = 3,
            Bring = 4,
            Freeze = 4,
            Unfreeze = 4,
            Kill = 4,

            FlyAll = 5,
            UnflyAll = 5,
            HealAll = 5,
            RespawnAll = 5,
            BringAll = 5,
            KillAll = 5,
        }

        local minimum = permissions[command]

        if not minimum then
            notify(admin, false, "Comando não reconhecido.")
            return
        end

        local allowed, permissionError = requireLevel(admin, minimum)
        if not allowed then
            notify(admin, false, permissionError)
            return
        end

        local function characterParts(target)
            local character = target.Character
            if not character then
                return nil, nil
            end

            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local root = character:FindFirstChild("HumanoidRootPart")
            return humanoid, root
        end

        local function runSingle(target, singleCommand)
            -- Comandos de utilidade podem ser usados no próprio administrador.
            -- Isso NÃO afeta punições/cargos: essas continuam bloqueando autoação.
            local isSelf = target == admin
            local selfAllowed = {
                Fly = true,
                Unfly = true,
                Heal = true,
                Respawn = true,
                Freeze = true,
                Unfreeze = true,
                Kill = true,
            }

            if isSelf then
                if not selfAllowed[singleCommand] then
                    return false, "Esse comando não pode ser usado em você mesmo."
                end
            else
                local hierarchy, hierarchyError = canActOn(admin, target)
                if not hierarchy then
                    return false, hierarchyError
                end
            end

            local humanoid, root = characterParts(target)

            if singleCommand == "Fly" then
                -- Fonte de verdade server-side para o anticheat.
                FlyAuth.Grant(target, "AdminCommand", admin.UserId)
                target:SetAttribute("AdminFlying", true)
                Action:FireClient(target, "FlyState", {
                    enabled = true,
                    speed = Config.FlySpeed,
                })
                return true

            elseif singleCommand == "Unfly" then
                FlyAuth.Revoke(target)
                target:SetAttribute("AdminFlying", false)
                Action:FireClient(target, "FlyState", {
                    enabled = false,
                })
                return true

            elseif singleCommand == "Heal" then
                if not humanoid then
                    return false, "Personagem do jogador não está disponível."
                end
                humanoid.Health = humanoid.MaxHealth
                return true

            elseif singleCommand == "Kill" then
                if not humanoid then
                    return false, "Personagem do jogador não está disponível."
                end
                humanoid.Health = 0
                return true

            elseif singleCommand == "Respawn" then
                FlyAuth.GrantGrace(target, ServerConfig.AntiCheat.AdminTeleportGraceSeconds or 5, "AdminRespawn")
                pcall(function()
                    target:LoadCharacter()
                end)
                return true

            elseif singleCommand == "Bring" then
                local _, adminRoot = characterParts(admin)
                if not root or not adminRoot then
                    return false, "Personagem não está disponível."
                end

                FlyAuth.GrantGrace(target, ServerConfig.AntiCheat.AdminTeleportGraceSeconds or 5, "AdminBring")
                root.CFrame = adminRoot.CFrame * CFrame.new(3, 0, 0)
                return true

            elseif singleCommand == "Freeze" then
                if not root then
                    return false, "Personagem do jogador não está disponível."
                end
                root.Anchored = true
                target:SetAttribute("AdminFrozen", true)
                return true

            elseif singleCommand == "Unfreeze" then
                if not root then
                    return false, "Personagem do jogador não está disponível."
                end
                root.Anchored = false
                target:SetAttribute("AdminFrozen", false)
                return true
            end

            return false, "Comando inválido."
        end

        local allMap = {
            FlyAll = "Fly",
            UnflyAll = "Unfly",
            HealAll = "Heal",
            RespawnAll = "Respawn",
            BringAll = "Bring",
            KillAll = "Kill",
        }

        local mappedAll = allMap[command]

        if mappedAll then
            local affected = 0

            for _, target in ipairs(Players:GetPlayers()) do
                if target ~= admin then
                    local hierarchy = canActOn(admin, target)
                    if hierarchy then
                        local ok = runSingle(target, mappedAll)
                        if ok then
                            affected += 1
                        end
                    end
                end
            end

            addLog(
                admin,
                "COMANDO",
                "ALL",
                command .. " • " .. tostring(affected) .. " jogador(es)"
            )

            notify(
                admin,
                true,
                command .. " aplicado em " .. tostring(affected) .. " jogador(es)."
            )

            refreshAll("Players", admin.UserId)
            return
        end

        local target, targetError = onlineTarget(payload)
        if not target then
            notify(admin, false, targetError)
            return
        end

        local ok, commandError = runSingle(target, command)

        if not ok then
            notify(admin, false, commandError)
            return
        end

        addLog(
            admin,
            "COMANDO",
            target.Name,
            command,
            target.UserId
        )

        notify(
            admin,
            true,
            command .. " aplicado em " .. target.Name .. "."
        )

        refreshAll("Players", target.UserId)
        return
    end

    -- ALTERAÇÃO DE CARGO
    if actionName == "SetRank" then
        local ok, err = requireLevel(admin, 5)
        if not ok then notify(admin, false, err) return end
        local target, targetErr = onlineTarget(payload)
        if not target then notify(admin, false, targetErr) return end
        if target == admin then notify(admin, false, "Você não pode alterar o próprio cargo.") return end
        if target.UserId == Config.OWNER_USER_ID then notify(admin, false, "O Dono principal está protegido.") return end
        if target.UserId == Config.SUB_OWNER_USER_ID then notify(admin, false, "O Sub-Dono principal possui cargo fixo.") return end
        if target:GetAttribute("AdminRankLoaded") ~= true then notify(admin, false, "O cargo do alvo ainda está carregando.") return end

        local newRank = payload.newRank
        if not rankExists(newRank) then notify(admin, false, "Cargo inexistente.") return end

        local adminLevel = currentLevel(admin)
        local targetLevel = currentLevel(target)
        local newLevel = levelOfRank(newRank)

        if targetLevel >= adminLevel then
            notify(admin, false, "Você não pode alterar alguém de cargo igual ou superior.") return
        end
        if newRank == "Dono" then
            if not Config.ALLOW_MULTIPLE_OWNERS then
                notify(admin, false, "Apenas o OWNER_USER_ID pode ser Dono.") return
            end
            if adminLevel < 6 then
                notify(admin, false, "Somente Dono pode criar outro Dono.") return
            end
        elseif newLevel >= adminLevel then
            notify(admin, false, "Você não pode atribuir cargo igual ou superior ao seu.") return
        end

        local oldRank = currentRank(target)
        local saved, saveErr = saveRank(target.UserId, newRank)
        if not saved then notify(admin, false, saveErr) return end
        addLog(admin, "CARGO", target.Name, oldRank .. " → " .. newRank, target.UserId)
        notify(admin, true, "Cargo de " .. target.Name .. " atualizado para " .. newRank .. ".")
        refreshAll("Ranks", target.UserId)
        return
    end

    notify(admin, false, "Ação desconhecida.")
end)

-- ============================================================
-- CARGOS FIXOS / PLAYERADDED
-- ============================================================
local function setupPlayer(player)
    player:SetAttribute("AdminMuted", false)
    player:SetAttribute("AdminFlying", false)
    player:SetAttribute("AdminFlyAuthorized", false)
    player:SetAttribute("AdminFrozen", false)

    if player.UserId == Config.OWNER_USER_ID then
        player:SetAttribute("AdminRank", "Dono")
        player:SetAttribute("AdminRankLoaded", true)
        moveToSupportIfAdmin(player, "Dono")

    elseif player.UserId == Config.SUB_OWNER_USER_ID then
        player:SetAttribute("AdminRank", "Sub-Dono")
        player:SetAttribute("AdminRankLoaded", true)
        moveToSupportIfAdmin(player, "Sub-Dono")

    else
        player:SetAttribute("AdminRank", "Nenhum")
        player:SetAttribute("AdminRankLoaded", false)
    end

    task.spawn(function()
        local ban = getBan(player.UserId)

        if ban and player.Parent == Players then
            kickForBan(player, ban)
            return
        end

        if player.Parent ~= Players then
            return
        end

        loadPlayerRank(player)

        if player.Parent == Players then
            moveToSupportIfAdmin(player, currentRank(player))
            ExternalLogger.PushPlayerEvent("JOIN", player)
            refreshAll("Players", player.UserId)
        end
    end)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
    ExternalLogger.PushPlayerEvent("LEAVE", player)
    FlyAuth.Revoke(player)
    Muted[player.UserId] = nil
    LastCall[player.UserId] = nil
    refreshAll("Players", player.UserId)
end)

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Teams.ChildAdded:Connect(function(child)
    if child.Name == "Suporte" then
        for _, player in ipairs(Players:GetPlayers()) do
            if currentLevel(player) > 0 then
                moveToSupportIfAdmin(player, currentRank(player))
            end
        end
    end
end)

-- ============================================================
-- ANTICHEAT SERVER-SIDE
-- Fly legítimo vem de EBFlyAuthorization; atributo do cliente não libera nada.
-- ============================================================
AntiCheat.Start({
    OnSuspicious = function(player, evidence)
        ExternalLogger.PushAntiCheat(
            "ANTICHEAT_SUSPECT",
            player,
            evidence,
            "Movimento aéreo suspeito. Monitoramento reforçado; ainda sem punição."
        )
    end,

    OnConfirmed = function(player, evidence)
        if player.Parent ~= Players then
            return
        end

        ExternalLogger.PushAntiCheat(
            "ANTICHEAT_BAN",
            player,
            evidence,
            ServerConfig.AntiCheat.AutoBan and "Fly Hack confirmado sem autorização." or "Fly Hack confirmado; AutoBan desativado."
        )

        if ServerConfig.AntiCheat.AutoBan ~= true then
            return
        end

        local ban = {
            Permanent = true,
            ExpiresAt = 0,
            Reason = "AntiCheat: Fly não autorizado",
            AdminName = "EB AntiCheat",
            AdminUserId = 0,
            At = os.time(),
        }

        if saveBan(player.UserId, ban) then
            local evidenceText = string.format(
                "FLY • score=%s • hover=%ss • chão=%s • vY=%s • hSpeed=%s",
                tostring(evidence.score),
                tostring(evidence.hoverSeconds),
                tostring(evidence.groundDistance),
                tostring(evidence.velocityY),
                tostring(evidence.horizontalSpeed)
            )
            addLog(nil, "ANTICHEAT_BAN", player.Name, evidenceText, player.UserId)
            task.delay(0.15, function()
                if player.Parent == Players then
                    player:Kick("🛡️ EB ANTICHEAT\n\nFly não autorizado detectado.\nBanimento automático aplicado.")
                end
            end)
        else
            warn("[EB AntiCheat] Detecção confirmada, mas o banimento não pôde ser salvo para", player.Name)
        end
    end,
})

print("[EB Admin] Carregado. Dono:", Config.OWNER_USER_ID, "| Sub-Dono:", Config.SUB_OWNER_USER_ID, "| Logs/AntiCheat: V7")
]==]

-- ============================================================
-- GRAPHICS GUI + CLIENT
-- ============================================================
local graphicsGui = make("ScreenGui", "GraphicsSystem", StarterGui)
graphicsGui.ResetOnSpawn = false
graphicsGui.DisplayOrder = 40
graphicsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local graphicsClient = make("LocalScript", "GraphicsClient", graphicsGui)
graphicsClient.Source = [==[
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Gui = script.Parent

local C = {
    Dark = Color3.fromRGB(12, 20, 14),
    Panel = Color3.fromRGB(20, 32, 22),
    Card = Color3.fromRGB(27, 42, 29),
    Olive = Color3.fromRGB(89, 119, 72),
    Light = Color3.fromRGB(169, 210, 138),
    Text = Color3.fromRGB(232, 238, 226),
    Muted = Color3.fromRGB(126, 143, 121),
    Black = Color3.fromRGB(4, 7, 5),
}

local function new(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local function round(obj, radius)
    new("UICorner", {CornerRadius = UDim.new(0, radius)}, obj)
end

local function outline(obj, color, thickness, transparency)
    new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    }, obj)
end

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MENU = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SNAP = TweenInfo.new(0.17, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ============================================================
-- BOTÃO DE GRÁFICOS
-- ============================================================
local Gear = new("TextButton", {
    Name = "GearButton",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 22, 0.5, 0),
    Size = UDim2.fromOffset(64, 64),
    BackgroundColor3 = Color3.fromRGB(125, 164, 102),
    BorderSizePixel = 0,
    Text = "⚙",
    TextColor3 = Color3.fromRGB(245, 245, 245),
    TextSize = 33,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
    ZIndex = 20,
}, Gui)
round(Gear, 15)
outline(Gear, C.Black, 3, 0)
new("UIGradient", {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(153, 192, 126)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(103, 140, 84)),
    }),
}, Gear)
local GearScale = new("UIScale", {Scale = 1}, Gear)

-- ============================================================
-- PAINEL GRÁFICO
-- ============================================================
local Panel = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, -650, 0.5, 0),
    Size = UDim2.fromScale(0.34, 0.58),
    BackgroundColor3 = C.Panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 10,
}, Gui)
round(Panel, 18)
outline(Panel, C.Olive, 1.5, 0.15)
new("UIGradient", {
    Rotation = 115,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 50, 36)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 21, 14)),
    }),
}, Panel)
new("UISizeConstraint", {MaxSize = Vector2.new(520, 620)}, Panel)
local PanelScale = new("UIScale", {Scale = 0.96}, Panel)

local Header = new("Frame", {
    Position = UDim2.fromScale(0.045, 0.04),
    Size = UDim2.fromScale(0.91, 0.14),
    BackgroundTransparency = 1,
    ZIndex = 15,
}, Panel)
new("TextLabel", {
    Size = UDim2.fromScale(1, 0.28),
    BackgroundTransparency = 1,
    Text = "EB // CONFIG   •   SISTEMA GRÁFICO",
    TextColor3 = C.Light,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, Header)
new("TextLabel", {
    Position = UDim2.fromScale(0, 0.28),
    Size = UDim2.fromScale(1, 0.46),
    BackgroundTransparency = 1,
    Text = "CONFIGURAÇÕES GRÁFICAS",
    TextColor3 = C.Text,
    TextSize = 19,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, Header)
new("TextLabel", {
    Position = UDim2.fromScale(0, 0.74),
    Size = UDim2.fromScale(1, 0.24),
    BackgroundTransparency = 1,
    Text = "AJUSTE LOCAL • PC / MOBILE",
    TextColor3 = C.Muted,
    TextSize = 9,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, Header)

-- Camuflagem discreta
local Camo = new("Frame", {Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, ZIndex = 11}, Panel)
for i, d in ipairs({
    {0.03,0.08,0.32,0.08,-12},{0.59,0.06,0.34,0.09,16},{0.12,0.44,0.27,0.08,12},
    {0.62,0.36,0.30,0.09,-13},{0.05,0.77,0.35,0.08,10},{0.61,0.81,0.30,0.07,-11}
}) do
    local p = new("Frame", {
        Name = "Patch"..i,
        Position = UDim2.fromScale(d[1],d[2]),
        Size = UDim2.fromScale(d[3],d[4]),
        Rotation = d[5],
        BackgroundColor3 = Color3.fromRGB(100,113,76),
        BackgroundTransparency = 0.93,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, Camo)
    round(p, 40)
end

-- ============================================================
-- SOMBRAS
-- ============================================================
local ShadowCard = new("Frame", {
    Position = UDim2.fromScale(0.045, 0.215),
    Size = UDim2.fromScale(0.91, 0.17),
    BackgroundColor3 = C.Card,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    ZIndex = 15,
}, Panel)
round(ShadowCard, 13)
outline(ShadowCard, C.Olive, 1, 0.4)
new("TextLabel", {
    Position = UDim2.fromScale(0.05, 0.16),
    Size = UDim2.fromScale(0.5, 0.32),
    BackgroundTransparency = 1,
    Text = "SOMBRAS",
    TextColor3 = C.Text,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, ShadowCard)
local ShadowStatus = new("TextLabel", {
    Position = UDim2.fromScale(0.05, 0.53),
    Size = UDim2.fromScale(0.45, 0.24),
    BackgroundTransparency = 1,
    Text = "ATIVADAS",
    TextColor3 = C.Light,
    TextSize = 10,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, ShadowCard)

-- Toggle pequeno e simétrico: 76x28, círculo 20, margem 4.
local ShadowToggle = new("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -18, 0.5, 0),
    Size = UDim2.fromOffset(76, 28),
    BackgroundColor3 = Color3.fromRGB(78,112,63),
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 17,
}, ShadowCard)
round(ShadowToggle, 30)
local ShadowKnob = new("Frame", {
    AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.new(1,-14,0.5,0),
    Size = UDim2.fromOffset(20,20),
    BackgroundColor3 = Color3.fromRGB(228,240,216),
    BorderSizePixel = 0,
    ZIndex = 18,
}, ShadowToggle)
round(ShadowKnob, 30)

-- ============================================================
-- QUALIDADE
-- ============================================================
local Quality = new("Frame", {
    Position = UDim2.fromScale(0.045, 0.41),
    Size = UDim2.fromScale(0.91, 0.43),
    BackgroundColor3 = C.Card,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    ZIndex = 15,
}, Panel)
round(Quality, 13)
outline(Quality, C.Olive, 1, 0.4)
new("TextLabel", {
    Position = UDim2.fromScale(0.05,0.07),
    Size = UDim2.fromScale(0.62,0.14),
    BackgroundTransparency = 1,
    Text = "QUALIDADE GRÁFICA",
    TextColor3 = C.Text,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, Quality)
local Selected = new("TextLabel", {
    AnchorPoint = Vector2.new(1,0),
    Position = UDim2.fromScale(0.95,0.07),
    Size = UDim2.fromScale(0.28,0.14),
    BackgroundTransparency = 1,
    Text = "ALTO",
    TextColor3 = C.Light,
    TextSize = 11,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 16,
}, Quality)

local Labels = {}
for _, d in ipairs({{"BAIXO",0.08,0},{"MÉDIO",0.50,0.5},{"ALTO",0.92,1}}) do
    Labels[d[1]] = new("TextButton", {
        AnchorPoint = Vector2.new(d[3],0.5),
        Position = UDim2.fromScale(d[2],0.36),
        Size = UDim2.fromScale(0.25,0.16),
        BackgroundTransparency = 1,
        Text = d[1],
        TextColor3 = C.Muted,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
        ZIndex = 17,
    }, Quality)
end

local Track = new("Frame", {
    AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.fromScale(0.5,0.56),
    Size = UDim2.fromScale(0.82,0.035),
    BackgroundColor3 = Color3.fromRGB(56,72,54),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 17,
}, Quality)
round(Track, 10)
local Fill = new("Frame", {
    Size = UDim2.fromScale(1,1),
    BackgroundColor3 = Color3.fromRGB(122,166,95),
    BorderSizePixel = 0,
    ZIndex = 18,
}, Track)
round(Fill, 10)
for _, x in ipairs({0,0.5,1}) do
    local m = new("Frame", {
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(x,0.5),
        Size = UDim2.fromOffset(8,8),
        BackgroundColor3 = Color3.fromRGB(148,177,125),
        BorderSizePixel = 0,
        ZIndex = 19,
    }, Track)
    round(m, 10)
end
local SliderKnob = new("Frame", {
    AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.fromScale(1,0.5),
    Size = UDim2.fromOffset(24,24),
    BackgroundColor3 = Color3.fromRGB(222,236,210),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 21,
}, Track)
round(SliderKnob, 30)
outline(SliderKnob, C.Olive, 2, 0)
local Description = new("TextLabel", {
    AnchorPoint = Vector2.new(0.5,0),
    Position = UDim2.fromScale(0.5,0.69),
    Size = UDim2.fromScale(0.86,0.20),
    BackgroundTransparency = 1,
    Text = "QUALIDADE MÁXIMA // EFEITOS ORIGINAIS",
    TextColor3 = C.Muted,
    TextSize = 9,
    Font = Enum.Font.GothamMedium,
    TextWrapped = true,
    ZIndex = 16,
}, Quality)
new("TextLabel", {
    Position = UDim2.fromScale(0.045,0.87),
    Size = UDim2.fromScale(0.91,0.07),
    BackgroundTransparency = 1,
    Text = "ALTERAÇÕES APLICADAS SOMENTE NESTE DISPOSITIVO",
    TextColor3 = Color3.fromRGB(83,105,81),
    TextSize = 8,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 16,
}, Panel)

-- ============================================================
-- MENU RESPONSIVO
-- ============================================================
local menuOpen = false
local openPos = UDim2.new(0,100,0.5,0)
local closedPos = UDim2.new(0,-650,0.5,0)
local cameraConn

local function responsive()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if camera.ViewportSize.X < 700 then
        Panel.Size = UDim2.fromScale(0.78,0.68)
        openPos = UDim2.new(0,76,0.5,0)
        Gear.Position = UDim2.new(0,10,0.5,0)
        Gear.Size = UDim2.fromOffset(56,56)
    else
        Panel.Size = UDim2.fromScale(0.34,0.58)
        openPos = UDim2.new(0,100,0.5,0)
        Gear.Position = UDim2.new(0,22,0.5,0)
        Gear.Size = UDim2.fromOffset(64,64)
    end
    Panel.Position = menuOpen and openPos or closedPos
end

local function hookCamera()
    if cameraConn then cameraConn:Disconnect() end
    local camera = Workspace.CurrentCamera
    if camera then cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive) end
    responsive()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

local function setMenu(state)
    menuOpen = state
    TweenService:Create(Panel, MENU, {Position = state and openPos or closedPos}):Play()
    TweenService:Create(PanelScale, MENU, {Scale = state and 1 or 0.96}):Play()
    TweenService:Create(GearScale, FAST, {Scale = state and 1.06 or 1}):Play()
end
Gear.Activated:Connect(function() setMenu(not menuOpen) end)
Gear.MouseEnter:Connect(function() TweenService:Create(GearScale, FAST, {Scale=1.06}):Play() end)
Gear.MouseLeave:Connect(function() TweenService:Create(GearScale, FAST, {Scale=menuOpen and 1.06 or 1}):Play() end)

-- ============================================================
-- OTIMIZAÇÃO GRÁFICA + RESTAURAÇÃO
-- ============================================================
local originalGlobalShadows = Lighting.GlobalShadows
local originals = setmetatable({}, {__mode="k"})
local heavy = {
    [Enum.Material.Neon]=true,[Enum.Material.Glass]=true,[Enum.Material.ForceField]=true,
    [Enum.Material.Marble]=true,[Enum.Material.Granite]=true,[Enum.Material.Ice]=true,[Enum.Material.Foil]=true,
}

local function safeGet(obj, prop)
    local ok, value = pcall(function() return obj[prop] end)
    return ok and value or nil
end
local function safeSet(obj, prop, value)
    pcall(function() obj[prop] = value end)
end
local function protectedPart(part)
    local a = part.Parent
    while a and a ~= Workspace do
        if a:IsA("Tool") then return true end
        if a:IsA("Model") and a:FindFirstChildOfClass("Humanoid") then return true end
        a = a.Parent
    end
    return false
end

local function cache(obj)
    if originals[obj] or obj:GetAttribute("GraphicsEssential") == true then return end
    if obj:IsA("ParticleEmitter") then
        originals[obj] = {Kind="Particle",Enabled=obj.Enabled,Rate=obj.Rate,LightEmission=obj.LightEmission,LightInfluence=obj.LightInfluence}
    elseif obj:IsA("Trail") or obj:IsA("Beam") then
        originals[obj] = {Kind=obj.ClassName,Enabled=obj.Enabled}
    elseif obj:IsA("BloomEffect") then
        originals[obj] = {Kind="Bloom",Enabled=obj.Enabled,Intensity=obj.Intensity,Size=obj.Size,Threshold=obj.Threshold}
    elseif obj:IsA("SunRaysEffect") then
        originals[obj] = {Kind="Sun",Enabled=obj.Enabled,Intensity=obj.Intensity,Spread=obj.Spread}
    elseif obj:IsA("DepthOfFieldEffect") then
        originals[obj] = {Kind="Depth",Enabled=obj.Enabled,FarIntensity=obj.FarIntensity,FocusDistance=obj.FocusDistance,InFocusRadius=obj.InFocusRadius,NearIntensity=obj.NearIntensity}
    elseif obj:IsA("BlurEffect") then
        originals[obj] = {Kind="Blur",Enabled=obj.Enabled,Size=obj.Size}
    elseif obj:IsA("BasePart") and obj.Anchored and not protectedPart(obj) then
        originals[obj] = {Kind="Part",Material=obj.Material,MaterialVariant=safeGet(obj,"MaterialVariant"),CastShadow=obj.CastShadow,Reflectance=obj.Reflectance}
    end
end

local count = 0
for _, obj in ipairs(Workspace:GetDescendants()) do
    cache(obj); count += 1
    if count % 800 == 0 then task.wait() end
end
for _, obj in ipairs(Lighting:GetDescendants()) do cache(obj) end

local function restore(obj, d)
    if not obj or not obj.Parent then return end
    if d.Kind == "Particle" then
        safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Rate",d.Rate); safeSet(obj,"LightEmission",d.LightEmission); safeSet(obj,"LightInfluence",d.LightInfluence)
    elseif d.Kind == "Trail" or d.Kind == "Beam" then safeSet(obj,"Enabled",d.Enabled)
    elseif d.Kind == "Bloom" then
        safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Intensity",d.Intensity); safeSet(obj,"Size",d.Size); safeSet(obj,"Threshold",d.Threshold)
    elseif d.Kind == "Sun" then
        safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Intensity",d.Intensity); safeSet(obj,"Spread",d.Spread)
    elseif d.Kind == "Depth" then
        safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"FarIntensity",d.FarIntensity); safeSet(obj,"FocusDistance",d.FocusDistance); safeSet(obj,"InFocusRadius",d.InFocusRadius); safeSet(obj,"NearIntensity",d.NearIntensity)
    elseif d.Kind == "Blur" then safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Size",d.Size)
    elseif d.Kind == "Part" then
        safeSet(obj,"Material",d.Material); safeSet(obj,"MaterialVariant",d.MaterialVariant); safeSet(obj,"CastShadow",d.CastShadow); safeSet(obj,"Reflectance",d.Reflectance)
    end
end

local currentLevel = 3
local shadowEnabled = originalGlobalShadows
local SHADOW_OFF = UDim2.new(0,14,0.5,0)
local SHADOW_ON = UDim2.new(1,-14,0.5,0)

local function shadowVisual(animated)
    ShadowStatus.Text = shadowEnabled and "ATIVADAS" or "DESATIVADAS"
    ShadowStatus.TextColor3 = shadowEnabled and C.Light or C.Muted
    local pos = shadowEnabled and SHADOW_ON or SHADOW_OFF
    local col = shadowEnabled and Color3.fromRGB(78,112,63) or Color3.fromRGB(57,65,57)
    if animated then
        TweenService:Create(ShadowKnob, FAST, {Position=pos}):Play()
        TweenService:Create(ShadowToggle, FAST, {BackgroundColor3=col}):Play()
    else
        ShadowKnob.Position = pos
        ShadowToggle.BackgroundColor3 = col
    end
end
local function setShadows(value, animated)
    shadowEnabled = value == true
    safeSet(Lighting,"GlobalShadows",shadowEnabled)
    shadowVisual(animated)
end
ShadowToggle.Activated:Connect(function() setShadows(not shadowEnabled,true) end)

local function applyObject(obj,d,level)
    if not obj or not obj.Parent then return end
    if level == 3 then restore(obj,d) return end
    if d.Kind == "Particle" then
        if level == 1 then safeSet(obj,"Enabled",false)
        else safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Rate",type(d.Rate)=="number" and d.Rate*0.55 or d.Rate) end
    elseif d.Kind == "Trail" or d.Kind == "Beam" then
        safeSet(obj,"Enabled",level == 1 and false or d.Enabled)
    elseif d.Kind == "Bloom" then
        if level == 1 then safeSet(obj,"Enabled",false)
        else safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Intensity",type(d.Intensity)=="number" and d.Intensity*0.65 or d.Intensity) end
    elseif d.Kind == "Sun" then
        if level == 1 then safeSet(obj,"Enabled",false)
        else safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Intensity",type(d.Intensity)=="number" and d.Intensity*0.55 or d.Intensity) end
    elseif d.Kind == "Depth" then safeSet(obj,"Enabled",false)
    elseif d.Kind == "Blur" then
        if level == 1 then safeSet(obj,"Enabled",false)
        else safeSet(obj,"Enabled",d.Enabled); safeSet(obj,"Size",type(d.Size)=="number" and d.Size*0.5 or d.Size) end
    elseif d.Kind == "Part" then
        if level == 1 then
            safeSet(obj,"CastShadow",false)
            if d.Material and heavy[d.Material] then
                safeSet(obj,"Material",Enum.Material.SmoothPlastic); safeSet(obj,"MaterialVariant",""); safeSet(obj,"Reflectance",0)
            end
        else
            safeSet(obj,"Material",d.Material); safeSet(obj,"MaterialVariant",d.MaterialVariant); safeSet(obj,"CastShadow",d.CastShadow); safeSet(obj,"Reflectance",d.Reflectance)
        end
    end
end

local info = {
    [1]={Name="BAIXO",Alpha=0,Desc="FPS PRIORITÁRIO // EFEITOS REDUZIDOS"},
    [2]={Name="MÉDIO",Alpha=0.5,Desc="EQUILÍBRIO // VISUAL + DESEMPENHO"},
    [3]={Name="ALTO",Alpha=1,Desc="QUALIDADE MÁXIMA // EFEITOS ORIGINAIS"},
}
local function labelVisual(level)
    for name,b in pairs(Labels) do b.TextColor3 = info[level].Name == name and C.Light or C.Muted end
end
local function sliderAlpha(alpha, animated)
    alpha = math.clamp(alpha,0,1)
    local pos = UDim2.fromScale(alpha,0.5)
    local size = UDim2.fromScale(alpha,1)
    if animated then
        TweenService:Create(SliderKnob,SNAP,{Position=pos}):Play(); TweenService:Create(Fill,SNAP,{Size=size}):Play()
    else SliderKnob.Position=pos; Fill.Size=size end
end
local function selectLevel(level, animated)
    level = math.clamp(level,1,3); currentLevel = level
    Selected.Text = info[level].Name; Description.Text = info[level].Desc; labelVisual(level); sliderAlpha(info[level].Alpha,animated)
    for obj,d in pairs(originals) do applyObject(obj,d,level) end
    if level == 1 then setShadows(false,true)
    elseif level == 2 then setShadows(true,true)
    else setShadows(originalGlobalShadows,true) end
end
Labels.BAIXO.Activated:Connect(function() selectLevel(1,true) end)
Labels["MÉDIO"].Activated:Connect(function() selectLevel(2,true) end)
Labels.ALTO.Activated:Connect(function() selectLevel(3,true) end)

-- Slider Mouse + Touch
local dragging, activeTouch, dragAlpha = false, nil, 1
local function alphaFromX(x)
    local w = Track.AbsoluteSize.X
    if w <= 0 then return dragAlpha end
    return math.clamp((x - Track.AbsolutePosition.X)/w,0,1)
end
local function preview(x)
    dragAlpha = alphaFromX(x); sliderAlpha(dragAlpha,false)
    local level = dragAlpha < 0.25 and 1 or (dragAlpha < 0.75 and 2 or 3)
    Selected.Text = info[level].Name; Description.Text = info[level].Desc; labelVisual(level)
end
local function begin(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging = true; activeTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil; preview(input.Position.X)
end
local function finish()
    if not dragging then return end
    dragging=false; activeTouch=nil
    selectLevel(dragAlpha < 0.25 and 1 or (dragAlpha < 0.75 and 2 or 3),true)
end
Track.InputBegan:Connect(begin); SliderKnob.InputBegan:Connect(begin)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if activeTouch then if input == activeTouch then preview(input.Position.X) end
    elseif input.UserInputType == Enum.UserInputType.MouseMovement then preview(input.Position.X) end
end)
UserInputService.InputEnded:Connect(function(input)
    if not dragging then return end
    if activeTouch then if input == activeTouch then finish() end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then finish() end
end)

local function register(obj)
    cache(obj)
    local d = originals[obj]
    if d then applyObject(obj,d,currentLevel) end
end
Workspace.DescendantAdded:Connect(function(obj) task.defer(register,obj) end)
Lighting.DescendantAdded:Connect(function(obj) task.defer(register,obj) end)

shadowVisual(false)
selectLevel(3,false)
setMenu(false)
]==]

-- ============================================================
-- ADMIN GUI + CLIENT
-- ============================================================
local adminGui = make("ScreenGui", "AdminSystemGui", StarterGui)
adminGui.ResetOnSpawn = false
adminGui.DisplayOrder = 60
adminGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local adminClient = make("LocalScript", "AdminClient", adminGui)
adminClient.Source = [==[
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Player = Players.LocalPlayer
local Gui = script.Parent
local Root = ReplicatedStorage:WaitForChild("EBAdminSystem")
local Action = Root:WaitForChild("Action")
local Query = Root:WaitForChild("Query")

local C = {
    Panel=Color3.fromRGB(18,29,20), Card=Color3.fromRGB(25,39,27), Card2=Color3.fromRGB(32,48,34),
    Olive=Color3.fromRGB(88,117,72), Green=Color3.fromRGB(153,211,121), Text=Color3.fromRGB(232,238,226),
    Muted=Color3.fromRGB(126,143,121), Danger=Color3.fromRGB(189,79,72), Warning=Color3.fromRGB(205,160,76),
    Black=Color3.fromRGB(4,7,5),
}
local FAST = TweenInfo.new(0.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local OPEN = TweenInfo.new(0.20,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

local function new(className, props, parent)
    local o=Instance.new(className); for k,v in pairs(props or {}) do o[k]=v end; o.Parent=parent; return o
end
local function round(o,r) new("UICorner",{CornerRadius=UDim.new(0,r)},o) end
local function stroke(o,c,t,tr) new("UIStroke",{Color=c,Thickness=t or 1,Transparency=tr or 0},o) end
local function hover(button,normal,over)
    button.MouseEnter:Connect(function() TweenService:Create(button,FAST,{BackgroundColor3=over}):Play() end)
    button.MouseLeave:Connect(function() TweenService:Create(button,FAST,{BackgroundColor3=normal}):Play() end)
end
local function clear(frame)
    for _,c in ipairs(frame:GetChildren()) do if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end end
end
local function serverQuery(name,payload)
    local ok,res=pcall(function() return Query:InvokeServer(name,payload) end)
    if not ok then return {success=false,message="Falha ao comunicar com o servidor."} end
    return type(res)=="table" and res or {success=false,message="Resposta inválida."}
end

local state={rank="Nenhum",level=0,players={},allowMultipleOwners=false}
local selectedId=nil
local selected=nil
local currentTab="JOGADORES"
local panelOpen=false

-- ============================================================
-- NOTIFICAÇÕES
-- ============================================================
local Notices=new("Frame",{
    AnchorPoint=Vector2.new(1,0),Position=UDim2.fromScale(0.985,0.11),Size=UDim2.fromOffset(330,260),
    BackgroundTransparency=1,ZIndex=100,
},Gui)
new("UIListLayout",{Padding=UDim.new(0,7),HorizontalAlignment=Enum.HorizontalAlignment.Right,SortOrder=Enum.SortOrder.LayoutOrder},Notices)
local function notify(ok,text)
    local card=new("Frame",{Size=UDim2.new(1,0,0,52),BackgroundColor3=ok and Color3.fromRGB(39,69,42) or Color3.fromRGB(78,43,39),BorderSizePixel=0,ZIndex=101},Notices)
    round(card,11); stroke(card,ok and C.Green or C.Danger,1,0.25)
    local label=new("TextLabel",{Position=UDim2.fromScale(0.04,0.1),Size=UDim2.fromScale(0.92,0.8),BackgroundTransparency=1,Text=(ok and "✓  " or "✕  ")..tostring(text),TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamMedium,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=102},card)
    task.delay(3,function()
        if not card.Parent then return end
        TweenService:Create(card,FAST,{BackgroundTransparency=1}):Play(); TweenService:Create(label,FAST,{TextTransparency=1}):Play()
        task.wait(0.16); if card.Parent then card:Destroy() end
    end)
end

-- ============================================================
-- BOTÃO ADMIN
-- ============================================================
local AdminButton=new("TextButton",{
    AnchorPoint=Vector2.new(1,1),Position=UDim2.fromScale(0.98,0.95),Size=UDim2.fromOffset(184,48),
    BackgroundColor3=C.Card2,BorderSizePixel=0,Text="🛡  ADMIN PAINEL",TextColor3=C.Text,TextSize=13,
    Font=Enum.Font.GothamBold,AutoButtonColor=false,Visible=false,ZIndex=30,
},Gui)
round(AdminButton,13); stroke(AdminButton,C.Olive,1.5,0.12); hover(AdminButton,C.Card2,Color3.fromRGB(55,78,55))

-- ============================================================
-- PAINEL PRINCIPAL
-- ============================================================
local Panel=new("Frame",{
    AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromScale(0.72,0.72),
    BackgroundColor3=C.Panel,BorderSizePixel=0,Visible=false,ClipsDescendants=true,ZIndex=40,
},Gui)
round(Panel,18); stroke(Panel,C.Olive,1.5,0.12); new("UISizeConstraint",{MaxSize=Vector2.new(940,670)},Panel)
local PanelScale=new("UIScale",{Scale=0.94},Panel)

local Header=new("Frame",{Size=UDim2.fromScale(1,0.115),BackgroundColor3=Color3.fromRGB(21,34,23),BorderSizePixel=0,Active=true,ZIndex=42},Panel)
new("TextLabel",{Position=UDim2.fromScale(0.025,0.16),Size=UDim2.fromScale(0.52,0.68),BackgroundTransparency=1,Text="🛡  ADMINISTRAÇÃO",TextColor3=C.Text,TextSize=18,Font=Enum.Font.GothamBlack,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=43},Header)
local RankLabel=new("TextLabel",{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.fromScale(0.91,0.5),Size=UDim2.fromScale(0.25,0.55),BackgroundTransparency=1,Text="● SEM CARGO",TextColor3=C.Muted,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,ZIndex=43},Header)
local Close=new("TextButton",{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.fromScale(0.978,0.5),Size=UDim2.fromOffset(34,34),BackgroundColor3=Color3.fromRGB(53,61,53),BorderSizePixel=0,Text="×",TextColor3=C.Text,TextSize=22,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=44},Header)
round(Close,10); hover(Close,Color3.fromRGB(53,61,53),Color3.fromRGB(84,61,57))

-- ============================================================
-- JANELA ARRASTÁVEL (PC + TOUCH)
-- Segure o cabeçalho e mova o painel como uma janela.
-- A posição é limitada para não perder completamente a janela fora da tela.
-- ============================================================
local draggingPanel = false
local dragInput = nil
local dragStart = nil
local dragStartCenter = nil

local function panelCenterOnScreen()
    return Vector2.new(
        Panel.AbsolutePosition.X + Panel.AbsoluteSize.X * 0.5,
        Panel.AbsolutePosition.Y + Panel.AbsoluteSize.Y * 0.5
    )
end

local function clampPanelCenter(center)
    local camera = Workspace.CurrentCamera
    if not camera then
        return center
    end

    local viewport = camera.ViewportSize
    -- Mantém pelo menos uma parte grande do cabeçalho acessível.
    local visibleX = math.min(130, math.max(70, Panel.AbsoluteSize.X * 0.30))
    local visibleY = math.min(55, math.max(35, Header.AbsoluteSize.Y * 0.80))

    return Vector2.new(
        math.clamp(center.X, visibleX, math.max(visibleX, viewport.X - visibleX)),
        math.clamp(center.Y, visibleY, math.max(visibleY, viewport.Y - visibleY))
    )
end

local function updatePanelDrag(input)
    if not draggingPanel or not dragStart or not dragStartCenter then
        return
    end

    local delta = input.Position - dragStart
    local center = clampPanelCenter(dragStartCenter + Vector2.new(delta.X, delta.Y))
    Panel.Position = UDim2.fromOffset(center.X, center.Y)
end

Header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    -- Não inicia arrasto ao clicar exatamente sobre o botão de fechar.
    local p = input.Position
    local closePos = Close.AbsolutePosition
    local closeSize = Close.AbsoluteSize
    if p.X >= closePos.X and p.X <= closePos.X + closeSize.X
        and p.Y >= closePos.Y and p.Y <= closePos.Y + closeSize.Y then
        return
    end

    draggingPanel = true
    dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
    dragStart = input.Position
    dragStartCenter = panelCenterOnScreen()
end)

UserInputService.InputChanged:Connect(function(input)
    if not draggingPanel then
        return
    end

    if dragInput then
        if input == dragInput then
            updatePanelDrag(input)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseMovement then
        updatePanelDrag(input)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not draggingPanel then
        return
    end

    if (dragInput and input == dragInput)
        or (not dragInput and input.UserInputType == Enum.UserInputType.MouseButton1) then
        draggingPanel = false
        dragInput = nil
        dragStart = nil
        dragStartCenter = nil
    end
end)

local Sidebar=new("Frame",{Position=UDim2.fromScale(0,0.115),Size=UDim2.fromScale(0.23,0.815),BackgroundColor3=Color3.fromRGB(15,25,17),BorderSizePixel=0,ZIndex=42},Panel)
new("UIListLayout",{Padding=UDim.new(0,7),HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder},Sidebar)
new("UIPadding",{PaddingTop=UDim.new(0,16),PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)},Sidebar)
local Content=new("Frame",{Position=UDim2.fromScale(0.255,0.14),Size=UDim2.fromScale(0.72,0.74),BackgroundTransparency=1,ZIndex=43},Panel)
new("TextLabel",{Position=UDim2.fromScale(0.23,0.93),Size=UDim2.fromScale(0.77,0.07),BackgroundTransparency=1,Text="EB // SISTEMA ADMINISTRATIVO • SEGURANÇA NO SERVIDOR",TextColor3=Color3.fromRGB(79,101,77),TextSize=8,Font=Enum.Font.GothamMedium,ZIndex=42},Panel)

-- ============================================================
-- CONFIRMAÇÃO
-- ============================================================
local Overlay=new("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.Black,BackgroundTransparency=0.28,Visible=false,ZIndex=200},Gui)
local Confirm=new("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromScale(0.34,0.28),BackgroundColor3=C.Card,BorderSizePixel=0,ZIndex=201},Overlay)
round(Confirm,16); stroke(Confirm,C.Olive,1.5,0.15); new("UISizeConstraint",{MinSize=Vector2.new(300,190),MaxSize=Vector2.new(470,260)},Confirm)
local ConfirmTitle=new("TextLabel",{Position=UDim2.fromScale(0.06,0.08),Size=UDim2.fromScale(0.88,0.18),BackgroundTransparency=1,Text="TEM CERTEZA?",TextColor3=C.Text,TextSize=17,Font=Enum.Font.GothamBlack,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=202},Confirm)
local ConfirmBody=new("TextLabel",{Position=UDim2.fromScale(0.06,0.29),Size=UDim2.fromScale(0.88,0.32),BackgroundTransparency=1,Text="",TextColor3=C.Muted,TextSize=11,Font=Enum.Font.GothamMedium,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=202},Confirm)
local Cancel=new("TextButton",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0.06,0.91),Size=UDim2.fromScale(0.42,0.2),BackgroundColor3=Color3.fromRGB(54,62,54),BorderSizePixel=0,Text="CANCELAR",TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=202},Confirm)
local Accept=new("TextButton",{AnchorPoint=Vector2.new(1,1),Position=UDim2.fromScale(0.94,0.91),Size=UDim2.fromScale(0.42,0.2),BackgroundColor3=C.Danger,BorderSizePixel=0,Text="CONFIRMAR",TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=202},Confirm)
round(Cancel,10); round(Accept,10); hover(Cancel,Cancel.BackgroundColor3,Color3.fromRGB(68,76,68)); hover(Accept,Accept.BackgroundColor3,Color3.fromRGB(211,91,83))
local confirmCallback=nil
local function ask(title,body,callback) ConfirmTitle.Text=title; ConfirmBody.Text=body; confirmCallback=callback; Overlay.Visible=true end
Cancel.Activated:Connect(function() confirmCallback=nil; Overlay.Visible=false end)
Accept.Activated:Connect(function() local cb=confirmCallback; confirmCallback=nil; Overlay.Visible=false; if cb then cb() end end)

-- ============================================================
-- COMPONENTES
-- ============================================================
local function field(parent,placeholder)
    local b=new("TextBox",{Size=UDim2.new(1,0,0,40),BackgroundColor3=Color3.fromRGB(28,42,30),BorderSizePixel=0,Text="",PlaceholderText=placeholder,PlaceholderColor3=Color3.fromRGB(100,119,96),TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamMedium,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=45},parent)
    round(b,10); stroke(b,C.Olive,1,0.45); new("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},b); return b
end
local function actionButton(parent,text,color)
    local b=new("TextButton",{Size=UDim2.new(1,0,0,38),BackgroundColor3=color or Color3.fromRGB(47,69,48),BorderSizePixel=0,Text=text,TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=45},parent)
    round(b,10); hover(b,b.BackgroundColor3,b.BackgroundColor3:Lerp(Color3.new(1,1,1),0.08)); return b
end
local function title(text)
    return new("TextLabel",{Position=UDim2.fromScale(0,0),Size=UDim2.fromScale(1,0.07),BackgroundTransparency=1,Text=text,TextColor3=C.Text,TextSize=15,Font=Enum.Font.GothamBlack,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=44},Content)
end
local function selectedText()
    if not selected then return "Nenhum jogador selecionado." end
    return selected.DisplayName.."\n@"..selected.Name.."\nUserId: "..selected.UserId.."\nCargo: "..(selected.RankLoaded==false and "Carregando..." or selected.Rank)
end

-- ============================================================
-- TABS
-- ============================================================
local Tabs={}
local function tab(name,order)
    local b=new("TextButton",{LayoutOrder=order,Size=UDim2.new(1,0,0,42),BackgroundColor3=Color3.fromRGB(24,37,26),BorderSizePixel=0,Text=name,TextColor3=C.Muted,TextSize=11,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=43},Sidebar)
    round(b,10); hover(b,Color3.fromRGB(24,37,26),Color3.fromRGB(39,57,41)); Tabs[name]=b; return b
end
tab("JOGADORES",1); tab("PUNIÇÕES",2); tab("COMANDOS",3); tab("CARGOS",4); tab("REGISTROS",5)

local function updateTabVisibility()
    Tabs.JOGADORES.Visible=true
    Tabs["PUNIÇÕES"].Visible=state.level>=1
    Tabs.COMANDOS.Visible=state.level>=3
    Tabs.CARGOS.Visible=state.level>=5
    Tabs.REGISTROS.Visible=state.level>=4
end
local function activeTab()
    for name,b in pairs(Tabs) do
        local on=name==currentTab
        b.BackgroundColor3=on and Color3.fromRGB(53,75,54) or Color3.fromRGB(24,37,26)
        b.TextColor3=on and C.Text or C.Muted
    end
end

local renderCurrent
local function findSelected()
    selected=nil
    if not selectedId then return end
    for _,p in ipairs(state.players or {}) do if p.UserId==selectedId then selected=p break end end
    if not selected then selectedId=nil end
end

-- ============================================================
-- ABA JOGADORES
-- ============================================================
local function renderPlayers()
    clear(Content); title("JOGADORES ONLINE")
    local Search=field(Content,"Pesquisar jogador..."); Search.Position=UDim2.fromScale(0,0.09); Search.Size=UDim2.fromScale(1,0.075)
    local List=new("ScrollingFrame",{Position=UDim2.fromScale(0,0.19),Size=UDim2.fromScale(0.56,0.78),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.Olive,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=44},Content)
    new("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},List)
    local Details=new("TextLabel",{Position=UDim2.fromScale(0.60,0.19),Size=UDim2.fromScale(0.40,0.38),BackgroundColor3=Color3.fromRGB(24,37,26),BorderSizePixel=0,Text=selectedText(),TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamMedium,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=44},Content)
    round(Details,12); stroke(Details,C.Olive,1,0.45); new("UIPadding",{PaddingTop=UDim.new(0,14),PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14)},Details)
    new("TextLabel",{Position=UDim2.fromScale(0.60,0.61),Size=UDim2.fromScale(0.40,0.18),BackgroundTransparency=1,Text="Selecione um jogador e use PUNIÇÕES ou CARGOS.",TextColor3=C.Muted,TextSize=9,Font=Enum.Font.GothamMedium,TextWrapped=true,ZIndex=44},Content)

    local function rebuild()
        for _,child in ipairs(List:GetChildren()) do if not child:IsA("UIListLayout") then child:Destroy() end end
        local q=(Search.Text or ""):lower()
        for _,p in ipairs(state.players or {}) do
            local hay=(p.Name.." "..p.DisplayName):lower()
            if q=="" or hay:find(q,1,true) then
                local on=selectedId==p.UserId
                local card=new("TextButton",{Size=UDim2.new(1,-4,0,62),BackgroundColor3=on and Color3.fromRGB(55,78,56) or Color3.fromRGB(26,40,28),BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=45},List)
                round(card,11); stroke(card,on and C.Green or C.Olive,1,on and 0.15 or 0.55)
                new("TextLabel",{Position=UDim2.fromScale(0.04,0.12),Size=UDim2.fromScale(0.70,0.34),BackgroundTransparency=1,Text="👤  "..p.DisplayName,TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=46},card)
                new("TextLabel",{Position=UDim2.fromScale(0.04,0.50),Size=UDim2.fromScale(0.70,0.28),BackgroundTransparency=1,Text="@"..p.Name.." • "..(p.RankLoaded==false and "Carregando..." or p.Rank),TextColor3=C.Muted,TextSize=9,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=46},card)
                new("TextLabel",{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.fromScale(0.96,0.5),Size=UDim2.fromScale(0.20,0.34),BackgroundTransparency=1,Text=p.Muted and "MUTADO" or "ONLINE",TextColor3=p.Muted and C.Warning or C.Green,TextSize=9,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,ZIndex=46},card)
                card.Activated:Connect(function() selectedId=p.UserId; selected=p; Details.Text=selectedText(); rebuild() end)
            end
        end
    end
    Search:GetPropertyChangedSignal("Text"):Connect(rebuild); rebuild()
end

-- ============================================================
-- ABA PUNIÇÕES
-- ============================================================
local durations={{600,"10 minutos"},{1800,"30 minutos"},{3600,"1 hora"},{21600,"6 horas"},{43200,"12 horas"},{86400,"1 dia"},{259200,"3 dias"},{604800,"7 dias"}}
local durationIndex=1
local function renderPunishments()
    clear(Content)

    local Scroll = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = C.Olive,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 44,
    }, Content)

    new("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 8),
    }, Scroll)

    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, Scroll)

    new("TextLabel", {
        LayoutOrder = 1,
        Size = UDim2.new(1, -6, 0, 34),
        BackgroundTransparency = 1,
        Text = "PUNIÇÕES",
        TextColor3 = C.Text,
        TextSize = 15,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 45,
    }, Scroll)

    local Info = new("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, -6, 0, 84),
        BackgroundColor3 = Color3.fromRGB(24,37,26),
        BorderSizePixel = 0,
        Text = selectedText(),
        TextColor3 = C.Text,
        TextSize = 10,
        Font = Enum.Font.GothamMedium,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 45,
    }, Scroll)
    round(Info, 11)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, Info)

    local Reason = field(
        Scroll,
        "Motivo obrigatório para Warn / Kick / TempBan / Ban..."
    )
    Reason.LayoutOrder = 3
    Reason.Size = UDim2.new(1, -6, 0, 42)

    local function hasTarget()
        if not selected then
            notify(false, "Selecione um jogador primeiro.")
            return false
        end
        return true
    end

    local function hasReason()
        local t = (Reason.Text or ""):match("^%s*(.-)%s*$") or ""
        if #t < 3 then
            notify(false, "Informe um motivo antes de continuar.")
            return false
        end
        return true
    end

    local order = 10

    if state.level >= 1 then
        local b = actionButton(
            Scroll,
            "ADVERTIR",
            Color3.fromRGB(112,89,47)
        )
        b.LayoutOrder = order
        order += 1

        b.Activated:Connect(function()
            if hasTarget() and hasReason() then
                Action:FireServer("Warn", {
                    targetUserId = selected.UserId,
                    reason = Reason.Text,
                })
            end
        end)
    end

    if state.level >= 2 then
        local kick = actionButton(
            Scroll,
            "EXPULSAR",
            Color3.fromRGB(126,69,54)
        )
        kick.LayoutOrder = order
        order += 1

        kick.Activated:Connect(function()
            if not (hasTarget() and hasReason()) then
                return
            end

            ask(
                "CONFIRMAR KICK",
                "Expulsar " .. selected.Name .. "?\nMotivo: " .. Reason.Text,
                function()
                    Action:FireServer("Kick", {
                        targetUserId = selected.UserId,
                        reason = Reason.Text,
                    })
                end
            )
        end)

        local mute = actionButton(
            Scroll,
            "MUTAR CHAT",
            Color3.fromRGB(55,75,79)
        )
        mute.LayoutOrder = order
        order += 1

        mute.Activated:Connect(function()
            if hasTarget() then
                Action:FireServer("Mute", {
                    targetUserId = selected.UserId,
                })
            end
        end)

        local unmute = actionButton(
            Scroll,
            "DESMUTAR CHAT",
            Color3.fromRGB(48,78,61)
        )
        unmute.LayoutOrder = order
        order += 1

        unmute.Activated:Connect(function()
            if hasTarget() then
                Action:FireServer("Unmute", {
                    targetUserId = selected.UserId,
                })
            end
        end)
    end

    if state.level >= 3 then
        local durationButton = actionButton(
            Scroll,
            "DURAÇÃO: " .. durations[durationIndex][2],
            Color3.fromRGB(55,66,49)
        )
        durationButton.LayoutOrder = order
        order += 1

        durationButton.Activated:Connect(function()
            durationIndex = durationIndex % #durations + 1
            durationButton.Text =
                "DURAÇÃO: " .. durations[durationIndex][2]
        end)

        local temp = actionButton(
            Scroll,
            "TEMPBAN",
            Color3.fromRGB(139,83,49)
        )
        temp.LayoutOrder = order
        order += 1

        temp.Activated:Connect(function()
            if not (hasTarget() and hasReason()) then
                return
            end

            local choice = durations[durationIndex]

            ask(
                "CONFIRMAR TEMPBAN",
                "Banir "
                    .. selected.Name
                    .. " por "
                    .. choice[2]
                    .. "?\nMotivo: "
                    .. Reason.Text,
                function()
                    Action:FireServer("TempBan", {
                        targetUserId = selected.UserId,
                        reason = Reason.Text,
                        duration = choice[1],
                    })
                end
            )
        end)
    end

    if state.level >= 5 then
        local ban = actionButton(
            Scroll,
            "BAN PERMANENTE",
            C.Danger
        )
        ban.LayoutOrder = order
        order += 1

        ban.Activated:Connect(function()
            if not (hasTarget() and hasReason()) then
                return
            end

            ask(
                "CONFIRMAR BAN",
                "Banir "
                    .. selected.Name
                    .. " permanentemente?\nMotivo: "
                    .. Reason.Text,
                function()
                    Action:FireServer("Ban", {
                        targetUserId = selected.UserId,
                        reason = Reason.Text,
                    })
                end
            )
        end)
    end

    if state.level >= 3 then
        local sub = new("TextLabel", {
            LayoutOrder = order,
            Size = UDim2.new(1, -6, 0, 26),
            BackgroundTransparency = 1,
            Text = "DESBANIR POR USERID",
            TextColor3 = C.Muted,
            TextSize = 9,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 45,
        }, Scroll)
        order += 1

        local Offline = field(
            Scroll,
            "UserId para desbanir..."
        )
        Offline.LayoutOrder = order
        Offline.Size = UDim2.new(1, -6, 0, 42)
        order += 1

        local unban = actionButton(
            Scroll,
            "UNBAN",
            Color3.fromRGB(48,78,61)
        )
        unban.LayoutOrder = order
        order += 1

        unban.Activated:Connect(function()
            local id = tonumber(Offline.Text)

            if not id then
                notify(false, "Informe um UserId numérico.")
                return
            end

            ask(
                "REMOVER BAN",
                "Remover banimento do UserId " .. id .. "?",
                function()
                    Action:FireServer("Unban", {
                        targetUserId = id,
                    })
                end
            )
        end)
    end

    local spacer = new("Frame", {
        LayoutOrder = 999,
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        ZIndex = 44,
    }, Scroll)
end

-- ============================================================
-- ABA COMANDOS
-- ============================================================
local function renderCommands()
    clear(Content)

    local Scroll = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = C.Olive,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 44,
    }, Content)

    new("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 18),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 8),
    }, Scroll)

    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, Scroll)

    new("TextLabel", {
        LayoutOrder = 1,
        Size = UDim2.new(1, -6, 0, 34),
        BackgroundTransparency = 1,
        Text = "COMANDOS",
        TextColor3 = C.Text,
        TextSize = 15,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 45,
    }, Scroll)

    local Info = new("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, -6, 0, 84),
        BackgroundColor3 = Color3.fromRGB(24,37,26),
        BorderSizePixel = 0,
        Text = selectedText(),
        TextColor3 = C.Text,
        TextSize = 10,
        Font = Enum.Font.GothamMedium,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 45,
    }, Scroll)
    round(Info, 11)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, Info)

    new("TextLabel", {
        LayoutOrder = 3,
        Size = UDim2.new(1, -6, 0, 32),
        BackgroundTransparency = 1,
        Text = "COMANDOS EM MIM",
        TextColor3 = C.Green,
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 45,
    }, Scroll)

    local selfOrder = 4

    local function selfCommand(label, command, minimum, color, confirmText)
        if state.level < minimum then
            return
        end

        local b = actionButton(
            Scroll,
            label,
            color or Color3.fromRGB(47,69,48)
        )
        b.LayoutOrder = selfOrder
        selfOrder += 1

        b.Activated:Connect(function()
            local function run()
                Action:FireServer("Command", {
                    command = command,
                    targetUserId = Player.UserId,
                })
            end

            if confirmText then
                ask(
                    "CONFIRMAR COMANDO EM MIM",
                    confirmText,
                    run
                )
            else
                run()
            end
        end)
    end

    selfCommand(
        "✈ VOAR EU",
        "Fly",
        3,
        Color3.fromRGB(50,75,82)
    )

    selfCommand(
        "⏹ PARAR MEU VOO",
        "Unfly",
        3,
        Color3.fromRGB(49,67,72)
    )

    selfCommand(
        "❤ CURAR EU",
        "Heal",
        3,
        Color3.fromRGB(48,82,59)
    )

    selfCommand(
        "↻ RESPAWN EU",
        "Respawn",
        3,
        Color3.fromRGB(57,72,94),
        "Respawnar seu próprio personagem?"
    )

    if state.level >= 4 then
        selfCommand(
            "❄ CONGELAR EU",
            "Freeze",
            4,
            Color3.fromRGB(55,77,88)
        )

        selfCommand(
            "☀ DESCONGELAR EU",
            "Unfreeze",
            4,
            Color3.fromRGB(68,82,60)
        )

        selfCommand(
            "☠ KILL EU",
            "Kill",
            4,
            C.Danger,
            "Eliminar seu próprio personagem?"
        )
    end

    new("Frame", {
        LayoutOrder = 8,
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundTransparency = 1,
        ZIndex = 44,
    }, Scroll)

    new("TextLabel", {
        LayoutOrder = 9,
        Size = UDim2.new(1, -6, 0, 32),
        BackgroundTransparency = 1,
        Text = "COMANDOS NO JOGADOR SELECIONADO",
        TextColor3 = C.Muted,
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 45,
    }, Scroll)

    local function needTarget()
        if not selected then
            notify(false, "Selecione um jogador na aba JOGADORES.")
            return false
        end
        return true
    end

    local order = 20

    local function selectedCommand(label, command, minimum, color, confirmText)
        if state.level < minimum then
            return
        end

        local b = actionButton(
            Scroll,
            label,
            color or Color3.fromRGB(47,69,48)
        )
        b.LayoutOrder = order
        order += 1

        b.Activated:Connect(function()
            if not needTarget() then
                return
            end

            local function run()
                Action:FireServer("Command", {
                    command = command,
                    targetUserId = selected.UserId,
                })
            end

            if confirmText then
                ask(
                    "CONFIRMAR COMANDO",
                    confirmText .. "\nAlvo: " .. selected.Name,
                    run
                )
            else
                run()
            end
        end)
    end

    selectedCommand(
        "✈ VOAR",
        "Fly",
        3,
        Color3.fromRGB(50,75,82)
    )

    selectedCommand(
        "⏹ PARAR VOO",
        "Unfly",
        3,
        Color3.fromRGB(49,67,72)
    )

    selectedCommand(
        "❤ CURAR",
        "Heal",
        3,
        Color3.fromRGB(48,82,59)
    )

    selectedCommand(
        "↻ RESPAWN",
        "Respawn",
        3,
        Color3.fromRGB(57,72,94),
        "Respawnar o jogador?"
    )

    selectedCommand(
        "⇢ TRAZER ATÉ MIM",
        "Bring",
        4,
        Color3.fromRGB(73,68,48)
    )

    selectedCommand(
        "❄ CONGELAR",
        "Freeze",
        4,
        Color3.fromRGB(55,77,88)
    )

    selectedCommand(
        "☀ DESCONGELAR",
        "Unfreeze",
        4,
        Color3.fromRGB(68,82,60)
    )

    selectedCommand(
        "☠ KILL",
        "Kill",
        4,
        C.Danger,
        "Eliminar o personagem do jogador?"
    )

    if state.level >= 5 then
        new("TextLabel", {
            LayoutOrder = order,
            Size = UDim2.new(1, -6, 0, 34),
            BackgroundTransparency = 1,
            Text = "COMANDOS GLOBAIS • APENAS CARGOS INFERIORES",
            TextColor3 = C.Warning,
            TextSize = 9,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 45,
        }, Scroll)
        order += 1

        local function allCommand(label, command, color, confirmText)
            local b = actionButton(
                Scroll,
                label,
                color or Color3.fromRGB(55,73,50)
            )
            b.LayoutOrder = order
            order += 1

            b.Activated:Connect(function()
                local function run()
                    Action:FireServer("Command", {
                        command = command,
                    })
                end

                if confirmText then
                    ask(
                        "CONFIRMAR COMANDO GLOBAL",
                        confirmText,
                        run
                    )
                else
                    run()
                end
            end)
        end

        allCommand(
            "✈ VOAR TODOS",
            "FlyAll",
            Color3.fromRGB(50,75,82),
            "Ativar voo para todos os jogadores de cargo inferior?"
        )

        allCommand(
            "⏹ PARAR VOO DE TODOS",
            "UnflyAll",
            Color3.fromRGB(49,67,72),
            "Desativar voo de todos os jogadores de cargo inferior?"
        )

        allCommand(
            "❤ CURAR TODOS",
            "HealAll",
            Color3.fromRGB(48,82,59)
        )

        allCommand(
            "↻ RESPAWN TODOS",
            "RespawnAll",
            Color3.fromRGB(57,72,94),
            "Respawnar todos os jogadores de cargo inferior?"
        )

        allCommand(
            "⇢ TRAZER TODOS",
            "BringAll",
            Color3.fromRGB(73,68,48),
            "Trazer todos os jogadores de cargo inferior até você?"
        )

        allCommand(
            "☠ KILL ALL",
            "KillAll",
            C.Danger,
            "Eliminar todos os jogadores de cargo inferior ao seu?"
        )
    end

    new("Frame", {
        LayoutOrder = 999,
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        ZIndex = 44,
    }, Scroll)
end

-- ============================================================
-- ABA CARGOS
-- ============================================================
local rankIndex=1
local function renderRanks()
    clear(Content); title("GERENCIAMENTO DE CARGOS")
    local Info=new("TextLabel",{Position=UDim2.fromScale(0,0.10),Size=UDim2.fromScale(1,0.23),BackgroundColor3=Color3.fromRGB(24,37,26),BorderSizePixel=0,Text=selectedText(),TextColor3=C.Text,TextSize=11,Font=Enum.Font.GothamMedium,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=44},Content)
    round(Info,12); new("UIPadding",{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14)},Info)
    local ranks={"Nenhum","Suporte","Moderador","Administrador","Supervisor"}
    if state.level>=6 then table.insert(ranks,"Sub-Dono"); if state.allowMultipleOwners then table.insert(ranks,"Dono") end end
    rankIndex=math.clamp(rankIndex,1,#ranks)
    new("TextLabel",{Position=UDim2.fromScale(0,0.40),Size=UDim2.fromScale(1,0.08),BackgroundTransparency=1,Text="NOVO CARGO",TextColor3=C.Muted,TextSize=10,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=44},Content)
    local selector=new("TextButton",{Position=UDim2.fromScale(0,0.49),Size=UDim2.fromScale(1,0.10),BackgroundColor3=Color3.fromRGB(31,47,33),BorderSizePixel=0,Text=ranks[rankIndex].."   ▾",TextColor3=C.Text,TextSize=12,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=44},Content); round(selector,11); stroke(selector,C.Olive,1,0.35)
    selector.Activated:Connect(function() rankIndex=rankIndex%#ranks+1; selector.Text=ranks[rankIndex].."   ▾" end)
    local confirm=actionButton(Content,"CONFIRMAR ALTERAÇÃO",Color3.fromRGB(56,82,57)); confirm.Position=UDim2.fromScale(0,0.65); confirm.Size=UDim2.fromScale(1,0.11)
    confirm.Activated:Connect(function()
        if not selected then notify(false,"Selecione um jogador na aba JOGADORES.") return end
        local newRank=ranks[rankIndex]
        ask("ALTERAR CARGO",selected.Name.."\n"..selected.Rank.." → "..newRank,function() Action:FireServer("SetRank",{targetUserId=selected.UserId,newRank=newRank}) end)
    end)
    new("TextLabel",{Position=UDim2.fromScale(0,0.80),Size=UDim2.fromScale(1,0.15),BackgroundTransparency=1,Text="A hierarquia é validada novamente pelo servidor. O Dono principal não pode ser alterado.",TextColor3=C.Muted,TextSize=9,Font=Enum.Font.GothamMedium,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=44},Content)
end

-- ============================================================
-- ABA REGISTROS
-- ============================================================
local function renderLogs()
    clear(Content)

    new("TextLabel", {
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 0.07),
        BackgroundTransparency = 1,
        Text = "REGISTROS ADMINISTRATIVOS",
        TextColor3 = C.Text,
        TextSize = 15,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 44,
    }, Content)

    local result = serverQuery("Logs")

    if not result.success then
        notify(
            false,
            result.message or "Falha ao carregar o histórico global."
        )
    end

    new("TextLabel", {
        Position = UDim2.fromScale(0, 0.065),
        Size = UDim2.fromScale(1, 0.055),
        BackgroundTransparency = 1,
        Text = "HISTÓRICO GLOBAL • RETENÇÃO AUTOMÁTICA DE 7 DIAS",
        TextColor3 = C.Muted,
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 44,
    }, Content)

    local List = new("ScrollingFrame", {
        Position = UDim2.fromScale(0, 0.13),
        Size = UDim2.fromScale(1, 0.85),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = C.Olive,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 44,
    }, Content)

    new("UIPadding", {
        PaddingBottom = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 6),
    }, List)

    new("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, List)

    for _, log in ipairs(result.logs or {}) do
        local card = new("Frame", {
            Size = UDim2.new(1, -4, 0, 72),
            BackgroundColor3 = Color3.fromRGB(24,37,26),
            BorderSizePixel = 0,
            ZIndex = 45,
        }, List)
        round(card, 10)

        local timeText = "--/-- --:--"
        pcall(function()
            timeText = os.date(
                "%d/%m %H:%M",
                tonumber(log.Time) or os.time()
            )
        end)

        new("TextLabel", {
            Position = UDim2.fromScale(0.03, 0.08),
            Size = UDim2.fromScale(0.94, 0.35),
            BackgroundTransparency = 1,
            Text = "["
                .. timeText
                .. "] "
                .. tostring(log.AdminName)
                .. " • "
                .. tostring(log.Action)
                .. " • "
                .. tostring(log.TargetName),
            TextColor3 = C.Text,
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 46,
        }, card)

        new("TextLabel", {
            Position = UDim2.fromScale(0.03, 0.48),
            Size = UDim2.fromScale(0.94, 0.36),
            BackgroundTransparency = 1,
            Text = tostring(log.Detail or ""),
            TextColor3 = C.Muted,
            TextSize = 9,
            Font = Enum.Font.GothamMedium,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 46,
        }, card)
    end

    if #(result.logs or {}) == 0 then
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 52),
            BackgroundTransparency = 1,
            Text = "Nenhum registro global dos últimos 7 dias.",
            TextColor3 = C.Muted,
            TextSize = 11,
            Font = Enum.Font.GothamMedium,
            ZIndex = 45,
        }, List)
    end
end

-- ============================================================
-- ESTADO / RENDER
-- ============================================================
local function updateRankVisual()
    local rank=Player:GetAttribute("AdminRank") or state.rank or "Nenhum"
    state.rank=rank
    state.level=({Nenhum=0,Suporte=1,Moderador=2,Administrador=3,Supervisor=4,["Sub-Dono"]=5,Dono=6})[rank] or state.level or 0
    RankLabel.Text="● "..string.upper(rank=="Nenhum" and "SEM CARGO" or rank)
    RankLabel.TextColor3=state.level>0 and C.Green or C.Muted
end

renderCurrent=function()
    findSelected(); updateTabVisibility()
    if currentTab=="JOGADORES" then renderPlayers()
    elseif currentTab=="PUNIÇÕES" and state.level>=1 then renderPunishments()
    elseif currentTab=="COMANDOS" and state.level>=3 then renderCommands()
    elseif currentTab=="CARGOS" and state.level>=5 then renderRanks()
    elseif currentTab=="REGISTROS" and state.level>=4 then renderLogs()
    else currentTab="JOGADORES"; renderPlayers() end
    activeTab()
end

for name,b in pairs(Tabs) do b.Activated:Connect(function() currentTab=name; renderCurrent() end) end

local refreshing=false
local function refresh(renderAfter)
    if refreshing then return end
    refreshing=true
    task.spawn(function()
        local result=serverQuery("Bootstrap")
        refreshing=false
        if result.success then
            state=result; state.players=state.players or {}; state.level=tonumber(state.level) or 0; state.rank=state.rank or "Nenhum"
            updateRankVisual(); updateTabVisibility(); findSelected()
            if renderAfter and panelOpen then renderCurrent() end
        elseif panelOpen then
            notify(false,result.message or "Não foi possível atualizar o painel.")
        end
    end)
end

-- ============================================================
-- TEAM SUPORTE / ABRIR PAINEL
-- O painel aparece primeiro; consulta ao servidor acontece depois.
-- Isso evita o antigo bug do clique parecer não funcionar.
-- ============================================================
local function isSupport()
    local team=Teams:FindFirstChild("Suporte")
    return team~=nil and Player.Team==team
end
local function closePanel()
    panelOpen=false
    TweenService:Create(PanelScale,FAST,{Scale=0.94}):Play()
    task.delay(0.14,function() if not panelOpen then Panel.Visible=false end end)
end
local function openPanel()
    if not isSupport() then notify(false,"Você precisa estar no Team Suporte.") return end
    panelOpen=true; Panel.Visible=true; PanelScale.Scale=0.94
    TweenService:Create(PanelScale,OPEN,{Scale=1}):Play()
    updateRankVisual(); renderCurrent(); refresh(true)
end
local function teamGate()
    AdminButton.Visible=isSupport()
    if not AdminButton.Visible then closePanel() end
end
AdminButton.Activated:Connect(function() if panelOpen then closePanel() else openPanel() end end)
Close.Activated:Connect(closePanel)
Player:GetPropertyChangedSignal("Team"):Connect(function() teamGate(); refresh(panelOpen) end)
Teams.ChildAdded:Connect(teamGate); Teams.ChildRemoved:Connect(teamGate)
Player:GetAttributeChangedSignal("AdminRank"):Connect(function() updateRankVisual(); if panelOpen then refresh(true) end end)

-- ============================================================
-- VOO ADMINISTRATIVO
-- Usa LinearVelocity e funciona com teclado/controle/touch.
-- O servidor decide quem pode ativar/desativar o voo.
-- ============================================================
local flyConnection = nil
local flyAttachment = nil
local flyVelocity = nil
local flyUp = 0
local flyDown = 0
local flySpeed = 72

local function stopFlying()
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end

    ContextActionService:UnbindAction("EB_AdminFlyUp")
    ContextActionService:UnbindAction("EB_AdminFlyDown")

    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end

    if flyAttachment then
        flyAttachment:Destroy()
        flyAttachment = nil
    end

    flyUp = 0
    flyDown = 0

    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

local function flyVertical(actionName, inputState)
    local value =
        inputState == Enum.UserInputState.Begin
        and 1
        or 0

    if actionName == "EB_AdminFlyUp" then
        flyUp = value
    elseif actionName == "EB_AdminFlyDown" then
        flyDown = value
    end

    return Enum.ContextActionResult.Sink
end

local function startFlying(speed)
    stopFlying()

    flySpeed =
        math.clamp(
            tonumber(speed) or 72,
            30,
            150
        )

    local character =
        Player.Character
        or Player.CharacterAdded:Wait()

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        notify(false, "Não foi possível iniciar o voo.")
        return
    end

    flyAttachment = Instance.new("Attachment")
    flyAttachment.Name = "EBAdminFlyAttachment"
    flyAttachment.Parent = root

    flyVelocity = Instance.new("LinearVelocity")
    flyVelocity.Name = "EBAdminFlyVelocity"
    flyVelocity.Attachment0 = flyAttachment
    flyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    flyVelocity.MaxForce = 1000000000
    flyVelocity.VectorVelocity = Vector3.zero
    flyVelocity.Parent = root

    ContextActionService:BindAction(
        "EB_AdminFlyUp",
        flyVertical,
        true,
        Enum.KeyCode.Space,
        Enum.KeyCode.ButtonA
    )

    ContextActionService:BindAction(
        "EB_AdminFlyDown",
        flyVertical,
        true,
        Enum.KeyCode.LeftControl,
        Enum.KeyCode.ButtonB
    )

    pcall(function()
        ContextActionService:SetTitle(
            "EB_AdminFlyUp",
            "SUBIR"
        )

        ContextActionService:SetPosition(
            "EB_AdminFlyUp",
            UDim2.fromScale(0.84, 0.66)
        )

        ContextActionService:SetTitle(
            "EB_AdminFlyDown",
            "DESCER"
        )

        ContextActionService:SetPosition(
            "EB_AdminFlyDown",
            UDim2.fromScale(0.84, 0.79)
        )
    end)

    flyConnection =
        RunService.RenderStepped:Connect(function()
            if not root.Parent
                or not humanoid.Parent
                or humanoid.Health <= 0
                or not flyVelocity
                or not flyVelocity.Parent then

                stopFlying()
                return
            end

            local move =
                humanoid.MoveDirection

            local vertical =
                (flyUp - flyDown)
                * flySpeed

            flyVelocity.VectorVelocity =
                Vector3.new(
                    move.X * flySpeed,
                    vertical,
                    move.Z * flySpeed
                )
        end)
end

Player.CharacterAdded:Connect(function()
    task.delay(
        0.7,
        function()
            if Player:GetAttribute("AdminFlying") == true then
                startFlying(flySpeed)
            else
                stopFlying()
            end
        end
    )
end)

-- ============================================================
-- SERVIDOR -> CLIENTE
-- ============================================================
Action.OnClientEvent:Connect(function(kind,data)
    if kind=="FlyState" and type(data)=="table" then
        if data.enabled == true then
            startFlying(data.speed)
        else
            stopFlying()
        end
        return
    end

    if kind=="Result" and type(data)=="table" then
        notify(data.success==true,data.message or "Ação processada.")
        task.delay(0.12,function() refresh(panelOpen) end)
    elseif kind=="Refresh" then
        task.defer(function() refresh(panelOpen) end)
    end
end)
Players.PlayerAdded:Connect(function() task.defer(function() refresh(panelOpen) end) end)
Players.PlayerRemoving:Connect(function() task.delay(0.1,function() refresh(panelOpen) end) end)

-- ============================================================
-- RESPONSIVIDADE
-- ============================================================
local camConn
local function responsive()
    local cam=Workspace.CurrentCamera; if not cam then return end
    if cam.ViewportSize.X<700 then
        Panel.Size=UDim2.fromScale(0.95,0.84); Sidebar.Size=UDim2.fromScale(0.28,0.815)
        Content.Position=UDim2.fromScale(0.30,0.14); Content.Size=UDim2.fromScale(0.67,0.74)
        AdminButton.Size=UDim2.fromOffset(154,46); AdminButton.Position=UDim2.fromScale(0.97,0.95)
        Confirm.Size=UDim2.fromScale(0.82,0.30)
    else
        Panel.Size=UDim2.fromScale(0.72,0.72); Sidebar.Size=UDim2.fromScale(0.23,0.815)
        Content.Position=UDim2.fromScale(0.255,0.14); Content.Size=UDim2.fromScale(0.72,0.74)
        AdminButton.Size=UDim2.fromOffset(184,48); AdminButton.Position=UDim2.fromScale(0.98,0.95)
        Confirm.Size=UDim2.fromScale(0.34,0.28)
    end

    -- Se a resolução/orientação mudar depois de arrastar, mantém o painel recuperável.
    if Panel.Visible then
        task.defer(function()
            local center = clampPanelCenter(panelCenterOnScreen())
            Panel.Position = UDim2.fromOffset(center.X, center.Y)
        end)
    end
end
local function hookCam()
    if camConn then camConn:Disconnect() end
    local cam=Workspace.CurrentCamera; if cam then camConn=cam:GetPropertyChangedSignal("ViewportSize"):Connect(responsive) end
    responsive()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCam); hookCam()

teamGate(); updateRankVisual(); refresh(false)
]==]

print("============================================================")
print("EB // SISTEMA COMPLETO V7 INSTALADO - LOGS DISCORD + ANTICHEAT")
print("Dono configurado: 468762368")
print("Sub-Dono fixo: 2887861665")
print("ADMIN_AUTO_JOIN_SUPPORT = true: qualquer cargo administrativo entra automaticamente no Team Suporte.")
print("StarterGui recriado: GraphicsSystem + AdminSystemGui")
print("ReplicatedStorage: EBAdminSystem")
print("ServerScriptService: EBAdminServer + EBServerConfig + EBLogBridge + EBFlyAuthorization + EBAntiCheat")
print("IMPORTANTE: configure LOG_BACKEND_URL e LOG_SHARED_SECRET no começo do instalador antes de usar os logs externos.")
print("Anticheat Fly: server-side, com grace period, score de suspeita e integração ao Fly/Unfly/FlyAll/UnflyAll.")
print("Agora dê Play para testar.")
print("============================================================")
