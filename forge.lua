--[[ 
    ORE SCANNER + PATHFINDING + AUTO MINE + AUTO ATTACK (Ultimate Version v1.8)
    - Scans for ores in the "Rocks" folder
    - ESP Highlights + Radius Visualization
    - Pathfinding Visualizer (Cyan = Walk, Purple = Jump, Red = Fallback)
    - UPDATED: Shows Top 10 Closest Ores only
    - EXCLUSION: Ignores "Island2GoblinCave"
    - OCCUPANCY VISUAL: RED/YELLOW/GREEN status
    - LOGIC FIX: Checks Workspace.Living for players using WorldPivot
    - FEATURE: Player ESP Toggle & AUTO MINE Toggle
    - FEATURE: AUTO COMBAT (Switches to Sword if mob nearby)
    - FIX: Smooth Movement & Anti-Stuck
    - FIX: Highlight Limit (Switched Entity ESP to BoxHandleAdornment)
    - FIX: Robust Scanning (Uses GetDescendants + Safety Checks)
    - FIX: GUI Crash "InfoLabel is not a valid member" resolved
    - FIX: "Label" ghost ore removed
    - FEATURE: Immediate Mining upon entering radius (Proximity Override)
    - FIX: Proximity Override now accepts DAMAGED ores (Prevents jumping off ledges)
    - FIX: Close Button moved to initialization block to ensure visibility
    - FIX: Pathfinding Order (Connect event BEFORE MoveTo) - Solves "Broken Path"
]]

local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- 1. SETTINGS & STATE
local SCAN_DELAY = 1.0 
local MINING_RADIUS = 10 
local COMBAT_RADIUS = 15 
local HIGHLIGHT_LIMIT = 20 

local activeHighlights = {} 
local oreToggleStates = {} 
local lastScanResults = {} 

local playerEspEnabled = false 
local autoMineEnabled = false 
local wasAutoMineOnBeforeDeath = false -- State memory
local isPausedForRespawn = false

local currentMiningOre = nil 
local currentTargetMob = nil 

-- Cleanup old GUI
for _, g in ipairs(CoreGui:GetChildren()) do
    if g.Name == "OreScannerGui" then g:Destroy() end
end
for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
    if g.Name == "OreScannerGui" then g:Destroy() end
end

-- Container for path visuals
local existingFolder = Workspace:FindFirstChild("OrePaths")
if existingFolder then existingFolder:Destroy() end
local pathVisualsFolder = Instance.new("Folder")
pathVisualsFolder.Name = "OrePaths"
pathVisualsFolder.Parent = Workspace

-- 2. GUI CREATION
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OreScannerGui"
ScreenGui.ResetOnSpawn = false

pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "ScannerFrame"
MainFrame.Size = UDim2.new(0, 250, 0, 450)
MainFrame.Position = UDim2.new(0.8, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "v1.8 Ore Scanner + Auto" 
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.Parent = MainFrame

-- CLOSE BUTTON
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseButton"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 0)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.ZIndex = 10 
CloseBtn.Parent = MainFrame

-- Player ESP Button
local PlayerEspFrame = Instance.new("Frame")
PlayerEspFrame.Name = "PlayerESP_Control"
PlayerEspFrame.Size = UDim2.new(1, -10, 0, 30)
PlayerEspFrame.Position = UDim2.new(0, 5, 0, 35)
PlayerEspFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
PlayerEspFrame.BorderSizePixel = 0
PlayerEspFrame.Parent = MainFrame

local PE_Corner = Instance.new("UICorner")
PE_Corner.CornerRadius = UDim.new(0, 4)
PE_Corner.Parent = PlayerEspFrame

local PE_Label = Instance.new("TextLabel")
PE_Label.Size = UDim2.new(0.65, 0, 1, 0)
PE_Label.Position = UDim2.new(0, 5, 0, 0)
PE_Label.BackgroundTransparency = 1
PE_Label.Text = "Player ESP"
PE_Label.TextXAlignment = Enum.TextXAlignment.Left
PE_Label.TextColor3 = Color3.fromRGB(255, 100, 100)
PE_Label.Font = Enum.Font.GothamBold
PE_Label.TextSize = 14
PE_Label.Parent = PlayerEspFrame

local PE_Toggle = Instance.new("TextButton")
PE_Toggle.Size = UDim2.new(0.3, 0, 0.8, 0)
PE_Toggle.Position = UDim2.new(0.68, 0, 0.1, 0)
PE_Toggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
PE_Toggle.Text = "OFF"
PE_Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
PE_Toggle.Font = Enum.Font.GothamBold
PE_Toggle.TextSize = 11
PE_Toggle.Parent = PlayerEspFrame

local PE_BtnCorner = Instance.new("UICorner")
PE_BtnCorner.CornerRadius = UDim.new(0, 4)
PE_BtnCorner.Parent = PE_Toggle

-- Auto Mine Button
local AutoMineFrame = Instance.new("Frame")
AutoMineFrame.Name = "AutoMine_Control"
AutoMineFrame.Size = UDim2.new(1, -10, 0, 30)
AutoMineFrame.Position = UDim2.new(0, 5, 0, 70)
AutoMineFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
AutoMineFrame.BorderSizePixel = 0
AutoMineFrame.Parent = MainFrame

local AM_Corner = Instance.new("UICorner")
AM_Corner.CornerRadius = UDim.new(0, 4)
AM_Corner.Parent = AutoMineFrame

local AM_Label = Instance.new("TextLabel")
AM_Label.Size = UDim2.new(0.65, 0, 1, 0)
AM_Label.Position = UDim2.new(0, 5, 0, 0)
AM_Label.BackgroundTransparency = 1
AM_Label.Text = "Auto Mine/Attack"
AM_Label.TextXAlignment = Enum.TextXAlignment.Left
AM_Label.TextColor3 = Color3.fromRGB(100, 255, 255)
AM_Label.Font = Enum.Font.GothamBold
AM_Label.TextSize = 14
AM_Label.Parent = AutoMineFrame

local AM_Toggle = Instance.new("TextButton")
AM_Toggle.Size = UDim2.new(0.3, 0, 0.8, 0)
AM_Toggle.Position = UDim2.new(0.68, 0, 0.1, 0)
AM_Toggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
AM_Toggle.Text = "OFF"
AM_Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
AM_Toggle.Font = Enum.Font.GothamBold
AM_Toggle.TextSize = 11
AM_Toggle.Parent = AutoMineFrame

local AM_BtnCorner = Instance.new("UICorner")
AM_BtnCorner.CornerRadius = UDim.new(0, 4)
AM_BtnCorner.Parent = AM_Toggle

-- Scrolling Frame (Ores)
local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Size = UDim2.new(1, -10, 0, 150)
ScrollingFrame.Position = UDim2.new(0, 5, 0, 105)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.ScrollBarThickness = 4
ScrollingFrame.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 5)
UIListLayout.SortOrder = Enum.SortOrder.Name
UIListLayout.Parent = ScrollingFrame

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -10, 0, 20)
StatusLabel.Position = UDim2.new(0, 5, 0, 260)
StatusLabel.BackgroundTransparency = 0.8
StatusLabel.BackgroundColor3 = Color3.new(0,0,0)
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 12
StatusLabel.Parent = MainFrame

-- Debug Console (FIXED)
local DebugFrame = Instance.new("ScrollingFrame")
DebugFrame.Name = "DebugConsole"
DebugFrame.Size = UDim2.new(1, -10, 0, 150)
DebugFrame.Position = UDim2.new(0, 5, 0, 285)
DebugFrame.BackgroundTransparency = 0.5
DebugFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
DebugFrame.ScrollBarThickness = 2
DebugFrame.Parent = MainFrame

local DebugLayout = Instance.new("UIListLayout")
DebugLayout.Padding = UDim.new(0, 2)
DebugLayout.Parent = DebugFrame

DebugLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    DebugFrame.CanvasSize = UDim2.new(0, 0, 0, DebugLayout.AbsoluteContentSize.Y)
    DebugFrame.CanvasPosition = Vector2.new(0, DebugLayout.AbsoluteContentSize.Y)
end)

local function logDebug(msg)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 15)
    lbl.BackgroundTransparency = 1
    lbl.Text = "["..os.date("%X").."] " .. msg
    lbl.TextColor3 = Color3.fromRGB(180, 180, 180)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = DebugFrame
    
    if #DebugFrame:GetChildren() > 50 then 
        local children = DebugFrame:GetChildren()
        for i, child in ipairs(children) do
            if child:IsA("TextLabel") then
                child:Destroy()
                break
            end
        end
    end
end

-- 3. HELPER FUNCTIONS
local function getOrePosition(ore)
    if not ore or not ore.Parent then return nil end
    if ore:IsA("Model") then
        return ore:GetPivot().Position
    elseif ore:IsA("BasePart") then
        return ore.Position
    end
    return nil
end

local function isOreFullHealth(ore)
    local health = ore:GetAttribute("Health")
    local maxHealth = ore:GetAttribute("MaxHealth")
    if health and maxHealth then
        return health >= maxHealth
    end
    return true 
end

local function isOreOccupied(orePos)
    local living = Workspace:FindFirstChild("Living")
    if not living then return false end
    
    for _, model in ipairs(living:GetChildren()) do
        if model and model.Parent then
            if model:IsA("Model") and Players:FindFirstChild(model.Name) then
                if model.Name ~= LocalPlayer.Name then
                    local pivot = model:GetPivot()
                    if pivot then
                        local dist = (pivot.Position - orePos).Magnitude
                        if dist <= MINING_RADIUS then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function isValidOre(ore)
    local pos = getOrePosition(ore)
    if not pos then return false end
    
    if ore == currentMiningOre then
        return not isOreOccupied(pos)
    end
    
    return isOreFullHealth(ore) and not isOreOccupied(pos)
end

-- 4. COMBAT & TOOL FUNCTIONS
local function equipToolByName(toolName)
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
    if tool then
        humanoid:EquipTool(tool)
    end
end

local function equipPickaxe()
    equipToolByName("Pickaxe")
end

local function equipSword()
    equipToolByName("Sword")
    if not LocalPlayer.Character:FindFirstChild("Sword") then
        equipToolByName("Weapon") 
    end
end

local function mineTarget(ore)
    pcall(function()
        local args = { "Pickaxe" }
        ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer(unpack(args))
    end)
end

local function attackTargetMob(mob)
    pcall(function()
        local args = { "Weapon" }
        ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer(unpack(args))
    end)
end

local function faceTarget(pos)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local root = char.HumanoidRootPart
        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z))
    end
end

-- 5. ENTITY DETECTION (MOBS)
local function getNearbyMob()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    local living = Workspace:FindFirstChild("Living")
    if not living then return nil end
    
    local closestMob = nil
    local closestDist = COMBAT_RADIUS 
    
    for _, model in ipairs(living:GetChildren()) do
        if model:IsA("Model") and model ~= char then
            if not Players:FindFirstChild(model.Name) then
                local pivot = model:GetPivot()
                local hum = model:FindFirstChild("Humanoid")
                
                if pivot and hum and hum.Health > 0 then
                    local dist = (pivot.Position - root.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestMob = model
                    end
                end
            end
        end
    end
    return closestMob
end

-- 6. AUTO LOOP (MINE + COMBAT)
local function getBestOre()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    local bestOre = nil
    local shortestDist = math.huge
    
    for oreName, isEnabled in pairs(oreToggleStates) do
        if isEnabled and lastScanResults[oreName] then
            for _, ore in ipairs(lastScanResults[oreName].Instances) do
                if isValidOre(ore) then
                    local pos = getOrePosition(ore)
                    local dist = (root.Position - pos).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        bestOre = ore
                    end
                end
            end
        end
    end
    return bestOre
end

local function updateStatus(text)
    StatusLabel.Text = "Status: " .. text
end

local function autoMineLoop()
    logDebug("Auto System Started")
    
    while autoMineEnabled do
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") then
            local root = char.HumanoidRootPart
            local humanoid = char.Humanoid
            
            -- 1. COMBAT PRIORITY CHECK
            local nearbyMob = getNearbyMob()
            
            if nearbyMob then
                updateStatus("COMBAT: Attacking " .. nearbyMob.Name)
                if not char:FindFirstChild("Sword") and not char:FindFirstChild("Weapon") then
                    equipSword()
                end
                
                local mobPos = nearbyMob:GetPivot().Position
                humanoid:MoveTo(root.Position) 
                faceTarget(mobPos)
                attackTargetMob(nearbyMob)
                
                if (root.Position - mobPos).Magnitude > 5 then
                    humanoid:MoveTo(mobPos)
                end
                task.wait(0.1) 
                continue 
            end
            
            -- 2. IMMEDIATE PROXIMITY OVERRIDE
            local foundNearby = false
            for oreName, isEnabled in pairs(oreToggleStates) do
                if isEnabled and lastScanResults[oreName] then
                    for _, ore in ipairs(lastScanResults[oreName].Instances) do
                        local pos = getOrePosition(ore)
                        if pos and (root.Position - pos).Magnitude <= MINING_RADIUS then
                            if not isOreOccupied(pos) then 
                                currentMiningOre = ore
                                foundNearby = true
                                break
                            end
                        end
                    end
                end
                if foundNearby then break end
            end

            -- 3. MINING LOGIC
            if currentMiningOre and (not currentMiningOre.Parent) then
                logDebug("Ore broken/lost. Searching...")
                currentMiningOre = nil
            end

            if not currentMiningOre then
                updateStatus("Scanning...")
                currentMiningOre = getBestOre()
            end
            
            local targetOre = currentMiningOre
            
            if targetOre then
                local targetPos = getOrePosition(targetOre)
                
                if targetPos then
                    local dist = (root.Position - targetPos).Magnitude
                    
                    if dist <= MINING_RADIUS then
                        updateStatus("Mining " .. targetOre.Name)
                        humanoid:MoveTo(root.Position)
                        if not char:FindFirstChild("Pickaxe") then
                            equipPickaxe()
                        end
                        faceTarget(targetPos)
                        mineTarget(targetOre)
                        task.wait(0.1)
                    else
                        updateStatus("Moving to " .. targetOre.Name)
                        
                        -- PATHFINDING WITH ROBUST FAILSAFES
                        local path = PathfindingService:CreatePath({
                            AgentRadius = 2.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water = 20, [Enum.Material.Air] = 4 }
                        })
                        
                        local success = pcall(function()
                            path:ComputeAsync(root.Position, targetPos)
                        end)
                        
                        if success and path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            
                            -- ITERATE WAYPOINTS
                            for i, wp in ipairs(waypoints) do
                                if i == 1 then continue end
                                
                                -- Break checks
                                if not autoMineEnabled or not currentMiningOre or not currentMiningOre.Parent then break end
                                if getNearbyMob() then break end
                                if (root.Position - targetPos).Magnitude <= MINING_RADIUS then break end -- Close enough!
                                
                                -- Status Update for debugging
                                updateStatus("Moving to " .. targetOre.Name .. " ("..i.."/"..#waypoints..")")
                                
                                if wp.Action == Enum.PathWaypointAction.Jump then
                                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                                    humanoid.Jump = true
                                end
                                
                                -- MOVEMENT FIX: Connect BEFORE MoveTo
                                local moveSuccess = false
                                local connection
                                connection = humanoid.MoveToFinished:Connect(function() moveSuccess = true end)
                                
                                humanoid:MoveTo(wp.Position)
                                
                                local timeElapsed = 0
                                local timeout = 1.5 
                                
                                while not moveSuccess and timeElapsed < timeout do
                                    if not autoMineEnabled then break end
                                    if (root.Position - targetPos).Magnitude <= MINING_RADIUS then moveSuccess = true; break end
                                    if getNearbyMob() then moveSuccess = true; break end 
                                    
                                    -- AGGRESSIVE STUCK CHECK
                                    if root.Velocity.Magnitude < 0.1 and timeElapsed > 0.25 then
                                        logDebug("Stuck! Jumping...")
                                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                                        humanoid.Jump = true
                                        root.Velocity = root.Velocity + Vector3.new(0, 15, 0)
                                        break 
                                    end
                                    task.wait(0.1); timeElapsed = timeElapsed + 0.1
                                end
                                if connection then connection:Disconnect() end
                            end
                        else
                            -- Path failed? Try direct move for a bit
                            humanoid:MoveTo(targetPos)
                            task.wait(0.5)
                        end
                    end
                else
                    currentMiningOre = nil
                end
            else
                updateStatus("Idle - No ores")
                task.wait(0.5)
            end
        end
        task.wait()
    end
    updateStatus("Auto Disabled")
end

-- 7. ANIMATION SCRIPT
local function enableAnimations(character)
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid")
        local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
        local walkAnim = Instance.new("Animation")
        walkAnim.AnimationId = "http://www.roblox.com/asset/?id=180426354"
        local track = animator:LoadAnimation(walkAnim)
        while character.Parent do
            local speed = character.HumanoidRootPart.Velocity.Magnitude * Vector3.new(1,0,1).Magnitude
            if speed > 1 then
                if not track.IsPlaying then track:Play() end
                track:AdjustSpeed(speed / 16)
            else
                if track.IsPlaying then track:Stop() end
            end
            task.wait(0.1)
        end
    end)
end
LocalPlayer.CharacterAdded:Connect(enableAnimations)
if LocalPlayer.Character then enableAnimations(LocalPlayer.Character) end

-- 8. PLAYER/MOB ESP FUNCTION (Fixed Rendering)
local function updateEntityESP()
    local living = Workspace:FindFirstChild("Living")
    if not living then return end
    
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    
    if root then
        local combatVis = root:FindFirstChild("CombatRadiusVisual")
        if not combatVis then
            combatVis = Instance.new("CylinderHandleAdornment")
            combatVis.Name = "CombatRadiusVisual"
            combatVis.Adornee = root
            combatVis.Height = 1
            combatVis.Radius = COMBAT_RADIUS
            combatVis.CFrame = CFrame.new(0, -2.5, 0) * CFrame.Angles(math.rad(90), 0, 0)
            combatVis.Transparency = 0.8
            combatVis.Color3 = Color3.fromRGB(255, 0, 0) 
            combatVis.AlwaysOnTop = true
            combatVis.ZIndex = 0
            combatVis.Parent = root
        end
    end
    
    for _, model in ipairs(living:GetChildren()) do
        if model:IsA("Model") and model ~= LocalPlayer.Character then
            -- Is Player?
            if Players:FindFirstChild(model.Name) then
                if playerEspEnabled then
                    if not model:FindFirstChild("PlayerBox") then
                        local box = Instance.new("BoxHandleAdornment")
                        box.Name = "PlayerBox"; box.Adornee = model; box.Size = model:GetExtentsSize()
                        box.Color3 = Color3.fromRGB(255, 0, 0); box.Transparency = 0.5; box.AlwaysOnTop = true; box.ZIndex = 5; box.Parent = model
                        local bb = Instance.new("BillboardGui"); bb.Name = "PlayerTag"; bb.Adornee = model
                        bb.Size = UDim2.new(0, 100, 0, 20); bb.StudsOffset = Vector3.new(0, 3, 0); bb.AlwaysOnTop = true; bb.Parent = model
                        local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,0,1,0); t.BackgroundTransparency = 1
                        t.Text = model.Name; t.TextColor3 = Color3.fromRGB(255, 255, 255); t.Font = Enum.Font.GothamBold; t.Parent = bb
                    end
                else
                    if model:FindFirstChild("PlayerBox") then model.PlayerBox:Destroy() end
                    if model:FindFirstChild("PlayerTag") then model.PlayerTag:Destroy() end
                end
            else
                -- Is Mob?
                local hum = model:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 and autoMineEnabled then
                    if not model:FindFirstChild("MobBox") then
                        local box = Instance.new("BoxHandleAdornment")
                        box.Name = "MobBox"; box.Adornee = model; box.Size = model:GetExtentsSize()
                        box.Color3 = Color3.fromRGB(255, 100, 0) -- Orange
                        box.Transparency = 0.6
                        box.AlwaysOnTop = true; box.ZIndex = 5; box.Parent = model
                    end
                end
            end
        end
    end
end

-- 9. HIGHLIGHTS & PATHS (Fixed Limit)
local function updateHighlights(oreName, instances, isEnabled)
    if isEnabled then
        local count = 0
        local sortedInstances = {}
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            for _, model in ipairs(instances) do
                local pos = getOrePosition(model)
                if pos then
                    table.insert(sortedInstances, {model = model, dist = (root.Position - pos).Magnitude})
                end
            end
            table.sort(sortedInstances, function(a, b) return a.dist < b.dist end)
        end

        for _, entry in ipairs(sortedInstances) do
            local model = entry.model
            count = count + 1
            if count > HIGHLIGHT_LIMIT then
                if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end
                if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end
                continue
            end

            if model:IsA("Model") or model:IsA("BasePart") then
                local pos = getOrePosition(model)
                local isFull = isOreFullHealth(model)
                local isOccupied = pos and isOreOccupied(pos)
                local radiusColor = Color3.fromRGB(50, 255, 50)
                if model == currentMiningOre then radiusColor = Color3.fromRGB(0, 255, 255)
                elseif not isFull then radiusColor = Color3.fromRGB(255, 50, 50)
                elseif isOccupied then radiusColor = Color3.fromRGB(255, 255, 50) end

                if not model:FindFirstChild("OreHighlight") then
                    local h = Instance.new("Highlight"); h.Name = "OreHighlight"; h.Adornee = model
                    h.FillColor = Color3.fromRGB(0, 255, 0); h.FillTransparency = 0.5; h.Parent = model
                end
                local adornment = model:FindFirstChild("OreRadiusVisual")
                if not adornment then
                    adornment = Instance.new("SphereHandleAdornment"); adornment.Name = "OreRadiusVisual"
                    local center = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model
                    if center then adornment.Adornee = center; adornment.AlwaysOnTop = true; adornment.Transparency = 0.7; adornment.Parent = model end
                end
                if adornment then adornment.Radius = MINING_RADIUS; adornment.Color3 = radiusColor end
            end
        end
    else
        for _, model in ipairs(instances) do
            if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end
            if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end
        end
    end
end

local function updatePaths()
    pathVisualsFolder:ClearAllChildren()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local startPos = root.Position

    for oreName, isEnabled in pairs(oreToggleStates) do
        if isEnabled and lastScanResults[oreName] then
            local sortedOres = {}
            for _, ore in ipairs(lastScanResults[oreName].Instances) do
                if isValidOre(ore) then
                    local p = getOrePosition(ore)
                    table.insert(sortedOres, {Ore = ore, Pos = p, Dist = (startPos - p).Magnitude})
                end
            end
            table.sort(sortedOres, function(a,b) return a.Dist < b.Dist end)
            
            for i = 1, math.min(10, #sortedOres) do
                local entry = sortedOres[i]
                task.spawn(function()
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water=20, [Enum.Material.Air]=4 }
                    })
                    local s = pcall(function() path:ComputeAsync(startPos, entry.Pos) end)
                    if s and path.Status == Enum.PathStatus.Success then
                        for _, wp in ipairs(path:GetWaypoints()) do
                            local n = Instance.new("Part"); n.Shape = Enum.PartType.Ball; n.Size = Vector3.new(0.5,0.5,0.5); n.Material = Enum.Material.Neon; n.Anchored = true; n.CanCollide = false; n.Position = wp.Position; n.Parent = pathVisualsFolder
                            if wp.Action == Enum.PathWaypointAction.Jump then n.Color = Color3.fromRGB(170,0,255) else n.Color = Color3.fromRGB(0,255,255) end
                        end
                    else
                        local n = Instance.new("Part"); n.Shape = Enum.PartType.Ball; n.Size = Vector3.new(0.4,0.4,0.4); n.Color = Color3.fromRGB(255,50,50); n.Anchored = true; n.CanCollide = false; n.Position = entry.Pos; n.Parent = pathVisualsFolder
                    end
                end)
            end
        end
    end
end

-- 10. SCANNING LOGIC (ROBUST)
local function scanOres()
    local rocks = Workspace:FindFirstChild("Rocks")
    if not rocks then
        logDebug("Waiting for 'Rocks' folder...")
        rocks = Workspace:WaitForChild("Rocks", 5)
    end
    
    if not rocks then return {} end
    
    local current = {}
    
    for _, descendant in ipairs(rocks:GetDescendants()) do
        if descendant:IsA("Model") and descendant:GetAttribute("Health") then
            if descendant.Name == "Label" or descendant.Name == "Folder" or descendant.Name == "Model" or descendant.Name == "Part" or descendant.Name == "MeshPart" then continue end

            local parent = descendant.Parent
            local skip = false
            while parent and parent ~= Workspace do
                if parent.Name == "Island2GoblinCave" then skip = true; break end
                parent = parent.Parent
            end
            
            if not skip then
                local pos = getOrePosition(descendant)
                if pos then
                    local n = descendant.Name
                    if not current[n] then current[n] = {Count=0, Instances={}} end
                    table.insert(current[n].Instances, descendant)
                    current[n].Count = current[n].Count + 1
                end
            end
        end
    end
    
    lastScanResults = current
    for n, d in pairs(current) do
        if oreToggleStates[n] then updateHighlights(n, d.Instances, true) end
    end
    return current
end

-- 11. REFRESH & GUI
local function refreshGui()
    local data = scanOres()
    updateEntityESP()
    updatePaths()
    
    local seen = {}
    if data then
        for name, info in pairs(data) do
            seen[name] = true
            local fname = "Frame_"..name
            local f = ScrollingFrame:FindFirstChild(fname)
            if not f then
                f = Instance.new("Frame"); f.Name = fname; f.Size = UDim2.new(1,-5,0,30); f.BackgroundColor3 = Color3.fromRGB(40,40,40); f.Parent = ScrollingFrame
                local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = f
                local l = Instance.new("TextLabel"); l.Name = "InfoLabel"; l.Size = UDim2.new(0.65,0,1,0); l.Position = UDim2.new(0,5,0,0); l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextColor3 = Color3.fromRGB(220,220,220); l.Font = Enum.Font.GothamMedium; l.TextSize = 12; l.Parent = f
                local b = Instance.new("TextButton"); b.Name = "ToggleBtn"; b.Size = UDim2.new(0.3,0,0.8,0); b.Position = UDim2.new(0.68,0,0.1,0); b.BackgroundColor3 = Color3.fromRGB(60,60,60); b.Text = "OFF"; b.TextColor3 = Color3.fromRGB(255,255,255); b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.Parent = f
                local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,4); bc.Parent = b
                
                b.MouseButton1Click:Connect(function()
                    oreToggleStates[name] = not oreToggleStates[name]
                    if oreToggleStates[name] then b.Text="ON"; b.BackgroundColor3=Color3.fromRGB(0,170,0) else b.Text="OFF"; b.BackgroundColor3=Color3.fromRGB(60,60,60) if lastScanResults[name] then updateHighlights(name, lastScanResults[name].Instances, false) end end
                    scanOres(); updatePaths()
                end)
            end
            local lbl = f:FindFirstChild("InfoLabel")
            if lbl then lbl.Text = string.format("%s - [%d]", name, info.Count) end
        end
    end
    for _, c in ipairs(ScrollingFrame:GetChildren()) do if c:IsA("Frame") and not seen[c.Name:gsub("Frame_","")] then c:Destroy() end end
    ScrollingFrame.CanvasSize = UDim2.new(0,0,0,UIListLayout.AbsoluteContentSize.Y)
end

PE_Toggle.MouseButton1Click:Connect(function()
    playerEspEnabled = not playerEspEnabled
    if playerEspEnabled then PE_Toggle.Text="ON"; PE_Toggle.BackgroundColor3=Color3.fromRGB(255,50,50) else PE_Toggle.Text="OFF"; PE_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60) 
        local l = Workspace:FindFirstChild("Living")
        if l then for _,m in ipairs(l:GetChildren()) do if m:FindFirstChild("PlayerBox") then m.PlayerBox:Destroy() end if m:FindFirstChild("PlayerTag") then m.PlayerTag:Destroy() end end end
    end
    updateEntityESP()
end)

AM_Toggle.MouseButton1Click:Connect(function()
    autoMineEnabled = not autoMineEnabled
    if autoMineEnabled then AM_Toggle.Text="ON"; AM_Toggle.BackgroundColor3=Color3.fromRGB(0,255,255); task.spawn(autoMineLoop)
    else AM_Toggle.Text="OFF"; AM_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60); currentMiningOre = nil; updateStatus("Idle") end
end)

task.spawn(function() while true do refreshGui(); task.wait(SCAN_DELAY) end end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy(); pathVisualsFolder:Destroy()
    for n, d in pairs(lastScanResults) do updateHighlights(n, d.Instances, false) end
    autoMineEnabled = false
end)
