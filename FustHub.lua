-- FustHub - Precision Head Lock + Reliable ESP + Bow
-- Client-side Luau. Single file for Lynx/Delta-compatible executors.
-- This estimates ballistic trajectories, not game/server hit registration.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if _G.UnifiedAimCleanup then
    pcall(_G.UnifiedAimCleanup)
    _G.UnifiedAimCleanup = nil
end
local previous = PlayerGui:FindFirstChild("UnifiedAimESP")
if previous then previous:Destroy() end

local S = {
    Aim = false, BowAim = false, ESP = true,
    TargetPlayers = true, TargetNPCs = true,
    FOVVisible = true, FOV = 160,
    Distance = 150, Smooth = 0.5, Prediction = 0,
    HeadPrecision = true, -- exact camera-to-head alignment in normal Aim mode
    Part = "Head",
    Boxes = true, Names = true, Health = true, Highlight = true,
    ESPDistance = 1500,
    ESPNPCs = true,
    ESPCloseAlert = true,
    ESPCloseRange = 60,
    ESPBoxScale = 0.95, -- fit the outline to the actual body, not a large fixed billboard
    BowDistance = 350,
    BowSpeed = 300, -- fallback studs/second; actual Fust speed is unknown
    BowGravity = Workspace.Gravity, -- fallback; a custom projectile may differ
    BowSmooth = 0.35,
    BowMaxPitch = 32, -- degrees above horizontal; prevents 'aiming at the moon'
    BowMaxCorrection = 30, -- maximum correction above direct target angle
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
local function create(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function round(obj, px)
    create("UICorner", {CornerRadius = UDim.new(0, px)}, obj)
end

local gui = create("ScreenGui", {
    Name="UnifiedAimESP", ResetOnSpawn=false, IgnoreGuiInset=true,
    DisplayOrder=100
}, PlayerGui)
-- Compact draggable menu; the UIScale shrinks all controls proportionally.
local menuWidth, menuHeight = 310, 500
local panel = create("Frame", {
    Size=UDim2.fromOffset(menuWidth, menuHeight),
    Position=UDim2.fromOffset(18, 18),
    BackgroundColor3=Color3.fromRGB(22, 25, 36),
    BorderSizePixel=0, Active=true
}, gui)
round(panel, 12)
create("UIStroke", {Color=Color3.fromRGB(65,75,105), Thickness=1}, panel)

local cam = Workspace.CurrentCamera
local screenHeight = (cam and cam.ViewportSize.Y) or 600
local maxMenuScale = math.clamp((screenHeight - 36) / menuHeight, 0.55, 0.95)
local menuScales = {
    math.min(0.90, maxMenuScale),
    math.min(0.78, maxMenuScale),
    math.min(0.65, maxMenuScale)
}
local menuSizeIndex = 2  -- starts compact
local menuScale = create("UIScale", {Scale=menuScales[menuSizeIndex]}, panel)

local header = create("TextLabel", {
    Size=UDim2.new(1, -102, 0, 44), Position=UDim2.fromOffset(10, 2),
    BackgroundTransparency=1, Text="FUSTHUB | AIM / BOW / ESP",
    TextColor3=Color3.fromRGB(240,245,255),
    TextXAlignment=Enum.TextXAlignment.Left,
    Font=Enum.Font.GothamBold, TextSize=13, Active=true
}, panel)

-- Tap the percentage button to cycle between large, compact and tiny menu sizes.
local sizeButton = create("TextButton", {
    Size=UDim2.fromOffset(42,28), Position=UDim2.new(1,-90,0,9),
    BackgroundColor3=Color3.fromRGB(48,55,75),
    Text=string.format("%d%%", math.floor(menuScale.Scale*100+0.5)),
    TextColor3=Color3.new(1,1,1), Font=Enum.Font.GothamBold, TextSize=11
}, panel)
round(sizeButton, 6)
connect(sizeButton.MouseButton1Click, function()
    menuSizeIndex = menuSizeIndex % #menuScales + 1
    menuScale.Scale = menuScales[menuSizeIndex]
    sizeButton.Text = string.format("%d%%", math.floor(menuScale.Scale*100+0.5))
end)

local minimize = create("TextButton", {
    Size=UDim2.fromOffset(32,30), Position=UDim2.new(1,-40,0,8),
    BackgroundColor3=Color3.fromRGB(48,55,75), Text="-",
    TextColor3=Color3.new(1,1,1), Font=Enum.Font.GothamBold, TextSize=20
}, panel)
round(minimize, 6)
local scroll = create("ScrollingFrame", {
    Size=UDim2.new(1,-20,1,-58), Position=UDim2.fromOffset(10,50),
    BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
    CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y
}, panel)
create("UIListLayout", {
    Padding=UDim.new(0,7), SortOrder=Enum.SortOrder.LayoutOrder
}, scroll)

local collapsed = false
connect(minimize.MouseButton1Click, function()
    collapsed = not collapsed
    scroll.Visible = not collapsed
    panel.Size = collapsed and UDim2.fromOffset(165,46)
        or UDim2.fromOffset(menuWidth,menuHeight)
    header.Text = collapsed and "FUSTHUB" or "FUSTHUB | AIM / BOW / ESP"
    header.Size = collapsed and UDim2.new(1,-45,0,44)
        or UDim2.new(1,-102,0,44)
    sizeButton.Visible = not collapsed
    minimize.Text = collapsed and "+" or "-"
end)

local function button(label, callback)
    local b = create("TextButton", {
        Size=UDim2.new(1,-6,0,35),
        BackgroundColor3=Color3.fromRGB(43,49,68), Text=label,
        TextColor3=Color3.new(1,1,1), TextSize=13,
        Font=Enum.Font.GothamMedium
    }, scroll)
    round(b, 7)
    if callback then
        connect(b.MouseButton1Click, function() callback(b) end)
    end
    return b
end

local refreshBowUI = function() end
local function toggle(label, key)
    local b
    local function update()
        b.Text = label .. ": " .. (S[key] and "ON" or "OFF")
        b.BackgroundColor3 = S[key]
            and Color3.fromRGB(34,125,100)
            or Color3.fromRGB(43,49,68)
    end
    b = button("", function()
        S[key] = not S[key]
        update()
        if key == "BowAim" then refreshBowUI() end
    end)
    update()
    return update
end

local function adjust(label, key, minimum, maximum, step, format)
    local row = create("Frame", {
        Size=UDim2.new(1,-6,0,38), BackgroundTransparency=1
    }, scroll)
    local text = create("TextLabel", {
        Size=UDim2.new(0.66,0,1,0), BackgroundTransparency=1,
        TextColor3=Color3.fromRGB(225,230,245),
        TextXAlignment=Enum.TextXAlignment.Left,
        Font=Enum.Font.Gotham, TextSize=12
    }, row)
    local function update()
        text.Text = label .. ": " .. string.format(format or "%.1f", S[key])
    end
    for i, symbol in ipairs({"-", "+"}) do
        local minus = (i == 1)
        local b = create("TextButton", {
            Size=UDim2.fromOffset(38,30),
            Position=UDim2.new(minus and 0.68 or 0.84,0,0,4),
            BackgroundColor3=Color3.fromRGB(55,64,89), Text=symbol,
            TextColor3=Color3.new(1,1,1), TextSize=18,
            Font=Enum.Font.GothamBold
        }, row)
        round(b, 6)
        connect(b.MouseButton1Click, function()
            local delta = minus and -step or step
            S[key] = math.clamp(S[key] + delta, minimum, maximum)
            update()
        end)
    end
    update()
end

-- AIM controls
toggle("Aim Assist", "Aim")
button("Target: HEAD", function(b)
    S.Part = (S.Part == "Head") and "HumanoidRootPart" or "Head"
    b.Text = (S.Part == "Head") and "Target: HEAD" or "Target: BODY"
end)
toggle("FOV Circle", "FOVVisible")
adjust("FOV", "FOV", 30, 500, 10, "%.0f")
adjust("Distance", "Distance", 20, 500, 10, "%.0f")
adjust("Smooth", "Smooth", 0.05, 1, 0.05, "%.2f")
adjust("Prediction", "Prediction", 0, 0.5, 0.025, "%.3f")
toggle("Precise Head Lock", "HeadPrecision")
toggle("Target Players", "TargetPlayers")
toggle("Target NPCs", "TargetNPCs")

-- BOW controls
local updateBowToggle = toggle("Bow Aimbot", "BowAim")
adjust("Bow Range (studs)", "BowDistance", 50, 1000, 25, "%.0f")
adjust("Speed fallback", "BowSpeed", 40, 800, 10, "%.0f")
adjust("Gravity fallback", "BowGravity", 10, 400, 10, "%.0f")
adjust("Bow Smooth", "BowSmooth", 0.05, 1, 0.05, "%.2f")
adjust("Max bow pitch", "BowMaxPitch", 10, 45, 2, "%.0f")
adjust("Max correction", "BowMaxCorrection", 5, 35, 2, "%.0f")
local status = create("TextLabel", {
    Size=UDim2.new(1,-6,0,42), BackgroundTransparency=1,
    Text="Bow: waiting for target", TextWrapped=true,
    TextColor3=Color3.fromRGB(190,200,225),
    Font=Enum.Font.Gotham, TextSize=11
}, scroll)
local awaitingBind = false
local bindButton = button("Bow Keybind: B", function(b)
    awaitingBind = true
    b.Text = "Press a keyboard key..."
end)

-- ESP controls
toggle("Player ESP", "ESP")
toggle("ESP Boxes", "Boxes")
toggle("ESP Names", "Names")
toggle("ESP Health", "Health")
toggle("ESP Highlight", "Highlight")
toggle("ESP NPCs", "ESPNPCs")
toggle("Close Threat Alert", "ESPCloseAlert")
adjust("Close Alert Range", "ESPCloseRange", 15, 120, 15, "%.0f")
adjust("ESP Box Fit", "ESPBoxScale", 0.75, 1.10, 0.05, "%.2f")
adjust("ESP Distance", "ESPDistance", 50, 1500, 50, "%.0f")

-- Draggable panel
local draggingPanel, panelInput, panelStart, panelPos = false, nil, nil, nil
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingPanel = true
        panelInput = input
        panelStart = input.Position
        panelPos = panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if draggingPanel and panelStart and
        (input == panelInput or (panelInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local d = input.Position - panelStart
        panel.Position = UDim2.new(panelPos.X.Scale,panelPos.X.Offset+d.X,
            panelPos.Y.Scale,panelPos.Y.Offset+d.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input == panelInput then draggingPanel = false; panelInput = nil end
end)

-- Draggable touch toggle
local mobileButton = create("TextButton", {
    Name="BowMobileToggle", Size=UDim2.fromOffset(76,76),
    Position=UDim2.new(1,-105,0.65,0),
    BackgroundColor3=Color3.fromRGB(45,50,70),
    Text="BOW\nOFF", TextColor3=Color3.new(1,1,1),
    TextSize=16, Font=Enum.Font.GothamBold, Active=true, ZIndex=20
}, gui)
round(mobileButton, 18)
refreshBowUI = function()
    updateBowToggle()
    mobileButton.Text = S.BowAim and "BOW\nON" or "BOW\nOFF"
    mobileButton.BackgroundColor3 = S.BowAim
        and Color3.fromRGB(30,145,100)
        or Color3.fromRGB(45,50,70)
end
local function switchBow()
    S.BowAim = not S.BowAim
    refreshBowUI()
end
connect(UserInputService.InputBegan, function(input, processed)
    if awaitingBind then
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            S.BowKey = input.KeyCode
            bindButton.Text = "Bow Keybind: " .. input.KeyCode.Name
            awaitingBind = false
        end
        return
    end
    if not processed and input.KeyCode == S.BowKey then switchBow() end
end)
local bowDrag, bowInput, bowStart, bowPos, bowMoved = false,nil,nil,nil,false
connect(mobileButton.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        bowDrag = true
        bowInput = input
        bowStart = input.Position
        bowPos = mobileButton.Position
        bowMoved = false
    end
end)
connect(UserInputService.InputChanged, function(input)
    if bowDrag and bowStart and
        (input == bowInput or (bowInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local d = input.Position - bowStart
        if d.Magnitude > 8 then bowMoved = true end
        if bowMoved then
            mobileButton.Position = UDim2.new(
                bowPos.X.Scale,bowPos.X.Offset+d.X,
                bowPos.Y.Scale,bowPos.Y.Offset+d.Y)
        end
    end
end)
connect(UserInputService.InputEnded, function(input)
    if bowDrag and input == bowInput then
        bowDrag = false
        bowInput = nil
        if not bowMoved then switchBow() end
    end
end)
refreshBowUI()

-- FOV ring
local circle = create("Frame", {
    AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundTransparency=1, BorderSizePixel=0
}, gui)
create("UICorner",{CornerRadius=UDim.new(1,0)},circle)
create("UIStroke",{Color=Color3.fromRGB(75,170,255),Thickness=2},circle)

-- Read speed/gravity from an equipped weapon if the game exposes them.
-- No generic script can discover arbitrary server-only projectile data.
local function numericToolValue(tool, names)
    if not tool then return nil end
    for _, name in ipairs(names) do
        local a = tool:GetAttribute(name)
        if type(a) == "number" and a > 0 then return a end
        local child = tool:FindFirstChild(name, true)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue"))
            and child.Value > 0 then
            return child.Value
        end
    end
    return nil
end
local function bowStats()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local measuredSpeed = numericToolValue(tool, {
        "ArrowSpeed","ProjectileSpeed","LaunchSpeed","MuzzleVelocity","InitialSpeed"
    })
    local measuredGravity = numericToolValue(tool, {
        "ArrowGravity","ProjectileGravity","GravityAcceleration"
    })
    local gravityScale = numericToolValue(tool, {
        "GravityScale","ProjectileGravityScale"
    })
    local inherited = numericToolValue(tool, {
        "VelocityInheritance","ProjectileVelocityInheritance"
    })
    local speed = math.clamp(measuredSpeed or S.BowSpeed, 10, 1200)
    local grav = math.clamp(measuredGravity or
        (gravityScale and Workspace.Gravity * gravityScale or S.BowGravity), 0.1, 800)
    local inheritance = math.clamp(inherited or 0, 0, 1)
    return speed, grav, inheritance, measuredSpeed ~= nil
end

-- Exact lower-angle solution for a constant-speed, constant-gravity projectile.
-- If discriminant is negative, the target is physically unreachable.
local function solveLowArc(origin, target, speed, gravity)
    local delta = target - origin
    local horizontal = Vector3.new(delta.X,0,delta.Z)
    local x = horizontal.Magnitude
    if x < 0.5 or speed <= 0 then return nil end
    local y = delta.Y
    local v2 = speed * speed
    local disc = v2*v2 - gravity*(gravity*x*x + 2*y*v2)
    if disc < 0 then return nil end

    local theta = math.atan((v2 - math.sqrt(disc))/(gravity*x))
    local pitch = math.deg(theta)
    local directPitch = math.deg(math.atan(y/x))
    if pitch > S.BowMaxPitch or
        (pitch - directPitch) > S.BowMaxCorrection then
        return nil
    end

    local cosTheta = math.cos(theta)
    if cosTheta <= 0.05 then return nil end
    local t = x / (speed * cosTheta)
    if t > 3 then return nil end
    local aimPoint = origin + horizontal + Vector3.new(0,x*math.tan(theta),0)
    return aimPoint, t, pitch
end

local function solveMovingBow(targetPart, model, camera, speed, gravity, inheritance)
    local origin = camera.CFrame.Position
    local root = model:FindFirstChild("HumanoidRootPart")
    local targetVelocity = root and root.AssemblyLinearVelocity or Vector3.zero
    if targetVelocity.Magnitude > 120 then
        targetVelocity = targetVelocity.Unit * 120
    end
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    local myVelocity = myRoot and myRoot.AssemblyLinearVelocity or Vector3.zero
    if myVelocity.Magnitude > 120 then myVelocity = myVelocity.Unit * 120 end
    local relativeVelocity = targetVelocity - myVelocity * inheritance
    local base = targetPart.Position
    local travel = (base - origin).Magnitude / speed
    local aimPoint, pitch

    for _ = 1, 5 do
        local predicted = base + relativeVelocity * travel
        local nextAim, nextTime, nextPitch = solveLowArc(
            origin, predicted, speed, gravity)
        if not nextAim then return nil end
        aimPoint, pitch = nextAim, nextPitch
        travel = nextTime
    end
    return aimPoint, travel, pitch
end

local function canSee(model, position, camera)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LocalPlayer.Character
        and {LocalPlayer.Character} or {}
    params.IgnoreWater = true
    local origin = camera.CFrame.Position
    local hit = Workspace:Raycast(origin,position-origin,params)
    return hit and hit.Instance:IsDescendantOf(model) or false
end

-- NPC registry: discover humanoid instances, including rigs inside nested containers.
-- Player characters are handled by Players:GetPlayers() separately.
local npcModels, nextNpcScan = {}, 0
local function playerForAncestor(model)
    local current = model
    while current and current ~= Workspace do
        if current:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(current)
            if player then return player end
        end
        current = current.Parent
    end
    return nil
end

local function modelForHumanoid(humanoid)
    local firstModel = nil
    local current = humanoid.Parent
    while current and current ~= Workspace do
        if current:IsA("Model") then
            firstModel = firstModel or current
            if current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChild("UpperTorso")
                or current:FindFirstChild("Torso")
                or current:FindFirstChild("Head")
                or current.PrimaryPart then
                return current
            end
        end
        current = current.Parent
    end
    return firstModel
end

local function getNPCs()
    if os.clock() >= nextNpcScan then
        nextNpcScan = os.clock() + 0.85
        npcModels = {}
        local seen = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Health > 0 then
                local model = modelForHumanoid(obj)
                if model and not seen[model]
                    and not playerForAncestor(model) then
                    seen[model] = true
                    table.insert(npcModels, model)
                end
            end
        end
    end
    return npcModels
end
local function eachTarget(callback)
    if S.TargetPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then callback(p.Character) end
        end
    end
    if S.TargetNPCs then
        for _, model in ipairs(getNPCs()) do callback(model) end
    end
end

local function selectAimTarget(camera, maxDistance, partName)
    local center = camera.ViewportSize/2
    local bestPart, bestModel
    local best = S.FOV
    eachTarget(function(model)
        local hum = model:FindFirstChildOfClass("Humanoid")
        local part = model:FindFirstChild(partName)
        if hum and hum.Health > 0 and part and part:IsA("BasePart") then
            local d = (part.Position-camera.CFrame.Position).Magnitude
            if d <= maxDistance then
                local p, visible = camera:WorldToViewportPoint(part.Position)
                if visible then
                    local score = (Vector2.new(p.X,p.Y)-center).Magnitude
                    if score < best and canSee(model,part.Position,camera) then
                        bestPart,bestModel,best=part,model,score
                    end
                end
            end
        end
    end)
    return bestPart,bestModel
end

local function selectBowTarget(camera, speed, gravity, inheritance)
    local center = camera.ViewportSize/2
    local best, bestPart, bestModel, bestAim, bestTime, bestPitch
    best = S.FOV
    eachTarget(function(model)
        local hum = model:FindFirstChildOfClass("Humanoid")
        local part = model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("HumanoidRootPart")
        if hum and hum.Health > 0 and part and part:IsA("BasePart") then
            local distance = (part.Position-camera.CFrame.Position).Magnitude
            if distance <= S.BowDistance and canSee(model,part.Position,camera) then
                local aim, t, pitch = solveMovingBow(part,model,camera,
                    speed,gravity,inheritance)
                if aim then
                    local screenBody, bodyVisible = camera:WorldToViewportPoint(part.Position)
                    local screenAim, aimVisible = camera:WorldToViewportPoint(aim)
                    local score = math.huge
                    if bodyVisible then
                        score = math.min(score,
                            (Vector2.new(screenBody.X,screenBody.Y)-center).Magnitude)
                    end
                    if aimVisible then
                        score = math.min(score,
                            (Vector2.new(screenAim.X,screenAim.Y)-center).Magnitude)
                    end
                    if score < best then
                        best,bestPart,bestModel,bestAim,bestTime,bestPitch =
                            score,part,model,aim,t,pitch
                    end
                end
            end
        end
    end)
    return bestPart,bestModel,bestAim,bestTime,bestPitch
end

-- Fitted on-screen ESP (no fixed-size BillboardGui).
-- Tracks player characters even when Humanoid / Root loads after CharacterAdded.
-- Also shows nearby Humanoid NPCs if "ESP NPCs" is enabled.
local BODY_PARTS = {
    Head = true, HumanoidRootPart = true,
    Torso = true, UpperTorso = true, LowerTorso = true,
    ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local function getESPRoot(model)
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("Head")
        or model.PrimaryPart
        or model:FindFirstChild("HumanoidRootPart", true)
        or model:FindFirstChild("UpperTorso", true)
        or model:FindFirstChild("Torso", true)
        or model:FindFirstChild("Head", true)
    if root and root:IsA("BasePart") then return root end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end
    return nil
end

local function removeESP(model)
    local visual = visuals[model]
    if not visual then return end
    visuals[model] = nil
    for _, name in ipairs({"Highlight", "Box", "Name", "HPBackground"}) do
        if visual[name] then pcall(function() visual[name]:Destroy() end) end
    end
end

local function ensureESP(model, player)
    if not running or not model or not model:IsA("Model")
        or model == LocalPlayer.Character
        or not model:IsDescendantOf(Workspace) then return end

    local root = getESPRoot(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildWhichIsA("Humanoid", true)
    if not root or (not player and not humanoid) then return end
    if humanoid and humanoid.Health <= 0 then return end

    local old = visuals[model]
    if old and old.Root == root and old.Humanoid == humanoid then
        if player then old.Player = player end
        return
    end
    removeESP(model)

    -- Highlight is a 3D adornment, separate from the 2D fitted outline.
    local hl = create("Highlight", {
        Name = "FustHub_ESP_Highlight", Adornee = model,
        FillColor = Color3.fromRGB(255,70,80),
        OutlineColor = Color3.fromRGB(255,255,255),
        FillTransparency = 0.8, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = false
    }, Workspace)

    local box = create("Frame", {
        Name = "FustHub_ESP_Box", BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromOffset(0,0),
        Visible = false, ZIndex = 10
    }, gui)
    create("UIStroke", {
        Color = Color3.fromRGB(255,85,95), Thickness = 1.5
    }, box)

    local name = create("TextLabel", {
        Name = "FustHub_ESP_Name", BackgroundTransparency = 1,
        Text = (player and player.DisplayName or model.Name),
        TextColor3 = Color3.new(1,1,1),
        TextStrokeTransparency = 0.3,
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromOffset(120,18), Visible = false,
        ZIndex = 11
    }, gui)

    local hpBg = create("Frame", {
        Name = "FustHub_ESP_HP", BackgroundColor3 = Color3.fromRGB(30,30,30),
        BorderSizePixel = 0, Size = UDim2.fromOffset(4,0),
        Visible = false, ZIndex = 11
    }, gui)
    local hpFill = create("Frame", {
        AnchorPoint = Vector2.new(0,1),
        Position = UDim2.fromScale(0,1),
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.fromRGB(70,255,70),
        BorderSizePixel = 0, ZIndex = 12
    }, hpBg)

    visuals[model] = {
        Character = model, Root = root, Humanoid = humanoid,
        Player = player, Highlight = hl, Box = box, Name = name,
        HPBackground = hpBg, HPBar = hpFill,
        NextBoxUpdate = 0,
        OnScreen = false
    }
end

-- A world-space model box may include giant equipped weapons/accessories.
-- Instead measure only actual R6/R15 body parts and project their corners.
-- This makes the outline shrink naturally with distance and fit the player.
local function fittedBox(model, root, camera)
    local xMin, yMin = math.huge, math.huge
    local xMax, yMax = -math.huge, -math.huge
    local bodyCount, points = 0, 0

    local function addPart(cframe, size)
        local half = size * 0.5
        for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
                for sz = -1, 1, 2 do
                    local world = cframe:PointToWorldSpace(Vector3.new(
                        half.X*sx, half.Y*sy, half.Z*sz))
                    local p = camera:WorldToViewportPoint(world)
                    if p.Z > 0.15 then
                        points = points + 1
                        xMin = math.min(xMin,p.X)
                        yMin = math.min(yMin,p.Y)
                        xMax = math.max(xMax,p.X)
                        yMax = math.max(yMax,p.Y)
                    end
                end
            end
        end
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and BODY_PARTS[child.Name] then
            addPart(child.CFrame, child.Size)
            bodyCount = bodyCount + 1
        end
    end

    -- Nonstandard character rigs: estimate human proportions around root.
    if bodyCount < 2 then
        xMin,yMin,xMax,yMax,points = math.huge,math.huge,-math.huge,-math.huge,0
        local head = model:FindFirstChild("Head")
        local height = 5.5
        if head and head:IsA("BasePart") then
            height = math.clamp(math.abs(head.Position.Y-root.Position.Y)*2.4+2,4,10)
        end
        addPart(CFrame.new(root.Position + Vector3.new(0,0.25,0)),
            Vector3.new(2.4,height,1.6))
    end

    local view = camera.ViewportSize
    if points == 0 then
        -- If the camera is inside an enemy rig, its body corners can all
        -- be behind the near clipping plane. Fall back to a root projection.
        local p = camera:WorldToViewportPoint(root.Position)
        if p.Z <= 0.1 then return nil end
        local d = math.max((root.Position - camera.CFrame.Position).Magnitude,1)
        local approximateHeight = math.clamp(view.Y * 5.5 / d, 24, view.Y * 2)
        local approximateWidth = approximateHeight * 0.45
        xMin, xMax = p.X - approximateWidth/2, p.X + approximateWidth/2
        yMin, yMax = p.Y - approximateHeight/2, p.Y + approximateHeight/2
    end

    -- Clamp huge near-camera projections instead of rejecting them entirely.
    -- This is important when an enemy is just a few studs away.
    local left = math.clamp(xMin, 0, view.X)
    local right = math.clamp(xMax, 0, view.X)
    local top = math.clamp(yMin, 0, view.Y)
    local bottom = math.clamp(yMax, 0, view.Y)
    if right - left < 2 or bottom - top < 2 then return nil end

    local scale = math.clamp(S.ESPBoxScale, 0.75, 1.1)
    local bw, bh = (right-left)*scale, (bottom-top)*scale
    local centerX, centerY = (left+right)*0.5, (top+bottom)*0.5
    return centerX-bw*0.5, centerY-bh*0.5, bw, bh
end

local function hideESP(v)
    v.Box.Visible = false
    v.Name.Visible = false
    v.HPBackground.Visible = false
    v.Highlight.Enabled = false
    v.OnScreen = false
end

local function renderESP(v, camera, now)
    local model = v.Character
    local root = v.Root
    if not model:IsDescendantOf(Workspace) or not root:IsDescendantOf(model)
        or (v.Humanoid and v.Humanoid.Health <= 0)
        or (v.Player and v.Player.Character ~= model) then
        hideESP(v)
        return
    end

    local isNPC = v.Player == nil
    local distance = (camera.CFrame.Position-root.Position).Magnitude
    if not S.ESP or (isNPC and not S.ESPNPCs)
        or distance > S.ESPDistance then
        hideESP(v)
        return
    end

    v.Highlight.Enabled = S.Highlight

    -- Update near-character boxes 20 times/s; distant boxes 10 times/s.
    if now < v.NextBoxUpdate then return end
    v.NextBoxUpdate = now + (distance > 400 and 0.1 or 0.05)

    local x,y,w,h = fittedBox(model,root,camera)
    if not x then
        v.Box.Visible = false
        v.Name.Visible = false
        v.HPBackground.Visible = false
        v.OnScreen = false
        return
    end
    v.OnScreen = true
    v.Box.Position = UDim2.fromOffset(math.floor(x),math.floor(y))
    v.Box.Size = UDim2.fromOffset(math.ceil(w),math.ceil(h))
    v.Box.Visible = S.Boxes

    local maxHealth = v.Humanoid and math.max(v.Humanoid.MaxHealth,1) or 100
    local health = v.Humanoid and v.Humanoid.Health or maxHealth
    local hpRatio = math.clamp(health/maxHealth,0,1)

    v.Name.Visible = S.Names and h > 12
    if v.Name.Visible then
        local labelW = math.clamp(w + 30, 70, 155)
        v.Name.Size = UDim2.fromOffset(labelW,18)
        v.Name.Position = UDim2.fromOffset(
            math.floor(x+w/2-labelW/2),math.floor(y-20))
        local displayName = v.Player and v.Player.DisplayName or model.Name
        v.Name.Text = displayName .. (v.Humanoid and
            " [" .. math.ceil(health) .. " HP]" or "")
    end

    v.HPBackground.Visible = S.Health and h > 8
    if v.HPBackground.Visible then
        v.HPBackground.Position = UDim2.fromOffset(
            math.floor(x-8),math.floor(y))
        v.HPBackground.Size = UDim2.fromOffset(4,math.ceil(h))
        v.HPBar.Size = UDim2.fromScale(1,hpRatio)
        v.HPBar.BackgroundColor3 = Color3.fromRGB(
            math.floor(255*(1-hpRatio)),math.floor(255*hpRatio),40)
    end
end

local function setupPlayer(player)
    if player == LocalPlayer then return end
    connect(player.CharacterAdded, function(model)
        -- CharacterAdded fires before Humanoid/parts may replicate.
        task.defer(function()
            if running then ensureESP(model,player) end
        end)
    end)
    connect(player.CharacterRemoving, function(model)
        removeESP(model)
    end)
    if player.Character then ensureESP(player.Character,player) end
end

for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
connect(Players.PlayerAdded,setupPlayer)
connect(Players.PlayerRemoving,function(player)
    for model,v in pairs(visuals) do
        if v.Player == player then removeESP(model) end
    end
end)

-- Very close enemies may have their entire rig outside the camera view.
-- Spatial discovery provides a second detection path for those humanoids.
local nearbyParams = OverlapParams.new()
nearbyParams.FilterType = Enum.RaycastFilterType.Exclude
nearbyParams.MaxParts = 0
local nextNearbyScan = 0
local function refreshNearby(now)
    if not S.ESP or now < nextNearbyScan then return end
    nextNearbyScan = now + 0.25
    local character = LocalPlayer.Character
    local myRoot = character and (character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Head"))
    if not myRoot then return end
    nearbyParams.FilterDescendantsInstances = {character}
    local success, nearbyParts = pcall(function()
        return Workspace:GetPartBoundsInRadius(
            myRoot.Position, math.max(S.ESPCloseRange, 60), nearbyParams)
    end)
    if not success then return end

    local seen = {}
    for _, part in ipairs(nearbyParts) do
        local ancestor = part.Parent
        while ancestor and ancestor ~= Workspace do
            if ancestor:IsA("Model") then
                local hum = ancestor:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if not seen[ancestor] and ancestor ~= character then
                        seen[ancestor] = true
                        local owner = playerForAncestor(ancestor)
                        if owner ~= LocalPlayer and
                            (owner ~= nil or S.ESPNPCs) then
                            ensureESP(ancestor, owner)
                        end
                    end
                    break
                end
            end
            ancestor = ancestor.Parent
        end
    end
end

local nextESPPlayerScan, nextESPNPCScan = 0, 0
local function refreshESP(now)
    if not S.ESP then return end

    if now >= nextESPPlayerScan then
        nextESPPlayerScan = now + 0.20
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                ensureESP(player.Character, player)
            end
        end
    end

    if S.ESPNPCs and now >= nextESPNPCScan then
        nextESPNPCScan = now + 0.85
        for _, model in ipairs(getNPCs()) do
            if model:IsDescendantOf(Workspace)
                and not playerForAncestor(model) then
                ensureESP(model, nil)
            end
        end
    end

    refreshNearby(now)

    for model, v in pairs(visuals) do
        if not model:IsDescendantOf(Workspace)
            or (v.Player and v.Player.Character ~= model) then
            removeESP(model)
        end
    end
end

-- Listen for humanoids *and* late-arriving body parts. If a Humanoid
-- replicates before its root, the root event gives it another chance.
connect(Workspace.DescendantAdded, function(obj)
    if not running or not S.ESP then return end
    if not (obj:IsA("Humanoid") or
        (obj:IsA("BasePart") and
        (obj.Name == "HumanoidRootPart" or obj.Name == "Head"
        or obj.Name == "UpperTorso" or obj.Name == "Torso"))) then
        return
    end
    task.defer(function()
        if not running or not obj:IsDescendantOf(Workspace) then return end
        local current = obj.Parent
        while current and current ~= Workspace do
            if current:IsA("Model") then
                local owner = playerForAncestor(current)
                if owner == LocalPlayer then return end
                local hum = current:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if owner or S.ESPNPCs then
                        ensureESP(current, owner)
                    end
                    return
                end
            end
            current = current.Parent
        end
    end)
end)

-- This warning remains visible even when a nearby enemy is behind the camera
-- or too close for a valid projected bounding box.
local nearAlert = create("TextLabel", {
    Name = "FustHubCloseThreat", AnchorPoint = Vector2.new(0.5,0),
    Position = UDim2.new(0.5,0,0,65), Size = UDim2.fromOffset(350,39),
    BackgroundColor3 = Color3.fromRGB(85,25,30),
    BackgroundTransparency = 0.17, BorderSizePixel = 0,
    TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold,
    TextSize = 12, TextWrapped = true, Visible = false, ZIndex = 30
}, gui)
round(nearAlert, 7)

local espStatus = create("TextLabel", {
    Name = "ESPStatus", Size = UDim2.new(1,-6,0,30),
    BackgroundTransparency = 1, Text = "ESP scan: initializing...",
    TextWrapped = true, Font = Enum.Font.Gotham,
    TextSize = 10, TextColor3 = Color3.fromRGB(180,205,230)
}, scroll)

local nextThreatUpdate = 0
local function updateThreats(now, camera)
    if now < nextThreatUpdate then return end
    nextThreatUpdate = now + 0.25
    local myCharacter = LocalPlayer.Character
    local myRoot = myCharacter and (myCharacter:FindFirstChild("HumanoidRootPart")
        or myCharacter:FindFirstChild("Head"))
    local threats = {}
    local playerCount, npcCount = 0, 0
    if S.ESP then
        for model, v in pairs(visuals) do
            if model:IsDescendantOf(Workspace) and v.Root.Parent
                and (not v.Humanoid or v.Humanoid.Health > 0) then
                if v.Player then playerCount = playerCount + 1
                else npcCount = npcCount + 1 end
                if myRoot then
                    local d = (v.Root.Position - myRoot.Position).Magnitude
                    if d <= S.ESPCloseRange then
                        local name = v.Player and v.Player.DisplayName or model.Name
                        table.insert(threats, {distance=d,name=name})
                    end
                end
            end
        end
    end
    table.sort(threats, function(a,b) return a.distance < b.distance end)
    espStatus.Text = string.format("ESP tracked: %d players | %d NPCs | %d close",
        playerCount, npcCount, #threats)
    nearAlert.Visible = S.ESP and S.ESPCloseAlert and #threats > 0
    if nearAlert.Visible then
        local entries = {}
        for i = 1, math.min(#threats, 3) do
            local t = threats[i]
            table.insert(entries, string.format("%s (%.0f studs)", t.name, t.distance))
        end
        nearAlert.Text = "NEARBY: " .. table.concat(entries, " | ")
            .. (#threats > 3 and " | +more" or "")
    end
end

local lastStatusUpdate = 0
local lastESPWarn = 0
RunService:BindToRenderStep(renderName,Enum.RenderPriority.Camera.Value+1,function(dt)
    if not running then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local center = camera.ViewportSize/2
    circle.Position=UDim2.fromOffset(center.X,center.Y)
    circle.Size=UDim2.fromOffset(S.FOV*2,S.FOV*2)
    circle.Visible=S.FOVVisible

    local now = os.clock()
    local refreshOkay, refreshError = pcall(refreshESP, now)
    if not refreshOkay then
        if now - lastESPWarn > 2 then
            lastESPWarn = now
            warn("[FustHub ESP] Detection error:", refreshError)
        end
    end
    for _, visual in pairs(visuals) do
        -- One bad/nonstandard rig must never break ESP for every other rig.
        local ok, err = pcall(renderESP, visual, camera, now)
        if not ok then
            hideESP(visual)
            if not visual.Warned then
                visual.Warned = true
                warn("[FustHub ESP] Rig render error:", err)
            end
        end
    end
    updateThreats(now, camera)

    local aimPosition, smooth
    if S.BowAim then
        local speed, gravity, inheritance, fromTool = bowStats()
        local part, model, aim, travel, pitch = selectBowTarget(
            camera,speed,gravity,inheritance)
        if aim then
            aimPosition=aim
            smooth=S.BowSmooth
        end
        if os.clock() - lastStatusUpdate > 0.25 then
            lastStatusUpdate = os.clock()
            status.Text = string.format(
                "Bow: %s | v=%.0f g=%.0f %s",
                aim and string.format("%.1fs / %.0f deg",travel,pitch) or "no reachable target",
                speed,gravity,fromTool and "(tool)" or "(fallback)")
        end
    elseif S.Aim then
        -- Normal Aim and Bow Aim are intentionally independent.
        -- Head mode aims at the ACTUAL Head part center.
        -- Never apply the previous pixel-down correction or world-space
        -- lead: both moved the crosshair away from the visible head.
        local part, model = selectAimTarget(camera, S.Distance, S.Part)
        if part then
            if S.Part == "Head" then
                aimPosition = part.Position
                -- Instant alignment prevents smoothing lag at long range.
                smooth = S.HeadPrecision and 1 or S.Smooth
            else
                -- Optional body mode retains horizontal movement prediction.
                local root = model:FindFirstChild("HumanoidRootPart")
                local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
                local horizontalLead = Vector3.new(velocity.X, 0, velocity.Z)
                    * math.clamp(S.Prediction, 0, 0.5)
                aimPosition = part.Position + horizontalLead
                smooth = S.Smooth
            end
        end
    end

    if not aimPosition then return end
    local desired=CFrame.lookAt(camera.CFrame.Position,aimPosition)
    local alpha=1-math.pow(1-math.clamp(smooth,0.01,1), math.clamp(dt,0,0.1)*60)
    camera.CFrame=camera.CFrame:Lerp(desired,math.clamp(alpha,0,1))
end)

_G.UnifiedAimCleanup=function()
    running=false
    pcall(function() RunService:UnbindFromRenderStep(renderName) end)
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for model in pairs(visuals) do removeESP(model) end
    if gui then gui:Destroy() end
end
print("[FustHub] Precision head lock + Reliable ESP + Bow loaded")
