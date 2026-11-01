-- Roblox Mobile Visual Panel
-- Safe LocalScript for YOUR OWN Roblox experience.
-- Install: StarterPlayer > StarterPlayerScripts > LocalScript
-- This does not inject into other games or bypass Roblox protections.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remove an older copy if this script is re-run.
local old = playerGui:FindFirstChild("MobileVisualPanel")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MobileVisualPanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.Parent = playerGui

local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local panel = make("Frame", {
    Name = "Panel",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.new(0, 280, 0, 390),
    BackgroundColor3 = Color3.fromRGB(18, 20, 29),
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 14)}, panel)
make("UIStroke", {Color = Color3.fromRGB(75, 91, 130), Transparency = 0.25, Thickness = 1}, panel)

local title = make("TextLabel", {
    Name = "Title",
    Size = UDim2.new(1, -52, 0, 42),
    Position = UDim2.new(0, 14, 0, 4),
    BackgroundTransparency = 1,
    Text = "VISUAL PANEL",
    TextColor3 = Color3.fromRGB(235, 240, 255),
    TextSize = 18,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local close = make("TextButton", {
    Name = "Close",
    Size = UDim2.fromOffset(32, 32),
    Position = UDim2.new(1, -40, 0, 8),
    BackgroundColor3 = Color3.fromRGB(48, 52, 68),
    Text = "×",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 24,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
}, panel)
make("UICorner", {CornerRadius = UDim.new(0, 9)}, close)

local scroll = make("ScrollingFrame", {
    Name = "Effects",
    Position = UDim2.new(0, 10, 0, 48),
    Size = UDim2.new(1, -20, 1, -58),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Color3.fromRGB(115, 130, 170),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
make("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)
make("UIPadding", {
    PaddingTop = UDim.new(0, 3),
    PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 2),
    PaddingRight = UDim.new(0, 2),
}, scroll)

local effects = {}
local created = {}

local function getEffect(className, name)
    local key = name
    if created[key] and created[key].Parent then return created[key] end
    local effect = Lighting:FindFirstChild("MobileVisual_" .. name)
    if not effect or not effect:IsA(className) then
        effect = Instance.new(className)
        effect.Name = "MobileVisual_" .. name
        effect.Parent = Lighting
    end
    created[key] = effect
    return effect
end

local function addToggle(label, effectName, className, property, enabledValue, disabledValue)
    local effect = getEffect(className, effectName)
    effect.Enabled = false
    if property then effect[property] = disabledValue end
    effects[#effects + 1] = {
        label = label,
        object = effect,
        property = property,
        onValue = enabledValue,
        offValue = disabledValue,
    }
end

-- Built-in Roblox post-processing / lighting effects.
addToggle("Bloom", "Bloom", "BloomEffect", "Intensity", 0.35, 0)
created.Bloom.Threshold = 1.1
created.Bloom.Size = 24

addToggle("Color correction", "ColorCorrection", "ColorCorrectionEffect", "Saturation", 0.18, 0)
created.ColorCorrection.Contrast = 0.08
created.ColorCorrection.Brightness = 0.02
created.ColorCorrection.TintColor = Color3.fromRGB(255, 244, 230)

addToggle("Sun rays", "SunRays", "SunRaysEffect", "Intensity", 0.08, 0)
created.SunRays.Spread = 0.75

addToggle("Depth of field", "DepthOfField", "DepthOfFieldEffect", "FarIntensity", 0.15, 0)
created.DepthOfField.NearIntensity = 0
created.DepthOfField.FocusDistance = 40
created.DepthOfField.InFocusRadius = 30

addToggle("Soft blur", "Blur", "BlurEffect", "Size", 3, 0)

local function addButton(text, callback)
    local button = make("TextButton", {
        Size = UDim2.new(1, -4, 0, 38),
        BackgroundColor3 = Color3.fromRGB(35, 40, 55),
        Text = text,
        TextColor3 = Color3.fromRGB(225, 232, 248),
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
    }, scroll)
    make("UICorner", {CornerRadius = UDim.new(0, 9)}, button)
    make("UIStroke", {Color = Color3.fromRGB(70, 80, 105), Transparency = 0.5}, button)
    button.Activated:Connect(callback)
    return button
end

local function setButtonState(button, enabled)
    button.Text = (enabled and "●  " or "○  ") .. button:GetAttribute("EffectLabel")
    button.BackgroundColor3 = enabled
        and Color3.fromRGB(45, 75, 105)
        or Color3.fromRGB(35, 40, 55)
end

for _, item in ipairs(effects) do
    local button = addButton("○  " .. item.label, function() end)
    button:SetAttribute("EffectLabel", item.label)
    button:SetAttribute("On", false)
    setButtonState(button, false)

    button.Activated:Connect(function()
        local enabled = not button:GetAttribute("On")
        button:SetAttribute("On", enabled)
        item.object.Enabled = enabled
        if item.property then
            item.object[item.property] = enabled and item.onValue or item.offValue
        end
        setButtonState(button, enabled)
    end)
end

addButton("Preset: Cinematic", function()
    for _, item in ipairs(effects) do
        item.object.Enabled = true
        if item.property then item.object[item.property] = item.onValue end
    end
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("TextButton") and child:GetAttribute("EffectLabel") then
            child:SetAttribute("On", true)
            setButtonState(child, true)
        end
    end
end)

addButton("Preset: Clean", function()
    for _, item in ipairs(effects) do
        item.object.Enabled = false
        if item.property then item.object[item.property] = item.offValue end
    end
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("TextButton") and child:GetAttribute("EffectLabel") then
            child:SetAttribute("On", false)
            setButtonState(child, false)
        end
    end
end)

addButton("Reset lighting", function()
    Lighting.Brightness = 2
    Lighting.ClockTime = 14
    Lighting.ExposureCompensation = 0
    Lighting.GlobalShadows = true
    Lighting.FogEnd = 100000
    Lighting.FogStart = 0
    for _, item in ipairs(effects) do
        item.object.Enabled = false
        if item.property then item.object[item.property] = item.offValue end
    end
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("TextButton") and child:GetAttribute("EffectLabel") then
            child:SetAttribute("On", false)
            setButtonState(child, false)
        end
    end
end)

-- Small open/close handle for phone screens.
local handle = make("TextButton", {
    Name = "OpenHandle",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0),
    Size = UDim2.fromOffset(34, 54),
    BackgroundColor3 = Color3.fromRGB(35, 42, 60),
    Text = "V",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 17,
    Font = Enum.Font.GothamBold,
    Visible = false,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 10)}, handle)

local isOpen = true
local function togglePanel()
    isOpen = not isOpen
    panel.Visible = isOpen
    handle.Visible = not isOpen
end
close.Activated:Connect(togglePanel)
handle.Activated:Connect(togglePanel)

-- Keep panel usable on narrow phone displays.
local function fitPanel()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local width = math.clamp(viewport.X - 24, 230, 280)
    local height = math.clamp(viewport.Y - 40, 250, 390)
    panel.Size = UDim2.fromOffset(width, height)
end
fitPanel()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fitPanel)
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
end

print("Mobile Visual Panel loaded. Intended for your own Roblox experience.")
