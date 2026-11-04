local editorActive = false
local pendingPermission = false
local permissionKnown = nil
local lastEntity = nil
local frozenLocal = {}
local selectionSession = nil
local placementSession = nil
local selectionOutlinedEntity = nil

local function clearSelectionOutline()
    local entity = selectionOutlinedEntity
    selectionOutlinedEntity = nil
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    pcall(function() SetEntityDrawOutline(entity, false) end)
end

local function applySelectionOutline(entity)
    local settings = Config.Editor.selectionOutline or {}
    if settings.enabled == false or not entity or entity == 0 or not DoesEntityExist(entity) then
        clearSelectionOutline()
        return
    end
    if selectionOutlinedEntity ~= entity then
        clearSelectionOutline()
        selectionOutlinedEntity = entity
    end
    local color = settings.color or { r = 255, g = 190, b = 35, a = 255 }
    pcall(function()
        if type(SetEntityDrawOutlineShader) == 'function' then
            SetEntityDrawOutlineShader(tonumber(settings.shader) or 1)
        end
        SetEntityDrawOutlineColor(
            tonumber(color.r) or 255,
            tonumber(color.g) or 190,
            tonumber(color.b) or 35,
            tonumber(color.a) or 255
        )
        SetEntityDrawOutline(entity, true)
    end)
end

local function finishSelection(result, reason)
    local session = selectionSession
    if not session then return end
    clearSelectionOutline()
    selectionSession = nil
    editorActive = false
    if result then
        TriggerEvent('mz_world_editor:client:selectionResult', session.requestId, result)
    else
        TriggerEvent('mz_world_editor:client:selectionCancelled', session.requestId, reason or 'cancelled')
    end
end

exports('StartEntitySelection', function(options)
    options = type(options) == 'table' and options or {}
    if selectionSession or editorActive then return false, 'editor_busy' end
    local requestId = tostring(options.requestId or '')
    if requestId == '' then return false, 'invalid_request_id' end
    selectionSession = {
        requestId = requestId,
        objectsOnly = options.objectsOnly ~= false,
        title = tostring(options.title or 'Selecionar objeto'),
        targetLabel = tostring(options.targetLabel or 'folha da porta'),
        selectedCount = math.max(0, tonumber(options.selectedCount) or 0),
        requiredCount = math.max(1, tonumber(options.requiredCount) or 1),
        excluded = type(options.excluded) == 'table' and options.excluded or {},
        candidates = {},
        candidateIndex = 1,
        lastCandidateRefresh = 0
    }
    editorActive = true
    return true
end)

local function updatePlacementCamera(session)
    if not session or not session.camera or not DoesCamExist(session.camera) then return end
    local center = MZWE.GetEntityVisualCenter(session.entity) or session.position
    local yaw = math.rad(session.cameraYaw or 0.0)
    local pitch = math.rad(session.cameraPitch or -20.0)
    local distance = tonumber(session.cameraDistance) or 4.5
    local horizontalDistance = math.cos(pitch) * distance
    local cameraCoords = vector3(
        center.x + (math.sin(yaw) * horizontalDistance),
        center.y - (math.cos(yaw) * horizontalDistance),
        center.z - (math.sin(pitch) * distance)
    )
    SetCamCoord(session.camera, cameraCoords.x, cameraCoords.y, cameraCoords.z)
    PointCamAtCoord(session.camera, center.x, center.y, center.z)
end

local function destroyPlacementCamera(session)
    if not session or not session.camera then return end
    RenderScriptCams(false, true, 250, true, true)
    if DoesCamExist(session.camera) then
        SetCamActive(session.camera, false)
        DestroyCam(session.camera, false)
    end
    session.camera = nil
end

local function surfaceRotation(normal, offset, fallbackHeading)
    if not normal then return { x = 0.0, y = 0.0, z = tonumber(fallbackHeading) or 0.0 } end
    local nx, ny, nz = tonumber(normal.x) or 0.0, tonumber(normal.y) or 0.0, tonumber(normal.z) or 0.0
    local horizontal = math.sqrt(nx * nx + ny * ny)
    local rotation = {
        x = math.deg(math.atan(nz, math.max(horizontal, 0.0001))),
        y = 0.0,
        z = math.deg(math.atan(-nx, ny))
    }
    offset = type(offset) == 'table' and offset or {}
    rotation.x = rotation.x + (tonumber(offset.x) or 0.0)
    rotation.y = rotation.y + (tonumber(offset.y) or 0.0)
    rotation.z = rotation.z + (tonumber(offset.z) or 0.0)
    return rotation
end

local function finishPlacement(result, reason)
    local session = placementSession
    if not session then return end
    placementSession = nil
    destroyPlacementCamera(session)
    if session.entity and DoesEntityExist(session.entity) then DeleteEntity(session.entity) end
    if session.ped and DoesEntityExist(session.ped) and session.pedWasFrozen ~= true then
        FreezeEntityPosition(session.ped, false)
    end
    SetModelAsNoLongerNeeded(session.modelHash)
    if result then
        TriggerEvent('mz_world_editor:client:placementResult', session.requestId, result)
    else
        TriggerEvent('mz_world_editor:client:placementCancelled', session.requestId, reason or 'cancelled')
    end
end

exports('StartPropPlacement', function(options)
    options = type(options) == 'table' and options or {}
    if selectionSession or placementSession or editorActive then return false, 'editor_busy' end
    local requestId = tostring(options.requestId or '')
    local modelHash = tonumber(options.modelHash)
    if requestId == '' then return false, 'invalid_request_id' end
    if not modelHash or not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        return false, 'invalid_model'
    end

    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() > timeout then
            SetModelAsNoLongerNeeded(modelHash)
            return false, 'model_timeout'
        end
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'leave_vehicle_first'
    end
    local pedCoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local initialCoords = vector3(
        pedCoords.x + (forward.x * 3.0),
        pedCoords.y + (forward.y * 3.0),
        pedCoords.z
    )
    local suppliedCoords = type(options.initialCoords) == 'table' and options.initialCoords or nil
    local initialSurfaceNormal = type(options.initialSurfaceNormal) == 'table'
        and options.initialSurfaceNormal or nil
    if suppliedCoords and tonumber(suppliedCoords.x) and tonumber(suppliedCoords.y)
        and tonumber(suppliedCoords.z) then
        initialCoords = vector3(
            tonumber(suppliedCoords.x) + 0.0,
            tonumber(suppliedCoords.y) + 0.0,
            tonumber(suppliedCoords.z) + 0.0
        )
    else
        local hit, hitCoords, hitNormal = MZWE.RaycastFromCamera(math.max(Config.ViewDistance, 25.0))
        if hit and hitCoords and #(pedCoords - hitCoords) >= 1.5 and #(pedCoords - hitCoords) <= 30.0 then
            initialSurfaceNormal = hitNormal
            local offset = options.surfaceSnap == true and (tonumber(options.surfaceOffset) or 0.0) or 0.0
            initialCoords = hitCoords + (hitNormal * offset)
        end
    end

    local entity = CreateObjectNoOffset(
        modelHash,
        initialCoords.x, initialCoords.y, initialCoords.z,
        false, false, false
    )
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'ghost_creation_failed'
    end
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityAlpha(entity, 165, false)
    local pedWasFrozen = false
    if type(IsEntityPositionFrozen) == 'function' then
        local frozenOk, frozen = pcall(IsEntityPositionFrozen, ped)
        pedWasFrozen = frozenOk and frozen == true
    end
    FreezeEntityPosition(ped, true)
    local gameplayRotation = GetGameplayCamRot(2)
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not camera or camera == 0 or not DoesCamExist(camera) then
        DeleteEntity(entity)
        if pedWasFrozen ~= true then FreezeEntityPosition(ped, false) end
        SetModelAsNoLongerNeeded(modelHash)
        return false, 'placement_camera_failed'
    end

    placementSession = {
        requestId = requestId,
        title = tostring(options.title or 'Posicionar prop'),
        modelHash = modelHash,
        modelName = tostring(options.modelName or ''),
        entity = entity,
        ped = ped,
        pedWasFrozen = pedWasFrozen,
        heading = tonumber(options.heading) or GetEntityHeading(PlayerPedId()),
        position = initialCoords + vector3(0.0, 0.0, tonumber(options.zOffset) or 0.0),
        initialRotation = type(options.initialRotation) == 'table' and options.initialRotation or nil,
        fullRotation = options.fullRotation == true,
        rotationAxis = 'z',
        surfaceSnap = options.surfaceSnap == true,
        surfaceOffset = tonumber(options.surfaceOffset) or 0.0,
        surfaceRotationOffset = type(options.surfaceRotationOffset) == 'table'
            and options.surfaceRotationOffset or nil,
        surfaceNormal = initialSurfaceNormal,
        resetRotation = type(options.resetRotation) == 'table' and options.resetRotation or nil,
        validationRequired = options.validationRequired == true,
        valid = options.validationRequired ~= true,
        validationReason = options.validationRequired == true and 'validating_position' or nil,
        camera = camera,
        cameraYaw = gameplayRotation.z,
        cameraPitch = math.max(
            Config.Editor.placementCameraMinPitch or -70.0,
            math.min(Config.Editor.placementCameraMaxPitch or -8.0, gameplayRotation.x)
        ),
        cameraDistance = tonumber(Config.Editor.placementCameraDistance) or 4.5
    }
    SetEntityCoordsNoOffset(
        entity,
        placementSession.position.x,
        placementSession.position.y,
        placementSession.position.z,
        false, false, false
    )
    if not placementSession.initialRotation and placementSession.surfaceSnap and initialSurfaceNormal then
        placementSession.initialRotation = surfaceRotation(
            initialSurfaceNormal,
            placementSession.surfaceRotationOffset,
            placementSession.heading
        )
    end
    if placementSession.initialRotation then
        placementSession.rotation = {
            x = tonumber(placementSession.initialRotation.x) or 0.0,
            y = tonumber(placementSession.initialRotation.y) or 0.0,
            z = tonumber(placementSession.initialRotation.z) or placementSession.heading
        }
        SetEntityRotation(
            entity,
            placementSession.rotation.x,
            placementSession.rotation.y,
            placementSession.rotation.z,
            2,
            true
        )
        placementSession.heading = placementSession.rotation.z
    else
        placementSession.rotation = { x = 0.0, y = 0.0, z = placementSession.heading }
        SetEntityHeading(entity, placementSession.heading)
    end
    placementSession.resetRotation = placementSession.resetRotation or {
        x = placementSession.rotation.x,
        y = placementSession.rotation.y,
        z = placementSession.rotation.z
    }
    SetCamFov(camera, GetGameplayCamFov())
    SetCamNearClip(camera, 0.1)
    updatePlacementCamera(placementSession)
    SetCamActive(camera, true)
    RenderScriptCams(true, true, 300, true, true)
    return true
end)

exports('SetPlacementValidity', function(requestId, valid, reason, detail)
    local session = placementSession
    if not session or tostring(session.requestId) ~= tostring(requestId or '') then
        return false, 'placement_not_found'
    end
    session.valid = valid == true
    session.validationReason = session.valid and nil or tostring(reason or 'invalid_position')
    session.validationDetail = type(detail) == 'table' and detail or nil
    return true
end)

exports('CancelActiveSession', function(reason)
    if placementSession then
        finishPlacement(nil, reason or 'cancelled_by_consumer')
        return true
    end
    if selectionSession then
        finishSelection(nil, reason or 'cancelled_by_consumer')
        return true
    end
    if editorActive then editorActive = false return true end
    return false
end)

exports('IsSessionActive', function()
    return selectionSession ~= nil or placementSession ~= nil
end)

local function toggleEditor()
    print('[mz_world_editor] comando /' .. tostring(Config.Command) .. ' chamado no client')

    if permissionKnown == true then
        editorActive = not editorActive
        print(('[mz_world_editor] editorActive=%s'):format(tostring(editorActive)))
        MZWE.Notify(editorActive and 'Editor ativado. Mire em uma entidade.' or 'Editor desativado.', editorActive and 'success' or 'info')
        return
    end

    if pendingPermission then
        MZWE.Notify('Aguardando resposta de permissao do servidor...', 'info')
        return
    end

    pendingPermission = true
    MZWE.Notify('Verificando permissao ACE...', 'info')
    TriggerServerEvent('mz_world_editor:server:checkPermission')

    SetTimeout(3500, function()
        if pendingPermission then
            pendingPermission = false
            MZWE.Notify('Sem resposta do servidor. Confira se mz_world_editor/server/main.lua iniciou sem erro.', 'error')
        end
    end)
end

RegisterNetEvent('mz_world_editor:client:permissionResult', function(allowed, matchedAce, aceList)
    pendingPermission = false
    permissionKnown = allowed == true
    if not permissionKnown then
        MZWE.Notify(('Sem permissao ACE. Testados: %s'):format(aceList or Config.AdminAce), 'error')
        return
    end

    editorActive = not editorActive
    print(('[mz_world_editor] editorActive=%s | matchedAce=%s'):format(tostring(editorActive), tostring(matchedAce)))
    MZWE.Notify(editorActive and ('Editor ativado. ACE: ' .. tostring(matchedAce or Config.AdminAce)) or 'Editor desativado.', editorActive and 'success' or 'info')
end)

RegisterCommand(Config.Command, function()
    toggleEditor()
end, false)

CreateThread(function()
    Wait(1000)
    print(('[mz_world_editor] client iniciado | comando: /%s | ACE principal: %s'):format(Config.Command, Config.AdminAce))
    if GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Ativa/desativa o MZ World Editor')
    end
end)

local function canUseEntityForDoor(entity)
    if not DoesEntityExist(entity) then return false end
    if not Config.Editor.allowCreateDoorFromObjectsOnly then return true end
    return GetEntityType(entity) == 3
end

local function canUseEntityForProp(entity)
    if not DoesEntityExist(entity) then return false end
    if not Config.Editor.allowCreatePropFromObjectsOnly then return true end
    return GetEntityType(entity) == 3
end

local function createDoor(entity)
    if GetResourceState('mz_doors') ~= 'started' then
        MZWE.Notify('mz_doors nao esta iniciado.', 'error')
        return
    end

    if not canUseEntityForDoor(entity) then
        MZWE.Notify('Para criar porta, mire em um objeto/prop.', 'error')
        return
    end

    local data, err = MZWE.BuildEntityData(entity)
    if not data then
        MZWE.Notify(('Nao consegui ler o modelo da entidade: %s'):format(tostring(err)), 'error')
        return
    end
    data.name = ('Porta %s'):format(data.model_hash)
    data.locked = Config.DefaultDoor.locked
    data.distance = Config.DefaultDoor.distance
    data.ace_permission = Config.DefaultDoor.ace_permission

    TriggerServerEvent('mz_doors:server:createFromEditor', data)
    TriggerServerEvent('mz_world_editor:server:logAction', 'create_door', data)
end

local function createProp(entity)
    if GetResourceState('mz_props') ~= 'started' then
        MZWE.Notify('mz_props nao esta iniciado.', 'error')
        return
    end

    if not canUseEntityForProp(entity) then
        MZWE.Notify('Para criar prop persistente, mire em um objeto/prop.', 'error')
        return
    end

    local data, err = MZWE.BuildEntityData(entity)
    if not data then
        MZWE.Notify(('Nao consegui ler o modelo da entidade: %s'):format(tostring(err)), 'error')
        return
    end
    data.name = ('Prop %s'):format(data.model_hash)
    data.frozen = Config.DefaultProp.frozen
    data.collision = Config.DefaultProp.collision
    data.visible = Config.DefaultProp.visible

    TriggerServerEvent('mz_props:server:createFromEditor', data)
    TriggerServerEvent('mz_world_editor:server:logAction', 'create_prop', data)
end

local function toggleFreeze(entity)
    if not Config.Editor.allowFreezeEntity then return end
    if not DoesEntityExist(entity) then return end

    local state = not frozenLocal[entity]
    frozenLocal[entity] = state
    FreezeEntityPosition(entity, state)
    MZWE.Notify(state and 'Entidade congelada localmente.' or 'Entidade descongelada localmente.', 'info')
end

local function isSelectionEntityExcluded(session, entity)
    if not session or not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local model
    local coords
    for _, excluded in ipairs(session.excluded or {}) do
        if tonumber(excluded.entity) and tonumber(excluded.entity) == tonumber(entity) then return true end
        local excludedModel = tonumber(excluded.model_hash)
        if excludedModel then
            model = model or MZWE.TryGetModelHash(entity)
            if tonumber(model) == excludedModel then
                coords = coords or GetEntityCoords(entity)
                local excludedCoords = type(excluded.coords) == 'table' and excluded.coords or excluded
                local x, y, z = tonumber(excludedCoords.x), tonumber(excludedCoords.y), tonumber(excludedCoords.z)
                if x and y and z then
                    local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
                    if math.sqrt(dx * dx + dy * dy + dz * dz) <= 0.08 then return true end
                end
            end
        end
    end
    return false
end

local function refreshSelectionCandidates(session, rayEntity)
    local candidates = MZWE.FindObjectsNearCrosshair(
        Config.Editor.selectorMaxDistance or Config.ViewDistance,
        Config.Editor.selectorScreenRadius,
        Config.Editor.selectorMaxCandidates
    )
    for index = #candidates, 1, -1 do
        if isSelectionEntityExcluded(session, candidates[index].entity) then
            table.remove(candidates, index)
        end
    end
    if rayEntity and rayEntity ~= 0 and DoesEntityExist(rayEntity) and GetEntityType(rayEntity) == 3
        and not isSelectionEntityExcluded(session, rayEntity) then
        local foundAt
        for index, candidate in ipairs(candidates) do
            if candidate.entity == rayEntity then foundAt = index break end
        end
        if foundAt and foundAt > 1 then
            local candidate = table.remove(candidates, foundAt)
            table.insert(candidates, 1, candidate)
        elseif not foundAt then
            table.insert(candidates, 1, {
                entity = rayEntity,
                center = MZWE.GetEntityVisualCenter(rayEntity),
                distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(rayEntity)),
                screenDistance = 0,
                score = 0
            })
        end
    end
    session.candidates = candidates
    if #candidates == 0 then
        session.candidateIndex = 1
    else
        session.candidateIndex = math.max(1, math.min(session.candidateIndex or 1, #candidates))
    end
    session.lastCandidateRefresh = GetGameTimer()
end

CreateThread(function()
    while true do
        if not editorActive then
            Wait(350)
        else
            Wait(0)
            local ped = PlayerPedId()
            local hit, hitCoords, _, entity, camCoord, dest = MZWE.RaycastFromCamera(Config.ViewDistance)
            local activeSelection = selectionSession

            if activeSelection then
                DisableControlAction(0, 44, true)
                DisableControlAction(0, Config.Keys.inspect, true)
                DisableControlAction(0, Config.Keys.exit, true)
                local refreshMs = tonumber(Config.Editor.selectorRefreshMs) or 120
                if GetGameTimer() - (activeSelection.lastCandidateRefresh or 0) >= refreshMs then
                    refreshSelectionCandidates(activeSelection, entity)
                end
                if IsDisabledControlJustPressed(0, 44) and #(activeSelection.candidates or {}) > 1 then
                    activeSelection.candidateIndex = (activeSelection.candidateIndex % #activeSelection.candidates) + 1
                end
                local selected = activeSelection.candidates[activeSelection.candidateIndex or 1]
                entity = selected and selected.entity or 0
            end

            local hasEntity = entity and entity ~= 0 and DoesEntityExist(entity) and entity ~= ped

            if activeSelection then
                if hasEntity then applySelectionOutline(entity) else clearSelectionOutline() end
            elseif selectionOutlinedEntity then
                clearSelectionOutline()
            end

            local exitPressed = activeSelection
                and IsDisabledControlJustPressed(0, Config.Keys.exit)
                or IsControlJustPressed(0, Config.Keys.exit)
            if exitPressed then
                if selectionSession then
                    finishSelection(nil, 'cancelled')
                else
                    editorActive = false
                    MZWE.Notify('Editor desativado.', 'info')
                end
            end

            local lines
            if activeSelection then
                lines = {
                    '~b~' .. activeSelection.title .. '~s~',
                    ('~c~Ja selecionadas: %d/%d~s~'):format(
                        activeSelection.selectedCount, activeSelection.requiredCount
                    ),
                    ('~c~Centralize o alvo (%s) no reticulo.~s~'):format(activeSelection.targetLabel),
                    '~g~E~s~ Confirmar alvo | ~y~Q~s~ Alternar alvo',
                    '~g~BACKSPACE~s~ Cancelar'
                }
            else
                lines = {
                    '~b~MZ World Editor~s~',
                    ('ACE: ~y~%s~s~'):format(Config.AdminAce),
                    '~g~E~s~ Inspecionar | ~g~G~s~ Criar porta | ~g~H~s~ Criar prop',
                    '~g~F~s~ Congelar local | ~g~BACKSPACE~s~ Sair'
                }
            end

            if activeSelection then
                MZWE.DrawSelectorReticle(hasEntity)
            elseif hit then
                DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.08, 0.08, 0.08, Config.Colors.marker.r, Config.Colors.marker.g, Config.Colors.marker.b, Config.Colors.marker.a, false, false, 2, false, nil, nil, false)

                if Config.Editor.drawAimLine then
                    DrawLine(camCoord.x, camCoord.y, camCoord.z, hitCoords.x, hitCoords.y, hitCoords.z, Config.Colors.line.r, Config.Colors.line.g, Config.Colors.line.b, Config.Colors.line.a)
                end
            else
                if Config.Editor.drawAimLine then
                    DrawLine(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, Config.Colors.line.r, Config.Colors.line.g, Config.Colors.line.b, 90)
                end
            end

            if hasEntity then
                lastEntity = entity
                local preview = MZWE.BuildEntityPreviewData(entity)

                if not activeSelection and Config.Editor.drawEntityBox then
                    MZWE.DrawEntityBox(entity, Config.Colors.box)
                end

                lines[#lines + 1] = ' '
                if preview then
                    if activeSelection then
                        local candidateCount = #(activeSelection.candidates or {})
                        local candidateIndex = activeSelection.candidateIndex or 1
                        local modelText = preview.model_name or ('hash ' .. tostring(MZWE.TryGetModelHash(entity) or '?'))
                        local distance = #(GetEntityCoords(ped) - GetEntityCoords(entity))
                        lines[#lines + 1] = ('Alvo ~y~%d/%d~s~: ~y~%s~s~'):format(
                            candidateIndex, candidateCount, modelText
                        )
                        lines[#lines + 1] = ('Distancia: ~y~%.2fm~s~ | heading: ~y~%.2f~s~'):format(
                            distance, preview.heading
                        )
                        local center = MZWE.GetEntityVisualCenter(entity)
                        if center then
                            MZWE.DrawText3D(
                                vector3(center.x, center.y, center.z + 0.18),
                                ('~g~[E]~s~ Selecionar %s'):format(activeSelection.targetLabel)
                            )
                        end
                    else
                        lines[#lines + 1] = ('Tipo: ~y~%s~s~ | Entity: ~y~%s~s~'):format(MZWE.EntityTypeName(preview.entity_type), preview.entity)
                    end
                    lines[#lines + 1] = ('Coords: ~y~%.2f %.2f %.2f~s~ | H: ~y~%.2f~s~'):format(preview.coords.x, preview.coords.y, preview.coords.z, preview.heading)
                    if not activeSelection then
                        lines[#lines + 1] = '~c~Aperte E/G/H para ler hash/modelo somente sob demanda.~s~'
                    end
                else
                    lines[#lines + 1] = '~r~Entidade detectada, mas preview invalido.~s~'
                end

                local inspectPressed = activeSelection
                    and IsDisabledControlJustPressed(0, Config.Keys.inspect)
                    or IsControlJustPressed(0, Config.Keys.inspect)
                if inspectPressed then
                    local data, err = MZWE.BuildEntityData(entity)
                    if not data then
                        MZWE.Notify(('Nao consegui ler o modelo da entidade: %s'):format(tostring(err)), 'error')
                    elseif activeSelection then
                        if activeSelection.objectsOnly and data.entity_type ~= 3 then
                            MZWE.Notify('Selecione um objeto/prop.', 'error')
                        else
                            finishSelection(data)
                        end
                    else
                        MZWE.PrintEntityData(data)
                        TriggerServerEvent('mz_world_editor:server:logAction', 'inspect', data)
                    end
                elseif not selectionSession and IsControlJustPressed(0, Config.Keys.createDoor) then
                    createDoor(entity)
                elseif not selectionSession and IsControlJustPressed(0, Config.Keys.createProp) then
                    createProp(entity)
                elseif not selectionSession and IsControlJustPressed(0, Config.Keys.freeze) then
                    toggleFreeze(entity)
                end
            else
                lastEntity = nil
                lines[#lines + 1] = ' '
                lines[#lines + 1] = '~r~Nenhuma entidade valida na mira.~s~'
            end

            MZWE.DrawPanel(lines)
        end
    end
end)

CreateThread(function()
    while true do
        local session = placementSession
        if not session then
            Wait(250)
        else
            Wait(0)
            local entity = session.entity
            if not entity or not DoesEntityExist(entity) then
                finishPlacement(nil, 'ghost_lost')
            else
                for _, control in ipairs({
                    1, 2, 24, 25, 30, 31, 32, 33, 34, 35, 44, 45,
                    174, 175, 14, 15, 10, 11, 21, 36, 47, 73,
                    Config.Keys.inspect, Config.Keys.exit
                }) do
                    DisableControlAction(0, control, true)
                end

                local fast = IsDisabledControlPressed(0, 21)
                local precise = IsDisabledControlPressed(0, 36)
                local multiplier = fast and (Config.Editor.placementFastMultiplier or 3.0)
                    or precise and (Config.Editor.placementPrecisionMultiplier or 0.2)
                    or 1.0
                local moveStep = (Config.Editor.placementMoveSpeed or 2.0) * multiplier * GetFrameTime()
                local rotateStep = (Config.Editor.placementRotationStep or 5.0) * multiplier
                local cameraSensitivity = tonumber(Config.Editor.placementCameraSensitivity) or 160.0
                session.cameraYaw = (session.cameraYaw or 0.0)
                    - (GetDisabledControlNormal(0, 1) * cameraSensitivity)
                session.cameraPitch = math.max(
                    Config.Editor.placementCameraMinPitch or -70.0,
                    math.min(
                        Config.Editor.placementCameraMaxPitch or -8.0,
                        (session.cameraPitch or -20.0)
                            - (GetDisabledControlNormal(0, 2) * cameraSensitivity)
                    )
                )

                local cameraYawRadians = math.rad(session.cameraYaw)
                local cameraForward = vector3(
                    -math.sin(cameraYawRadians),
                    math.cos(cameraYawRadians),
                    0.0
                )
                local cameraRight = vector3(cameraForward.y, -cameraForward.x, 0.0)
                local movement = vector3(0.0, 0.0, 0.0)

                if IsDisabledControlPressed(0, 32) then movement = movement + cameraForward end
                if IsDisabledControlPressed(0, 33) then movement = movement - cameraForward end
                if IsDisabledControlPressed(0, 34) then movement = movement - cameraRight end
                if IsDisabledControlPressed(0, 35) then movement = movement + cameraRight end
                if movement.x ~= 0.0 or movement.y ~= 0.0 then
                    session.position = session.position + (movement * moveStep)
                end

                if session.fullRotation and IsDisabledControlJustPressed(0, 44) then
                    session.rotationAxis = session.rotationAxis == 'z' and 'x'
                        or session.rotationAxis == 'x' and 'y' or 'z'
                end
                local rotationDelta = IsDisabledControlJustPressed(0, 174) and rotateStep
                    or IsDisabledControlJustPressed(0, 175) and -rotateStep or nil
                if rotationDelta then
                    if session.fullRotation and session.rotationAxis == 'x' then
                        session.rotation.x = (tonumber(session.rotation.x) or 0.0) + rotationDelta
                    elseif session.fullRotation and session.rotationAxis == 'y' then
                        session.rotation.y = (tonumber(session.rotation.y) or 0.0) + rotationDelta
                    else
                        session.heading = session.heading + rotationDelta
                    end
                end
                local heightStep = (Config.Editor.placementHeightSpeed or 0.75)
                    * multiplier * GetFrameTime()
                if IsDisabledControlPressed(0, 10) then
                    session.position = session.position + vector3(0.0, 0.0, heightStep)
                end
                if IsDisabledControlPressed(0, 11) then
                    session.position = session.position - vector3(0.0, 0.0, heightStep)
                end
                local minCameraDistance = tonumber(Config.Editor.placementCameraMinDistance) or 1.5
                local maxCameraDistance = tonumber(Config.Editor.placementCameraMaxDistance) or 12.0
                if IsDisabledControlJustPressed(0, 14) then
                    session.cameraDistance = math.max(minCameraDistance, session.cameraDistance - 0.4)
                end
                if IsDisabledControlJustPressed(0, 15) then
                    session.cameraDistance = math.min(maxCameraDistance, session.cameraDistance + 0.4)
                end
                if IsDisabledControlJustPressed(0, 45) then
                    local snapHit, snapCoords, snapNormal = MZWE.RaycastFromCamera(
                        math.max(Config.ViewDistance, 30.0), entity
                    )
                    if snapHit and snapCoords then
                        session.surfaceNormal = snapNormal
                        session.position = snapCoords + (snapNormal * (session.surfaceOffset or 0.0))
                        if session.surfaceSnap then
                            local aligned = surfaceRotation(
                                snapNormal,
                                session.surfaceRotationOffset,
                                session.heading
                            )
                            session.rotation.x, session.rotation.y, session.heading = aligned.x, aligned.y, aligned.z
                        end
                    end
                end
                if IsDisabledControlJustPressed(0, 73) then
                    session.rotation.x = tonumber(session.resetRotation.x) or 0.0
                    session.rotation.y = tonumber(session.resetRotation.y) or 0.0
                    session.heading = tonumber(session.resetRotation.z) or 0.0
                end

                session.heading = session.heading % 360.0
                SetEntityCoordsNoOffset(
                    entity,
                    session.position.x,
                    session.position.y,
                    session.position.z,
                    false, false, false
                )
                SetEntityRotation(
                    entity,
                    tonumber(session.rotation.x) or 0.0,
                    tonumber(session.rotation.y) or 0.0,
                    session.heading,
                    2,
                    true
                )
                if IsDisabledControlJustPressed(0, 47) then
                    PlaceObjectOnGroundProperly(entity)
                    local grounded = GetEntityCoords(entity)
                    session.position = vector3(grounded.x, grounded.y, grounded.z)
                end
                updatePlacementCamera(session)

                local coords = GetEntityCoords(entity)
                local rotation = GetEntityRotation(entity, 2)
                TriggerEvent('mz_world_editor:client:placementUpdated', session.requestId, {
                    coords = MZWE.VecToTable(coords),
                    rotation = MZWE.VecToTable(rotation),
                    heading = MZWE.Round(session.heading, 4),
                    surfaceNormal = session.surfaceNormal and MZWE.VecToTable(session.surfaceNormal) or nil
                })
                if session.validationRequired then
                    SetEntityDrawOutlineColor(
                        session.valid and 45 or 220,
                        session.valid and 210 or 55,
                        70,
                        220
                    )
                    SetEntityDrawOutline(entity, true)
                end
                MZWE.DrawPanel({
                    '~b~' .. session.title .. '~s~',
                    session.validationRequired and (
                        session.valid and '~g~Posicao valida~s~'
                        or ('~r~Posicao invalida: %s~s~'):format(
                            tostring(session.validationReason or 'aguarde')
                        )
                    ) or '~g~Preview livre~s~',
                    '~g~E~s~ Confirmar | ~g~BACKSPACE~s~ Cancelar',
                    '~g~W/A/S/D~s~ Mover | ~g~SHIFT~s~ Rapido | ~g~CTRL~s~ Preciso',
                    '~g~MOUSE~s~ Orbitar camera | ~g~SCROLL~s~ Zoom',
                    session.fullRotation
                        and ('~g~Q~s~ Eixo (%s) | ~g~SETA ESQ/DIR~s~ Girar | ~g~PGUP/PGDN~s~ Altura'):format(
                            tostring(session.rotationAxis or 'z'):upper()
                        )
                        or '~g~SETA ESQ/DIR~s~ Girar em passos | ~g~SEGURE PGUP/PGDN~s~ Altura',
                    '~y~R~s~ Mira | ~y~G~s~ Alinhar ao chao | ~y~X~s~ Resetar rotacao',
                    session.validationDetail and session.validationDetail.wallClearance
                        and ('Distancia livre: ~y~%.2f m~s~'):format(
                            tonumber(session.validationDetail.wallClearance) or 0.0
                        ) or ' ',
                    ('Coords: ~y~%.3f %.3f %.3f~s~'):format(coords.x, coords.y, coords.z),
                    ('Rotacao: ~y~%.2f %.2f %.2f~s~'):format(
                        tonumber(rotation.x) or 0.0,
                        tonumber(rotation.y) or 0.0,
                        tonumber(rotation.z) or session.heading
                    )
                })

                if IsDisabledControlJustPressed(0, Config.Keys.inspect) then
                    if session.validationRequired and session.valid ~= true then
                        MZWE.Notify(
                            ('Posicao invalida: %s'):format(
                                tostring(session.validationReason or 'fora dos limites')
                            ),
                            'error'
                        )
                    else
                        finishPlacement({
                            model_hash = session.modelHash,
                            model_name = session.modelName ~= '' and session.modelName or nil,
                            coords = MZWE.VecToTable(coords),
                            rotation = MZWE.VecToTable(rotation),
                            heading = MZWE.Round(session.heading, 4),
                            surfaceNormal = session.surfaceNormal and MZWE.VecToTable(session.surfaceNormal) or nil
                        })
                    end
                elseif IsDisabledControlJustPressed(0, Config.Keys.exit) then
                    finishPlacement(nil, 'cancelled')
                end
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        clearSelectionOutline()
        if selectionSession then finishSelection(nil, 'resource_stopped') end
        if placementSession then finishPlacement(nil, 'resource_stopped') end
    end
end)
