-- FustHub - Bow Ballistics Fix
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
    Aim = false, BowAim = false, ESP = false,
    TargetPlayers = true, TargetNPCs = true,
    FOVVisible = true, FOV = 160,
    Distance = 150, Smooth = 0.5, Prediction = 0,
    Part = "Head",
    Boxes = true, Names = true, Health = true, Highlight = true,
    ESPDistance = 1500,
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

-- Collect NPCs periodically so we don't scan the entire Workspace every frame.
local npcModels, nextNpcScan = {}, 0
local function getNPCs()
    if os.clock() >= nextNpcScan then
        nextNpcScan = os.clock() + 0.8
        npcModels = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid")
                and not Players:GetPlayerFromCharacter(obj) then
                table.insert(npcModels,obj)
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

-- ESP for players
local function removeESP(player)
    local v = visuals[player]
    if not v then return end
    if v.Highlight then v.Highlight:Destroy() end
    if v.Billboard then v.Billboard:Destroy() end
    visuals[player] = nil
end
local function createESP(player)
    if player == LocalPlayer then return end
    removeESP(player)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end
    local highlight = create("Highlight", {
        Adornee=char, FillColor=Color3.fromRGB(255,70,80),
        OutlineColor=Color3.new(1,1,1), FillTransparency=0.75,
        OutlineTransparency=0,
        DepthMode=Enum.HighlightDepthMode.AlwaysOnTop, Enabled=false
    }, gui)
    local billboard = create("BillboardGui", {
        Adornee=root, Size=UDim2.fromOffset(120,190),
        StudsOffset=Vector3.new(0,0.4,0),
        AlwaysOnTop=true, Enabled=false
    }, gui)
    local outline = create("Frame", {
        Size=UDim2.new(0.82,0,0.82,0),
        Position=UDim2.new(0.09,0,0.09,0),
        BackgroundTransparency=1
    }, billboard)
    create("UIStroke",{Color=Color3.fromRGB(255,80,90),Thickness=2},outline)
    local name = create("TextLabel", {
        Size=UDim2.new(1,30,0,24), Position=UDim2.fromOffset(-15,-26),
        BackgroundTransparency=1, Text=player.DisplayName,
        TextColor3=Color3.new(1,1,1), TextStrokeTransparency=0.25,
        Font=Enum.Font.GothamBold, TextSize=12
    }, outline)
    local hpBG = create("Frame", {
        Size=UDim2.fromOffset(6,155), Position=UDim2.fromOffset(-12,0),
        BackgroundColor3=Color3.fromRGB(35,35,35), BorderSizePixel=0
    }, outline)
    local hpBar = create("Frame", {
        AnchorPoint=Vector2.new(0,1), Position=UDim2.fromScale(0,1),
        Size=UDim2.fromScale(1,1),
        BackgroundColor3=Color3.fromRGB(50,255,80), BorderSizePixel=0
    }, hpBG)
    visuals[player] = {
        Character=char, Root=root, Humanoid=hum,
        Highlight=highlight, Billboard=billboard, Box=outline,
        Name=name, HPBackground=hpBG, HPBar=hpBar
    }
end
local function setupPlayer(player)
    if player == LocalPlayer then return end
    connect(player.CharacterAdded,function(char)
        task.defer(function()
            local hum = char:WaitForChild("Humanoid",10)
            local root = char:WaitForChild("HumanoidRootPart",10)
            if running and hum and root then createESP(player) end
        end)
    end)
    if player.Character then createESP(player) end
end
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
connect(Players.PlayerAdded,setupPlayer)
connect(Players.PlayerRemoving,removeESP)

local lastStatusUpdate = 0
RunService:BindToRenderStep(renderName,Enum.RenderPriority.Camera.Value+1,function(dt)
    if not running then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local center = camera.ViewportSize/2
    circle.Position=UDim2.fromOffset(center.X,center.Y)
    circle.Size=UDim2.fromOffset(S.FOV*2,S.FOV*2)
    circle.Visible=S.FOVVisible

    for player, v in pairs(visuals) do
        local alive = v.Character.Parent ~= nil and
            v.Root.Parent ~= nil and v.Humanoid.Health > 0
        local distance = alive and
            (camera.CFrame.Position-v.Root.Position).Magnitude or math.huge
        local show = S.ESP and alive and distance <= S.ESPDistance
        v.Billboard.Enabled=show
        v.Highlight.Enabled=show and S.Highlight
        v.Box.Visible=S.Boxes
        v.Name.Visible=S.Names
        v.HPBackground.Visible=S.Health
        if show then
            local hp = math.clamp(v.Humanoid.Health/math.max(v.Humanoid.MaxHealth,1),0,1)
            v.HPBar.Size=UDim2.fromScale(1,hp)
            v.HPBar.BackgroundColor3=Color3.fromRGB(
                math.floor(255*(1-hp)),math.floor(255*hp),50)
            v.Name.Text=player.DisplayName .. " [" .. math.ceil(v.Humanoid.Health) .. " HP]"
        end
    end

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
        local part,model=selectAimTarget(camera,S.Distance,S.Part)
        if part then
            local root=model:FindFirstChild("HumanoidRootPart")
            local velocity=root and root.AssemblyLinearVelocity or Vector3.zero
            aimPosition=part.Position + velocity*S.Prediction
            smooth=S.Smooth
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
    for player in pairs(visuals) do removeESP(player) end
    if gui then gui:Destroy() end
end
print("[FustHub] Bow ballistic fix loaded")
