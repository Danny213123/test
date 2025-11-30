-- Rocks Scanner - Advanced Miner v2.5 (WORLD 2 CANNON LAUNCHER)
-- TYPE: LocalScript
-- LOCATION: StarterPlayer -> StarterPlayerScripts
-- 
-- FEATURES v2.5:
-- ✅ CANNON LAUNCHER: Auto-fires from spawn to cave (World 2)
-- ✅ Detects spawn location after death → Pathfinds to cannon → Presses E → Resumes mining
-- ✅ Manual cannon button in GUI for re-firing
-- ✅ Dynamic pathfinding: Recalculates path every 3 seconds
-- ✅ Advanced combat: Dodge rolls + Block (F key) + Smart tactics
-- ✅ Fixed tweening: Only after 10 REAL pathfinding failures
-- ✅ Continuous ore facing during mining
-- ✅ Mining effectiveness checks (verifies ore takes damage every 5s)
-- ✅ Distance monitoring + Auto-repositioning
-- ✅ Fall detection with auto re-pathing
-- 
-- CANNON SYSTEM v2.5:
-- ✅ Automatic spawn detection (checks if near spawn area)
-- ✅ Finds cannon in workspace (Main Island [2] -> Cannon)
-- ✅ Pathfinds to cannon location
-- ✅ Presses 'E' key 3 times to ensure firing
-- ✅ Waits 5 seconds for flight/landing
-- ✅ Manual button to re-fire cannon
-- 
-- COMBAT FEATURES:
-- ✅ Dodge roll - 25% chance when attacked, random direction (6 studs)
-- ✅ Block attacks - Press 'F' to block, 33% chance when attacked
-- ✅ Smart movement - Defensive dodges even when not attacked (5%)
-- ✅ Close-range tactics - Blocks/dodges at <7 studs
-- 
-- VERSION: v2.5

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Script Version
local SCRIPT_VERSION = "v2.5"

-- =========================================================================
-- CONFIGURATION (MOVED BEFORE FUNCTIONS THAT USE THEM)
-- =========================================================================
local autoMineEnabled = false
local stealthModeEnabled = false -- Default Legit
local strictAvoidance = true 
local playerEspEnabled = false
local oreEspEnabled = false
local mobEspEnabled = false
local isCurrentlyMining = false 
local selectedTargets = {}
local skippedUnderwaterOres = {} -- Track ores that are underwater to avoid infinite loops
local UNDERWATER_SKIP_DURATION = 30 -- Seconds before retrying underwater ore
local lastCombatTime = 0 -- Track when last combat ended to prevent spam
local lastHealthCheck = 0
local isBeingAttacked = false

-- Forward declare UI elements (will be set later)
local statusLabel
local visualFolder

-- =========================================================================
-- CANNON LAUNCHER (World 2 - Spawn to Cave)
-- =========================================================================
local cannonFired = false -- Track if cannon was used this session
local SPAWN_POSITION = Vector3.new(0, 50, 0) -- Approximate spawn location (adjust if needed)
local SPAWN_DETECTION_RADIUS = 100 -- Distance from spawn to detect respawn

local function isAtSpawn(position)
	-- Check if player is near spawn (World 2 spawn area)
	local spawnAreas = {
		Vector3.new(0, 50, 0),  -- Adjust these positions based on actual spawn
		Vector3.new(0, 100, 0),
		Vector3.new(0, 75, 0)
	}
	
	for _, spawnPos in ipairs(spawnAreas) do
		if (position - spawnPos).Magnitude < SPAWN_DETECTION_RADIUS then
			return true
		end
	end
	
	return false
end

local function findCannon()
	-- Look for Cannon in workspace
	local function searchForCannon(parent)
		for _, child in ipairs(parent:GetDescendants()) do
			if child.Name == "Cannon" and child:IsA("Model") then
				return child
			end
		end
		return nil
	end
	
	-- Try Main Island first
	local mainIsland = workspace:FindFirstChild("Main Island [2]")
	if mainIsland then
		local cannon = searchForCannon(mainIsland)
		if cannon then return cannon end
	end
	
	-- Fallback: search entire workspace
	return searchForCannon(workspace)
end

local function fireCannon()
	local character = player.Character
	if not character then return false end
	
	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return false end
	
	debugPrint("🎯 Searching for cannon...")
	statusLabel.Text = "🔍 Looking for cannon..."
	
	local cannon = findCannon()
	
	if not cannon then
		debugPrint("⚠️ Cannon not found in workspace!")
		statusLabel.Text = "⚠️ Cannon not found - continuing anyway"
		return false
	end
	
	local cannonPart = cannon:FindFirstChild("CannonPart") or cannon:FindFirstChild("Cannon") or cannon.PrimaryPart
	if not cannonPart then
		-- Try to find any part in the cannon model
		for _, child in ipairs(cannon:GetChildren()) do
			if child:IsA("BasePart") then
				cannonPart = child
				break
			end
		end
	end
	
	if not cannonPart then
		debugPrint("⚠️ Cannon part not found!")
		return false
	end
	
	local cannonPos = cannonPart.Position
	debugPrint("📍 Cannon found at:", math.floor(cannonPos.X), math.floor(cannonPos.Y), math.floor(cannonPos.Z))
	statusLabel.Text = "🚶 Walking to cannon..."
	
	-- Pathfind to cannon
	local arrivedAtCannon = followPath(cannonPos, 0)
	
	if not arrivedAtCannon then
		debugPrint("⚠️ Failed to reach cannon")
		statusLabel.Text = "⚠️ Can't reach cannon - trying anyway"
		-- Try to get close with tween
		local distance = (rootPart.Position - cannonPos).Magnitude
		if distance > 50 then
			TweenService:Create(rootPart, TweenInfo.new(2), {CFrame = CFrame.new(cannonPos + Vector3.new(0, 5, 0))}):Play()
			task.wait(2.5)
		end
	end
	
	-- Get close to cannon interaction point
	local interactionPos = cannonPos + Vector3.new(0, 3, 0)
	rootPart.CFrame = CFrame.new(interactionPos)
	task.wait(0.5)
	
	debugPrint("🎆 Firing cannon - pressing E!")
	statusLabel.Text = "🎆 FIRING CANNON!"
	
	-- Press E to fire cannon
	local VirtualInputManager = game:GetService("VirtualInputManager")
	for i = 1, 3 do -- Press E multiple times to ensure it fires
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			task.wait(0.1)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		end)
		task.wait(0.3)
	end
	
	debugPrint("🚀 Cannon fired! Waiting for landing...")
	statusLabel.Text = "🚀 Flying through air..."
	
	-- Wait for cannon to launch and land (give it time to fly)
	task.wait(5)
	
	cannonFired = true
	debugPrint("✅ Cannon sequence complete!")
	statusLabel.Text = "✅ Landed - resuming mining"
	
	return true
end

local function handleRespawnCannon()
	local character = player.Character
	if not character then return false end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	-- Check if we're at spawn and haven't used cannon yet
	if isAtSpawn(rootPart.Position) and not cannonFired then
		debugPrint("🏁 Detected spawn location - initiating cannon sequence")
		statusLabel.Text = "🏁 At spawn - using cannon"
		return fireCannon()
	end
	
	return false
end

-- =========================================================================
-- CHARACTER RESPAWN HANDLER
-- =========================================================================
local function onCharacterAdded(character)
	debugPrint("Character respawned, waiting for full load...")
	
	-- Wait for essential parts
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	
	if not humanoid or not rootPart then
		debugPrint("Failed to load character parts!")
		return
	end
	
	-- Setup death detection
	humanoid.Died:Connect(function()
		debugPrint("Character died!")
		statusLabel.Text = "💀 Died! Waiting for respawn..."
		isCurrentlyMining = false
		visualFolder:ClearAllChildren()
		
		-- Clean up animation tracks
		if walkAnimTrack then
			walkAnimTrack:Stop()
			walkAnimTrack:Destroy()
			walkAnimTrack = nil
		end
		if jumpAnimTrack then
			jumpAnimTrack:Stop()
			jumpAnimTrack:Destroy()
			jumpAnimTrack = nil
		end
	end)
	
	-- Setup damage detection for auto-combat
	lastHealthCheck = humanoid.Health
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealthCheck then
			local damageTaken = lastHealthCheck - newHealth
			if damageTaken > 0 and strictAvoidance then
				debugPrint("Took damage! (" .. math.floor(damageTaken) .. " HP)")
				isBeingAttacked = true
				statusLabel.Text = "🛡️ UNDER ATTACK! Engaging combat..."
				statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
				-- Combat will be triggered on next check
				task.delay(3, function() 
					isBeingAttacked = false
					statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
				end) -- Clear flag after 3 seconds
			end
		end
		lastHealthCheck = newHealth
	end)
	
	-- Wait a bit for character to stabilize
	task.wait(2)
	
	-- Reset mining state
	isCurrentlyMining = false
	
	-- CRITICAL: Reinitialize animation tracks for new character
	walkAnimTrack = nil
	jumpAnimTrack = nil
	
	-- Clear visuals
	visualFolder:ClearAllChildren()
	
	debugPrint("Character fully loaded and ready!")
	
	-- Check if we need to use cannon (World 2 spawn -> cave)
	local usedCannon = handleRespawnCannon()
	
	if usedCannon then
		debugPrint("Cannon fired successfully, ready to mine")
	end
	
	-- Auto-resume mining if it was enabled
	if autoMineEnabled then
		statusLabel.Text = "🔄 Resuming mining after respawn..."
		debugPrint("Auto-mine was enabled, resuming operations...")
		task.wait(1)
	end
end

-- Connect respawn handler
player.CharacterAdded:Connect(onCharacterAdded)

-- Handle initial character if already loaded
if player.Character then
	task.spawn(function()
		onCharacterAdded(player.Character)
	end)
end

-- =========================================================================
-- SETTINGS
-- =========================================================================
-- Settings
local SIGHT_DISTANCE = 150      
local TRAVEL_DEPTH = 20         
local MINING_DEPTH = 12         
local MOVEMENT_SPEED = 35       

-- Safety Settings
local CRITICAL_MOB_DIST = 15    -- Only run away if mob is THIS close (Active Avoidance)
local COMBAT_COOLDOWN = 1.0     -- Wait 1 second after combat before checking for mobs again

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
local MAX_PATHFIND_ATTEMPTS = 10 -- Maximum attempts before using tween fallback
local NATURAL_TWEEN_SPEED = 25  -- Speed for natural-looking tweens (studs/second)

-- Visuals
visualFolder = workspace:FindFirstChild("PathVisuals") or Instance.new("Folder")
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
-- KEYBOARD INPUT & HOTBAR HELPERS
-- =========================================================================
local function pressKey(key)
	VirtualInputManager:SendKeyEvent(true, key, false, game)
end

local function releaseKey(key)
	VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function switchToPickaxe()
	debugPrint("Switching to Pickaxe (Slot 1)")
	pressKey(Enum.KeyCode.One)
	task.wait(0.05)
	releaseKey(Enum.KeyCode.One)
	task.wait(0.1)
end

local function switchToWeapon()
	debugPrint("Switching to Weapon (Slot 2)")
	pressKey(Enum.KeyCode.Two)
	task.wait(0.05)
	releaseKey(Enum.KeyCode.Two)
	task.wait(0.1)
end

-- =========================================================================
-- UNDERWATER ORE TRACKING HELPER
-- =========================================================================
local function isOreSkipped(ore)
	if not ore then return false end
	local skipData = skippedUnderwaterOres[ore]
	if not skipData then return false end
	
	-- Check if skip duration has expired
	if tick() - skipData.timestamp > UNDERWATER_SKIP_DURATION then
		skippedUnderwaterOres[ore] = nil
		debugPrint("Underwater ore retry timeout expired for:", ore.Name)
		return false
	end
	
	return true
end

local function markOreAsSkipped(ore)
	if ore then
		skippedUnderwaterOres[ore] = {
			timestamp = tick(),
			name = ore.Name
		}
		debugPrint("Marked ore as skipped (underwater):", ore.Name)
	end
end

local function clearSkippedOres()
	skippedUnderwaterOres = {}
	debugPrint("Cleared all skipped underwater ores")
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
-- SIMPLE GUI SETUP
-- =========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RocksScannerGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 600)
mainFrame.Position = UDim2.new(0.5, -175, 0.5, -300)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
titleBar.Parent = mainFrame

Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "Advanced Miner " .. SCRIPT_VERSION
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

-- Controls Frame
local controlsFrame = Instance.new("Frame")
controlsFrame.Size = UDim2.new(1, -20, 0, 195)
controlsFrame.Position = UDim2.new(0, 10, 0, 50)
controlsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
controlsFrame.Parent = mainFrame

Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 6)

-- Auto Mine Toggle
local autoMineButton = Instance.new("TextButton")
autoMineButton.Size = UDim2.new(0, 24, 0, 24)
autoMineButton.Position = UDim2.new(0, 10, 0, 10)
autoMineButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
autoMineButton.Text = ""
autoMineButton.Parent = controlsFrame

Instance.new("UICorner", autoMineButton).CornerRadius = UDim.new(0, 4)

local autoMineLabel = Instance.new("TextLabel")
autoMineLabel.Text = "ENABLE AUTO-MINE"
autoMineLabel.Size = UDim2.new(0, 200, 0, 24)
autoMineLabel.Position = UDim2.new(0, 40, 0, 10)
autoMineLabel.BackgroundTransparency = 1
autoMineLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
autoMineLabel.Font = Enum.Font.GothamBold
autoMineLabel.TextXAlignment = Enum.TextXAlignment.Left
autoMineLabel.Parent = controlsFrame

-- Stealth Mode Toggle
local stealthButton = Instance.new("TextButton")
stealthButton.Size = UDim2.new(0, 24, 0, 24)
stealthButton.Position = UDim2.new(0, 10, 0, 45)
stealthButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
stealthButton.Text = ""
stealthButton.Parent = controlsFrame

Instance.new("UICorner", stealthButton).CornerRadius = UDim.new(0, 4)

local stealthLabel = Instance.new("TextLabel")
stealthLabel.Text = "STEALTH MODE"
stealthLabel.Size = UDim2.new(0, 200, 0, 24)
stealthLabel.Position = UDim2.new(0, 40, 0, 45)
stealthLabel.BackgroundTransparency = 1
stealthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
stealthLabel.Font = Enum.Font.Gotham
stealthLabel.TextXAlignment = Enum.TextXAlignment.Left
stealthLabel.Parent = controlsFrame

-- Combat Toggle
local combatButton = Instance.new("TextButton")
combatButton.Size = UDim2.new(0, 24, 0, 24)
combatButton.Position = UDim2.new(0, 10, 0, 80)
combatButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
combatButton.Text = ""
combatButton.Parent = controlsFrame

Instance.new("UICorner", combatButton).CornerRadius = UDim.new(0, 4)

local combatLabel = Instance.new("TextLabel")
combatLabel.Text = "AUTO COMBAT"
combatLabel.Size = UDim2.new(0, 200, 0, 24)
combatLabel.Position = UDim2.new(0, 40, 0, 80)
combatLabel.BackgroundTransparency = 1
combatLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
combatLabel.Font = Enum.Font.Gotham
combatLabel.TextXAlignment = Enum.TextXAlignment.Left
combatLabel.Parent = controlsFrame

-- Cannon Button (World 2)
local cannonButton = Instance.new("TextButton")
cannonButton.Size = UDim2.new(0, 24, 0, 24)
cannonButton.Position = UDim2.new(0, 10, 0, 115)
cannonButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
cannonButton.Text = ""
cannonButton.Parent = controlsFrame

Instance.new("UICorner", cannonButton).CornerRadius = UDim.new(0, 4)

local cannonLabel = Instance.new("TextLabel")
cannonLabel.Text = "FIRE CANNON (World 2)"
cannonLabel.Size = UDim2.new(0, 200, 0, 24)
cannonLabel.Position = UDim2.new(0, 40, 0, 115)
cannonLabel.BackgroundTransparency = 1
cannonLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
cannonLabel.Font = Enum.Font.Gotham
cannonLabel.TextXAlignment = Enum.TextXAlignment.Left
cannonLabel.Parent = controlsFrame

-- ESP Toggles
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

local oreEspButton = Instance.new("TextButton")
oreEspButton.Size = UDim2.new(0, 24, 0, 24)
oreEspButton.Position = UDim2.new(0, 180, 0, 45)
oreEspButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
oreEspButton.Text = ""
oreEspButton.Parent = controlsFrame

Instance.new("UICorner", oreEspButton).CornerRadius = UDim.new(0, 4)

local oreEspLabel = Instance.new("TextLabel")
oreEspLabel.Text = "ORE ESP"
oreEspLabel.Size = UDim2.new(0, 100, 0, 24)
oreEspLabel.Position = UDim2.new(0, 210, 0, 45)
oreEspLabel.BackgroundTransparency = 1
oreEspLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
oreEspLabel.Font = Enum.Font.Gotham
oreEspLabel.TextXAlignment = Enum.TextXAlignment.Left
oreEspLabel.Parent = controlsFrame

-- Refresh Button
local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 80, 0, 24)
refreshBtn.Position = UDim2.new(1, -90, 0, 10)
refreshBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
refreshBtn.Text = "Refresh"
refreshBtn.TextColor3 = Color3.new(1, 1, 1)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.Parent = controlsFrame

Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 4)

-- Ore List
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -255)
scrollFrame.Position = UDim2.new(0, 10, 0, 255)
scrollFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
scrollFrame.ScrollBarThickness = 6
scrollFrame.Parent = mainFrame

Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.Name
listLayout.Parent = scrollFrame

-- Status Label
statusLabel = Instance.new("TextLabel")
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
-- ANIMATIONS & MOVEMENT
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

-- =========================================================================
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
		clearSkippedOres()
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			disableFlightPhysics(player.Character.HumanoidRootPart)
		end
	end
end

-- Auto Mine Toggle
autoMineButton.MouseButton1Click:Connect(function()
	autoMineEnabled = not autoMineEnabled
	debugPrint("Auto-mine toggled:", autoMineEnabled)
	updateAutoMineVisuals()
end)

-- Stealth Mode Toggle
stealthButton.MouseButton1Click:Connect(function()
	stealthModeEnabled = not stealthModeEnabled
	stealthButton.BackgroundColor3 = stealthModeEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	debugPrint("Stealth mode:", stealthModeEnabled)
end)

-- Combat Toggle
combatButton.MouseButton1Click:Connect(function()
	strictAvoidance = not strictAvoidance
	combatButton.BackgroundColor3 = strictAvoidance and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	debugPrint("Auto combat mode:", strictAvoidance)
end)

-- Cannon Fire Button
cannonButton.MouseButton1Click:Connect(function()
	debugPrint("Manual cannon fire requested")
	cannonFired = false -- Reset flag to allow re-firing
	task.spawn(function()
		local success = fireCannon()
		if success then
			cannonButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
			task.wait(2)
			cannonButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		else
			cannonButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			task.wait(2)
			cannonButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		end
	end)
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
		updateAutoMineVisuals()
	end)
end

local function isSpawnLocation(obj) return obj:IsA("SpawnLocation") or obj.Name == "SpawnLocation" end
local function isValidItem(item) return not (item:IsA("Decal") or item:IsA("SurfaceGui") or item:IsA("TouchTransmitter") or item:IsA("Weld") or item:IsA("Script")) end

local function scanRocks()
	for _, child in ipairs(scrollFrame:GetChildren()) do 
		if child:IsA("Frame") then 
			child:Destroy() 
		end 
	end
	
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
-- =========================================================================
-- COMBAT SYSTEM (WITH DODGE & BLOCK)
-- =========================================================================
local lastDodge = 0
local lastBlock = 0
local DODGE_COOLDOWN = 2 -- Dodge every 2 seconds max
local BLOCK_COOLDOWN = 1 -- Block every 1 second max
local BLOCK_DURATION = 0.5 -- Hold block for 0.5 seconds

local function pressKey(key)
	local VirtualInputManager = game:GetService("VirtualInputManager")
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(0.05)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end)
end

local function holdKey(key, duration)
	local VirtualInputManager = game:GetService("VirtualInputManager")
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(duration)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end)
end

local function dodge(character)
	if tick() - lastDodge < DODGE_COOLDOWN then return false end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	-- Random dodge direction (side-to-side or back)
	local dodgeDirections = {
		Vector3.new(6, 0, 0),  -- Right
		Vector3.new(-6, 0, 0), -- Left
		Vector3.new(0, 0, -6)  -- Back
	}
	
	local randomDir = dodgeDirections[math.random(1, #dodgeDirections)]
	local dodgePos = rootPart.Position + randomDir
	
	-- Quick dodge tween
	TweenService:Create(rootPart, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(dodgePos)
	}):Play()
	
	lastDodge = tick()
	debugPrint("🏃 Dodged!")
	return true
end

local function blockAttack()
	if tick() - lastBlock < BLOCK_COOLDOWN then return false end
	
	-- Press and hold 'f' to block
	task.spawn(function()
		holdKey(Enum.KeyCode.F, BLOCK_DURATION)
	end)
	
	lastBlock = tick()
	debugPrint("🛡️ Blocking!")
	statusLabel.Text = "🛡️ BLOCKING ATTACK!"
	return true
end

local function getNearbyMobs(myPos, maxDistance)
	local nearbyMobs = {}
	local living = workspace:FindFirstChild("Living")
	if living then
		local playerCharacters = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				playerCharacters[plr.Character] = true
			end
		end
		
		for _, mob in ipairs(living:GetChildren()) do
			if not playerCharacters[mob] and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChild("Humanoid") then
				local mobHumanoid = mob.Humanoid
				local mobRoot = mob.HumanoidRootPart
				
				-- CRITICAL: Only add mobs that are actually alive
				if mobHumanoid.Health > 0 and mobRoot.Parent then
					local dist = (mobRoot.Position - myPos).Magnitude
					if dist < maxDistance then
						table.insert(nearbyMobs, {
							mob = mob,
							distance = dist,
							health = mobHumanoid.Health
						})
					end
				end
			end
		end
	end
	
	-- Sort by distance (closest first)
	table.sort(nearbyMobs, function(a, b) return a.distance < b.distance end)
	return nearbyMobs
end

local function attackMob(mob, character)
	if not mob or not mob.Parent or not character then return false end
	
	local mobRoot = mob:FindFirstChild("HumanoidRootPart")
	local mobHumanoid = mob:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	
	if not mobRoot or not mobHumanoid or not rootPart or not humanoid then return false end
	
	-- Check if mob is already dead before starting combat
	if mobHumanoid.Health <= 0 then
		debugPrint("Mob is already dead, skipping")
		return false
	end
	
	debugPrint("Engaging mob:", mob.Name, "Health:", mobHumanoid.Health)
	
	-- Switch to weapon (slot 2)
	switchToWeapon()
	
	local combatStartTime = tick()
	local maxCombatTime = 15 -- Maximum 15 seconds per mob
	
	while mob.Parent and mobHumanoid.Health > 0 and autoMineEnabled do
		-- Check if player is still alive
		if not humanoid or humanoid.Health <= 0 then
			debugPrint("Player died during combat!")
			return false
		end
		
		-- CRITICAL: Re-check mob is still valid
		if not mob.Parent or not mobRoot.Parent or not mobHumanoid.Parent then
			debugPrint("Mob became invalid during combat")
			break
		end
		
		-- CRITICAL: Check mob health again
		if mobHumanoid.Health <= 0 then
			debugPrint("Mob died during combat loop")
			break
		end
		
		if tick() - combatStartTime > maxCombatTime then
			debugPrint("Combat timeout - moving on")
			break
		end
		
		-- Calculate distance
		local dist = (mobRoot.Position - rootPart.Position).Magnitude
		statusLabel.Text = "⚔️ Fighting " .. mob.Name .. " (" .. math.floor(dist) .. " studs | HP:" .. math.floor(mobHumanoid.Health) .. ")"
		
		-- ADVANCED COMBAT TACTICS
		-- 1. Try to block if being attacked and close range
		if isBeingAttacked and dist < 7 then
			if math.random(1, 3) == 1 then -- 33% chance to block when attacked
				local blocked = blockAttack()
				if blocked then
					task.wait(BLOCK_DURATION + 0.1)
					-- Continue to next iteration after blocking
					if mobHumanoid.Health > 0 then
						continue
					end
				end
			end
		end
		
		-- 2. Dodge if being attacked and close range
		if isBeingAttacked and dist < 8 then
			if math.random(1, 4) == 1 then -- 25% chance to dodge when attacked
				local dodged = dodge(character)
				if dodged then
					task.wait(0.3)
					statusLabel.Text = "⚔️ Fighting " .. mob.Name .. " (DODGED!)"
					if mobHumanoid.Health > 0 then
						continue
					end
				end
			end
		end
		
		-- 3. Periodic dodge even without being attacked (defensive movement)
		if dist < 6 and math.random(1, 20) == 1 then -- 5% chance per loop
			dodge(character)
			task.wait(0.3)
		end
		
		-- Face the mob properly using CFrame.lookAt
		if mobRoot and rootPart then
			local lookPos = Vector3.new(mobRoot.Position.X, rootPart.Position.Y, mobRoot.Position.Z) -- Keep Y level
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookPos)
		end
		
		-- Move closer if too far
		if dist > 5 then -- Reduced from 8 to 5 for closer melee range
			humanoid:MoveTo(mobRoot.Position)
			playWalkAnim(humanoid)
		else
			humanoid:MoveTo(rootPart.Position) -- Stop moving
			stopWalkAnim()
		end
		
		-- Attack with weapon
		pcall(function()
			ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Weapon")
		end)
		
		task.wait(0.2) -- Attack cooldown (faster than before)
	end
	
	stopWalkAnim()
	
	if mob.Parent and mobHumanoid.Health > 0 then
		debugPrint("Mob still alive, combat ended")
		return false
	else
		debugPrint("Mob defeated!")
		return true
	end
end

local function handleCombat(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	-- Check combat cooldown to prevent attacking dead mobs
	if tick() - lastCombatTime < COMBAT_COOLDOWN then
		return false
	end
	
	local nearbyMobs = getNearbyMobs(rootPart.Position, CRITICAL_MOB_DIST)
	
	if #nearbyMobs > 0 then
		debugPrint("Found", #nearbyMobs, "nearby alive mobs")
		
		-- Attack each nearby mob
		for _, mobData in ipairs(nearbyMobs) do
			if not autoMineEnabled then break end
			
			-- Double-check mob is still valid and alive before attacking
			local mob = mobData.mob
			if mob and mob.Parent and mob:FindFirstChild("Humanoid") then
				local mobHumanoid = mob:FindFirstChild("Humanoid")
				if mobHumanoid and mobHumanoid.Health > 0 then
					debugPrint("Attacking mob:", mob.Name, "HP:", mobHumanoid.Health)
					attackMob(mob, character)
					task.wait(0.5)
				else
					debugPrint("Skipping dead/invalid mob:", mob.Name)
				end
			end
		end
		
		-- Update last combat time
		lastCombatTime = tick()
		debugPrint("Combat cooldown started")
		
		return true -- Combat occurred
	end
	
	return false -- No combat
end

-- =========================================================================
-- NATURAL TWEEN MOVEMENT (FALLBACK)
-- =========================================================================
local function naturalTweenToPosition(character, targetPos)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not rootPart or not humanoid then return false end
	
	debugPrint("Using natural tween fallback to reach ore")
	statusLabel.Text = "🎯 Natural movement to ore..."
	
	local startPos = rootPart.Position
	local distance = (targetPos - startPos).Magnitude
	local travelTime = distance / NATURAL_TWEEN_SPEED
	
	-- Create natural looking path with slight arc
	local midPoint = (startPos + targetPos) / 2 + Vector3.new(0, 3, 0) -- Slight upward arc
	
	-- Play walk animation
	playWalkAnim(humanoid)
	
	-- Tween to midpoint first (creates natural arc)
	local tween1Time = travelTime / 2
	local tween1 = TweenService:Create(rootPart, 
		TweenInfo.new(tween1Time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{CFrame = CFrame.new(midPoint)}
	)
	
	local reached1 = false
	tween1.Completed:Connect(function()
		reached1 = true
	end)
	
	tween1:Play()
	
	-- Wait for first part of arc
	local startTime = tick()
	while not reached1 and autoMineEnabled do
		task.wait(0.1)
		if tick() - startTime > tween1Time + 2 then
			tween1:Cancel()
			break
		end
	end
	
	if not autoMineEnabled then
		stopWalkAnim()
		return false
	end
	
	-- Tween to final position (completes arc)
	local tween2Time = travelTime / 2
	local finalCFrame = CFrame.new(targetPos)
	local tween2 = TweenService:Create(rootPart,
		TweenInfo.new(tween2Time, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{CFrame = finalCFrame}
	)
	
	local reached2 = false
	tween2.Completed:Connect(function()
		reached2 = true
	end)
	
	tween2:Play()
	
	-- Wait for completion
	startTime = tick()
	while not reached2 and autoMineEnabled do
		task.wait(0.1)
		if tick() - startTime > tween2Time + 2 then
			tween2:Cancel()
			break
		end
	end
	
	stopWalkAnim()
	
	if reached2 then
		debugPrint("Natural tween successful!")
		return true
	else
		debugPrint("Natural tween interrupted")
		return false
	end
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
		task.wait(0.3)
	end
	
	playWalkAnim(humanoid)
	humanoid:MoveTo(targetPos)
	
	local startTime = tick()
	local lastPos = rootPart.Position
	local stuckCounter = 0
	local character = player.Character
	
	while autoMineEnabled do
		task.wait(0.1)
		
		-- CRITICAL: Check for nearby mobs during pathfinding
		if strictAvoidance or isBeingAttacked then
			local nearbyMobs = getNearbyMobs(rootPart.Position, CRITICAL_MOB_DIST)
			if #nearbyMobs > 0 then
				debugPrint("Mob detected during pathfinding! Engaging combat...")
				stopWalkAnim()
				handleCombat(character)
				-- Resume walking animation and movement after combat
				playWalkAnim(humanoid)
				humanoid:MoveTo(targetPos)
			end
		end
		
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
				task.wait(0.3)
				stuckCounter = 0
			end
		else
			stuckCounter = 0
		end
		
		-- Timeout
		if tick() - startTime > STUCK_TIMEOUT then 
			debugPrint("Waypoint timeout - jumping and continuing")
			performPhysicsJump(humanoid, rootPart) 
			task.wait(0.3)
			return true -- Continue to next waypoint
		end
		
		lastPos = rootPart.Position
	end
	
	stopWalkAnim()
	return false
end

local function followPath(destination, pathfindFailures)
	pathfindFailures = pathfindFailures or 0
	
	local character = player.Character
	if not character then return false end
	local hum = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return false end

	local totalDist = (root.Position - destination).Magnitude
	
	-- ONLY use tween after 10 ACTUAL createAdvancedPath() failures
	if pathfindFailures >= MAX_PATHFIND_ATTEMPTS then
		debugPrint("PATHFINDING FAILED 10 TIMES - Using natural tween fallback")
		statusLabel.Text = "🚁 Tween fallback (pathfinding impossible)"
		return naturalTweenToPosition(character, destination)
	end
	
	-- If very close, just walk directly
	if totalDist < DIRECT_PATH_DIST then
		debugPrint("Close enough - walking directly")
		return moveToWaypoint(hum, root, destination, nil)
	end

	-- Try to compute a path
	if pathfindFailures > 0 then
		debugPrint("Pathfinding attempt", pathfindFailures + 1, "of", MAX_PATHFIND_ATTEMPTS)
		statusLabel.Text = "🗺️ Computing path... (attempt " .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
	else
		debugPrint("Computing initial path to destination")
		statusLabel.Text = "🗺️ Computing path..."
	end
	
	local path = createAdvancedPath(root.Position, destination)
	
	if not path then
		-- THIS IS A REAL PATHFINDING FAILURE - increment the counter
		debugPrint("createAdvancedPath() FAILED - no path found")
		statusLabel.Text = "⚠️ No path found, retrying... (" .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
		task.wait(0.5)
		return followPath(destination, pathfindFailures + 1)
	end
	
	local waypoints = path:GetWaypoints()
	debugPrint("Path found with", #waypoints, "waypoints")
	
	-- Filter out water waypoints
	local validWaypoints = {}
	for _, waypoint in ipairs(waypoints) do
		if validateWaypoint(waypoint) then
			table.insert(validWaypoints, waypoint)
		end
	end
	
	if #validWaypoints < 2 then
		-- Path exists but all in water - THIS IS A PATHFINDING FAILURE
		debugPrint("createAdvancedPath() succeeded but path is all water")
		statusLabel.Text = "⚠️ Path in water, retrying... (" .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
		task.wait(0.5)
		return followPath(destination, pathfindFailures + 1)
	end
	
	-- We have a valid path - RESET pathfindFailures since pathfinding succeeded
	-- Now we're just following waypoints, not pathfinding
	showPath(validWaypoints)
	statusLabel.Text = "🚶 Following path (" .. #validWaypoints .. " waypoints)"
	
	-- Dynamic pathfinding - recalculate path every 3 seconds
	local lastPathUpdate = tick()
	local PATH_UPDATE_INTERVAL = 3
	
	-- Follow waypoints with dynamic recalculation
	for i = 2, #validWaypoints do
		if not autoMineEnabled then
			stopWalkAnim()
			return false
		end
		
		-- Check if we should recalculate the path (every 3 seconds)
		if tick() - lastPathUpdate >= PATH_UPDATE_INTERVAL then
			local currentDist = (root.Position - destination).Magnitude
			
			-- If we're close enough, continue with current path
			if currentDist < DIRECT_PATH_DIST then
				debugPrint("Close to destination - keeping current path")
			else
				-- Recalculate path from current position
				debugPrint("🔄 Dynamic path update (3s interval)")
				statusLabel.Text = "🔄 Updating path..."
				
				local newPath = createAdvancedPath(root.Position, destination)
				
				if newPath then
					local newWaypoints = newPath:GetWaypoints()
					local newValidWaypoints = {}
					
					for _, waypoint in ipairs(newWaypoints) do
						if validateWaypoint(waypoint) then
							table.insert(newValidWaypoints, waypoint)
						end
					end
					
					if #newValidWaypoints > 1 then
						-- Use the new path
						debugPrint("Path updated with", #newValidWaypoints, "waypoints")
						validWaypoints = newValidWaypoints
						i = 1 -- Restart from beginning of new path
						showPath(validWaypoints)
						statusLabel.Text = "🚶 Following updated path"
					else
						debugPrint("New path invalid (water), keeping old path")
					end
				else
					debugPrint("Path update failed, keeping old path")
				end
			end
			
			lastPathUpdate = tick()
		end
		
		-- Don't go past the end of the waypoints array
		if i > #validWaypoints then
			break
		end
		
		local waypoint = validWaypoints[i]
		debugPrint("Moving to waypoint", i, "of", #validWaypoints)
		
		-- Check for mobs during pathfinding
		if strictAvoidance or isBeingAttacked then
			local hadCombat = handleCombat(character)
			if hadCombat then
				-- After combat, force path update on next iteration
				lastPathUpdate = tick() - PATH_UPDATE_INTERVAL
			end
		end
		
		if not moveToWaypoint(hum, root, waypoint.Position, waypoint.Action) then
			-- Failed to reach waypoint - NOT a pathfinding failure, just a movement issue
			-- Recompute path from current position but DON'T increment pathfindFailures
			debugPrint("Failed to reach waypoint - recomputing path (NOT a pathfinding failure)")
			task.wait(0.3)
			return followPath(destination, pathfindFailures) -- Same counter
		end
	end
	
	-- Successfully followed path - check if we're close to destination
	local finalDist = (root.Position - destination).Magnitude
	if finalDist < DIRECT_PATH_DIST * 2 then
		debugPrint("Reached destination area - final approach")
		return moveToWaypoint(hum, root, destination, nil)
	else
		-- Still too far - NOT a pathfinding failure, just need to recalculate
		debugPrint("Still", math.floor(finalDist), "studs from destination - recalculating path")
		return followPath(destination, pathfindFailures) -- Don't increment
	end
end

-- =========================================================================
-- MAIN LOOP (FIXED - NO MORE UNDERWATER ORE INFINITE LOOP)
-- =========================================================================

task.spawn(function()
	while true do
		task.wait(0.5)
		
		if autoMineEnabled and not isCurrentlyMining then
			-- Validate character exists and is alive
			local character = player.Character
			if not character or not character:FindFirstChild("HumanoidRootPart") then
				task.wait(1)
				continue
			end
			
			local humanoid = character:FindFirstChild("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				task.wait(1)
				continue
			end
			
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
			
			if rocksFolder and character and character:FindFirstChild("HumanoidRootPart") then
				local rootPart = character.HumanoidRootPart
				local currentPos = rootPart.Position
				local closestItem = nil
				local shortestDistance = math.huge
				
				-- Find Closest Target (EXCLUDING SKIPPED UNDERWATER ORES)
				for _, area in ipairs(rocksFolder:GetChildren()) do
					for _, spawnLoc in ipairs(area:GetChildren()) do
						if isSpawnLocation(spawnLoc) then
							for _, item in ipairs(spawnLoc:GetChildren()) do
								if isValidItem(item) and selectedTargets[item.Name] == true then
									-- FIXED: Skip ores that were marked as underwater
									if not isOreSkipped(item) then
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
				end
				
				if closestItem then
					debugPrint("Found target:", closestItem.Name, "at distance:", math.floor(shortestDistance))
					isCurrentlyMining = true
					local targetPos = closestItem:GetPivot().Position
					
					-- Check if target is underwater
					if isPositionInWater(targetPos) then
						statusLabel.Text = "💧 Skipping underwater ore (" .. closestItem.Name .. ")"
						debugPrint("Target is underwater, marking as skipped:", closestItem.Name)
						markOreAsSkipped(closestItem) -- FIXED: Mark this ore to skip it temporarily
						isCurrentlyMining = false
						task.wait(1)
					else
						-- ===================================
						-- MODE A: STEALTH (with combat)
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
								
								-- Switch to pickaxe for mining
								switchToPickaxe()
								
								statusLabel.Text = "⛏️ Mining..."
								local lastPositionCheck = tick()
								local lastHealthCheck = tick()
								local lastOreHealth = nil
								local POSITION_CHECK_INTERVAL = 2
								local HEALTH_CHECK_INTERVAL = 5
								local healthCheckFailures = 0
								
								-- Get initial ore health if possible
								if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
									lastOreHealth = closestItem.Health.Value
								end
								
								while closestItem.Parent and autoMineEnabled do
									-- CRITICAL: Continuously face the ore while mining
									if rootPart and (closestItem:FindFirstChild("PrimaryPart") or closestItem:IsA("BasePart")) then
										local orePos = closestItem:IsA("Model") and closestItem:GetPivot().Position or closestItem.Position
										local lookPos = Vector3.new(orePos.X, rootPart.Position.Y, orePos.Z)
										rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookPos)
									end
									
									-- Check if still in mining range
									local currentDistToOre = (rootPart.Position - targetPos).Magnitude
									if currentDistToOre > MINING_DEPTH + 8 then
										debugPrint("Too far from ore in stealth mode - repositioning")
										statusLabel.Text = "⚠️ Repositioning to ore..."
										TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
										task.wait(0.5)
									end
									
									-- Check for mobs and fight if combat is enabled OR if being attacked
									if strictAvoidance or isBeingAttacked then
										local hadCombat = handleCombat(character)
										if hadCombat then
											-- Switch back to pickaxe after combat
											switchToPickaxe()
											-- After combat, check if we're still near the ore
											local distToOre = (rootPart.Position - targetPos).Magnitude
											if distToOre > MINING_DEPTH + 5 then
												debugPrint("Moved too far during combat, repositioning...")
												statusLabel.Text = "🔄 Repositioning after combat..."
												TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
												task.wait(0.5)
											end
										end
									end
									
									-- Periodic health check (verify ore is taking damage)
									if tick() - lastHealthCheck >= HEALTH_CHECK_INTERVAL then
										if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
											local currentHealth = closestItem.Health.Value
											
											if lastOreHealth and currentHealth >= lastOreHealth then
												-- Ore not taking damage!
												healthCheckFailures = healthCheckFailures + 1
												debugPrint("WARNING: Ore health not decreasing in stealth mode! (Failures:", healthCheckFailures, ")")
												
												if healthCheckFailures >= 2 then
													debugPrint("Ore not being damaged - repositioning closer")
													statusLabel.Text = "⚠️ Mining ineffective - repositioning..."
													
													-- Move closer to ore
													local orePos = closestItem:GetPivot().Position
													local closerPos = orePos + Vector3.new(0, -MINING_DEPTH + 2, 0)
													TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(closerPos)}):Play()
													task.wait(0.5)
													
													-- Reset counter
													healthCheckFailures = 0
												end
											else
												-- Ore is taking damage - good!
												healthCheckFailures = 0
											end
											
											lastOreHealth = currentHealth
										end
										lastHealthCheck = tick()
									end
									
									-- Periodic position check for stealth mode
									if tick() - lastPositionCheck >= POSITION_CHECK_INTERVAL then
										local distToOre = (rootPart.Position - targetPos).Magnitude
										if distToOre > MINING_DEPTH + 10 then
											debugPrint("Player too far from ore in stealth mode, repositioning...")
											statusLabel.Text = "🔄 Repositioning to ore..."
											TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
											task.wait(0.5)
										end
										lastPositionCheck = tick()
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
						-- MODE B: LEGIT MODE (with combat & pathfinding retry)
						-- ===================================
						else 
							statusLabel.Text = "🏃 Walking to " .. closestItem.Name .. "..."
							disableFlightPhysics(rootPart)
							
							local arrived = followPath(targetPos)
							
							if arrived and autoMineEnabled then
								debugPrint("Arrived at target, mining...")
								
								-- Switch to pickaxe for mining
								switchToPickaxe()
								
								statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
								
								local mineStartTime = tick()
								local lastPositionCheck = tick()
								local lastHealthCheck = tick()
								local lastOreHealth = nil
								local POSITION_CHECK_INTERVAL = 2 -- Check every 2 seconds
								local HEALTH_CHECK_INTERVAL = 5 -- Check ore damage every 5 seconds
								local healthCheckFailures = 0
								
								-- Get initial ore health if possible
								if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
									lastOreHealth = closestItem.Health.Value
								end
								
								while closestItem.Parent and autoMineEnabled do
									-- CRITICAL: Continuously face the ore while mining
									if rootPart and (closestItem:FindFirstChild("PrimaryPart") or closestItem:IsA("BasePart")) then
										local orePos = closestItem:IsA("Model") and closestItem:GetPivot().Position or closestItem.Position
										local lookPos = Vector3.new(orePos.X, rootPart.Position.Y, orePos.Z)
										rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookPos)
									end
									
									-- Check if still in range of ore
									local currentDistToOre = (rootPart.Position - targetPos).Magnitude
									if currentDistToOre > 10 then
										debugPrint("Moved too far from ore during mining (", math.floor(currentDistToOre), "studs)")
										statusLabel.Text = "⚠️ Too far from ore! Repositioning..."
										
										-- Try to get back to ore
										local returnSuccess = followPath(targetPos, 0)
										
										if not returnSuccess then
											debugPrint("Failed to return to ore position")
											statusLabel.Text = "⚠️ Can't return to ore - moving to next"
											break
										end
										
										-- Switch back to pickaxe and continue
										switchToPickaxe()
										statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
									end
									
									-- Check for mobs and fight if combat is enabled OR if being attacked
									if strictAvoidance or isBeingAttacked then
										local hadCombat = handleCombat(character)
										if hadCombat then
											-- Switch back to pickaxe after combat
											switchToPickaxe()
											-- After combat, check if we're still near the ore
											local distToOre = (rootPart.Position - targetPos).Magnitude
											if distToOre > 15 then
												debugPrint("Moved too far during combat (", math.floor(distToOre), "studs), re-pathing...")
												statusLabel.Text = "🔄 Returning to ore after combat..."
												
												-- Redo pathfinding to get back to ore
												local returnSuccess = followPath(targetPos, 0)
												
												if not returnSuccess then
													debugPrint("Failed to return to ore after combat")
													statusLabel.Text = "⚠️ Can't return to ore - moving to next"
													break
												end
												
												-- Switch to pickaxe again after returning
												switchToPickaxe()
												debugPrint("Returned to ore, resuming mining")
												statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
											end
										end
									end
									
									-- Periodic health check (verify ore is taking damage)
									if tick() - lastHealthCheck >= HEALTH_CHECK_INTERVAL then
										if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
											local currentHealth = closestItem.Health.Value
											
											if lastOreHealth and currentHealth >= lastOreHealth then
												-- Ore not taking damage!
												healthCheckFailures = healthCheckFailures + 1
												debugPrint("WARNING: Ore health not decreasing! (Failures:", healthCheckFailures, ")")
												
												if healthCheckFailures >= 2 then
													debugPrint("Ore not being damaged after 10 seconds - repositioning")
													statusLabel.Text = "⚠️ Mining ineffective - repositioning..."
													
													-- Try moving slightly closer
													local orePos = closestItem:GetPivot().Position
													local closerPos = orePos + (rootPart.Position - orePos).Unit * -2
													rootPart.CFrame = CFrame.new(closerPos)
													task.wait(0.5)
													
													-- Reset counter
													healthCheckFailures = 0
												end
											else
												-- Ore is taking damage - good!
												healthCheckFailures = 0
											end
											
											lastOreHealth = currentHealth
										end
										lastHealthCheck = tick()
									end
									
									-- Periodic position check (detect if player fell)
									if tick() - lastPositionCheck >= POSITION_CHECK_INTERVAL then
										local distToOre = (rootPart.Position - targetPos).Magnitude
										if distToOre > 20 then
											debugPrint("Player too far from ore (fell?), re-pathing...")
											statusLabel.Text = "🔄 Repositioning to ore..."
											
											local repositionSuccess = followPath(targetPos, 0)
											
											if not repositionSuccess then
												debugPrint("Failed to reposition to ore")
												statusLabel.Text = "⚠️ Can't reach ore - moving to next"
												break
											end
											
											switchToPickaxe()
											debugPrint("Repositioned, resuming mining")
											statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
										end
										lastPositionCheck = tick()
									end
									
									pcall(function() 
										ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") 
									end)
									task.wait(0.1)
									
									-- Safety timeout - don't mine forever
									if tick() - mineStartTime > 60 then
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
					-- FIXED: Check if all ores are just temporarily skipped
					local totalSkipped = 0
					for _ in pairs(skippedUnderwaterOres) do
						totalSkipped = totalSkipped + 1
					end
					
					if totalSkipped > 0 then
						statusLabel.Text = "⏳ Waiting for skipped ores... (" .. totalSkipped .. " underwater)"
						debugPrint("All available ores are temporarily skipped (underwater)")
					else
						statusLabel.Text = "⚠️ No matching ores found"
						debugPrint("No ores found matching selected targets")
					end
					task.wait(2)
				end
			end
		end
	end
end)

-- =========================================================================
-- SIMPLE UI EVENTS
-- =========================================================================
local dragging, dragInput, mousePos, framePos

local function update(input)
	local delta = input.Position - mousePos
	mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
end

-- Dragging
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		mousePos = input.Position
		framePos = mainFrame.Position
		input.Changed:Connect(function() 
			if input.UserInputState == Enum.UserInputState.End then 
				dragging = false 
			end 
		end)
	end
end)

titleBar.InputChanged:Connect(function(input) 
	if input.UserInputType == Enum.UserInputType.MouseMovement then 
		dragInput = input 
	end 
end)

game:GetService("UserInputService").InputChanged:Connect(function(input) 
	if input == dragInput and dragging then 
		update(input) 
	end 
end)

-- Close
closeBtn.MouseButton1Click:Connect(function() 
	screenGui:Destroy() 
end)

-- Refresh
refreshBtn.MouseButton1Click:Connect(function()
	scanRocks()
	clearSkippedOres()
	debugPrint("Refreshed ore list and cleared skip list")
end)

-- Canvas resize
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

-- ESP toggles
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

-- Initial scan
task.wait(1)
scanRocks()
print("✅ Advanced Miner " .. SCRIPT_VERSION .. " - CANNON LAUNCHER ADDED!")
print("🎆 CANNON: Auto-fires from spawn to cave (World 2)")
print("🔘 Manual cannon button in GUI - press to re-fire")
print("🔄 DYNAMIC PATHFINDING: Recalculates path every 3 seconds")
print("🥊 COMBAT: Dodge rolls (25%) + Block with F key (33%)")
print("🎯 CONTINUOUS ore facing while mining")
print("🔍 Mining effectiveness checks every 5s")
print("🚁 FIXED TWEENING: Only after 10 REAL pathfinding failures")
print("📍 Fall detection every 2s with auto re-pathing")
print("⚔️ Smart combat tactics + defensive movement")
print("🔄 Auto-resume after death")
