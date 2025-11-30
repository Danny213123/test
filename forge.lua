-- Rocks Scanner (FIXED Pathfinding + Water Avoidance + Fixed ESP)
-- TYPE: LocalScript
-- LOCATION: StarterPlayer -> StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================================================================
-- CONFIGURATION
-- =========================================================================
local autoMineEnabled = false
local stealthModeEnabled = false -- Default Legit
local strictAvoidance = true 
local playerEspEnabled = false
local oreEspEnabled = false
local mobEspEnabled = false
local isCurrentlyMining = false 
local selectedTargets = {} 

-- Settings
local SIGHT_DISTANCE = 150      
local TRAVEL_DEPTH = 20         
local MINING_DEPTH = 12         
local MOVEMENT_SPEED = 35       

-- Safety Settings
local CRITICAL_MOB_DIST = 15    -- Only run away if mob is THIS close (Active Avoidance)

-- Advanced Pathfinding Settings (FIXED VALUES)
local STUCK_TIMEOUT = 4         -- Increased timeout before assuming stuck
local JUMP_THRESHOLD = 2.0 
local DIRECT_PATH_DIST = 8      -- FIXED: Was 45, now only skip pathfinding when very close
local WATER_COST = 100          -- Very high cost to avoid water
local LAVA_COST = math.huge     -- Never cross lava
local PATH_MAX_SLOPE = 75       -- Maximum slope angle
local PATH_SPACING = 4          -- Waypoint spacing for smoother paths
local PATH_RETRY_COUNT = 3      -- NEW: Number of times to retry pathfinding
local WAYPOINT_REACH_DIST = 4   -- NEW: Distance to consider waypoint reached

-- Visuals
local visualFolder = workspace:FindFirstChild("PathVisuals") or Instance.new("Folder")
visualFolder.Name = "PathVisuals"
visualFolder.Parent = workspace

local espFolder = Instance.new("Folder")
espFolder.Name = "ESPHighlights"
espFolder.Parent = CoreGui

-- Animation Tracks
local walkAnimTrack = nil
local jumpAnimTrack = nil
local noclipConnection = nil

-- Debug mode - set to true to see prints in console
local DEBUG_MODE = true

-- Water check settings
local WATER_CHECK_ENABLED = true  -- Set to false to disable water checking entirely
local WATER_CHECK_STRICT = false  -- If true, any nearby water triggers. If false, only direct water.

local function debugPrint(...)
	if DEBUG_MODE then
		print("[MinerDebug]", ...)
	end
end

-- =========================================================================
-- TERRAIN & WATER DETECTION (FIXED - Less Aggressive)
-- =========================================================================
local function isPositionInWater(position)
	-- If water checking is disabled, always return false
	if not WATER_CHECK_ENABLED then
		return false
	end
	
	local terrain = workspace.Terrain
	
	-- Method 1: Check the exact voxel at this position (most accurate)
	local voxelPos = terrain:WorldToCell(position)
	local region = Region3.new(
		terrain:CellCornerToWorld(voxelPos.X, voxelPos.Y, voxelPos.Z),
		terrain:CellCornerToWorld(voxelPos.X + 1, voxelPos.Y + 1, voxelPos.Z + 1)
	):ExpandToGrid(4)
	
	local success, materials = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	
	if not success then return false end
	
	-- Check center voxel only (not surrounding area)
	local size = materials.Size
	if size.X > 0 and size.Y > 0 and size.Z > 0 then
		-- Check the center voxel
		local centerX = math.ceil(size.X / 2)
		local centerY = math.ceil(size.Y / 2)
		local centerZ = math.ceil(size.Z / 2)
		
		local material = materials[centerX][centerY][centerZ]
		if material == Enum.Material.Water then
			debugPrint("Water detected at exact position")
			return true
		end
		
		-- If strict mode, also check if ANY voxel is water
		if WATER_CHECK_STRICT then
			for x = 1, size.X do
				for y = 1, size.Y do
					for z = 1, size.Z do
						if materials[x][y][z] == Enum.Material.Water then
							debugPrint("Water detected nearby (strict mode)")
							return true
						end
					end
				end
			end
		end
	end
	
	return false
end

-- Simpler check - is the player currently swimming?
local function isPlayerInWater()
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return false end
	
	-- Check if humanoid state is swimming
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Swimming
end

local function getTerrainMaterial(position)
	local terrain = workspace.Terrain
	
	local voxelPos = terrain:WorldToCell(position)
	local region = Region3.new(
		terrain:CellCornerToWorld(voxelPos.X, voxelPos.Y, voxelPos.Z),
		terrain:CellCornerToWorld(voxelPos.X + 1, voxelPos.Y + 1, voxelPos.Z + 1)
	):ExpandToGrid(4)
	
	local success, materials = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	
	if not success then return Enum.Material.Air end
	
	if materials.Size.X > 0 and materials.Size.Y > 0 and materials.Size.Z > 0 then
		return materials[1][1][1]
	end
	
	return Enum.Material.Air
end

-- =========================================================================
-- ADVANCED PATHFINDING (FIXED)
-- =========================================================================
local function createAdvancedPath(startPos, endPos)
	-- Create path with water avoidance and advanced settings
	local pathParams = {
		AgentRadius = 2.0,
		AgentHeight = 5.0,
		AgentCanJump = true,
		AgentCanClimb = false,
		AgentMaxSlope = PATH_MAX_SLOPE,
		WaypointSpacing = PATH_SPACING,
		Costs = {
			Water = WATER_COST,
			CrackedLava = LAVA_COST,
			Mud = 20,
			Snow = 5,
			Sand = 3,
			Glacier = 10,
			Salt = 8,
		}
	}
	
	local path = PathfindingService:CreatePath(pathParams)
	
	local success, errorMessage = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if not success then
		debugPrint("Path computation error:", errorMessage)
		return nil
	end
	
	if path.Status == Enum.PathStatus.NoPath then
		debugPrint("No path found from", startPos, "to", endPos)
		return nil
	end
	
	if path.Status ~= Enum.PathStatus.Success then
		debugPrint("Path status:", path.Status)
		return nil
	end
	
	debugPrint("Path computed successfully!")
	return path
end

local function validateWaypoint(waypoint)
	-- Only reject if water check is enabled AND position is directly in water
	if WATER_CHECK_ENABLED and WATER_CHECK_STRICT then
		if isPositionInWater(waypoint.Position) then
			return false
		end
		
		local material = getTerrainMaterial(waypoint.Position)
		if material == Enum.Material.Water or material == Enum.Material.CrackedLava then
			return false
		end
	end
	
	return true
end

-- =========================================================================
-- GUI SETUP
-- =========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RocksScannerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 650)
mainFrame.Position = UDim2.new(0.5, -175, 0.5, -325)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

-- Header
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "Advanced Miner (FIXED)"
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -35, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- CONTROLS
local controlsFrame = Instance.new("Frame")
controlsFrame.Size = UDim2.new(1, -20, 0, 200)
controlsFrame.Position = UDim2.new(0, 10, 0, 50)
controlsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
controlsFrame.Parent = mainFrame
Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 6)

-- 1. Auto Mine
local autoMineButton = Instance.new("TextButton")
autoMineButton.Size = UDim2.new(0, 24, 0, 24)
autoMineButton.Position = UDim2.new(0, 10, 0, 10)
autoMineButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
autoMineButton.Text = ""
autoMineButton.Parent = controlsFrame
Instance.new("UICorner", autoMineButton).CornerRadius = UDim.new(0, 4)

local autoMineLabel = Instance.new("TextLabel")
autoMineLabel.Text = "ENABLE AUTO-MINE"
autoMineLabel.Size = UDim2.new(0, 150, 0, 24)
autoMineLabel.Position = UDim2.new(0, 40, 0, 10)
autoMineLabel.BackgroundTransparency = 1
autoMineLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
autoMineLabel.Font = Enum.Font.GothamBold
autoMineLabel.TextXAlignment = Enum.TextXAlignment.Left
autoMineLabel.Parent = controlsFrame

-- 2. Stealth
local stealthButton = Instance.new("TextButton")
stealthButton.Size = UDim2.new(0, 24, 0, 24)
stealthButton.Position = UDim2.new(0, 10, 0, 45)
stealthButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
stealthButton.Text = ""
stealthButton.Parent = controlsFrame
Instance.new("UICorner", stealthButton).CornerRadius = UDim.new(0, 4)

local stealthLabel = Instance.new("TextLabel")
stealthLabel.Text = "STEALTH MODE"
stealthLabel.Size = UDim2.new(0, 150, 0, 24)
stealthLabel.Position = UDim2.new(0, 40, 0, 45)
stealthLabel.BackgroundTransparency = 1
stealthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
stealthLabel.Font = Enum.Font.Gotham
stealthLabel.TextXAlignment = Enum.TextXAlignment.Left
stealthLabel.Parent = controlsFrame

-- 3. Strict Avoidance
local strictButton = Instance.new("TextButton")
strictButton.Size = UDim2.new(0, 24, 0, 24)
strictButton.Position = UDim2.new(0, 10, 0, 80)
strictButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
strictButton.Text = ""
strictButton.Parent = controlsFrame
Instance.new("UICorner", strictButton).CornerRadius = UDim.new(0, 4)

local strictLabel = Instance.new("TextLabel")
strictLabel.Text = "REACTIVE DODGE (Run Away)"
strictLabel.Size = UDim2.new(0, 200, 0, 24)
strictLabel.Position = UDim2.new(0, 40, 0, 80)
strictLabel.BackgroundTransparency = 1
strictLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
strictLabel.Font = Enum.Font.Gotham
strictLabel.TextXAlignment = Enum.TextXAlignment.Left
strictLabel.Parent = controlsFrame

-- 4. PLAYER ESP
local espButton = Instance.new("TextButton")
espButton.Size = UDim2.new(0, 24, 0, 24)
espButton.Position = UDim2.new(0, 180, 0, 10)
espButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
espButton.Text = ""
espButton.Parent = controlsFrame
Instance.new("UICorner", espButton).CornerRadius = UDim.new(0, 4)

local espLabel = Instance.new("TextLabel")
espLabel.Text = "PLAYER ESP"
espLabel.Size = UDim2.new(0, 100, 0, 24)
espLabel.Position = UDim2.new(0, 210, 0, 10)
espLabel.BackgroundTransparency = 1
espLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
espLabel.Font = Enum.Font.Gotham
espLabel.TextXAlignment = Enum.TextXAlignment.Left
espLabel.Parent = controlsFrame

-- 5. ORE ESP
local oreEspButton = Instance.new("TextButton")
oreEspButton.Size = UDim2.new(0, 24, 0, 24)
oreEspButton.Position = UDim2.new(0, 160, 0, 115)
oreEspButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
oreEspButton.Text = ""
oreEspButton.Parent = controlsFrame
Instance.new("UICorner", oreEspButton).CornerRadius = UDim.new(0, 4)

local oreEspLabel = Instance.new("TextLabel")
oreEspLabel.Text = "ORE ESP"
oreEspLabel.Size = UDim2.new(0, 100, 0, 24)
oreEspLabel.Position = UDim2.new(0, 190, 0, 115)
oreEspLabel.BackgroundTransparency = 1
oreEspLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
oreEspLabel.Font = Enum.Font.Gotham
oreEspLabel.TextXAlignment = Enum.TextXAlignment.Left
oreEspLabel.Parent = controlsFrame

-- 6. MOB ESP
local mobEspButton = Instance.new("TextButton")
mobEspButton.Size = UDim2.new(0, 24, 0, 24)
mobEspButton.Position = UDim2.new(0, 160, 0, 150)
mobEspButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
mobEspButton.Text = ""
mobEspButton.Parent = controlsFrame
Instance.new("UICorner", mobEspButton).CornerRadius = UDim.new(0, 4)

local mobEspLabel = Instance.new("TextLabel")
mobEspLabel.Text = "MOB ESP"
mobEspLabel.Size = UDim2.new(0, 100, 0, 24)
mobEspLabel.Position = UDim2.new(0, 190, 0, 150)
mobEspLabel.BackgroundTransparency = 1
mobEspLabel.TextColor3 = Color3.fromRGB(170, 0, 255)
mobEspLabel.Font = Enum.Font.Gotham
mobEspLabel.TextXAlignment = Enum.TextXAlignment.Left
mobEspLabel.Parent = controlsFrame

-- Refresh
local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 80, 0, 24)
refreshBtn.Position = UDim2.new(1, -90, 0, 10)
refreshBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
refreshBtn.Text = "Refresh"
refreshBtn.TextColor3 = Color3.new(1, 1, 1)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.Parent = controlsFrame
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 4)

-- Scroll
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -260)
scrollFrame.Position = UDim2.new(0, 10, 0, 260)
scrollFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
scrollFrame.ScrollBarThickness = 6
scrollFrame.Parent = mainFrame
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.Name
listLayout.Parent = scrollFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 1, -25)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle - Select ores & enable"
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.Parent = mainFrame

-- =========================================================================
-- PHYSICS & REPLICATION HELPERS
-- =========================================================================
local function enableFlightPhysics(rootPart)
	local bv = rootPart:FindFirstChild("HoldVelocity") or Instance.new("BodyVelocity")
	bv.Name = "HoldVelocity"
	bv.Velocity = Vector3.new(0,0,0)
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Parent = rootPart
	
	if noclipConnection then noclipConnection:Disconnect() end
	noclipConnection = RunService.Stepped:Connect(function()
		if player.Character then
			for _, part in pairs(player.Character:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	end)
end

local function disableFlightPhysics(rootPart)
	local bv = rootPart:FindFirstChild("HoldVelocity")
	if bv then bv:Destroy() end
	if noclipConnection then 
		noclipConnection:Disconnect() 
		noclipConnection = nil
	end
	-- Re-enable collisions
	if player.Character then
		for _, part in pairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end
end

-- =========================================================================
-- ANIMATIONS
-- =========================================================================
local function getWalkAnimId(humanoid) return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507767714" or "rbxassetid://180426354" end
local function getJumpAnimId(humanoid) return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507765000" or "rbxassetid://125750702" end

local function playWalkAnim(humanoid)
	if walkAnimTrack and walkAnimTrack.IsPlaying then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 1)
	if not animator then return end
	if not walkAnimTrack then
		local anim = Instance.new("Animation")
		anim.AnimationId = getWalkAnimId(humanoid)
		walkAnimTrack = animator:LoadAnimation(anim)
		walkAnimTrack.Priority = Enum.AnimationPriority.Movement
		walkAnimTrack.Looped = true
	end
	walkAnimTrack:Play()
end
local function stopWalkAnim() if walkAnimTrack then walkAnimTrack:Stop() end end
local function playJumpAnim(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	if not jumpAnimTrack then
		local anim = Instance.new("Animation")
		anim.AnimationId = getJumpAnimId(humanoid)
		jumpAnimTrack = animator:LoadAnimation(anim)
		jumpAnimTrack.Priority = Enum.AnimationPriority.Action
		jumpAnimTrack.Looped = false
	end
	jumpAnimTrack:Play()
end

-- =========================================================================
-- ESP LOGIC
-- =========================================================================
local function updateESP()
	espFolder:ClearAllChildren()
	
	-- Player ESP
	if playerEspEnabled then
		for _, v in ipairs(Players:GetPlayers()) do
			if v ~= player and v.Character then
				local highlight = Instance.new("Highlight")
				highlight.Adornee = v.Character
				highlight.FillColor = Color3.fromRGB(255, 0, 0)
				highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
				highlight.FillTransparency = 0.5
				highlight.Parent = espFolder
			end
		end
	end
	
	-- Ore ESP
	if oreEspEnabled then
		local rocksFolder = workspace:FindFirstChild("Rocks")
		if rocksFolder then
			for _, area in ipairs(rocksFolder:GetChildren()) do
				for _, spawnLoc in ipairs(area:GetChildren()) do
					if spawnLoc:IsA("SpawnLocation") then
						for _, item in ipairs(spawnLoc:GetChildren()) do
							if selectedTargets[item.Name] == true then
								local highlight = Instance.new("Highlight")
								highlight.Adornee = item
								highlight.FillColor = Color3.fromRGB(0, 255, 255)
								highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
								highlight.FillTransparency = 0.3
								highlight.Parent = espFolder
							end
						end
					end
				end
			end
		end
	end
	
	-- Mob ESP
	if mobEspEnabled then
		local living = workspace:FindFirstChild("Living")
		if living then
			local playerCharacters = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character then
					playerCharacters[plr.Character] = true
				end
			end
			
			for _, mob in ipairs(living:GetChildren()) do
				if mob:IsA("Model") and mob:FindFirstChild("Humanoid") and not playerCharacters[mob] then
					local highlight = Instance.new("Highlight")
					highlight.Adornee = mob
					highlight.FillColor = Color3.fromRGB(170, 0, 255)
					highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
					highlight.FillTransparency = 0.4
					highlight.Parent = espFolder
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function() task.wait(1) updateESP() end)
Players.PlayerRemoving:Connect(updateESP)
task.spawn(function() while true do task.wait(2) updateESP() end end)

espButton.MouseButton1Click:Connect(function()
	playerEspEnabled = not playerEspEnabled
	espButton.BackgroundColor3 = playerEspEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	updateESP()
end)
oreEspButton.MouseButton1Click:Connect(function()
	oreEspEnabled = not oreEspEnabled
	oreEspButton.BackgroundColor3 = oreEspEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	updateESP()
end)
mobEspButton.MouseButton1Click:Connect(function()
	mobEspEnabled = not mobEspEnabled
	mobEspButton.BackgroundColor3 = mobEspEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	updateESP()
end)

-- =========================================================================
-- GUI LOGIC
-- =========================================================================
local function countSelectedTargets()
	local count = 0
	for _, v in pairs(selectedTargets) do
		if v then count = count + 1 end
	end
	return count
end

local function updateAutoMineVisuals()
	if autoMineEnabled then
		autoMineButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		autoMineLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
		local targetCount = countSelectedTargets()
		if targetCount == 0 then
			statusLabel.Text = "⚠️ No ores selected! Check boxes below"
		else
			statusLabel.Text = "Status: Active (" .. targetCount .. " ore types)"
		end
	else
		autoMineButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		autoMineLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		statusLabel.Text = "Status: Idle"
		isCurrentlyMining = false
		visualFolder:ClearAllChildren()
		stopWalkAnim()
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			disableFlightPhysics(player.Character.HumanoidRootPart)
		end
	end
end

autoMineButton.MouseButton1Click:Connect(function()
	autoMineEnabled = not autoMineEnabled
	debugPrint("Auto-mine toggled:", autoMineEnabled)
	updateAutoMineVisuals()
end)

stealthButton.MouseButton1Click:Connect(function()
	stealthModeEnabled = not stealthModeEnabled
	stealthButton.BackgroundColor3 = stealthModeEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	debugPrint("Stealth mode:", stealthModeEnabled)
end)

strictButton.MouseButton1Click:Connect(function()
	strictAvoidance = not strictAvoidance
	strictButton.BackgroundColor3 = strictAvoidance and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	debugPrint("Strict avoidance:", strictAvoidance)
end)

local function createRow(itemName, count)
	local row = Instance.new("Frame")
	row.Name = itemName
	row.Size = UDim2.new(1, -10, 0, 35)
	row.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	row.Parent = scrollFrame
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Text = itemName .. " (x" .. count .. ")"
	nameLabel.Size = UDim2.new(0.7, 0, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row
	local checkBg = Instance.new("TextButton")
	checkBg.Size = UDim2.new(0, 24, 0, 24)
	checkBg.Position = UDim2.new(1, -34, 0.5, -12)
	checkBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	checkBg.Text = ""
	checkBg.Parent = row
	Instance.new("UICorner", checkBg).CornerRadius = UDim.new(0, 4)
	local checkMark = Instance.new("Frame")
	checkMark.Size = UDim2.new(0, 14, 0, 14)
	checkMark.Position = UDim2.new(0.5, -7, 0.5, -7)
	checkMark.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
	checkMark.Visible = selectedTargets[itemName] or false
	checkMark.Parent = checkBg
	Instance.new("UICorner", checkMark).CornerRadius = UDim.new(0, 2)
	checkBg.MouseButton1Click:Connect(function()
		local newState = not checkMark.Visible
		checkMark.Visible = newState
		selectedTargets[itemName] = newState
		debugPrint("Target toggled:", itemName, "=", newState)
		updateESP()
		updateAutoMineVisuals() -- Update status to show target count
	end)
end

local function isSpawnLocation(obj) return obj:IsA("SpawnLocation") or obj.Name == "SpawnLocation" end
local function isValidItem(item) return not (item:IsA("Decal") or item:IsA("SurfaceGui") or item:IsA("TouchTransmitter") or item:IsA("Weld") or item:IsA("Script")) end

local function scanRocks()
	for _, child in ipairs(scrollFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
	local rocksFolder = workspace:FindFirstChild("Rocks") or workspace:FindFirstChild("rocks")
	if not rocksFolder then 
		statusLabel.Text = "⚠️ No 'Rocks' folder found in workspace!"
		debugPrint("ERROR: No Rocks folder found!")
		return 
	end
	local tallies = {}
	for _, area in ipairs(rocksFolder:GetChildren()) do
		for _, child in ipairs(area:GetChildren()) do
			if isSpawnLocation(child) then
				for _, item in ipairs(child:GetChildren()) do
					if isValidItem(item) then
						tallies[item.Name] = (tallies[item.Name] or 0) + 1
					end
				end
			end
		end
	end
	
	local count = 0
	for name, num in pairs(tallies) do 
		createRow(name, num) 
		count = count + 1
	end
	
	debugPrint("Scanned", count, "ore types")
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	
	if count == 0 then
		statusLabel.Text = "⚠️ No ores found - check Rocks folder structure"
	else
		statusLabel.Text = "Found " .. count .. " ore types - select & enable"
	end
end

-- =========================================================================
-- REACTIVE SAFETY CHECK
-- =========================================================================
local function isMobTooClose(myPos)
	local living = workspace:FindFirstChild("Living")
	if living then
		local playerCharacters = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				playerCharacters[plr.Character] = true
			end
		end
		
		for _, mob in ipairs(living:GetChildren()) do
			if not playerCharacters[mob] and mob:FindFirstChild("HumanoidRootPart") then
				local dist = (mob.HumanoidRootPart.Position - myPos).Magnitude
				if dist < CRITICAL_MOB_DIST then
					return true
				end
			end
		end
	end
	return false
end

-- =========================================================================
-- ENHANCED MOVEMENT WITH WATER AVOIDANCE (FIXED)
-- =========================================================================
local function showPath(waypoints)
	visualFolder:ClearAllChildren()
	for i, waypoint in ipairs(waypoints) do
		if not validateWaypoint(waypoint) then
			continue
		end
		
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.6, 0.6, 0.6)
		dot.Position = waypoint.Position + Vector3.new(0, 0.5, 0)
		dot.Anchored = true
		dot.CanCollide = false
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(0, 160, 255)
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			dot.Color = Color3.fromRGB(255, 200, 0)
			dot.Size = Vector3.new(1, 1, 1)
		end
		dot.Parent = visualFolder
	end
end

local function performPhysicsJump(humanoid, rootPart)
	stopWalkAnim() 
	playJumpAnim(humanoid) 
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	humanoid.Jump = true
	task.wait(0.5) 
end

local function moveToWaypoint(humanoid, rootPart, targetPos, action)
	-- Check if target is in water - abort if so
	if isPositionInWater(targetPos) then
		debugPrint("Target waypoint is in water! Skipping.")
		return false
	end
	
	local needsJump = (action == Enum.PathWaypointAction.Jump) or (targetPos.Y > rootPart.Position.Y + JUMP_THRESHOLD)
	
	if needsJump then 
		debugPrint("Jumping!")
		performPhysicsJump(humanoid, rootPart) 
	end
	
	playWalkAnim(humanoid)
	humanoid:MoveTo(targetPos)
	
	local startTime = tick()
	local lastPos = rootPart.Position
	local stuckCounter = 0
	
	while autoMineEnabled do
		task.wait(0.1)
		
		-- Check if we're actually swimming (more reliable than voxel check)
		if isPlayerInWater() then
			debugPrint("Player is swimming! Jumping out!")
			performPhysicsJump(humanoid, rootPart)
			return false
		end
		
		-- Check horizontal distance to target
		local horizontalDist = ((rootPart.Position - targetPos) * Vector3.new(1, 0, 1)).Magnitude
		
		if horizontalDist < WAYPOINT_REACH_DIST then 
			debugPrint("Waypoint reached!")
			return true 
		end
		
		-- Stuck detection
		local moved = (rootPart.Position - lastPos).Magnitude
		if moved < 0.3 then
			stuckCounter = stuckCounter + 1
			if stuckCounter > 10 then -- Stuck for 1 second
				debugPrint("Stuck! Jumping...")
				performPhysicsJump(humanoid, rootPart)
				stuckCounter = 0
			end
		else
			stuckCounter = 0
		end
		
		-- Timeout
		if tick() - startTime > STUCK_TIMEOUT then 
			debugPrint("Waypoint timeout - jumping and continuing")
			performPhysicsJump(humanoid, rootPart) 
			return true -- Continue to next waypoint
		end
		
		lastPos = rootPart.Position
	end
	
	stopWalkAnim()
	return false
end

local function followPath(destination)
	local character = player.Character
	if not character then return false end
	local hum = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return false end

	local totalDist = (root.Position - destination).Magnitude
	debugPrint("Following path to destination, distance:", math.floor(totalDist))
	
	-- If very close, just walk directly
	if totalDist < DIRECT_PATH_DIST then
		debugPrint("Close enough - walking directly")
		return moveToWaypoint(hum, root, destination, nil)
	end

	-- Pathfinding with retry logic
	local retries = 0
	while retries < PATH_RETRY_COUNT and autoMineEnabled do
		local currentDist = (root.Position - destination).Magnitude
		
		-- Close enough? Walk directly
		if currentDist < DIRECT_PATH_DIST then
			debugPrint("Now close enough - walking directly")
			return moveToWaypoint(hum, root, destination, nil)
		end
		
		statusLabel.Text = "🗺️ Computing path... (attempt " .. (retries + 1) .. ")"
		
		local path = createAdvancedPath(root.Position, destination)
		
		if path then
			local waypoints = path:GetWaypoints()
			debugPrint("Path found with", #waypoints, "waypoints")
			
			-- Filter out water waypoints
			local validWaypoints = {}
			for _, waypoint in ipairs(waypoints) do
				if validateWaypoint(waypoint) then
					table.insert(validWaypoints, waypoint)
				end
			end
			
			if #validWaypoints > 1 then
				showPath(validWaypoints)
				statusLabel.Text = "🚶 Following path (" .. #validWaypoints .. " waypoints)"
				
				-- Follow each waypoint
				for i = 2, #validWaypoints do -- Skip first (current position)
					if not autoMineEnabled then
						stopWalkAnim()
						return false
					end
					
					local waypoint = validWaypoints[i]
					debugPrint("Moving to waypoint", i, "of", #validWaypoints)
					
					if not moveToWaypoint(hum, root, waypoint.Position, waypoint.Action) then
						-- Failed to reach waypoint - try recomputing
						debugPrint("Failed to reach waypoint - recomputing path")
						break
					end
				end
				
				-- Check if we're close to destination now
				local finalDist = (root.Position - destination).Magnitude
				if finalDist < DIRECT_PATH_DIST then
					debugPrint("Close to destination - final approach")
					return moveToWaypoint(hum, root, destination, nil)
				end
			else
				debugPrint("All waypoints were in water!")
			end
		else
			debugPrint("Pathfinding failed on attempt", retries + 1)
		end
		
		retries = retries + 1
		
		if retries < PATH_RETRY_COUNT then
			statusLabel.Text = "⚠️ Retrying pathfinding..."
			task.wait(0.5)
		end
	end
	
	-- Final check - are we close enough?
	local finalDist = (root.Position - destination).Magnitude
	if finalDist < DIRECT_PATH_DIST * 2 then
		debugPrint("Close enough after retries - attempting direct walk")
		return moveToWaypoint(hum, root, destination, nil)
	end
	
	debugPrint("Failed to reach destination after all retries")
	statusLabel.Text = "⚠️ Cannot reach target - skipping"
	return false
end

-- =========================================================================
-- MAIN LOOP (FIXED)
-- =========================================================================

task.spawn(function()
	while true do
		task.wait(0.5)
		
		if autoMineEnabled and not isCurrentlyMining then
			-- Check if any targets are selected
			local hasTargets = false
			for _, v in pairs(selectedTargets) do
				if v then hasTargets = true break end
			end
			
			if not hasTargets then
				statusLabel.Text = "⚠️ No ores selected! Check boxes below"
				task.wait(1)
				continue
			end
			
			local rocksFolder = workspace:FindFirstChild("Rocks")
			local character = player.Character
			
			if rocksFolder and character and character:FindFirstChild("HumanoidRootPart") then
				local rootPart = character.HumanoidRootPart
				local currentPos = rootPart.Position
				local closestItem = nil
				local shortestDistance = math.huge
				
				-- Find Closest Target
				for _, area in ipairs(rocksFolder:GetChildren()) do
					for _, spawnLoc in ipairs(area:GetChildren()) do
						if isSpawnLocation(spawnLoc) then
							for _, item in ipairs(spawnLoc:GetChildren()) do
								if isValidItem(item) and selectedTargets[item.Name] == true then
									local itemPos = item:GetPivot().Position 
									local dist = (currentPos - itemPos).Magnitude
									if dist < shortestDistance then
										shortestDistance = dist
										closestItem = item
									end
								end
							end
						end
					end
				end
				
				if closestItem then
					debugPrint("Found target:", closestItem.Name, "at distance:", math.floor(shortestDistance))
					isCurrentlyMining = true
					local targetPos = closestItem:GetPivot().Position
					
					-- Check if target is underwater
					if isPositionInWater(targetPos) then
						statusLabel.Text = "⚠️ Target underwater - skipping"
						debugPrint("Target is underwater, skipping")
						isCurrentlyMining = false
						task.wait(1)
					else
						-- ===================================
						-- MODE A: STEALTH (unchanged)
						-- ===================================
						if stealthModeEnabled then
							statusLabel.Text = "🚇 Stealth: Traveling..."
							enableFlightPhysics(rootPart)
							if rootPart.Position.Y > targetPos.Y - TRAVEL_DEPTH + 5 then 
								local downPos = Vector3.new(rootPart.Position.X, targetPos.Y - TRAVEL_DEPTH, rootPart.Position.Z)
								TweenService:Create(rootPart, TweenInfo.new(1), {CFrame = CFrame.new(downPos)}):Play()
								task.wait(1)
							end
							local underRockPos = targetPos - Vector3.new(0, TRAVEL_DEPTH, 0)
							local travelDist = (rootPart.Position - underRockPos).Magnitude
							local timeToTravel = travelDist / MOVEMENT_SPEED
							local travelTween = TweenService:Create(rootPart, TweenInfo.new(timeToTravel, Enum.EasingStyle.Linear), {CFrame = CFrame.new(underRockPos)})
							travelTween:Play()
							local arrived = false
							travelTween.Completed:Connect(function() arrived = true end)
							while not arrived do 
								if not autoMineEnabled then travelTween:Cancel() break end 
								task.wait(0.1) 
							end
							if autoMineEnabled then
								statusLabel.Text = "⬆️ Approaching..."
								local minePos = targetPos - Vector3.new(0, MINING_DEPTH, 0)
								TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
								task.wait(0.5)
								
								statusLabel.Text = "⛏️ Mining..."
								while closestItem.Parent and autoMineEnabled do
									if strictAvoidance and isMobTooClose(rootPart.Position) then
										statusLabel.Text = "⚠️ MOB DETECTED! ESCAPING!"
										break 
									end
									pcall(function() ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") end)
									task.wait(0.1)
								end
								
								statusLabel.Text = "⬇️ Retreating..."
								TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(underRockPos)}):Play()
								task.wait(0.5)
							end
							disableFlightPhysics(rootPart)
						
						-- ===================================
						-- MODE B: LEGIT MODE (FIXED)
						-- ===================================
						else 
							statusLabel.Text = "🏃 Walking to " .. closestItem.Name .. "..."
							disableFlightPhysics(rootPart)
							
							local arrived = followPath(targetPos)
							
							if arrived and autoMineEnabled then
								debugPrint("Arrived at target, mining...")
								statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
								
								local mineStartTime = tick()
								while closestItem.Parent and autoMineEnabled do
									if strictAvoidance and isMobTooClose(rootPart.Position) then
										statusLabel.Text = "⚠️ MOB DETECTED! RUNNING!"
										debugPrint("Mob too close! Fleeing!")
										performPhysicsJump(player.Character.Humanoid, rootPart)
										break 
									end
									
									pcall(function() 
										ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") 
									end)
									task.wait(0.1)
									
									-- Safety timeout - don't mine forever
									if tick() - mineStartTime > 30 then
										debugPrint("Mining timeout - moving on")
										break
									end
								end
								
								debugPrint("Mining complete or interrupted")
							else
								debugPrint("Failed to arrive at target")
								statusLabel.Text = "⚠️ Couldn't reach target"
								task.wait(1)
							end
							
							stopWalkAnim()
							visualFolder:ClearAllChildren()
						end
						
						isCurrentlyMining = false
					end
				else
					statusLabel.Text = "⚠️ No matching ores found"
					debugPrint("No ores found matching selected targets")
					task.wait(2)
				end
			end
		end
	end
end)

-- =========================================================================
-- UI DRAGGING & EVENTS
-- =========================================================================
local dragging, dragInput, mousePos, framePos
local function update(input)
	local delta = input.Position - mousePos
	mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
end
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		mousePos = input.Position
		framePos = mainFrame.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
titleBar.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end end)
game:GetService("UserInputService").InputChanged:Connect(function(input) if input == dragInput and dragging then update(input) end end)

closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)
refreshBtn.MouseButton1Click:Connect(scanRocks)
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

-- Initial scan
task.wait(1)
scanRocks()
print("✅ Advanced Miner (FIXED) Loaded - Select ores and enable auto-mine!")
