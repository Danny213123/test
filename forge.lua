--[[ 
    ORE SCANNER + PATHFINDING + AUTO MINE + AUTO ATTACK (Ultimate Version v1.56)
    - v1.56 UPDATE: Added "Visuals" Toggle (Hide/Show all ESP/Radius/Paths).
    - v1.56 UPDATE: Added 60s Idle/Stuck Reset.
        - If character doesn't move >2 studs for 60s, it resets (BreakJoints).
        - Status label shows countdown when stuck for >5s.
    - v1.56 UPDATE: Fixed Player ESP Blinking (Optimized update logic).
    - v1.55 UPDATE: Restored Lenient Obstacle Checks.
    - v1.54 UPDATE: Fixed "Unreachable" for close ores + 3D Radius Visuals.
    - Scans for ores in the "Rocks" folder
    - FEATURE: Player ESP Toggle & AUTO MINE Toggle & VISUALS Toggle
    - FEATURE: AUTO COMBAT (Switches to Sword if mob nearby)
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
local SCAN_DELAY = 0.2 
local MINING_RADIUS = 12.0          
local PLAYER_DETECTION_RADIUS = 45  
local SURFACE_STOP_DISTANCE = 3.5   
local COMBAT_RADIUS = 15 
local HIGHLIGHT_LIMIT = 30 

-- TIMEOUT SETTINGS
local ORE_BLACKLIST_DURATION = 300 
local MAX_COMBAT_TIME = 15        
local COMBAT_BLACKLIST_DURATION = 60 
local TIMEOUT_PROXIMITY_THRESHOLD = 40 
local IDLE_RESET_TIME = 60 -- Seconds before resetting character if stuck

local activeHighlights = {} 
local oreToggleStates = {} 
local orePriorityList = {} 
local lastScanResults = {} 

local oreBlacklist = {} 
local mobBlacklist = {} 

local playerEspEnabled = false 
local autoMineEnabled = false 
local visualsEnabled = true -- v1.56: New Toggle State
local currentMiningOre = nil 
local currentOreStartTime = 0 
local currentMaxTime = 60 
local lastOreHealth = 0   

local currentCombatTarget = nil
local currentCombatStartTime = 0

local lastPathUpdate = 0 
local lastRespawnTime = 0 

-- Idle Monitor State (v1.56)
local lastIdlePos = Vector3.new(0,0,0)
local lastIdleTime = tick()

-- UI States
local isTargetDropdownOpen = false 
local isPriorityDropdownOpen = false

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
MainFrame.Size = UDim2.new(0, 260, 0, 640) -- Slightly taller
MainFrame.Position = UDim2.new(0.8, 0, 0.1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true 
MainFrame.Parent = ScreenGui
makeDraggable(MainFrame)

local UICorner = Instance.new("UICorner"); UICorner.Parent = MainFrame
local Title = Instance.new("TextLabel"); Title.Size = UDim2.new(1, 0, 0, 30); Title.BackgroundTransparency = 1; Title.Text = "v1.56 Ore Scanner"; Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.Font = Enum.Font.GothamBold; Title.TextSize = 16; Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton"); CloseBtn.Name = "CloseButton"; CloseBtn.Size = UDim2.new(0, 30, 0, 30); CloseBtn.Position = UDim2.new(1, -30, 0, 0); CloseBtn.BackgroundTransparency = 1; CloseBtn.Text = "X"; CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200); CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 18; CloseBtn.ZIndex = 10; CloseBtn.Parent = MainFrame

-- Controls Container
local ControlsContainer = Instance.new("Frame"); ControlsContainer.Name = "Controls"; ControlsContainer.Size = UDim2.new(1, 0, 0, 110); ControlsContainer.Position = UDim2.new(0, 0, 0, 35); ControlsContainer.BackgroundTransparency = 1; ControlsContainer.Parent = MainFrame

local function createControl(name, yPos, text, color)
    local f = Instance.new("Frame"); f.Name = name; f.Size = UDim2.new(1, -10, 0, 30); f.Position = UDim2.new(0, 5, 0, yPos); f.BackgroundColor3 = Color3.fromRGB(35, 35, 35); f.Parent = ControlsContainer
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(0.65, 0, 1, 0); l.Position = UDim2.new(0, 5, 0, 0); l.BackgroundTransparency = 1; l.Text = text; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextColor3 = color; l.Font = Enum.Font.GothamBold; l.TextSize = 13; l.Parent = f
    local b = Instance.new("TextButton"); b.Size = UDim2.new(0.3, 0, 0.8, 0); b.Position = UDim2.new(0.68, 0, 0.1, 0); b.BackgroundColor3 = Color3.fromRGB(60, 60, 60); b.Text = "OFF"; b.TextColor3 = Color3.fromRGB(255, 255, 255); b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.Parent = f
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local PE_Toggle = createControl("PlayerESP_Control", 0, "Player ESP", Color3.fromRGB(255, 80, 80))
local AM_Toggle = createControl("AutoMine_Control", 35, "Auto Mine/Attack", Color3.fromRGB(80, 255, 255))
-- v1.56: Visuals Toggle
local VS_Toggle = createControl("Visuals_Control", 70, "Visuals", Color3.fromRGB(255, 200, 80))
VS_Toggle.Text = "ON"; VS_Toggle.BackgroundColor3 = Color3.fromRGB(255, 150, 0) -- Default ON

-- === DROPDOWNS ===
local TargetHeader = Instance.new("Frame"); TargetHeader.Size = UDim2.new(1, -10, 0, 25); TargetHeader.Position = UDim2.new(0, 5, 0, 150); TargetHeader.BackgroundColor3 = Color3.fromRGB(45, 45, 45); TargetHeader.Parent = MainFrame; Instance.new("UICorner", TargetHeader).CornerRadius = UDim.new(0, 4)
local TargetBtn = Instance.new("TextButton"); TargetBtn.Size = UDim2.new(1, 0, 1, 0); TargetBtn.BackgroundTransparency = 1; TargetBtn.Text = "Target Selection ▼"; TargetBtn.TextColor3 = Color3.fromRGB(200, 200, 200); TargetBtn.Font = Enum.Font.GothamBold; TargetBtn.TextSize = 12; TargetBtn.Parent = TargetHeader

local TargetList = Instance.new("ScrollingFrame"); TargetList.Name = "TargetList"; TargetList.Size = UDim2.new(1, -10, 0, 0); TargetList.Position = UDim2.new(0, 5, 0, 180); TargetList.BackgroundTransparency = 1; TargetList.ScrollBarThickness = 2; TargetList.Visible = false; TargetList.Parent = MainFrame
local TargetLayout = Instance.new("UIListLayout"); TargetLayout.Padding = UDim.new(0, 2); TargetLayout.SortOrder = Enum.SortOrder.Name; TargetLayout.Parent = TargetList

TargetBtn.MouseButton1Click:Connect(function()
    isTargetDropdownOpen = not isTargetDropdownOpen
    TargetList.Visible = isTargetDropdownOpen
    if isTargetDropdownOpen then TargetList.Size = UDim2.new(1, -10, 0, 120); TargetBtn.Text = "Target Selection ▼"
    else TargetList.Size = UDim2.new(1, -10, 0, 0); TargetBtn.Text = "Target Selection ▶" end
end)

local PriorityHeader = Instance.new("Frame"); PriorityHeader.Name = "PriorityHeader"; PriorityHeader.Size = UDim2.new(1, -10, 0, 25); PriorityHeader.Position = UDim2.new(0, 5, 0, 305); PriorityHeader.BackgroundColor3 = Color3.fromRGB(45, 45, 45); PriorityHeader.Parent = MainFrame; Instance.new("UICorner", PriorityHeader).CornerRadius = UDim.new(0, 4)
local PriorityBtn = Instance.new("TextButton"); PriorityBtn.Name = "PriorityBtn"; PriorityBtn.Size = UDim2.new(1, 0, 1, 0); PriorityBtn.BackgroundTransparency = 1; PriorityBtn.Text = "Priority Reorder ▶"; PriorityBtn.TextColor3 = Color3.fromRGB(200, 200, 200); PriorityBtn.Font = Enum.Font.GothamBold; PriorityBtn.TextSize = 12; PriorityBtn.Parent = PriorityHeader

local PriorityList = Instance.new("ScrollingFrame"); PriorityList.Name = "PriorityList"; PriorityList.Size = UDim2.new(1, -10, 0, 0); PriorityList.Position = UDim2.new(0, 5, 0, 335); PriorityList.BackgroundTransparency = 1; PriorityList.ScrollBarThickness = 2; PriorityList.Visible = false; PriorityList.Parent = MainFrame
local PriorityLayout = Instance.new("UIListLayout"); PriorityLayout.Padding = UDim.new(0, 2); PriorityLayout.SortOrder = Enum.SortOrder.LayoutOrder; PriorityLayout.Parent = PriorityList

PriorityBtn.MouseButton1Click:Connect(function()
    isPriorityDropdownOpen = not isPriorityDropdownOpen
    PriorityList.Visible = isPriorityDropdownOpen
    if isPriorityDropdownOpen then PriorityList.Size = UDim2.new(1, -10, 0, 120); PriorityBtn.Text = "Priority Reorder ▼"
    else PriorityList.Size = UDim2.new(1, -10, 0, 0); PriorityBtn.Text = "Priority Reorder ▶" end
end)

-- FOOTER (Status & Debug)
local StatusLabel = Instance.new("TextLabel"); StatusLabel.Name = "StatusLabel"; StatusLabel.Size = UDim2.new(1, -10, 0, 20); StatusLabel.Position = UDim2.new(0, 5, 0, 465); StatusLabel.BackgroundTransparency = 0.8; StatusLabel.BackgroundColor3 = Color3.new(0,0,0); StatusLabel.Text = "Status: Idle"; StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200); StatusLabel.Font = Enum.Font.Gotham; StatusLabel.TextSize = 11; StatusLabel.Parent = MainFrame

local DebugFrame = Instance.new("ScrollingFrame"); DebugFrame.Name = "DebugConsole"; DebugFrame.Size = UDim2.new(1, -10, 0, 130); DebugFrame.Position = UDim2.new(0, 5, 0, 490); DebugFrame.BackgroundTransparency = 0.5; DebugFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10); DebugFrame.ScrollBarThickness = 2; DebugFrame.Parent = MainFrame
local DebugLayout = Instance.new("UIListLayout"); DebugLayout.Padding = UDim.new(0, 2); DebugLayout.Parent = DebugFrame
DebugLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() DebugFrame.CanvasSize = UDim2.new(0, 0, 0, DebugLayout.AbsoluteContentSize.Y); DebugFrame.CanvasPosition = Vector2.new(0, DebugLayout.AbsoluteContentSize.Y) end)

local function logDebug(msg)
    local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1, 0, 0, 12); lbl.BackgroundTransparency = 1; lbl.Text = "["..os.date("%X").."] " .. msg; lbl.TextColor3 = Color3.fromRGB(150, 150, 150); lbl.Font = Enum.Font.Code; lbl.TextSize = 10; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = DebugFrame
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

local function isPathBlockedByObstacle(character)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character, existingFolder} 
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local direction = root.CFrame.LookVector * 1.1
    local result = Workspace:Raycast(root.Position, direction, rayParams)
    
    if result and result.Instance.CanCollide then
        if result.Instance:IsDescendantOf(Workspace:FindFirstChild("Rocks")) then return false end
        if result.Position.Y < root.Position.Y - 1.5 then return false end
        
        return true 
    end
    return false
end

local function hasLineOfSight(startPos, endPos, ignoreList)
    local diff = endPos - startPos
    local dir = diff.Unit
    local dist = diff.Magnitude
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = ignoreList or {}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local result = Workspace:Raycast(startPos, dir * dist, params)
    return result == nil 
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
    
    if distance < 8 then return true end

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
    local h = tonumber(ore:GetAttribute("Health"))
    local m = tonumber(ore:GetAttribute("MaxHealth"))
    if h and m then
        return h >= m
    end
    return true
end

local function movePriority(oreName, direction)
    local idx = table.find(orePriorityList, oreName)
    if not idx then return end
    if direction == -1 and idx > 1 then
        table.remove(orePriorityList, idx); table.insert(orePriorityList, idx - 1, oreName)
    elseif direction == 1 and idx < #orePriorityList then
        table.remove(orePriorityList, idx); table.insert(orePriorityList, idx + 1, oreName)
    end
end

local function setTarget(ore)
    currentMiningOre = ore
    currentOreStartTime = tick()
    local h = ore:GetAttribute("Health")
    lastOreHealth = h or 999999
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local dist = 100
    if root and ore then
        local pos = getOrePosition(ore)
        if pos then dist = (root.Position - pos).Magnitude end
    end
    local travelTime = (dist / 12) + 20 
    currentMaxTime = travelTime
    StatusLabel.Text = "Status: Target " .. ore.Name .. " ("..math.floor(travelTime).."s)"
    logDebug("Target set: " .. ore.Name .. " (Dist: " .. math.floor(dist) .. ")")
end

local function getOreStatus(ore)
    if ore == currentMiningOre then return "GREEN" end

    local orePos = getOrePosition(ore)
    if not orePos then return "RED" end
    local isFull = isOreFullHealth(ore)
    local playerNearby = false
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local targetPart = player.Character.PrimaryPart or player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("Head")
            if targetPart then
                local dist = (targetPart.Position - orePos).Magnitude
                if dist <= PLAYER_DETECTION_RADIUS then playerNearby = true; break end
            end
        end
    end
    if playerNearby then 
        if not isFull then return "RED" else return "YELLOW" end
    else 
        return "GREEN" 
    end
end

local function isValidOre(ore)
    if oreBlacklist[ore] and (tick() - oreBlacklist[ore] < ORE_BLACKLIST_DURATION) then return false end
    if not ore.Parent then return false end
    local status = getOreStatus(ore)
    if status == "RED" then return false end 
    return true
end

-- 4. COMBAT & TOOL
local function equipToolByName(toolName)
    local char = LocalPlayer.Character; if not char then return end
    local hum = char:FindFirstChild("Humanoid"); if not hum then return end
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
    if tool then hum:EquipTool(tool) end
end
local function equipPickaxe() equipToolByName("Pickaxe") end
local function equipSword() equipToolByName("Sword"); if not LocalPlayer.Character:FindFirstChild("Sword") then equipToolByName("Weapon") end end
local function mineTarget(ore) pcall(function() ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer("Pickaxe") end) end
local function attackTargetMob(mob) pcall(function() ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer("Weapon") end) end
local function faceTarget(pos)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pos.X, root.Position.Y, pos.Z)) end
end

local function getNearbyMob()
    local char = LocalPlayer.Character; if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return nil end
    local living = Workspace:FindFirstChild("Living"); if not living then return nil end
    local closestMob = nil; local closestDist = COMBAT_RADIUS 
    for _, model in ipairs(living:GetChildren()) do
        if model:IsA("Model") and model ~= char then
            if mobBlacklist[model] and (tick() - mobBlacklist[model] < COMBAT_BLACKLIST_DURATION) then continue end
            if not Players:FindFirstChild(model.Name) then
                if not model:FindFirstChild("MobBox") then continue end 
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

-- 6. AUTO LOOP
local function getBestOre()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); if not root then return nil end
    logDebug("--- Scanning (Priority Mode) ---")
    
    for _, oreName in ipairs(orePriorityList) do
        if oreToggleStates[oreName] and lastScanResults[oreName] then
            local greenCandidates = {}; local yellowCandidates = {}; local count = 0
            for _, ore in ipairs(lastScanResults[oreName].Instances) do
                if isValidOre(ore) then
                    local pos = getOrePosition(ore)
                    if pos then
                        local dist = (root.Position - pos).Magnitude
                        local status = getOreStatus(ore)
                        local entry = {Ore = ore, Pos = pos, Dist = dist}
                        if status == "GREEN" then table.insert(greenCandidates, entry) else table.insert(yellowCandidates, entry) end
                        count = count + 1
                    end
                end
            end
            
            if count > 0 then
                local function selectFromList(list, label)
                    table.sort(list, function(a, b) return a.Dist < b.Dist end)
                    local best = nil
                    local checkLimit = math.min(20, #list) 
                    
                    for i = 1, checkLimit do
                        if getNearbyMob() then 
                            logDebug("Scan Aborted: Enemy Nearby!")
                            return nil 
                        end 
                        local entry = list[i]
                        
                        if entry.Dist < 60 and isSafeToWalk(entry.Pos) and hasLineOfSight(root.Position, entry.Pos, {LocalPlayer.Character, entry.Ore}) then
                            logDebug("Instant Match (LoS): " .. entry.Ore.Name)
                            return entry.Ore
                        end

                        StatusLabel.Text = string.format("Pathing: %s (%d/%d)...", entry.Ore.Name, i, checkLimit)
                        local path = PathfindingService:CreatePath({AgentRadius = 2.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water = 20 }})
                        local success = pcall(function() path:ComputeAsync(root.Position, entry.Pos) end)
                        if success and path.Status == Enum.PathStatus.Success then
                            return entry.Ore
                        end
                        if i % 2 == 0 then task.wait() end 
                    end
                    
                    if not best and #list > 0 then 
                        local closest = list[1]
                        local veryClose = closest.Dist < 20
                        if veryClose or (closest.Dist < 45 and isSafeToWalk(closest.Pos)) then 
                            best = closest.Ore 
                            logDebug("Fallback used for " .. best.Name)
                        else
                            logDebug("Ore " .. closest.Ore.Name .. " rejected: Unsafe / No LOS")
                        end 
                    end
                    return best
                end

                local found = selectFromList(greenCandidates, "Green")
                if found then logDebug("Priority Hit: " .. oreName); return found end
                found = selectFromList(yellowCandidates, "Yellow")
                if found then logDebug("Priority Hit (Yellow): " .. oreName); return found end
            end
        end
    end
    logDebug("No reachable ores found.")
    StatusLabel.Text = "Status: Scan Failed (No Paths)"
    return nil
end

local function updateStatus(text) StatusLabel.Text = "Status: " .. text end

local function autoMineLoop()
    logDebug("Auto System Started")
    
    -- Reset idle timer on start
    lastIdleTime = tick()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then lastIdlePos = root.Position end

    while autoMineEnabled do
        local success, err = pcall(function()
            local char = LocalPlayer.Character
            if not char then task.wait(0.5); return end
            local hum = char:FindFirstChild("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            if not hum or not root or hum.Health <= 0 then task.wait(0.5); return end

            -- v1.56: IDLE/STUCK RESET MONITOR
            if (root.Position - lastIdlePos).Magnitude > 2 then
                lastIdlePos = root.Position
                lastIdleTime = tick()
            else
                local idleTime = tick() - lastIdleTime
                if idleTime > IDLE_RESET_TIME then
                    logDebug("IDLE TIMEOUT: Resetting Character...")
                    char:BreakJoints() -- Reset
                    lastIdleTime = tick() -- Prevent double reset
                    task.wait(2)
                    return
                elseif idleTime > 5 then
                     StatusLabel.Text = "Status: STUCK! Resetting in " .. math.ceil(IDLE_RESET_TIME - idleTime) .. "s..."
                end
            end

            -- Respawn Timer
            if tick() - lastRespawnTime < 10 then
                StatusLabel.Text = "Status: Waiting for Cannon (" .. math.ceil(10 - (tick() - lastRespawnTime)) .. "s)"
                task.wait(0.5)
                return
            end
            
            -- COMBAT
            local nearbyMob = getNearbyMob()
            if nearbyMob then
                if nearbyMob ~= currentCombatTarget then currentCombatTarget = nearbyMob; currentCombatStartTime = tick() end
                if tick() - currentCombatStartTime > MAX_COMBAT_TIME then
                    mobBlacklist[nearbyMob] = tick(); currentCombatTarget = nil
                else
                    updateStatus("COMBAT: Attacking " .. nearbyMob.Name)
                    if not char:FindFirstChild("Sword") and not char:FindFirstChild("Weapon") then equipSword() end
                    local mobPos = nearbyMob:GetPivot().Position
                    hum:MoveTo(root.Position); faceTarget(mobPos); attackTargetMob(nearbyMob)
                    if (root.Position - mobPos).Magnitude > 5 then hum:MoveTo(mobPos) end
                    task.wait(0.1); return
                end
            else
                currentCombatTarget = nil
            end
            
            -- IMMEDIATE NEARBY ORE
            local foundNearby = false
            if currentMiningOre and isValidOre(currentMiningOre) then
                local p = getOrePosition(currentMiningOre)
                if p and (root.Position - p).Magnitude <= MINING_RADIUS then foundNearby = true end
            end

            if currentMiningOre then
                local currentH = currentMiningOre:GetAttribute("Health") or 0
                if currentH < lastOreHealth then lastOreHealth = currentH; currentOreStartTime = tick(); currentMaxTime = 30 end
                local distToOre = 9999; local oreP = getOrePosition(currentMiningOre)
                if oreP then distToOre = (root.Position - oreP).Magnitude end

                if not currentMiningOre.Parent then logDebug("Ore lost."); currentMiningOre = nil
                elseif tick() - currentOreStartTime > currentMaxTime then 
                    if distToOre < TIMEOUT_PROXIMITY_THRESHOLD then logDebug("TIMEOUT (Near): Blacklisting " .. currentMiningOre.Name); oreBlacklist[currentMiningOre] = tick(); currentMiningOre = nil 
                    else currentOreStartTime = tick() end
                elseif getOreStatus(currentMiningOre) == "RED" then logDebug("Target became BLOCKED."); currentMiningOre = nil end
            end

            if not currentMiningOre then 
                updateStatus("Scanning..."); 
                local best = getBestOre()
                if best then setTarget(best) else task.wait(1) end 
            end
            
            local targetOre = currentMiningOre
            if targetOre then
                local targetPos = getOrePosition(targetOre)
                if targetPos then
                    local surfaceDist = getSurfaceDistance(root, targetOre)
                    local centerDist = (root.Position - targetPos).Magnitude
                    
                    if centerDist <= MINING_RADIUS or surfaceDist <= SURFACE_STOP_DISTANCE + 1.0 then
                        if getOreStatus(targetOre) == "RED" then
                             logDebug("Target occupied! Aborting."); currentMiningOre = nil; return
                        end

                        updateStatus("Mining " .. targetOre.Name)
                        hum:MoveTo(root.Position) 
                        if not char:FindFirstChild("Pickaxe") then equipPickaxe() end
                        faceTarget(targetPos); mineTarget(targetOre); task.wait(0.1)
                    else
                        updateStatus("Moving to " .. targetOre.Name)
                        local path = PathfindingService:CreatePath({AgentRadius = 2.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water = 20 }})
                        local success = pcall(function() path:ComputeAsync(root.Position, targetPos) end)
                        
                        if success and path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            local pathBlocked = false
                            local blockedConn; blockedConn = path.Blocked:Connect(function() logDebug("PATH BLOCKED"); pathBlocked = true end)

                            for i, wp in ipairs(waypoints) do
                                if i == 1 then continue end
                                if pathBlocked then break end
                                
                                if not autoMineEnabled or not currentMiningOre or not currentMiningOre.Parent then break end
                                if getNearbyMob() then break end
                                if tick() - currentOreStartTime > currentMaxTime then break end
                                if hum.Health <= 0 then break end
                                if getOreStatus(targetOre) == "RED" then break end

                                if i % 15 == 0 then 
                                    local potentialNewTarget = getBestOre()
                                    if potentialNewTarget and potentialNewTarget ~= currentMiningOre then
                                        updateStatus("Found higher priority target!"); setTarget(potentialNewTarget); break
                                    end
                                end

                                if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then hum:MoveTo(root.Position); break end

                                updateStatus("Moving to " .. targetOre.Name)
                                if wp.Action == Enum.PathWaypointAction.Jump then 
                                    if wp.Position.Y >= root.Position.Y - 3.0 then hum:ChangeState(Enum.HumanoidStateType.Jumping); hum.Jump = true end
                                end
                                
                                local moveSuccess = false
                                local connection = hum.MoveToFinished:Connect(function() moveSuccess = true end)
                                hum:MoveTo(wp.Position)
                                
                                local timeElapsed = 0; local timeout = 1.0
                                local lastMovePos = root.Position

                                while not moveSuccess and timeElapsed < timeout do
                                    if not autoMineEnabled then break end
                                    if pathBlocked then break end
                                    if hum.Health <= 0 then break end
                                    if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then moveSuccess = true; break end
                                    if getNearbyMob() then moveSuccess = true; break end 
                                    
                                    if isPathBlockedByObstacle(char) then
                                        logDebug("OBSTACLE: Hitting Wall! Switching target...")
                                        oreBlacklist[targetOre] = tick() + 10 
                                        currentMiningOre = nil
                                        pathBlocked = true; moveSuccess = true; break
                                    end

                                    if root.Velocity.Magnitude < 0.1 and timeElapsed > 0.5 then
                                        if (root.Position - targetPos).Magnitude < 15 then
                                             logDebug("STUCK but close: Forcing Mine...")
                                             equipPickaxe(); faceTarget(targetPos); mineTarget(targetOre)
                                             moveSuccess = true; break
                                        else
                                            hum:ChangeState(Enum.HumanoidStateType.Jumping); hum.Jump = true
                                            if timeElapsed > 0.8 then 
                                                logDebug("STUCK (Pos): Switching target...")
                                                oreBlacklist[targetOre] = tick() + 10 
                                                currentMiningOre = nil
                                                moveSuccess = true; pathBlocked = true
                                            end
                                        end
                                    end 
                                    task.wait(0.1); timeElapsed = timeElapsed + 0.1
                                end
                                if connection then connection:Disconnect() end
                            end
                            if blockedConn then blockedConn:Disconnect() end
                        else
                            if isSafeToWalk(targetPos) and hasLineOfSight(root.Position, targetPos, {char, targetOre}) then
                                if surfaceDist > SURFACE_STOP_DISTANCE then
                                    hum:MoveTo(targetPos)
                                    local timeElapsed = 0
                                    while timeElapsed < 0.5 do
                                        if hum.Health <= 0 then break end
                                        if getSurfaceDistance(root, targetOre) <= SURFACE_STOP_DISTANCE then hum:MoveTo(root.Position); break end
                                        task.wait(0.1); timeElapsed = timeElapsed + 0.1
                                    end
                                end
                            else
                                logDebug("Path failed & No LOS: Blacklisting " .. targetOre.Name)
                                oreBlacklist[targetOre] = tick() + 5; currentMiningOre = nil
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
        end)
        
        if not success then
            warn("AutoMine Error: " .. tostring(err))
            task.wait(1)
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
    
    -- v1.56: Reset idle time on respawn
    lastIdleTime = tick()
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
    lastRespawnTime = tick() 
    logDebug("Respawn detected. Waiting 10s for cannon...")
    local hum = char:WaitForChild("Humanoid", 10)
    local root = char:WaitForChild("HumanoidRootPart", 10)
    if hum and root then 
        hum.Died:Connect(resetState)
        enableAnimations(char)
    else
        logDebug("Character load failed (Incomplete)")
    end
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end

-- 8. ENTITY ESP & HIGHLIGHTS
local function updateEntityESP()
    -- v1.56: If visuals disabled, cleanup and return
    if not visualsEnabled then 
        local living = Workspace:FindFirstChild("Living")
        if living then
            for _, model in ipairs(living:GetChildren()) do
                if model:FindFirstChild("PlayerBox") then model.PlayerBox:Destroy() end
                if model:FindFirstChild("PlayerTag") then model.PlayerTag:Destroy() end
                if model:FindFirstChild("MobBox") then model.MobBox:Destroy() end
            end
        end
        return 
    end

    local living = Workspace:FindFirstChild("Living"); if not living then return end
    local char = LocalPlayer.Character; local root = char and char:FindFirstChild("HumanoidRootPart")
    
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
    -- v1.56: If visuals disabled, destroy all highlights
    if not visualsEnabled then
        for _, model in ipairs(instances) do
            if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end
            if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end
            if model:FindFirstChild("OreStatusRadius") then model.OreStatusRadius:Destroy() end
        end
        return
    end

    if isEnabled then
        local count = 0; local sortedInstances = {}; local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            for _, model in ipairs(instances) do local pos = getOrePosition(model); if pos then table.insert(sortedInstances, {model = model, dist = (root.Position - pos).Magnitude}) end end
            table.sort(sortedInstances, function(a, b) return a.dist < b.dist end)
        end
        for _, entry in ipairs(sortedInstances) do
            local model = entry.model; count = count + 1
            if count > HIGHLIGHT_LIMIT then if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end; if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end; if model:FindFirstChild("OreStatusRadius") then model.OreStatusRadius:Destroy() end; continue end
            if model:IsA("Model") or model:IsA("BasePart") then
                local pos = getOrePosition(model); local status = getOreStatus(model); local radiusColor = Color3.fromRGB(50, 255, 50)
                local statusColor = Color3.fromRGB(0, 255, 0)
                if status == "RED" then statusColor = Color3.fromRGB(255, 0, 0); radiusColor = Color3.fromRGB(255, 0, 0) elseif status == "YELLOW" then statusColor = Color3.fromRGB(255, 255, 0); radiusColor = Color3.fromRGB(255, 255, 0) end
                
                if model == currentMiningOre then radiusColor = Color3.fromRGB(0, 255, 255) end

                if not model:FindFirstChild("OreHighlight") then local h = Instance.new("Highlight", model); h.Name = "OreHighlight"; h.Adornee = model; h.FillColor = Color3.fromRGB(0, 255, 0); h.FillTransparency = 0.5 end
                local adornment = model:FindFirstChild("OreRadiusVisual")
                if not adornment then adornment = Instance.new("SphereHandleAdornment", model); adornment.Name = "OreRadiusVisual"; local center = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model; if center then adornment.Adornee = center; adornment.AlwaysOnTop = true; adornment.Transparency = 0.7 end end
                if adornment then adornment.Radius = MINING_RADIUS; adornment.Color3 = radiusColor end

                -- v1.54: PLAYER DETECTION RADIUS VISUAL (3D Sphere Bubble)
                local statusRad = model:FindFirstChild("OreStatusRadius")
                if not statusRad then 
                    statusRad = Instance.new("SphereHandleAdornment", model); statusRad.Name = "OreStatusRadius"; statusRad.Height = 1; statusRad.Transparency = 0.8; statusRad.AlwaysOnTop = true
                    local center = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model
                    if center then statusRad.Adornee = center; statusRad.CFrame = CFrame.new(0, 0, 0) end
                end
                statusRad.Radius = PLAYER_DETECTION_RADIUS
                statusRad.Color3 = statusColor
            end
        end
    else
        for _, model in ipairs(instances) do if model:FindFirstChild("OreHighlight") then model.OreHighlight:Destroy() end; if model:FindFirstChild("OreRadiusVisual") then model.OreRadiusVisual:Destroy() end; if model:FindFirstChild("OreStatusRadius") then model.OreStatusRadius:Destroy() end end
    end
end

local function updatePaths()
    if tick() - lastPathUpdate < 2.0 then return end
    lastPathUpdate = tick()
    pathVisualsFolder:ClearAllChildren()
    
    if not visualsEnabled then return end -- v1.56: Respect toggle

    local char = LocalPlayer.Character; if not char then return end; local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end; local startPos = root.Position
    for oreName, isEnabled in pairs(oreToggleStates) do
        if isEnabled and lastScanResults[oreName] then
            local sortedOres = {}
            for _, ore in ipairs(lastScanResults[oreName].Instances) do if isValidOre(ore) then local p = getOrePosition(ore); table.insert(sortedOres, {Ore = ore, Pos = p, Dist = (startPos - p).Magnitude}) end end
            table.sort(sortedOres, function(a,b) return a.Dist < b.Dist end)
            for i = 1, math.min(10, #sortedOres) do
                local entry = sortedOres[i]
                task.spawn(function()
                    local path = PathfindingService:CreatePath({AgentRadius = 3.0, AgentHeight = 4.0, AgentCanJump = true, Costs = { Water=20, [Enum.Material.Air]=4 }})
                    local s = pcall(function() path:ComputeAsync(startPos, entry.Pos) end)
                    if s and path.Status == Enum.PathStatus.Success then
                        for _, wp in ipairs(path:GetWaypoints()) do
                            local n = Instance.new("Part"); n.Shape = Enum.PartType.Ball; n.Size = Vector3.new(0.5,0.5,0.5); n.Material = Enum.Material.Neon; n.Anchored = true; n.CanCollide = false; n.Position = wp.Position; n.Parent = pathVisualsFolder
                            if wp.Action == Enum.PathWaypointAction.Jump then n.Color = Color3.fromRGB(170,0,255) else n.Color = Color3.fromRGB(0,255,255) end
                        end
                    end
                end)
            end
        end
    end
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
                if pos then 
                    local n = descendant.Name
                    if not current[n] then current[n] = {Count=0, Instances={}}; if not table.find(orePriorityList, n) then table.insert(orePriorityList, n) end end
                    table.insert(current[n].Instances, descendant)
                    current[n].Count = current[n].Count + 1 
                end
            end
        end
    end
    lastScanResults = current
    for n, d in pairs(current) do if oreToggleStates[n] then updateHighlights(n, d.Instances, true) end end
    return current
end

local function refreshGui()
    local data = scanOres(); updateEntityESP(); updatePaths()
    local targetSeen = {}
    if data then
        for name, info in pairs(data) do
            targetSeen[name] = true; local fname = "Frame_"..name; local f = TargetList:FindFirstChild(fname)
            if not f then
                f = Instance.new("Frame"); f.Name = fname; f.Size = UDim2.new(1,-5,0,30); f.BackgroundColor3 = Color3.fromRGB(40,40,40); f.Parent = TargetList; Instance.new("UICorner", f).CornerRadius = UDim.new(0,4)
                Instance.new("TextLabel", f).Name = "InfoLabel"; f.InfoLabel.Size = UDim2.new(0.65,0,1,0); f.InfoLabel.Position = UDim2.new(0,5,0,0); f.InfoLabel.BackgroundTransparency = 1; f.InfoLabel.TextXAlignment = Enum.TextXAlignment.Left; f.InfoLabel.TextColor3 = Color3.fromRGB(220,220,220); f.InfoLabel.Font = Enum.Font.GothamMedium; f.InfoLabel.TextSize = 12
                local b = Instance.new("TextButton", f); b.Name = "ToggleBtn"; b.Size = UDim2.new(0.3,0,0.8,0); b.Position = UDim2.new(0.68,0,0.1,0); b.BackgroundColor3 = Color3.fromRGB(60,60,60); b.Text = "OFF"; b.TextColor3 = Color3.fromRGB(255,255,255); b.Font = Enum.Font.GothamBold; b.TextSize = 11; Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
                b.MouseButton1Click:Connect(function() oreToggleStates[name] = not oreToggleStates[name]; if oreToggleStates[name] then b.Text="ON"; b.BackgroundColor3=Color3.fromRGB(0,170,0) else b.Text="OFF"; b.BackgroundColor3=Color3.fromRGB(60,60,60) if lastScanResults[name] then updateHighlights(name, lastScanResults[name].Instances, false) end end; scanOres(); updatePaths() end)
            end
            f.InfoLabel.Text = string.format("%s - [%d]", name, info.Count)
        end
    end
    for _, c in ipairs(TargetList:GetChildren()) do if c:IsA("Frame") and not targetSeen[c.Name:gsub("Frame_","")] then c:Destroy() end end
    TargetList.CanvasSize = UDim2.new(0,0,0,TargetLayout.AbsoluteContentSize.Y)

    local prioritySeen = {}
    for i, name in ipairs(orePriorityList) do
        prioritySeen[name] = true; local fname = "PFrame_"..name; local f = PriorityList:FindFirstChild(fname)
        if not f then
            f = Instance.new("Frame"); f.Name = fname; f.Size = UDim2.new(1,-5,0,30); f.BackgroundColor3 = Color3.fromRGB(40,40,40); f.Parent = PriorityList; Instance.new("UICorner", f).CornerRadius = UDim.new(0,4)
            Instance.new("TextLabel", f).Name = "NameLabel"; f.NameLabel.Size = UDim2.new(0.6,0,1,0); f.NameLabel.Position = UDim2.new(0,5,0,0); f.NameLabel.BackgroundTransparency = 1; f.NameLabel.TextXAlignment = Enum.TextXAlignment.Left; f.NameLabel.TextColor3 = Color3.fromRGB(220,220,220); f.NameLabel.Font = Enum.Font.GothamMedium; f.NameLabel.TextSize = 12
            local bUp = Instance.new("TextButton", f); bUp.Name = "UpBtn"; bUp.Size = UDim2.new(0.15,0,0.8,0); bUp.Position = UDim2.new(0.62,0,0.1,0); bUp.BackgroundColor3 = Color3.fromRGB(60,60,60); bUp.Text = "▲"; bUp.TextColor3 = Color3.fromRGB(255,255,255); bUp.Font = Enum.Font.GothamBold; bUp.TextSize = 10; Instance.new("UICorner", bUp).CornerRadius = UDim.new(0,4)
            bUp.MouseButton1Click:Connect(function() movePriority(name, -1); refreshGui() end)
            local bDown = Instance.new("TextButton", f); bDown.Name = "DownBtn"; bDown.Size = UDim2.new(0.15,0,0.8,0); bDown.Position = UDim2.new(0.8,0,0.1,0); bDown.BackgroundColor3 = Color3.fromRGB(60,60,60); bDown.Text = "▼"; bDown.TextColor3 = Color3.fromRGB(255,255,255); bDown.Font = Enum.Font.GothamBold; bDown.TextSize = 10; Instance.new("UICorner", bDown).CornerRadius = UDim.new(0,4)
            bDown.MouseButton1Click:Connect(function() movePriority(name, 1); refreshGui() end)
        end
        f.LayoutOrder = i; f.NameLabel.Text = string.format("%d. %s", i, name)
    end
    for _, c in ipairs(PriorityList:GetChildren()) do if c:IsA("Frame") and not prioritySeen[c.Name:gsub("PFrame_","")] then c:Destroy() end end
    PriorityList.CanvasSize = UDim2.new(0,0,0,PriorityLayout.AbsoluteContentSize.Y)
end

PE_Toggle.MouseButton1Click:Connect(function() playerEspEnabled = not playerEspEnabled; if playerEspEnabled then PE_Toggle.Text="ON"; PE_Toggle.BackgroundColor3=Color3.fromRGB(255,50,50) else PE_Toggle.Text="OFF"; PE_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60) end; updateEntityESP() end)
AM_Toggle.MouseButton1Click:Connect(function() autoMineEnabled = not autoMineEnabled; if autoMineEnabled then AM_Toggle.Text="ON"; AM_Toggle.BackgroundColor3=Color3.fromRGB(0,255,255); task.spawn(autoMineLoop) else AM_Toggle.Text="OFF"; AM_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60); currentMiningOre = nil; updateStatus("Idle") end end)
-- v1.56: Visuals Toggle Logic
VS_Toggle.MouseButton1Click:Connect(function() 
    visualsEnabled = not visualsEnabled
    if visualsEnabled then VS_Toggle.Text="ON"; VS_Toggle.BackgroundColor3=Color3.fromRGB(255, 150, 0)
    else VS_Toggle.Text="OFF"; VS_Toggle.BackgroundColor3=Color3.fromRGB(60,60,60) end
    -- Force update to clear/show
    if lastScanResults then 
        for n, d in pairs(lastScanResults) do 
            if oreToggleStates[n] then updateHighlights(n, d.Instances, true) end
        end 
    end
    updateEntityESP()
    updatePaths()
end)

CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy(); pathVisualsFolder:Destroy(); for n, d in pairs(lastScanResults) do updateHighlights(n, d.Instances, false) end; autoMineEnabled = false end)

task.spawn(function() while true do refreshGui(); task.wait(SCAN_DELAY) end end)
