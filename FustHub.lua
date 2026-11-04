
-- UNIFIED AIM / BOW / ESP
-- Roblox Luau - single script

local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local WS = game:GetService("Workspace")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- Cleanup previous run
if _G.UnifiedAimCleanup then
    pcall(_G.UnifiedAimCleanup)
    _G.UnifiedAimCleanup = nil
end

local old = PG:FindFirstChild("UnifiedAimESP")
if old then old:Destroy() end

local S = {
    Aim = false,
    BowAim = false,
    ESP = false,

    FOVVisible = true,
    FOV = 160,
    Distance = 150,
    Smooth = 0.5,
    Prediction = 0,
    Part = "Head",

    TargetPlayers = true,
    TargetNPCs = true,

    Boxes = true,
    Names = true,
    Health = true,
    Highlight = true,
    ESPDistance = 1500,

    BowDistance = 350,
    BowSpeed = 120,
    BowGravity = 196.2,
    BowSmooth = 0.8,
    BowKey = Enum.KeyCode.B
}

local connections = {}
local visuals = {}
local running = true
local renderName = "UnifiedAimRender"

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function round(obj, radius)
    new("UICorner", {
        CornerRadius = UDim.new(0, radius)
    }, obj)
end

-- GUI
local gui = new("ScreenGui", {
    Name = "UnifiedAimESP",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 100
}, PG)

local panel = new("Frame", {
    Size = UDim2.fromOffset(310, 480),
    Position = UDim2.new(0, 25, 0.5, -240),
    BackgroundColor3 = Color3.fromRGB(22, 25, 36),
    BorderSizePixel = 0,
    Active = true
}, gui)
round(panel, 12)

new("UIStroke", {
    Color = Color3.fromRGB(65, 75, 105),
    Thickness = 1
}, panel)

local header = new("TextLabel", {
    Size = UDim2.new(1, -60, 0, 44),
    Position = UDim2.fromOffset(10, 4),
    BackgroundTransparency = 1,
    Text = "AIM / BOW / ESP",
    TextColor3 = Color3.fromRGB(240, 245, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    Active = true
}, panel)

local minimize = new("TextButton", {
    Size = UDim2.fromOffset(32, 30),
    Position = UDim2.new(1, -40, 0, 10),
    BackgroundColor3 = Color3.fromRGB(48, 55, 75),
    Text = "-",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 20
}, panel)
round(minimize, 6)

local scroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -20, 1, -58),
    Position = UDim2.fromOffset(10, 50),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y
}, panel)

new("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder
}, scroll)

local collapsed = false
connect(minimize.MouseButton1Click, function()
    collapsed = not collapsed
    scroll.Visible = not collapsed
    panel.Size = collapsed
        and UDim2.fromOffset(310, 50)
        or UDim2.fromOffset(310, 480)
    minimize.Text = collapsed and "+" or "-"
end)

local function button(text, callback)
    local b = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 35),
        BackgroundColor3 = Color3.fromRGB(43, 49, 68),
        Text = text,
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 13,
        Font = Enum.Font.GothamMedium
    }, scroll)
    round(b, 7)
    connect(b.MouseButton1Click, function()
        callback(b)
    end)
    return b
end

local function toggle(label, key)
    local b

    local function update()
        b.Text = label .. ": " ..
            (S[key] and "ON" or "OFF")

        b.BackgroundColor3 = S[key]
            and Color3.fromRGB(34, 125, 100)
            or Color3.fromRGB(43, 49, 68)
    end

    b = button("", function()
        S[key] = not S[key]
        update()
    end)

    update()
    return update
end

local function adjust(label, key, minimum, maximum, step)
    local row = new("Frame", {
        Size = UDim2.new(1, -6, 0, 38),
        BackgroundTransparency = 1
    }, scroll)

    local txt = new("TextLabel", {
        Size = UDim2.new(0.6, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(225, 230, 245),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextSize = 12
    }, row)

    local function update()
        txt.Text = label .. ": " ..
            string.format("%.2f", S[key])
    end

    for i, sign in ipairs({"-", "+"}) do
        local b = new("TextButton", {
            Size = UDim2.fromOffset(38, 30),
            Position = UDim2.new(
                i == 1 and 0.68 or 0.84,
                0, 0, 4
            ),
            BackgroundColor3 = Color3.fromRGB(55, 64, 89),
            Text = sign,
            TextColor3 = Color3.new(1, 1, 1),
            TextSize = 18,
            Font = Enum.Font.GothamBold
        }, row)
        round(b, 6)

        connect(b.MouseButton1Click, function()
            local delta = i == 1 and -step or step
            S[key] = math.clamp(
                S[key] + delta,
                minimum,
                maximum
            )
            S[key] = math.round(S[key] * 1000) / 1000
            update()
        end)
    end

    update()
end

-- AIM SETTINGS
toggle("Aim Assist", "Aim")

button("Target: HEAD", function(b)
    S.Part = S.Part == "Head"
        and "HumanoidRootPart" or "Head"

    b.Text = S.Part == "Head"
        and "Target: HEAD" or "Target: BODY"
end)

toggle("FOV Circle", "FOVVisible")
adjust("FOV", "FOV", 30, 500, 10)
adjust("Distance", "Distance", 20, 500, 10)
adjust("Smooth", "Smooth", 0.05, 1, 0.05)
adjust("Prediction", "Prediction", 0, 0.5, 0.025)

toggle("Target Players", "TargetPlayers")
toggle("Target NPCs", "TargetNPCs")

-- BOW SETTINGS
local updateBowToggle = toggle("Bow Aimbot", "BowAim")

adjust("Bow Range", "BowDistance", 50, 1000, 25)
adjust("Arrow Speed", "BowSpeed", 20, 400, 10)
adjust("Arrow Gravity", "BowGravity", 20, 400, 10)
adjust("Bow Smooth", "BowSmooth", 0.05, 1, 0.05)

local waitingForBind = false

local bindButton = button("Bow Keybind: B", function(b)
    waitingForBind = true
    b.Text = "Press any key..."
end)

-- ESP SETTINGS
toggle("Player ESP", "ESP")
toggle("ESP Boxes", "Boxes")
toggle("ESP Names", "Names")
toggle("ESP Health", "Health")
toggle("ESP Highlight", "Highlight")
adjust("ESP Distance", "ESPDistance", 50, 1500, 50)

-- DRAG PANEL
local dragging = false
local dragStart, panelStart

connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        panelStart = panel.Position
    end
end)

connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

connect(UIS.InputChanged, function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local d = input.Position - dragStart
        panel.Position = UDim2.new(
            panelStart.X.Scale,
            panelStart.X.Offset + d.X,
            panelStart.Y.Scale,
            panelStart.Y.Offset + d.Y
        )
    end
end)

-- MOBILE BOW BUTTON
local mobileButton = new("TextButton", {
    Name = "BowMobileToggle",
    Size = UDim2.fromOffset(76, 76),
    Position = UDim2.new(1, -105, 0.65, 0),
    BackgroundColor3 = Color3.fromRGB(45, 50, 70),
    Text = "BOW\nOFF",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    Active = true,
    ZIndex = 20
}, gui)
round(mobileButton, 18)

local function updateBow()
    updateBowToggle()

    mobileButton.Text = S.BowAim
        and "BOW\nON" or "BOW\nOFF"

    mobileButton.BackgroundColor3 = S.BowAim
        and Color3.fromRGB(30, 145, 100)
        or Color3.fromRGB(45, 50, 70)
end

local function switchBow()
    S.BowAim = not S.BowAim
    updateBow()
end

connect(UIS.InputBegan, function(input, processed)
    if waitingForBind then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            S.BowKey = input.KeyCode
            bindButton.Text =
                "Bow Keybind: " .. input.KeyCode.Name
            waitingForBind = false
        end
        return
    end

    if processed then return end

    if input.KeyCode == S.BowKey then
        switchBow()
    end
end)

-- Drag or tap mobile button
local draggingBow = false
local movedBow = false
local bowStart, bowPosition

connect(mobileButton.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingBow = true
        movedBow = false
        bowStart = input.Position
        bowPosition = mobileButton.Position
    end
end)

connect(UIS.InputChanged, function(input)
    if draggingBow and (
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
    ) then
        local d = input.Position - bowStart

        if d.Magnitude > 8 then
            movedBow = true
        end

        mobileButton.Position = UDim2.new(
            bowPosition.X.Scale,
            bowPosition.X.Offset + d.X,
            bowPosition.Y.Scale,
            bowPosition.Y.Offset + d.Y
        )
    end
end)

connect(UIS.InputEnded, function(input)
    if draggingBow and (
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    ) then
        draggingBow = false

        if not movedBow then
            switchBow()
        end
    end
end)

updateBow()

-- FOV CIRCLE
local circle = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0
}, gui)

new("UICorner", {
    CornerRadius = UDim.new(1, 0)
}, circle)

new("UIStroke", {
    Color = Color3.fromRGB(75, 170, 255),
    Thickness = 2
}, circle)

-- VISIBILITY
local function canSee(model, position, camera)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances =
        LP.Character and {LP.Character} or {}
    params.IgnoreWater = true

    local origin = camera.CFrame.Position
    local hit = WS:Raycast(
        origin,
        position - origin,
        params
    )

    return hit ~= nil
        and hit.Instance:IsDescendantOf(model)
end

-- TARGET SELECTION
local function getTarget(camera, maxDistance, targetPart)
    local center = camera.ViewportSize / 2
    local bestPart, bestModel
    local bestScore = S.FOV

    for _, model in ipairs(WS:GetDescendants()) do
        if model:IsA("Model") and model ~= LP.Character then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local part = model:FindFirstChild(targetPart)
            local root = model:FindFirstChild("HumanoidRootPart")

            if hum and hum.Health > 0
                and part and part:IsA("BasePart")
                and root then

                local targetPlayer =
                    Players:GetPlayerFromCharacter(model)

                local allowed =
                    (targetPlayer ~= nil and S.TargetPlayers)
                    or (targetPlayer == nil and S.TargetNPCs)

                if allowed then
                    local distance = (
                        camera.CFrame.Position - part.Position
                    ).Magnitude

                    if distance <= maxDistance then
                        local screen, onScreen =
                            camera:WorldToViewportPoint(part.Position)

                        if onScreen then
                            local score = (
                                Vector2.new(screen.X, screen.Y)
                                - center
                            ).Magnitude

                            if score < bestScore
                                and canSee(model, part.Position, camera) then
                                bestScore = score
                                bestPart = part
                                bestModel = model
                            end
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestModel
end

-- APPROXIMATE BOW BALLISTICS
local function bowAimPosition(part, model, camera)
    local root = model:FindFirstChild("HumanoidRootPart")
    local velocity = root
        and root.AssemblyLinearVelocity
        or Vector3.zero

    local origin = camera.CFrame.Position
    local target = part.Position

    local speed = math.max(S.BowSpeed, 1)
    local gravity = S.BowGravity

    local time = (target - origin).Magnitude / speed

    -- Iteratively estimate moving target position
    for _ = 1, 4 do
        local future = target + velocity * time
        local displacement = future - origin

        local horizontal = Vector3.new(
            displacement.X, 0, displacement.Z
        ).Magnitude

        time = math.sqrt(
            horizontal * horizontal
            + displacement.Y * displacement.Y
        ) / speed
    end

    local futurePosition = target + velocity * time
    local drop = 0.5 * gravity * time * time

    return futurePosition + Vector3.new(0, drop, 0)
end

-- ESP
local function removeVisual(p)
    local v = visuals[p]
    if not v then return end

    if v.Highlight then v.Highlight:Destroy() end
    if v.Billboard then v.Billboard:Destroy() end
    visuals[p] = nil
end

local function createVisual(p)
    if p == LP then return end
    removeVisual(p)

    local char = p.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local hl = new("Highlight", {
        Name = "UnifiedESPHighlight",
        Adornee = char,
        FillColor = Color3.fromRGB(255, 70, 80),
        OutlineColor = Color3.new(1, 1, 1),
        FillTransparency = 0.75,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = false
    }, gui)

    local bb = new("BillboardGui", {
        Name = "UnifiedESPInfo",
        Adornee = root,
        Size = UDim2.fromOffset(120, 190),
        StudsOffset = Vector3.new(0, 0.4, 0),
        AlwaysOnTop = true,
        Enabled = false
    }, gui)

    local box = new("Frame", {
        Size = UDim2.new(0.82, 0, 0.82, 0),
        Position = UDim2.new(0.09, 0, 0.09, 0),
        BackgroundTransparency = 1
    }, bb)

    new("UIStroke", {
        Color = Color3.fromRGB(255, 80, 90),
        Thickness = 2
    }, box)

    local name = new("TextLabel", {
        Size = UDim2.new(1, 30, 0, 24),
        Position = UDim2.fromOffset(-15, -26),
        BackgroundTransparency = 1,
        Text = p.DisplayName,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeTransparency = 0.25,
        Font = Enum.Font.GothamBold,
        TextSize = 12
    }, box)

    local hpBG = new("Frame", {
        Size = UDim2.fromOffset(6, 155),
        Position = UDim2.fromOffset(-12, 0),
        BackgroundColor3 = Color3.fromRGB(35, 35, 35),
        BorderSizePixel = 0
    }, box)

    local hpBar = new("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(50, 255, 80),
        BorderSizePixel = 0
    }, hpBG)

    visuals[p] = {
        Character = char,
        Humanoid = hum,
        Root = root,
        Highlight = hl,
        Billboard = bb,
        Box = box,
        Name = name,
        HPBackground = hpBG,
        HPBar = hpBar
    }
end

local function setupPlayer(p)
    if p == LP then return end

    connect(p.CharacterAdded, function(char)
        task.defer(function()
            local hum = char:WaitForChild("Humanoid", 10)
            local root = char:WaitForChild("HumanoidRootPart", 10)

            if running and hum and root then
                createVisual(p)
            end
        end)
    end)

    if p.Character then
        createVisual(p)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    setupPlayer(p)
end

connect(Players.PlayerAdded, setupPlayer)
connect(Players.PlayerRemoving, removeVisual)

-- MAIN RENDER
RS:BindToRenderStep(
    renderName,
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not running then return end

        local camera = WS.CurrentCamera
        if not camera then return end

        local center = camera.ViewportSize / 2
        circle.Position = UDim2.fromOffset(center.X, center.Y)
        circle.Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2)
        circle.Visible = S.FOVVisible

        -- ESP
        for p, v in pairs(visuals) do
            local alive = v.Character.Parent ~= nil
                and v.Root.Parent ~= nil
                and v.Humanoid.Health > 0

            local distance = alive and (
                camera.CFrame.Position - v.Root.Position
            ).Magnitude or math.huge

            local show = S.ESP and alive
                and distance <= S.ESPDistance

            v.Billboard.Enabled = show
            v.Highlight.Enabled = show and S.Highlight
            v.Box.Visible = S.Boxes
            v.Name.Visible = S.Names
            v.HPBackground.Visible = S.Health

            if show then
                local hp = math.clamp(
                    v.Humanoid.Health /
                    math.max(v.Humanoid.MaxHealth, 1),
                    0, 1
                )

                v.HPBar.Size = UDim2.fromScale(1, hp)
                v.HPBar.BackgroundColor3 = Color3.fromRGB(
                    math.floor(255 * (1 - hp)),
                    math.floor(255 * hp),
                    50
                )

                v.Name.Text = p.DisplayName
                    .. " [" .. math.ceil(v.Humanoid.Health) .. " HP]"
            end
        end

        local part, model
        local aimPosition
        local smooth

        -- Bow has priority when enabled
        if S.BowAim then
            part, model = getTarget(
                camera,
                S.BowDistance,
                "HumanoidRootPart"
            )

            if part then
                aimPosition = bowAimPosition(
                    part, model, camera
                )
                smooth = S.BowSmooth
            end

        elseif S.Aim then
            part, model = getTarget(
                camera,
                S.Distance,
                S.Part
            )

            if part then
                local root = model:FindFirstChild("HumanoidRootPart")
                local velocity = root
                    and root.AssemblyLinearVelocity
                    or Vector3.zero

                aimPosition =
                    part.Position + velocity * S.Prediction

                smooth = S.Smooth
            end
        end

        if not aimPosition then return end

        local desired = CFrame.lookAt(
            camera.CFrame.Position,
            aimPosition
        )

        local alpha = 1 - math.pow(
            1 - smooth,
            math.clamp(dt, 0, 0.1) * 60
        )

        camera.CFrame = camera.CFrame:Lerp(
            desired,
            math.clamp(alpha, 0, 1)
        )
    end
)

-- CLEANUP
_G.UnifiedAimCleanup = function()
    running = false

    pcall(function()
        RS:UnbindFromRenderStep(renderName)
    end)

    for _, c in ipairs(connections) do
        c:Disconnect()
    end

    for p in pairs(visuals) do
        removeVisual(p)
    end

    if gui then gui:Destroy() end
end

print("[UnifiedAimESP] Loaded successfully")
