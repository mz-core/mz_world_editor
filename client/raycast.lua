MZWE = MZWE or {}

local function rotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))

    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function activeCameraRotation()
    if type(GetFinalRenderedCamRot) == 'function' then
        local ok, rotation = pcall(GetFinalRenderedCamRot, 2)
        if ok and rotation then return rotation end
    end
    return GetGameplayCamRot(2)
end

local function activeCameraCoords()
    if type(GetFinalRenderedCamCoord) == 'function' then
        local ok, coords = pcall(GetFinalRenderedCamCoord)
        if ok and coords then return coords end
    end
    return GetGameplayCamCoord()
end

function MZWE.CameraDirection(flatten)
    local direction = rotationToDirection(activeCameraRotation())
    if flatten ~= true then return direction end
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    if length < 0.001 then return vector3(0.0, 1.0, 0.0) end
    return vector3(direction.x / length, direction.y / length, 0.0)
end

function MZWE.RaycastFromCamera(distance, ignoredEntity)
    local camCoord = activeCameraCoords()
    local camRot = activeCameraRotation()
    local direction = rotationToDirection(camRot)
    local dest = camCoord + (direction * (distance or Config.ViewDistance))

    local ray = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        -1,
        ignoredEntity or PlayerPedId(),
        7
    )
    local _, hit, endCoords, surfaceNormal, entity = GetShapeTestResult(ray)

    return hit == 1, endCoords, surfaceNormal, entity, camCoord, dest
end

function MZWE.FindObjectsNearCrosshair(maxDistance, screenRadius, maxResults)
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local candidates = {}
    local ok, objects = pcall(GetGamePool, 'CObject')
    if not ok or type(objects) ~= 'table' then return candidates end

    maxDistance = tonumber(maxDistance) or Config.ViewDistance
    screenRadius = tonumber(screenRadius) or 0.16
    maxResults = math.max(1, tonumber(maxResults) or 10)

    for _, entity in ipairs(objects) do
        if entity ~= 0 and DoesEntityExist(entity) then
            local origin = GetEntityCoords(entity)
            if #(playerCoords - origin) <= (maxDistance + 5.0) then
                local center = MZWE.GetEntityVisualCenter(entity)
                if center then
                    local distance = #(playerCoords - center)
                    if distance <= maxDistance then
                        local onScreen, screenX, screenY = World3dToScreen2d(center.x, center.y, center.z)
                        if onScreen then
                            local dx, dy = screenX - 0.5, screenY - 0.5
                            local screenDistance = math.sqrt(dx * dx + dy * dy)
                            if screenDistance <= screenRadius then
                                local lineOfSight = HasEntityClearLosToEntity(ped, entity, 17)
                                candidates[#candidates + 1] = {
                                    entity = entity,
                                    center = center,
                                    distance = distance,
                                    screenDistance = screenDistance,
                                    score = screenDistance + (distance * 0.0015) + (lineOfSight and 0.0 or 0.08)
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score == b.score then return a.entity < b.entity end
        return a.score < b.score
    end)
    while #candidates > maxResults do candidates[#candidates] = nil end
    return candidates
end
