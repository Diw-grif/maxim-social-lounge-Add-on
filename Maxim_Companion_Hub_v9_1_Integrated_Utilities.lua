--[[
    MAXIM COMPANION HUB v9.1
    Rayfield UI + splash + current-server player snapshots
    Server history is local to this device/executor filesystem where supported.

    IMPORTANT:
    * This only records players visible to your client in the current server.
    * It cannot globally search Roblox servers or recover players never observed.
    * Persistence requires executor filesystem APIs (writefile/readfile/isfile/isfolder/makefolder).
    * Roblox avatar thumbnails are fetched by UserId when available.
]]

--========================================================
-- SERVICES / SAFE RE-RUN CLEANUP
--========================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then warn("[Companion Hub] LocalPlayer unavailable"); return end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = PlayerGui:FindFirstChild("MaximCompanionSplash")
if oldGui then oldGui:Destroy() end
local oldViewer = PlayerGui:FindFirstChild("MaximServerHistoryViewer")
if oldViewer then oldViewer:Destroy() end

--========================================================
-- SPLASH (ONLY ONE SPLASH BLOCK)
--========================================================
do
    local gui = Instance.new("ScreenGui")
    gui.Name = "MaximCompanionSplash"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999
    gui.Parent = PlayerGui

    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
    bg.BorderSizePixel = 0
    bg.Parent = gui

    local function label(name, text, pos, size, color, font)
        local obj = Instance.new("TextLabel")
        obj.Name = name
        obj.AnchorPoint = Vector2.new(0.5, 0.5)
        obj.Position = pos
        obj.Size = size
        obj.BackgroundTransparency = 1
        obj.Text = text
        obj.TextColor3 = color
        obj.TextTransparency = 1
        obj.Font = font
        obj.TextScaled = true
        obj.Parent = bg
        return obj
    end

    local title = label("Title", "COMPANION HUB", UDim2.fromScale(.5, .43),
        UDim2.fromScale(.9, .12), Color3.fromRGB(100, 220, 255), Enum.Font.GothamBold)
    local credit = label("Credit", "Сделано Максимом", UDim2.fromScale(.5, .53),
        UDim2.fromScale(.9, .06), Color3.fromRGB(235, 235, 245), Enum.Font.Gotham)
    local status = label("Status", "ЗАГРУЗКА...", UDim2.fromScale(.5, .64),
        UDim2.fromScale(.9, .05), Color3.fromRGB(150, 160, 185), Enum.Font.Code)

    local titleScale = Instance.new("UIScale")
    titleScale.Scale = .92
    titleScale.Parent = title
    local fi = TweenInfo.new(.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(titleScale, TweenInfo.new(.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    for _, obj in ipairs({title, credit, status}) do
        TweenService:Create(obj, fi, {TextTransparency = 0}):Play()
        task.wait(.16)
    end
    task.wait(.45)
    status.Text = "ЗАПУСК RAYFIELD..."
    local fo = TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    for _, obj in ipairs({title, credit, status}) do
        TweenService:Create(obj, fo, {TextTransparency = 1}):Play()
    end
    TweenService:Create(bg, fo, {BackgroundTransparency = 1}):Play()
    task.wait(.3)
    gui:Destroy()
end

--========================================================
-- OPTIONAL EXECUTOR FUNCTIONS / STORAGE
--========================================================
local function optionalFunction(name)
    local env
    if type(getgenv) == "function" then
        local ok, value = pcall(getgenv)
        if ok then env = value end
    end
    if type(env) == "table" and type(env[name]) == "function" then return env[name] end
    if type(_G[name]) == "function" then return _G[name] end
    return nil
end

local readfileFn = optionalFunction("readfile")
local writefileFn = optionalFunction("writefile")
local isfileFn = optionalFunction("isfile")
local isfolderFn = optionalFunction("isfolder")
local makefolderFn = optionalFunction("makefolder")
local setclipboardFn = optionalFunction("setclipboard")

local ROOT = "MaximCompanionHub"
local DATA_PATH = ROOT .. "/CompanionHub.json"
local EXPORT_PATH = ROOT .. "/Session_History.txt"
local function ensureFolder()
    if not makefolderFn then return false end
    local exists = false
    if isfolderFn then
        local ok, result = pcall(isfolderFn, ROOT)
        exists = ok and result == true
    end
    if not exists then pcall(makefolderFn, ROOT) end
    return true
end

local function copyText(text)
    if setclipboardFn then
        local ok = pcall(setclipboardFn, tostring(text))
        if ok then return true end
    end
    if warn then warn("[Companion Hub] Clipboard unavailable; text printed below:\n" .. tostring(text)) end
    return false
end

local Rayfield -- forward declaration used by notify()

local State = {
    FriendNotes = {},
    Bookmarks = {},
    Events = {},
    ServerHistory = {},
    CurrentTargetUserId = nil,
    SessionStarted = os.time(),
    LastSavedServerId = nil,
}

local function notify(title, content)
    if Rayfield and Rayfield.Notify then
        pcall(function()
            Rayfield:Notify({Title = title, Content = content, Duration = 5})
        end)
    else
        print("[Companion Hub] " .. title .. ": " .. content)
    end
end

local function saveData()
    if not writefileFn then return false end
    ensureFolder()
    local payload = {
        Version = 9,
        FriendNotes = State.FriendNotes,
        Bookmarks = State.Bookmarks,
        Events = State.Events,
        ServerHistory = State.ServerHistory,
        SavedAt = os.time(),
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then warn("[Companion Hub] JSON encode failed: " .. tostring(encoded)); return false end
    local wrote, err = pcall(writefileFn, DATA_PATH, encoded)
    if not wrote then warn("[Companion Hub] Save failed: " .. tostring(err)); return false end
    return true
end

local function loadData()
    if not readfileFn or not isfileFn then return end
    local existsOk, exists = pcall(isfileFn, DATA_PATH)
    if not existsOk or not exists then return end
    local ok, raw = pcall(readfileFn, DATA_PATH)
    if not ok or type(raw) ~= "string" then return end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodedOk or type(data) ~= "table" then return end
    State.FriendNotes = type(data.FriendNotes) == "table" and data.FriendNotes or {}
    State.Bookmarks = type(data.Bookmarks) == "table" and data.Bookmarks or {}
    State.Events = type(data.Events) == "table" and data.Events or {}
    State.ServerHistory = type(data.ServerHistory) == "table" and data.ServerHistory or {}
end
loadData()

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function addEvent(message)
    table.insert(State.Events, 1, {
        Time = os.time(),
        Message = tostring(message),
        PlaceId = game.PlaceId,
        JobId = game.JobId,
    })
    while #State.Events > 200 do table.remove(State.Events) end
    saveData()
end

local function getRoot(player)
    local char = player and player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(player)
    local char = player and player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getDistance(player)
    local myRoot, root = getRoot(LocalPlayer), getRoot(player)
    if myRoot and root then return math.floor((myRoot.Position - root.Position).Magnitude + .5) end
    return nil
end

local function getHealth(player)
    local hum = getHumanoid(player)
    if hum then return math.floor(hum.Health + .5), math.floor(hum.MaxHealth + .5) end
    return nil, nil
end

local function snapshotPlayer(player)
    local health, maxHealth = getHealth(player)
    local distance = getDistance(player)
    return {
        Name = player.Name,
        DisplayName = player.DisplayName,
        UserId = player.UserId,
        Health = health,
        MaxHealth = maxHealth,
        Distance = distance,
        SeenAt = os.time(),
    }
end

local function currentServerRecord()
    return {
        Key = tostring(game.PlaceId) .. ":" .. tostring(game.JobId),
        PlaceId = game.PlaceId,
        JobId = game.JobId,
        PlaceName = game.Name,
        FirstSeen = os.time(),
        LastSeen = os.time(),
        PlayerCount = #Players:GetPlayers(),
        Players = {},
    }
end

local function findCurrentServerRecord()
    local key = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
    for _, record in ipairs(State.ServerHistory) do
        if record.Key == key then return record end
    end
    return nil
end

local function recordCurrentServer()
    local record = findCurrentServerRecord()
    if not record then
        record = currentServerRecord()
        table.insert(State.ServerHistory, 1, record)
    end
    record.LastSeen = os.time()
    record.PlaceId = game.PlaceId
    record.JobId = game.JobId
    record.PlaceName = game.Name
    record.PlayerCount = #Players:GetPlayers()
    record.Players = type(record.Players) == "table" and record.Players or {}

    for _, player in ipairs(Players:GetPlayers()) do
        local snap = snapshotPlayer(player)
        local found
        for _, old in ipairs(record.Players) do
            if tonumber(old.UserId) == player.UserId then
                found = old
                break
            end
        end
        if found then
            found.Name = snap.Name
            found.DisplayName = snap.DisplayName
            found.Health = snap.Health
            found.MaxHealth = snap.MaxHealth
            found.Distance = snap.Distance
            found.SeenAt = snap.SeenAt
        else
            table.insert(record.Players, snap)
        end
    end

    -- Limit history size so the JSON file does not grow indefinitely.
    while #State.ServerHistory > 40 do table.remove(State.ServerHistory) end
    saveData()
    return record
end

local function playerByQuery(query)
    query = string.lower(trim(query))
    if query == "" then return nil end
    local numeric = tonumber(query)
    for _, player in ipairs(Players:GetPlayers()) do
        if (numeric and player.UserId == numeric)
            or string.lower(player.Name) == query
            or string.lower(player.DisplayName) == query then
            return player
        end
    end
    return nil
end

local function nearestPlayer()
    local nearest, best
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local distance = getDistance(player)
            if distance and (not best or distance < best) then
                nearest, best = player, distance
            end
        end
    end
    return nearest, best
end

local function serverSummary(record)
    local date = os.date("%Y-%m-%d %H:%M", tonumber(record.LastSeen or record.FirstSeen or 0))
    return string.format("%s | place %s | %d players | last seen %s",
        tostring(record.PlaceName or "Roblox server"),
        tostring(record.PlaceId or "?"),
        #(record.Players or {}),
        date)
end

local function exportHistory()
    local lines = {
        "MAXIM COMPANION HUB — LOCAL HISTORY",
        "Exported: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "",
        "SERVER HISTORY:",
    }
    for _, server in ipairs(State.ServerHistory) do
        table.insert(lines, serverSummary(server))
        table.insert(lines, "  JobId: " .. tostring(server.JobId or ""))
        for _, p in ipairs(server.Players or {}) do
            table.insert(lines, string.format("  %s (@%s) | UserId %s | seen %s",
                tostring(p.DisplayName or p.Name or "?"),
                tostring(p.Name or "?"),
                tostring(p.UserId or "?"),
                os.date("%Y-%m-%d %H:%M", tonumber(p.SeenAt or 0))))
        end
    end
    table.insert(lines, "")
    table.insert(lines, "EVENTS:")
    for _, event in ipairs(State.Events) do
        table.insert(lines, string.format("[%s] %s | place %s | JobId %s",
            os.date("%Y-%m-%d %H:%M:%S", tonumber(event.Time or 0)),
            tostring(event.Message or ""),
            tostring(event.PlaceId or ""),
            tostring(event.JobId or "")))
    end
    local output = table.concat(lines, "\n")
    if writefileFn then
        ensureFolder()
        local ok, err = pcall(writefileFn, EXPORT_PATH, output)
        if ok then notify("Экспорт", "История сохранена в " .. EXPORT_PATH)
        else notify("Экспорт", "Не удалось записать файл: " .. tostring(err)) end
    else
        copyText(output)
        notify("Экспорт", "Файловое сохранение недоступно; текст отправлен в буфер/консоль.")
    end
end

-- Record this server and this initial roster.
local currentRecord = recordCurrentServer()
State.LastSavedServerId = currentRecord.Key
addEvent("Сессия началась; записан текущий сервер")

--========================================================
-- RAYFIELD LOADER
--========================================================
Rayfield = nil
do
    local loaderError
    local sources = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    for _, url in ipairs(sources) do
        local ok, result = pcall(function()
            local source
            local okHttp, httpResult = pcall(function() return game:HttpGet(url) end)
            if okHttp and type(httpResult) == "string" and #httpResult > 0 then
                source = httpResult
            else
                local requestFn = optionalFunction("http_request") or optionalFunction("request")
                if requestFn then
                    local response = requestFn({Url = url, Method = "GET"})
                    source = response and response.Body
                else
                    error("HTTP-запросы недоступны")
                end
            end
            if type(source) ~= "string" or #source == 0 then error("Пустой ответ: " .. url) end
            if type(loadstring) ~= "function" then error("loadstring недоступен") end
            local compiled, compileErr = loadstring(source)
            if not compiled then error(tostring(compileErr)) end
            return compiled()
        end)
        if ok and type(result) == "table" and type(result.CreateWindow) == "function" then
            Rayfield = result
            break
        else
            loaderError = tostring(result)
            warn("[Companion Hub] Rayfield source failed: " .. url .. " | " .. loaderError)
        end
    end
    if not Rayfield then
        warn("[Companion Hub] Не удалось загрузить Rayfield: " .. tostring(loaderError))
        return
    end
end

local Window
local winOk, winResult = pcall(function()
    return Rayfield:CreateWindow({
        Name = "MAXIM | COMPANION HUB v8",
        LoadingTitle = "Companion Hub",
        LoadingSubtitle = "Сделано Максимом",
        ConfigurationSaving = {Enabled = false},
        Discord = {Enabled = false},
        KeySystem = false,
    })
end)
if not winOk or not winResult then
    warn("[Companion Hub] CreateWindow failed: " .. tostring(winResult))
    return
end
Window = winResult

--========================================================
-- TABS
--========================================================
local DashboardTab = Window:CreateTab("Dashboard", 4483362458)
local TargetTab = Window:CreateTab("Target", 4483362458)
local RadarTab = Window:CreateTab("Radar", 4483362458)
local PlayersTab = Window:CreateTab("Players", 4483362458)
local FriendsTab = Window:CreateTab("Friend Notes", 4483362458)
local HistoryTab = Window:CreateTab("History", 4483362458)
local ServersTab = Window:CreateTab("Server History", 4483362458)
local ServerTab = Window:CreateTab("Server", 4483362458)
local VaultTab = Window:CreateTab("Склад", 4483362458)

local function safeParagraph(tab, title, content)
    pcall(function() tab:CreateParagraph({Title = title, Content = content}) end)
end

safeParagraph(DashboardTab, "MAXIM COMPANION HUB", "Сделано Максимом\nЛокальные инструменты для игроков, заметок и истории серверов.")
safeParagraph(DashboardTab, "Ограничения", "История содержит только игроков, которых ваш клиент видел в посещённых серверах. Глобальный поиск игроков по всем серверам недоступен.")
safeParagraph(DashboardTab, "Хранилище", writefileFn and ("Файловое сохранение доступно: " .. DATA_PATH) or "Файловые функции не найдены. Данные могут пропасть после перезапуска.")

DashboardTab:CreateButton({
    Name = "Обновить снимок текущего сервера",
    Callback = function()
        recordCurrentServer()
        notify("Снимок", "Состав текущего сервера обновлён.")
    end
})
DashboardTab:CreateButton({
    Name = "Экспортировать историю",
    Callback = exportHistory
})
DashboardTab:CreateButton({
    Name = "Показать статистику",
    Callback = function()
        local totalPlayers = 0
        for _, server in ipairs(State.ServerHistory) do totalPlayers = totalPlayers + #(server.Players or {}) end
        notify("Статистика", string.format("Серверов: %d | Записей игроков по серверам: %d | Событий: %d",
            #State.ServerHistory, totalPlayers, #State.Events))
    end
})

-- TARGET
local targetInput = ""
TargetTab:CreateInput({
    Name = "Username / DisplayName / UserId",
    PlaceholderText = "Например: Builderman или UserId",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) targetInput = value end
})
TargetTab:CreateButton({
    Name = "Найти в текущем сервере",
    Callback = function()
        local player = playerByQuery(targetInput)
        if not player then
            notify("Поиск", "Игрок не найден в текущем сервере.")
            return
        end
        State.CurrentTargetUserId = player.UserId
        local distance = getDistance(player)
        notify("Игрок найден", string.format("%s (@%s) | UserId %d | дистанция %s studs",
            player.DisplayName, player.Name, player.UserId, tostring(distance or "неизвестна")))
    end
})
TargetTab:CreateButton({
    Name = "Выбрать ближайшего игрока",
    Callback = function()
        local player, distance = nearestPlayer()
        if not player then notify("Радар", "Не удалось найти игрока с загруженным персонажем."); return end
        State.CurrentTargetUserId = player.UserId
        notify("Ближайший игрок", string.format("%s (@%s) — %d studs", player.DisplayName, player.Name, distance))
    end
})
TargetTab:CreateButton({
    Name = "Сохранить выбранного игрока в заметки",
    Callback = function()
        local id = tonumber(State.CurrentTargetUserId)
        if not id then notify("Заметки", "Сначала найди игрока или выбери ближайшего."); return end
        local player
        for _, p in ipairs(Players:GetPlayers()) do if p.UserId == id then player = p break end end
        if not player then notify("Заметки", "Выбранного игрока уже нет в текущем сервере."); return end
        State.FriendNotes[tostring(player.UserId)] = {
            UserId = player.UserId, Name = player.Name, DisplayName = player.DisplayName,
            Note = "Встречен в игре; хотел добавить в друзья", UpdatedAt = os.time()
        }
        saveData()
        addEvent("Добавлена заметка: @" .. player.Name)
        notify("Заметки", "Игрок сохранён.")
    end
})

-- RADAR
RadarTab:CreateButton({
    Name = "Сканировать дистанции",
    Callback = function()
        local rows = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local distance = getDistance(player)
                table.insert(rows, {Player = player, Distance = distance})
            end
        end
        table.sort(rows, function(a, b)
            if not a.Distance then return false end
            if not b.Distance then return true end
            return a.Distance < b.Distance
        end)
        local lines = {}
        for i = 1, math.min(#rows, 12) do
            local row = rows[i]
            table.insert(lines, string.format("%s (@%s): %s studs",
                row.Player.DisplayName, row.Player.Name, tostring(row.Distance or "?")))
        end
        notify("Radar", #lines > 0 and table.concat(lines, "\n") or "Других игроков не найдено.")
    end
})
safeParagraph(RadarTab, "Единицы", "Дистанция указана в Roblox studs, не в метрах.")

-- PLAYERS
PlayersTab:CreateButton({
    Name = "Показать игроков текущего сервера",
    Callback = function()
        local lines = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local distance = getDistance(p)
                table.insert(lines, string.format("%s (@%s) | ID %d | %s studs",
                    p.DisplayName, p.Name, p.UserId, tostring(distance or "?")))
            end
        end
        notify("Игроки сервера", #lines > 0 and table.concat(lines, "\n") or "На сервере больше никого нет.")
    end
})
PlayersTab:CreateButton({
    Name = "Сохранить снимок состава сервера",
    Callback = function()
        recordCurrentServer()
        addEvent("Снимок состава сервера сохранён")
        notify("История", "Игроки текущего сервера записаны.")
    end
})

-- FRIEND NOTES
local noteUserInput, noteTextInput = "", ""
FriendsTab:CreateInput({
    Name = "Username или UserId",
    PlaceholderText = "Имя или числовой UserId",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) noteUserInput = value end
})
FriendsTab:CreateInput({
    Name = "Текст заметки",
    PlaceholderText = "Где встретились, о чём говорили...",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) noteTextInput = value end
})
FriendsTab:CreateButton({
    Name = "Сохранить заметку",
    Callback = function()
        local query = trim(noteUserInput)
        if query == "" then notify("Заметки", "Введи username или UserId."); return end
        local player = playerByQuery(query)
        local id, name, displayName
        if player then
            id, name, displayName = player.UserId, player.Name, player.DisplayName
        elseif tonumber(query) then
            id, name, displayName = tonumber(query), query, query
        else
            id, name, displayName = nil, query, query
        end
        local key = id and tostring(id) or ("name:" .. string.lower(name))
        State.FriendNotes[key] = {
            UserId = id, Name = name, DisplayName = displayName,
            Note = trim(noteTextInput), UpdatedAt = os.time()
        }
        saveData()
        addEvent("Сохранена заметка: " .. name)
        notify("Заметки", "Запись сохранена локально.")
    end
})
FriendsTab:CreateButton({
    Name = "Показать сохранённые заметки",
    Callback = function()
        local lines = {}
        for _, note in pairs(State.FriendNotes) do
            table.insert(lines, string.format("%s (@%s) | ID %s | %s",
                tostring(note.DisplayName or note.Name or "?"),
                tostring(note.Name or "?"), tostring(note.UserId or "?"),
                tostring(note.Note or "")))
        end
        table.sort(lines)
        notify("Friend Notes", #lines > 0 and table.concat(lines, "\n") or "Заметок пока нет.")
    end
})
FriendsTab:CreateButton({
    Name = "Удалить заметку по Username/UserId",
    Callback = function()
        local query = string.lower(trim(noteUserInput))
        if query == "" then notify("Заметки", "Введи username или UserId в первое поле."); return end
        local removed = false
        for key, note in pairs(State.FriendNotes) do
            if tostring(note.UserId or "") == query or string.lower(tostring(note.Name or "")) == query then
                State.FriendNotes[key] = nil
                removed = true
            end
        end
        saveData()
        notify("Заметки", removed and "Запись удалена." or "Совпадений не найдено.")
    end
})

-- HISTORY
HistoryTab:CreateButton({
    Name = "Показать последние события",
    Callback = function()
        local lines = {}
        for i = 1, math.min(#State.Events, 12) do
            local e = State.Events[i]
            table.insert(lines, os.date("%m-%d %H:%M", tonumber(e.Time or 0)) .. " — " .. tostring(e.Message))
        end
        notify("История событий", #lines > 0 and table.concat(lines, "\n") or "История пока пуста.")
    end
})
HistoryTab:CreateButton({
    Name = "Сохранить историю в файл / буфер",
    Callback = exportHistory
})
HistoryTab:CreateButton({
    Name = "Очистить историю событий",
    Callback = function()
        State.Events = {}
        saveData()
        notify("История", "События очищены.")
    end
})

-- SERVER HISTORY / WEEKLY WARNING
local function showServerViewer(record)
    local gui = PlayerGui:FindFirstChild("MaximServerHistoryViewer")
    if gui then gui:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "MaximServerHistoryViewer"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000000
    gui.Parent = PlayerGui

    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(.5, .5)
    panel.Position = UDim2.fromScale(.5, .5)
    panel.Size = UDim2.fromScale(.88, .72)
    panel.BackgroundColor3 = Color3.fromRGB(15, 19, 32)
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -60, 0, 48)
    header.Position = UDim2.fromOffset(12, 4)
    header.BackgroundTransparency = 1
    header.TextColor3 = Color3.fromRGB(100, 220, 255)
    header.Font = Enum.Font.GothamBold
    header.TextScaled = true
    header.Text = tostring(record.PlaceName or "Сохранённый сервер")
    header.Parent = panel

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(40, 36)
    close.Position = UDim2.new(1, -46, 0, 8)
    close.Text = "X"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.BackgroundColor3 = Color3.fromRGB(125, 45, 55)
    close.Font = Enum.Font.GothamBold
    close.TextScaled = true
    close.Parent = panel
    close.MouseButton1Click:Connect(function() gui:Destroy() end)

    local info = Instance.new("TextLabel")
    info.Position = UDim2.fromOffset(12, 52)
    info.Size = UDim2.new(1, -24, 0, 44)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(210, 215, 230)
    info.Font = Enum.Font.Code
    info.TextScaled = true
    info.TextWrapped = true
    info.Text = string.format("PlaceId: %s | JobId: %s\nПоследний визит: %s",
        tostring(record.PlaceId or "?"), tostring(record.JobId or "?"),
        os.date("%Y-%m-%d %H:%M", tonumber(record.LastSeen or 0)))
    info.Parent = panel

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(10, 102)
    scroll.Size = UDim2.new(1, -20, 1, -114)
    scroll.BackgroundColor3 = Color3.fromRGB(22, 27, 43)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = scroll

    local roster = record.Players or {}
    table.sort(roster, function(a, b)
        return string.lower(tostring(a.Name or "")) < string.lower(tostring(b.Name or ""))
    end)

    for _, savedPlayer in ipairs(roster) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 66)
        row.BackgroundColor3 = Color3.fromRGB(31, 38, 58)
        row.BorderSizePixel = 0
        row.Parent = scroll
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 8)
        rc.Parent = row

        local avatar = Instance.new("ImageLabel")
        avatar.Size = UDim2.fromOffset(52, 52)
        avatar.Position = UDim2.fromOffset(7, 7)
        avatar.BackgroundColor3 = Color3.fromRGB(50, 58, 80)
        avatar.BorderSizePixel = 0
        avatar.Parent = row

        local userId = tonumber(savedPlayer.UserId)
        if userId then
            task.spawn(function()
                local ok, imageUrl = pcall(function()
                    return Players:GetUserThumbnailAsync(
                        userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100
                    )
                end)
                if ok and avatar.Parent then avatar.Image = imageUrl end
            end)
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.fromOffset(68, 4)
        nameLabel.Size = UDim2.new(1, -76, 0, 30)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.new(1, 1, 1)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Text = tostring(savedPlayer.DisplayName or savedPlayer.Name or "Unknown")
            .. "  @" .. tostring(savedPlayer.Name or "?")
        nameLabel.Parent = row

        local sub = Instance.new("TextLabel")
        sub.Position = UDim2.fromOffset(68, 32)
        sub.Size = UDim2.new(1, -76, 0, 26)
        sub.BackgroundTransparency = 1
        sub.TextColor3 = Color3.fromRGB(175, 185, 205)
        sub.Font = Enum.Font.Code
        sub.TextSize = 11
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.Text = "UserId: " .. tostring(savedPlayer.UserId or "?")
            .. " | Видели: " .. os.date("%m-%d %H:%M", tonumber(savedPlayer.SeenAt or 0))
        sub.Parent = row
    end

    if #roster == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -16, 0, 70)
        empty.BackgroundTransparency = 1
        empty.TextColor3 = Color3.new(1, 1, 1)
        empty.TextWrapped = true
        empty.Text = "Список игроков для этого сервера не сохранён."
        empty.Parent = scroll
    end
end

local function oldServerCount()
    local cutoff = os.time() - 7 * 24 * 60 * 60
    local count = 0
    for _, server in ipairs(State.ServerHistory) do
        if tonumber(server.LastSeen or server.FirstSeen or 0) < cutoff then count = count + 1 end
    end
    return count
end

ServersTab:CreateButton({
    Name = "Показать сохранённые серверы",
    Callback = function()
        if #State.ServerHistory == 0 then notify("Серверы", "Сохранённых серверов пока нет."); return end
        for i, record in ipairs(State.ServerHistory) do
            local label = string.format("%02d. %s", i, serverSummary(record))
            pcall(function()
                ServersTab:CreateButton({
                    Name = label,
                    Callback = function() showServerViewer(record) end
                })
            end)
        end
        notify("Серверы", "Кнопки серверов добавлены в эту вкладку. Нажми нужную, чтобы увидеть сохранённых игроков и аватары.")
    end
})
ServersTab:CreateButton({
    Name = "Открыть самый последний сервер",
    Callback = function()
        local record = State.ServerHistory[1]
        if record then showServerViewer(record) else notify("Серверы", "История пуста.") end
    end
})
ServersTab:CreateButton({
    Name = "Удалить серверы, не посещавшиеся 7+ дней",
    Callback = function()
        local cutoff = os.time() - 7 * 24 * 60 * 60
        local kept, removed = {}, 0
        for _, record in ipairs(State.ServerHistory) do
            if tonumber(record.LastSeen or record.FirstSeen or 0) >= cutoff then
                table.insert(kept, record)
            else
                removed = removed + 1
            end
        end
        State.ServerHistory = kept
        saveData()
        notify("Очистка серверов", "Удалено: " .. removed .. ". Осталось: " .. #kept)
    end
})
ServersTab:CreateButton({
    Name = "Показать предупреждение о старых серверах",
    Callback = function()
        local count = oldServerCount()
        if count > 0 then
            notify("Память истории", string.format("%d сервер(ов) не посещались больше недели. При желании удали старые записи.", count))
        else
            notify("Память истории", "Серверов старше недели нет.")
        end
    end
})

-- SERVER / MANUAL JOIN
local jobIdInput = ""
ServerTab:CreateInput({
    Name = "Известный JobId для ручного подключения",
    PlaceholderText = "Вставь сохранённый JobId",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) jobIdInput = value end
})
ServerTab:CreateButton({
    Name = "Подключиться к указанному серверу",
    Callback = function()
        local jobId = trim(jobIdInput)
        if jobId == "" then notify("Подключение", "Введи JobId."); return end
        if jobId == game.JobId then notify("Подключение", "Ты уже в этом сервере."); return end
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
        end)
        if not ok then notify("Подключение не удалось", tostring(err)) end
    end
})
ServerTab:CreateButton({
    Name = "Скопировать JobId текущего сервера",
    Callback = function()
        local text = tostring(game.JobId)
        if copyText(text) then notify("JobId", "Скопировано: " .. text)
        else notify("JobId", "JobId выведен в консоль, если буфер недоступен.") end
    end
})
ServerTab:CreateButton({
    Name = "Сохранить текущий сервер в историю",
    Callback = function()
        recordCurrentServer()
        addEvent("Сервер вручную сохранён в историю")
        notify("Сервер", "Текущий сервер и видимые игроки сохранены.")
    end
})

--========================================================
-- VAULT / LOCAL SERVER BOOKMARKS + HISTORY SEARCH
-- This section works only with records this client has already seen.
-- It does not scan public servers or locate users globally.
--========================================================
local function bookmarkKey(record)
    return tostring(record.PlaceId or game.PlaceId) .. ":" .. tostring(record.JobId or "")
end

local function getBookmarkedCount()
    local count = 0
    for _, item in pairs(State.Bookmarks) do
        if type(item) == "table" then count = count + 1 end
    end
    return count
end

local function bookmarkServer(record, customLabel)
    if type(record) ~= "table" or trim(record.JobId) == "" then
        return false, "У этой записи нет JobId."
    end
    local key = bookmarkKey(record)
    State.Bookmarks[key] = {
        Key = key,
        PlaceId = tonumber(record.PlaceId) or game.PlaceId,
        JobId = tostring(record.JobId),
        PlaceName = tostring(record.PlaceName or game.Name or "Roblox server"),
        Label = trim(customLabel) ~= "" and trim(customLabel) or tostring(record.PlaceName or game.Name or "Сохранённый сервер"),
        SavedAt = os.time(),
        LastSeen = tonumber(record.LastSeen or record.FirstSeen or os.time()),
        PlayerCount = tonumber(record.PlayerCount) or #(record.Players or {}),
    }
    saveData()
    return true, key
end

local function sortedBookmarks()
    local rows = {}
    for key, item in pairs(State.Bookmarks) do
        if type(item) == "table" and trim(item.JobId) ~= "" then
            item.Key = item.Key or key
            table.insert(rows, item)
        end
    end
    table.sort(rows, function(a, b)
        return tonumber(a.SavedAt or 0) > tonumber(b.SavedAt or 0)
    end)
    return rows
end

local function findLocalHistoryMatches(query)
    query = string.lower(trim(query))
    local matches = {}
    if query == "" then return matches end
    for _, server in ipairs(State.ServerHistory) do
        local roster = type(server.Players) == "table" and server.Players or {}
        for _, person in ipairs(roster) do
            local username = string.lower(tostring(person.Name or ""))
            local display = string.lower(tostring(person.DisplayName or ""))
            local userId = tostring(person.UserId or "")
            -- Prefer exact username/display name/user id; allow partial username as fallback.
            if username == query or display == query or userId == query then
                table.insert(matches, {Server = server, Player = person, Exact = true})
            elseif #query >= 3 and (username:find(query, 1, true) or display:find(query, 1, true)) then
                table.insert(matches, {Server = server, Player = person, Exact = false})
            end
        end
    end
    table.sort(matches, function(a, b)
        local ta = tonumber(a.Server.LastSeen or a.Server.FirstSeen or 0)
        local tb = tonumber(b.Server.LastSeen or b.Server.FirstSeen or 0)
        if ta == tb then return a.Exact and not b.Exact end
        return ta > tb
    end)
    return matches
end

local lastLocalMatches = {}
local historyUsernameInput = ""
ServerTab:CreateInput({
    Name = "Username в МОЕЙ локальной истории",
    PlaceholderText = "Username / DisplayName / UserId",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) historyUsernameInput = value end
})
ServerTab:CreateButton({
    Name = "Найти в сохранённой истории и показать JobId",
    Callback = function()
        lastLocalMatches = findLocalHistoryMatches(historyUsernameInput)
        if #lastLocalMatches == 0 then
            notify("Локальная история", "Совпадений нет. Поиск работает только по игрокам, которых этот клиент ранее видел и сохранил.")
            return
        end
        local first = lastLocalMatches[1]
        local server = first.Server
        local person = first.Player
        local copied = copyText(tostring(server.JobId or ""))
        local detail = string.format("@%s | %s\nСервер: %s\nСовпадений: %d\nJobId %s",
            tostring(person.Name or "?"), tostring(person.DisplayName or ""),
            tostring(server.PlaceName or "Roblox"), #lastLocalMatches, copied and "скопирован" or "выведен в консоль")
        notify("Найдено в локальной истории", detail)
    end
})
ServerTab:CreateButton({
    Name = "Показать все локальные совпадения",
    Callback = function()
        if #lastLocalMatches == 0 then
            notify("История", "Сначала выполни поиск по сохранённой истории.")
            return
        end
        local lines = {}
        for i = 1, math.min(#lastLocalMatches, 8) do
            local hit = lastLocalMatches[i]
            table.insert(lines, string.format("%d. @%s — %s | %s",
                i, tostring(hit.Player.Name or "?"), tostring(hit.Server.PlaceName or "Roblox"),
                os.date("%m-%d %H:%M", tonumber(hit.Server.LastSeen or hit.Server.FirstSeen or 0))))
        end
        if #lastLocalMatches > 8 then table.insert(lines, "… и ещё " .. (#lastLocalMatches - 8)) end
        notify("Сохранённые совпадения", table.concat(lines, "\n"))
    end
})
ServerTab:CreateButton({
    Name = "Скопировать JobId следующего совпадения",
    Callback = function()
        if #lastLocalMatches < 2 then
            notify("История", "Нет следующего совпадения. Сначала найди игрока, встречавшегося на нескольких сохранённых серверах.")
            return
        end
        table.remove(lastLocalMatches, 1)
        local hit = lastLocalMatches[1]
        local ok = copyText(tostring(hit.Server.JobId or ""))
        notify("JobId", string.format("Совпадение @%s; JobId %s. Вставь его в поле ручного подключения выше.",
            tostring(hit.Player.Name or "?"), ok and "скопирован" or "выведен в консоль"))
    end
})

safeParagraph(VaultTab, "ЛОКАЛЬНЫЙ СКЛАД", "Сохраняй интересные серверы в отдельный список на этом устройстве. Данные записываются в CompanionHub.json, если executor поддерживает файловые функции.")
VaultTab:CreateButton({
    Name = "Положить текущий сервер на склад",
    Callback = function()
        local record = recordCurrentServer()
        local ok, result = bookmarkServer(record, game.Name)
        if ok then
            notify("Склад", "Сервер сохранён. Всего в складе: " .. getBookmarkedCount())
        else
            notify("Склад", tostring(result))
        end
    end
})
VaultTab:CreateButton({
    Name = "Добавить последний сервер из истории на склад",
    Callback = function()
        local record = State.ServerHistory[1]
        if not record then notify("Склад", "История серверов пока пуста."); return end
        local ok, result = bookmarkServer(record, record.PlaceName)
        if ok then notify("Склад", "Последний сервер сохранён. Всего: " .. getBookmarkedCount())
        else notify("Склад", tostring(result)) end
    end
})
VaultTab:CreateButton({
    Name = "Показать склад",
    Callback = function()
        local rows = sortedBookmarks()
        if #rows == 0 then
            notify("Склад пуст", "Сохрани текущий сервер кнопкой выше.")
            return
        end
        local lines = {}
        for i = 1, math.min(#rows, 10) do
            local item = rows[i]
            table.insert(lines, string.format("%02d. %s | PlaceId %s | %d игроков\nJobId: %s",
                i, tostring(item.Label or item.PlaceName or "Сервер"), tostring(item.PlaceId or "?"),
                tonumber(item.PlayerCount or 0), tostring(item.JobId or "")))
        end
        if #rows > 10 then table.insert(lines, "… и ещё " .. (#rows - 10) .. " сохранённых серверов") end
        notify("Склад серверов", table.concat(lines, "\n\n"))
    end
})
VaultTab:CreateButton({
    Name = "Скопировать JobId последнего сохранённого сервера",
    Callback = function()
        local rows = sortedBookmarks()
        if #rows == 0 then notify("Склад", "Склад пуст."); return end
        local item = rows[1]
        local ok = copyText(item.JobId)
        notify("Склад", (ok and "JobId скопирован: " or "JobId выведен в консоль: ") .. tostring(item.JobId)
            .. "\nВставь его в поле ручного подключения на вкладке Server.")
    end
})
VaultTab:CreateButton({
    Name = "Удалить последний сохранённый сервер со склада",
    Callback = function()
        local rows = sortedBookmarks()
        if #rows == 0 then notify("Склад", "Склад уже пуст."); return end
        State.Bookmarks[rows[1].Key] = nil
        saveData()
        notify("Склад", "Удалена запись: " .. tostring(rows[1].Label or rows[1].PlaceName) .. ". Осталось: " .. getBookmarkedCount())
    end
})
VaultTab:CreateButton({
    Name = "Экспортировать склад в буфер / консоль",
    Callback = function()
        local rows = sortedBookmarks()
        if #rows == 0 then notify("Склад", "Нет записей для экспорта."); return end
        local lines = {"MAXIM COMPANION HUB — SERVER VAULT", "Exported: " .. os.date("%Y-%m-%d %H:%M:%S"), ""}
        for _, item in ipairs(rows) do
            table.insert(lines, tostring(item.Label or item.PlaceName or "Сервер"))
            table.insert(lines, "PlaceId: " .. tostring(item.PlaceId or ""))
            table.insert(lines, "JobId: " .. tostring(item.JobId or ""))
            table.insert(lines, "Saved: " .. os.date("%Y-%m-%d %H:%M:%S", tonumber(item.SavedAt or 0)))
            table.insert(lines, "")
        end
        local ok = copyText(table.concat(lines, "\n"))
        notify("Экспорт склада", ok and "Список скопирован." or "Не удалось скопировать; проверь консоль executor.")
    end
})
VaultTab:CreateButton({
    Name = "Очистить склад",
    Callback = function()
        State.Bookmarks = {}
        saveData()
        notify("Склад", "Все закладки удалены. История серверов не затронута.")
    end
})
safeParagraph(VaultTab, "ПРИМЕЧАНИЕ", "Поиск по username проверяет только локальные снимки серверов, которые этот клиент уже посещал. Он не сканирует все серверы Roblox и не отслеживает игроков глобально. Если используешь сохранённый JobId, он может устареть или сервер может стать недоступен.")

--========================================================
-- PLAYER JOIN / LEAVE + PERIODIC SNAPSHOTS
--========================================================
Players.PlayerAdded:Connect(function(player)
    task.defer(function()
        recordCurrentServer()
        addEvent("Игрок вошёл: @" .. player.Name)
        if State.FriendNotes[tostring(player.UserId)] then
            notify("Знакомый игрок", "@" .. player.Name .. " из твоих заметок появился на этом сервере.")
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    addEvent("Игрок вышел: @" .. player.Name)
    task.defer(function()
        recordCurrentServer()
    end)
end)

task.spawn(function()
    while true do
        task.wait(60)
        if not LocalPlayer.Parent then break end
        recordCurrentServer()
        local count = oldServerCount()
        if count > 0 then
            notify("История серверов", string.format("%d сервер(ов) не посещались больше недели. Открой Server History, чтобы удалить старые записи.", count))
            -- Avoid repeating the warning every minute; wait until next day.
            task.wait(23 * 60 * 60)
        end
    end
end)

addEvent("Companion Hub v8 запущен")
if oldServerCount() > 0 then
    task.delay(2, function()
        notify("Предупреждение о памяти", string.format("%d сервер(ов) не посещались больше недели. Можно удалить старые записи во вкладке Server History.", oldServerCount()))
    end)
end

print("[Companion Hub] v8 initialized")
notify("Companion Hub", "Запущен. Данные сохраняются локально, если файловые функции доступны.")

--[[
MAXIM COMPANION HUB v8.1 — INTEGRATION ADD-ON
How to use:
1) Keep the original v8.0 script unchanged.
2) Paste this entire block at the VERY END of the same script, replacing the old
   misplaced mobile-toggle block if you already pasted it there.
3) This must be in the same Lua chunk as v8.0 because it uses its local variables.

What this adds:
- Reliable floating minimize/restore button for Rayfield.
- A searchable avatar list for saved server snapshots.
- Roblox public user search (limited results per request; not millions).
- Roblox public experience/place search and a Play button.
- Uses public Roblox web APIs; executor HTTP support may be required.

Limits:
- Roblox does not expose a public API that searches every live server for a username.
- Public user search finds accounts, not every server they are in.
- Saved server history only contains players this client previously observed.
]]

--========================================================
-- V8.1 SAFE CLEANUP
--========================================================
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local existingToggle = PlayerGui:FindFirstChild("MaximHubMobileToggle")
if existingToggle then existingToggle:Destroy() end

--========================================================
-- HTTP HELPERS FOR PUBLIC ROBLOX SEARCH APIs
--========================================================
local function companionRequest(url)
    local requestFn = optionalFunction("http_request")
        or optionalFunction("request")
        or optionalFunction("http")
    if requestFn then
        local ok, response = pcall(function()
            return requestFn({Url = url, Method = "GET", Headers = {["Accept"] = "application/json"}})
        end)
        if ok and response then
            local body = response.Body or response.body
            if type(body) == "string" and #body > 0 then
                local decodedOk, decoded = pcall(function()
                    return HttpService:JSONDecode(body)
                end)
                if decodedOk then return decoded end
            end
        end
    end

    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then
        local decodedOk, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if decodedOk then return decoded end
    end
    return nil
end

local function encodeQuery(value)
    value = tostring(value or "")
    value = value:gsub("\n", " ")
    return value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function getAvatarUrl(userId)
    local ok, url = pcall(function()
        local image, _ready = Players:GetUserThumbnailAsync(
            tonumber(userId),
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size100x100
        )
        return image
    end)
    return ok and url or ""
end

--========================================================
-- MOBILE MINIMIZE / RESTORE
-- Finds Rayfield windows by their known GUI names and by the
-- GUI objects that were added after this script started.
--========================================================
local rayfieldGuis = {}
local knownNames = {
    Rayfield = true,
    RayfieldMain = true,
    ["MAXIM | COMPANION HUB v8"] = true,
    ["MAXIM | COMPANION HUB v8.1"] = true,
}

local function collectRayfieldGuis()
    local found = {}
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "MaximHubMobileToggle"
            and gui.Name ~= "MaximServerHistoryViewer"
            and gui.Name ~= "MaximCompanionSplash" then
            local nameLooksRelevant = knownNames[gui.Name] == true
                or string.find(string.lower(gui.Name), "rayfield", 1, true) ~= nil
                or string.find(string.lower(gui.Name), "companion", 1, true) ~= nil
            if nameLooksRelevant then found[gui] = true end
        end
    end
    -- Rayfield's GUI name varies between releases. As a fallback, inspect
    -- ScreenGuis for a visible large frame containing typical window controls.
    if next(found) == nil then
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name ~= "MaximHubMobileToggle"
                and gui.Name ~= "MaximServerHistoryViewer" then
                for _, descendant in ipairs(gui:GetDescendants()) do
                    if descendant:IsA("TextButton") and (
                        descendant.Text == "×" or descendant.Text == "X"
                        or string.find(string.lower(descendant.Text), "dashboard", 1, true)
                    ) then
                        found[gui] = true
                        break
                    end
                end
            end
        end
    end
    local list = {}
    for gui in pairs(found) do table.insert(list, gui) end
    return list
end

rayfieldGuis = collectRayfieldGuis()

local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "MaximHubMobileToggle"
toggleGui.ResetOnSpawn = false
toggleGui.IgnoreGuiInset = true
toggleGui.DisplayOrder = 1000001
toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
toggleGui.Parent = PlayerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 0)
toggleButton.Position = UDim2.new(1, -14, 0, 84)
toggleButton.Size = UDim2.fromOffset(54, 50)
toggleButton.BackgroundColor3 = Color3.fromRGB(20, 28, 45)
toggleButton.Text = "×"
toggleButton.TextColor3 = Color3.fromRGB(100, 220, 255)
toggleButton.TextSize = 32
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Active = true
toggleButton.Selectable = true
toggleButton.ZIndex = 20
toggleButton.Parent = toggleGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 14)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(100, 220, 255)
toggleStroke.Thickness = 1.5
toggleStroke.Parent = toggleButton

local minimized = false
local function setRayfieldVisible(visible)
    -- Refresh the list in case Rayfield recreated its root ScreenGui.
    local current = collectRayfieldGuis()
    if #current > 0 then rayfieldGuis = current end

    local changed = 0
    for _, gui in ipairs(rayfieldGuis) do
        if gui and gui.Parent then
            gui.Enabled = visible
            changed += 1
        end
    end

    minimized = not visible
    if minimized then
        toggleButton.Text = "☰"
        toggleButton.Size = UDim2.fromOffset(58, 50)
        toggleButton.BackgroundColor3 = Color3.fromRGB(15, 75, 95)
        toggleStroke.Color = Color3.fromRGB(80, 245, 190)
    else
        toggleButton.Text = "×"
        toggleButton.Size = UDim2.fromOffset(54, 50)
        toggleButton.BackgroundColor3 = Color3.fromRGB(20, 28, 45)
        toggleStroke.Color = Color3.fromRGB(100, 220, 255)
        if changed == 0 then
            notify("Кнопка панели", "Не удалось автоматически найти GUI Rayfield. Проверь версию Rayfield.")
        end
    end
end

toggleButton.Activated:Connect(function()
    setRayfieldVisible(minimized)
end)

-- Drag only after a meaningful movement, so taps still activate the button.
local dragInput, dragStart, dragPosition
local movedDuringDrag = false
toggleButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragInput = input
        dragStart = input.Position
        dragPosition = toggleButton.Position
        movedDuringDrag = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragInput then return end
    local matching = input == dragInput
        or (dragInput.UserInputType == Enum.UserInputType.Touch
            and input.UserInputType == Enum.UserInputType.Touch)
        or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement)
    if not matching then return end

    local delta = input.Position - dragStart
    if math.abs(delta.X) + math.abs(delta.Y) > 8 then movedDuringDrag = true end
    if movedDuringDrag then
        toggleButton.Position = UDim2.new(
            dragPosition.X.Scale, dragPosition.X.Offset + delta.X,
            dragPosition.Y.Scale, dragPosition.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if dragInput and (
        input == dragInput
        or input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    ) then
        dragInput = nil
    end
end)

--========================================================
-- SEARCH GUI HELPERS
--========================================================
local function makeSearchWindow(guiName, titleText)
    local old = PlayerGui:FindFirstChild(guiName)
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = guiName
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 1000002
    gui.Parent = PlayerGui

    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0.92, 0, 0.78, 0)
    panel.BackgroundColor3 = Color3.fromRGB(15, 19, 32)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(280, 300)
    sizeConstraint.MaxSize = Vector2.new(650, 720)
    sizeConstraint.Parent = panel

    local header = Instance.new("TextLabel")
    header.Position = UDim2.fromOffset(14, 8)
    header.Size = UDim2.new(1, -68, 0, 38)
    header.BackgroundTransparency = 1
    header.Text = titleText
    header.TextColor3 = Color3.fromRGB(100, 220, 255)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 19
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = panel

    local close = Instance.new("TextButton")
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -8, 0, 8)
    close.Size = UDim2.fromOffset(42, 38)
    close.BackgroundColor3 = Color3.fromRGB(130, 43, 55)
    close.Text = "×"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 28
    close.Parent = panel
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
    close.Activated:Connect(function() gui:Destroy() end)

    local search = Instance.new("TextBox")
    search.Position = UDim2.fromOffset(12, 54)
    search.Size = UDim2.new(1, -24, 0, 42)
    search.BackgroundColor3 = Color3.fromRGB(29, 36, 55)
    search.TextColor3 = Color3.new(1, 1, 1)
    search.PlaceholderColor3 = Color3.fromRGB(155, 165, 185)
    search.PlaceholderText = "Введи имя для фильтрации..."
    search.Text = ""
    search.ClearTextOnFocus = false
    search.Font = Enum.Font.Gotham
    search.TextSize = 15
    search.Parent = panel
    Instance.new("UICorner", search).CornerRadius = UDim.new(0, 9)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 106)
    scroll.Size = UDim2.new(1, -24, 1, -118)
    scroll.BackgroundColor3 = Color3.fromRGB(22, 27, 43)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = panel
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 9)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = scroll

    return gui, panel, search, scroll, layout
end

local function clearRows(scroll, layout)
    for _, child in ipairs(scroll:GetChildren()) do
        if child ~= layout and not child:IsA("UIPadding") then child:Destroy() end
    end
end

local function addStatusRow(scroll, text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, 54)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(205, 215, 232)
    label.TextWrapped = true
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.Text = text
    label.Parent = scroll
end

--========================================================
-- OVERRIDE SAVED-SERVER VIEWER: SEARCHABLE PLAYER ROSTER
-- Keeps the same function name used by the Server History buttons.
--========================================================
showServerViewer = function(record)
    local gui, panel, search, scroll, layout =
        makeSearchWindow("MaximServerHistoryViewer", tostring(record.PlaceName or "Сохранённый сервер"))

    local info = Instance.new("TextLabel")
    info.Position = UDim2.fromOffset(12, 98)
    info.Size = UDim2.new(1, -24, 0, 0)
    info.AutomaticSize = Enum.AutomaticSize.Y
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(180, 195, 215)
    info.Font = Enum.Font.Code
    info.TextSize = 11
    info.TextWrapped = true
    info.Text = string.format("PlaceId: %s | JobId: %s\nПоследний визит: %s",
        tostring(record.PlaceId or "?"), tostring(record.JobId or "?"),
        os.date("%Y-%m-%d %H:%M", tonumber(record.LastSeen or record.FirstSeen or 0)))
    info.Parent = panel

    search.Position = UDim2.fromOffset(12, 132)
    scroll.Position = UDim2.fromOffset(12, 182)
    scroll.Size = UDim2.new(1, -24, 1, -194)

    local roster = {}
    for _, item in ipairs(record.Players or {}) do table.insert(roster, item) end
    table.sort(roster, function(a, b)
        return string.lower(tostring(a.Name or "")) < string.lower(tostring(b.Name or ""))
    end)

    local function render()
        clearRows(scroll, layout)
        local query = string.lower(trim(search.Text))
        local shown = 0
        for _, savedPlayer in ipairs(roster) do
            local name = tostring(savedPlayer.Name or "")
            local display = tostring(savedPlayer.DisplayName or "")
            local userId = tostring(savedPlayer.UserId or "")
            local haystack = string.lower(name .. " " .. display .. " " .. userId)
            if query == "" or string.find(haystack, query, 1, true) then
                shown += 1
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, -8, 0, 68)
                row.BackgroundColor3 = Color3.fromRGB(31, 38, 58)
                row.BorderSizePixel = 0
                row.LayoutOrder = shown
                row.Parent = scroll
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                local avatar = Instance.new("ImageLabel")
                avatar.Size = UDim2.fromOffset(52, 52)
                avatar.Position = UDim2.fromOffset(7, 8)
                avatar.BackgroundColor3 = Color3.fromRGB(50, 58, 80)
                avatar.BorderSizePixel = 0
                avatar.Parent = row
                Instance.new("UICorner", avatar).CornerRadius = UDim.new(0, 8)

                local id = tonumber(savedPlayer.UserId)
                if id then
                    task.spawn(function()
                        local url = getAvatarUrl(id)
                        if avatar.Parent and url ~= "" then avatar.Image = url end
                    end)
                end

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Position = UDim2.fromOffset(68, 7)
                nameLabel.Size = UDim2.new(1, -76, 0, 28)
                nameLabel.BackgroundTransparency = 1
                nameLabel.TextColor3 = Color3.new(1, 1, 1)
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.TextSize = 14
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.Text = display .. "  @" .. name
                nameLabel.Parent = row

                local sub = Instance.new("TextLabel")
                sub.Position = UDim2.fromOffset(68, 35)
                sub.Size = UDim2.new(1, -76, 0, 24)
                sub.BackgroundTransparency = 1
                sub.TextColor3 = Color3.fromRGB(175, 185, 205)
                sub.Font = Enum.Font.Code
                sub.TextSize = 11
                sub.TextXAlignment = Enum.TextXAlignment.Left
                sub.Text = "UserId: " .. userId .. " | " ..
                    os.date("%m-%d %H:%M", tonumber(savedPlayer.SeenAt or 0))
                sub.Parent = row
            end
        end
        if shown == 0 then addStatusRow(scroll, "Совпадений не найдено.") end
    end
    search:GetPropertyChangedSignal("Text"):Connect(render)
    render()
end

--========================================================
-- GLOBAL PUBLIC USER SEARCH TAB
--========================================================
local GlobalPlayersTab = Window:CreateTab("Player Search", 4483362458)
local globalUserQuery = ""
GlobalPlayersTab:CreateParagraph({
    Title = "Поиск игроков Roblox",
    Content = "Ищет публичные аккаунты по username/display name через официальный веб-поиск Roblox. Это не поиск игроков по всем активным серверам."
})
GlobalPlayersTab:CreateInput({
    Name = "Username или Display Name",
    PlaceholderText = "Например: Builderman",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) globalUserQuery = value end
})
GlobalPlayersTab:CreateButton({
    Name = "Искать аккаунты Roblox",
    Callback = function()
        local query = trim(globalUserQuery)
        if #query < 2 then
            notify("Поиск игроков", "Введи хотя бы 2 символа.")
            return
        end
        local url = "https://users.roblox.com/v1/users/search?keyword="
            .. encodeQuery(query) .. "&limit=10"
        notify("Поиск игроков", "Отправляю запрос к публичному поиску Roblox...")
        task.spawn(function()
            local data = companionRequest(url)
            if type(data) ~= "table" or type(data.data) ~= "table" then
                notify("Поиск игроков", "Запрос не прошёл. Возможно, executor блокирует HTTP или API временно недоступен.")
                return
            end

            local gui, panel, search, scroll, layout =
                makeSearchWindow("MaximGlobalPlayerSearch", "Результаты поиска Roblox")
            search.PlaceholderText = "Фильтр результатов..."
            local results = data.data

            local function renderResults()
                clearRows(scroll, layout)
                local filter = string.lower(trim(search.Text))
                local shown = 0
                for _, user in ipairs(results) do
                    local name = tostring(user.name or "")
                    local display = tostring(user.displayName or name)
                    local id = tonumber(user.id)
                    if string.find(string.lower(name .. " " .. display .. " " .. tostring(id or "")), filter, 1, true) then
                        shown += 1
                        local row = Instance.new("Frame")
                        row.Size = UDim2.new(1, -8, 0, 70)
                        row.BackgroundColor3 = Color3.fromRGB(31, 38, 58)
                        row.BorderSizePixel = 0
                        row.LayoutOrder = shown
                        row.Parent = scroll
                        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                        local avatar = Instance.new("ImageLabel")
                        avatar.Size = UDim2.fromOffset(52, 52)
                        avatar.Position = UDim2.fromOffset(7, 9)
                        avatar.BackgroundColor3 = Color3.fromRGB(50, 58, 80)
                        avatar.BorderSizePixel = 0
                        avatar.Parent = row
                        Instance.new("UICorner", avatar).CornerRadius = UDim.new(0, 8)
                        if id then
                            task.spawn(function()
                                local imageUrl = getAvatarUrl(id)
                                if avatar.Parent and imageUrl ~= "" then avatar.Image = imageUrl end
                            end)
                        end

                        local nameLabel = Instance.new("TextLabel")
                        nameLabel.Position = UDim2.fromOffset(68, 5)
                        nameLabel.Size = UDim2.new(1, -76, 0, 28)
                        nameLabel.BackgroundTransparency = 1
                        nameLabel.TextColor3 = Color3.new(1, 1, 1)
                        nameLabel.Font = Enum.Font.GothamBold
                        nameLabel.TextSize = 14
                        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                        nameLabel.Text = display .. "  @" .. name
                        nameLabel.Parent = row

                        local sub = Instance.new("TextLabel")
                        sub.Position = UDim2.fromOffset(68, 32)
                        sub.Size = UDim2.new(1, -76, 0, 22)
                        sub.BackgroundTransparency = 1
                        sub.TextColor3 = Color3.fromRGB(175, 185, 205)
                        sub.Font = Enum.Font.Code
                        sub.TextSize = 11
                        sub.TextXAlignment = Enum.TextXAlignment.Left
                        sub.Text = "UserId: " .. tostring(id or "?")
                        sub.Parent = row

                        local profile = Instance.new("TextButton")
                        profile.AnchorPoint = Vector2.new(1, 1)
                        profile.Position = UDim2.new(1, -6, 1, -5)
                        profile.Size = UDim2.fromOffset(74, 22)
                        profile.BackgroundColor3 = Color3.fromRGB(15, 75, 95)
                        profile.Text = "Профиль"
                        profile.TextColor3 = Color3.new(1, 1, 1)
                        profile.Font = Enum.Font.Gotham
                        profile.TextSize = 11
                        profile.Parent = row
                        Instance.new("UICorner", profile).CornerRadius = UDim.new(0, 6)
                        profile.Activated:Connect(function()
                            if id then
                                local profileUrl = "https://www.roblox.com/users/" .. tostring(id) .. "/profile"
                                local openFn = optionalFunction("open_url") or optionalFunction("openurl")
                                if openFn then pcall(openFn, profileUrl)
                                else copyText(profileUrl); notify("Профиль", "Ссылка на профиль скопирована/выведена.") end
                            end
                        end)
                    end
                end
                if shown == 0 then addStatusRow(scroll, "Нет совпадений в полученных результатах.") end
            end
            search:GetPropertyChangedSignal("Text"):Connect(renderResults)
            renderResults()
        end)
    end
})

--========================================================
-- PUBLIC EXPERIENCE / PLACE SEARCH TAB
--========================================================
local PlacesTab = Window:CreateTab("Place Search", 4483362458)
local placeQuery = ""
PlacesTab:CreateParagraph({
    Title = "Поиск плейсов",
    Content = "Ищет публичные Roblox experiences. Количество результатов ограничено API; кнопка Play пытается открыть выбранный плейс."
})
PlacesTab:CreateInput({
    Name = "Название плейса",
    PlaceholderText = "Например: Brookhaven",
    RemoveTextAfterFocusLost = false,
    Callback = function(value) placeQuery = value end
})
PlacesTab:CreateButton({
    Name = "Искать плейсы",
    Callback = function()
        local query = trim(placeQuery)
        if #query < 2 then notify("Поиск плейсов", "Введи хотя бы 2 символа."); return end
        local url = "https://games.roblox.com/v1/games/list?model.keyword="
            .. encodeQuery(query) .. "&model.maxRows=10&model.startRows=0"
        notify("Поиск плейсов", "Отправляю запрос к публичному поиску Roblox...")
        task.spawn(function()
            local data = companionRequest(url)
            if type(data) ~= "table" then
                notify("Поиск плейсов", "Не удалось получить ответ. HTTP может быть недоступен в executor.")
                return
            end
            local results = data.games or data.data or data
            if type(results) ~= "table" then
                notify("Поиск плейсов", "API вернул неизвестный формат.")
                return
            end

            local gui, panel, search, scroll, layout =
                makeSearchWindow("MaximPlaceSearch", "Результаты поиска плейсов")
            search.PlaceholderText = "Фильтр названий..."
            local function renderPlaces()
                clearRows(scroll, layout)
                local filter = string.lower(trim(search.Text))
                local shown = 0
                for _, place in ipairs(results) do
                    local name = tostring(place.name or place.title or place.Name or "Unknown experience")
                    local description = tostring(place.description or place.Description or "")
                    local placeId = tonumber(place.placeId or place.rootPlaceId or place.id or place.universeId)
                    if string.find(string.lower(name .. " " .. description), filter, 1, true) then
                        shown += 1
                        local row = Instance.new("Frame")
                        row.Size = UDim2.new(1, -8, 0, 82)
                        row.BackgroundColor3 = Color3.fromRGB(31, 38, 58)
                        row.BorderSizePixel = 0
                        row.LayoutOrder = shown
                        row.Parent = scroll
                        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                        local nameLabel = Instance.new("TextLabel")
                        nameLabel.Position = UDim2.fromOffset(10, 5)
                        nameLabel.Size = UDim2.new(1, -100, 0, 28)
                        nameLabel.BackgroundTransparency = 1
                        nameLabel.TextColor3 = Color3.new(1, 1, 1)
                        nameLabel.Font = Enum.Font.GothamBold
                        nameLabel.TextSize = 14
                        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                        nameLabel.Text = name
                        nameLabel.Parent = row

                        local sub = Instance.new("TextLabel")
                        sub.Position = UDim2.fromOffset(10, 34)
                        sub.Size = UDim2.new(1, -20, 0, 20)
                        sub.BackgroundTransparency = 1
                        sub.TextColor3 = Color3.fromRGB(175, 185, 205)
                        sub.Font = Enum.Font.Code
                        sub.TextSize = 11
                        sub.TextXAlignment = Enum.TextXAlignment.Left
                        sub.Text = "PlaceId: " .. tostring(placeId or "не найден")
                        sub.Parent = row

                        local play = Instance.new("TextButton")
                        play.AnchorPoint = Vector2.new(1, 0.5)
                        play.Position = UDim2.new(1, -8, 0.5, 0)
                        play.Size = UDim2.fromOffset(78, 34)
                        play.BackgroundColor3 = Color3.fromRGB(20, 120, 80)
                        play.Text = "PLAY"
                        play.TextColor3 = Color3.new(1, 1, 1)
                        play.Font = Enum.Font.GothamBold
                        play.TextSize = 13
                        play.Parent = row
                        Instance.new("UICorner", play).CornerRadius = UDim.new(0, 8)
                        play.Activated:Connect(function()
                            if not placeId then
                                notify("Play", "В ответе API не найден PlaceId для этого результата.")
                                return
                            end
                            local ok, err = pcall(function()
                                TeleportService:Teleport(placeId, LocalPlayer)
                            end)
                            if not ok then notify("Play", "Не удалось начать переход: " .. tostring(err)) end
                        end)
                    end
                end
                if shown == 0 then addStatusRow(scroll, "Нет совпадений. Попробуй другое название.") end
            end
            search:GetPropertyChangedSignal("Text"):Connect(renderPlaces)
            renderPlaces()
        end)
    end
})

--========================================================
-- VERSION NOTE
--========================================================
addEvent("Companion Hub v8.1 add-on активирован")
notify("Companion Hub v8.1", "Крестик, поиск аккаунтов, поиск плейсов и фильтр истории подключены.")
print("[Companion Hub] v8.1 add-on initialized")

--========================================================
-- MAXIM SOCIAL LOUNGE v1.0 (CLOUD CHAT ADD-ON)
-- Configure API_BASE after deploying the companion backend.
-- This is an external community chat, not Roblox's official chat.
-- Do not use it to evade Roblox moderation or share personal data.
--========================================================
do
    local API_BASE = "https://maxim-social-lounge.onrender.com"
    local POLL_SECONDS = 4
    local MAX_MESSAGE_LENGTH = 180
    local socialGuiName = "MaximSocialLounge"
    local triggerGuiName = "MaximSocialLoungeToggle"
    local oldSocial = PlayerGui:FindFirstChild(socialGuiName)
    if oldSocial then oldSocial:Destroy() end
    local oldTrigger = PlayerGui:FindFirstChild(triggerGuiName)
    if oldTrigger then oldTrigger:Destroy() end

    local requestFn = optionalFunction("http_request") or optionalFunction("request") or optionalFunction("http")
    local function apiCall(method, path, payload)
        if not requestFn then return false, "В executor нет HTTP request-функции." end
        local ok, response = pcall(function()
            local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
            -- Некоторые executor HTTP-клиенты поддерживают Timeout; остальные его проигнорируют.
            local args = { Url = API_BASE .. path, Method = method, Headers = headers, Timeout = 12 }
            if payload then args.Body = HttpService:JSONEncode(payload) end
            return requestFn(args)
        end)
        if not ok or not response then return false, "HTTP-запрос не выполнен." end
        local status = tonumber(response.StatusCode or response.Status or 0) or 0
        local body = response.Body or response.body or ""
        local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if status < 200 or status >= 300 then
            local msg = decodedOk and type(decoded) == "table" and decoded.error or "HTTP " .. tostring(status)
            return false, tostring(msg)
        end
        if not decodedOk then return false, "Сервер вернул некорректный JSON." end
        return true, decoded
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = socialGuiName
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 1000004
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = false
    gui.Parent = PlayerGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.52)
    panel.Size = UDim2.new(0.92, 0, 0.76, 0)
    panel.BackgroundColor3 = Color3.fromRGB(12, 16, 29)
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
    local stroke = Instance.new("UIStroke", panel)
    stroke.Color = Color3.fromRGB(76, 203, 235)
    stroke.Transparency = 0.2
    stroke.Thickness = 1.3
    local sizeConstraint = Instance.new("UISizeConstraint", panel)
    sizeConstraint.MinSize = Vector2.new(280, 330)
    sizeConstraint.MaxSize = Vector2.new(560, 620)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Color3.fromRGB(20, 30, 49)
    header.BorderSizePixel = 0
    header.Parent = panel
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)
    local title = Instance.new("TextLabel")
    title.Position = UDim2.fromOffset(14, 0)
    title.Size = UDim2.new(1, -112, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "✦ SOCIAL LOUNGE"
    title.TextColor3 = Color3.fromRGB(100, 220, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local function makeButton(parent, text, position, size, color)
        local b = Instance.new("TextButton")
        b.Position = position
        b.Size = size
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 18
        b.AutoButtonColor = true
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)
        return b
    end
    local minimize = makeButton(header, "—", UDim2.new(1, -88, 0, 7), UDim2.fromOffset(36, 34), Color3.fromRGB(40, 66, 88))
    local close = makeButton(header, "×", UDim2.new(1, -46, 0, 7), UDim2.fromOffset(36, 34), Color3.fromRGB(130, 43, 55))

    local status = Instance.new("TextLabel")
    status.Position = UDim2.fromOffset(12, 52)
    status.Size = UDim2.new(1, -24, 0, 25)
    status.BackgroundTransparency = 1
    status.Text = "Подключение не настроено"
    status.TextColor3 = Color3.fromRGB(180, 190, 210)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = panel

    local feed = Instance.new("ScrollingFrame")
    feed.Position = UDim2.fromOffset(10, 80)
    feed.Size = UDim2.new(1, -20, 1, -174)
    feed.BackgroundColor3 = Color3.fromRGB(20, 26, 42)
    feed.BackgroundTransparency = 0.08
    feed.BorderSizePixel = 0
    feed.ScrollBarThickness = 4
    feed.AutomaticCanvasSize = Enum.AutomaticSize.Y
    feed.CanvasSize = UDim2.new(0, 0, 0, 0)
    feed.Parent = panel
    Instance.new("UICorner", feed).CornerRadius = UDim.new(0, 10)
    local feedPadding = Instance.new("UIPadding", feed)
    feedPadding.PaddingTop = UDim.new(0, 8)
    feedPadding.PaddingBottom = UDim.new(0, 8)
    feedPadding.PaddingLeft = UDim.new(0, 8)
    feedPadding.PaddingRight = UDim.new(0, 8)
    local layout = Instance.new("UIListLayout", feed)
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local input = Instance.new("TextBox")
    input.Position = UDim2.new(0, 10, 1, -82)
    input.Size = UDim2.new(1, -92, 0, 42)
    input.BackgroundColor3 = Color3.fromRGB(30, 38, 57)
    input.BorderSizePixel = 0
    input.Text = ""
    input.PlaceholderText = "Напиши сообщение..."
    input.PlaceholderColor3 = Color3.fromRGB(150, 160, 180)
    input.TextColor3 = Color3.new(1, 1, 1)
    input.Font = Enum.Font.Gotham
    input.TextSize = 14
    input.ClearTextOnFocus = false
    input.TextXAlignment = Enum.TextXAlignment.Left
    input.Parent = panel
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 9)
    local send = makeButton(panel, "➤", UDim2.new(1, -72, 1, -82), UDim2.fromOffset(62, 42), Color3.fromRGB(18, 122, 147))
    local quick = Instance.new("Frame")
    quick.Position = UDim2.new(0, 10, 1, -34)
    quick.Size = UDim2.new(1, -20, 0, 28)
    quick.BackgroundTransparency = 1
    quick.Parent = panel
    local quickLayout = Instance.new("UIListLayout", quick)
    quickLayout.FillDirection = Enum.FillDirection.Horizontal
    quickLayout.Padding = UDim.new(0, 6)
    quickLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local quickItems = {{"👋", "Всем привет! 👋"}, {"🎮", "Кто хочет поиграть? 🎮"}, {"GG", "GG! ✨"}, {"😂", "😂😂😂"}}
    for _, item in ipairs(quickItems) do
        local b = makeButton(quick, item[1], UDim2.new(), UDim2.new(0.25, -5, 1, 0), Color3.fromRGB(38, 52, 76))
        b.TextSize = 13
        b.Activated:Connect(function() input.Text = item[2]; input:CaptureFocus() end)
    end

    local triggerGui = Instance.new("ScreenGui")
    triggerGui.Name = triggerGuiName
    triggerGui.ResetOnSpawn = false
    triggerGui.IgnoreGuiInset = true
    triggerGui.DisplayOrder = 1000005
    triggerGui.Parent = PlayerGui
    local trigger = makeButton(triggerGui, "✦", UDim2.new(1, -72, 0.55, 0), UDim2.fromOffset(54, 54), Color3.fromRGB(15, 77, 100))
    trigger.AnchorPoint = Vector2.new(0, 0)
    trigger.TextSize = 25
    trigger.Active = true
    trigger.Draggable = false
    Instance.new("UIStroke", trigger).Color = Color3.fromRGB(100, 220, 255)

    local minimized = false
    local function setOpen(open)
        if open then
            minimized = false
            gui.Enabled = true
            panel.Visible = true
            trigger.Text = "✦"
        else
            gui.Enabled = false
            trigger.Text = "✦"
        end
    end
    trigger.Activated:Connect(function()
        if minimized then
            minimized = false
            gui.Enabled = true
            panel.Visible = true
        else
            gui.Enabled = not gui.Enabled
        end
    end)
    minimize.Activated:Connect(function()
        minimized = true
        panel.Visible = false
        gui.Enabled = true
        trigger.Text = "↗"
    end)
    close.Activated:Connect(function()
        gui.Enabled = false
        panel.Visible = true
        minimized = false
        trigger.Text = "✦"
    end)

    -- Touch/mouse drag for the floating launcher.
    local dragStart, startPos, dragging
    trigger.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragStart = i.Position
            startPos = trigger.Position
            dragging = true
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragging or not dragStart then return end
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = i.Position - dragStart
            if math.abs(delta.X) + math.abs(delta.Y) > 7 then
                trigger.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragStart = nil
        end
    end)

    local lastId = 0
    local seen = {}
    local sending = false
    local function addMessage(message)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 0)
        row.AutomaticSize = Enum.AutomaticSize.Y
        row.BackgroundColor3 = Color3.fromRGB(31, 40, 60)
        row.BorderSizePixel = 0
        row.Parent = feed
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local label = Instance.new("TextLabel")
        label.Position = UDim2.fromOffset(9, 6)
        label.Size = UDim2.new(1, -18, 0, 0)
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.BackgroundTransparency = 1
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(225, 232, 244)
        local author = tostring(message.name or "Guest"):gsub("[%c]", "")
        local body = tostring(message.text or ""):gsub("[%c]", " ")
        label.Text = author .. "  ·  " .. body
        label.Parent = row
        local padding = Instance.new("UIPadding", row)
        padding.PaddingTop = UDim.new(0, 5)
        padding.PaddingBottom = UDim.new(0, 5)
        table.insert(seen, row)
        while #seen > 60 do
            local old = table.remove(seen, 1)
            if old and old.Parent then old:Destroy() end
        end
    end

    local function refresh()
        local ok, result = apiCall("GET", "/api/messages?after=" .. tostring(lastId), nil)
        if not ok then
            status.Text = "Cloud: " .. tostring(result)
            status.TextColor3 = Color3.fromRGB(255, 185, 120)
            return
        end
        status.Text = "● ONLINE  ·  общий чат / сообщения модерируются"
        status.TextColor3 = Color3.fromRGB(100, 230, 180)
        if type(result.messages) == "table" then
            for _, message in ipairs(result.messages) do
                local id = tonumber(message.id) or 0
                if id > lastId then lastId = id end
                addMessage(message)
            end
            if #result.messages > 0 then task.defer(function() feed.CanvasPosition = Vector2.new(0, math.max(0, feed.AbsoluteCanvasSize.Y)) end) end
        end
    end

    local function sendMessage()
        if sending then return end
        local text = trim(input.Text)
        if text == "" then return end
        if #text > MAX_MESSAGE_LENGTH then
            status.Text = "Слишком длинное сообщение (максимум 180 символов)."
            return
        end
        sending = true
        status.Text = "Отправка сообщения..."
        -- Не выполняем сетевой запрос прямо в обработчике кнопки: медленный сервер
        -- не должен блокировать интерфейс Social Lounge.
        task.spawn(function()
            local ok, result = apiCall("POST", "/api/messages", {
                name = LocalPlayer.DisplayName,
                text = text,
                userId = LocalPlayer.UserId,
                kind = "chat"
            })
            sending = false
            if not gui.Parent then return end
            if ok then
                input.Text = ""
                status.Text = "Сообщение отправлено."
                task.spawn(refresh)
            else
                status.Text = "Не отправлено: " .. tostring(result)
            end
        end)
    end
    send.Activated:Connect(sendMessage)
    input.FocusLost:Connect(function(enterPressed) if enterPressed then sendMessage() end end)
    task.spawn(function()
        while gui.Parent and triggerGui.Parent do
            if gui.Enabled then refresh() end
            task.wait(POLL_SECONDS)
        end
    end)
    notify("Social Lounge", "Панель готова. Подключение: maxim-social-lounge.onrender.com")
end

--========================================================
-- MAXIM UTILITY ADDON v9.1 — INTEGRATED INTO RAYFIELD
-- Utilities are added to the existing Hub window; no second ScreenGui panel.
--========================================================
do
    local UtilitiesTab = Window:CreateTab("Utilities", 4483362458)
    local UtilityStats = game:GetService("Stats")
    local UtilityRunService = game:GetService("RunService")

    local function utilityClipboard(value)
        local candidates = {}
        if type(setclipboard) == "function" then table.insert(candidates, setclipboard) end
        if type(toclipboard) == "function" then table.insert(candidates, toclipboard) end
        if type(writeclipboard) == "function" then table.insert(candidates, writeclipboard) end
        for _, fn in ipairs(candidates) do
            local ok = pcall(fn, tostring(value))
            if ok then return true end
        end
        return false
    end

    local function utilityNotify(title, message)
        pcall(function()
            if type(notify) == "function" then
                notify(title, message)
            elseif Rayfield and type(Rayfield.Notify) == "function" then
                Rayfield:Notify({Title = title, Content = message, Duration = 4})
            end
        end)
    end

    local function utilityGetPing()
        local ok, value = pcall(function()
            local network = UtilityStats:FindFirstChild("Network")
            local serverStats = network and network:FindFirstChild("ServerStatsItem")
            local dataPing = serverStats and serverStats:FindFirstChild("Data Ping")
            return dataPing and dataPing:GetValueString() or "Unavailable"
        end)
        return ok and tostring(value) or "Unavailable"
    end

    local fps = 0
    local ping = utilityGetPing()
    local playerCount = #Players:GetPlayers()
    local utilityParagraph
    local function utilityStatusText()
        local jobId = tostring(game.JobId)
        if jobId == "" then jobId = "Unavailable" end
        return string.format(
            "FPS: %s  |  Ping: %s\nPlayers: %d\nPlaceId: %s\nJobId: %s",
            tostring(fps), tostring(ping), #Players:GetPlayers(), tostring(game.PlaceId), jobId
        )
    end

    local paragraphOk, paragraphResult = pcall(function()
        return UtilitiesTab:CreateParagraph({
            Title = "Live Session Information",
            Content = utilityStatusText()
        })
    end)
    if paragraphOk then utilityParagraph = paragraphResult end

    local function refreshUtilityParagraph()
        ping = utilityGetPing()
        playerCount = #Players:GetPlayers()
        if utilityParagraph and type(utilityParagraph.Set) == "function" then
            pcall(function()
                utilityParagraph:Set({Title = "Live Session Information", Content = utilityStatusText()})
            end)
        end
    end

    UtilitiesTab:CreateButton({
        Name = "Refresh server information",
        Callback = function()
            refreshUtilityParagraph()
            utilityNotify("Utilities", "Server information refreshed.")
        end
    })

    UtilitiesTab:CreateButton({
        Name = "Copy current JobId",
        Callback = function()
            local value = tostring(game.JobId)
            if value == "" then
                utilityNotify("Utilities", "This session does not expose a JobId.")
            elseif utilityClipboard(value) then
                utilityNotify("Utilities", "JobId copied.")
            else
                utilityNotify("Utilities", "Clipboard API unavailable. JobId: " .. value)
            end
        end
    })

    UtilitiesTab:CreateButton({
        Name = "Copy PlaceId",
        Callback = function()
            local value = tostring(game.PlaceId)
            if utilityClipboard(value) then
                utilityNotify("Utilities", "PlaceId copied.")
            else
                utilityNotify("Utilities", "Clipboard API unavailable. PlaceId: " .. value)
            end
        end
    })

    UtilitiesTab:CreateButton({
        Name = "Copy my coordinates",
        Callback = function()
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then
                utilityNotify("Utilities", "Character is not loaded yet.")
                return
            end
            local position = root.Position
            local value = string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z)
            if utilityClipboard(value) then
                utilityNotify("Utilities", "Coordinates copied: " .. value)
            else
                utilityNotify("Utilities", "Clipboard API unavailable. Coordinates: " .. value)
            end
        end
    })

    UtilitiesTab:CreateButton({
        Name = "Rejoin this server",
        Callback = function()
            if tostring(game.JobId) == "" then
                utilityNotify("Utilities", "JobId is unavailable in this session.")
                return
            end
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end)
            if not ok then
                utilityNotify("Utilities", "Rejoin failed: " .. tostring(err))
            end
        end
    })

    -- Update FPS once per second. Paragraph updates are guarded for Rayfield versions
    -- that expose the Paragraph:Set method; buttons remain available regardless.
    local utilityFrameCount = 0
    local utilityLastUpdate = os.clock()
    UtilityRunService.RenderStepped:Connect(function()
        utilityFrameCount += 1
        local now = os.clock()
        if now - utilityLastUpdate >= 1 then
            fps = utilityFrameCount
            utilityFrameCount = 0
            utilityLastUpdate = now
            refreshUtilityParagraph()
        end
    end)
end

