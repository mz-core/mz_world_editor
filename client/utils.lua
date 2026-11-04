MZWE = MZWE or {}

function MZWE.Round(value, decimals)
    local mult = 10 ^ (decimals or 2)
    return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
end

function MZWE.VecToTable(v)
    return {
        x = MZWE.Round(v.x, 4),
        y = MZWE.Round(v.y, 4),
        z = MZWE.Round(v.z, 4)
    }
end

function MZWE.Notify(message, typ)
    message = tostring(message or '')
    typ = typ or 'info'

    -- Sempre printa no F8 para debug. Antes, se mz_notify existisse,
    -- o script retornava cedo e podia aparecer uma notificacao vazia sem log.
    print(('[mz_world_editor][notify:%s] %s'):format(tostring(typ), message))

    if Config.UseMzNotify == true and GetResourceState('mz_notify') == 'started' then
        local notifyType = typ == 'inform' and 'info' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_notify']:Notify({
                type = notifyType,
                title = 'MZ World Editor',
                message = message,
                duration = 4000
            })
        end)
        if ok and result ~= false then return true end
        print(('[mz_world_editor] mz_notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseMzMenuNotify == true and GetResourceState('mz_menu') == 'started' then
        local menuType = typ == 'info' and 'inform' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_menu']:Notify(message, menuType, 4000, { title = 'MZ World Editor' })
        end)
        if ok and result ~= false then return true end
        print(('[mz_world_editor] mz_menu Notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseChatNotify ~= false and GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', {
            color = typ == 'error' and { 255, 80, 80 } or { 80, 200, 255 },
            multiline = true,
            args = { 'MZ World Editor', message }
        })
    end

    if Config.UseNativeNotify ~= false then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('MZ World Editor: %s'):format(message))
        EndTextCommandThefeedPostTicker(false, false)
    end
    return false
end

function MZWE.DrawText2D(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.34, scale or 0.34)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(false)
    SetTextDropshadow(1, 0, 0, 0, 180)
    SetTextEdge(1, 0, 0, 0, 180)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function MZWE.DrawPanel(lines)
    local x, y = 0.015, 0.22
    local w = 0.34
    local h = 0.032 + (#lines * 0.024)
    DrawRect(x + (w / 2), y + (h / 2), w, h, 8, 10, 18, 185)
    for i, line in ipairs(lines) do
        MZWE.DrawText2D(x + 0.012, y + 0.012 + ((i - 1) * 0.024), line, i == 1 and 0.42 or 0.32)
    end
end

function MZWE.DrawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function MZWE.DrawSelectorReticle(hasTarget)
    local color = hasTarget and { r = 245, g = 210, b = 110 } or { r = 235, g = 235, b = 235 }
    local x, y = 0.5, 0.5
    local gap, length, thickness = 0.012, 0.010, 0.0015
    DrawRect(x - gap - (length * 0.5), y, length, thickness, color.r, color.g, color.b, 230)
    DrawRect(x + gap + (length * 0.5), y, length, thickness, color.r, color.g, color.b, 230)
    DrawRect(x, y - gap - (length * 0.5), thickness, length, color.r, color.g, color.b, 230)
    DrawRect(x, y + gap + (length * 0.5), thickness, length, color.r, color.g, color.b, 230)
end

function MZWE.TryGetModelHash(entity)
    if not entity or entity == 0 then
        return nil, 'empty_entity'
    end

    if not DoesEntityExist(entity) then
        return nil, 'entity_not_exists'
    end

    -- IsAnEntity ajuda a filtrar alguns handles estranhos retornados por raycast.
    if IsAnEntity and not IsAnEntity(entity) then
        return nil, 'not_an_entity'
    end

    local ok, model = pcall(function()
        return GetEntityModel(entity)
    end)

    if not ok or not model or model == 0 then
        return nil, tostring(model or 'get_model_failed')
    end

    return model, nil
end

function MZWE.GetEntityModelName(entity)
    if type(GetEntityArchetypeName) ~= 'function' then return nil end
    local ok, name = pcall(GetEntityArchetypeName, entity)
    if not ok or type(name) ~= 'string' or name == '' then return nil end
    return name
end

function MZWE.GetEntityVisualCenter(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local coords = GetEntityCoords(entity)
    local model = MZWE.TryGetModelHash(entity)
    if not model then return coords end
    local okDimensions, minimum, maximum = pcall(GetModelDimensions, model)
    if not okDimensions or not minimum or not maximum then return coords end
    local okCenter, center = pcall(
        GetOffsetFromEntityInWorldCoords,
        entity,
        (minimum.x + maximum.x) * 0.5,
        (minimum.y + maximum.y) * 0.5,
        (minimum.z + maximum.z) * 0.5
    )
    return okCenter and center or coords
end

function MZWE.DrawEntityBox(entity, color)
    if not DoesEntityExist(entity) then return end

    local model = MZWE.TryGetModelHash(entity)
    if not model then return end

    local okDim, min, max = pcall(function()
        local a, b = GetModelDimensions(model)
        return a, b
    end)
    if not okDim or not min or not max then return end

    local okMatrix, right, forward, up, pos = pcall(function()
        return GetEntityMatrix(entity)
    end)
    if not okMatrix or not pos then return end

    local corners = {}
    for _, sx in ipairs({ min.x, max.x }) do
        for _, sy in ipairs({ min.y, max.y }) do
            for _, sz in ipairs({ min.z, max.z }) do
                corners[#corners + 1] = vector3(
                    pos.x + forward.x * sx + right.x * sy + up.x * sz,
                    pos.y + forward.y * sx + right.y * sy + up.y * sz,
                    pos.z + forward.z * sx + right.z * sy + up.z * sz
                )
            end
        end
    end

    local edges = {
        {1, 2}, {1, 3}, {1, 5},
        {4, 2}, {4, 3}, {4, 8},
        {6, 2}, {6, 5}, {6, 8},
        {7, 3}, {7, 5}, {7, 8}
    }

    color = color or Config.Colors.box
    for _, e in ipairs(edges) do
        local a, b = corners[e[1]], corners[e[2]]
        if a and b then
            DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, color.r, color.g, color.b, color.a)
        end
    end
end

function MZWE.BuildEntityPreviewData(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    local coords = GetEntityCoords(entity)
    return {
        entity = entity,
        entity_type = GetEntityType(entity),
        model_name = MZWE.GetEntityModelName(entity),
        coords = MZWE.VecToTable(coords),
        heading = MZWE.Round(GetEntityHeading(entity), 4)
    }
end

function MZWE.EntityTypeName(entityType)
    if entityType == 1 then return 'Ped' end
    if entityType == 2 then return 'Vehicle' end
    if entityType == 3 then return 'Object/Prop' end
    return 'Unknown'
end

function MZWE.BuildEntityData(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil, 'entity_not_exists'
    end

    local model, modelErr = MZWE.TryGetModelHash(entity)
    if not model then
        return nil, modelErr or 'get_model_failed'
    end

    local coords = GetEntityCoords(entity)
    local rot = GetEntityRotation(entity, 2)
    local interactionCoords = coords
    local okDimensions, minDimensions, maxDimensions = pcall(function()
        return GetModelDimensions(model)
    end)
    if okDimensions and minDimensions and maxDimensions then
        local centerX = (minDimensions.x + maxDimensions.x) * 0.5
        local centerY = (minDimensions.y + maxDimensions.y) * 0.5
        local centerZ = (minDimensions.z + maxDimensions.z) * 0.5
        local okCenter, worldCenter = pcall(function()
            return GetOffsetFromEntityInWorldCoords(entity, centerX, centerY, centerZ)
        end)
        if okCenter and worldCenter then interactionCoords = worldCenter end
    end

    local netId = 0
    local okNet, isNetworked = pcall(function()
        return NetworkGetEntityIsNetworked(entity)
    end)
    if okNet and isNetworked then
        local okId, id = pcall(function()
            return NetworkGetNetworkIdFromEntity(entity)
        end)
        if okId then netId = id or 0 end
    end

    local data = {
        entity = entity,
        entity_type = GetEntityType(entity),
        model_hash = model,
        model_name = MZWE.GetEntityModelName(entity),
        net_id = netId,
        coords = MZWE.VecToTable(coords),
        interaction_coords = MZWE.VecToTable(interactionCoords),
        rotation = MZWE.VecToTable(rot),
        heading = MZWE.Round(GetEntityHeading(entity), 4)
    }
    return data, nil
end

function MZWE.PrintEntityData(data)
    local text = json.encode(data)
    print('[mz_world_editor] Entity data:')
    print(text)
    TriggerEvent('chat:addMessage', {
        color = { 80, 200, 255 },
        multiline = true,
        args = { 'MZWE', ('Hash: %s | Type: %s | Coords: %.2f %.2f %.2f | Heading: %.2f'):format(
            data.model_hash,
            MZWE.EntityTypeName(data.entity_type),
            data.coords.x, data.coords.y, data.coords.z,
            data.heading
        ) }
    })
end
