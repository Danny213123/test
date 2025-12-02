--[[ 
    ORE SCANNER + PATHFINDING + AUTO MINE + AUTO ATTACK (Ultimate Version v1.24)
    - v1.24 UPDATE: Reduced Dynamic Path Check Frequency (Fixed movement stuttering).
        - Now checks for better ores every 15 waypoints instead of 5.
    - v1.23 UPDATE: Dual-Radius Availability System (Red/Yellow/Green Status).
    - v1.23 UPDATE: Prioritizes Green ores over Yellow. Aborts path if target turns Red.
    - v1.22 UPDATE: Fixed "Impossible Ore" Bug.
    - v1.21 UPDATE: Reverted to standard walking.
    - Scans for ores in the "Rocks" folder
    - ESP Highlights + Radius Visualization
    - EXCLUSION: Ignores "Island2GoblinCave"
    - FEATURE: Player ESP Toggle & AUTO MINE Toggle
    - FEATURE: AUTO COMBAT (Switches to Sword if mob nearby)
    - FIX: Robust Scanning (Uses GetDescendants + Safety Checks)
]]

local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- 1. SETTINGS & STATE
local SCAN_DELAY = 0.5 -- Faster scanning for real-time status updates
local MINING_RADIUS = 7.5           -- Interaction range
local PLAYER_DETECTION_RADIUS = 25  -- Player detection range (The "Larger" radius)
local SURFACE_STOP_DISTANCE = 3.5   -- Stop distance from ore surface
local COMBAT_RADIUS = 15 
local HIGHLIGHT_LIMIT = 30 

-- TIMEOUT SETTINGS
local MAX_ORE_TIME = 60           
local ORE_BLACKLIST_DURATION = 300 
local MAX_COMBAT_TIME = 15        
local COMBAT_BLACKLIST_DURATION = 60 

local activeHighlights = {} 
local oreToggleStates = {} 
local lastScanResults = {} 

local oreBlacklist = {} 
local mobBlacklist = {} 

local playerEspEnabled = false 
local autoMineEnabled = false 
local currentMiningOre = nil 
local currentOreStartTime = 0 
local currentCombatTarget = nil
local currentCombatStartTime = 0

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

-- DRAGGABLE FUNCTION
local function makeDraggable(gui)
    local dragging, dragInput, dragStart, startPos
    local function update(input)
        local delta = input.Position - dragStart
        gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = gui.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    gui.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
    UserInputService.InputChanged:Connect(function(input) if input == dragInput and dragging then update(input) end end)
end

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
MainFrame.Active = true 
MainFrame.Parent = ScreenGui
makeDraggable(MainFrame)

local UICorner = Instance.new("UICorner"); UICorner.Parent = MainFrame
local Title = Instance.new("TextLabel"); Title.Size = UDim2.new(1, 0, 0, 30); Title.BackgroundTransparency = 1; Title.Text = "v1.24 Ore Scanner + Auto"; Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.Font = Enum.Font.GothamBold; Title.TextSize = 18; Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton"); CloseBtn.Name = "CloseButton"; CloseBtn.Size = UDim2.new(0, 30, 0, 30); CloseBtn.Position = UDim2.new(1, -35, 0, 0); CloseBtn.BackgroundTransparency = 1; CloseBtn.Text = "X"; CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200); CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 18; CloseBtn.ZIndex = 10; CloseBtn.Parent = MainFrame

-- Controls
local function createControl(name, yPos, text, color)
    local f = Instance.new("Frame"); f.Name = name; f.Size = UDim2.new(1, -10, 0, 30); f.Position = UDim2.new(0, 5, 0, yPos); f.BackgroundColor3 = Color3.fromRGB(40, 40, 40); f.Parent = MainFrame
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(0.65, 0, 1, 0); l.Position = UDim2.new(0, 5, 0, 0); l.BackgroundTransparency = 1; l.Text = text; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextColor3 = color; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.Parent = f
    local b = Instance.new("TextButton"); b.Size = UDim2.new(0.3, 0, 0.8, 0); b.Position = UDim2.new(0.68, 0, 0.1, 0); b.BackgroundColor3 = Color3.fromRGB(60, 60, 60); b.Text = "OFF"; b.TextColor3 = Color3.fromRGB(255, 255, 255); b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.Parent = f
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local PE_Toggle = createControl("PlayerESP_Control", 35, "Player ESP", Color3.fromRGB(255, 100, 100))
local AM_Toggle = createControl("AutoMine_Control", 70, "Auto Mine/Attack", Color3.fromRGB(100, 255, 255))

local ScrollingFrame = Instance.new("ScrollingFrame"); ScrollingFrame.Size = UDim2.new(1, -10, 0, 150); ScrollingFrame.Position = UDim2.new(0, 5, 0, 105); ScrollingFrame.BackgroundTransparency = 1; ScrollingFrame.ScrollBarThickness = 4; ScrollingFrame.Parent = MainFrame
local UIListLayout = Instance.new("UIListLayout"); UIListLayout.Padding = UDim.new(0, 5); UIListLayout.SortOrder = Enum.SortOrder.Name; UIListLayout.Parent = ScrollingFrame

local StatusLabel = Instance.new("TextLabel"); StatusLabel.Name = "StatusLabel"; StatusLabel.Size = UDim2.new(1, -10, 0, 20); StatusLabel.Position = UDim2.new(0, 5, 0, 260); StatusLabel.BackgroundTransparency = 0.8; StatusLabel.BackgroundColor3 = Color3.new(0,0,0); StatusLabel.Text = "Status: Idle"; StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200); StatusLabel.Font = Enum.Font.Gotham; StatusLabel.TextSize = 12; StatusLabel.Parent = MainFrame

local DebugFrame = Instance.new("ScrollingFrame"); DebugFrame.Name = "DebugConsole"; DebugFrame.Size = UDim2.new(1, -10, 0, 150); DebugFrame.Position = UDim2.new(0, 5, 0, 285); DebugFrame.BackgroundTransparency = 0.5; DebugFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10); DebugFrame.ScrollBarThickness = 2; DebugFrame.Parent = MainFrame
local DebugLayout = Instance.new("UIListLayout"); DebugLayout.Padding = UDim.new(0, 2); DebugLayout.Parent = DebugFrame
DebugLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() DebugFrame.CanvasSize = UDim2.new(0, 0, 0, DebugLayout.AbsoluteContentSize.Y); DebugFrame.CanvasPosition = Vector2.new(0, DebugLayout.AbsoluteContentSize.Y) end)

local function logDebug(msg)
    local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1, 0, 0, 15); lbl.BackgroundTransparency = 1; lbl.Text = "["..os.date("%X").."] " .. msg; lbl.TextColor3 = Color3.fromRGB(180, 180, 180); lbl.Font = Enum.Font.Code; lbl.TextSize = 10; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = DebugFrame
    if #DebugFrame:GetChildren() > 50 then local c = DebugFrame:GetChildren(); for i, ch in ipairs(c) do if ch:IsA("TextLabel") then ch:Destroy(); break end end end
end

-- 3. HELPER FUNCTIONS
local function getOrePosition(ore)
    if not ore or not ore.Parent then return nil end
    if ore:IsA("Model") then return ore:GetPivot().Position
    elseif ore:IsA("BasePart") then return ore.Position end
    return nil
end

local function getSurfaceDistance(characterRoot, targetOre)
    local targetPos = getOrePosition(targetOre)
    if not targetPos then return 9999 end
    local origin = characterRoot.Position
    local direction = (targetPos - origin)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {targetOre}
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    local raycastResult = Workspace:Raycast(origin, direction, raycastParams)
    if raycastResult then return (origin - raycastResult.Position).Magnitude else return direction.Magnitude end
end

local function isSafeToWalk(targetPos)
    local char = LocalPlayer.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local origin = root.Position
    local diff = (targetPos - origin)
    local horizontalDir = Vector3.new(diff.X, 0, diff.Z).Unit
    local distance = diff.Magnitude
    if (origin.Y - targetPos.Y) > 10 and distance > 5 then return false end
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {char}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local checkPos = origin + (horizontalDir * 3)
    local rayDown = Workspace:Raycast(checkPos, Vector3.new(0, -15, 0), rayParams)
    if not rayDown then return false end
    local rayForward = Workspace:Raycast(origin, horizontalDir * 3, rayParams)
    if rayForward and rayForward.Instance.CanCollide then
        if not rayForward.Instance:IsDescendantOf(Workspace:FindFirstChild("Rocks")) then return false end
    end
    return true
end

local function isOreFullHealth(ore)
    local h = ore:GetAttribute("Health")
    local m = ore:GetAttribute("MaxHealth")
    return (h and m) and h >= m or true
end

-- V1.23: ADVANCED AVAILABILITY CHECK
-- Returns: "RED" (Blocked), "YELLOW" (Caution), "GREEN" (Free)
local function getOreStatus(ore)
    local orePos = getOrePosition(ore)
    if not orePos then return "RED" end
    
    local isFull = isOreFullHealth(ore)
    local playerNearby = false
    
    local living = Workspace:FindFirstChild("Living")
    if living then
        for _, model in ipairs(living:GetChildren()) do
            if model and model.Parent and model:IsA("Model") and Players:FindFirstChild(model.Name) and model.Name ~= LocalPlayer.Name then
                local pivot = model:GetPivot()
                if pivot and (pivot.Position - orePos).Magnitude <= PLAYER_DETECTION_RADIUS then
                    playerNearby = true
                    break
                end
            end
        end
    end
    
    if playerNearby then
        if not isFull then
            return "RED" -- Player is nearby AND ore is damaged (Active Mining)
        else
            return "YELLOW" -- Player is nearby BUT ore is healthy (Camping/AFK)
        end
    else
        return "GREEN" -- No players nearby
    end
end

local function isValidOre(ore)
    if oreBlacklist[ore] and (tick() - oreBlacklist[ore] < ORE_BLACKLIST_DURATION) then return false end
    if not ore.Parent then return false end
    
    -- V1.23: Use Status Logic
    local status = getOreStatus(ore)
    
    if status == "RED" then return false end -- Never go to RED ores
    -- Allow YELLOW and GREEN
    return true
end

-- 4. COMBAT & TOOL FUNCTIONS
local function equipToolByName(toolName)
    local char = LocalPlayer.Character; if not char then return end
    local hum = char:FindFirstChild("Humanoid"); if not hum then return end
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
    if tool then hum:EquipTool(tool) end
end

local function equipPickaxe() equipToolByName("Pickaxe") end
local function equipSword() equipToolByName("Sword"); if not LocalPlayer.Character:FindFirstChild("Sword") then equipToolByName("Weapon") end end

local function mineTarget(ore)
    pcall(function() ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer("Pickaxe") end)
end

local function attackTargetMob(mob)
    pcall(function() ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer("Weapon") end)
end

local function faceTarget(pos)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z)) end
end

-- 5. ENTITY DETECTION (MOBS)
local function getNearbyMob()
    local char = LocalPlayer.Character; if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return nil end
    local living = Workspace:FindFirstChild("Living"); if not living then return nil end
    
    local closestMob = nil; local closestDist = COMBAT_RADIUS 
    for _, model in ipairs(living:GetChildren()) do
        if model:IsA("Model") and model ~= char then
            if mobBlacklist[model] and (tick() - mobBlacklist[model] < COMBAT_BLACKLIST_DURATION) then continue end
            if not Players:FindFirstChild(model.Name) then
                local pivot = model:GetPivot(); local hum = model:FindFirstChild("Humanoid")
                if pivot and hum and hum.Health > 0 then
                    local dist = (pivot.Position - root.Position).Magnitude
                    if dist < closestDist then closestDist = dist; closestMob = model end
                end
            end
        end
    end
    return closestMob
end

-- 6. AUTO LOOP (MINE + COMBAT)
-- v1.23 UPDATE: PRIORITY ORE SELECTION (Green > Yellow)
local function getBestOre()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    local greenCandidates = {}
    local yellowCandidates = {}
    
    -- 1. Gather & Bucket
    for oreName, isEnabled in pairs(oreToggleStates) do
        if isEnabled and lastScanResults[oreName] then
            for _, ore in ipairs(lastScanResults[oreName].Instances) do
                if isValidOre(ore) then
                    local pos = getOrePosition(ore)
                    if pos then
                        local dist = (root.Position - pos).Magnitude
                        local status = getOreStatus(ore)
                        local entry = {Ore = ore, Pos = pos, Dist = dist}
                        
                        if status == "GREEN" then
                            table.insert(greenCandidates, entry)
                        else
                            table.insert(yellowCandidates, entry)
                        end
                    end
                end
            end
        end
    end
    
    -- 2. Helper to find best from a list using Pathfinding
    local function selectFromList(list)
        table.sort(list, function(a, b) return a.Dist < b.Dist end)
        local best = nil
        local minWps = math.huge
        local checkLimit = math.min(5, #list)
        
        for i = 1, checkLimit do
            local entry = list[i]
            local path = PathfindingService:CreatePath({AgentRadius = 3.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water = 20, [Enum.Material.Air] = 4 }})
            local success = pcall(function() path:ComputeAsync(root.Position, entry.Pos) end)
            if success and path.Status == Enum.PathStatus.Success then
                local wps = #path:GetWaypoints()
                if wps < minWps then
                    minWps = wps
                    best = entry.Ore
                end
            end
        end
        
        -- Fallback to close & safe check
        if not best and #list > 0 then
            local closest = list[1]
            if closest.Dist < 25 and isSafeToWalk(closest.Pos) then best = closest.Ore end
        end
        return best
    end
    
    -- 3. Prioritize Green
    local chosenOre = selectFromList(greenCandidates)
    
    -- 4. If no green reachable, try Yellow
    if not chosenOre then
        chosenOre = selectFromList(yellowCandidates)
    end
    
    return chosenOre
end

local function updateStatus(text) StatusLabel.Text = "Status: " .. text end

local function autoMineLoop()
    logDebug("Auto System Started")
    
    while autoMineEnabled do
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") and char.Humanoid.Health > 0 then
            local root = char.HumanoidRootPart
            local humanoid = char.Humanoid
            
            -- 1. COMBAT CHECK
            local nearbyMob = getNearbyMob()
            if nearbyMob then
                if nearbyMob ~= currentCombatTarget then currentCombatTarget = nearbyMob; currentCombatStartTime = tick() end
                if tick() - currentCombatStartTime > MAX_COMBAT_TIME then
                    mobBlacklist[nearbyMob] = tick(); currentCombatTarget = nil
                else
                    updateStatus("COMBAT: Attacking " .. nearbyMob.Name)
                    if not char:FindFirstChild("Sword") and not char:FindFirstChild("Weapon") then equipSword() end
                    local mobPos = nearbyMob:GetPivot().Position
                    humanoid:MoveTo(root.Position); faceTarget(mobPos); attackTargetMob(nearbyMob)
                    if (root.Position - mobPos).Magnitude > 5 then humanoid:MoveTo(mobPos) end
                    task.wait(0.1); continue 
                end
            else
                currentCombatTarget = nil
            end
            
            -- 2. NEARBY ORE CHECK (Optimization)
            local foundNearby = false
            for oreName, isEnabled in pairs(oreToggleStates) do
                if isEnabled and lastScanResults[oreName] then
                    for _, ore in ipairs(lastScanResults[oreName].Instances) do
                        if oreBlacklist[ore] and (tick() - oreBlacklist[ore] < ORE_BLACKLIST_DURATION) then continue end
                        local pos = getOrePosition(ore)
                        if pos and (root.Position - pos).Magnitude <= MINING_RADIUS then
                            -- Only mine if not RED status (Even if close)
                            if getOreStatus(ore) ~= "RED" then 
                                if currentMiningOre ~= ore then currentMiningOre = ore; currentOreStartTime = tick() end
                                foundNearby = true; break
                            end
                        end
                    end
                end
                if foundNearby then break end
            end

            -- 3. TARGETING
            if currentMiningOre then
                if not currentMiningOre.Parent then logDebug("Ore lost."); currentMiningOre = nil
                elseif tick() - currentOreStartTime > MAX_ORE_TIME then logDebug("TIMEOUT: Blacklisting " .. currentMiningOre.Name); oreBlacklist[currentMiningOre] = tick(); currentMiningOre = nil 
                -- V1.23: Status Change Check
                elseif getOreStatus(currentMiningOre) == "RED" then
                    logDebug("Target became BLOCKED. Switching..."); currentMiningOre = nil
                end
            end

            if not currentMiningOre then updateStatus("Scanning..."); currentMiningOre = getBestOre(); if currentMiningOre then currentOreStartTime = tick() end end
            
            local targetOre = currentMiningOre
            if targetOre then
                local targetPos = getOrePosition(targetOre)
                if targetPos then
                    -- DISTANCE CHECKS
                    local surfaceDist = getSurfaceDistance(root, targetOre)
                    local centerDist = (root.Position - targetPos).Magnitude
                    
                    -- MINE if close enough to center OR close enough to surface
                    if centerDist <= MINING_RADIUS or surfaceDist <= SURFACE_STOP_DISTANCE + 1.0 then
                        updateStatus("Mining " .. targetOre.Name)
                        humanoid:MoveTo(root.Position) -- Stop moving
                        if not char:FindFirstChild("Pickaxe") then equipPickaxe() end
                        faceTarget(targetPos)
                        mineTarget(targetOre)
                        task.wait(0.1)
                    else
                        updateStatus("Moving to " .. targetOre.Name)
                        
                        -- PATHFINDING
                        local path = PathfindingService:CreatePath({
                            AgentRadius = 3.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water = 20, [Enum.Material.Air] = 4 }
                        })
                        
                        local success = pcall(function() path:ComputeAsync(root.Position, targetPos) end)
                        
                        if success and path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            for i, wp in ipairs(waypoints) do
                                if i == 1 then continue end
                                
                                if not autoMineEnabled or not currentMiningOre or not currentMiningOre.Parent then break end
                                if getNearbyMob() then break end
                                if tick() - currentOreStartTime > MAX_ORE_TIME then break end
                                if humanoid.Health <= 0 then break end

                                -- V1.23: CONSTANT STATUS CHECK
                                if getOreStatus(targetOre) == "RED" then break end

                                -- Dynamic Switching
                                if i % 15 == 0 then -- Changed from 5 to 15 to reduce stutter
                                    local potentialNewTarget = getBestOre()
                                    if potentialNewTarget and potentialNewTarget ~= currentMiningOre then
                                        updateStatus("Found better target! Switching...")
                                        currentMiningOre = potentialNewTarget
                                        currentOreStartTime = tick()
                                        break
                                    end
                                end

                                if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then humanoid:MoveTo(root.Position); break end

                                updateStatus("Moving to " .. targetOre.Name)
                                
                                if wp.Action == Enum.PathWaypointAction.Jump then humanoid:ChangeState(Enum.HumanoidStateType.Jumping); humanoid.Jump = true end
                                
                                local moveSuccess = false
                                local connection = humanoid.MoveToFinished:Connect(function() moveSuccess = true end)
                                humanoid:MoveTo(wp.Position)
                                
                                local timeElapsed = 0; local timeout = 1.0
                                while not moveSuccess and timeElapsed < timeout do
                                    if not autoMineEnabled then break end
                                    if humanoid.Health <= 0 then break end
                                    if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then moveSuccess = true; break end
                                    if getNearbyMob() then moveSuccess = true; break end 
                                    if root.Velocity.Magnitude < 0.1 and timeElapsed > 0.5 then humanoid:ChangeState(Enum.HumanoidStateType.Jumping); humanoid.Jump = true; moveSuccess = true; break end 
                                    task.wait(0.1); timeElapsed = timeElapsed + 0.1
                                end
                                if connection then connection:Disconnect() end
                            end
                        else
                            -- FALLBACK WITH SAFETY CHECK
                            if isSafeToWalk(targetPos) then
                                if surfaceDist > SURFACE_STOP_DISTANCE then
                                    humanoid:MoveTo(targetPos)
                                    local timeElapsed = 0
                                    while timeElapsed < 0.5 do
                                        if humanoid.Health <= 0 then break end
                                        if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then humanoid:MoveTo(root.Position); break end
                                        task.wait(0.1); timeElapsed = timeElapsed + 0.1
                                    end
                                end
                            else
                                oreBlacklist[targetOre] = tick(); currentMiningOre = nil
                            end
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

-- 7. ANIMATION & RESPAWN RESET
local function resetState()
    logDebug("Character Reset (Death/Respawn)")
    currentMiningOre = nil
    currentOreStartTime = 0
    currentCombatTarget = nil
    currentCombatStartTime = 0
    pathVisualsFolder:ClearAllChildren()
end

local function enableAnimations(character)
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid")
        local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
        local walkAnim = Instance.new("Animation"); walkAnim.AnimationId = "http://www.roblox.com/asset/?id=180426354"
        local track = animator:LoadAnimation(walkAnim)
        while character.Parent do
            local speed = character.HumanoidRootPart.Velocity.Magnitude * Vector3.new(1,0,1).Magnitude
            if speed > 1 then if not track.IsPlaying then track:Play() end; track:AdjustSpeed(speed / 16)
            else if track.IsPlaying then track:Stop() end end
            task.wait(0.1)
        end
    end)
end

local function onCharacterAdded(char)
    resetState()
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then hum.Died:Connect(resetState) end
    enableAnimations(char)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end

-- 8. ENTITY ESP & HIGHLIGHTS
local function updateEntityESP()
    local living = Workspace:FindFirstChild("Living"); if not living then return end
    local char = LocalPlayer.Character; local root = char and char:FindFirstChild("HumanoidRootPart")
    
    if root then
        -- V1.23: Show Detection Radius visually
        local detectVis = root:FindFirstChild("PlayerDetectRadius")
        if not detectVis then
            detectVis = Instance.new("CylinderHandleAdornment", root); detectVis.Name = "PlayerDetectRadius"; detectVis.Adornee = root; detectVis.Height = 0.5; detectVis.Radius = PLAYER_DETECTION_RADIUS; detectVis.CFrame = CFrame.new(0, -2.8, 0) * CFrame.Angles(math.rad(90), 0, 0); detectVis.Transparency = 0.9; detectVis.Color3 = Color3.fromRGB(255, 100, 100); detectVis.AlwaysOnTop = true; detectVis.ZIndex = 0
        end
    end
    
    for _, model in ipairs(living:GetChildren()) do
        if model:IsA("Model") and model ~= char then
            if Players:FindFirstChild(model.Name) then
                if playerEspEnabled then
                    if not model:FindFirstChild("PlayerBox") then
                        local box = Instance.new("BoxHandleAdornment", model); box.Name = "PlayerBox"; box.Adornee = model; box.Size = model:GetExtentsSize(); box.Color3 = Color3.fromRGB(255, 0, 0); box.Transparency = 0.5; box.AlwaysOnTop = true; box.ZIndex = 5
                        local bb = Instance.new("BillboardGui", model); bb.Name = "PlayerTag"; bb.Adornee = model; bb.Size = UDim2.new(0, 100, 0, 20); bb.StudsOffset = Vector3.new(0, 3, 0); bb.AlwaysOnTop = true
                        local t = Instance.new("TextLabel", bb); t.Size = UDim2.new(1,0,1,0); t.BackgroundTransparency = 1; t.Text = model.Name; t.TextColor3 = Color3.fromRGB(255, 255, 255); t.Font = Enum.Font.GothamBold
                    end
                else
                    if model:FindFirstChild("PlayerBox") then model.PlayerBox:Destroy() end
                    if model:FindFirstChild("PlayerTag") then model.PlayerTag:Destroy() end
                end
            elseif autoMineEnabled then -- Mob ESP
                if not model:FindFirstChild("MobBox") then
                   local box = Instance.new("BoxHandleAdornment", model); box.Name = "MobBox"; box.Adornee = model; box.Size = model:GetExtentsSize(); box.Color3 = Color3.fromRGB(255, 100, 0); box.Transparency = 0.6; box.AlwaysOnTop = true; box.ZIndex = 5
                end
            end
        end
    end
end

local function updateHighlights(oreName, instances, isEnabled)
    if isEnabled then
        local count = 0; local sortedInstances = {}; local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            for _, model in ipairs(instances) do local pos = getOrePosition(model); if pos then table.insert(sortedInstances, {model = model, dist = (root.Position - pos).Magnitude}) end end
            table.sort(sortedInstances, function(a, b) return a.dist < b.dist end)
        end
        for _, entry in ipairs(sortedInstances) do
            local model = entry.model; count = count + 1
            if count > HIGHLIGHT_LIMIT then if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end; if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end; continue end
            if model:IsA("Model") or model:IsA("BasePart") then
                local pos = getOrePosition(model)
                local status = getOreStatus(model)
                local radiusColor = Color3.fromRGB(50, 255, 50) -- GREEN (Default)
                
                -- V1.23: Color Visualization based on Status
                if status == "RED" then radiusColor = Color3.fromRGB(255, 0, 0) -- Blocked
                elseif status == "YELLOW" then radiusColor = Color3.fromRGB(255, 255, 0) -- Caution
                end
                
                if model == currentMiningOre then radiusColor = Color3.fromRGB(0, 255, 255) end

                if not model:FindFirstChild("OreHighlight") then local h = Instance.new("Highlight", model); h.Name = "OreHighlight"; h.Adornee = model; h.FillColor = Color3.fromRGB(0, 255, 0); h.FillTransparency = 0.5 end
                local adornment = model:FindFirstChild("OreRadiusVisual")
                if not adornment then adornment = Instance.new("SphereHandleAdornment", model); adornment.Name = "OreRadiusVisual"; local center = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model; if center then adornment.Adornee = center; adornment.AlwaysOnTop = true; adornment.Transparency = 0.7 end end
                if adornment then adornment.Radius = MINING_RADIUS; adornment.Color3 = radiusColor end
            end
        end
    else
        for _, model in ipairs(instances) do if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end; if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end end
    end
end

local function updatePaths()
    pathVisualsFolder:ClearAllChildren()
    -- Only draw paths if auto mine is off (debugging) or if we want to see potential paths
    if autoMineEnabled then return end 
    -- ... (Existing path visual logic remains if needed for debugging)
end

-- 9. MAIN LOOP
local function scanOres()
    local rocks = Workspace:FindFirstChild("Rocks"); if not rocks then rocks = Workspace:WaitForChild("Rocks", 5) end; if not rocks then return {} end
    local current = {}
    for _, descendant in ipairs(rocks:GetDescendants()) do
        if descendant:IsA("Model") and descendant:GetAttribute("Health") then
            if descendant.Name == "Label" or descendant.Name == "Folder" or descendant.Name == "Model" or descendant.Name == "Part" or descendant.Name == "MeshPart" then continue end
            local parent = descendant.Parent; local skip = false; while parent and parent ~= Workspace do if parent.Name == "Island2GoblinCave" then skip = true; break end; parent = parent.Parent end
            if not skip then
                local pos = getOrePosition(descendant)
                if pos then local n = descendant.Name; if not current[n] then current[n] = {Count=0, Instances={}} end; table.insert(current[n].Instances, descendant); current[n].Count = current[n].Count + 1 end
            end
        end
    end
    lastScanResults = current
    for n, d in pairs(current) do if oreToggleStates[n] then updateHighlights(n, d.Instances, true) end end
    return current
end

local function refreshGui()
    local data = scanOres(); updateEntityESP(); updatePaths()
    local seen = {}
    if data then
        for name, info in pairs(data) do
            seen[name] = true; local fname = "Frame_"..name; local f = ScrollingFrame:FindFirstChild(fname)
            if not f then
                f = Instance.new("Frame"); f.Name = fname; f.Size = UDim2.new(1,-5,0,30); f.BackgroundColor3 = Color3.fromRGB(40,40,40); f.Parent = ScrollingFrame; Instance.new("UICorner", f).CornerRadius = UDim.new(0,4)
                Instance.new("TextLabel", f).Name = "InfoLabel"; f.InfoLabel.Size = UDim2.new(0.65,0,1,0); f.InfoLabel.Position = UDim2.new(0,5,0,0); f.InfoLabel.BackgroundTransparency = 1; f.InfoLabel.TextXAlignment = Enum.TextXAlignment.Left; f.InfoLabel.TextColor3 = Color3.fromRGB(220,220,220); f.InfoLabel.Font = Enum.Font.GothamMedium; f.InfoLabel.TextSize = 12
                local b = Instance.new("TextButton", f); b.Name = "ToggleBtn"; b.Size = UDim2.new(0.3,0,0.8,0); b.Position = UDim2.new(0.68,0,0.1,0); b.BackgroundColor3 = Color3.fromRGB(60,60,60); b.Text = "OFF"; b.TextColor3 = Color3.fromRGB(255,255,255); b.Font = Enum.Font.GothamBold; b.TextSize = 11; Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
                b.MouseButton1Click:Connect(function() oreToggleStates[name] = not oreToggleStates[name]; if oreToggleStates[name] then b.Text="ON"; b.BackgroundColor3=Color3.fromRGB(0,170,0) else b.Text="OFF"; b.BackgroundColor3=Color3.fromRGB(60,60,60) if lastScanResults[name] then updateHighlights(name, lastScanResults[name].Instances, false) end end; scanOres(); updatePaths() end)
            end
            f.InfoLabel.Text = string.format("%s - [%d]", name, info.Count)
        end
    end
    for _, c in ipairs(ScrollingFrame:GetChildren()) do if c:IsA("Frame") and not seen[c.Name:gsub("Frame_","")] then c:Destroy() end end
    ScrollingFrame.CanvasSize = UDim2.new(0,0,0,UIListLayout.AbsoluteContentSize.Y)
end

PE_Toggle.MouseButton1Click:Connect(function() playerEspEnabled = not playerEspEnabled; if playerEspEnabled then PE_Toggle.Text="ON"; PE_Toggle.BackgroundColor3=Color3.fromRGB(255,50,50) else PE_Toggle.Text="OFF"; PE_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60) end; updateEntityESP() end)
AM_Toggle.MouseButton1Click:Connect(function() autoMineEnabled = not autoMineEnabled; if autoMineEnabled then AM_Toggle.Text="ON"; AM_Toggle.BackgroundColor3=Color3.fromRGB(0,255,255); task.spawn(autoMineLoop) else AM_Toggle.Text="OFF"; AM_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60); currentMiningOre = nil; updateStatus("Idle") end end)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy(); pathVisualsFolder:Destroy(); for n, d in pairs(lastScanResults) do updateHighlights(n, d.Instances, false) end; autoMineEnabled = false end)

task.spawn(function() while true do refreshGui(); task.wait(SCAN_DELAY) end end)
