-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- Player Variables
local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()

-- State Variables
local showESP = false -- Highlight para NPCs
local showPlayerESP = false -- Highlight para jogadores
local espRange = 150 -- Distância inicial do ESP (near)
local espRanges = {150, 300, 500} -- Near, Medium, Far
local espRangeIndex = 1 -- Índice inicial para a sequência de distâncias

-- ESP Variables (usando Highlight)
local espHighlights = {} -- Highlights para NPCs
local playerHighlights = {} -- Highlights para jogadores
local activeNPCTargets = {} -- NPCs ativos
local activePlayerTargets = {} -- Jogadores ativos
local npcTargets = {} -- Cache de alvos NPCs válidos
local lastNPCScan = 0
local SCAN_INTERVAL = 0.5 -- Intervalo de escaneamento em segundos

-- Atualiza personagem quando o jogador respawnar
local characterConnection = localPlayer.CharacterAdded:Connect(function(char)
    character = char
end)

-- Verifica se o modelo é um player
local function isPlayerModel(model)
    return Players:GetPlayerFromCharacter(model) ~= nil
end

-- Encontra a parte do peito ou alternativa
local function findChestPart(model)
    local possibleChestNames = {"HumanoidRootPart", "Torso", "torso", "TORSO", "Body", "Chest", "UpperTorso", "LowerTorso"}
    for _, name in ipairs(possibleChestNames) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

-- Verifica se o modelo tem características de um NPC/Mob
local function isValidNPCModel(model)
    if not model:IsA("Model") or model == character then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local healthValue = model:FindFirstChild("Health") or model:FindFirstChild("health")
    local hasParts = findChestPart(model)
    return (humanoid or healthValue) and hasParts and not isPlayerModel(model)
end

-- Verifica se o modelo está dentro da distância do ESP
local function isWithinESPRange(model)
    local root = findChestPart(model)
    if root and character.HumanoidRootPart then
        local distance = (root.Position - character.HumanoidRootPart.Position).Magnitude
        return distance <= espRange
    end
    return false
end

-- Escaneia o workspace para NPCs de forma otimizada
local function scanWorkspaceForNPCs()
    local newTargets = {}
    local function scanContainer(container)
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Model") and isValidNPCModel(obj) then
                local chest = findChestPart(obj)
                if chest then
                    newTargets[obj] = {Chest = chest}
                end
            elseif obj:IsA("Folder") or obj:IsA("Model") then
                scanContainer(obj) -- Recursivamente escaneia pastas ou modelos
            end
        end
    end

    scanContainer(Workspace)
    npcTargets = newTargets
end

-- Atualiza o cache quando NPCs são adicionados
local descendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
    if showESP and isValidNPCModel(descendant) and not isPlayerModel(descendant) then
        local chest = findChestPart(descendant)
        if chest then
            npcTargets[descendant] = {Chest = chest}
            updateNPCESP()
        end
    end
end)

-- Atualiza o cache quando NPCs são removidos
local descendantRemovingConnection = Workspace.DescendantRemoving:Connect(function(descendant)
    if npcTargets[descendant] then
        npcTargets[descendant] = nil
        if showESP then
            if espHighlights[descendant] then
                espHighlights[descendant]:Destroy()
                espHighlights[descendant] = nil
            end
            activeNPCTargets[descendant] = nil
        end
    end
end)

-- Retorna todos os NPCs válidos
local function getValidNPCTargets()
    local targets = {}
    for model, target in pairs(npcTargets) do
        if isWithinESPRange(model) and target.Chest.Parent then
            table.insert(targets, target)
        else
            npcTargets[model] = nil -- Remove se inválido
        end
    end
    return targets
end

-- Retorna todos os jogadores válidos
local function getValidPlayerTargets()
    local targets = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and isWithinESPRange(player.Character) then
            local chest = findChestPart(player.Character)
            if chest then
                table.insert(targets, {Chest = chest})
            end
        end
    end
    return targets
end

-- Cria um novo Highlight para NPCs (vermelho saturado)
local function createNPCHighlight()
    local highlight = Instance.new("Highlight")
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0) -- Vermelho saturado
    highlight.OutlineTransparency = 0
    highlight.FillTransparency = 1
    highlight.Enabled = false
    return highlight
end

-- Cria um novo Highlight para jogadores (verde saturado ou vermelho saturado)
local function createPlayerHighlight(isTeam)
    local highlight = Instance.new("Highlight")
    highlight.OutlineColor = isTeam and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0) -- Verde para equipe, vermelho para não-equipe
    highlight.OutlineTransparency = 0
    highlight.FillTransparency = 1
    highlight.Enabled = false
    return highlight
end

-- Limpa todos os highlights de NPCs
local function clearNPCHighlights()
    for _, highlight in pairs(espHighlights) do
        highlight:Destroy()
    end
    espHighlights = {}
    activeNPCTargets = {}
end

-- Limpa todos os highlights de jogadores
local function clearPlayerHighlights()
    for _, highlight in pairs(playerHighlights) do
        highlight:Destroy()
    end
    playerHighlights = {}
    activePlayerTargets = {}
end

-- Verifica se é do mesmo time
local function isSameTeam(model)
    local player = Players:GetPlayerFromCharacter(model)
    if player then
        return player.Team == localPlayer.Team
    end
    return false
end

-- Atualiza o ESP para NPCs
local lastNPCUpdate = 0
local UPDATE_INTERVAL = 0.1 -- Intervalo de atualização em segundos
local function updateNPCESP()
    if not showESP then
        clearNPCHighlights()
        return
    end

    local currentTime = tick()
    if currentTime - lastNPCUpdate < UPDATE_INTERVAL then
        return
    end
    lastNPCUpdate = currentTime

    local targets = getValidNPCTargets()
    local newActiveTargets = {}

    for _, target in ipairs(targets) do
        local model = target.Chest.Parent
        local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("Health")
        local root = findChestPart(model)

        if (humanoid or model:FindFirstChild("Health")) and root then
            newActiveTargets[model] = true
            local highlight = espHighlights[model]
            if not highlight then
                highlight = createNPCHighlight()
                highlight.Adornee = model
                highlight.Parent = model
                espHighlights[model] = highlight
            end
            highlight.Enabled = true
        end
    end

    for model, highlight in pairs(espHighlights) do
        if not newActiveTargets[model] then
            highlight:Destroy()
            espHighlights[model] = nil
        end
    end

    activeNPCTargets = newActiveTargets
end

-- Atualiza o ESP para jogadores
local function updatePlayerESP()
    if not showPlayerESP then
        clearPlayerHighlights()
        return
    end

    local targets = getValidPlayerTargets()
    local newActiveTargets = {}

    for _, target in ipairs(targets) do
        local model = target.Chest.Parent
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = findChestPart(model)

        if humanoid and root then
            newActiveTargets[model] = true
            local highlight = playerHighlights[model]
            if not highlight then
                local isTeam = isSameTeam(model)
                highlight = createPlayerHighlight(isTeam)
                highlight.Adornee = model
                highlight.Parent = model
                playerHighlights[model] = highlight
            end
            highlight.Enabled = true
        end
    end

    for model, highlight in pairs(playerHighlights) do
        if not newActiveTargets[model] then
            highlight:Destroy()
            playerHighlights[model] = nil
        end
    end

    activePlayerTargets = newActiveTargets
end

-- Loop principal para atualizar ESP
local renderSteppedConnection = game:GetService("RunService").RenderStepped:Connect(function()
    local currentTime = tick()
    if currentTime - lastNPCScan >= SCAN_INTERVAL then
        scanWorkspaceForNPCs()
        lastNPCScan = currentTime
    end

    updateNPCESP()
    updatePlayerESP()
end)

-- Monitorar novos jogadores
local playerAddedConnection = Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        player.CharacterAdded:Connect(function(char)
            if showPlayerESP then
                updatePlayerESP()
            end
        end)
    end
end)

-- Inicializa o escaneamento de NPCs
scanWorkspaceForNPCs()

-- Função para encerrar o script
local function terminateScript()
    -- Desconectar todos os eventos
    if renderSteppedConnection then
        renderSteppedConnection:Disconnect()
        renderSteppedConnection = nil
    end
    if characterConnection then
        characterConnection:Disconnect()
        characterConnection = nil
    end
    if descendantAddedConnection then
        descendantAddedConnection:Disconnect()
        descendantAddedConnection = nil
    end
    if descendantRemovingConnection then
        descendantRemovingConnection:Disconnect()
        descendantRemovingConnection = nil
    end
    if playerAddedConnection then
        playerAddedConnection:Disconnect()
        playerAddedConnection = nil
    end
    if inputBeganConnection then
        inputBeganConnection:Disconnect()
        inputBeganConnection = nil
    end

    -- Limpar highlights
    clearNPCHighlights()
    clearPlayerHighlights()

    -- Limpar caches
    npcTargets = {}
    activeNPCTargets = {}
    activePlayerTargets = {}
end

-- Teclas de controle
local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.K then -- Highlight para NPCs e ciclo de distância
        if showESP and espRangeIndex == #espRanges then
            showESP = false
            clearNPCHighlights()
        else
            showESP = true
            espRangeIndex = espRangeIndex % #espRanges + 1
            espRange = espRanges[espRangeIndex]
        end
    end

    if input.KeyCode == Enum.KeyCode.L then -- Highlight para jogadores e ciclo de distância
        if showPlayerESP and espRangeIndex == #espRanges then
            showPlayerESP = false
            clearPlayerHighlights()
        else
            showPlayerESP = true
            espRangeIndex = espRangeIndex % #espRanges + 1
            espRange = espRanges[espRangeIndex]
        end
    end

    if input.KeyCode == Enum.KeyCode.PageDown then -- Encerrar o script
        terminateScript()
    end
end)
