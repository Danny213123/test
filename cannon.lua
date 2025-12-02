local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- Update character references on respawn
LocalPlayer.CharacterAdded:Connect(function(newChar)
	Character = newChar
	Humanoid = newChar:WaitForChild("Humanoid")
	RootPart = newChar:WaitForChild("HumanoidRootPart")
end)

-- 1. CONFIGURATION
local TARGET_CFRAME = CFrame.new(
	-224.087341, 24.1698914, -21.4238281,
	0.0982458591, -0.796521664, 0.596574366,
	-0.102026045, -0.604377747, -0.790138245,
	0.989918411, 0.0167616904, -0.140643597
)

local SEARCH_RADIUS_ERROR = 0.5
local INTERACTION_DISTANCE = 5
local DETECTION_RADIUS = 40 -- Radius within which auto-walk triggers
local WALK_ANIM_ID = "rbxassetid://180426354"

local isEnabled = false -- Toggle state
local isBusy = false -- Debounce to prevent overlapping actions

-- 2. GUI CREATION
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CannonAutoGui"
ScreenGui.ResetOnSpawn = false

pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 200, 0, 110)
MainFrame.Position = UDim2.new(0.05, 0, 0.4, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -30, 0, 30)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Cannon Bot"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextSize = 18
Title.Parent = MainFrame

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 30, 0, 30)
CloseButton.Position = UDim2.new(1, -30, 0, 0)
CloseButton.BackgroundTransparency = 1
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 18
CloseButton.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.8, 0, 0, 40)
ToggleButton.Position = UDim2.new(0.1, 0, 0.4, 0)
ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleButton.Text = "OFF"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.Gotham
ToggleButton.TextSize = 18
ToggleButton.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.Parent = ToggleButton

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 20)
StatusLabel.Position = UDim2.new(0, 0, 0.8, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
StatusLabel.TextSize = 12
StatusLabel.Parent = MainFrame

-- 3. VISUALIZATION & ANIMATION SETUP
local visualSphere = Instance.new("Part")
visualSphere.Name = "CannonRadiusVisual"
visualSphere.Shape = Enum.PartType.Ball
visualSphere.Material = Enum.Material.ForceField
visualSphere.Color = Color3.fromRGB(255, 50, 50)
visualSphere.Transparency = 0.8
visualSphere.Anchored = true
visualSphere.CanCollide = false
visualSphere.CastShadow = false
visualSphere.Size = Vector3.new(DETECTION_RADIUS * 2, DETECTION_RADIUS * 2, DETECTION_RADIUS * 2)
visualSphere.Parent = Workspace

local pathVisualsFolder = Instance.new("Folder")
pathVisualsFolder.Name = "CannonPathVisuals"
pathVisualsFolder.Parent = Workspace

-- Animation Objects
local walkAnimation = Instance.new("Animation")
walkAnimation.AnimationId = WALK_ANIM_ID
local walkTrack = nil

-- 4. HELPER FUNCTIONS
local function findSpecificCannon()
	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("Model") and object.Name == "Cannon" then
			local pivot = object:GetPivot()
			local distance = (pivot.Position - TARGET_CFRAME.Position).Magnitude
			
			if distance < SEARCH_RADIUS_ERROR then
				return object
			end
		end
	end
	return nil
end

local targetCannon = findSpecificCannon()
if targetCannon then
	visualSphere.Position = targetCannon:GetPivot().Position
else
	StatusLabel.Text = "Error: Cannon not found!"
	visualSphere:Destroy()
end

-- Animation Control
local function updateWalkAnim(shouldPlay)
	if shouldPlay then
		if not walkTrack or walkTrack.Parent ~= Humanoid then
			-- Load if missing or if humanoid changed
			local success, track = pcall(function()
				return Humanoid:LoadAnimation(walkAnimation)
			end)
			if success then
				walkTrack = track
				walkTrack.Priority = Enum.AnimationPriority.Action -- Ensure it overrides default walk
				walkTrack.Looped = true
			end
		end
		
		if walkTrack and not walkTrack.IsPlaying then
			walkTrack:Play()
		end
	else
		if walkTrack and walkTrack.IsPlaying then
			walkTrack:Stop(0.2) -- 0.2s fade out
		end
	end
end

-- 5. PATHFINDING LOGIC
local function walkTo(targetPosition)
	if not isEnabled then return end

	-- Clean up old visuals
	pathVisualsFolder:ClearAllChildren()

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4
	})

	local success, errorMessage = pcall(function()
		path:ComputeAsync(RootPart.Position, targetPosition)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		
		-- VISUALIZE
		for _, wp in ipairs(waypoints) do
			local node = Instance.new("Part")
			node.Name = "PathNode"
			node.Shape = Enum.PartType.Ball
			node.Size = Vector3.new(0.6, 0.6, 0.6)
			node.Material = Enum.Material.Neon
			node.Color = Color3.fromRGB(0, 255, 255)
			node.Anchored = true
			node.CanCollide = false
			node.CastShadow = false
			node.Position = wp.Position
			node.Parent = pathVisualsFolder
		end

		-- START ANIMATION
		updateWalkAnim(true)

		for i, waypoint in ipairs(waypoints) do
			-- CHECK: Disabled?
			if not isEnabled then 
				Humanoid:MoveTo(RootPart.Position)
				updateWalkAnim(false)
				break 
			end 
			
			-- CHECK: Manual Override?
			if Humanoid.MoveDirection.Magnitude > 0.1 then
				StatusLabel.Text = "Status: User Control..."
				updateWalkAnim(false)
				break
			end
			
			local currentPos = waypoint.Position
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				Humanoid.Jump = true
			end
			
			Humanoid:MoveTo(currentPos)
			local moveSuccess = Humanoid.MoveToFinished:Wait()
			
			if not moveSuccess then
				StatusLabel.Text = "Status: Interrupted..."
				updateWalkAnim(false)
				break 
			end
			
			if (RootPart.Position - targetPosition).Magnitude < INTERACTION_DISTANCE then
				break
			end
		end
		
		-- STOP ANIMATION & CLEANUP
		updateWalkAnim(false)
		pathVisualsFolder:ClearAllChildren()
	else
		StatusLabel.Text = "Status: Path computation failed"
		warn("Pathfinding failed:", errorMessage)
	end
end

-- 6. INTERACTION LOGIC
local function triggerInteraction(model)
	StatusLabel.Text = "Interacting..."
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	
	if prompt then
		if fireproximityprompt then
			fireproximityprompt(prompt)
		else
			local promptPos = prompt.Parent.Position
			local camera = Workspace.CurrentCamera
			camera.CFrame = CFrame.new(camera.CFrame.Position, promptPos)
			task.wait(0.1)
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			task.wait(0.1)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		end
	end
end

-- 7. GUI CONNECTIONS
local heartBeatConnection -- Forward declaration

ToggleButton.MouseButton1Click:Connect(function()
	isEnabled = not isEnabled
	if isEnabled then
		ToggleButton.Text = "ON"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
		visualSphere.Color = Color3.fromRGB(50, 255, 50)
		StatusLabel.Text = "Status: Scanning..."
	else
		ToggleButton.Text = "OFF"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		visualSphere.Color = Color3.fromRGB(255, 50, 50)
		StatusLabel.Text = "Status: Idle"
		
		-- Force stop
		pathVisualsFolder:ClearAllChildren()
		updateWalkAnim(false) -- Stop anim
		isBusy = false
		if Humanoid and RootPart then
			Humanoid:MoveTo(RootPart.Position)
		end
	end
end)

CloseButton.MouseButton1Click:Connect(function()
	isEnabled = false
	if heartBeatConnection then heartBeatConnection:Disconnect() end
	if visualSphere then visualSphere:Destroy() end
	if pathVisualsFolder then pathVisualsFolder:Destroy() end
	updateWalkAnim(false)
	ScreenGui:Destroy()
end)

-- 8. MAIN LOOP
heartBeatConnection = RunService.Heartbeat:Connect(function()
	if not isEnabled or not targetCannon or not RootPart then return end
	
	-- USER INPUT CHECK
	if Humanoid.MoveDirection.Magnitude > 0.1 then
		StatusLabel.Text = "Status: Waiting for user..."
		pathVisualsFolder:ClearAllChildren()
		updateWalkAnim(false) -- Stop anim if user takes control
		isBusy = false
		return
	end
	
	if isBusy then return end
	
	local dist = (RootPart.Position - targetCannon:GetPivot().Position).Magnitude
	
	if dist <= DETECTION_RADIUS then
		isBusy = true
		StatusLabel.Text = "Status: Approaching..."
		
		task.spawn(function()
			-- Walk
			local destination = targetCannon:GetPivot().Position + (targetCannon:GetPivot().LookVector * -4)
			walkTo(destination)
			
			-- Fire?
			local currentDist = (RootPart.Position - destination).Magnitude
			if isEnabled and currentDist < INTERACTION_DISTANCE then
				triggerInteraction(targetCannon)
				StatusLabel.Text = "Status: Fired!"
				task.wait(1)
			else
				StatusLabel.Text = "Status: Retrying..."
				task.wait(0.2) 
			end
			
			isBusy = false
		end)
	else
		StatusLabel.Text = "Status: Waiting in range..."
	end
end)
