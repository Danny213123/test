-- Rocks Scanner (Ultimate: Realistic Jump + Animations + Safety)
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
local stealthModeEnabled = true 
local espEnabled = false
local isCurrentlyMining = false 
local selectedTargets = {} 

-- Safety & Travel Settings
local MIN_PLAYER_DISTANCE = 70  -- Skip rocks if players are this close
local TRAVEL_DEPTH = 20         -- Depth to travel underground (Stealth Travel)
local HIDE_OFFSET = 3           -- Depth to sink into ground while mining (Mob Safety)
local MOVEMENT_SPEED = 35       -- Studs per second (Stealth Mode)

-- Pathfinding Settings (Surface Mode)
local STUCK_TIMEOUT = 2       
local JUMP_THRESHOLD = 2.0      -- Height difference to trigger jump

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

-- =========================================================================
-- GUI SETUP
-- =========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RocksScannerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 500)
mainFrame.Position = UDim2.new(0.5, -175, 0.5, -250)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

-- Header
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "Realistic Miner"
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
controlsFrame.Size = UDim2.new(1, -20, 0, 80)
controlsFrame.Position = UDim2.new(0, 10, 0, 50)
controlsFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
controlsFrame.Parent = mainFrame
Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 6)

-- Auto Mine
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

-- Stealth
local stealthButton = Instance.new("TextButton")
stealthButton.Size = UDim2.new(0, 24, 0, 24)
stealthButton.Position = UDim2.new(0, 10, 0, 45)
stealthButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
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

-- ESP
local espButton = Instance.new("TextButton")
espButton.Size = UDim2.new(0, 24, 0, 24)
espButton.Position = UDim2.new(0, 180, 0, 45)
espButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
espButton.Text = ""
espButton.Parent = controlsFrame
Instance.new("UICorner", espButton).CornerRadius = UDim.new(0, 4)

local espLabel = Instance.new("TextLabel")
espLabel.Text = "PLAYER ESP"
espLabel.Size = UDim2.new(0, 100, 0, 24)
espLabel.Position = UDim2.new(0, 210, 0, 45)
espLabel.BackgroundTransparency = 1
espLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
espLabel.Font = Enum.Font.Gotham
espLabel.TextXAlignment = Enum.TextXAlignment.Left
espLabel.Parent = controlsFrame

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
scrollFrame.Size = UDim2.new(1, -20, 1, -150)
scrollFrame.Position = UDim2.new(0, 10, 0, 140)
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
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.Parent = mainFrame

-- =========================================================================
-- ANIMATION HELPERS
-- =========================================================================

local function getWalkAnimId(humanoid)
	return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507767714" or "rbxassetid://180426354"
end

local function getJumpAnimId(humanoid)
	return (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507765000" or "rbxassetid://125750702"
end

local function playWalkAnim(humanoid)
	if walkAnimTrack and walkAnimTrack.IsPlaying then return end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
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
-- ESP & GUI LOGIC
-- =========================================================================

local function updateESP()
	espFolder:ClearAllChildren()
	if espEnabled then
		for _, v in ipairs(Players:GetPlayers()) do
			if v ~= player and v.Character then
				local highlight = Instance.new("Highlight")
				highlight.Adornee = v.Character
				highlight.FillColor = Color3.fromRGB(255, 0, 0)
				highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
				highlight.FillTransparency = 0.5
				highlight.OutlineTransparency = 0
				highlight.Parent = espFolder
			end
		end
	end
end

Players.PlayerAdded:Connect(function() task.wait(1) updateESP() end)
Players.PlayerRemoving:Connect(updateESP)
task.spawn(function() while true do task.wait(5) if espEnabled then updateESP() end end end)

espButton.MouseButton1Click:Connect(function()
	espEnabled = not espEnabled
	espButton.BackgroundColor3 = espEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
	updateESP()
end)

local function updateAutoMineVisuals()
	if autoMineEnabled then
		autoMineButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		autoMineLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
		statusLabel.Text = "Status: Active"
	else
		autoMineButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		autoMineLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		statusLabel.Text = "Status: Idle"
		isCurrentlyMining = false
		visualFolder:ClearAllChildren()
		stopWalkAnim()
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			player.Character.HumanoidRootPart.Anchored = false
		end
	end
end

autoMineButton.MouseButton1Click:Connect(function()
	autoMineEnabled = not autoMineEnabled
	updateAutoMineVisuals()
end)

stealthButton.MouseButton1Click:Connect(function()
	stealthModeEnabled = not stealthModeEnabled
	stealthButton.BackgroundColor3 = stealthModeEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(80, 80, 80)
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
	end)
end

local function isSpawnLocation(obj) return obj:IsA("SpawnLocation") or obj.Name == "SpawnLocation" end
local function isValidItem(item) return not (item:IsA("Decal") or item:IsA("SurfaceGui") or item:IsA("TouchTransmitter") or item:IsA("Weld") or item:IsA("Script")) end

local function scanRocks()
	for _, child in ipairs(scrollFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
	local workspace = game:GetService("Workspace")
	local rocksFolder = workspace:FindFirstChild("Rocks") or workspace:FindFirstChild("rocks")
	if not rocksFolder then return end
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
	for name, count in pairs(tallies) do createRow(name, count) end
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end

-- =========================================================================
-- LOGIC HELPERS
-- =========================================================================

local function isAreaSafe(targetPos)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local dist = (otherPlayer.Character.HumanoidRootPart.Position - targetPos).Magnitude
			if dist < MIN_PLAYER_DISTANCE then
				return false
			end
		end
	end
	return true
end

-- PATHFINDING VISUALS
local function showPath(waypoints)
	visualFolder:ClearAllChildren()
	for _, waypoint in ipairs(waypoints) do
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.6, 0.6, 0.6)
		dot.Position = waypoint.Position + Vector3.new(0, 0.5, 0)
		dot.Anchored = true
		dot.CanCollide = false
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(160, 50, 255)
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			dot.Color = Color3.fromRGB(255, 200, 0)
			dot.Size = Vector3.new(1, 1, 1)
		end
		dot.Parent = visualFolder
	end
end

-- REALISTIC PHYSICS JUMP
local function performPhysicsJump(humanoid, rootPart)
	stopWalkAnim() -- Stop walking while in air
	playJumpAnim(humanoid) -- Play jump anim
	
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	humanoid.Jump = true
	
	task.wait(0.5) -- Wait a bit for air time
	-- Anim stops naturally or when land
end

local function moveSmart(humanoid, rootPart, targetPos, action)
	-- Determine if we need to jump
	local needsJump = (action == Enum.PathWaypointAction.Jump) or (targetPos.Y > rootPart.Position.Y + JUMP_THRESHOLD)
	
	if needsJump then
		performPhysicsJump(humanoid, rootPart)
		return true 
	else
		-- WALK
		playWalkAnim(humanoid)
		humanoid:MoveTo(targetPos)
		
		local startTime = tick()
		local lastPos = rootPart.Position
		
		while true do
			task.wait(0.1)
			if not autoMineEnabled then stopWalkAnim() return false end
			
			local dist = (rootPart.Position - targetPos) * Vector3.new(1,0,1)
			if dist.Magnitude < 3 then return true end
			
			if tick() - startTime > STUCK_TIMEOUT then stopWalkAnim() return false end
			
			-- Stuck check
			if (rootPart.Position - lastPos).Magnitude < 0.2 then 
				performPhysicsJump(humanoid, rootPart) 
				return true 
			end
			lastPos = rootPart.Position
		end
	end
end

local function followPath(destination)
	local character = player.Character
	if not character then return false end
	local hum, root = character:FindFirstChild("Humanoid"), character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return false end

	local path = PathfindingService:CreatePath({AgentRadius=2.5, AgentHeight=5, AgentCanJump=true, AgentMaxSlope=60, WaypointSpacing=5})
	local success = pcall(function() path:ComputeAsync(root.Position, destination) end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		showPath(waypoints)
		for i, waypoint in ipairs(waypoints) do
			if i > 1 then 
				if not moveSmart(hum, root, waypoint.Position, waypoint.Action) then 
					stopWalkAnim() 
					return false 
				end
			end
		end
		stopWalkAnim()
		visualFolder:ClearAllChildren()
		return true
	else
		return false
	end
end

-- =========================================================================
-- MAIN LOOP
-- =========================================================================

task.spawn(function()
	while true do
		task.wait(0.5)
		
		if autoMineEnabled and not isCurrentlyMining then
			local workspace = game:GetService("Workspace")
			local rocksFolder = workspace:FindFirstChild("Rocks")
			local character = player.Character
			
			if rocksFolder and character and character:FindFirstChild("HumanoidRootPart") then
				local rootPart = character.HumanoidRootPart
				local currentPos = rootPart.Position
				local closestItem = nil
				local shortestDistance = math.huge
				
				-- 1. Find Safe Target
				for _, area in ipairs(rocksFolder:GetChildren()) do
					for _, spawnLoc in ipairs(area:GetChildren()) do
						if isSpawnLocation(spawnLoc) then
							for _, item in ipairs(spawnLoc:GetChildren()) do
								if isValidItem(item) and selectedTargets[item.Name] == true then
									local itemPos = item:GetPivot().Position 
									local dist = (currentPos - itemPos).Magnitude
									
									-- PLAYER PROXIMITY CHECK (Applies to Surface Mode mainly, but good for both)
									if isAreaSafe(itemPos) then
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
					isCurrentlyMining = true
					local targetPos = closestItem:GetPivot().Position
					
					-- ===================================
					-- MODE A: STEALTH (TWEEN UNDERGROUND)
					-- ===================================
					if stealthModeEnabled then
						statusLabel.Text = "🚇 Stealth: Traveling..."
						rootPart.Anchored = true
						
						-- 1. Sink
						local travelPos = rootPart.Position
						if travelPos.Y > targetPos.Y - TRAVEL_DEPTH + 5 then 
							local downPos = Vector3.new(travelPos.X, targetPos.Y - TRAVEL_DEPTH, travelPos.Z)
							TweenService:Create(rootPart, TweenInfo.new(1), {CFrame = CFrame.new(downPos)}):Play()
							task.wait(1)
						end
						
						-- 2. Travel
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
							-- 3. Hitbox Contact
							statusLabel.Text = "⬆️ Hitbox Contact..."
							TweenService:Create(rootPart, TweenInfo.new(0.4), {CFrame = CFrame.new(targetPos)}):Play()
							task.wait(0.4)
							
							-- 4. Mine
							statusLabel.Text = "⛏️ Mining..."
							while closestItem.Parent and autoMineEnabled do
								pcall(function() ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") end)
								task.wait(0.1)
							end
							
							-- 5. Retreat
							statusLabel.Text = "⬇️ Retreating..."
							TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(underRockPos)}):Play()
							task.wait(0.5)
						end
					
					-- ===================================
					-- MODE B: SURFACE WALK (REALISTIC JUMP + MOB SAFE)
					-- ===================================
					else 
						statusLabel.Text = "🏃 Walking to target..."
						rootPart.Anchored = false
						local arrived = followPath(targetPos)
						
						if arrived and autoMineEnabled then
							statusLabel.Text = "🛡️ Hiding from Mobs..."
							
							-- 1. Hide in Ground (Mob Safety)
							rootPart.Anchored = true
							local surfaceCFrame = rootPart.CFrame
							local hidePos = targetPos - Vector3.new(0, HIDE_OFFSET, 0) 
							TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = CFrame.new(hidePos)}):Play()
							task.wait(0.5)
							
							-- 2. Mine
							statusLabel.Text = "⛏️ Mining..."
							while closestItem.Parent and autoMineEnabled do
								pcall(function() ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe") end)
								task.wait(0.1)
							end
							
							-- 3. Surface
							statusLabel.Text = "⬆️ Surfacing..."
							TweenService:Create(rootPart, TweenInfo.new(0.5), {CFrame = surfaceCFrame}):Play()
							task.wait(0.5)
							rootPart.Anchored = false
							
						else
							statusLabel.Text = "⚠️ Path Failed."
							task.wait(0.5)
						end
					end
					
					isCurrentlyMining = false
				else
					statusLabel.Text = "⚠️ No Safe Targets Found"
				end
			end
		end
	end
end)

-- UI DRAGGING & EVENTS
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

task.wait(1)
scanRocks()
print("Realistic Miner Loaded")
