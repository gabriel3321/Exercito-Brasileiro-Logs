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
