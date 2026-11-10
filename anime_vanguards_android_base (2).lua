-- BOOTSTRAP AV Mobile 0.6: código local completo, sem downloads.
-- A mesma fonte é usada para continuar após teleporte quando a opção estiver ligada.
local source = [====[
return function(SOURCE, resumed)
-- AV Mobile Base 0.6 | Lua/Luau | opções de entrada e Auto Play nativo.
-- Rota: Play > Event Modes > Trail of the Saint > Infinite > Start (se necessário).
-- Navegação por textos da interface. Não contém caminhos/remotes inventados.
-- Não implementa colocação, upgrades, farm próprio ou anti-ban.
-- Auto Play é conferido pelo texto Auto Playing e rearmado após nova run.
-- Os textos/valores são lidos em Instances; não há OCR ou imagens de referência.
-- Autoexecução após teleporte depende de queue_on_teleport no executor.
-- Marcar um ponto NÃO coloca uma unidade nem registra uma colocação do jogo.
-- Compatibilidade com Delta/Android ainda precisa ser testada no dispositivo.
-- Não baixa nem executa código externo. Arquivos locais são opcionais.
-- APIs de toque/câmera: https://create.roblox.com/docs/reference/engine/classes/UserInputService
-- https://create.roblox.com/docs/reference/engine/classes/Camera

local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local World = game:GetService("Workspace")
local player = Players.LocalPlayer
assert(player, "Execute no cliente, depois de entrar no jogo.")
local playerGui = player:WaitForChild("PlayerGui", 15)
assert(playerGui, "PlayerGui não ficou disponível.")

local GUI_NAME = "AVMobileBase_01"
local FILE_NAME = "av_mobile_base_01_" .. tostring(game.PlaceId) .. ".json"
local MAX_POINTS = 100
-- CARD_CONFIG: validação compartilhada entre perfil, teleporte e editor.
local function cardNameKey(value)
    return (tostring(value):gsub("<[^>]*>", ""):lower():gsub("[^%w]", ""))
end
local function copyNames(names)
    local result = {}
    for i, name in ipairs(names) do result[i] = name end
    return result
end
local function validateNames(names)
    assert(type(names) == "table", "A lista de cards deve ser uma lista.")
    local count = 0
    for key in pairs(names) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= 32,
            "Lista de cards inválida ou com mais de 32 itens.")
        count = count + 1
    end
    local result, seen = {}, {}
    for i = 1, count do
        local name = names[i]
        assert(type(name) == "string", "Nome de card inválido.")
        name = name:match("^%s*(.-)%s*$")
        local key = cardNameKey(name)
        assert(#name <= 64 and key ~= "", "Use um nome de card entre 1 e 64 bytes.")
        assert(not seen[key], "Card repetido: " .. name)
        result[i], seen[key] = name, true
    end
    return result
end
local function validateCardConfig(config)
    assert(type(config) == "table", "Configuração de cards inválida.")
    assert(config.mode == "fixed" or config.mode == "waves10", "Modo de cards inválido.")
    assert(type(config.bands) == "table", "Faixas de waves inválidas.")
    local bands, count = {}, 0
    for key, names in pairs(config.bands) do
        local first = tonumber(key)
        assert(first and first >= 1 and first <= 999991 and first % 10 == 1,
            "A faixa deve começar em 1, 11, 21, 31…")
        local canonical = tostring(first)
        assert(not bands[canonical], "Faixa repetida.")
        count = count + 1
        assert(count <= 100, "Limite de 100 faixas personalizadas.")
        bands[canonical] = validateNames(names)
    end
    return {enabled = config.enabled == true, mode = config.mode,
        fixed = validateNames(config.fixed), bands = bands}
end
local function activeCardList(config, wave)
    if config.mode == "fixed" then return config.fixed, "ordem fixa" end
    if type(wave) ~= "number" or wave ~= wave or wave < 1 or wave > 1000000 then return nil, "wave não identificada" end
    local lastFirst = 1
    for key in pairs(config.bands) do lastFirst = math.max(lastFirst, tonumber(key)) end
    local cycleLength = lastFirst + 9
    local cycleWave = (wave - 1) % cycleLength + 1
    local first = math.floor((cycleWave - 1) / 10) * 10 + 1
    local key = tostring(first)
    local custom = config.bands[key]
    return custom or config.fixed, "faixa " .. first .. "–" .. (first + 9) .. " · ciclo de " .. cycleLength
        .. (custom and "" or " (usando a fixa)")
end
local function bestCard(available, priorities)
    if not priorities then return nil end
    for _, wanted in ipairs(priorities) do
        for _, card in ipairs(available) do
            if cardNameKey(card.name) == cardNameKey(wanted) then return card end
        end
    end
end
-- END_CARD_CONFIG
-- RUN_CONFIG: opções locais e validação do destino do relatório.
local Runtime = {}
function Runtime.webhookURL(value)
    if type(value) ~= "string" or #value > 512 then return nil end
    local url = value:match("^%s*(.-)%s*$")
    local host, path = url:match("^https://([^/]+)(/[^%s]+)$")
    local allowed = {['discord.com'] = true, ['discordapp.com'] = true,
        ['canary.discord.com'] = true, ['ptb.discord.com'] = true}
    if not host or not allowed[host:lower()] then return nil end
    local base = path:match("^[^?]+")
    local query = path:match("%?(.*)$")
    if query and not query:match("^thread_id=%d+$") then return nil end
    if not base:match("^/api/webhooks/%d+/[%w_%-]+$")
        and not base:match("^/api/v%d+/webhooks/%d+/[%w_%-]+$") then return nil end
    return url
end
function Runtime.settings(value)
    value = type(value) == "table" and value or {}
    local url = value.webhookURL or ""
    assert(type(url) == "string", "URL do webhook inválida.")
    if url ~= "" then url = assert(Runtime.webhookURL(url), "Use uma URL válida de webhook do Discord.") end
    assert(not value.webhookEnabled or url ~= "", "Configure a URL antes de ativar o webhook.")
    return {antiAfk = value.antiAfk == true, autoRestart = value.autoRestart == true,
        webhookEnabled = value.webhookEnabled == true, webhookURL = url}
end
function Runtime.requestFunction()
    if type(request) == "function" then return request end
    if type(http_request) == "function" then return http_request end
    if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
end
-- END_RUN_CONFIG
local old = playerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local connections = {}
local cardRowConnections = {}
local stopped = false
local state = {
    slot = 1, mode = "repeat", points = {}, armed = false, preview = true,
    autoEnter = false, autoPlay = false, autoExecute = false,
    safety = Runtime.settings(),
    cards = {enabled = false, mode = "fixed", bands = {}, fixed = {
        "New Unit", "Nightmare Boss", "Monarch", "Nightmare Armor", "Nightmare Health", "Nightmare Speed",
    }},
}
if type(resumed) == "table" then
    state.autoEnter = resumed.autoEnter == true
    state.autoPlay = resumed.autoPlay == true
    state.autoExecute = resumed.autoExecute == true
    if resumed.safety then
        local ok, safety = pcall(Runtime.settings, resumed.safety)
        if ok then state.safety = safety end
    end
    if resumed.cards then
        local ok, config = pcall(validateCardConfig, resumed.cards)
        if ok then state.cards = config end
    end
end
local routeToken, routeBusy, routeDone = 0, false, false
local autoPlayBusy = false
local cardBusy, cardToken, observedWave = false, 0, nil
local cardSession
local renderCardEditor, refreshCardOptions
local refreshRunOptions
local queueTeleport = type(queue_on_teleport) == "function" and queue_on_teleport
    or (type(queueonteleport) == "function" and queueonteleport or nil)
if not queueTeleport then state.autoExecute = false end
local theme = {
    bg = Color3.fromRGB(14, 14, 13), card = Color3.fromRGB(26, 25, 23),
    text = Color3.fromRGB(241, 242, 247), muted = Color3.fromRGB(145, 152, 171),
    accent = Color3.fromRGB(247, 141, 40),
}

local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    if class == "TextBox" then
        local corner = Instance.new("UICorner")
        corner.CornerRadius, corner.Parent = UDim.new(0, 8), object
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
        padding.Parent = object
    end
    return object
end

local function watch(signal, fn)
    local connection = signal:Connect(fn)
    connections[#connections + 1] = connection
    return connection
end

local gui = make("ScreenGui", {
    Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = false,
    DisplayOrder = 80, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local area = make("Frame", {
    Name = "Area", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
}, gui)
local panel = make("Frame", {
    Name = "Painel", BackgroundColor3 = theme.bg, BorderSizePixel = 0,
    Position = UDim2.fromOffset(72, 12), Size = UDim2.fromOffset(360, 500),
    Active = true,
}, area)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, panel)
make("UIStroke", {Color = Color3.fromRGB(60, 64, 80), Thickness = 1, Transparency = 0.3}, panel)
local floating = make("TextButton", {
    Name = "AbrirMenu", Text = "AV", Size = UDim2.fromOffset(52, 52),
    Position = UDim2.fromOffset(10, 12), BackgroundColor3 = theme.accent,
    TextColor3 = theme.text, TextSize = 18, Font = Enum.Font.GothamBold,
    BorderSizePixel = 0, ZIndex = 5,
}, area)
make("UICorner", {CornerRadius = UDim.new(1, 0)}, floating)

local header = make("Frame", {
    Name = "Arrastar", BackgroundTransparency = 1, Active = true,
    Size = UDim2.new(1, -100, 0, 48),
}, panel)
make("TextLabel", {
    Text = "NANO HUB  /  VANGUARDS", BackgroundTransparency = 1,
    Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -48, 1, 0),
    TextColor3 = theme.text, Font = Enum.Font.GothamBold, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local minimize = make("TextButton", {
    Text = "−", Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -94, 0, 4),
    BackgroundTransparency = 1, TextColor3 = theme.text, TextSize = 26,
}, panel)
local close = make("TextButton", {
    Text = "×", Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -48, 0, 4),
    BackgroundTransparency = 1, TextColor3 = theme.text, TextSize = 26,
}, panel)
-- Navegação lateral inspirada na referência; compacta em telas estreitas.
local UI = {pages = {}, tabs = {}, markers = {}, selected = "Início", compact = false,
    names = {['Início'] = 'Home', Partida = 'Join', ['Auto Play'] = 'Auto Play',
        Cards = 'Priority', Continuidade = 'Session', Webhook = 'Webhook', Unidades = 'Units', Perfil = 'Settings'}}
UI.nav = make("ScrollingFrame", {BackgroundColor3 = Color3.fromRGB(19, 18, 16),
    BorderSizePixel = 0, Position = UDim2.fromOffset(10, 68), Size = UDim2.new(0, 156, 1, -84),
    CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 2, ScrollBarImageColor3 = theme.accent}, panel)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, UI.nav)
make("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, UI.nav)
make("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8)}, UI.nav)
for index, name in ipairs({"Início", "Partida", "Auto Play", "Cards", "Continuidade", "Webhook", "Unidades", "Perfil"}) do
    local pageName = name
    local page = make("ScrollingFrame", {
        Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = index == 1,
        Position = UDim2.fromOffset(184, 70), Size = UDim2.new(1, -202, 1, -148),
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = theme.accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, panel)
    make("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, page)
    make("UIPadding", {PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 6)}, page)
    local tab = make("TextButton", {Text = UI.names[name], LayoutOrder = index,
        Size = UDim2.new(1, -12, 0, 44), BackgroundColor3 = Color3.fromRGB(19, 18, 16),
        BorderSizePixel = 0, TextColor3 = theme.muted, TextSize = 12,
        Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left}, UI.nav)
    make("UIPadding", {PaddingLeft = UDim.new(0, 14)}, tab)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, tab)
    UI.markers[name] = make("Frame", {BackgroundColor3 = theme.accent, BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 3, 1, -20), Visible = index == 1}, tab)
    UI.pages[name], UI.tabs[name] = page, tab
    watch(tab.Activated, function() UI.select(pageName) end)
end
function UI.select(name)
    UI.selected = name
    for key, page in pairs(UI.pages) do
        page.Visible = key == name
        UI.tabs[key].BackgroundColor3 = key == name and Color3.fromRGB(38, 30, 22) or Color3.fromRGB(19, 18, 16)
        UI.tabs[key].TextColor3 = key == name and theme.accent or theme.muted
        UI.markers[key].Visible = key == name
    end
end
function UI.layout(width)
    local narrow = width < 480
    local side = (UI.compact or narrow) and 54 or 148
    UI.nav.Size = UDim2.new(0, side, 1, -84)
    for key, page in pairs(UI.pages) do
        page.Position = UDim2.fromOffset(side + 26, 68)
        page.Size = UDim2.new(1, -side - 44, 1, -146)
        UI.tabs[key].Text = (UI.compact or narrow) and UI.names[key]:sub(1, 2):upper() or UI.names[key]
    end
    if UI.status then
        UI.status.Position = UDim2.new(0, side + 26, 1, -68)
        UI.status.Size = UDim2.new(1, -side - 44, 0, 56)
    end
end
UI.menu = make("TextButton", {Text = "≡", BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(36, 40),
    TextColor3 = theme.accent, TextSize = 24}, panel)
watch(UI.menu.Activated, function() UI.compact = not UI.compact; UI.layout(panel.AbsoluteSize.X) end)
local body = UI.pages.Partida
function UI.build(name) body = UI.pages[name] end
UI.select("Início")
local status = make("TextLabel", {
    Text = "Pronto · Escolha uma aba para configurar.",
    BackgroundColor3 = theme.card, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -68), Size = UDim2.new(1, -24, 0, 56),
    TextColor3 = theme.text, Font = Enum.Font.Gotham, TextSize = 12,
    TextWrapped = true,
}, panel)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, status)
UI.status = status

local order = 0
local function text(message, height)
    order = order + 1
    return make("TextLabel", {
        Text = message, Size = UDim2.new(1, 0, 0, height or 40), LayoutOrder = order,
        BackgroundTransparency = 1, TextColor3 = theme.muted,
        Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, body)
end
local function button(message, fn)
    order = order + 1
    local object = make("TextButton", {
        Text = message, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = theme.card, BorderSizePixel = 0, TextColor3 = theme.text,
        Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextTransparency = 1,
    }, body)
    make("UICorner", {CornerRadius = UDim.new(0, 8)}, object)
    make("UIStroke", {Color = Color3.fromRGB(46, 51, 65), Thickness = 1, Transparency = 0.45}, object)
    local title = make("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -88, 1, 0), TextColor3 = theme.text, TextSize = 12,
        Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left}, object)
    local badge = make("TextLabel", {BackgroundColor3 = Color3.fromRGB(37, 41, 53),
        Position = UDim2.new(1, -62, 0.5, -13), Size = UDim2.fromOffset(48, 26),
        TextColor3 = theme.muted, TextSize = 10, Font = Enum.Font.GothamBold}, object)
    make("UICorner", {CornerRadius = UDim.new(0, 7)}, badge)
    local function repaint()
        local value = object.Text
        local off = value:find("DESLIGAD", 1, true) ~= nil
        local on = not off and value:find("LIGAD", 1, true) ~= nil
        title.Text = value:gsub(":%s*DESLIGAD[OA]$", ""):gsub(":%s*LIGAD[OA]$", "")
        badge.Text = on and "ON" or (off and "OFF" or "›")
        badge.TextSize = (on or off) and 10 or 22
        badge.TextColor3 = on and theme.accent or theme.muted
        badge.BackgroundColor3 = on and Color3.fromRGB(59, 39, 22) or Color3.fromRGB(37, 41, 53)
    end
    watch(object:GetPropertyChangedSignal("Text"), repaint)
    repaint()
    watch(object.Activated, function() if not stopped then fn() end end)
    return object
end
function UI.section(title, subtitle)
    local label = text(title, 28)
    label.Font, label.TextSize, label.TextColor3 = Enum.Font.GothamBold, 18, theme.text
    if subtitle then text(subtitle, 40) end
end
local function notify(message) if not stopped then status.Text = message end end

-- Mantém o painel dentro da área útil ao girar o aparelho.
local function clampPosition(object, x, y)
    local available = area.AbsoluteSize
    local size = object.AbsoluteSize
    object.Position = UDim2.fromOffset(
        math.clamp(x, 0, math.max(0, available.X - size.X)),
        math.clamp(y, 0, math.max(0, available.Y - size.Y)))
end
local function resize()
    local available = area.AbsoluteSize
    if available.X < 100 or available.Y < 150 then return end
    panel.Size = UDim2.fromOffset(math.min(820, available.X - 20), math.min(590, available.Y - 20))
    UI.layout(math.min(820, available.X - 20))
    clampPosition(panel, panel.Position.X.Offset, panel.Position.Y.Offset)
    clampPosition(floating, floating.Position.X.Offset, floating.Position.Y.Offset)
end
local function draggable(handle, target, tapped)
    local pointer, origin, original, moved
    watch(handle.InputBegan, function(input)
        local kind = input.UserInputType
        if pointer or (kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1) then return end
        pointer, origin, original, moved = input, input.Position, target.Position, false
    end)
    watch(Input.InputChanged, function(input)
        if not pointer then return end
        local mouse = pointer.UserInputType == Enum.UserInputType.MouseButton1
        if input ~= pointer and not (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
        local delta = input.Position - origin
        if delta.Magnitude > 6 then moved = true end
        if moved then clampPosition(target, original.X.Offset + delta.X, original.Y.Offset + delta.Y) end
    end)
    watch(Input.InputEnded, function(input)
        if input ~= pointer then return end
        local clicked = not moved
        pointer = nil
        if clicked and tapped then tapped() end
    end)
end
draggable(header, panel)
draggable(floating, floating, function() panel.Visible = not panel.Visible end)
watch(minimize.Activated, function() panel.Visible = false end)
watch(close.Activated, function() gui:Destroy() end)
watch(area:GetPropertyChangedSignal("AbsoluteSize"), resize)

local markers = make("Folder", {Name = "AVMobilePontosLocais"}, World)
local function cleanup()
    if stopped then return end
    stopped = true
    routeToken = routeToken + 1
    if Runtime.leafConnection then Runtime.leafConnection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, connection in ipairs(cardRowConnections) do connection:Disconnect() end
    markers:Destroy()
end
watch(gui.Destroying, cleanup)

local countLabel
local function showPoints()
    markers:ClearAllChildren()
    countLabel.Text = tostring(#state.points) .. " ponto(s) manual(is). Não são unidades do jogo."
    if not state.preview then return end
    for index, point in ipairs(state.points) do
        local sphere = make("Part", {
            Name = "Ponto_" .. tostring(index), Shape = Enum.PartType.Ball,
            Size = Vector3.new(0.6, 0.6, 0.6), Position = Vector3.new(point.x, point.y, point.z),
            Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
            CastShadow = false, Color = theme.accent, Transparency = 0.25,
            Material = Enum.Material.Neon,
        }, markers)
        local billboard = make("BillboardGui", {
            Size = UDim2.fromOffset(110, 26), StudsOffset = Vector3.new(0, 1, 0),
            AlwaysOnTop = true, MaxDistance = 300,
        }, sphere)
        make("TextLabel", {
            BackgroundColor3 = theme.bg, BackgroundTransparency = 0.15,
            Size = UDim2.fromScale(1, 1), TextColor3 = theme.text,
            TextSize = 12, Text = "#" .. index .. " · slot " .. point.slot,
        }, billboard)
    end
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1000000
end
local function encode()
    return Http:JSONEncode({version = 1, placeId = game.PlaceId, mode = state.mode,
        points = state.points, autoEnter = state.autoEnter,
        autoPlay = state.autoPlay, autoExecute = state.autoExecute, cards = state.cards, safety = state.safety})
end
local function decode(raw)
    assert(type(raw) == "string" and #raw <= 262144, "Perfil vazio ou grande demais.")
    local data = Http:JSONDecode(raw)
    assert(type(data) == "table" and data.version == 1, "Versão de perfil inválida.")
    assert(data.placeId == game.PlaceId, "O perfil pertence a outro lugar/mapa.")
    assert(data.mode == "repeat" or data.mode == "advance", "Modo inválido.")
    assert(type(data.points) == "table", "Lista de pontos inválida.")
    local size = 0
    for key in pairs(data.points) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= MAX_POINTS,
            "Índice de ponto inválido.")
        size = size + 1
    end
    local points = {}
    for index = 1, size do
        local p = data.points[index]
        assert(type(p) == "table", "Lista de pontos incompleta.")
        assert(type(p.slot) == "number" and p.slot % 1 == 0 and p.slot >= 1 and p.slot <= 6,
            "Slot inválido.")
        assert(finite(p.x) and finite(p.y) and finite(p.z), "Coordenada inválida.")
        points[index] = {slot = p.slot, x = p.x, y = p.y, z = p.z}
    end
    return data.mode, points, {
        autoEnter = data.autoEnter == true,
        autoPlay = data.autoPlay == true,
        autoExecute = data.autoExecute == true and queueTeleport ~= nil,
        cards = data.cards and validateCardConfig(data.cards) or nil,
        safety = data.safety and Runtime.settings(data.safety) or nil,
    }
end

-- NAVIGAÇÃO. As imagens fornecem os rótulos; a hierarquia real é lida no cliente.
-- Se o jogo não expuser esses textos ou o executor negar cliques, a rotina para.
local function normalize(value)
    return (tostring(value):gsub("<[^>]*>", ""):lower():gsub("[^%w]", ""))
end

local function shown(object, allowOffscreen)
    if not object:IsA("GuiObject") or object:IsDescendantOf(gui) then return false end
    local pos, size = object.AbsolutePosition, object.AbsoluteSize
    if size.X <= 1 or size.Y <= 1 then return false end
    local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
    local ancestor = object
    while ancestor and ancestor ~= playerGui do
        if ancestor:IsA("GuiObject") then
            if not ancestor.Visible then return false end
            if ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency >= 0.99 then return false end
            if not allowOffscreen and ancestor.ClipsDescendants then
                local p, s = ancestor.AbsolutePosition, ancestor.AbsoluteSize
                if x < p.X or y < p.Y or x > p.X + s.X or y > p.Y + s.Y then return false end
            end
        elseif ancestor:IsA("ScreenGui") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    if not allowOffscreen then
        local camera = World.CurrentCamera
        if not camera or x < 0 or y < 0 or x > camera.ViewportSize.X or y > camera.ViewportSize.Y then return false end
    end
    return ancestor == playerGui
end

local function labels(allowOffscreen)
    local result = {}
    for _, object in ipairs(playerGui:GetDescendants()) do
        if shown(object, allowOffscreen) then
            local content, raw = "", ""
            if object:IsA("TextLabel") or object:IsA("TextButton") then raw = object.Text; content = normalize(raw) end
            if content ~= "" or object:IsA("GuiButton") then
                result[#result + 1] = {object = object, content = content, raw = raw, name = normalize(object.Name)}
            end
        end
    end
    return result
end

local function findLabel(aliases, list)
    list = list or labels(false)
    -- Texto explícito tem prioridade sobre nomes internos.
    for _, alias in ipairs(aliases) do
        local wanted = normalize(alias)
        for _, entry in ipairs(list) do if entry.content == wanted then return entry.object end end
    end
    for _, alias in ipairs(aliases) do
        local wanted = normalize(alias)
        for _, entry in ipairs(list) do
            if entry.object:IsA("GuiButton") and entry.name == wanted then return entry.object end
        end
    end
end

local function mapReady(list)
    list = list or labels(false)
    local trail, infinite, hud = false, false, false
    for _, entry in ipairs(list) do
        trail = trail or entry.content:find("trailofthesaint", 1, true) ~= nil
        infinite = infinite or entry.content:find("infinite", 1, true) ~= nil
        hud = hud or entry.content == "autoplay" or entry.content == "autoplaying" or entry.content == "unitmanager"
    end
    return trail and infinite and hud
end

local function revealTrail()
    local object = findLabel({"Trail of the Saint"}, labels(true))
    if not object then return end
    local ancestor = object.Parent
    while ancestor and ancestor ~= playerGui do
        if ancestor:IsA("ScrollingFrame") then
            local pos = ancestor.CanvasPosition
            local offset = object.AbsolutePosition - ancestor.AbsolutePosition
            local maxX = math.max(0, ancestor.AbsoluteCanvasSize.X - ancestor.AbsoluteSize.X)
            local maxY = math.max(0, ancestor.AbsoluteCanvasSize.Y - ancestor.AbsoluteSize.Y)
            ancestor.CanvasPosition = Vector2.new(
                math.clamp(pos.X + offset.X - ancestor.AbsoluteSize.X / 2 + object.AbsoluteSize.X / 2, 0, maxX),
                math.clamp(pos.Y + offset.Y - ancestor.AbsoluteSize.Y / 2 + object.AbsoluteSize.Y / 2, 0, maxY))
        end
        ancestor = ancestor.Parent
    end
end

local function valid(token)
    return not stopped and state.autoEnter and token == routeToken
end
local function waitFor(token, seconds, predicate, message)
    local deadline = os.clock() + seconds
    while valid(token) do
        local result = predicate(labels(false))
        if result then return result end
        if os.clock() >= deadline then error("Tempo esgotado: " .. message, 0) end
        task.wait(0.5)
    end
    error("Rotina cancelada.", 0)
end

local function buttonTarget(object, preferRight)
    if not object then return nil end
    local ancestor = object
    while ancestor and ancestor ~= playerGui do
        if ancestor:IsA("GuiButton") then return ancestor end
        if ancestor:IsA("ScreenGui") then break end
        ancestor = ancestor.Parent
    end
    -- Alguns cartões deixam o rótulo como irmão do botão da imagem.
    ancestor = object.Parent
    for _ = 1, 3 do
        if not ancestor or not ancestor:IsA("GuiObject") then break end
        local candidates = {}
        for _, child in ipairs(ancestor:GetDescendants()) do
            if child:IsA("GuiButton") and shown(child, false) then candidates[#candidates + 1] = child end
        end
        if #candidates == 1 then return candidates[1] end
        -- Auto Play tem engrenagem à esquerda e acionamento à direita, na imagem fornecida.
        if preferRight and ancestor.AbsoluteSize.Y <= object.AbsoluteSize.Y * 4
            and ancestor.AbsoluteSize.X <= object.AbsoluteSize.X * 6 then
            local right, rightX
            local centerX = object.AbsolutePosition.X + object.AbsoluteSize.X / 2
            local centerY = object.AbsolutePosition.Y + object.AbsoluteSize.Y / 2
            for _, candidate in ipairs(candidates) do
                local p, s = candidate.AbsolutePosition, candidate.AbsoluteSize
                local x, y = p.X + s.X / 2, p.Y + s.Y / 2
                if x > centerX and math.abs(y - centerY) <= math.max(s.Y, object.AbsoluteSize.Y) / 2
                    and (not rightX or x > rightX) then right, rightX = candidate, x end
            end
            if right then return right end
        end
        ancestor = ancestor.Parent
    end
    return object
end
local clickBusy = false
-- Eventos reais do GuiButton quando expostos pelo executor; um evento por ação.
local function directButton(object)
    if not object:IsA("GuiButton") or type(firesignal) ~= "function" or type(getconnections) ~= "function" then return false end
    for _, name in ipairs({"MouseButton1Click", "Activated"}) do
        local signal = object[name]
        local ok, handlers = pcall(getconnections, signal)
        if ok and type(handlers) == "table" and #handlers > 0 then
            local fired
            if name == "Activated" then fired = pcall(firesignal, signal, nil, 1)
            else fired = pcall(firesignal, signal) end
            if fired then return true end
        end
    end
    return false
end
local function click(object, allowed, preferRight, exactTarget)
    if not exactTarget then object = buttonTarget(object, preferRight) end
    assert(object and allowed() and shown(object, false), "Alvo indisponível ou rotina cancelada.")
    while clickBusy and allowed() do task.wait(0.1) end
    assert(allowed(), "Rotina cancelada.")
    if directButton(object) then task.wait(0.6); return end
    local got, virtual = pcall(function() return game:GetService("VirtualInputManager") end)
    assert(got and virtual, "O executor não disponibilizou entrada virtual.")
    clickBusy = true
    local enabled = gui.Enabled
    gui.Enabled = false -- evita que nosso próprio menu intercepte o clique.
    local ok, err = pcall(function()
        task.wait(0.05)
        assert(allowed(), "Rotina cancelada.")
        local pos, size = object.AbsolutePosition, object.AbsoluteSize
        local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
        -- Confere a área do alvo; tenta também o deslocamento da barra superior.
        local inset = game:GetService("GuiService"):GetGuiInset()
        local positions = {{x, y}, {x + inset.X, y + inset.Y}}
        local found = false
        for _, position in ipairs(positions) do
            for _, hit in ipairs(playerGui:GetGuiObjectsAtPosition(position[1], position[2])) do
                if hit == object or hit:IsDescendantOf(object) then
                    x, y, found = position[1], position[2], true
                    break
                end
            end
            if found then break end
        end
        assert(found, "O alvo não está visível na área clicável.")
        local down, downError = pcall(function()
            virtual:SendMouseButtonEvent(x, y, 0, true, game, 0)
        end)
        task.wait(0.06)
        local up, upError = pcall(function()
            virtual:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        assert(down and up, "Clique virtual indisponível: " .. tostring(downError or upError))
    end)
    if gui.Parent then gui.Enabled = enabled end
    clickBusy = false
    assert(ok, tostring(err))
    task.wait(0.6)
end

local function enterMap(token)
    local function active() return valid(token) end
    local function currentStage(items)
        if mapReady(items) then return "map" end
        if findLabel({"Infinite"}, items) then return "infinite" end
        if findLabel({"Trail of the Saint"}, items) then return "trail" end
        if findLabel({"Event Modes", "Event Mode"}, items) then return "events" end
        if findLabel({"Play"}, items) then return "play" end
    end
    notify("Entrada: aguardando o lobby ou o mapa carregar…")
    local stage = waitFor(token, 60, currentStage, "tela de entrada não identificada")
    if stage == "map" then return end
    if stage == "play" then
        notify("Entrada: Play…")
        click(findLabel({"Play"}), active)
        stage = waitFor(token, 30, function(items)
            local nextStage = currentStage(items)
            if nextStage ~= "play" then return nextStage end
        end, "menu de modos não abriu")
        if stage == "map" then return end
    end
    if stage == "events" then
        notify("Entrada: Event Modes…")
        click(findLabel({"Event Modes", "Event Mode"}), active)
        stage = "trail"
    end
    if stage == "trail" then
        notify("Entrada: procurando Trail of the Saint…")
        local target = waitFor(token, 30, function(items)
            if mapReady(items) then return "map" end
            if findLabel({"Infinite"}, items) then return "infinite" end
            local card = findLabel({"Trail of the Saint"}, items)
            if not card then revealTrail() end
            return card
        end, "Trail of the Saint não encontrado")
        if target == "map" then return end
        if target ~= "infinite" then click(target, active) end
    end
    notify("Entrada: selecionando Infinite…")
    local target = waitFor(token, 30, function(items)
        if mapReady(items) then return "map" end
        return findLabel({"Infinite"}, items)
    end, "Infinite não encontrado")
    if target == "map" then return end
    click(target, active)
    notify("Entrada: aguardando o mapa ou o botão Start…")
    target = waitFor(token, 45, function(items)
        if mapReady(items) then return "map" end
        return findLabel({"Start"}, items)
    end, "nem Start nem o mapa apareceram")
    if target == "map" then return end
    click(target, active)
    notify(state.autoExecute and "Start acionado. Aguardando mapa/teleporte…"
        or "Start acionado. Em um novo servidor, reexecute o script se o autoexec estiver desligado.")
    waitFor(token, 150, function(items) return mapReady(items) end, "mapa não foi identificado")
end

-- AUTO_PICK: seleção somente no diálogo Additive Cards, pelos nomes configurados.
local function detectWave(list)
    local best, bestScore = nil, 0
    local function accept(value, score)
        value = tonumber(value)
        if value and value >= 1 and value <= 1000000
            and (score > bestScore or (score == bestScore and (not best or value > best))) then
            best, bestScore = value, score
        end
    end
    for _, entry in ipairs(list) do
        local raw = (entry.raw or ""):gsub("<[^>]*>", ""):lower()
        local counter = raw:match("^%s*wave%s*:?%s*(%d+)%s*/")
        local plain = raw:match("^%s*wave%s*:?%s*(%d+)%s*$")
        if counter then accept(counter, 100) elseif plain then accept(plain, 70) end
        if entry.content == "wave" then
            local parent = entry.object.Parent
            if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.X <= 500 and parent.AbsoluteSize.Y <= 140 then
                for _, sibling in ipairs(parent:GetDescendants()) do
                    if shown(sibling, false) and (sibling:IsA("TextLabel") or sibling:IsA("TextButton")) then
                        local value = sibling.Text:gsub("<[^>]*>", ""):match("^%s*(%d+)%s*/")
                        if value then accept(value, 90) end
                    end
                end
            end
        end
    end
    return best
end

local function cardDialogScope(header, list)
    local ancestor = header.Parent
    while ancestor and ancestor ~= playerGui do
        for _, entry in ipairs(list) do
            if entry.content:find("clicktovote", 1, true) == 1 and entry.object:IsDescendantOf(ancestor) then
                return ancestor
            end
        end
        if ancestor:IsA("ScreenGui") then break end
        ancestor = ancestor.Parent
    end
end

local function cardTarget(title, list)
    local ancestor = title
    while ancestor and ancestor ~= playerGui and not ancestor:IsA("ScreenGui") do
        if ancestor:IsA("GuiButton") then return ancestor end
        ancestor = ancestor.Parent
    end
    ancestor = title.Parent
    for _ = 1, 5 do
        if not ancestor or not ancestor:IsA("GuiObject") then break end
        local votes, buttons = 0, {}
        for _, entry in ipairs(list) do
            if entry.object:IsDescendantOf(ancestor) and entry.content:find("clicktovote", 1, true) == 1 then
                votes = votes + 1
            end
        end
        if votes == 1 then
            for _, object in ipairs(ancestor:GetDescendants()) do
                if object:IsA("GuiButton") and shown(object, false) then buttons[#buttons + 1] = object end
            end
            if #buttons == 1 then return buttons[1] end
            if #buttons == 0 then return ancestor end
            return nil -- evita confundir botões de mais de um cartão.
        elseif votes > 1 then return nil end
        ancestor = ancestor.Parent
    end
end

local function availableCards(header, list, priorities)
    local result, seen = {}, {}
    local scope = cardDialogScope(header, list)
    if not scope then return result end
    for _, wanted in ipairs(priorities or {}) do
        local key = cardNameKey(wanted)
        if not seen[key] then
            for _, entry in ipairs(list) do
                if entry.content == key and entry.object:IsDescendantOf(scope) then
                    local target = cardTarget(entry.object, list)
                    if target then
                        result[#result + 1] = {name = wanted, object = entry.object, target = target}
                        seen[key] = true
                        break
                    end
                end
            end
        end
    end
    return result
end
-- END_AUTO_PICK

-- RUN_ENGINE: leitura de Instances/Text; nenhum reconhecimento de imagem.
do
    local function clean(value)
        return (tostring(value or ""):gsub("<[^>]*>", ""):match("^%s*(.-)%s*$"))
    end
    function Runtime.clockValue(value)
        local textValue = clean(value)
        local h, m, s = textValue:match("^(%d+):(%d%d):(%d%d)$")
        if not h then m, s = textValue:match("^(%d%d?):(%d%d)$"); h = m and "0" or nil end
        if not h or tonumber(h) > 9999 or tonumber(m) >= 60 or tonumber(s) >= 60 then return nil end
        return string.format("%02d:%02d:%02d", tonumber(h), tonumber(m), tonumber(s))
    end
    function Runtime.waveValue(value)
        local digits = clean(value):gsub(",", "")
        if not digits:match("^%d+$") then return nil end
        local count = tonumber(digits)
        if count and count >= 0 and count <= 1000000 then return count end
    end
    function Runtime.counterValue(value)
        if #clean(value) > 32 then return nil end
        local number = clean(value):lower():gsub("×", "x"):match("^x%s*([%d][%d,%.]*[kmb]?)$")
        if not number or not tonumber((number:gsub("[kmb]$", ""):gsub(",", ""))) then return nil end
        return number:upper()
    end
    local function caption(wanted, list)
        local key = normalize(wanted)
        for _, entry in ipairs(list) do
            if entry.content:find(key, 1, true) == 1 then return entry.object, entry.raw end
        end
    end
    local function rowValue(anchor, list, parse)
        if not anchor then return nil end
        local centerY = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y / 2
        local ancestor = anchor.Parent
        for _ = 1, 4 do
            if not ancestor or ancestor == playerGui then break end
            local best, bestDistance
            for _, entry in ipairs(list) do
                local object = entry.object
                if object ~= anchor and object:IsDescendantOf(ancestor) then
                    local p, s = object.AbsolutePosition, object.AbsoluteSize
                    local y = p.Y + s.Y / 2
                    local distance = p.X - anchor.AbsolutePosition.X
                    local value = parse(entry.raw)
                    if value ~= nil and distance >= 0 and math.abs(y - centerY) <= math.max(s.Y, anchor.AbsoluteSize.Y) / 2
                        and (not bestDistance or distance < bestDistance) then
                        best, bestDistance = value, distance
                    end
                end
            end
            if best ~= nil then return best end
            if ancestor:IsA("ScreenGui") then break end
            ancestor = ancestor.Parent
        end
    end
    function Runtime.retryButton(list)
        for _, entry in ipairs(list) do
            local raw = clean(entry.raw):lower()
            if raw == "retry" or raw:match("^retry%s*%(") then
                local votes, total = raw:match("%((%d+)%s*/%s*(%d+)%)")
                return entry.object, tonumber(votes), tonumber(total)
            end
        end
    end
    function Runtime.readResults(list)
        local title = findLabel({"Failed", "Defeat", "Victory", "Success", "Completed"}, list)
        local retry, votes, total = Runtime.retryButton(list)
        local waveAnchor, waveRaw = caption("Waves Completed", list)
        local timeAnchor, timeRaw = caption("Play Time", list)
        if not title or not retry or not waveAnchor or not timeAnchor then return nil end
        local waveSuffix = clean(waveRaw):lower():gsub("^waves%s*completed%s*:?%s*", "")
        local timeSuffix = clean(timeRaw):lower():gsub("^play%s*time%s*:?%s*", "")
        local waves = Runtime.waveValue(waveSuffix) or rowValue(waveAnchor, list, Runtime.waveValue)
        local duration = Runtime.clockValue(timeSuffix) or rowValue(timeAnchor, list, Runtime.clockValue)
        local key = normalize((title:IsA("TextLabel") or title:IsA("TextButton")) and title.Text or title.Name)
        return {header = title, retry = retry, votes = votes, voteTotal = total,
            outcome = (key == "failed" or key == "defeat") and "Derrota" or "Vitória",
            waves = waves, duration = duration}
    end
    function Runtime.readLeaves(list)
        local best, bestObject, bestScore, ambiguous
        for _, anchor in ipairs(list) do
            local raw = clean(anchor.raw):lower()
            if anchor.content == "wave" or raw:match("^wave%s*:?%s*%d+%s*/") then
                local p, s = anchor.object.AbsolutePosition, anchor.object.AbsoluteSize
                for _, candidate in ipairs(list) do
                    local value = Runtime.counterValue(candidate.raw)
                    if value then
                        local cp, cs = candidate.object.AbsolutePosition, candidate.object.AbsoluteSize
                        local dx = cp.X + cs.X / 2 - (p.X + s.X / 2)
                        local dy = cp.Y + cs.Y / 2 - (p.Y + s.Y / 2)
                        if dy >= s.Y / 2 and dy <= math.max(100, s.Y * 5) and math.abs(dx) <= math.max(180, s.X * 3) then
                            local score = dx * dx + dy * dy
                            -- Metadados reais podem reforçar a identificação do contador.
                            local parent = candidate.object.Parent
                            if candidate.name:find("leav", 1, true)
                                or (parent and normalize(parent.Name):find("leav", 1, true)) then score = score / 4 end
                            if not bestScore or score < bestScore * 0.85 then
                                best, bestObject, bestScore, ambiguous = value, candidate.object, score, false
                            elseif math.abs(score - bestScore) <= bestScore * 0.15 and value ~= best then ambiguous = true end
                        end
                    end
                end
            end
        end
        if ambiguous then return nil end
        return best, bestObject
    end
    function Runtime.autoPlayState(list)
        local active = findLabel({"Auto Playing", "AutoPlaying"}, list)
        if active then return "active", active end
        local inactive = findLabel({"Auto Play", "Autoplay"}, list)
        if inactive then return "inactive", inactive end
        return "unknown"
    end
    function Runtime.observeLeaves(list)
        local value, object = Runtime.readLeaves(list)
        if value == nil then return end
        Runtime.lastLeaves = value
        if Runtime.leafBinding ~= object then
            if Runtime.leafConnection then Runtime.leafConnection:Disconnect() end
            Runtime.leafBinding = object
            Runtime.leafConnection = object:GetPropertyChangedSignal("Text"):Connect(function()
                if stopped or Runtime.session then return end
                local nextValue = Runtime.counterValue(object.Text)
                if nextValue ~= nil then Runtime.lastLeaves = nextValue end
            end)
        end
    end
    function Runtime.message(report)
        return {embeds = {{
            title = "Anime Vanguards • " .. report.outcome,
            description = "Trail of the Saint • Infinite",
            color = report.outcome == "Vitória" and 5763719 or 15548997,
            fields = {
                {name = "Folhas obtidas (HUD)", value = report.leaves or "Não identificado", inline = true},
                {name = "Waves completas", value = report.waves ~= nil and tostring(report.waves) or "Não identificado", inline = true},
                {name = "Tempo da run", value = report.duration or "Não identificado", inline = true},
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}}
    end
    function Runtime.sendWebhook(report, url)
        url = Runtime.webhookURL(url)
        local send = Runtime.requestFunction()
        if not url or not send then return false, "URL ou função HTTP indisponível." end
        local destination = url .. (url:find("?", 1, true) and "&wait=true" or "?wait=true")
        local body = Http:JSONEncode(Runtime.message(report))
        for attempt = 1, 2 do
            if stopped or not state.safety.webhookEnabled then return false, "Envio cancelado." end
            local ok, response = pcall(send, {Url = destination, Method = "POST",
                Headers = {["Content-Type"] = "application/json"}, Body = body})
            if not ok or type(response) ~= "table" then return false, "Falha de rede. Não houve reenvio automático." end
            local code = tonumber(response.StatusCode or response.Status)
            if code and code >= 200 and code < 300 then return true, "Resumo enviado ao webhook." end
            if code == 429 and attempt == 1 then
                local parsed, data = pcall(function() return Http:JSONDecode(response.Body or "{}") end)
                local delay = parsed and type(data) == "table" and tonumber(data.retry_after) or nil
                if not delay or delay < 0 or delay > 10 then return false, "Webhook limitado; tente na próxima run." end
                task.wait(math.max(0.5, delay))
            else return false, "Webhook retornou HTTP " .. tostring(code or "desconhecido") .. "." end
        end
        return false, "Webhook ainda está limitado."
    end
end
-- END_RUN_ENGINE

-- RUN_LIFECYCLE: uma notificação e um voto de Retry por término detectado.
do
    Runtime.lastInputAt, Runtime.lastAfkPulse = os.clock(), -1000
    Runtime.nextAfkAt, Runtime.playAttempts, Runtime.lastPlayAttempt = os.clock() + 90, 0, -1000
    Runtime.needAutoPlay = type(resumed) == "table" and resumed.needAutoPlay == true
    function Runtime.resetRun(wave)
        Runtime.session, Runtime.lastLeaves, Runtime.lastWave = nil, nil, wave
        Runtime.playAttempts, Runtime.lastPlayAttempt = 0, -1000
        Runtime.needAutoPlay = Runtime.restartRequested == true
        Runtime.restartRequested = false
        observedWave, cardSession = wave, nil
        cardToken = cardToken + 1
        routeToken, routeDone = routeToken + 1, true
    end
    function Runtime.wantsAutoPlay()
        return state.autoPlay or (state.safety.autoRestart and Runtime.needAutoPlay)
    end
    function Runtime.antiAfkTick(now, cardHeader)
        if not state.safety.antiAfk or cardHeader or clickBusy or cardBusy or autoPlayBusy or Runtime.restartBusy then return end
        if Input:GetFocusedTextBox() then return end
        if now - Runtime.lastAfkPulse < 30 then return end
        if not Runtime.idleDue and (now < Runtime.nextAfkAt or now - Runtime.lastInputAt < 90) then return end
        local camera = World.CurrentCamera
        if not camera then return end
        clickBusy = true
        local ok = pcall(function()
            local virtual = game:GetService("VirtualUser")
            virtual:CaptureController()
            virtual:ClickButton2(Vector2.new(0, 0), camera.CFrame)
        end)
        clickBusy = false
        Runtime.lastAfkPulse, Runtime.nextAfkAt, Runtime.idleDue = now, now + 90, false
        if ok then Runtime.afkCount = (Runtime.afkCount or 0) + 1
        else
            state.safety.antiAfk = false
            if refreshRunOptions then refreshRunOptions() end
            notify("Anti-AFK interrompido: entrada virtual não autorizada pelo ambiente.")
        end
    end
    function Runtime.tick(list, inMap, wave, cardHeader)
        local now = os.clock()
        local result = Runtime.readResults(list)
        Runtime.resultsVisible = result ~= nil
        if result then
            local session = Runtime.session
            if not session then
                session = {firstSeen = now, stableAt = now,
                    leaves = Runtime.lastLeaves or Runtime.readLeaves(list)}
                Runtime.session = session
            end
            session.closedAt, session.current = nil, result
            local key = result.outcome .. ":" .. tostring(result.waves) .. ":" .. tostring(result.duration)
            if session.key ~= key then session.key, session.stableAt = key, now end
            if not session.report and ((result.waves ~= nil and result.duration and now - session.stableAt >= 1)
                or now - session.firstSeen >= 3) then
                session.report = {outcome = result.outcome, waves = result.waves,
                    duration = result.duration, leaves = session.leaves}
                Runtime.lastReport = session.report
                Runtime.completedRuns = (Runtime.completedRuns or 0) + 1
            end
            if session.report and state.safety.webhookEnabled and not session.notifyAttempted then
                session.notifyAttempted, session.notifyPending, session.notifyAt = true, true, now
                local url = state.safety.webhookURL
                task.spawn(function()
                    local ok, message = Runtime.sendWebhook(session.report, url)
                    session.notifyPending, session.notifyOK = false, ok
                    if not stopped then notify(message) end
                end)
            end
            local waitingSend = session.notifyPending and now - session.notifyAt < 15
            if session.report and state.safety.autoRestart and not session.restartAttempted
                and not Runtime.restartBusy and not waitingSend and now - session.firstSeen >= 2 then
                session.restartAttempted, Runtime.restartRequested = true, true
                if result.votes and result.voteTotal and result.votes >= result.voteTotal then
                    notify("Retry já recebeu os votos necessários. Aguardando nova run.")
                else
                    Runtime.restartBusy = true
                    task.spawn(function()
                        local ok, err = pcall(function()
                            click(result.retry, function()
                                return not stopped and state.safety.autoRestart and Runtime.session == session
                                    and shown(result.retry, false)
                            end)
                        end)
                        Runtime.restartBusy = false
                        if stopped then return end
                        if ok then notify("Retry acionado. Aguardando uma nova run para conferir o Auto Play.")
                        else
                            Runtime.restartRequested = false
                            if state.safety.autoRestart then
                                state.safety.autoRestart = false
                                if refreshRunOptions then refreshRunOptions() end
                                notify("Auto Restart interrompido: " .. tostring(err))
                            end
                        end
                    end)
                end
            end
        else
            local session = Runtime.session
            if session then
                session.closedAt = session.closedAt or now
                local endedWave = session.report and session.report.waves or (session.current and session.current.waves)
                local freshWave = wave and (wave <= 1 or (endedWave and wave < endedWave))
                if inMap and freshWave and now - session.closedAt >= 0.5 then Runtime.resetRun(wave) end
            else
                if inMap and wave and Runtime.lastWave and wave <= 1 and wave < Runtime.lastWave then Runtime.resetRun(wave) end
                if wave then Runtime.lastWave = wave end
                Runtime.observeLeaves(list)
            end
        end
        if Runtime.uiStatus then
            local report = Runtime.lastReport
            Runtime.uiStatus.Text = "Folhas lidas no HUD: " .. (Runtime.lastLeaves or "não identificado")
                .. "\nÚltima run: " .. (report and (tostring(report.waves or "?") .. " waves · "
                    .. (report.duration or "tempo ?") .. " · " .. (report.leaves or "folhas ?")) or "aguardando término")
                .. "\nAnti-AFK: " .. tostring(Runtime.afkCount or 0) .. " acionamento(s)"
        end
        Runtime.antiAfkTick(now, cardHeader)
        return Runtime.session ~= nil
    end
end
-- END_RUN_LIFECYCLE
watch(player.Idled, function() Runtime.idleDue = true end)
watch(Input.InputBegan, function() Runtime.lastInputAt = os.clock() end)

UI.build("Partida")
UI.section("Sua próxima run", "Trail of the Saint / Infinite")
text("Play  ›  Event Modes  ›  Trail of the Saint  ›  Infinite", 36)
local enterButton, playButton, executeButton
local function refreshOptions()
    enterButton.Text = "Entrada automática: " .. (state.autoEnter and "LIGADA" or "DESLIGADA")
    playButton.Text = "Acionar Auto Play no mapa: " .. (state.autoPlay and "LIGADO" or "DESLIGADO")
    executeButton.Text = "Autoexecutar após teleporte: " .. (state.autoExecute and "LIGADO" or "DESLIGADO")
end
enterButton = button("", function()
    state.autoEnter = not state.autoEnter
    state.armed = false
    routeToken, routeDone = routeToken + 1, false
    refreshOptions()
    notify(state.autoEnter and "Entrada automática ativada." or "Entrada automática cancelada.")
end)
UI.build("Auto Play")
UI.section("Auto Play", "Ativação e confirmação do modo automático do jogo.")
playButton = button("", function()
    state.autoPlay = not state.autoPlay
    refreshOptions()
    notify(state.autoPlay and "Auto Play será acionado uma vez neste mapa."
        or "Acionamento automático desligado. Isso não pausa o Auto Play já iniciado pelo jogo.")
end)
UI.build("Continuidade")
UI.section("Sessão contínua", "Inatividade, reinício e recuperação do Auto Play.")
executeButton = button("", function()
    if not queueTeleport then
        notify("O executor não expôs queue_on_teleport. Autoexec após teleporte indisponível.")
        return
    end
    state.autoExecute = not state.autoExecute
    refreshOptions()
    notify(state.autoExecute and "O script continuará após teleporte com estas opções."
        or "Autoexec após teleporte desligado.")
end)
refreshOptions()
text("Auto Playing confirma que o jogo está jogando sozinho. Auto Play indica que precisa ativar. Após Retry, o Auto Restart também confere esse estado. Autoexec é após teleporte.", 78)
UI.build("Continuidade")
local afkButton, restartButton, webhookButton, webhookInput
afkButton = button("", function()
    state.safety.antiAfk = not state.safety.antiAfk
    Runtime.nextAfkAt, Runtime.lastInputAt = os.clock() + 90, os.clock()
    refreshRunOptions()
    notify(state.safety.antiAfk and "Anti-AFK ligado. Aguarda inatividade para acionar a entrada virtual."
        or "Anti-AFK desligado.")
end)
restartButton = button("", function()
    state.safety.autoRestart = not state.safety.autoRestart
    if state.safety.autoRestart and Runtime.session then Runtime.session.restartAttempted = false end
    refreshRunOptions()
    notify(state.safety.autoRestart and "Auto Restart ligado. Retry será acionado ao terminar a run."
        or "Auto Restart desligado.")
end)
UI.build("Webhook")
UI.section("Resumo de resultados", "Folhas, waves e duração ao fim de cada run.")
webhookButton = button("", function()
    if not state.safety.webhookEnabled then
        if not Runtime.webhookURL(state.safety.webhookURL) then notify("Configure uma URL de webhook válida primeiro."); return end
        if not Runtime.requestFunction() then notify("Este ambiente não expôs uma função de requisição HTTP."); return end
    end
    state.safety.webhookEnabled = not state.safety.webhookEnabled
    refreshRunOptions()
    notify(state.safety.webhookEnabled and "Webhook ligado: envia folhas, waves e tempo ao final de cada run."
        or "Webhook desligado.")
end)
order = order + 1
webhookInput = make("TextBox", {
    LayoutOrder = order, Size = UDim2.new(1, 0, 0, 64), Text = state.safety.webhookURL,
    PlaceholderText = "Cole aqui a URL do webhook do Discord", ClearTextOnFocus = false,
    BackgroundColor3 = theme.card, TextColor3 = theme.text, TextSize = 12,
    TextWrapped = true, Font = Enum.Font.Gotham, BorderSizePixel = 0,
}, body)
button("Aplicar URL do webhook", function()
    local value = webhookInput.Text:match("^%s*(.-)%s*$")
    if value == "" then state.safety.webhookURL, state.safety.webhookEnabled = "", false
    else
        value = Runtime.webhookURL(value)
        if not value then notify("URL inválida. Use o endereço de um webhook do Discord."); return end
        state.safety.webhookURL = value
    end
    refreshRunOptions()
    notify("Configuração do webhook atualizada. Nenhuma mensagem de teste foi enviada.")
end)
refreshRunOptions = function()
    afkButton.Text = "Anti-AFK: " .. (state.safety.antiAfk and "LIGADO" or "DESLIGADO")
    restartButton.Text = "Auto Restart + conferir Auto Play: " .. (state.safety.autoRestart and "LIGADO" or "DESLIGADO")
    webhookButton.Text = "Webhook de fim de run: " .. (state.safety.webhookEnabled and "LIGADO" or "DESLIGADO")
end
refreshRunOptions()
Runtime.uiStatus = text("Aguardando dados da run…", 88)
text("O resumo usa o contador de folhas próximo à Wave, Waves Completed e Play Time. Um campo não identificado é informado como tal. Salvar/exportar o perfil também inclui a URL configurada.", 90)
UI.build("Continuidade")
button("Parar todas as rotinas", function()
    state.autoEnter, state.autoPlay, state.armed = false, false, false
    state.cards.enabled, cardToken = false, cardToken + 1
    state.safety.antiAfk, state.safety.autoRestart, state.safety.webhookEnabled = false, false, false
    routeToken, routeDone = routeToken + 1, false
    refreshOptions()
    if refreshCardOptions then refreshCardOptions() end
    refreshRunOptions()
    notify("Rotinas canceladas. O Auto Play já iniciado no jogo permanece como está.")
end)

UI.build("Cards")
UI.section("Prioridades de cards", "Defina sua ordem fixa ou um ciclo a cada 10 waves.")
local cardToggle, cardModeButton, cardStatusLabel
local editScope, editFirst = "fixed", 1
cardToggle = button("", function()
    state.cards.enabled = not state.cards.enabled
    cardToken = cardToken + 1
    refreshCardOptions()
    notify(state.cards.enabled and "Auto Pick Cards ligado. Aguardando Additive Cards."
        or "Auto Pick Cards desligado.")
end)
cardModeButton = button("", function()
    state.cards.mode = state.cards.mode == "fixed" and "waves10" or "fixed"
    editScope = state.cards.mode == "fixed" and "fixed" or "range"
    cardToken = cardToken + 1
    refreshCardOptions()
    renderCardEditor()
end)
refreshCardOptions = function()
    cardToggle.Text = "Auto Pick Cards: " .. (state.cards.enabled and "LIGADO" or "DESLIGADO")
    cardModeButton.Text = "Prioridades: " .. (state.cards.mode == "fixed" and "ORDEM FIXA" or "A CADA 10 WAVES")
end
refreshCardOptions()
cardStatusLabel = text("Wave ainda não identificada.", 44)
text("Faixas: 1–10, 11–20, 21–30… Depois da última faixa configurada, o ciclo volta à primeira. Lacunas usam a fixa. Sem carta da lista ou sem wave identificada, o modo por faixas aguarda.", 92)
local scopeButton, rangeBox, previousRange, nextRange, resetRange, editorTitle
scopeButton = button("", function()
    editScope = editScope == "fixed" and "range" or "fixed"
    renderCardEditor()
end)
order = order + 1
rangeBox = make("TextBox", {
    LayoutOrder = order, Size = UDim2.new(1, 0, 0, 44), Text = "1",
    PlaceholderText = "Digite uma wave para editar a faixa dela", ClearTextOnFocus = false,
    BackgroundColor3 = theme.card, TextColor3 = theme.text, TextSize = 14,
    Font = Enum.Font.Gotham, BorderSizePixel = 0,
}, body)
watch(rangeBox.FocusLost, function()
    local wave = tonumber(rangeBox.Text)
    if not wave or wave ~= wave or wave < 1 or wave > 1000000 then
        notify("Digite uma wave entre 1 e 1000000.")
    else editFirst = math.floor((wave - 1) / 10) * 10 + 1 end
    renderCardEditor()
end)
previousRange = button("← Faixa anterior (10 waves)", function()
    editFirst = math.max(1, editFirst - 10)
    renderCardEditor()
end)
nextRange = button("Próxima faixa (10 waves) →", function()
    editFirst = math.min(999991, editFirst + 10)
    renderCardEditor()
end)
editorTitle = text("", 42)
order = order + 1
local ranking = make("Frame", {
    Name = "PrioridadesCards", LayoutOrder = order, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, body)
make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, ranking)
local function editingList()
    if editScope == "fixed" then return state.cards.fixed end
    return state.cards.bands[tostring(editFirst)] or state.cards.fixed
end
local function changeCards(change)
    local names = copyNames(editingList())
    change(names)
    local ok, validNames = pcall(validateNames, names)
    if not ok then notify(tostring(validNames)); return end
    if editScope == "fixed" then state.cards.fixed = validNames
    else
        local key, count = tostring(editFirst), 0
        for _ in pairs(state.cards.bands) do count = count + 1 end
        if not state.cards.bands[key] and count >= 100 then notify("Limite de 100 faixas personalizadas."); return end
        state.cards.bands[key] = validNames
    end
    cardToken = cardToken + 1
    renderCardEditor()
end
renderCardEditor = function()
    for _, connection in ipairs(cardRowConnections) do connection:Disconnect() end
    cardRowConnections = {}
    for _, child in ipairs(ranking:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    local range = editScope == "range"
    scopeButton.Text = "Editar: " .. (range and "LISTA DE UMA FAIXA" or "ORDEM FIXA")
    rangeBox.Visible, previousRange.Visible, nextRange.Visible = range, range, range
    resetRange.Visible = range
    rangeBox.Text = tostring(editFirst)
    editorTitle.Text = range and ("Editando waves " .. editFirst .. "–" .. (editFirst + 9)
        .. (state.cards.bands[tostring(editFirst)] and " · personalizada" or " · herdando a fixa"))
        or "Editando ordem fixa · vale também como fallback"
    local names = editingList()
    for index, name in ipairs(names) do
        local rowIndex = index
        local row = make("Frame", {
            LayoutOrder = index, Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = theme.card,
            BorderSizePixel = 0,
        }, ranking)
        make("TextLabel", {Text = tostring(index), Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(30, 56), BackgroundTransparency = 1,
            TextColor3 = theme.text, TextSize = 14, Font = Enum.Font.GothamBold}, row)
        make("TextLabel", {Text = name, Position = UDim2.fromOffset(32, 0),
            Size = UDim2.new(1, -170, 1, 0), BackgroundTransparency = 1,
            TextColor3 = theme.text, TextSize = 12, TextWrapped = true,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left}, row)
        local function control(symbol, offset, callback)
            local target = make("TextButton", {Text = symbol, Position = UDim2.new(1, offset, 0, 6),
                Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1,
                TextColor3 = theme.text, TextSize = 21}, row)
            cardRowConnections[#cardRowConnections + 1] = target.Activated:Connect(function()
                if not stopped then callback() end
            end)
        end
        control("↑", -132, function()
            if rowIndex > 1 then changeCards(function(values)
                values[rowIndex], values[rowIndex - 1] = values[rowIndex - 1], values[rowIndex]
            end) end
        end)
        control("↓", -88, function()
            if rowIndex < #names then changeCards(function(values)
                values[rowIndex], values[rowIndex + 1] = values[rowIndex + 1], values[rowIndex]
            end) end
        end)
        control("×", -44, function() changeCards(function(values) table.remove(values, rowIndex) end) end)
    end
end
resetRange = button("Remover personalização desta faixa", function()
    state.cards.bands[tostring(editFirst)] = nil
    cardToken = cardToken + 1
    renderCardEditor()
end)
order = order + 1
local newCardName = make("TextBox", {
    LayoutOrder = order, Size = UDim2.new(1, 0, 0, 44), Text = "",
    PlaceholderText = "Nome exato de outro card", ClearTextOnFocus = false,
    BackgroundColor3 = theme.card, TextColor3 = theme.text, TextSize = 13,
    Font = Enum.Font.Gotham, BorderSizePixel = 0,
}, body)
button("Adicionar card à lista em edição", function()
    local name = newCardName.Text
    changeCards(function(values) values[#values + 1] = name end)
end)
text("↑ ↓ Reordenar   ·   × Remover\nAdicione outros cards pelo nome exato.", 42)
renderCardEditor()

UI.build("Unidades")
UI.section("Unidades e posições", "Marcação manual de pontos. Colocação automática ainda pendente.")
local modeButton
local function showMode()
    modeButton.Text = "Modo planejado: " .. (state.mode == "repeat" and "repetir fase" or "avançar fases")
end
modeButton = button("", function()
    state.mode = state.mode == "repeat" and "advance" or "repeat"
    showMode()
    notify("Preferência alterada. Ela ainda não controla o jogo.")
end)
showMode()
button("Colocação e upgrades próprios • PENDENTES", function()
    notify("A entrada e o Auto Play nativo usam as opções acima. Colocação e upgrades próprios ainda não foram implementados.")
end)
text("Escolha o slot, marque um ponto e toque no mapa.", 36)
local slotButton
slotButton = button("Slot para marcar: 1 (toque para trocar)", function()
    state.slot = state.slot % 6 + 1
    slotButton.Text = "Slot para marcar: " .. state.slot .. " (toque para trocar)"
end)
countLabel = text("0 ponto(s) manual(is). Não são unidades do jogo.", 36)
button("Marcar próximo ponto no mapa", function()
    if routeBusy then notify("Pare a entrada automática antes de marcar pontos."); return end
    if #state.points >= MAX_POINTS then notify("Limite de 100 pontos atingido."); return end
    state.armed = true
    panel.Visible = false
    notify("Marcação ativa. Toque no chão; abra AV para cancelar.")
end)
button("Cancelar marcação", function()
    state.armed = false
    notify("Marcação cancelada.")
end)
button("Desfazer último ponto", function()
    state.armed = false
    table.remove(state.points)
    showPoints()
    notify("Último ponto removido, se existia.")
end)
local previewButton
previewButton = button("Mostrar pontos: SIM", function()
    state.preview = not state.preview
    previewButton.Text = "Mostrar pontos: " .. (state.preview and "SIM" or "NÃO")
    showPoints()
end)
UI.build("Perfil")
UI.section("Suas configurações", "Salve no dispositivo ou importe um perfil em JSON.")
order = order + 1
local profile = make("TextBox", {
    Name = "PerfilJSON", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 96),
    BackgroundColor3 = theme.card, BorderSizePixel = 0, Text = "",
    PlaceholderText = "Cole o JSON do perfil aqui…", ClearTextOnFocus = false,
    MultiLine = true, TextWrapped = true, TextSize = 12, Font = Enum.Font.Code,
    TextColor3 = theme.text, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, body)
button("Exportar perfil para o campo / copiar", function()
    local raw = encode()
    profile.Text = raw
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, raw)
        if ok then notify("Perfil copiado e exibido no campo."); return end
    end
    notify("Perfil exibido no campo. Selecione o texto para copiar.")
end)
local function import(raw)
    local ok, mode, points, options = pcall(decode, raw)
    if not ok then notify("Não importado: " .. tostring(mode)); return end
    state.armed, state.mode, state.points = false, mode, points
    routeToken, routeDone = routeToken + 1, false
    state.autoEnter, state.autoPlay, state.autoExecute = options.autoEnter, options.autoPlay, options.autoExecute
    if options.cards then state.cards = options.cards end
    if options.safety then state.safety = options.safety end
    cardToken = cardToken + 1
    refreshOptions()
    refreshCardOptions()
    renderCardEditor()
    refreshRunOptions()
    webhookInput.Text = state.safety.webhookURL
    showMode()
    showPoints()
    notify("Perfil carregado: " .. #points .. " ponto(s).")
end
button("Importar perfil do campo", function() import(profile.Text) end)
button("Salvar perfil no dispositivo", function()
    if type(writefile) ~= "function" then notify("Salvar arquivo não está disponível neste ambiente. Use exportar."); return end
    local ok, err = pcall(writefile, FILE_NAME, encode())
    notify(ok and "Perfil salvo no arquivo local do executor." or ("Falha ao salvar: " .. tostring(err)))
end)
button("Carregar perfil do dispositivo", function()
    if type(readfile) ~= "function" then notify("Ler arquivo não está disponível neste ambiente. Use importar."); return end
    local ok, raw = pcall(readfile, FILE_NAME)
    if not ok then notify("Perfil indisponível: " .. tostring(raw)); return end
    import(raw)
end)

local function capture(position, processed)
    if stopped or not state.armed or processed or panel.Visible then return end
    local camera = World.CurrentCamera
    if not camera then notify("Câmera indisponível. Tente novamente."); return end
    local exclusions = {markers}
    if player.Character then exclusions[#exclusions + 1] = player.Character end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    local ray = camera:ScreenPointToRay(position.X, position.Y)
    local hit = World:Raycast(ray.Origin, ray.Direction * 2048, params)
    if not hit then
        panel.Visible = true
        notify("Sem superfície nesse toque. Minimize o painel e tente de novo.")
        return
    end
    state.armed = false
    local p = hit.Position
    state.points[#state.points + 1] = {slot = state.slot, x = p.X, y = p.Y, z = p.Z}
    showPoints()
    panel.Visible = true
    notify("Ponto manual salvo para o slot " .. state.slot .. ". Nenhuma unidade foi colocada.")
end
watch(Input.TouchTapInWorld, capture)
-- Facilita testar a interface também com mouse, sem duplicar os eventos de toque.
watch(Input.InputBegan, function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        capture(Input:GetMouseLocation(), processed)
    end
end)

-- Página inicial: somente estatísticas reais desta execução.
UI.build("Início")
UI.section("Home", "NANO HUB   /   Anime Vanguards   /   v0.6")
UI.homeStarted = os.clock()
order = order + 1
UI.homeGrid = make("Frame", {BackgroundTransparency = 1, LayoutOrder = order,
    Size = UDim2.new(1, 0, 0, 182)}, body)
make("UIGridLayout", {CellSize = UDim2.new(0.5, -4, 0, 87), CellPadding = UDim2.fromOffset(8, 8),
    SortOrder = Enum.SortOrder.LayoutOrder}, UI.homeGrid)
UI.homeStats = {}
for i, item in ipairs({{"wave", "Wave atual"}, {"leaves", "Folhas da run"}, {"runs", "Runs concluídas"}, {"session", "Tempo da sessão"}}) do
    local tile = make("Frame", {LayoutOrder = i, BackgroundColor3 = theme.card, BorderSizePixel = 0}, UI.homeGrid)
    make("UICorner", {CornerRadius = UDim.new(0, 8)}, tile)
    make("UIStroke", {Color = Color3.fromRGB(48, 43, 36), Transparency = 0.5}, tile)
    UI.homeStats[item[1]] = make("TextLabel", {Text = "—", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 35),
        TextSize = 24, TextColor3 = theme.text, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left}, tile)
    make("TextLabel", {Text = item[2], BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -20, 0, 24),
        TextSize = 11, TextColor3 = theme.muted, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left}, tile)
end
UI.section("Quick actions", "Acesso direto às suas configurações.")
button("Configurar entrada na fase", function() UI.select("Partida") end)
button("Editar prioridades de cards", function() UI.select("Cards") end)
button("Carregar último perfil", function()
    if type(readfile) ~= "function" then notify("Leitura de arquivo indisponível."); return end
    local ok, raw = pcall(readfile, FILE_NAME)
    if ok then import(raw) else notify("Nenhum perfil salvo para este mapa.") end
end)
button("Minimizar painel", function() panel.Visible = false end)
UI.select("Início")
resize()
showPoints()
-- Executa o mesmo código no novo cliente, com as opções atuais do menu.
-- O código não precisa de hospedagem nem baixa loaders de terceiros.
local queued = false
watch(player.OnTeleport, function(teleportState)
    if teleportState == Enum.TeleportState.Failed then queued = false; return end
    if teleportState ~= Enum.TeleportState.Started or queued or stopped or not state.autoExecute then return end
    if not queueTeleport then return end
    local payload = Http:JSONEncode({autoEnter = state.autoEnter, autoPlay = state.autoPlay,
        autoExecute = state.autoExecute, cards = state.cards, safety = state.safety,
        needAutoPlay = Runtime.needAutoPlay or Runtime.restartRequested == true})
    local bootstrap = "if not game:IsLoaded() then game.Loaded:Wait() end\n"
        .. "local source = " .. string.format("%q", SOURCE) .. "\n"
        .. "local run, err = loadstring(source, 'AV Mobile 0.6')\nassert(run, err)\n"
        .. "run()(source, game:GetService('HttpService'):JSONDecode(" .. string.format("%q", payload) .. "))"
    local ok, err = pcall(queueTeleport, bootstrap)
    queued = ok
    if not ok then notify("Falha ao preparar autoexec: " .. tostring(err)) end
end)

-- Um supervisor por execução; desligar uma opção invalida a rotina em andamento.
task.spawn(function()
    while not stopped do
        local list = labels(false)
        local inMap = mapReady(list)
        local cardHeader = findLabel({"Additive Cards"}, list)
        local wave = detectWave(list)
        local terminal = Runtime.tick(list, inMap, wave, cardHeader)
        if wave then observedWave = wave end
        if UI.homeStats then
            UI.homeStats.wave.Text = observedWave and tostring(observedWave) or "—"
            UI.homeStats.leaves.Text = Runtime.lastLeaves or "—"
            UI.homeStats.runs.Text = tostring(Runtime.completedRuns or 0)
            local elapsed = math.floor(os.clock() - UI.homeStarted)
            UI.homeStats.session.Text = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)
        end
        if not cardHeader then cardSession = nil
        elseif not cardSession or cardSession.header ~= cardHeader then
            cardSession = {header = cardHeader, picked = false}
        end
        local priorities, rangeName = activeCardList(state.cards, observedWave)
        cardStatusLabel.Text = "Wave: " .. (observedWave and tostring(observedWave) or "?")
            .. " · " .. rangeName .. (state.cards.enabled and " · ativo" or " · desligado")
        if not terminal and state.cards.enabled and cardSession and not cardSession.picked and not cardBusy and priorities then
            local chosen = bestCard(availableCards(cardHeader, list, priorities), priorities)
            if chosen then
                local session, token = cardSession, cardToken
                session.picked, cardBusy = true, true
                task.spawn(function()
                    local ok, err = pcall(function()
                        click(chosen.target, function()
                            return not stopped and state.cards.enabled and cardToken == token
                                and cardSession == session and shown(session.header, false)
                        end, false, true)
                    end)
                    cardBusy = false
                    if stopped then return end
                    if ok then
                        notify("Voto enviado: " .. chosen.name .. " · " .. rangeName .. ".")
                    elseif cardToken ~= token or not state.cards.enabled or cardSession ~= session then
                        session.picked = false
                    else
                        state.cards.enabled = false
                        refreshCardOptions()
                        notify("Auto Pick interrompido: " .. tostring(err))
                    end
                end)
            end
        end
        if state.autoEnter and not routeBusy and not routeDone and not inMap and not cardHeader and not terminal then
            routeBusy = true
            local token = routeToken
            task.spawn(function()
                local ok, err = pcall(enterMap, token)
                routeBusy = false
                if stopped or token ~= routeToken then return end
                if ok then
                    routeDone = true
                    notify("Mapa identificado. Entrada concluída.")
                else
                    state.autoEnter = false
                    refreshOptions()
                    notify("Entrada interrompida: " .. tostring(err))
                end
            end)
        end
        if inMap and not terminal and not cardHeader and Runtime.wantsAutoPlay() and not autoPlayBusy then
            local playState, target = Runtime.autoPlayState(list)
            if playState == "active" then
                Runtime.needAutoPlay, Runtime.playAttempts = false, 0
            elseif playState == "inactive" and Runtime.playAttempts < 3 and os.clock() - Runtime.lastPlayAttempt >= 3 then
                autoPlayBusy = true
                Runtime.playAttempts, Runtime.lastPlayAttempt = Runtime.playAttempts + 1, os.clock()
                task.spawn(function()
                    local ok, err = pcall(function()
                        local function allowed()
                            return not stopped and Runtime.wantsAutoPlay() and not Runtime.resultsVisible
                                and Runtime.autoPlayState(labels(false)) == "inactive"
                        end
                        local fresh, current = Runtime.autoPlayState(labels(false))
                        if fresh == "active" then return end
                        assert(fresh == "inactive", "Estado do Auto Play não identificado.")
                        click(current or target, allowed, true)
                        local deadline = os.clock() + 3
                        repeat
                            if stopped or not Runtime.wantsAutoPlay() then return end
                            if Runtime.autoPlayState(labels(false)) == "active" then return end
                            task.wait(0.25)
                        until os.clock() >= deadline
                        error("O texto Auto Playing não apareceu.", 0)
                    end)
                    autoPlayBusy = false
                    if stopped then return end
                    if Runtime.autoPlayState(labels(false)) == "active" then
                        Runtime.needAutoPlay, Runtime.playAttempts = false, 0
                        notify("Auto Playing identificado: Auto Play está ativo.")
                    elseif not ok then
                        notify("Auto Play não confirmado (tentativa " .. Runtime.playAttempts .. "/3): " .. tostring(err))
                    end
                end)
            end
        end
        task.wait(0.5)
    end
end)
print("AV Mobile Base 0.6: entrada, cards, Anti-AFK, Webhook, Auto Restart e autoexec disponíveis no menu; teste no Delta pendente.")

end
]====]
if not game:IsLoaded() then game.Loaded:Wait() end
local run, err = loadstring(source, "AV Mobile 0.6")
assert(run, err)
run()(source, nil)
