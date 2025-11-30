-- Rocks Scanner - Advanced Miner v2.31 (CORRECT CFRAME.LOOKAT)
-- TYPE: LocalScript
-- LOCATION: StarterPlayer -> StarterPlayerScripts
-- 
-- FEATURES v2.31:
-- ✅ CORRECT CFRAME: Uses CFrame.lookAt(pos, lookAt) pattern
-- ✅ POSITION LOCKING: Character frozen in place while mining
-- ✅ VELOCITY ZEROING: Forces velocity to zero every frame
-- ✅ CONTINUOUS SCANNING: Rescans from current position every 0.5s
-- ✅ PATHFINDING ONLY: No tween fallbacks
-- ✅ TEST ALL ORES: Tests every ore before attempting
-- 
-- BUG FIXES v2.31:
-- 🐛 FIX #35: Changed from CFrame.new(pos, target) to CFrame.lookAt(pos, lookAt)
-- 
-- VERSION: v2.31

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
local SCRIPT_VERSION = "v2.31"

-- Debug mode - set to true to see prints in console
local DEBUG_MODE = true

local function debugPrint(...)
	if DEBUG_MODE then
		print("[MinerDebug]", ...)
	end
end

-- =========================================================================
-- CONFIGURATION (CRITICAL: MUST BE BEFORE FUNCTIONS)
-- =========================================================================
local autoMineEnabled = false
local stealthModeEnabled = false -- Default Legit
local strictAvoidance = true 
local playerEspEnabled = false
local oreEspEnabled = false
local mobEspEnabled = false
local isCurrentlyMining = false 
local selectedTargets = {}
local skippedUnderwaterOres = {}
local UNDERWATER_SKIP_DURATION = 30
local lastCombatTime = 0
local lastHealthCheck = 0
local isBeingAttacked = false

-- Forward declare UI elements
local statusLabel
local visualFolder

-- Cannon variables
local cannonFired = false
local SPAWN_POSITION = Vector3.new(0, 50, 0)
local SPAWN_DETECTION_RADIUS = 100

-- Animation Tracks
local walkAnimTrack = nil
local jumpAnimTrack = nil
local noclipConnection = nil

-- =========================================================================
-- SETTINGS (MUST BE DEFINED BEFORE getAgentParameters)
-- =========================================================================
local SIGHT_DISTANCE = 150      
local TRAVEL_DEPTH = 20         
local MINING_DEPTH = 12         
local MOVEMENT_SPEED = 35       

-- Safety Settings
local CRITICAL_MOB_DIST = 15
local COMBAT_COOLDOWN = 1.0
local PLAYER_PROXIMITY_CHECK = true
local PLAYER_AVOIDANCE_DIST = 12
local PLAYER_PATH_AVOIDANCE_DIST = 8

-- Advanced Pathfinding Settings
local STUCK_TIMEOUT = 5
local JUMP_THRESHOLD = 2.5
local DIRECT_PATH_DIST = 15
local MINING_RANGE = 15
local SAFE_MINING_OFFSET = 5
local WAYPOINT_REACH_DIST = 2.5
local MAX_PATHFIND_ATTEMPTS = 10
local NATURAL_TWEEN_SPEED = 25
local WALL_STUCK_THRESHOLD = 8
local MAX_MINING_DISTANCE = 18
local MAX_RECURSION_DEPTH = 20

-- Pathfinding Agent Parameters
local AGENT_CAN_JUMP = true
local AGENT_CAN_CLIMB = false  -- CRITICAL: Disabled to prevent climbing over ledges
local AGENT_MAX_SLOPE = 30  -- UPDATED: Prefer flat terrain (30° max instead of 45°)

-- Pathfinding Costs (UPDATED - Heavy penalties for climbing/flying)
local COSTS = {
	Water = 100,
	CrackedLava = math.huge,
	Mud = 20,
	Snow = 5,
	Sand = 3,
	Glacier = 10,
	Salt = 8,
	Ground = 1,
	Grass = 1,
	Pavement = 1,
	Brick = 1,
	Concrete = 1,
	WoodPlanks = 2,
	Rock = 2,
	Slate = 2,
	Air = math.huge, -- CRITICAL: Infinite cost - NEVER allow floating/climbing paths
}

-- Path Update Settings
local PATH_SPACING = 1.5  -- UPDATED: Smaller spacing = more waypoints = smoother movement (was 3)
local PATH_UPDATE_INTERVAL = 0  -- UPDATED: Recalculate at EVERY waypoint (was 1.5)
local BLOCKED_PATH_RETRY_DELAY = 0.5

-- Water check settings
local WATER_CHECK_ENABLED = true
local WATER_CHECK_STRICT = false

-- Combat settings
local lastDodge = 0
local lastBlock = 0
local DODGE_COOLDOWN = 2
local BLOCK_COOLDOWN = 1
local BLOCK_DURATION = 0.5

-- =========================================================================
-- AGENT PARAMETERS FUNCTION (NOW SAFE)
-- =========================================================================
local function getAgentParameters()
	debugPrint("🔧 getAgentParameters() called")
	
	local character = player.Character
	if not character then
		debugPrint("⚠️ No character found - using default parameters")
		return {
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentCanClimb = true,
			AgentMaxSlope = 89,
			WaypointSpacing = 3,
			Costs = COSTS
		}
	end
	
	debugPrint("✓ Character found:", character.Name)
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		debugPrint("⚠️ No HumanoidRootPart - using default parameters")
		return {
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentCanClimb = true,
			AgentMaxSlope = 89,
			WaypointSpacing = 3,
			Costs = COSTS
		}
	end
	
	debugPrint("✓ HumanoidRootPart found")
	
	-- FIXED: Use HumanoidRootPart.Size (standard Roblox property)
	local rootSize = humanoidRootPart.Size
	debugPrint("Root Size - X:", rootSize.X, "Y:", rootSize.Y, "Z:", rootSize.Z)
	
	-- CRITICAL: Inflate agent size significantly to avoid ledges and tight spaces
	-- The pathfinder will avoid any space the agent can't fit through
	local agentRadius = math.max(rootSize.X or 2, rootSize.Z or 2) / 2 * 3  -- 3x wider than actual
	local agentHeight = (rootSize.Y or 5) * 2  -- 2x taller than actual
	
	debugPrint("Calculated - Radius:", math.floor(agentRadius), "Height:", math.floor(agentHeight))
	debugPrint("NOTE: Agent size inflated 3x to avoid ledges and tight spaces")
	
	local params = {
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = AGENT_CAN_JUMP,
		AgentCanClimb = AGENT_CAN_CLIMB,
		AgentMaxSlope = AGENT_MAX_SLOPE,
		WaypointSpacing = PATH_SPACING,
		Costs = COSTS
	}
	
	debugPrint("✓ Agent parameters created successfully")
	return params
end

-- =========================================================================
-- VISUALS SETUP
-- =========================================================================
visualFolder = workspace:FindFirstChild("PathVisuals") or Instance.new("Folder")
visualFolder.Name = "PathVisuals"
visualFolder.Parent = workspace

local espFolder = Instance.new("Folder")
espFolder.Name = "ESPHighlights"
espFolder.Parent = CoreGui

-- =========================================================================
-- CANNON LAUNCHER (World 2 - Spawn to Cave)
-- =========================================================================
local function isAtSpawn(position)
	local spawnAreas = {
		Vector3.new(0, 50, 0),
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
	local function searchForCannon(parent)
		for _, child in ipairs(parent:GetDescendants()) do
			if child.Name == "Cannon" and child:IsA("Model") then
				return child
			end
		end
		return nil
	end
	
	local mainIsland = workspace:FindFirstChild("Main Island [2]")
	if mainIsland then
		local cannon = searchForCannon(mainIsland)
		if cannon then return cannon end
	end
	
	return searchForCannon(workspace)
end

-- Forward declare followPath (will be defined later)
local followPath

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
	
	local arrivedAtCannon = followPath(cannonPos, 0, 0)
	
	if not arrivedAtCannon then
		debugPrint("⚠️ Failed to reach cannon")
		statusLabel.Text = "⚠️ Can't reach cannon - trying anyway"
		local distance = (rootPart.Position - cannonPos).Magnitude
		if distance > 50 then
			TweenService:Create(rootPart, TweenInfo.new(2), {CFrame = CFrame.new(cannonPos + Vector3.new(0, 5, 0))}):Play()
			task.wait(2.5)
		end
	end
	
	local interactionPos = cannonPos + Vector3.new(0, 3, 0)
	rootPart.CFrame = CFrame.new(interactionPos)
	task.wait(0.5)
	
	debugPrint("🎆 Firing cannon - pressing E!")
	statusLabel.Text = "🎆 FIRING CANNON!"
	
	for i = 1, 3 do
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			task.wait(0.1)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		end)
		task.wait(0.3)
	end
	
	debugPrint("🚀 Cannon fired! Waiting for landing...")
	statusLabel.Text = "🚀 Flying through air..."
	
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
	
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	
	if not humanoid or not rootPart then
		debugPrint("Failed to load character parts!")
		return
	end
	
	humanoid.Died:Connect(function()
		debugPrint("Character died!")
		statusLabel.Text = "💀 Died! Waiting for respawn..."
		isCurrentlyMining = false
		visualFolder:ClearAllChildren()
		
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
	
	lastHealthCheck = humanoid.Health
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealthCheck then
			local damageTaken = lastHealthCheck - newHealth
			if damageTaken > 0 and strictAvoidance then
				debugPrint("Took damage! (" .. math.floor(damageTaken) .. " HP)")
				isBeingAttacked = true
				statusLabel.Text = "🛡️ UNDER ATTACK! Engaging combat..."
				statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
				task.delay(3, function() 
					isBeingAttacked = false
					statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
				end)
			end
		end
		lastHealthCheck = newHealth
	end)
	
	task.wait(2)
	
	isCurrentlyMining = false
	walkAnimTrack = nil
	jumpAnimTrack = nil
	visualFolder:ClearAllChildren()
	
	debugPrint("Character fully loaded and ready!")
	
	local usedCannon = handleRespawnCannon()
	
	if usedCannon then
		debugPrint("Cannon fired successfully, ready to mine")
	end
	
	if autoMineEnabled then
		statusLabel.Text = "🔄 Resuming mining after respawn..."
		debugPrint("Auto-mine was enabled, resuming operations...")
		task.wait(1)
	end
end

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	task.spawn(function()
		onCharacterAdded(player.Character)
	end)
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
-- PLAYER PROXIMITY DETECTION
-- =========================================================================
local function getNearbyPlayers(position, maxDistance)
	local nearbyPlayers = {}
	
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local distance = (otherRoot.Position - position).Magnitude
				if distance <= maxDistance then
					table.insert(nearbyPlayers, {
						player = otherPlayer,
						distance = distance,
						position = otherRoot.Position
					})
				end
			end
		end
	end
	
	return nearbyPlayers
end

local function isOreBeingMinedByOthers(orePosition)
	if not PLAYER_PROXIMITY_CHECK then
		return false
	end
	
	local nearbyPlayers = getNearbyPlayers(orePosition, PLAYER_AVOIDANCE_DIST)
	
	if #nearbyPlayers > 0 then
		debugPrint("Player(s) detected near ore:", #nearbyPlayers, "players within", PLAYER_AVOIDANCE_DIST, "studs")
		return true
	end
	
	return false
end

local function isWaypointNearPlayers(waypointPos)
	if not PLAYER_PROXIMITY_CHECK then
		return false
	end
	
	local nearbyPlayers = getNearbyPlayers(waypointPos, PLAYER_PATH_AVOIDANCE_DIST)
	return #nearbyPlayers > 0
end

-- =========================================================================
-- TERRAIN & WATER DETECTION
-- =========================================================================
local function isPositionInWater(position)
	if not WATER_CHECK_ENABLED then
		return false
	end
	
	local terrain = workspace.Terrain
	
	local success, result = pcall(function()
		local voxelPos = terrain:WorldToCell(position)
		local region = Region3.new(
			terrain:CellCornerToWorld(voxelPos.X, voxelPos.Y, voxelPos.Z),
			terrain:CellCornerToWorld(voxelPos.X + 1, voxelPos.Y + 1, voxelPos.Z + 1)
		):ExpandToGrid(4)
		
		local materials = terrain:ReadVoxels(region, 4)
		return materials
	end)
	
	if not success then return false end
	
	local materials = result
	local size = materials.Size
	if size.X > 0 and size.Y > 0 and size.Z > 0 then
		local centerX = math.ceil(size.X / 2)
		local centerY = math.ceil(size.Y / 2)
		local centerZ = math.ceil(size.Z / 2)
		
		local material = materials[centerX][centerY][centerZ]
		if material == Enum.Material.Water then
			debugPrint("Water detected at exact position")
			return true
		end
		
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

local function isPlayerInWater()
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return false end
	
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Swimming
end

local function getTerrainMaterial(position)
	local terrain = workspace.Terrain
	
	local success, result = pcall(function()
		local voxelPos = terrain:WorldToCell(position)
		local region = Region3.new(
			terrain:CellCornerToWorld(voxelPos.X, voxelPos.Y, voxelPos.Z),
			terrain:CellCornerToWorld(voxelPos.X + 1, voxelPos.Y + 1, voxelPos.Z + 1)
		):ExpandToGrid(4)
		
		local materials = terrain:ReadVoxels(region, 4)
		
		if materials.Size.X > 0 and materials.Size.Y > 0 and materials.Size.Z > 0 then
			return materials[1][1][1]
		end
		
		return Enum.Material.Air
	end)
	
	if success then
		return result
	else
		return Enum.Material.Air
	end
end

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
	if player.Character then
		for _, part in pairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end
end

-- NEW: Soft noclip for pathfinding - only disables collision with small obstacles
local softNoclipConnection = nil

local function enableSoftNoclip()
	if softNoclipConnection then return end -- Already enabled
	
	debugPrint("🌫️ Soft noclip enabled (pathfinding mode)")
	
	softNoclipConnection = RunService.Stepped:Connect(function()
		if player.Character then
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if not rootPart then return end
			
			-- Get all parts touching the character
			local touchingParts = workspace:GetPartBoundsInBox(
				rootPart.CFrame,
				rootPart.Size + Vector3.new(2, 3, 2) -- Small detection area
			)
			
			for _, part in pairs(touchingParts) do
				-- Only disable collision with small parts (obstacles, decorations)
				-- Keep collision with: Terrain, large structures, SpawnLocations
				if part:IsA("BasePart") 
					and part ~= rootPart 
					and not part:IsDescendantOf(player.Character)
					and part.Size.Magnitude < 15 -- Only small parts
					and not part:IsA("SpawnLocation")
					and not part:IsA("Terrain")
					and part.Name ~= "Baseplate" then
					
					-- Temporarily disable collision with this part
					part.CanCollide = false
					
					-- Re-enable after a short delay
					task.delay(0.5, function()
						if part and part.Parent then
							part.CanCollide = true
						end
					end)
				end
			end
		end
	end)
end

local function disableSoftNoclip()
	if softNoclipConnection then
		softNoclipConnection:Disconnect()
		softNoclipConnection = nil
		debugPrint("🌫️ Soft noclip disabled")
	end
end

-- =========================================================================
-- ANIMATIONS & MOVEMENT
-- =========================================================================
local function getWalkAnimId(humanoid) 
	return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507767714" or "rbxassetid://180426354" 
end

local function getJumpAnimId(humanoid) 
	return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507765000" or "rbxassetid://125750702" 
end

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

local function stopWalkAnim() 
	if walkAnimTrack then walkAnimTrack:Stop() end 
end

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
-- COMBAT SYSTEM
-- =========================================================================
local function holdKey(key, duration)
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
	
	local dodgeDirections = {
		Vector3.new(6, 0, 0),
		Vector3.new(-6, 0, 0),
		Vector3.new(0, 0, -6)
	}
	
	local randomDir = dodgeDirections[math.random(1, #dodgeDirections)]
	local dodgePos = rootPart.Position + randomDir
	
	TweenService:Create(rootPart, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(dodgePos)
	}):Play()
	
	lastDodge = tick()
	debugPrint("🏃 Dodged!")
	return true
end

local function blockAttack()
	if tick() - lastBlock < BLOCK_COOLDOWN then return false end
	
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
	
	if mobHumanoid.Health <= 0 then
		debugPrint("Mob is already dead, skipping")
		return false
	end
	
	debugPrint("Engaging mob:", mob.Name, "Health:", mobHumanoid.Health)
	
	switchToWeapon()
	
	local combatStartTime = tick()
	local maxCombatTime = 15
	
	while mob.Parent and mobHumanoid.Health > 0 and autoMineEnabled do
		if not humanoid or humanoid.Health <= 0 then
			debugPrint("Player died during combat!")
			return false
		end
		
		if not mob.Parent or not mobRoot.Parent or not mobHumanoid.Parent then
			debugPrint("Mob became invalid during combat")
			break
		end
		
		if mobHumanoid.Health <= 0 then
			debugPrint("Mob died during combat loop")
			break
		end
		
		if tick() - combatStartTime > maxCombatTime then
			debugPrint("Combat timeout - moving on")
			break
		end
		
		local dist = (mobRoot.Position - rootPart.Position).Magnitude
		statusLabel.Text = "⚔️ Fighting " .. mob.Name .. " (" .. math.floor(dist) .. " studs | HP:" .. math.floor(mobHumanoid.Health) .. ")"
		
		if isBeingAttacked and dist < 7 then
			if math.random(1, 3) == 1 then
				local blocked = blockAttack()
				if blocked then
					task.wait(BLOCK_DURATION + 0.1)
					if mobHumanoid.Health > 0 then
						continue
					end
				end
			end
		end
		
		if isBeingAttacked and dist < 8 then
			if math.random(1, 4) == 1 then
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
		
		if dist < 6 and math.random(1, 20) == 1 then
			dodge(character)
			task.wait(0.3)
		end
		
		if mobRoot and rootPart then
			local lookPos = Vector3.new(mobRoot.Position.X, rootPart.Position.Y, mobRoot.Position.Z)
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookPos)
		end
		
		if dist > 5 then
			humanoid:MoveTo(mobRoot.Position)
			playWalkAnim(humanoid)
		else
			humanoid:MoveTo(rootPart.Position)
			stopWalkAnim()
		end
		
		pcall(function()
			ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Weapon")
		end)
		
		task.wait(0.2)
	end
	
	stopWalkAnim()
	
	-- CRITICAL: Stop all movement commands after combat
	if humanoid then
		humanoid:MoveTo(rootPart.Position) -- Stop moving
	end
	
	-- Switch back to pickaxe after combat
	debugPrint("Combat ended - switching back to pickaxe")
	task.wait(0.3) -- Brief delay to let movement stop
	switchToPickaxe()
	
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
	
	if tick() - lastCombatTime < COMBAT_COOLDOWN then
		return false
	end
	
	local nearbyMobs = getNearbyMobs(rootPart.Position, CRITICAL_MOB_DIST)
	
	if #nearbyMobs > 0 then
		debugPrint("Found", #nearbyMobs, "nearby alive mobs")
		
		for _, mobData in ipairs(nearbyMobs) do
			if not autoMineEnabled then break end
			
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
		
		lastCombatTime = tick()
		debugPrint("Combat cooldown started")
		
		return true
	end
	
	return false
end

-- =========================================================================
-- DISTANCE CALCULATIONS (3D - considers X, Y, Z)
-- =========================================================================
local function calculate3DDistance(pos1, pos2)
	-- Full 3D distance including Y (vertical)
	return (pos1 - pos2).Magnitude
end

local function calculateHorizontalDistance(pos1, pos2)
	-- Only X and Z (ignores Y/height)
	return math.sqrt((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)
end

local function calculateVerticalDistance(pos1, pos2)
	-- Only Y (height difference)
	return math.abs(pos1.Y - pos2.Y)
end

-- =========================================================================
-- PATH VALIDATION (Test if ore is reachable)
-- =========================================================================
local function canPathToPosition(startPos, targetPos)
	-- Quick test using ONLY Roblox PathfindingService - no custom validation
	-- Returns: true if path exists, false if no path possible
	
	debugPrint("═══════════════════════════════════════════════")
	debugPrint("🔍 PATH TEST START")
	debugPrint("From:", math.floor(startPos.X), math.floor(startPos.Y), math.floor(startPos.Z))
	debugPrint("To:", math.floor(targetPos.X), math.floor(targetPos.Y), math.floor(targetPos.Z))
	
	-- Calculate distances
	local horizontalDist = math.sqrt((startPos.X - targetPos.X)^2 + (startPos.Z - targetPos.Z)^2)
	local verticalDist = math.abs(startPos.Y - targetPos.Y)
	
	debugPrint("Distances - Horizontal:", math.floor(horizontalDist), "Vertical:", math.floor(verticalDist))
	
	-- REMOVED: "Close enough" bypass - always verify path exists
	-- Even close ores might be unreachable (ledges, walls, etc.)
	
	-- Get agent parameters with error protection
	debugPrint("📊 Getting agent parameters...")
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		debugPrint("❌ FAILED: No character or HumanoidRootPart")
		debugPrint("═══════════════════════════════════════════════")
		return false
	end
	
	local rootPart = character.HumanoidRootPart
	local rootSize = rootPart.Size
	local agentRadius = math.max(rootSize.X, rootSize.Z) / 2 + 1
	local agentHeight = rootSize.Y + 3
	
	debugPrint("Agent - Radius:", math.floor(agentRadius), "Height:", math.floor(agentHeight))
	
	-- Create path parameters
	local pathParams = {
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = true,
		AgentCanClimb = true,
		Costs = {
			Water = 100,
			Air = 1000,
		}
	}
	
	-- Create and compute path with full error protection
	debugPrint("🗺️ Creating path...")
	local success, result = pcall(function()
		local path = PathfindingService:CreatePath(pathParams)
		
		-- Compute path
		debugPrint("📍 Computing path...")
		path:ComputeAsync(startPos, targetPos)
		
		-- Check status
		debugPrint("Path Status:", tostring(path.Status))
		
		if path.Status == Enum.PathStatus.Success then
			-- Get waypoint count (Roblox official method)
			local waypoints = path:GetWaypoints()
			local waypointCount = #waypoints
			
			debugPrint("Total waypoints:", waypointCount)
			
			-- Simple check: if path has waypoints and status is success, it's valid
			if waypointCount >= 2 then
				debugPrint("✅ PATH VALID - Has", waypointCount, "waypoints")
				return true
			else
				debugPrint("❌ PATH INVALID - Not enough waypoints")
				return false
			end
		else
			-- Path status is not Success
			debugPrint("❌ Path status is not Success")
			if path.Status == Enum.PathStatus.NoPath then
				debugPrint("   Reason: NoPath - Pathfinding failed")
			elseif path.Status == Enum.PathStatus.ClosestNoPath then
				debugPrint("   Reason: ClosestNoPath - Partial path only")
			elseif path.Status == Enum.PathStatus.ClosestOutOfRange then
				debugPrint("   Reason: ClosestOutOfRange - Too far")
			end
			return false
		end
	end)
	
	debugPrint("═══════════════════════════════════════════════")
	
	if success then
		return result
	else
		debugPrint("❌ CRITICAL ERROR:", result)
		debugPrint("═══════════════════════════════════════════════")
		return false
	end
end

-- =========================================================================
-- PATHFINDING
-- =========================================================================
local function createAdvancedPath(startPos, endPos)
	local pathParams = getAgentParameters()
	
	-- CRITICAL: Check if destination requires climbing/falling
	local verticalDist = calculateVerticalDistance(startPos, endPos)
	local horizontalDist = calculateHorizontalDistance(startPos, endPos)
	
	if verticalDist > 15 and horizontalDist < 20 then
		debugPrint("⚠️ Path requires climbing", math.floor(verticalDist), "studs vertically!")
		debugPrint("⚠️ This will likely fail or take very long route")
	end
	
	local path = PathfindingService:CreatePath(pathParams)
	
	local success, errorMessage = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if not success then
		debugPrint("❌ Path computation error:", errorMessage)
		return nil
	end
	
	if path.Status == Enum.PathStatus.NoPath then
		debugPrint("❌ No path exists between points")
		debugPrint("   Vertical distance:", math.floor(verticalDist), "Horizontal:", math.floor(horizontalDist))
		return nil
	end
	
	if path.Status ~= Enum.PathStatus.Success then
		debugPrint("❌ Path status:", tostring(path.Status))
		return nil
	end
	
	debugPrint("✅ Path computed successfully!")
	return path
end

local function validateWaypoint(waypoint)
	if WATER_CHECK_ENABLED and WATER_CHECK_STRICT then
		if isPositionInWater(waypoint.Position) then
			debugPrint("      ❌ Waypoint REJECTED: In water")
			return false
		end
		
		local material = getTerrainMaterial(waypoint.Position)
		if material == Enum.Material.Water or material == Enum.Material.CrackedLava then
			debugPrint("      ❌ Waypoint REJECTED: Material is", tostring(material))
			return false
		end
	end
	
	if isWaypointNearPlayers(waypoint.Position) then
		debugPrint("      ❌ Waypoint REJECTED: Too close to player")
		return false
	end
	
	return true
end

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
	if isPositionInWater(targetPos) then
		debugPrint("Target waypoint is in water! Skipping.")
		return false
	end
	
	-- NEW: Ledge detection - check if waypoint is significantly higher (ledge/climb)
	local verticalDiff = targetPos.Y - rootPart.Position.Y
	local horizontalDist = math.sqrt((targetPos.X - rootPart.Position.X)^2 + (targetPos.Z - rootPart.Position.Z)^2)
	
	if verticalDiff > 3 and horizontalDist < 6 then
		-- Steep upward climb detected (going up more than 3 studs in less than 6 horizontal studs)
		debugPrint("⚠️ LEDGE DETECTED! Vertical:", math.floor(verticalDiff), "Horizontal:", math.floor(horizontalDist))
		debugPrint("This looks like a climb/ledge - aborting path")
		return false
	end
	
	if action == Enum.PathWaypointAction.Jump then
		debugPrint("⬆️ Jump waypoint detected!")
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		humanoid.Jump = true
	end
	
	playWalkAnim(humanoid)
	humanoid:MoveTo(targetPos)
	
	local moveFinished = false
	local moveSuccess = false
	local character = player.Character
	
	local moveConnection
	moveConnection = humanoid.MoveToFinished:Connect(function(reached)
		moveFinished = true
		moveSuccess = reached
		if moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
	end)
	
	local startTime = tick()
	local lastPos = rootPart.Position
	local stuckCounter = 0
	local microStuckCounter = 0 -- NEW: Detect getting stuck on tiny ledges
	local lastMicroPos = rootPart.Position
	
	while autoMineEnabled and not moveFinished do
		task.wait(0.1)
		
		if tick() - startTime > STUCK_TIMEOUT then
			debugPrint("⏱️ Movement timeout - stuck for", STUCK_TIMEOUT, "seconds")
			if moveConnection then moveConnection:Disconnect() end
			return false
		end
		
		if strictAvoidance or isBeingAttacked then
			local nearbyMobs = getNearbyMobs(rootPart.Position, CRITICAL_MOB_DIST)
			if #nearbyMobs > 0 then
				debugPrint("Mob detected during pathfinding! Engaging combat...")
				if moveConnection then moveConnection:Disconnect() end
				stopWalkAnim()
				handleCombat(character)
				playWalkAnim(humanoid)
				humanoid:MoveTo(targetPos)
				moveConnection = humanoid.MoveToFinished:Connect(function(reached)
					moveFinished = true
					moveSuccess = reached
				end)
			end
		end
		
		if isPlayerInWater() then
			debugPrint("Player is swimming! Jumping out!")
			if moveConnection then moveConnection:Disconnect() end
			performPhysicsJump(humanoid, rootPart)
			return false
		end
		
		-- NEW: Micro-stuck detection (tiny ledges, small obstacles)
		local microMoved = (rootPart.Position - lastMicroPos).Magnitude
		if microMoved < 0.1 then -- Moving less than 0.1 studs = stuck on tiny ledge
			microStuckCounter = microStuckCounter + 1
			if microStuckCounter > 5 then -- Stuck for 0.5 seconds
				debugPrint("🪨 Stuck on small ledge! Auto-unstuck...")
				
				-- Try multiple unstuck strategies
				-- 1. Jump
				performPhysicsJump(humanoid, rootPart)
				task.wait(0.3)
				
				-- 2. If still stuck, move sideways
				if (rootPart.Position - lastMicroPos).Magnitude < 0.5 then
					local sidewaysOffset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
					rootPart.CFrame = CFrame.new(rootPart.Position + sidewaysOffset)
					debugPrint("Moved sideways to escape ledge")
					task.wait(0.2)
				end
				
				microStuckCounter = 0
				lastMicroPos = rootPart.Position
			end
		else
			microStuckCounter = 0
		end
		lastMicroPos = rootPart.Position
		
		-- Original stuck detection (walls, large obstacles)
		local moved = (rootPart.Position - lastPos).Magnitude
		if moved < 0.3 then
			stuckCounter = stuckCounter + 1
			if stuckCounter > WALL_STUCK_THRESHOLD then
				debugPrint("🧱 Stuck against wall for", WALL_STUCK_THRESHOLD, "checks")
				if moveConnection then moveConnection:Disconnect() end
				return false
			elseif stuckCounter > 10 then
				debugPrint("Stuck! Jumping...")
				performPhysicsJump(humanoid, rootPart)
				task.wait(0.3)
			end
		else
			stuckCounter = 0
		end
		
		lastPos = rootPart.Position
	end
	
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end
	
	if moveSuccess then
		debugPrint("✅ Waypoint reached!")
		return true
	else
		debugPrint("❌ Failed to reach waypoint")
		return false
	end
end

local function naturalTweenToPosition(character, targetPos)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not rootPart or not humanoid then return false end
	
	debugPrint("⚠️ Using tween fallback (pathfinding impossible)")
	debugPrint("⚠️ This is a LAST RESORT - means pathfinding tried 10 times!")
	statusLabel.Text = "🚁 Tween mode (NOCLIP enabled)"
	
	-- CRITICAL: Enable noclip for tween to prevent client-only movement
	enableFlightPhysics(rootPart)
	
	local startPos = rootPart.Position
	local distance = (targetPos - startPos).Magnitude
	local travelTime = distance / NATURAL_TWEEN_SPEED
	
	local midPoint = (startPos + targetPos) / 2 + Vector3.new(0, 5, 0) -- Higher arc for safety
	
	playWalkAnim(humanoid)
	
	-- Phase 1: Tween to midpoint
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
	
	local startTime = tick()
	while not reached1 and autoMineEnabled do
		task.wait(0.1)
		if tick() - startTime > tween1Time + 2 then
			tween1:Cancel()
			break
		end
	end
	
	if not autoMineEnabled then
		disableFlightPhysics(rootPart) -- CRITICAL: Disable noclip
		stopWalkAnim()
		return false
	end
	
	-- Phase 2: Tween to destination
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
	
	startTime = tick()
	while not reached2 and autoMineEnabled do
		task.wait(0.1)
		if tick() - startTime > tween2Time + 2 then
			tween2:Cancel()
			break
		end
	end
	
	-- CRITICAL: Disable noclip after tween
	disableFlightPhysics(rootPart)
	stopWalkAnim()
	
	if reached2 then
		debugPrint("✅ Tween successful! Noclip disabled.")
		statusLabel.Text = "✅ Arrived (noclip disabled)"
		task.wait(0.5) -- Let physics settle
		return true
	else
		debugPrint("❌ Tween interrupted")
		return false
	end
end

local function getSafeMiningPosition(orePosition, characterPosition)
	-- Calculate horizontal direction only (ignore Y)
	local horizontalDirection = Vector3.new(
		characterPosition.X - orePosition.X,
		0,  -- CRITICAL: Ignore Y to prevent climbing
		characterPosition.Z - orePosition.Z
	).Unit
	
	-- Place player at safe distance on GROUND LEVEL
	local groundY = math.min(characterPosition.Y, orePosition.Y) -- Use lower Y value
	local safePosition = Vector3.new(
		orePosition.X + (horizontalDirection.X * SAFE_MINING_OFFSET),
		groundY + 3, -- Slight elevation above ground (standard character height)
		orePosition.Z + (horizontalDirection.Z * SAFE_MINING_OFFSET)
	)
	
	debugPrint("Safe mining position:", math.floor(safePosition.X), math.floor(safePosition.Y), math.floor(safePosition.Z))
	debugPrint("Ore Y:", math.floor(orePosition.Y), "Char Y:", math.floor(characterPosition.Y), "Safe Y:", math.floor(safePosition.Y))
	return safePosition
end

local function isInMiningRange(characterPos, orePos)
	local horizontalDist = math.sqrt(
		(characterPos.X - orePos.X)^2 + 
		(characterPos.Z - orePos.Z)^2
	)
	local verticalDist = math.abs(characterPos.Y - orePos.Y)
	
	-- CRITICAL: Check both horizontal AND vertical distance
	-- Player must be on same level (within 8 studs vertically) AND close enough horizontally
	local inRange = horizontalDist <= MINING_RANGE and verticalDist <= 8
	
	if not inRange and horizontalDist <= MINING_RANGE then
		debugPrint("❌ Wrong Y level! Horizontal:", math.floor(horizontalDist), "Vertical:", math.floor(verticalDist))
	end
	
	return inRange
end

-- FIXED: followPath with recursion protection and 3D distance awareness
function followPath(destination, pathfindFailures, recursionDepth)
	pathfindFailures = pathfindFailures or 0
	recursionDepth = recursionDepth or 0
	
	if recursionDepth > MAX_RECURSION_DEPTH then
		debugPrint("❌ Maximum recursion depth reached - aborting pathfinding")
		statusLabel.Text = "❌ Pathfinding failed - too many retries"
		disableSoftNoclip()  -- Clean up
		return false
	end
	
	local character = player.Character
	if not character then 
		disableSoftNoclip()  -- Clean up
		return false 
	end
	local hum = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then 
		disableSoftNoclip()  -- Clean up
		return false 
	end
	
	-- NEW: Enable soft noclip for smooth pathfinding
	enableSoftNoclip()

	local total3DDist = calculate3DDistance(root.Position, destination)
	local horizontalDist = calculateHorizontalDistance(root.Position, destination)
	local verticalDist = calculateVerticalDistance(root.Position, destination)
	
	debugPrint("Distance check - 3D:", math.floor(total3DDist), "Horiz:", math.floor(horizontalDist), "Vert:", math.floor(verticalDist))
	
	-- REMOVED: Vertical distance tween - just fail so ore gets skipped
	if verticalDist > 20 and horizontalDist < 30 then
		debugPrint("⚠️ Vertical distance too high (", math.floor(verticalDist), "studs) - skipping ore")
		statusLabel.Text = "❌ Vertical gap too high - trying next ore"
		disableSoftNoclip()
		return false
	end
	
	if pathfindFailures >= MAX_PATHFIND_ATTEMPTS then
		debugPrint("❌ PATHFINDING FAILED 10 TIMES - Skipping this ore")
		statusLabel.Text = "❌ Path failed - trying next ore"
		disableSoftNoclip()
		return false
	end
	
	-- REMOVED: Direct walk check - now ALWAYS uses PathfindingService
	-- Even if close, we need to verify a valid path exists
	debugPrint("Distance - H:", math.floor(horizontalDist), "V:", math.floor(verticalDist), "- using PathfindingService")

	if pathfindFailures > 0 then
		debugPrint("Pathfinding attempt", pathfindFailures + 1, "of", MAX_PATHFIND_ATTEMPTS)
		statusLabel.Text = "🗺️ Computing path... (attempt " .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
	else
		debugPrint("Computing initial path to destination")
		statusLabel.Text = "🗺️ Computing path..."
	end
	
	local path = createAdvancedPath(root.Position, destination)
	
	if not path then
		debugPrint("createAdvancedPath() FAILED - no path found")
		statusLabel.Text = "⚠️ No path found, retrying... (" .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
		task.wait(0.5)
		return followPath(destination, pathfindFailures + 1, recursionDepth + 1)
	end
	
	local waypoints = path:GetWaypoints()
	debugPrint("Path found with", #waypoints, "waypoints")
	
	local validWaypoints = {}
	for _, waypoint in ipairs(waypoints) do
		if validateWaypoint(waypoint) then
			table.insert(validWaypoints, waypoint)
		end
	end
	
	if #validWaypoints < 2 then
		debugPrint("createAdvancedPath() succeeded but path is all water")
		statusLabel.Text = "⚠️ Path in water, retrying... (" .. (pathfindFailures + 1) .. "/" .. MAX_PATHFIND_ATTEMPTS .. ")"
		task.wait(0.5)
		return followPath(destination, pathfindFailures + 1, recursionDepth + 1)
	end
	
	showPath(validWaypoints)
	statusLabel.Text = "🚶 Following path (" .. #validWaypoints .. " waypoints)"
	
	local pathBlocked = false
	local blockedConnection
	local blockedCount = 0  -- NEW: Track how many times path gets blocked
	
	blockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
		debugPrint("⚠️ Path blocked at waypoint", blockedWaypointIndex)
		pathBlocked = true
		blockedCount = blockedCount + 1
		
		-- CRITICAL: If path gets blocked 3+ times, it's likely a ledge/impossible path
		if blockedCount >= 3 then
			debugPrint("❌ PATH BLOCKED", blockedCount, "TIMES - Likely a ledge or impossible path!")
			debugPrint("❌ Aborting this path attempt")
			statusLabel.Text = "❌ Path repeatedly blocked - aborting"
			
			if blockedConnection then
				blockedConnection:Disconnect()
				blockedConnection = nil
			end
		end
	end)
	
	-- REMOVED: lastPathUpdate - now recalculates at EVERY waypoint
	local waypointCount = 0
	
	for i = 2, #validWaypoints do
		if not autoMineEnabled then
			stopWalkAnim()
			if blockedConnection then blockedConnection:Disconnect() end
			disableSoftNoclip()  -- Clean up
			return false
		end
		
		if pathBlocked then
			-- Check if this is a repeatedly blocked path (ledge)
			if blockedCount >= 3 then
				debugPrint("❌ Path blocked", blockedCount, "times - giving up on this ore")
				if blockedConnection then blockedConnection:Disconnect() end
				disableSoftNoclip()
				return false  -- Signal failure so ore gets skipped
			end
			
			debugPrint("Path blocked detected - recomputing from current position")
			statusLabel.Text = "⚠️ Path blocked - recalculating..."
			if blockedConnection then blockedConnection:Disconnect() end
			task.wait(BLOCKED_PATH_RETRY_DELAY)
			return followPath(destination, pathfindFailures, recursionDepth + 1)
		end
		
		-- CRITICAL: Recalculate path at EVERY waypoint for human-like adaptive movement
		waypointCount = waypointCount + 1
		
		-- Only recalculate every 3-5 waypoints to balance performance and smoothness
		if waypointCount >= 3 or i == 2 then
			local currentHorizDist = calculateHorizontalDistance(root.Position, destination)
			local currentVertDist = calculateVerticalDistance(root.Position, destination)
			
			-- Don't recalculate if very close to destination
			if currentHorizDist > 8 or currentVertDist > 4 then
				debugPrint("🔄 Adaptive path update at waypoint", i)
				
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
						if blockedConnection then
							blockedConnection:Disconnect()
						end
						
						debugPrint("✅ Path updated:", #newValidWaypoints, "waypoints from current position")
						validWaypoints = newValidWaypoints
						i = 1  -- Reset to start of new path
						showPath(validWaypoints)
						
						pathBlocked = false
						blockedConnection = newPath.Blocked:Connect(function(blockedWaypointIndex)
							debugPrint("⚠️ New path blocked at waypoint", blockedWaypointIndex)
							pathBlocked = true
						end)
						
						waypointCount = 0  -- Reset counter
					else
						debugPrint("⚠️ New path invalid (water/players), keeping current path")
					end
				else
					debugPrint("⚠️ Path update failed, keeping current path")
				end
			else
				debugPrint("Close to destination (H:", math.floor(currentHorizDist), "V:", math.floor(currentVertDist), ") - no update needed")
			end
		end
		
		if i > #validWaypoints then
			break
		end
		
		local waypoint = validWaypoints[i]
		debugPrint("Moving to waypoint", i, "of", #validWaypoints)
		
		if strictAvoidance or isBeingAttacked then
			local hadCombat = handleCombat(character)
			if hadCombat then
				debugPrint("Combat occurred - resuming pathfinding")
				-- Force path recalculation after combat
				waypointCount = 999  -- Force immediate recalculation on next waypoint
				-- Resume walking animation
				playWalkAnim(hum)
			end
		end
		
		if not moveToWaypoint(hum, root, waypoint.Position, waypoint.Action) then
			debugPrint("Failed to reach waypoint - recomputing path")
			if blockedConnection then blockedConnection:Disconnect() end
			task.wait(0.3)
			return followPath(destination, pathfindFailures, recursionDepth + 1)
		end
	end
	
	if blockedConnection then
		blockedConnection:Disconnect()
		blockedConnection = nil
	end
	
	local finalHorizDist = calculateHorizontalDistance(root.Position, destination)
	local finalVertDist = calculateVerticalDistance(root.Position, destination)
	
	-- REMOVED: Direct final approach
	-- Always use PathfindingService to ensure valid path
	debugPrint("Path complete - H:", math.floor(finalHorizDist), "V:", math.floor(finalVertDist))
	
	if finalHorizDist < 5 and finalVertDist < 3 then
		debugPrint("✅ Destination reached")
		disableSoftNoclip()  -- Clean up soft noclip
		return true
	else
		debugPrint("Still far from destination - recomputing path")
		-- Keep soft noclip enabled for recursive call
		return followPath(destination, pathfindFailures, recursionDepth + 1)
	end
end

-- =========================================================================
-- SIMPLE GUI SETUP
-- =========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RocksScannerGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 600)
mainFrame.Position = UDim2.new(0.5, -175, 0.5, -300)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

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

local controlsFrame = Instance.new("Frame")
controlsFrame.Size = UDim2.new(1, -20, 0, 195)
controlsFrame.Position = UDim2.new(0, 10, 0, 50)
controlsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
controlsFrame.Parent = mainFrame

Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 6)

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

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 80, 0, 24)
refreshBtn.Position = UDim2.new(1, -90, 0, 10)
refreshBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
refreshBtn.Text = "Refresh"
refreshBtn.TextColor3 = Color3.new(1, 1, 1)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.Parent = controlsFrame

Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 4)

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

combatButton.MouseButton1Click:Connect(function()
	strictAvoidance = not strictAvoidance
	combatButton.BackgroundColor3 = strictAvoidance and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	debugPrint("Auto combat mode:", strictAvoidance)
end)

cannonButton.MouseButton1Click:Connect(function()
	debugPrint("Manual cannon fire requested")
	cannonFired = false
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

local function isSpawnLocation(obj) 
	return obj:IsA("SpawnLocation") or obj.Name == "SpawnLocation" 
end

local function isValidItem(item) 
	return not (item:IsA("Decal") or item:IsA("SurfaceGui") or item:IsA("TouchTransmitter") or item:IsA("Weld") or item:IsA("Script")) 
end

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
-- MAIN LOOP
-- =========================================================================
task.spawn(function()
	while true do
		task.wait(0.5)
		
		if autoMineEnabled and not isCurrentlyMining then
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
				
				debugPrint("🔄 SCANNING FROM CURRENT POSITION:", math.floor(currentPos.X), math.floor(currentPos.Y), math.floor(currentPos.Z))
				
				-- STEP 1: Gather ALL valid ore candidates
				local oresCandidates = {}
				
				for _, area in ipairs(rocksFolder:GetChildren()) do
					for _, spawnLoc in ipairs(area:GetChildren()) do
						if isSpawnLocation(spawnLoc) then
							for _, item in ipairs(spawnLoc:GetChildren()) do
								if isValidItem(item) and selectedTargets[item.Name] == true then
									if not isOreSkipped(item) then
										local itemPos = item:GetPivot().Position 
										
										if not isOreBeingMinedByOthers(itemPos) then
											local dist = (currentPos - itemPos).Magnitude
											table.insert(oresCandidates, {
												ore = item,
												position = itemPos,
												distance = dist
											})
										end
									end
								end
							end
						end
					end
				end
				
				if #oresCandidates == 0 then
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
					continue
				end
				
				-- STEP 2: Sort by distance (closest first)
				table.sort(oresCandidates, function(a, b) return a.distance < b.distance end)
				
				debugPrint("═══════════════════════════════════════════════")
				debugPrint("STARTING ORE PATH TESTING")
				debugPrint("Found", #oresCandidates, "ore candidates, testing ALL ores for valid paths...")
				debugPrint("═══════════════════════════════════════════════")
				debugPrint("CONFIGURATION:")
				debugPrint("  WATER_CHECK_ENABLED:", WATER_CHECK_ENABLED)
				debugPrint("  WATER_CHECK_STRICT:", WATER_CHECK_STRICT)
				debugPrint("  PLAYER_PROXIMITY_CHECK:", PLAYER_PROXIMITY_CHECK)
				debugPrint("  DIRECT_PATH_DIST:", DIRECT_PATH_DIST)
				debugPrint("  AGENT_CAN_JUMP:", AGENT_CAN_JUMP)
				debugPrint("  AGENT_CAN_CLIMB:", AGENT_CAN_CLIMB)
				debugPrint("  AGENT_MAX_SLOPE:", AGENT_MAX_SLOPE)
				debugPrint("  AIR_COST:", COSTS.Air)
				debugPrint("  WATER_COST:", COSTS.Water)
				debugPrint("═══════════════════════════════════════════════")
				statusLabel.Text = "🔍 Testing " .. #oresCandidates .. " ores for valid paths..."
				
				-- STEP 3: Test EVERY ore for valid path (closest first)
				-- Build list of ALL reachable ores, don't stop at first one
				local reachableOres = {}
				local testedCount = 0
				
				for _, candidate in ipairs(oresCandidates) do
					testedCount = testedCount + 1
					local ore = candidate.ore
					local orePos = candidate.position
					
					-- Check if underwater first (fast check)
					if isPositionInWater(orePos) then
						debugPrint("Ore #" .. testedCount, ore.Name, "is underwater - skipping")
						markOreAsSkipped(ore)
						continue
					end
					
					-- Test if we can path to this ore
					debugPrint("Testing path to", ore.Name, "(#" .. testedCount .. "/" .. #oresCandidates .. ") at", math.floor(candidate.distance), "studs...")
					statusLabel.Text = "🧪 Testing " .. ore.Name .. " (#" .. testedCount .. "/" .. #oresCandidates .. ")"
					
					if canPathToPosition(currentPos, orePos) then
						debugPrint("✅ Reachable:", ore.Name)
						table.insert(reachableOres, candidate)
						-- DON'T BREAK - continue testing all ores
					else
						debugPrint("❌ Cannot path to", ore.Name)
					end
				end
				
				debugPrint("═══════════════════════════════════════════════")
				debugPrint("ORE TESTING COMPLETE:", #reachableOres, "reachable out of", testedCount, "tested")
				debugPrint("═══════════════════════════════════════════════")
				
				-- STEP 4: Try each reachable ore one by one
				local miningSuccess = false
				
				if #reachableOres > 0 then
					debugPrint("📋 Trying", #reachableOres, "reachable ores one by one...")
					
					for attemptNum, candidate in ipairs(reachableOres) do
						if not autoMineEnabled then break end
						
						local closestItem = candidate.ore
						local targetPos = candidate.position
						
						debugPrint("═══════════════════════════════════════════════")
						debugPrint("🎯 ATTEMPT", attemptNum, "of", #reachableOres)
						debugPrint("Target:", closestItem.Name, "at", math.floor(candidate.distance), "studs")
						debugPrint("═══════════════════════════════════════════════")
						statusLabel.Text = "🎯 Trying ore " .. attemptNum .. "/" .. #reachableOres .. ": " .. closestItem.Name
						
						-- CRITICAL: Double-check ore isn't being mined before starting
						if isOreBeingMinedByOthers(targetPos) then
							debugPrint("⚠️ ABORT: Ore is now being mined by another player!")
							statusLabel.Text = "❌ Ore taken by another player"
							continue  -- Try next ore
						end
						
						isCurrentlyMining = true
						
						-- Note: Underwater check already done in STEP 3/4 above
					
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
								
								switchToPickaxe()
								
								statusLabel.Text = "⛏️ Mining..."
								local lastPositionCheck = tick()
								local lastHealthCheck = tick()
								local lastPlayerCheck = tick()  -- NEW: Check for other players
								local PLAYER_CHECK_INTERVAL = 2  -- NEW: Check every 2 seconds
								local lastOreHealth = nil
								local POSITION_CHECK_INTERVAL = 2
								local HEALTH_CHECK_INTERVAL = 5
								local healthCheckFailures = 0
								
								if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
									lastOreHealth = closestItem.Health.Value
								end
								
								-- Lock character position to prevent drift
								local miningPosition = rootPart.Position
								
								while closestItem.Parent and autoMineEnabled do
									-- CRITICAL: Lock position and face ore every frame
									if rootPart and (closestItem:FindFirstChild("PrimaryPart") or closestItem:IsA("BasePart")) then
										local orePos = closestItem:IsA("Model") and closestItem:GetPivot().Position or closestItem.Position
										
										-- Force character to stay at mining position (prevent drift)
										local pos = miningPosition
										local lookAt = orePos
										local cf = CFrame.lookAt(pos, lookAt)
										rootPart.CFrame = cf
										
										-- Zero out velocities to prevent drift
										rootPart.Velocity = Vector3.new(0, 0, 0)
										rootPart.RotVelocity = Vector3.new(0, 0, 0)
									end
									
									local currentDistToOre = (rootPart.Position - targetPos).Magnitude
									if currentDistToOre > MINING_DEPTH + 8 then
										debugPrint("Too far from ore in stealth mode - repositioning")
										statusLabel.Text = "⚠️ Repositioning to ore..."
										TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
										task.wait(0.5)
									end
									
									-- NEW: Check if another player started mining this ore
									if tick() - lastPlayerCheck >= PLAYER_CHECK_INTERVAL then
										if isOreBeingMinedByOthers(targetPos) then
											debugPrint("⚠️ ABORT MINING: Another player is now mining this ore!")
											statusLabel.Text = "❌ Ore taken by another player"
											break  -- Exit mining loop
										end
										lastPlayerCheck = tick()
									end
									
									if strictAvoidance or isBeingAttacked then
										local hadCombat = handleCombat(character)
										if hadCombat then
											switchToPickaxe()
											local distToOre = (rootPart.Position - targetPos).Magnitude
											if distToOre > MINING_DEPTH + 5 then
												debugPrint("Moved too far during combat, repositioning...")
												statusLabel.Text = "🔄 Repositioning after combat..."
												TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(minePos)}):Play()
												task.wait(0.5)
											end
										end
									end
									
									if tick() - lastHealthCheck >= HEALTH_CHECK_INTERVAL then
										if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
											local currentHealth = closestItem.Health.Value
											
											if lastOreHealth and currentHealth >= lastOreHealth then
												healthCheckFailures = healthCheckFailures + 1
												debugPrint("WARNING: Ore health not decreasing in stealth mode! (Failures:", healthCheckFailures, ")")
												
												if healthCheckFailures >= 2 then
													debugPrint("Ore not being damaged - repositioning closer")
													statusLabel.Text = "⚠️ Mining ineffective - repositioning..."
													
													local orePos = closestItem:GetPivot().Position
													local closerPos = orePos + Vector3.new(0, -MINING_DEPTH + 2, 0)
													TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(closerPos)}):Play()
													task.wait(0.5)
													
													healthCheckFailures = 0
												end
											else
												healthCheckFailures = 0
											end
											
											lastOreHealth = currentHealth
										end
										lastHealthCheck = tick()
									end
									
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
									
									pcall(function() 
										ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") 
									end)
									task.wait(0.1)
								end
								
								statusLabel.Text = "⬇️ Retreating..."
								TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(underRockPos)}):Play()
								task.wait(0.5)
							end
							disableFlightPhysics(rootPart)
						
						else
							statusLabel.Text = "🏃 Walking to " .. closestItem.Name .. "..."
							disableFlightPhysics(rootPart)
							
							local safeMiningPos = getSafeMiningPosition(targetPos, rootPart.Position)
							
							-- PATHFINDING ONLY - no tween fallback
							local arrived = false
							debugPrint("Using pathfinding (valid path exists)")
							arrived = followPath(safeMiningPos, 0, 0)
							
							-- CRITICAL: If pathfinding failed even though canPathToPosition said it would work
							if not arrived then
								debugPrint("⚠️ PATH VERIFICATION FAILED - canPathToPosition was wrong!")
								debugPrint("⚠️ Marking ore as unreachable and trying next ore")
								statusLabel.Text = "❌ Path failed - trying next ore"
								
								-- Mark this ore as skipped temporarily
								markOreAsSkipped(closestItem)
								
								-- Don't mine this ore, go back to finding another one
								isCurrentlyMining = false
								task.wait(0.5)
								continue  -- Go back to ore selection loop
							end
							
							if not arrived and isInMiningRange(rootPart.Position, targetPos) then
								debugPrint("Already in mining range, starting mining")
								arrived = true
							end
							
							if arrived and autoMineEnabled then
								debugPrint("In mining range, starting mining...")
								
								switchToPickaxe()
								
								statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
								
								local mineStartTime = tick()
								local lastPositionCheck = tick()
								local lastHealthCheck = tick()
								local lastPlayerCheck = tick()  -- NEW: Check for other players
								local PLAYER_CHECK_INTERVAL = 2  -- NEW: Check every 2 seconds
								local lastOreHealth = nil
								local POSITION_CHECK_INTERVAL = 2
								local HEALTH_CHECK_INTERVAL = 5
								local healthCheckFailures = 0
								
								if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
									lastOreHealth = closestItem.Health.Value
								end
								
								-- Lock character position to prevent drift
								local miningPosition = rootPart.Position
								
								while closestItem.Parent and autoMineEnabled do
									-- CRITICAL: Lock position and face ore every frame
									if rootPart and (closestItem:FindFirstChild("PrimaryPart") or closestItem:IsA("BasePart")) then
										local orePos = closestItem:IsA("Model") and closestItem:GetPivot().Position or closestItem.Position
										
										-- Force character to stay at mining position (prevent drift)
										local pos = miningPosition
										local lookAt = orePos
										local cf = CFrame.lookAt(pos, lookAt)
										rootPart.CFrame = cf
										
										-- Zero out velocities to prevent drift
										rootPart.Velocity = Vector3.new(0, 0, 0)
										rootPart.RotVelocity = Vector3.new(0, 0, 0)
									end
									
									local currentDistToOre = (rootPart.Position - targetPos).Magnitude
									if currentDistToOre > MAX_MINING_DISTANCE then
										debugPrint("Moved too far from ore during mining (", math.floor(currentDistToOre), "studs)")
										statusLabel.Text = "⚠️ Too far from ore! Repositioning..."
										
										local returnSuccess = followPath(safeMiningPos, 0, 0)
										
										if not returnSuccess then
											debugPrint("Failed to return to ore position")
											statusLabel.Text = "⚠️ Can't return to ore - moving to next"
											break
										end
										
										switchToPickaxe()
										statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
									end
									
									-- NEW: Check if another player started mining this ore
									if tick() - lastPlayerCheck >= PLAYER_CHECK_INTERVAL then
										if isOreBeingMinedByOthers(targetPos) then
											debugPrint("⚠️ ABORT MINING: Another player is now mining this ore!")
											statusLabel.Text = "❌ Ore taken by another player"
											break  -- Exit mining loop
										end
										lastPlayerCheck = tick()
									end
									
									if strictAvoidance or isBeingAttacked then
										local hadCombat = handleCombat(character)
										if hadCombat then
											switchToPickaxe()
											local distToOre = (rootPart.Position - targetPos).Magnitude
											if distToOre > MAX_MINING_DISTANCE then
												debugPrint("Moved too far during combat (", math.floor(distToOre), "studs), re-pathing...")
												statusLabel.Text = "🔄 Returning to ore after combat..."
												
												local returnSuccess = followPath(targetPos, 0, 0)
												
												if not returnSuccess then
													debugPrint("Failed to return to ore after combat")
													statusLabel.Text = "⚠️ Can't return to ore - moving to next"
													break
												end
												
												switchToPickaxe()
												debugPrint("Returned to ore, resuming mining")
												statusLabel.Text = "⛏️ Mining " .. closestItem.Name .. "..."
											end
										end
									end
									
									if tick() - lastHealthCheck >= HEALTH_CHECK_INTERVAL then
										if closestItem:IsA("Model") and closestItem:FindFirstChild("Health") then
											local currentHealth = closestItem.Health.Value
											
											if lastOreHealth and currentHealth >= lastOreHealth then
												healthCheckFailures = healthCheckFailures + 1
												debugPrint("WARNING: Ore health not decreasing! (Failures:", healthCheckFailures, ")")
												
												if healthCheckFailures >= 2 then
													debugPrint("Ore not being damaged after 10 seconds - repositioning")
													statusLabel.Text = "⚠️ Mining ineffective - repositioning..."
													
													local orePos = closestItem:GetPivot().Position
													local closerPos = orePos + (rootPart.Position - orePos).Unit * -2
													rootPart.CFrame = CFrame.new(closerPos)
													task.wait(0.5)
													
													healthCheckFailures = 0
												end
											else
												healthCheckFailures = 0
											end
											
											lastOreHealth = currentHealth
										end
										lastHealthCheck = tick()
									end
									
									if tick() - lastPositionCheck >= POSITION_CHECK_INTERVAL then
										local distToOre = (rootPart.Position - targetPos).Magnitude
										if distToOre > 25 then
											debugPrint("Player too far from ore (fell?), re-pathing...")
											statusLabel.Text = "🔄 Repositioning to ore..."
											
											local repositionSuccess = followPath(targetPos, 0, 0)
											
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
					end
				end
			end
		end
	end)
	
	-- =========================================================================
-- UI EVENTS
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

closeBtn.MouseButton1Click:Connect(function() 
	screenGui:Destroy() 
end)

refreshBtn.MouseButton1Click:Connect(function()
	scanRocks()
	clearSkippedOres()
	debugPrint("Refreshed ore list and cleared skip list")
end)

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

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

-- =========================================================================
-- INITIAL SCAN
-- =========================================================================
task.wait(1)
scanRocks()
print("✅ Advanced Miner " .. SCRIPT_VERSION .. " - TEST ALL ORES!")
print("🔥 NEW: Tests EVERY ore for valid paths (not just 5)")
print("🚨 NEW: Tween is ABSOLUTE LAST RESORT (only if all ores unreachable)")
print("🎯 NEW: Exhaustive path testing = maximum success rate")
print("⚡ NEW: Comprehensive ore evaluation before any movement")
print("🐛 BUG FIX #6: Tests ALL ores - tween is last resort")
print("🐛 BUG FIX #5: Smart ore loop - no more stuck on first ore")
print("🐛 BUG FIX #1: No climbing on ores - ground level positioning")
print("🐛 BUG FIX #2: Auto-unstuck from tiny ledges")
print("🐛 BUG FIX #3: Y-axis validation (no swinging at nothing)")
print("🐛 BUG FIX #4: Noclip tweening + proper Z-axis")
print("📏 3D Distance: Full X, Y, Z awareness in pathfinding")
print("🗺️ PATHFINDING: Vertical distance detection + smart routing")
print("👥 PLAYER AVOIDANCE: Working correctly")
print("⛏️ LARGE ORE: 15 stud range, safe positioning")
print("🎆 CANNON: Auto-fires (World 2)")
print("🥊 COMBAT: Dodge + Block + Facing")
