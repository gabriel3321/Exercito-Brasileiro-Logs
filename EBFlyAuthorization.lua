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
