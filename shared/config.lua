Config = Config or {}

-- Permissao padrao confirmada pelo Mazus.
-- Em FiveM, o mais seguro é tratar `group.mz_owner` como grupo/principal
-- e criar uma permissao propria para o script, por exemplo `mz.world`.
Config.AdminAce = 'group.mz_owner'
Config.AdminAces = {
    'group.mz_owner',
    'mz.world',
    'sbstudio.open',
    'command'
}

Config.Command = 'mzworld'
Config.ViewDistance = 15.0
Config.EnableDebugPrint = true

-- Prioriza o mz_notify oficial; mz_menu e depois nativo/chat sao fallbacks.
Config.UseMzNotify = true
Config.UseMzMenuNotify = true
Config.UseChatNotify = true
Config.UseNativeNotify = true

Config.Keys = {
    inspect = 38,      -- E
    createDoor = 47,   -- G
    createProp = 74,   -- H
    freeze = 23,       -- F
    exit = 177         -- BACKSPACE
}

Config.DefaultDoor = {
    locked = true,
    distance = 2.0,
    ace_permission = 'group.mz_owner'
}

Config.DefaultProp = {
    frozen = true,
    collision = true,
    visible = true
}

Config.Editor = {
    allowFreezeEntity = true,
    allowCreateDoorFromObjectsOnly = true,
    allowCreatePropFromObjectsOnly = true,

    -- V5: desligado por padrão.
    -- O desenho da caixa precisava de GetEntityModel/GetModelDimensions em todo frame.
    -- Em algumas entidades do mundo, GetEntityModel pode falhar quando o handle do raycast
    -- fica instável/streamando. A linha e o marker continuam iguais.
    drawEntityBox = false,

    drawAimLine = true,
    selectorRefreshMs = 120,
    selectorScreenRadius = 0.16,
    selectorMaxCandidates = 10,
    selectorMaxDistance = 20.0,
    selectionOutline = {
        enabled = true,
        -- Amarelo forte para diferenciar claramente a folha sob a mira.
        color = { r = 255, g = 190, b = 35, a = 255 },
        shader = 1
    },

    placementMoveSpeed = 2.0,
    placementFastMultiplier = 3.0,
    placementPrecisionMultiplier = 0.2,
    placementRotateSpeed = 75.0,
    placementRotationStep = 5.0,
    placementHeightStep = 0.025,
    placementHeightSpeed = 0.75,
    placementCameraDistance = 4.5,
    placementCameraMinDistance = 1.5,
    placementCameraMaxDistance = 12.0,
    placementCameraSensitivity = 8.0,
    placementCameraMinPitch = -70.0,
    placementCameraMaxPitch = -8.0,

    -- V5: evita chamar GetEntityModel continuamente.
    -- O hash/modelo é lido somente quando apertar E/G/H.
    readModelEveryFrame = false
}

Config.Colors = {
    line = { r = 0, g = 200, b = 255, a = 200 },
    box = { r = 0, g = 200, b = 255, a = 255 },
    marker = { r = 0, g = 200, b = 255, a = 180 }
}
