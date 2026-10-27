--[[
    MAXIM COMPANION HUB v9.1 — UTILITY ADDON
    Standalone client-side utility panel.
    Does NOT replace or edit the main Hub script.

    Included:
      • Current place / server information
      • Copy JobId, PlaceId, and current coordinates (when clipboard API exists)
      • FPS and ping display
      • Rejoin current server
      • Minimize / restore / close
      • Draggable compact panel

    Notes:
      • Clipboard support depends on the executor. If unavailable, IDs remain visible
        in the panel so they can be copied manually.
      • Rejoin uses Roblox TeleportService and may be unavailable in Studio or
        restricted environments.
      • No global server scanning, player tracking, or movement/targeting exploits.
]]

local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Maxim Utility Addon] LocalPlayer not available.")
    return
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GUI_NAME = "MaximUtilityAddonV91"

local existing = PlayerGui:FindFirstChild(GUI_NAME)
if existing then
    existing:Destroy()
end

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(parent, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, parent)
end

local function stroke(parent, color, transparency)
    make("UIStroke", {
        Color = color or Color3.fromRGB(74, 87, 115),
        Thickness = 1,
        Transparency = transparency or 0.25
    }, parent)
end

local function safeClipboard(value)
    local candidates = {}
    if type(setclipboard) == "function" then table.insert(candidates, setclipboard) end
    if type(toclipboard) == "function" then table.insert(candidates, toclipboard) end
    if type(writeclipboard) == "function" then table.insert(candidates, writeclipboard) end
    for _, fn in ipairs(candidates) do
        if fn then
            local ok = pcall(fn, tostring(value))
            if ok then return true end
        end
    end
    return false
end

local gui = make("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 80
}, PlayerGui)

local main = make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(310, 360),
    Position = UDim2.new(0, 24, 0.35, 0),
    BackgroundColor3 = Color3.fromRGB(17, 20, 30),
    BorderSizePixel = 0,
    Active = true
}, gui)
round(main, 14)
stroke(main, Color3.fromRGB(92, 108, 145), 0.15)

local top = make("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = Color3.fromRGB(28, 34, 50),
    BorderSizePixel = 0
}, main)
round(top, 14)
make("Frame", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = Color3.fromRGB(28, 34, 50),
    BorderSizePixel = 0
}, top)

local title = make("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(13, 0),
    Size = UDim2.new(1, -94, 1, 0),
    BackgroundTransparency = 1,
    Text = "MAXIM  •  UTILITIES",
    TextColor3 = Color3.fromRGB(238, 242, 255),
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, top)

local function makeTopButton(text, x, color)
    local button = make("TextButton", {
        Size = UDim2.fromOffset(27, 26),
        Position = UDim2.new(1, x, 0, 8),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(245, 247, 255),
        TextSize = 15,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true
    }, top)
    round(button, 8)
    return button
end

local minimizeButton = makeTopButton("—", -62, Color3.fromRGB(68, 78, 104))
local closeButton = makeTopButton("×", -31, Color3.fromRGB(148, 61, 75))

local body = make("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(12, 51),
    Size = UDim2.new(1, -24, 1, -62),
    BackgroundTransparency = 1
}, main)

local status = make("TextLabel", {
    Name = "Status",
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = Color3.fromRGB(25, 31, 45),
    BorderSizePixel = 0,
    Text = "Loading session information…",
    TextColor3 = Color3.fromRGB(180, 197, 225),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextWrapped = true
}, body)
round(status, 8)

local info = make("TextLabel", {
    Name = "Info",
    Position = UDim2.fromOffset(0, 34),
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundTransparency = 1,
    Text = "FPS: --   •   Ping: --\nPlayers: --   •   JobId: loading",
    TextColor3 = Color3.fromRGB(208, 216, 235),
    TextSize = 11,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextWrapped = true
}, body)

local idBox = make("TextBox", {
    Name = "JobIdBox",
    Position = UDim2.fromOffset(0, 83),
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = Color3.fromRGB(11, 14, 22),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Text = tostring(game.JobId),
    PlaceholderText = "Current JobId",
    TextColor3 = Color3.fromRGB(168, 205, 255),
    PlaceholderColor3 = Color3.fromRGB(115, 125, 149),
    TextSize = 10,
    Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left
}, body)
round(idBox, 7)
make("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, idBox)

local function makeButton(text, y, callback, accent)
    local button = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 31),
        Position = UDim2.fromOffset(0, y),
        BackgroundColor3 = accent or Color3.fromRGB(43, 55, 80),
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(244, 247, 255),
        TextSize = 11,
        Font = Enum.Font.GothamSemibold,
        AutoButtonColor = true
    }, body)
    round(button, 8)
    button.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then
            status.Text = "Error: " .. tostring(err):sub(1, 70)
            status.TextColor3 = Color3.fromRGB(255, 148, 158)
        end
    end)
    return button
end

local function setStatus(message, isError)
    status.Text = tostring(message)
    status.TextColor3 = isError
        and Color3.fromRGB(255, 148, 158)
        or Color3.fromRGB(180, 220, 190)
end

makeButton("Copy current JobId", 123, function()
    local value = tostring(game.JobId)
    if value == "" then
        setStatus("This server has no available JobId.", true)
        return
    end
    if safeClipboard(value) then
        setStatus("JobId copied to clipboard.")
    else
        idBox.Text = value
        idBox:CaptureFocus()
        idBox.CursorPosition = #idBox.Text + 1
        setStatus("Clipboard unavailable — select the ID above.")
    end
end)

makeButton("Copy PlaceId", 160, function()
    local value = tostring(game.PlaceId)
    if safeClipboard(value) then
        setStatus("PlaceId copied to clipboard.")
    else
        idBox.Text = value
        idBox:CaptureFocus()
        idBox.CursorPosition = #idBox.Text + 1
        setStatus("Clipboard unavailable — PlaceId is shown above.")
    end
end)

makeButton("Copy my coordinates", 197, function()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        setStatus("Character is not loaded yet.", true)
        return
    end
    local p = root.Position
    local value = string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
    if safeClipboard(value) then
        setStatus("Coordinates copied: " .. value)
    else
        idBox.Text = value
        idBox:CaptureFocus()
        idBox.CursorPosition = #idBox.Text + 1
        setStatus("Clipboard unavailable — coordinates are shown above.")
    end
end)

makeButton("Refresh server information", 234, function()
    idBox.Text = tostring(game.JobId)
    setStatus(string.format("Refreshed • PlaceId %s", tostring(game.PlaceId)))
end)

makeButton("Rejoin this server", 271, function()
    if game.JobId == "" then
        setStatus("JobId is unavailable in this session.", true)
        return
    end
    setStatus("Requesting rejoin…")
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end, Color3.fromRGB(58, 76, 112))

local footer = make("TextLabel", {
    Position = UDim2.new(0, 0, 1, -20),
    Size = UDim2.new(1, 0, 0, 18),
    BackgroundTransparency = 1,
    Text = "Local utilities • no global player scan",
    TextColor3 = Color3.fromRGB(112, 125, 153),
    TextSize = 9,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Center
}, body)

-- Drag panel from the top bar. Supports mouse and touch.
local dragging = false
local dragStart, startPosition
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local minimized = false
minimizeButton.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(310, 42) or UDim2.fromOffset(310, 360)
    minimizeButton.Text = minimized and "+" or "—"
end)

closeButton.Activated:Connect(function()
    gui:Destroy()
end)

-- Lightweight performance display.
local frameCount = 0
local lastFpsUpdate = os.clock()
local fps = 0
local pingText = "--"
local alive = true

local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
    if not alive or not gui.Parent then
        if renderConnection then renderConnection:Disconnect() end
        return
    end
    frameCount += 1
    local now = os.clock()
    if now - lastFpsUpdate >= 1 then
        fps = frameCount
        frameCount = 0
        lastFpsUpdate = now

        local pingOk, pingValue = pcall(function()
            local network = Stats:FindFirstChild("Network")
            local serverStats = network and network:FindFirstChild("ServerStatsItem")
            local dataPing = serverStats and serverStats:FindFirstChild("Data Ping")
            return dataPing and dataPing:GetValueString() or nil
        end)
        if pingOk and pingValue then
            pingText = tostring(pingValue)
        end

        local playerCount = #Players:GetPlayers()
        local job = tostring(game.JobId)
        local shortJob = job ~= "" and (job:sub(1, 8) .. "…") or "unavailable"
        info.Text = string.format(
            "FPS: %d   •   Ping: %s\nPlayers: %d   •   JobId: %s",
            fps, pingText, playerCount, shortJob
        )
    end
end)

gui.Destroying:Connect(function()
    alive = false
    if renderConnection then
        renderConnection:Disconnect()
    end
end)

-- Small entrance animation.
main.BackgroundTransparency = 1
main.Size = UDim2.fromOffset(292, 338)
TweenService:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    BackgroundTransparency = 0,
    Size = UDim2.fromOffset(310, 360)
}):Play()

setStatus("Utility addon loaded.")
print("[Maxim Utility Addon] Loaded successfully.")
