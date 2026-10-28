--[[
    MAXIM COMPANION HUB v12.2 — UI Studio + Settings Enhanced
    Rayfield UI + splash + local history + manual JobId queue + public server browser
    UI Studio: eight theme presets, custom accent, UI scale, panel hierarchy, compact mode,
    mobile toggle placement, local persistence, background image and optional panel animation.
    Server history is local to this device/executor filesystem where supported.

    IMPORTANT:
    * This only records players visible to your client in the current server.
    * Public server browser lists instances/metrics; it does not reveal every server's roster or globally locate a user.
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

local Palette = {
    BG_DEEP       = Color3.fromRGB(14, 8, 12),
    BG_MAIN       = Color3.fromRGB(22, 12, 18),
    BG_PANEL      = Color3.fromRGB(32, 18, 26),
    BG_ROW        = Color3.fromRGB(48, 26, 36),
    BG_INPUT      = Color3.fromRGB(38, 22, 30),
    BG_SCROLL     = Color3.fromRGB(26, 15, 22),
    RED_PRIMARY   = Color3.fromRGB(230, 40, 60),
    RED_BRIGHT    = Color3.fromRGB(255, 70, 90),
    RED_NEON      = Color3.fromRGB(255, 130, 150),
    RED_DARK      = Color3.fromRGB(140, 20, 40),
    RED_DEEP      = Color3.fromRGB(90, 15, 30),
    WHITE         = Color3.fromRGB(255, 250, 252),
    WHITE_SOFT    = Color3.fromRGB(240, 230, 235),
    TEXT_MUTED    = Color3.fromRGB(180, 160, 170),
    TEXT_DIM      = Color3.fromRGB(140, 120, 130),
}
local BRAND_ICON = "✺"

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
    bg.BackgroundColor3 = Palette.BG_DEEP
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
        UDim2.fromScale(.9, .12), Palette.WHITE, Enum.Font.GothamBold)
    local credit = label("Credit", "Сделано Максимом", UDim2.fromScale(.5, .53),
        UDim2.fromScale(.9, .06), Palette.WHITE_SOFT, Enum.Font.Gotham)
    local status = label("Status", "ЗАГРУЗКА...", UDim2.fromScale(.5, .64),
        UDim2.fromScale(.9, .05), Palette.TEXT_MUTED, Enum.Font.Code)

    local brand = label("BrandIcon", BRAND_ICON, UDim2.fromScale(.5, .30),
        UDim2.fromScale(.18, .10), Palette.WHITE, Enum.Font.GothamBold)
    brand.TextTransparency = 0
    local brandPulse = TweenService:Create(brand,
        TweenInfo.new(.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {TextColor3 = Palette.RED_NEON})
    brandPulse:Play()

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
    UISettings = {SelectedTheme = "RedWhiteNeon", Hierarchy = {Scale = 1, Transparency = 0.78, Corner = 10, Padding = 8}, NeonGlow = true, AMOLED = false, CompactMode = false, Animations = true, FontScale = 1, MobileButtonSide = "Right", MobileButtonY = 84},
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
        Version = 12,
        FriendNotes = State.FriendNotes,
        Bookmarks = State.Bookmarks,
        Events = State.Events,
        ServerHistory = State.ServerHistory,
        UISettings = State.UISettings,
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
    if type(data.UISettings) == "table" then
        State.UISettings = data.UISettings
        State.UISettings.Hierarchy = type(data.UISettings.Hierarchy) == "table" and data.UISettings.Hierarchy or {Scale = 1, Transparency = 0.78, Corner = 10, Padding = 8}
    end
end
loadData()

-- UI Studio helper: only touches our own custom ScreenGuis, never Rayfield descendants.
local function applyCustomGuiSettings(gui, panel)
    if not gui or not gui:IsA("ScreenGui") then return end
    local cfg = State.UISettings or {}
    local hierarchy = cfg.Hierarchy or {}
    local scale = tonumber(hierarchy.Scale) or 1
    local uiScale = gui:FindFirstChild("MaximUserUIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Name = "MaximUserUIScale"
        uiScale.Parent = gui
    end
    uiScale.Scale = math.clamp(scale * (tonumber(cfg.FontScale) or 1), 0.55, 1.6)
    if panel and panel:IsA("GuiObject") then
        panel.BackgroundTransparency = math.clamp(tonumber(hierarchy.Transparency) or 0, 0, 1)
        local corner = panel:FindFirstChildOfClass("UICorner")
        if corner then corner.CornerRadius = UDim.new(0, math.clamp(tonumber(hierarchy.Corner) or 10, 0, 32)) end
        local padding = panel:FindFirstChild("MaximUserPadding")
        if not padding then padding = Instance.new("UIPadding"); padding.Name = "MaximUserPadding"; padding.Parent = panel end
        local px = math.clamp(tonumber(hierarchy.Padding) or 8, 0, 28)
        padding.PaddingTop = UDim.new(0, px); padding.PaddingBottom = UDim.new(0, px)
        padding.PaddingLeft = UDim.new(0, px); padding.PaddingRight = UDim.new(0, px)
    end
end

local function refreshCustomGuiSettings()
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and (gui.Name == "MaximServerHistoryViewer"
            or gui.Name == "MaximGlobalPlayerSearch" or gui.Name == "MaximPlaceSearch"
            or gui.Name == "MaximServerPanel" or gui.Name == "MaximSocialLounge") then
            local panel = gui:FindFirstChild("MainPanel") or gui:FindFirstChild("Panel")
            if not panel then
                for _, child in ipairs(gui:GetChildren()) do
                    if child:IsA("Frame") then panel = child; break end
                end
            end
            applyCustomGuiSettings(gui, panel)
        end
    end
end

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
        Name = "MAXIM | COMPANION HUB v12",
        LoadingTitle = "Companion Hub v12",
        LoadingSubtitle = "Сделано Максимом  •  Red/White Neon",
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
-- RAYFIELD SETTINGS PATCH v12.1 — THEME PRESETS + LOCAL UI PREFS
-- Appearance-only patch. Existing gameplay, server/history and resolver code untouched.
--========================================================
do
    local SettingsTab = Window:CreateTab("Rayfield Settings", 4483362458)
    local backgroundImage = nil
    local uiSettings = State.UISettings or {}
    uiSettings.SelectedTheme = tostring(uiSettings.SelectedTheme or "RedWhiteNeon")
    uiSettings.Hierarchy = type(uiSettings.Hierarchy) == "table" and uiSettings.Hierarchy or {}
    uiSettings.Hierarchy.Scale = tonumber(uiSettings.Hierarchy.Scale) or 1
    uiSettings.Hierarchy.Transparency = tonumber(uiSettings.Hierarchy.Transparency) or 0.78
    uiSettings.Hierarchy.Corner = tonumber(uiSettings.Hierarchy.Corner) or 10
    uiSettings.Hierarchy.Padding = tonumber(uiSettings.Hierarchy.Padding) or 8
    uiSettings.NeonGlow = uiSettings.NeonGlow ~= false
    uiSettings.AMOLED = uiSettings.AMOLED == true
    uiSettings.CompactMode = uiSettings.CompactMode == true
    uiSettings.Animations = uiSettings.Animations ~= false
    uiSettings.FontScale = math.clamp(tonumber(uiSettings.FontScale) or 1, 0.75, 1.35)
    uiSettings.MobileButtonSide = uiSettings.MobileButtonSide == "Left" and "Left" or "Right"
    uiSettings.MobileButtonY = math.clamp(tonumber(uiSettings.MobileButtonY) or 84, 40, 260)
    State.UISettings = uiSettings
    if type(uiSettings.CustomAccent) == "table" then
        local r, g, b = tonumber(uiSettings.CustomAccent.R), tonumber(uiSettings.CustomAccent.G), tonumber(uiSettings.CustomAccent.B)
        if r and g and b then
            Palette.RED_PRIMARY = Color3.fromRGB(math.clamp(r,0,255), math.clamp(g,0,255), math.clamp(b,0,255))
            Palette.RED_BRIGHT = Palette.RED_PRIMARY:Lerp(Color3.new(1,1,1), 0.28)
        end
    end

    local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
    local ThemePresets = {
        RedWhiteNeon = {TextColor=rgb(255,245,248), Background=rgb(18,10,14), Topbar=rgb(28,12,18), Shadow=rgb(5,3,5), NotificationBackground=rgb(28,12,18), NotificationActionsBackground=rgb(45,18,26), TabBackground=rgb(38,16,24), TabStroke=rgb(85,24,38), TabBackgroundSelected=rgb(210,35,58), TabTextColor=rgb(225,205,212), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(38,18,26), ElementBackgroundHover=rgb(55,22,32), SecondaryElementBackground=rgb(28,14,20), ElementStroke=rgb(100,28,45), SecondaryElementStroke=rgb(70,24,35), SliderBackground=rgb(55,22,32), SliderProgress=rgb(255,55,78), SliderStroke=rgb(150,35,55), ToggleBackground=rgb(45,20,28), ToggleEnabled=rgb(255,50,75), ToggleDisabled=rgb(75,40,48), ToggleEnabledStroke=rgb(255,115,130), ToggleDisabledStroke=rgb(100,55,65), ToggleEnabledOuterStroke=rgb(255,65,90), ToggleDisabledOuterStroke=rgb(60,35,42), DropdownSelected=rgb(55,22,32), DropdownUnselected=rgb(32,15,21), InputBackground=rgb(30,15,21), InputStroke=rgb(95,30,45), PlaceholderColor=rgb(160,130,140)},
        Dark = {TextColor=rgb(235,235,235), Background=rgb(20,20,20), Topbar=rgb(26,26,26), Shadow=rgb(0,0,0), NotificationBackground=rgb(28,28,28), NotificationActionsBackground=rgb(45,45,45), TabBackground=rgb(35,35,35), TabStroke=rgb(60,60,60), TabBackgroundSelected=rgb(70,70,70), TabTextColor=rgb(190,190,190), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(35,35,35), ElementBackgroundHover=rgb(48,48,48), SecondaryElementBackground=rgb(28,28,28), ElementStroke=rgb(65,65,65), SecondaryElementStroke=rgb(50,50,50), SliderBackground=rgb(50,50,50), SliderProgress=rgb(130,130,130), SliderStroke=rgb(90,90,90), ToggleBackground=rgb(50,50,50), ToggleEnabled=rgb(130,130,130), ToggleDisabled=rgb(70,70,70), ToggleEnabledStroke=rgb(180,180,180), ToggleDisabledStroke=rgb(90,90,90), ToggleEnabledOuterStroke=rgb(150,150,150), ToggleDisabledOuterStroke=rgb(65,65,65), DropdownSelected=rgb(50,50,50), DropdownUnselected=rgb(30,30,30), InputBackground=rgb(30,30,30), InputStroke=rgb(65,65,65), PlaceholderColor=rgb(145,145,145)},
        Light = {TextColor=rgb(35,35,40), Background=rgb(245,245,248), Topbar=rgb(235,235,240), Shadow=rgb(160,160,170), NotificationBackground=rgb(245,245,248), NotificationActionsBackground=rgb(225,225,232), TabBackground=rgb(225,225,232), TabStroke=rgb(195,195,205), TabBackgroundSelected=rgb(190,205,235), TabTextColor=rgb(90,90,100), SelectedTabTextColor=rgb(25,35,55), ElementBackground=rgb(235,235,240), ElementBackgroundHover=rgb(220,220,230), SecondaryElementBackground=rgb(225,225,232), ElementStroke=rgb(190,190,200), SecondaryElementStroke=rgb(205,205,215), SliderBackground=rgb(205,205,215), SliderProgress=rgb(90,130,210), SliderStroke=rgb(160,175,205), ToggleBackground=rgb(205,205,215), ToggleEnabled=rgb(90,130,210), ToggleDisabled=rgb(175,175,185), ToggleEnabledStroke=rgb(120,155,225), ToggleDisabledStroke=rgb(190,190,200), ToggleEnabledOuterStroke=rgb(100,140,220), ToggleDisabledOuterStroke=rgb(180,180,190), DropdownSelected=rgb(220,220,230), DropdownUnselected=rgb(235,235,240), InputBackground=rgb(235,235,240), InputStroke=rgb(190,190,200), PlaceholderColor=rgb(125,125,135)},
        Cyberpunk = {TextColor=rgb(245,255,255), Background=rgb(12,10,24), Topbar=rgb(22,12,38), Shadow=rgb(0,0,0), NotificationBackground=rgb(22,12,38), NotificationActionsBackground=rgb(40,18,60), TabBackground=rgb(28,16,48), TabStroke=rgb(0,220,255), TabBackgroundSelected=rgb(220,0,255), TabTextColor=rgb(160,210,225), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(28,16,48), ElementBackgroundHover=rgb(42,20,65), SecondaryElementBackground=rgb(18,12,32), ElementStroke=rgb(0,220,255), SecondaryElementStroke=rgb(100,0,150), SliderBackground=rgb(42,20,65), SliderProgress=rgb(0,230,255), SliderStroke=rgb(220,0,255), ToggleBackground=rgb(40,20,60), ToggleEnabled=rgb(0,230,255), ToggleDisabled=rgb(70,40,90), ToggleEnabledStroke=rgb(255,0,220), ToggleDisabledStroke=rgb(100,60,120), ToggleEnabledOuterStroke=rgb(0,230,255), ToggleDisabledOuterStroke=rgb(60,40,80), DropdownSelected=rgb(42,20,65), DropdownUnselected=rgb(20,12,35), InputBackground=rgb(20,12,35), InputStroke=rgb(0,200,230), PlaceholderColor=rgb(140,120,170)},
        Purple = {TextColor=rgb(245,240,255), Background=rgb(20,12,30), Topbar=rgb(32,18,48), Shadow=rgb(5,0,10), NotificationBackground=rgb(32,18,48), NotificationActionsBackground=rgb(50,28,72), TabBackground=rgb(40,22,58), TabStroke=rgb(100,55,150), TabBackgroundSelected=rgb(125,65,190), TabTextColor=rgb(205,185,225), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(40,22,58), ElementBackgroundHover=rgb(55,30,78), SecondaryElementBackground=rgb(30,18,45), ElementStroke=rgb(110,65,160), SecondaryElementStroke=rgb(80,45,120), SliderBackground=rgb(55,30,78), SliderProgress=rgb(160,90,230), SliderStroke=rgb(125,70,185), ToggleBackground=rgb(55,30,78), ToggleEnabled=rgb(160,90,230), ToggleDisabled=rgb(75,50,90), ToggleEnabledStroke=rgb(190,130,255), ToggleDisabledStroke=rgb(110,80,125), ToggleEnabledOuterStroke=rgb(150,90,220), ToggleDisabledOuterStroke=rgb(65,45,75), DropdownSelected=rgb(55,30,78), DropdownUnselected=rgb(30,18,45), InputBackground=rgb(30,18,45), InputStroke=rgb(100,60,145), PlaceholderColor=rgb(155,130,175)},
        Ocean = {TextColor=rgb(235,250,255), Background=rgb(8,18,28), Topbar=rgb(12,28,42), Shadow=rgb(0,5,10), NotificationBackground=rgb(12,28,42), NotificationActionsBackground=rgb(18,42,58), TabBackground=rgb(15,35,50), TabStroke=rgb(30,100,130), TabBackgroundSelected=rgb(20,115,155), TabTextColor=rgb(165,210,225), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(15,35,50), ElementBackgroundHover=rgb(20,50,68), SecondaryElementBackground=rgb(10,25,38), ElementStroke=rgb(35,110,145), SecondaryElementStroke=rgb(25,75,100), SliderBackground=rgb(20,50,68), SliderProgress=rgb(30,170,220), SliderStroke=rgb(35,125,165), ToggleBackground=rgb(20,50,68), ToggleEnabled=rgb(30,170,220), ToggleDisabled=rgb(45,65,75), ToggleEnabledStroke=rgb(80,205,240), ToggleDisabledStroke=rgb(75,100,110), ToggleEnabledOuterStroke=rgb(40,150,200), ToggleDisabledOuterStroke=rgb(35,55,65), DropdownSelected=rgb(20,50,68), DropdownUnselected=rgb(10,25,38), InputBackground=rgb(10,25,38), InputStroke=rgb(30,100,130), PlaceholderColor=rgb(120,160,175)},
        AMOLED = {TextColor=rgb(245,245,245), Background=rgb(0,0,0), Topbar=rgb(0,0,0), Shadow=rgb(0,0,0), NotificationBackground=rgb(5,5,5), NotificationActionsBackground=rgb(15,15,15), TabBackground=rgb(8,8,8), TabStroke=rgb(35,35,35), TabBackgroundSelected=rgb(45,45,45), TabTextColor=rgb(165,165,165), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(8,8,8), ElementBackgroundHover=rgb(20,20,20), SecondaryElementBackground=rgb(4,4,4), ElementStroke=rgb(40,40,40), SecondaryElementStroke=rgb(25,25,25), SliderBackground=rgb(25,25,25), SliderProgress=rgb(230,230,230), SliderStroke=rgb(55,55,55), ToggleBackground=rgb(25,25,25), ToggleEnabled=rgb(230,230,230), ToggleDisabled=rgb(55,55,55), ToggleEnabledStroke=rgb(255,255,255), ToggleDisabledStroke=rgb(75,75,75), ToggleEnabledOuterStroke=rgb(200,200,200), ToggleDisabledOuterStroke=rgb(30,30,30), DropdownSelected=rgb(25,25,25), DropdownUnselected=rgb(5,5,5), InputBackground=rgb(5,5,5), InputStroke=rgb(35,35,35), PlaceholderColor=rgb(115,115,115)},
        Glass = {TextColor=rgb(245,250,255), Background=rgb(30,35,45), Topbar=rgb(45,50,62), Shadow=rgb(10,15,25), NotificationBackground=rgb(45,50,62), NotificationActionsBackground=rgb(65,72,85), TabBackground=rgb(55,62,75), TabStroke=rgb(110,125,145), TabBackgroundSelected=rgb(100,125,155), TabTextColor=rgb(200,210,225), SelectedTabTextColor=rgb(255,255,255), ElementBackground=rgb(55,62,75), ElementBackgroundHover=rgb(70,78,92), SecondaryElementBackground=rgb(45,52,65), ElementStroke=rgb(125,140,160), SecondaryElementStroke=rgb(95,110,130), SliderBackground=rgb(70,78,92), SliderProgress=rgb(130,175,220), SliderStroke=rgb(125,150,180), ToggleBackground=rgb(70,78,92), ToggleEnabled=rgb(130,175,220), ToggleDisabled=rgb(90,95,105), ToggleEnabledStroke=rgb(170,205,240), ToggleDisabledStroke=rgb(125,130,140), ToggleEnabledOuterStroke=rgb(150,190,230), ToggleDisabledOuterStroke=rgb(70,75,85), DropdownSelected=rgb(70,78,92), DropdownUnselected=rgb(45,52,65), InputBackground=rgb(45,52,65), InputStroke=rgb(110,125,145), PlaceholderColor=rgb(155,165,180)},
    }

    SettingsTab:CreateParagraph({Title="Rayfield Appearance", Content="8 пресетов оформления. Настройки интерфейса сохраняются в локальный CompanionHub.json, если доступно файловое сохранение. Применение темы зависит от API установленной версии Rayfield."})

    local function saveUISettings()
        State.UISettings = uiSettings
        local ok = saveData()
        refreshCustomGuiSettings()
        notify("UI Settings", ok and "Настройки сохранены." or "Файловое сохранение недоступно; настройки действуют до перезапуска.")
    end

    local function applyTheme(themeName)
        local theme = ThemePresets[themeName]
        if not theme then notify("Rayfield Theme", "Неизвестная тема: " .. tostring(themeName)); return end
        local ok, err = pcall(function()
            if Rayfield and type(Rayfield.ModifyTheme) == "function" then
                Rayfield:ModifyTheme(theme)
            else
                error("В загруженной версии Rayfield нет ModifyTheme; тема не применена")
            end
        end)
        if ok then
            uiSettings.SelectedTheme = themeName
            State.UISettings = uiSettings
            saveData()
            notify("Rayfield Theme", "Применена тема: " .. themeName)
        else
            notify("Rayfield Theme", "Не удалось применить: " .. tostring(err))
        end
    end

    local themeOptions = {"RedWhiteNeon", "Dark", "Light", "Cyberpunk", "Purple", "Ocean", "AMOLED", "Glass"}
    for _, name in ipairs(themeOptions) do
        SettingsTab:CreateButton({Name="Тема: " .. name, Callback=function() applyTheme(name) end})
    end

    SettingsTab:CreateToggle({Name="AMOLED Mode", CurrentValue=uiSettings.AMOLED, Callback=function(value)
        uiSettings.AMOLED = value == true
        if uiSettings.AMOLED then applyTheme("AMOLED") elseif uiSettings.SelectedTheme == "AMOLED" then applyTheme("RedWhiteNeon") end
        saveUISettings()
    end})
    SettingsTab:CreateToggle({Name="Neon Glow (custom panels)", CurrentValue=uiSettings.NeonGlow, Callback=function(value)
        uiSettings.NeonGlow = value == true
        saveUISettings()
        notify("UI Settings", "Neon Glow сохранён для собственных панелей. Rayfield элементы не изменялись.")
    end})
    SettingsTab:CreateColorPicker({Name="Custom panel accent", Color=Palette.RED_PRIMARY, Flag="MaximCustomAccent", Callback=function(color)
        if typeof(color) == "Color3" then
            Palette.RED_PRIMARY = color
            Palette.RED_BRIGHT = color:Lerp(Color3.new(1,1,1), 0.28)
            for _, gui in ipairs(PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and (gui.Name == "MaximServerHistoryViewer" or gui.Name == "MaximGlobalPlayerSearch" or gui.Name == "MaximPlaceSearch" or gui.Name == "MaximServerPanel" or gui.Name == "MaximSocialLounge") then
                    for _, obj in ipairs(gui:GetDescendants()) do
                        if obj:IsA("UIStroke") and obj.Name ~= "MaximUserAccentStroke" then obj.Color = Palette.RED_BRIGHT end
                        if obj:IsA("TextButton") and (obj.Name == "ToggleButton" or obj.Text == "×" or obj.Text == "Refresh") then obj.BackgroundColor3 = Palette.RED_PRIMARY end
                    end
                end
            end
            uiSettings.CustomAccent = {R=math.floor(color.R*255+0.5), G=math.floor(color.G*255+0.5), B=math.floor(color.B*255+0.5)}
            saveUISettings()
        end
    end})

    SettingsTab:CreateSlider({Name="UI Scale", Range={0.75,1.25}, Increment=0.05, CurrentValue=uiSettings.Hierarchy.Scale, Callback=function(value)
        uiSettings.Hierarchy.Scale = tonumber(value) or 1
        saveUISettings()
    end})
    SettingsTab:CreateSlider({Name="Panel Transparency", Range={0,1}, Increment=0.05, CurrentValue=uiSettings.Hierarchy.Transparency, Callback=function(value)
        uiSettings.Hierarchy.Transparency = tonumber(value) or 0.78
        saveUISettings()
    end})
    SettingsTab:CreateSlider({Name="Panel Corner", Range={0,24}, Increment=1, CurrentValue=uiSettings.Hierarchy.Corner, Callback=function(value)
        uiSettings.Hierarchy.Corner = tonumber(value) or 10
        saveUISettings()
    end})
    SettingsTab:CreateSlider({Name="Panel Padding", Range={0,20}, Increment=1, CurrentValue=uiSettings.Hierarchy.Padding, Callback=function(value)
        uiSettings.Hierarchy.Padding = tonumber(value) or 8
        saveUISettings()
    end})
    SettingsTab:CreateSlider({Name="Font / UI Scale", Range={0.75,1.35}, Increment=0.05, CurrentValue=uiSettings.FontScale, Callback=function(value)
        uiSettings.FontScale = math.clamp(tonumber(value) or 1, 0.75, 1.35)
        saveUISettings()
    end})
    SettingsTab:CreateToggle({Name="Compact custom panels", CurrentValue=uiSettings.CompactMode, Callback=function(value)
        uiSettings.CompactMode = value == true
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name == "MaximServerHistoryViewer" or gui.Name == "MaximGlobalPlayerSearch" or gui.Name == "MaximPlaceSearch" or gui.Name == "MaximServerPanel" or gui.Name == "MaximSocialLounge") then
                local panel = gui:FindFirstChild("MainPanel") or gui:FindFirstChild("Panel")
                if panel and panel:IsA("Frame") then
                    panel.Size = uiSettings.CompactMode and UDim2.new(0.86,0,0.68,0) or UDim2.new(0.92,0,0.78,0)
                end
            end
        end
        saveUISettings()
    end})
    SettingsTab:CreateToggle({Name="Custom panel animations", CurrentValue=uiSettings.Animations, Callback=function(value)
        uiSettings.Animations = value == true
        saveUISettings()
        notify("UI Studio", uiSettings.Animations and "Анимации включены для новых собственных окон." or "Анимации отключены для новых собственных окон.")
    end})
    SettingsTab:CreateDropdown({Name="Mobile toggle side", Options={"Right","Left"}, CurrentOption={uiSettings.MobileButtonSide}, Callback=function(value)
        local selected = type(value)=="table" and value[1] or value
        uiSettings.MobileButtonSide = selected == "Left" and "Left" or "Right"
        local mobile = PlayerGui:FindFirstChild("MaximHubMobileToggle")
        local button = mobile and mobile:FindFirstChild("ToggleButton")
        if button then
            local left = uiSettings.MobileButtonSide == "Left"
            button.AnchorPoint = Vector2.new(left and 0 or 1, 0)
            button.Position = UDim2.new(left and 0 or 1, left and 14 or -14, 0, uiSettings.MobileButtonY)
        end
        saveUISettings()
    end})
    SettingsTab:CreateSlider({Name="Mobile toggle vertical position", Range={40,260}, Increment=5, CurrentValue=uiSettings.MobileButtonY, Callback=function(value)
        uiSettings.MobileButtonY = math.clamp(tonumber(value) or 84,40,260)
        local mobile = PlayerGui:FindFirstChild("MaximHubMobileToggle")
        local button = mobile and mobile:FindFirstChild("ToggleButton")
        if button then button.AnchorPoint = Vector2.new(uiSettings.MobileButtonSide == "Left" and 0 or 1,0); button.Position = UDim2.new(uiSettings.MobileButtonSide == "Left" and 0 or 1, uiSettings.MobileButtonSide == "Left" and 14 or -14,0,uiSettings.MobileButtonY) end
        saveUISettings()
    end})
    SettingsTab:CreateButton({Name="Refresh custom GUI styling", Callback=function()
        refreshCustomGuiSettings(); notify("UI Studio", "Настройки применены к собственным окнам.")
    end})
    SettingsTab:CreateButton({Name="Save UI Settings", Callback=saveUISettings})
    SettingsTab:CreateButton({Name="Reset UI Settings", Callback=function()
        uiSettings.Hierarchy = {Scale=1, Transparency=0.78, Corner=10, Padding=8}
        uiSettings.NeonGlow = true
        uiSettings.AMOLED = false
        uiSettings.CompactMode = false
        uiSettings.Animations = true
        uiSettings.FontScale = 1
        uiSettings.MobileButtonSide = "Right"
        uiSettings.MobileButtonY = 84
        uiSettings.SelectedTheme = "RedWhiteNeon"
        State.UISettings = uiSettings
        applyTheme("RedWhiteNeon")
        saveUISettings()
        notify("UI Settings", "Параметры сброшены.")
    end})

    local function findRayfieldGui()
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name == "Rayfield" or gui.Name == "RayfieldMain" or gui.Name == "RayfieldGui") then return gui end
        end
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui:FindFirstChild("Main") then return gui end
        end
        return nil
    end
    local function removeBackgroundImage()
        local gui = findRayfieldGui()
        if gui then local old = gui:FindFirstChild("MaximRayfieldBackground"); if old then old:Destroy() end end
        backgroundImage = nil
    end
    SettingsTab:CreateInput({Name="Background image URL / executor path", PlaceholderText="https://... или путь к файлу", RemoveTextAfterFocusLost=false, Callback=function(value)
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if value == "" then removeBackgroundImage(); notify("Rayfield Background", "Фон очищен."); return end
        local imageAsset
        if value:match("^https?://") then imageAsset = value else
            local assetFn = optionalFunction("getcustomasset") or optionalFunction("getsynasset")
            if assetFn then local ok, result = pcall(assetFn, value); if ok and type(result)=="string" then imageAsset=result end end
        end
        if not imageAsset then notify("Rayfield Background", "Локальный файл требует getcustomasset/getsynasset."); return end
        local gui = findRayfieldGui()
        if not gui then notify("Rayfield Background", "GUI Rayfield не найден. Открой панель и повтори."); return end
        removeBackgroundImage()
        local image = Instance.new("ImageLabel")
        image.Name="MaximRayfieldBackground"; image.BackgroundTransparency=1; image.BorderSizePixel=0
        image.Size=UDim2.fromScale(1,1); image.Position=UDim2.fromScale(0,0); image.Image=imageAsset
        image.ScaleType=Enum.ScaleType.Crop; image.ImageTransparency=uiSettings.Hierarchy.Transparency; image.ZIndex=0; image.Parent=gui
        backgroundImage=image
        notify("Rayfield Background", "Изображение добавлено.")
    end})
    SettingsTab:CreateButton({Name="Remove Rayfield background image", Callback=removeBackgroundImage})
    SettingsTab:CreateParagraph({Title="Custom panels", Content="Scale, transparency, corner и padding записываются в UIHierarchyConfig. Они не применяются автоматически к Rayfield: это настройки для собственных панелей, их подключение нужно делать отдельно в соответствующих UI-модулях. Сетевые функции, Instance Resolver и существующие вкладки не менялись."})
end

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
toggleButton.AnchorPoint = Vector2.new((State.UISettings and State.UISettings.MobileButtonSide == "Left") and 0 or 1, 0)
toggleButton.Position = UDim2.new((State.UISettings and State.UISettings.MobileButtonSide == "Left") and 0 or 1, (State.UISettings and State.UISettings.MobileButtonSide == "Left") and 14 or -14, 0, (State.UISettings and tonumber(State.UISettings.MobileButtonY)) or 84)
toggleButton.Size = UDim2.fromOffset(54, 50)
toggleButton.BackgroundColor3 = Palette.RED_PRIMARY
toggleButton.Text = "×"
toggleButton.TextColor3 = Palette.WHITE
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
toggleStroke.Color = Palette.WHITE
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
        toggleButton.Text = BRAND_ICON
        toggleButton.Size = UDim2.fromOffset(58, 50)
        toggleButton.BackgroundColor3 = Palette.RED_PRIMARY
        toggleStroke.Color = Palette.WHITE
    else
        toggleButton.Text = "×"
        toggleButton.Size = UDim2.fromOffset(54, 50)
        toggleButton.BackgroundColor3 = Palette.RED_PRIMARY
        toggleStroke.Color = Palette.WHITE
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
    panel.Size = (State.UISettings and State.UISettings.CompactMode) and UDim2.new(0.86, 0, 0.68, 0) or UDim2.new(0.92, 0, 0.78, 0)
    panel.BackgroundColor3 = Palette.BG_PANEL
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
    applyCustomGuiSettings(gui, panel)
    if State.UISettings and State.UISettings.Animations then
        local finalSize = panel.Size
        panel.Size = UDim2.new(finalSize.X.Scale * 0.96, finalSize.X.Offset, finalSize.Y.Scale * 0.96, finalSize.Y.Offset)
        TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size=finalSize}):Play()
    end

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(280, 300)
    sizeConstraint.MaxSize = Vector2.new(650, 720)
    sizeConstraint.Parent = panel

    local header = Instance.new("TextLabel")
    header.Position = UDim2.fromOffset(14, 8)
    header.Size = UDim2.new(1, -68, 0, 38)
    header.BackgroundTransparency = 1
    header.Text = titleText
    header.TextColor3 = Palette.RED_BRIGHT
    header.Font = Enum.Font.GothamBold
    header.TextSize = 19
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = panel

    local close = Instance.new("TextButton")
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -8, 0, 8)
    close.Size = UDim2.fromOffset(42, 38)
    close.BackgroundColor3 = Palette.RED_PRIMARY
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
    search.BackgroundColor3 = Palette.BG_INPUT
    search.TextColor3 = Color3.new(1, 1, 1)
    search.PlaceholderColor3 = Palette.TEXT_MUTED
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
    scroll.BackgroundColor3 = Palette.BG_SCROLL
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Palette.RED_PRIMARY
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
    label.TextColor3 = Palette.WHITE_SOFT
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
    info.TextColor3 = Palette.TEXT_MUTED
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
                row.BackgroundColor3 = Palette.BG_ROW
                row.BorderSizePixel = 0
                row.LayoutOrder = shown
                row.Parent = scroll
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                local avatar = Instance.new("ImageLabel")
                avatar.Size = UDim2.fromOffset(52, 52)
                avatar.Position = UDim2.fromOffset(7, 8)
                avatar.BackgroundColor3 = Palette.BG_INPUT
                avatar.BorderSizePixel = 0
                avatar.Parent = row
                local avatarStroke = Instance.new("UIStroke", avatar)
                avatarStroke.Color = Palette.RED_BRIGHT
                avatarStroke.Thickness = 1
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
                sub.TextColor3 = Palette.TEXT_MUTED
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
                        row.BackgroundColor3 = Palette.BG_ROW
                        row.BorderSizePixel = 0
                        row.LayoutOrder = shown
                        row.Parent = scroll
                        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                        local avatar = Instance.new("ImageLabel")
                        avatar.Size = UDim2.fromOffset(52, 52)
                        avatar.Position = UDim2.fromOffset(7, 9)
                        avatar.BackgroundColor3 = Palette.BG_INPUT
                        avatar.BorderSizePixel = 0
                        avatar.Parent = row
                        local avatarStroke = Instance.new("UIStroke", avatar)
                        avatarStroke.Color = Palette.RED_BRIGHT
                        avatarStroke.Thickness = 1
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
                        sub.TextColor3 = Palette.TEXT_MUTED
                        sub.Font = Enum.Font.Code
                        sub.TextSize = 11
                        sub.TextXAlignment = Enum.TextXAlignment.Left
                        sub.Text = "UserId: " .. tostring(id or "?")
                        sub.Parent = row

                        local profile = Instance.new("TextButton")
                        profile.AnchorPoint = Vector2.new(1, 1)
                        profile.Position = UDim2.new(1, -6, 1, -5)
                        profile.Size = UDim2.fromOffset(74, 22)
                        profile.BackgroundColor3 = Palette.RED_PRIMARY
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

GlobalPlayersTab:CreateParagraph({
    Title = "Поиск в текущем сервере",
    Content = "Проверяет только игроков, видимых этому клиенту в текущем сервере. Для ранее встреченных игроков используй локальную историю серверов; глобального сканирования чужих серверов здесь нет."
})
GlobalPlayersTab:CreateButton({
    Name = "Проверить текущий сервер и скопировать JobId",
    Callback = function()
        local query = string.lower(trim(globalUserQuery))
        if query == "" then
            notify("Поиск в сервере", "Сначала введи точный username в поле выше.")
            return
        end
        for _, candidate in ipairs(Players:GetPlayers()) do
            local username = string.lower(tostring(candidate.Name or ""))
            local displayName = string.lower(tostring(candidate.DisplayName or ""))
            if username == query or displayName == query then
                local jobId = tostring(game.JobId or "")
                if jobId == "" then
                    notify("Поиск в сервере", "Игрок найден: @" .. tostring(candidate.Name) .. ", но JobId недоступен в этой сессии.")
                else
                    local copied = copyText(jobId)
                    notify("Поиск в сервере", "Найден @" .. tostring(candidate.Name) .. " в текущем сервере. JobId " .. (copied and "скопирован." or ("(" .. jobId .. ")")))
                end
                return
            end
        end
        notify("Поиск в сервере", "Игрок не найден в текущем сервере. Это не проверяет другие серверы; можно проверить сохранённую историю, если ты уже встречал этого игрока.")
    end
})

--========================================================
-- MANUAL SERVER-ID QUEUE (NO AUTOMATED PLAYER SCANNING)
--========================================================
local JobQueueTab = Window:CreateTab("JobId Queue", 4483362458)
local jobQueueRaw = ""
local jobQueue = {}
local jobQueueIndex = 1

JobQueueTab:CreateParagraph({
    Title = "Очередь известных серверов",
    Content = "Вставь JobId, которые ты уже собрал сам или нашёл в своей истории. Очередь убирает повторы и позволяет копировать следующий ID. Она не сканирует состав чужих серверов и не подключается автоматически."
})

JobQueueTab:CreateInput({
    Name = "JobId (можно несколько через запятую или пробел)",
    PlaceholderText = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx, ...",
    RemoveTextAfterFocusLost = false,
    Callback = function(value)
        jobQueueRaw = tostring(value or "")
    end
})

local function parseJobIdQueue(raw)
    local result, seen = {}, {}
    -- UUID-like JobIds; accepts hyphenated or compact hexadecimal IDs.
    for token in string.gmatch(tostring(raw or ""), "[%w%-]+") do
        local candidate = string.lower(token)
        local compact = string.gsub(candidate, "%-", "")
        local isHex = #compact >= 24 and #compact <= 40
            and string.match(compact, "^[0-9a-f]+$") ~= nil
        if isHex and not seen[candidate] then
            seen[candidate] = true
            table.insert(result, candidate)
        end
    end
    return result
end

JobQueueTab:CreateButton({
    Name = "Загрузить и очистить список JobId",
    Callback = function()
        jobQueue = parseJobIdQueue(jobQueueRaw)
        jobQueueIndex = 1
        if #jobQueue == 0 then
            notify("JobId Queue", "Не нашёл подходящих ID. Вставь ID, разделённые запятыми или пробелами.")
            return
        end
        notify("JobId Queue", string.format("Загружено %d уникальных ID. Повторы удалены.", #jobQueue))
    end
})

JobQueueTab:CreateButton({
    Name = "Скопировать следующий JobId",
    Callback = function()
        if #jobQueue == 0 then
            notify("JobId Queue", "Сначала нажми «Загрузить и очистить список JobId».")
            return
        end
        if jobQueueIndex > #jobQueue then
            notify("JobId Queue", "Очередь закончилась. Загрузи новый список.")
            return
        end
        local value = jobQueue[jobQueueIndex]
        local copied = copyText(value)
        notify("JobId Queue", string.format("ID %d/%d %s: %s",
            jobQueueIndex, #jobQueue,
            copied and "скопирован" or "готов к копированию",
            value))
        jobQueueIndex += 1
    end
})

JobQueueTab:CreateButton({
    Name = "Скопировать текущий JobId в очередь",
    Callback = function()
        local current = tostring(game.JobId or "")
        if current == "" then
            notify("JobId Queue", "Текущий сервер не предоставил JobId.")
            return
        end
        local copied = copyText(current)
        notify("JobId Queue", copied and "JobId текущего сервера скопирован." or ("JobId: " .. current))
    end
})

JobQueueTab:CreateButton({
    Name = "Сбросить очередь",
    Callback = function()
        jobQueue = {}
        jobQueueIndex = 1
        notify("JobId Queue", "Очередь очищена.")
    end
})

JobQueueTab:CreateParagraph({
    Title = "Важно",
    Content = "Эта вкладка только организует вручную собранные ID. Она не может определить, на каком из них находится конкретный игрок, пока сервер не раскрывает такой статус через доступный механизм. Для проверки используй существующую кнопку подключения вручную; автоматический перебор серверов и сбор присутствия конкретного пользователя сюда не добавлены."
})


--========================================================
-- MAXIM SERVER PANEL — PUBLIC SERVER BROWSER
-- Lists public instances and searches only the user's local saved history.
-- Public server list responses do not provide each server's full roster.
--========================================================
local ServerPanelTab = Window:CreateTab("Maxim Server Panel", 4483362458)
ServerPanelTab:CreateParagraph({
    Title = "Maxim Server Panel",
    Content = "Самописная мобильная панель: публичные серверы текущего плейса, число игроков, доступный ping/FPS и копирование JobId. Поиск ника проверяет только локально сохранённую историю встреч — список публичных серверов не раскрывает состав каждого сервера."
})

ServerPanelTab:CreateButton({
    Name = "Открыть Maxim Server Panel",
    Callback = function()
        local oldPanelGui = PlayerGui:FindFirstChild("MaximServerPanel")
        if oldPanelGui then oldPanelGui:Destroy() end

        local panelGui = Instance.new("ScreenGui")
        panelGui.Name = "MaximServerPanel"
        panelGui.ResetOnSpawn = false
        panelGui.IgnoreGuiInset = true
        panelGui.DisplayOrder = 1000004
        panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        panelGui.Parent = PlayerGui

        local panel = Instance.new("Frame")
        panel.Name = "MainPanel"
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.Position = UDim2.fromScale(0.5, 0.5)
        panel.Size = (State.UISettings and State.UISettings.CompactMode) and UDim2.new(0.86, 0, 0.68, 0) or UDim2.new(0.94, 0, 0.80, 0)
        panel.BackgroundColor3 = Palette.BG_MAIN
        panel.BorderSizePixel = 0
        panel.Parent = panelGui
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
        applyCustomGuiSettings(panelGui, panel)
        local panelStroke = Instance.new("UIStroke")
        panelStroke.Color = Palette.RED_BRIGHT
        panelStroke.Thickness = 1.5
        panelStroke.Parent = panel
        local panelConstraint = Instance.new("UISizeConstraint")
        panelConstraint.MinSize = Vector2.new(285, 360)
        panelConstraint.MaxSize = Vector2.new(720, 800)
        panelConstraint.Parent = panel

        local header = Instance.new("TextLabel")
        header.Position = UDim2.fromOffset(14, 8)
        header.Size = UDim2.new(1, -118, 0, 34)
        header.BackgroundTransparency = 1
        header.Text = "MAXIM  •  SERVER PANEL"
        local brand = Instance.new("TextLabel")
        brand.Name = "BrandIcon"
        brand.Position = UDim2.new(1, -116, 0, 0)
        brand.Size = UDim2.fromOffset(32, 34)
        brand.BackgroundTransparency = 1
        brand.Text = BRAND_ICON
        brand.TextColor3 = Palette.WHITE
        brand.Font = Enum.Font.GothamBold
        brand.TextSize = 23
        brand.Parent = panel
        TweenService:Create(brand, TweenInfo.new(.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {TextColor3 = Palette.RED_NEON}):Play()
        header.TextColor3 = Palette.RED_BRIGHT
        header.Font = Enum.Font.GothamBold
        header.TextSize = 17
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Parent = panel

        local function makeTopButton(name, textValue, xOffset, width, color)
            local button = Instance.new("TextButton")
            button.Name = name
            button.AnchorPoint = Vector2.new(1, 0)
            button.Position = UDim2.new(1, xOffset, 0, 8)
            button.Size = UDim2.fromOffset(width, 32)
            button.BackgroundColor3 = color
            button.Text = textValue
            button.TextColor3 = Color3.new(1, 1, 1)
            button.Font = Enum.Font.GothamBold
            button.TextSize = 19
            button.Parent = panel
            Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
            return button
        end

        local minimizeButton = makeTopButton("Minimize", "—", -52, 36, Palette.RED_PRIMARY)
        local closeButton = makeTopButton("Close", "×", -10, 34, Palette.RED_PRIMARY)

        local usernameBox = Instance.new("TextBox")
        usernameBox.Name = "HistoryUsername"
        usernameBox.Position = UDim2.fromOffset(12, 50)
        usernameBox.Size = UDim2.new(1, -24, 0, 40)
        usernameBox.BackgroundColor3 = Palette.BG_INPUT
        usernameBox.BorderSizePixel = 0
        usernameBox.TextColor3 = Color3.new(1, 1, 1)
        usernameBox.PlaceholderColor3 = Palette.TEXT_MUTED
        usernameBox.PlaceholderText = "Username — поиск только в локальной истории"
        usernameBox.Text = ""
        usernameBox.ClearTextOnFocus = false
        usernameBox.Font = Enum.Font.Gotham
        usernameBox.TextSize = 13
        usernameBox.Parent = panel
        Instance.new("UICorner", usernameBox).CornerRadius = UDim.new(0, 9)

        local refreshButton = Instance.new("TextButton")
        refreshButton.Name = "RefreshServers"
        refreshButton.Position = UDim2.fromOffset(12, 98)
        refreshButton.Size = UDim2.new(0.48, -16, 0, 38)
        refreshButton.BackgroundColor3 = Palette.RED_PRIMARY
        refreshButton.Text = "↻  ОБНОВИТЬ СЕРВЕРЫ"
        refreshButton.TextColor3 = Color3.new(1, 1, 1)
        refreshButton.Font = Enum.Font.GothamBold
        refreshButton.TextSize = 12
        refreshButton.Parent = panel
        Instance.new("UICorner", refreshButton).CornerRadius = UDim.new(0, 9)

        local historyButton = Instance.new("TextButton")
        historyButton.Name = "SearchSavedHistory"
        historyButton.Position = UDim2.new(0.52, 4, 0, 98)
        historyButton.Size = UDim2.new(0.48, -16, 0, 38)
        historyButton.BackgroundColor3 = Palette.RED_PRIMARY
        historyButton.Text = "⌕  ИСТОРИЯ ВСТРЕЧ"
        historyButton.TextColor3 = Color3.new(1, 1, 1)
        historyButton.Font = Enum.Font.GothamBold
        historyButton.TextSize = 12
        historyButton.Parent = panel
        Instance.new("UICorner", historyButton).CornerRadius = UDim.new(0, 9)

        local status = Instance.new("TextLabel")
        status.Name = "Status"
        status.Position = UDim2.fromOffset(14, 141)
        status.Size = UDim2.new(1, -28, 0, 35)
        status.BackgroundTransparency = 1
        status.TextColor3 = Palette.TEXT_MUTED
        status.Text = "Нажми «Обновить серверы». Поиск ника работает по сохранённым встречам."
        status.TextWrapped = true
        status.Font = Enum.Font.Gotham
        status.TextSize = 11
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = panel

        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "Results"
        scroll.Position = UDim2.fromOffset(12, 180)
        scroll.Size = UDim2.new(1, -24, 1, -192)
        scroll.BackgroundColor3 = Palette.BG_SCROLL
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 5
        scroll.ScrollBarImageColor3 = Palette.RED_PRIMARY
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.Parent = panel
        Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 10)
        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 6)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Parent = scroll
        local listPadding = Instance.new("UIPadding")
        listPadding.PaddingTop = UDim.new(0, 7)
        listPadding.PaddingBottom = UDim.new(0, 7)
        listPadding.PaddingLeft = UDim.new(0, 7)
        listPadding.PaddingRight = UDim.new(0, 7)
        listPadding.Parent = scroll

        local floatingM = Instance.new("TextButton")
        floatingM.Name = "FloatingM"
        floatingM.AnchorPoint = Vector2.new(1, 1)
        floatingM.Position = UDim2.new(1, -18, 1, -100)
        floatingM.Size = UDim2.fromOffset(52, 52)
        floatingM.BackgroundColor3 = Palette.BG_PANEL
        floatingM.BackgroundTransparency = 0.12
        floatingM.Text = "M"
        floatingM.TextColor3 = Palette.RED_BRIGHT
        floatingM.TextSize = 24
        floatingM.Font = Enum.Font.GothamBold
        floatingM.Visible = false
        floatingM.Parent = panelGui
        Instance.new("UICorner", floatingM).CornerRadius = UDim.new(1, 0)
        local mStroke = Instance.new("UIStroke")
        mStroke.Color = Palette.RED_BRIGHT
        mStroke.Thickness = 2
        mStroke.Parent = floatingM

        local minimizedPanel = false
        minimizeButton.Activated:Connect(function()
            minimizedPanel = true
            panel.Visible = false
            floatingM.Visible = true
        end)
        floatingM.Activated:Connect(function()
            minimizedPanel = false
            panel.Visible = true
            floatingM.Visible = false
        end)
        closeButton.Activated:Connect(function()
            panelGui:Destroy()
        end)

        local publicServers = {}
        local refreshing = false

        local function clearPanelRows()
            for _, child in ipairs(scroll:GetChildren()) do
                if child ~= listLayout and child ~= listPadding then
                    child:Destroy()
                end
            end
        end

        local function addPanelStatus(message, order)
            local label = Instance.new("TextLabel")
            label.LayoutOrder = order or 999999
            label.Size = UDim2.new(1, -8, 0, 52)
            label.BackgroundColor3 = Palette.BG_ROW
            label.BackgroundTransparency = 0.15
            label.BorderSizePixel = 0
            label.TextColor3 = Palette.WHITE_SOFT
            label.TextWrapped = true
            label.Font = Enum.Font.Gotham
            label.TextSize = 12
            label.Text = message
            label.Parent = scroll
            Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
        end

        local function addSection(titleText, order)
            local label = Instance.new("TextLabel")
            label.LayoutOrder = order
            label.Size = UDim2.new(1, -8, 0, 28)
            label.BackgroundTransparency = 1
            label.TextColor3 = Palette.RED_BRIGHT
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Font = Enum.Font.GothamBold
            label.TextSize = 13
            label.Text = titleText
            label.Parent = scroll
        end

        local function addServerRow(titleText, details, jobId, order)
            local row = Instance.new("Frame")
            row.LayoutOrder = order
            row.Size = UDim2.new(1, -8, 0, 76)
            row.BackgroundColor3 = Palette.BG_ROW
            row.BorderSizePixel = 0
            row.Parent = scroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

            local title = Instance.new("TextLabel")
            title.Position = UDim2.fromOffset(9, 6)
            title.Size = UDim2.new(1, -94, 0, 24)
            title.BackgroundTransparency = 1
            title.TextColor3 = Color3.new(1, 1, 1)
            title.Font = Enum.Font.GothamBold
            title.TextSize = 12
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.TextTruncate = Enum.TextTruncate.AtEnd
            title.Text = titleText
            title.Parent = row

            local info = Instance.new("TextLabel")
            info.Position = UDim2.fromOffset(9, 31)
            info.Size = UDim2.new(1, -18, 0, 34)
            info.BackgroundTransparency = 1
            info.TextColor3 = Palette.TEXT_MUTED
            info.Font = Enum.Font.Code
            info.TextSize = 10
            info.TextXAlignment = Enum.TextXAlignment.Left
            info.TextYAlignment = Enum.TextYAlignment.Top
            info.TextWrapped = true
            info.Text = details
            info.Parent = row

            local copyButton = Instance.new("TextButton")
            copyButton.AnchorPoint = Vector2.new(1, 0)
            copyButton.Position = UDim2.new(1, -7, 0, 7)
            copyButton.Size = UDim2.fromOffset(78, 28)
            copyButton.BackgroundColor3 = Palette.RED_PRIMARY
            copyButton.Text = "КОПИРОВАТЬ"
            copyButton.TextColor3 = Color3.new(1, 1, 1)
            copyButton.Font = Enum.Font.GothamBold
            copyButton.TextSize = 9
            copyButton.Parent = row
            Instance.new("UICorner", copyButton).CornerRadius = UDim.new(0, 7)
            copyButton.Activated:Connect(function()
                if type(jobId) ~= "string" or jobId == "" then
                    notify("Maxim Server Panel", "Для этой записи нет JobId.")
                    return
                end
                local copied = copyText(jobId)
                notify("Maxim Server Panel", copied and "JobId скопирован." or ("JobId: " .. jobId))
            end)
        end

        local function renderPanel()
            if not panelGui.Parent then return end
            clearPanelRows()
            local query = string.lower(trim(usernameBox.Text))
            local order = 1

            if query ~= "" then
                addSection("СОВПАДЕНИЯ В ЛОКАЛЬНОЙ ИСТОРИИ", order)
                order += 1
                local matched = 0
                for _, record in ipairs(State.ServerHistory or {}) do
                    local foundPlayers = {}
                    for _, playerRecord in ipairs(record.Players or {}) do
                        local name = string.lower(tostring(playerRecord.Name or ""))
                        local displayName = string.lower(tostring(playerRecord.DisplayName or ""))
                        if string.find(name, query, 1, true) or string.find(displayName, query, 1, true) then
                            table.insert(foundPlayers, playerRecord)
                        end
                    end
                    if #foundPlayers > 0 then
                        matched += 1
                        local names = {}
                        for i = 1, math.min(#foundPlayers, 3) do
                            table.insert(names, "@" .. tostring(foundPlayers[i].Name or "?"))
                        end
                        addServerRow(
                            tostring(record.PlaceName or "Сохранённый сервер"),
                            table.concat(names, ", ") .. "\nПоследняя встреча: " ..
                                os.date("%Y-%m-%d %H:%M", tonumber(record.LastSeen or record.FirstSeen or 0)),
                            tostring(record.JobId or ""),
                            order
                        )
                        order += 1
                    end
                end
                if matched == 0 then
                    addPanelStatus("В локальной истории совпадений нет. Это не означает, что игрок офлайн: публичный список серверов не содержит состав игроков.", order)
                    order += 1
                end
            end

            addSection("ПУБЛИЧНЫЕ СЕРВЕРЫ ТЕКУЩЕГО ПЛЕЙСА", order)
            order += 1
            if #publicServers == 0 then
                addPanelStatus("Список пока пуст. Нажми «Обновить серверы».", order)
                return
            end
            -- Легитная сводка: только поля, которые возвращает публичный API Roblox.
            -- API не предоставляет roster, usernames, avatar/skin или сообщения чата.
            local totalPlayers, totalCapacity, joinable, fullServers = 0, 0, 0, 0
            for _, server in ipairs(publicServers) do
                local playing = tonumber(server.playing) or 0
                local capacity = tonumber(server.maxPlayers) or 0
                totalPlayers += playing
                totalCapacity += capacity
                if capacity > 0 and playing < capacity then
                    joinable += 1
                elseif capacity > 0 and playing >= capacity then
                    fullServers += 1
                end
            end
            addPanelStatus(string.format(
                "СВОДКА: серверов %d  •  игроков %d  •  места %d\nСо свободными слотами: %d  •  заполненных: %d\nПопулярность = заполненность сервера; данные игроков/чата не раскрываются API.",
                #publicServers, totalPlayers, totalCapacity, joinable, fullServers
            ), order)
            order += 1

            -- Сортировка отображения: сначала самые заполненные серверы.
            local rankedServers = {}
            for _, server in ipairs(publicServers) do
                table.insert(rankedServers, server)
            end
            table.sort(rankedServers, function(a, b)
                local aPlaying, aMax = tonumber(a.playing) or 0, tonumber(a.maxPlayers) or 0
                local bPlaying, bMax = tonumber(b.playing) or 0, tonumber(b.maxPlayers) or 0
                local aFill = aMax > 0 and (aPlaying / aMax) or -1
                local bFill = bMax > 0 and (bPlaying / bMax) or -1
                if aFill ~= bFill then return aFill > bFill end
                local aPing, bPing = tonumber(a.ping), tonumber(b.ping)
                if aPing and bPing then return aPing < bPing end
                if aPing then return true end
                if bPing then return false end
                return tostring(a.id or "") < tostring(b.id or "")
            end)

            for i, server in ipairs(rankedServers) do
                local ping = tonumber(server.ping)
                local fps = tonumber(server.fps)
                local playing = tonumber(server.playing) or 0
                local capacity = tonumber(server.maxPlayers) or 0
                local freeSlots = math.max(0, capacity - playing)
                local fillPercent = capacity > 0 and math.floor((playing / capacity) * 100 + 0.5) or nil
                local details = string.format(
                    "Игроки: %d/%d  •  Заполнение: %s  •  Свободно: %d\nPing: %s  •  FPS: %s\nJobId: %s",
                    playing,
                    capacity,
                    fillPercent and (tostring(fillPercent) .. "%") or "н/д",
                    freeSlots,
                    ping and (tostring(math.floor(ping + 0.5)) .. " ms") or "н/д",
                    fps and tostring(math.floor(fps + 0.5)) or "н/д",
                    tostring(server.id or "?")
                )
                local titleText = string.format(
                    "%s #%d%s",
                    (capacity > 0 and playing >= capacity) and "ЗАПОЛНЕН" or "Публичный сервер",
                    i,
                    (fillPercent and ("  •  " .. tostring(fillPercent) .. "%")) or ""
                )
                addServerRow(titleText, details, tostring(server.id or ""), order)
                order += 1
            end
        end

        local function searchHistoryOnly()
            renderPanel()
            if trim(usernameBox.Text) ~= "" then
                status.Text = "Ник проверяется по локальным снимкам; это не live-поиск по чужим серверам."
            else
                status.Text = "Введи ник для поиска в истории или обнови список публичных серверов."
            end
        end
        usernameBox:GetPropertyChangedSignal("Text"):Connect(searchHistoryOnly)
        historyButton.Activated:Connect(searchHistoryOnly)

        refreshButton.Activated:Connect(function()
            if refreshing then return end
            refreshing = true
            refreshButton.Text = "ЗАГРУЗКА..."
            status.Text = "Запрашиваю страницы публичных серверов текущего плейса..."
            task.spawn(function()
                local collected, seen = {}, {}
                local cursor = nil
                local maxPages = 10
                local failed = false
                for page = 1, maxPages do
                    if not panelGui.Parent then break end
                    local url = "https://games.roblox.com/v1/games/"
                        .. tostring(game.PlaceId)
                        .. "/servers/Public?limit=100&sortOrder=Asc"
                    if cursor and cursor ~= "" then
                        url = url .. "&cursor=" .. encodeQuery(cursor)
                    end

                    local data = companionRequest(url)
                    if type(data) ~= "table" or type(data.data) ~= "table" then
                        failed = true
                        break
                    end

                    for _, server in ipairs(data.data) do
                        local id = tostring(server.id or "")
                        if id ~= "" and not seen[id] then
                            seen[id] = true
                            table.insert(collected, server)
                        end
                    end

                    cursor = data.nextPageCursor
                    status.Text = string.format(
                        "Загрузка страниц: %d/%d  •  получено серверов: %d",
                        page, maxPages, #collected
                    )
                    if not cursor or cursor == "" then break end
                    task.wait(0.35)
                end

                if panelGui.Parent then
                    publicServers = collected
                    table.sort(publicServers, function(a, b)
                        local pa, pb = tonumber(a.ping), tonumber(b.ping)
                        if pa and pb then return pa < pb end
                        if pa then return true end
                        if pb then return false end
                        return (tonumber(a.playing) or 0) < (tonumber(b.playing) or 0)
                    end)
                    status.Text = string.format(
                        "%s • Загружено публичных серверов: %d",
                        failed and "Запрос остановлен: API/HTTP ограничение" or "Обновление завершено",
                        #publicServers
                    )
                    renderPanel()
                end
                refreshing = false
                if refreshButton.Parent then refreshButton.Text = "↻  ОБНОВИТЬ СЕРВЕРЫ" end
            end)
        end)

        renderPanel()
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
                        row.BackgroundColor3 = Palette.BG_ROW
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
                        sub.TextColor3 = Palette.TEXT_MUTED
                        sub.Font = Enum.Font.Code
                        sub.TextSize = 11
                        sub.TextXAlignment = Enum.TextXAlignment.Left
                        sub.Text = "PlaceId: " .. tostring(placeId or "не найден")
                        sub.Parent = row

                        local play = Instance.new("TextButton")
                        play.AnchorPoint = Vector2.new(1, 0.5)
                        play.Position = UDim2.new(1, -8, 0.5, 0)
                        play.Size = UDim2.fromOffset(78, 34)
                        play.BackgroundColor3 = Palette.RED_PRIMARY
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
    panel.Size = (State.UISettings and State.UISettings.CompactMode) and UDim2.new(0.86,0,0.68,0) or UDim2.new(0.92, 0, 0.76, 0)
    panel.BackgroundColor3 = Palette.BG_PANEL
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
    applyCustomGuiSettings(gui, panel)
    local stroke = Instance.new("UIStroke", panel)
    stroke.Color = Palette.RED_BRIGHT
    stroke.Transparency = 0.2
    stroke.Thickness = 1.3
    local sizeConstraint = Instance.new("UISizeConstraint", panel)
    sizeConstraint.MinSize = Vector2.new(280, 330)
    sizeConstraint.MaxSize = Vector2.new(560, 620)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Palette.RED_DEEP
    header.BorderSizePixel = 0
    header.Parent = panel
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)
    local title = Instance.new("TextLabel")
    title.Position = UDim2.fromOffset(14, 0)
    title.Size = UDim2.new(1, -112, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "✦ SOCIAL LOUNGE"
    title.TextColor3 = Palette.WHITE
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
    local minimize = makeButton(header, "—", UDim2.new(1, -88, 0, 7), UDim2.fromOffset(36, 34), Palette.RED_PRIMARY)
    local close = makeButton(header, "×", UDim2.new(1, -46, 0, 7), UDim2.fromOffset(36, 34), Palette.RED_PRIMARY)

    local status = Instance.new("TextLabel")
    status.Position = UDim2.fromOffset(12, 52)
    status.Size = UDim2.new(1, -24, 0, 25)
    status.BackgroundTransparency = 1
    status.Text = "Подключение не настроено"
    status.TextColor3 = Palette.TEXT_MUTED
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = panel

    local feed = Instance.new("ScrollingFrame")
    feed.Position = UDim2.fromOffset(10, 80)
    feed.Size = UDim2.new(1, -20, 1, -174)
    feed.BackgroundColor3 = Palette.BG_SCROLL
    feed.BackgroundTransparency = 0.08
    feed.BorderSizePixel = 0
    feed.ScrollBarThickness = 4
    feed.ScrollBarImageColor3 = Palette.RED_PRIMARY
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
    input.BackgroundColor3 = Palette.BG_INPUT
    input.BorderSizePixel = 0
    input.Text = ""
    input.PlaceholderText = "Напиши сообщение..."
    input.PlaceholderColor3 = Palette.TEXT_MUTED
    input.TextColor3 = Color3.new(1, 1, 1)
    input.Font = Enum.Font.Gotham
    input.TextSize = 14
    input.ClearTextOnFocus = false
    input.TextXAlignment = Enum.TextXAlignment.Left
    input.Parent = panel
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 9)
    local send = makeButton(panel, "➤", UDim2.new(1, -72, 1, -82), UDim2.fromOffset(62, 42), Palette.RED_PRIMARY)
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
        local b = makeButton(quick, item[1], UDim2.new(), UDim2.new(0.25, -5, 1, 0), Palette.BG_ROW)
        b.TextSize = 13
        b.Activated:Connect(function() input.Text = item[2]; input:CaptureFocus() end)
    end

    local triggerGui = Instance.new("ScreenGui")
    triggerGui.Name = triggerGuiName
    triggerGui.ResetOnSpawn = false
    triggerGui.IgnoreGuiInset = true
    triggerGui.DisplayOrder = 1000005
    triggerGui.Parent = PlayerGui
    local trigger = makeButton(triggerGui, "✦", UDim2.new(1, -72, 0.55, 0), UDim2.fromOffset(54, 54), Palette.RED_PRIMARY)
    trigger.AnchorPoint = Vector2.new(0, 0)
    trigger.TextSize = 25
    trigger.Active = true
    trigger.Draggable = false
    Instance.new("UIStroke", trigger).Color = Palette.WHITE

    local minimized = false
    local function setOpen(open)
        if open then
            minimized = false
            gui.Enabled = true
            panel.Visible = true
            trigger.Text = BRAND_ICON
        else
            gui.Enabled = false
            trigger.Text = BRAND_ICON
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
        trigger.Text = BRAND_ICON
    end)
    close.Activated:Connect(function()
        gui.Enabled = false
        panel.Visible = true
        minimized = false
        trigger.Text = BRAND_ICON
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
        row.BackgroundColor3 = Palette.BG_ROW
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




--========================================================
-- MAXIM SESSION INSIGHTS v12
-- Uses only the existing local State tables.
--========================================================
do
    local InsightsTab = Window:CreateTab("Insights v12", 4483362458)
    local sessionStartedAt = os.clock()
    local insightsParagraph = InsightsTab:CreateParagraph({Title="Session Insights", Content="Нажми «Обновить сводку»."})

    local function collectInsights()
        local serverCount, playerRecords, uniquePlayers, totalPlayers = 0, 0, {}, 0
        local totalSize, maxSize = 0, 0
        for _, server in ipairs(State.ServerHistory or {}) do
            serverCount += 1
            local players = type(server.Players) == "table" and server.Players or {}
            local count = #players
            playerRecords += count
            totalPlayers += count
            totalSize += tonumber(server.PlayerCount) or count
            maxSize = math.max(maxSize, tonumber(server.PlayerCount) or count)
            for _, player in ipairs(players) do
                local id = tonumber(player.UserId)
                if id then
                    uniquePlayers[id] = uniquePlayers[id] or {
                        Name = tostring(player.Name or player.DisplayName or "Unknown"), UserId = id
                    }
                end
            end
        end
        local uniqueCount = 0
        for _ in pairs(uniquePlayers) do uniqueCount += 1 end
        local duration = math.max(0, math.floor(os.clock() - sessionStartedAt))
        local avgSize = serverCount > 0 and (totalSize / serverCount) or 0
        local eventsCount = #(State.Events or {})
        local content = string.format("Длительность: %02d:%02d:%02d\nСерверов в истории: %d\nЗаписей игроков: %d\nУникальных UserId: %d\nСредний размер: %.1f | Максимальный: %d\nСобытий: %d",
            math.floor(duration/3600), math.floor((duration%3600)/60), duration%60,
            serverCount, playerRecords, uniqueCount, avgSize, maxSize, eventsCount)
        return content, uniquePlayers, serverCount, playerRecords, totalPlayers, maxSize
    end

    local function refreshInsights()
        local content = collectInsights()
        if insightsParagraph and type(insightsParagraph.Set) == "function" then
            pcall(function() insightsParagraph:Set({Title="Session Insights", Content=content}) end)
        end
        notify("Insights v12", "Сводка обновлена.")
    end

    InsightsTab:CreateButton({Name="Обновить сводку", Callback=refreshInsights})
    InsightsTab:CreateButton({Name="Топ-5 крупнейших серверов", Callback=function()
        local servers = {}
        for _, record in ipairs(State.ServerHistory or {}) do table.insert(servers, record) end
        table.sort(servers, function(a,b)
            return #(a.Players or {}) > #(b.Players or {})
        end)
        local lines = {}
        for i=1,math.min(5,#servers) do
            local record=servers[i]
            lines[#lines+1]=string.format("%d. %s — %d игроков | PlaceId: %s",
                i, tostring(record.PlaceName or "Server"), #(record.Players or {}), tostring(record.PlaceId or "?"))
        end
        notify("Insights v12 | Top 5", #lines>0 and table.concat(lines,"\n") or "История серверов пуста.")
    end})
    InsightsTab:CreateButton({Name="Список уникальных игроков", Callback=function()
        local _, players = collectInsights()
        local list={}
        for _, player in pairs(players) do table.insert(list,player) end
        table.sort(list,function(a,b) return a.UserId < b.UserId end)
        local lines={}
        for i=1,math.min(30,#list) do lines[#lines+1]=string.format("@%s (%d)",list[i].Name,list[i].UserId) end
        if #list>30 then lines[#lines+1]="… и ещё "..tostring(#list-30) end
        notify("Insights v12 | Игроки",#lines>0 and table.concat(lines,"\n") or "Уникальных игроков нет.")
    end})
    InsightsTab:CreateButton({Name="Экспорт инсайтов в буфер", Callback=function()
        local content, players, servers, records, total, maxSize = collectInsights()
        local lines={"MAXIM COMPANION HUB — SESSION INSIGHTS",content,"","Уникальные игроки:"}
        local list={}; for _,player in pairs(players) do table.insert(list,player) end
        table.sort(list,function(a,b) return a.UserId < b.UserId end)
        for _,player in ipairs(list) do lines[#lines+1]=string.format("@%s (%d)",player.Name,player.UserId) end
        local exported=copyText(table.concat(lines,"\n"))
        notify("Insights v12", exported and "Инсайты скопированы." or "Не удалось скопировать инсайты.")
    end})
end

--========================================================
-- MAXIM INSTANCE RESOLVER ADDON v1.0 (integrated)
-- Public server browser; Roblox public API does not expose
-- player rosters, so UserId -> JobId cannot be verified here.
--========================================================
do
    local InstanceResolver = {}
    InstanceResolver.Status = {
        FOUND = "found", NOT_FOUND = "not_found",
        PRIVATE_OR_DELETED = "private_or_deleted",
        UNVERIFIABLE = "unverifiable", INVALID_ARGUMENTS = "invalid_arguments",
        HTTP_ERROR = "http_error", RATE_LIMITED = "rate_limited",
    }
    InstanceResolver.__cache = {}
    local CONFIG = {
        url = "https://games.roblox.com/v1/games/%d/servers/Public",
        pageSize = 100, maxPages = 8, attempts = 3, cacheTtl = 30,
    }
    local function resolverHttp(url)
        for attempt = 1, CONFIG.attempts do
            local ok, response = pcall(function()
                return HttpService:RequestAsync({Url=url, Method="GET",
                    Headers={["Accept"]="application/json"}})
            end)
            if ok and type(response)=="table" and response.StatusCode then
                local code = tonumber(response.StatusCode) or 0
                if response.Success and code >= 200 and code < 300 then
                    local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
                    if decoded and type(data)=="table" then return data, code end
                    return nil, code
                end
                if code == 403 or code == 404 or code == 429 then return nil, code end
            end
            if attempt < CONFIG.attempts then task.wait(math.min(6, 1.5 ^ attempt)) end
        end
        return nil, 0
    end
    function InstanceResolver.GetPublicServers(placeId, bypassCache)
        local pid = tonumber(placeId)
        if not pid then return nil, InstanceResolver.Status.INVALID_ARGUMENTS end
        local key = "servers:" .. tostring(pid)
        local cached = InstanceResolver.__cache[key]
        if not bypassCache and cached and os.clock()-cached.t < CONFIG.cacheTtl then
            return cached.v, InstanceResolver.Status.FOUND
        end
        local all, seen, cursor = {}, {}, nil
        for page=1,CONFIG.maxPages do
            local url = string.format(CONFIG.url,pid) .. "?limit=" .. CONFIG.pageSize .. "&sortOrder=Asc"
            if cursor and cursor ~= "" then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
            local data, code = resolverHttp(url)
            if not data then
                if code==403 or code==404 then return nil,InstanceResolver.Status.PRIVATE_OR_DELETED end
                if code==429 then return nil,InstanceResolver.Status.RATE_LIMITED end
                if #all==0 then return nil,InstanceResolver.Status.HTTP_ERROR end
                break
            end
            for _,server in ipairs(data.data or {}) do
                local id=tostring(server.id or "")
                if id~="" and not seen[id] then
                    seen[id]=true
                    all[#all+1]={id=id,playing=tonumber(server.playing) or 0,
                        maxPlayers=tonumber(server.maxPlayers) or 0,
                        ping=tonumber(server.ping),fps=tonumber(server.fps)}
                end
            end
            cursor=data.nextPageCursor
            if not cursor or cursor=="" then break end
            task.wait(0.35)
        end
        InstanceResolver.__cache[key]={t=os.clock(),v=all}
        return all,InstanceResolver.Status.FOUND
    end
    function InstanceResolver.StatusToText(status)
        local S=InstanceResolver.Status
        if status==S.FOUND then return "Публичные серверы загружены" end
        if status==S.NOT_FOUND then return "Сессия не найдена" end
        if status==S.PRIVATE_OR_DELETED then return "Сессия удалена или приватная" end
        if status==S.UNVERIFIABLE then return "Невозможно проверить присутствие игрока через публичный API" end
        if status==S.INVALID_ARGUMENTS then return "Некорректный PlaceId" end
        if status==S.RATE_LIMITED then return "Roblox API: слишком много запросов (429)" end
        return "Ошибка сети / Roblox API"
    end
    function InstanceResolver.ClearCache() InstanceResolver.__cache={} end

    local ResolverTab=Window:CreateTab("Instance Resolver",4483362458)
    ResolverTab:CreateParagraph({Title="Instance Resolver",
        Content="Публичный браузер серверов Roblox. API не раскрывает список UserId внутри каждого инстанса, поэтому поиск конкретного игрока по серверам не подтверждается."})
    local placeInput=""
    ResolverTab:CreateInput({Name="PlaceId (пусто = текущий)",PlaceholderText="например: 920587237",
        RemoveTextAfterFocusLost=false,Callback=function(v) placeInput=v end})
    ResolverTab:CreateButton({Name="Показать доступные серверы",Callback=function()
        local pid=tonumber(placeInput) or game.PlaceId
        notify("Instance Resolver","Загрузка публичных серверов...")
        task.spawn(function()
            local servers,status=InstanceResolver.GetPublicServers(pid)
            if not servers then notify("Instance Resolver",InstanceResolver.StatusToText(status)); return end
            local available={}
            for _,s in ipairs(servers) do
                if s.maxPlayers>0 and s.playing<s.maxPlayers then available[#available+1]=s end
            end
            table.sort(available,function(a,b) return (a.ping or math.huge)<(b.ping or math.huge) end)
            local lines={}
            for i=1,math.min(#available,8) do
                local s=available[i]
                lines[#lines+1]=string.format("%d. %d/%d | ping=%s\\nJobId: %s",
                    i,s.playing,s.maxPlayers,tostring(s.ping or "?"),s.id)
            end
            if #lines==0 then lines={"Свободных серверов не найдено."} end
            notify("Instance Resolver",string.format("Серверов: %d | со свободными слотами: %d",
                #servers,#available).."\\n\\n"..table.concat(lines,"\\n\\n"))
        end)
    end})
    ResolverTab:CreateButton({Name="Очистить кэш",Callback=function()
        InstanceResolver.ClearCache(); notify("Instance Resolver","Кэш очищен.")
    end})
    _G.MaximInstanceResolver=InstanceResolver
    print("[Instance Resolver] initialized")
    notify("Instance Resolver","Вкладка добавлена.")
end

