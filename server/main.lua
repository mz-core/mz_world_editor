
local function aceListText()
    return table.concat(Config.AdminAces or { Config.AdminAce }, ', ')
end

local function getAllowedAce(src)
    if src == 0 then return true, 'console' end

    local aces = Config.AdminAces or { Config.AdminAce }
    for _, ace in ipairs(aces) do
        if ace and ace ~= '' and IsPlayerAceAllowed(src, ace) then
            return true, ace
        end
    end

    return false, nil
end

local function canUse(src)
    local allowed = getAllowedAce(src)
    return allowed == true
end

CreateThread(function()
    Wait(500)
    print(('[mz_world_editor] server iniciado | comando client: /%s | ACEs aceitos: %s'):format(Config.Command, aceListText()))
end)

exports('CanUseWorldEditor', function(src)
    return canUse(src)
end)

RegisterNetEvent('mz_world_editor:server:checkPermission', function()
    local src = source
    local allowed, matchedAce = getAllowedAce(src)
    if Config.EnableDebugPrint then
        print(('[mz_world_editor] checkPermission | src=%s | name=%s | allowed=%s | matchedAce=%s | aces=%s'):format(src, GetPlayerName(src) or 'unknown', tostring(allowed), tostring(matchedAce), aceListText()))
    end
    TriggerClientEvent('mz_world_editor:client:permissionResult', src, allowed, matchedAce, aceListText())
end)

RegisterNetEvent('mz_world_editor:server:logAction', function(action, data)
    local src = source
    if not canUse(src) then return end
    if Config.EnableDebugPrint then
        print(('[mz_world_editor] %s (%s) -> %s %s'):format(GetPlayerName(src) or src, src, tostring(action), json.encode(data or {})))
    end
end)


RegisterCommand('mzwetest', function(src)
    if src == 0 then
        print(('[mz_world_editor] teste console | ACEs aceitos: %s'):format(aceListText()))
        return
    end

    local allowed, matchedAce = getAllowedAce(src)
    print(('[mz_world_editor] teste ACE | src=%s | name=%s | allowed=%s | matchedAce=%s'):format(src, GetPlayerName(src) or 'unknown', tostring(allowed), tostring(matchedAce)))

    for _, ace in ipairs(Config.AdminAces or { Config.AdminAce }) do
        print(('[mz_world_editor]  - IsPlayerAceAllowed(%s, %s) = %s'):format(src, ace, tostring(IsPlayerAceAllowed(src, ace))))
    end

    TriggerClientEvent('mz_world_editor:client:permissionResult', src, allowed, matchedAce, aceListText())
end, false)
