-- This script should be placed in StarterPlayer > StarterPlayerScripts
-- Controls:
-- F key = Toggle GUI visibility (show/hide the window)
-- Stop button = Stop walking to the target
-- X button = Hide the GUI (can reopen with F or Toggle button)

print("Plot Object Finder script starting...")

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Wait for workspace to load properly
wait(2)

print("Plot Object Finder loaded for player: " .. player.Name)
print("PathfindingService available: " .. tostring(PathfindingService ~= nil))
print("Checking for Plots folder...")
local plotsCheck = workspace:FindFirstChild("Plots")
if plotsCheck then
	print("Plots folder found with " .. #plotsCheck:GetChildren() .. " plots")
else
	print("WARNING: Plots folder not found in workspace!")
end

-- Create GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlotObjectFinder"
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Toggle Button (always visible)
local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 120, 0, 35)
toggleButton.Position = UDim2.new(1, -130, 0, 10)
toggleButton.Text = "Toggle Finder (F)"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.BackgroundColor3 = Color3.fromRGB(51, 51, 51)
toggleButton.BorderSizePixel = 2
toggleButton.BorderColor3 = Color3.fromRGB(102, 102, 102)
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.TextSize = 14
toggleButton.Parent = screenGui

-- Main Frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 350, 0, 320)
frame.Position = UDim2.new(0.5, -175, 0.5, -160)
frame.BackgroundColor3 = Color3.fromRGB(51, 51, 51)
frame.BorderSizePixel = 0
frame.Visible = true -- Start visible
frame.Parent = screenGui

-- Title Label
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -30, 0, 30)
titleLabel.Position = UDim2.new(0, 0, 0, 0)
titleLabel.Text = "Plot Object Finder - " .. player.Name .. " (Drag to move)"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
titleLabel.BorderSizePixel = 0
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 16
titleLabel.Parent = frame

-- Close Button
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -30, 0, 0)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.BackgroundColor3 = Color3.fromRGB(204, 51, 51)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 18
closeButton.Parent = frame

-- Make GUI draggable
local dragging = false
local dragStart = nil
local startPos = nil

local function updateDrag(input)
	local delta = input.Position - dragStart
	frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

titleLabel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

titleLabel.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
		updateDrag(input)
	end
end)

-- Input TextBox
local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(0.9, 0, 0, 30)
inputBox.Position = UDim2.new(0.05, 0, 0.15, 0)
inputBox.PlaceholderText = "Enter: Large Organic Tree, Small Organic Tree, tree"
inputBox.Text = ""
inputBox.TextColor3 = Color3.fromRGB(0, 0, 0)
inputBox.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
inputBox.BorderSizePixel = 1
inputBox.Font = Enum.Font.SourceSans
inputBox.TextSize = 14
inputBox.Parent = frame

-- Instructions label
local instructLabel = Instance.new("TextLabel")
instructLabel.Size = UDim2.new(0.9, 0, 0, 15)
instructLabel.Position = UDim2.new(0.05, 0, 0.25, 0)
instructLabel.Text = "Tip: Just type 'tree' to find any tree, 'large' for large trees, etc."
instructLabel.TextColor3 = Color3.fromRGB(153, 153, 153)
instructLabel.BackgroundTransparency = 1
instructLabel.Font = Enum.Font.SourceSansItalic
instructLabel.TextSize = 11
instructLabel.Parent = frame

-- Find Button
local findButton = Instance.new("TextButton")
findButton.Size = UDim2.new(0.4, 0, 0, 30)
findButton.Position = UDim2.new(0.05, 0, 0.35, 0)
findButton.Text = "Find & Walk"
findButton.TextColor3 = Color3.fromRGB(255, 255, 255)
findButton.BackgroundColor3 = Color3.fromRGB(51, 153, 51)
findButton.BorderSizePixel = 0
findButton.Font = Enum.Font.SourceSansBold
findButton.TextSize = 16
findButton.Parent = frame

-- Stop Button
local stopButton = Instance.new("TextButton")
stopButton.Size = UDim2.new(0.4, 0, 0, 30)
stopButton.Position = UDim2.new(0.55, 0, 0.35, 0)
stopButton.Text = "Stop"
stopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
stopButton.BackgroundColor3 = Color3.fromRGB(204, 51, 51)
stopButton.BorderSizePixel = 0
stopButton.Font = Enum.Font.SourceSansBold
stopButton.TextSize = 16
stopButton.Parent = frame

-- Allow pressing Enter to search
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		findButton.MouseButton1Click:Fire()
	end
end)

-- Status Label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.9, 0, 0, 20)
statusLabel.Position = UDim2.new(0.05, 0, 0.93, 0)
statusLabel.Text = "Ready | F = Show/Hide | Stop = Cancel Walking"
statusLabel.TextColor3 = Color3.fromRGB(204, 204, 204)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 12
statusLabel.Parent = frame

-- Debug Section
local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(0.7, 0, 0, 20)
debugLabel.Position = UDim2.new(0.05, 0, 0.5, 0)
debugLabel.Text = "Debug: SmallObjects Contents"
debugLabel.TextColor3 = Color3.fromRGB(204, 204, 204)
debugLabel.BackgroundTransparency = 1
debugLabel.Font = Enum.Font.SourceSansBold
debugLabel.TextSize = 12
debugLabel.Parent = frame

-- Refresh Button
local refreshButton = Instance.new("TextButton")
refreshButton.Size = UDim2.new(0, 60, 0, 20)
refreshButton.Position = UDim2.new(0.95, -60, 0.5, 0)
refreshButton.Text = "Refresh"
refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshButton.BackgroundColor3 = Color3.fromRGB(76, 76, 153)
refreshButton.BorderSizePixel = 0
refreshButton.Font = Enum.Font.SourceSans
refreshButton.TextSize = 12
refreshButton.Parent = frame

-- Debug ScrollingFrame
local debugScroll = Instance.new("ScrollingFrame")
debugScroll.Size = UDim2.new(0.9, 0, 0, 80)
debugScroll.Position = UDim2.new(0.05, 0, 0.57, 0)
debugScroll.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
debugScroll.BorderColor3 = Color3.fromRGB(76, 76, 76)
debugScroll.ScrollBarThickness = 6
debugScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
debugScroll.Parent = frame

-- Debug content label
local debugContent = Instance.new("TextLabel")
debugContent.Name = "DebugContent"
debugContent.Size = UDim2.new(1, -10, 1, 0)
debugContent.Position = UDim2.new(0, 5, 0, 0)
debugContent.Text = "Loading..."
debugContent.TextColor3 = Color3.fromRGB(230, 230, 230)
debugContent.BackgroundTransparency = 1
debugContent.Font = Enum.Font.Code
debugContent.TextSize = 11
debugContent.TextXAlignment = Enum.TextXAlignment.Left
debugContent.TextYAlignment = Enum.TextYAlignment.Top
debugContent.TextWrapped = true
debugContent.Parent = debugScroll

-- Variables for pathfinding
local currentPath = nil
local currentWaypoint = 1
local isWalking = false
local pathConnection = nil

-- Forward declare findPlayerPlot function
local findPlayerPlot

-- Function to update status
local function updateStatus(message, color)
	statusLabel.Text = message
	statusLabel.TextColor3 = color or Color3.fromRGB(204, 204, 204)
end

-- Function to update debug information
local function updateDebugInfo()
	debugContent.Text = "Searching for plot..."
	
	local plot = findPlayerPlot()
	if not plot then
		debugContent.Text = "Plot not found! Looking for: Plot_" .. player.Name
		return
	end
	
	local objectList = {}
	table.insert(objectList, "Plot found: " .. plot.Name)
	table.insert(objectList, "--------------------")
	
	-- First check for SmallObjects folder
	local smallObjectsFolder = plot:FindFirstChild("SmallObjects")
	if smallObjectsFolder then
		table.insert(objectList, "SmallObjects folder found!")
		table.insert(objectList, "")
		
		local objectCount = 0
		for _, obj in pairs(smallObjectsFolder:GetDescendants()) do
			if obj:IsA("Model") or obj:IsA("BasePart") then
				objectCount = objectCount + 1
				if objectCount <= 20 then -- Limit display to first 20 objects
					local objType = obj.ClassName
					local objName = obj.Name
					local info = string.format("- %s (%s)", objName, objType)
					
					-- Add parent info if not direct child
					if obj.Parent ~= smallObjectsFolder then
						info = info .. " in " .. obj.Parent.Name
					end
					
					table.insert(objectList, info)
				end
			end
		end
		
		if objectCount > 20 then
			table.insert(objectList, "... and " .. (objectCount - 20) .. " more objects")
		elseif objectCount == 0 then
			table.insert(objectList, "(No objects found in SmallObjects)")
		end
		
		table.insert(objectList, "")
		table.insert(objectList, "Total objects in SmallObjects: " .. objectCount)
	else
		table.insert(objectList, "SmallObjects folder NOT FOUND!")
		table.insert(objectList, "")
		table.insert(objectList, "Available folders/models in plot:")
		for _, child in pairs(plot:GetChildren()) do
			local childInfo = "- " .. child.Name .. " (" .. child.ClassName .. ")"
			table.insert(objectList, childInfo)
		end
	end
	
	local debugText = table.concat(objectList, "\n")
	debugContent.Text = debugText
	
	-- Adjust canvas size based on content
	local textService = game:GetService("TextService")
	local textBounds = textService:GetTextSize(
		debugText,
		debugContent.TextSize,
		debugContent.Font,
		Vector2.new(debugScroll.AbsoluteSize.X - 10, math.huge)
	)
	
	debugScroll.CanvasSize = UDim2.new(0, 0, 0, textBounds.Y + 10)
	
	print("Debug info updated - found plot: " .. plot.Name)
end

-- Function to find player's plot
findPlayerPlot = function()
	-- Wait for Plots folder with timeout
	local plotsFolder = workspace:WaitForChild("Plots", 5)
	
	if not plotsFolder then
		-- Try alternative locations
		for _, child in pairs(workspace:GetChildren()) do
			if child.Name:lower():find("plot") then
				plotsFolder = child
				break
			end
		end
		
		if not plotsFolder then
			updateStatus("Plots folder not found in Workspace!", Color3.fromRGB(255, 0, 0))
			return nil
		end
	end
	
	-- Try different plot naming conventions
	local possibleNames = {
		"Plot_" .. player.Name,
		"Plot" .. player.Name,
		player.Name .. "_Plot",
		player.Name .. "Plot",
		player.Name
	}
	
	-- First try exact matches
	for _, plotName in pairs(possibleNames) do
		local plot = plotsFolder:FindFirstChild(plotName)
		if plot then
			print("Found plot: " .. plot.Name)
			print("Plot children:")
			for _, child in pairs(plot:GetChildren()) do
				print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
			end
			return plot
		end
	end
	
	-- If exact match not found, try case-insensitive search
	for _, child in pairs(plotsFolder:GetChildren()) do
		if child.Name:lower():find(player.Name:lower()) then
			print("Found plot (case-insensitive): " .. child.Name)
			return child
		end
	end
	
	updateStatus("Your plot not found! Tried: " .. table.concat(possibleNames, ", "), Color3.fromRGB(255, 0, 0))
	print("Could not find plot for player: " .. player.Name)
	print("Available plots in Plots folder:")
	for _, child in pairs(plotsFolder:GetChildren()) do
		print("  - " .. child.Name)
	end
	return nil
end

-- Function to find object in plot
local function findObjectInPlot(plot, objectName)
	local foundObjects = {}
	
	-- Make search case-insensitive
	local searchName = objectName:lower()
	
	local function searchDescendants(parent)
		print("Searching in: " .. parent:GetFullName())
		for _, child in pairs(parent:GetDescendants()) do
			-- Check if it's a part or model and if name matches (case-insensitive, partial match)
			if (child:IsA("BasePart") or child:IsA("Model")) then
				-- Special handling for "tree" search to match any tree type
				local isTreeSearch = searchName == "tree" or searchName == "trees"
				local matchFound = false
				
				if isTreeSearch and (child.Name:lower():find("tree", 1, true) or 
					(child.Parent and child.Parent.Name:lower():find("tree", 1, true))) then
					matchFound = true
				elseif child.Name:lower():find(searchName, 1, true) then
					matchFound = true
				end
				
				if matchFound then
					print("  Found matching object: " .. child.Name .. " (" .. child.ClassName .. ")")
					-- For models, try to find a primary part or any part inside
					if child:IsA("Model") then
						local targetPart = nil
						
						-- First try PrimaryPart
						if child.PrimaryPart then
							targetPart = child.PrimaryPart
							print("    Found PrimaryPart: " .. targetPart.Name)
						else
							-- Try to set PrimaryPart if not set
							local firstPart = child:FindFirstChildWhichIsA("BasePart", true)
							if firstPart then
								targetPart = firstPart
								print("    Found first part: " .. firstPart.Name)
							else
								-- Find any BasePart descendant
								for _, desc in pairs(child:GetDescendants()) do
									if desc:IsA("BasePart") then
										targetPart = desc
										print("    Found descendant part: " .. desc.Name)
										break
									end
								end
							end
						end
						
						if targetPart then
							print("    Using part: " .. targetPart.Name .. " from model")
							table.insert(foundObjects, targetPart)
						else
							print("    Warning: Model has no parts!")
						end
					else
						table.insert(foundObjects, child)
					end
				end
			end
		end
	end
	
	-- Search entire plot
	searchDescendants(plot)
	
	print("Total found " .. #foundObjects .. " objects matching '" .. objectName .. "'")
	
	if #foundObjects > 0 then
		-- Return the closest object
		local closestObject = nil
		local closestDistance = math.huge
		
		for _, obj in pairs(foundObjects) do
			if obj.Position and rootPart and rootPart.Parent then
				local distance = (obj.Position - rootPart.Position).Magnitude
				if distance < closestDistance then
					closestDistance = distance
					closestObject = obj
				end
			end
		end
		
		if closestObject then
			print("Closest object is at distance: " .. closestDistance)
		end
		
		return closestObject
	end
	
	return nil
end

-- Function to create path
local function createPath(targetPosition)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentMaxSlope = 45,
		WaypointSpacing = 4,
		Costs = {
			Water = 20,
			-- Add more material costs if needed
		}
	})
	
	local success, errorMessage = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		return path
	else
		updateStatus("Failed to create path: " .. tostring(errorMessage), Color3.fromRGB(255, 0, 0))
		return nil
	end
end

-- Function to visualize path (optional, for debugging)
local function visualizePath(waypoints)
	-- Clear old visualization
	local existingParts = workspace:FindFirstChild("PathVisualization")
	if existingParts then
		existingParts:Destroy()
	end
	
	local folder = Instance.new("Folder")
	folder.Name = "PathVisualization"
	folder.Parent = workspace
	
	for i, waypoint in pairs(waypoints) do
		local part = Instance.new("Part")
		part.Name = "Waypoint" .. i
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.Position = waypoint.Position
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.BrickColor = waypoint.Action == Enum.PathWaypointAction.Jump and BrickColor.new("Bright yellow") or BrickColor.new("Bright green")
		part.Parent = folder
	end
end

-- Function to follow path
local function followPath()
	if not currentPath or not isWalking then
		return
	end
	
	local waypoints = currentPath:GetWaypoints()
	
	-- Visualize path (optional)
	-- visualizePath(waypoints)
	
	if pathConnection then
		pathConnection:Disconnect()
	end
	
	currentWaypoint = 1
	local lastWaypoint = 1
	local stuckTime = 0
	
	pathConnection = RunService.Heartbeat:Connect(function()
		if not isWalking or not currentPath then
			if pathConnection then
				pathConnection:Disconnect()
			end
			return
		end
		
		if currentWaypoint > #waypoints then
			-- Reached destination
			isWalking = false
			updateStatus("Reached destination!", Color3.fromRGB(51, 204, 51))
			if pathConnection then
				pathConnection:Disconnect()
			end
			
			-- Clear visualization
			local existingParts = workspace:FindFirstChild("PathVisualization")
			if existingParts then
				existingParts:Destroy()
			end
			return
		end
		
		local waypoint = waypoints[currentWaypoint]
		local distance = (waypoint.Position - rootPart.Position).Magnitude
		
		-- Move to waypoint
		humanoid:MoveTo(waypoint.Position)
		
		-- Check if need to jump
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		
		-- Check if reached waypoint
		if distance < 5 then
			currentWaypoint = currentWaypoint + 1
		end
		
		-- Timeout check - if stuck on same waypoint for too long, skip it
		if currentWaypoint == lastWaypoint then
			stuckTime = stuckTime + 0.03 -- approximate heartbeat time
			if stuckTime > 3 then -- 3 seconds timeout
				currentWaypoint = currentWaypoint + 1
				stuckTime = 0
				print("Skipped stuck waypoint " .. (currentWaypoint - 1))
			end
		else
			lastWaypoint = currentWaypoint
			stuckTime = 0
		end
		
		-- Update status
		updateStatus("Walking... Waypoint " .. currentWaypoint .. "/" .. #waypoints, Color3.fromRGB(204, 204, 51))
	end)
end

-- Function to stop walking
local function stopWalking()
	isWalking = false
	humanoid:MoveTo(rootPart.Position)
	
	if pathConnection then
		pathConnection:Disconnect()
		pathConnection = nil
	end
	
	-- Clear visualization
	local existingParts = workspace:FindFirstChild("PathVisualization")
	if existingParts then
		existingParts:Destroy()
	end
	
	updateStatus("Stopped", Color3.fromRGB(204, 204, 204))
end

-- Button click handlers
findButton.MouseButton1Click:Connect(function()
	-- Ensure character exists
	if not character or not character.Parent then
		character = player.Character or player.CharacterAdded:Wait()
		humanoid = character:WaitForChild("Humanoid")
		rootPart = character:WaitForChild("HumanoidRootPart")
	end
	
	local objectName = inputBox.Text
	
	if objectName == "" then
		updateStatus("Please enter an object name!", Color3.fromRGB(255, 128, 0))
		return
	end
	
	-- Stop any current pathfinding
	stopWalking()
	
	-- Update debug info
	updateDebugInfo()
	
	-- Find player's plot
	local plot = findPlayerPlot()
	if not plot then
		return
	end
	
	updateStatus("Searching for '" .. objectName .. "'...", Color3.fromRGB(204, 204, 51))
	
	-- Find object in plot
	local targetObject = findObjectInPlot(plot, objectName)
	if not targetObject then
		updateStatus("Object '" .. objectName .. "' not found in your plot!", Color3.fromRGB(255, 128, 0))
		-- Show what was searched
		print("Searched for: " .. objectName)
		print("In plot: " .. plot.Name)
		return
	end
	
	updateStatus("Found object! Creating path...", Color3.fromRGB(51, 204, 51))
	print("Target object found: " .. targetObject.Name .. " at position " .. tostring(targetObject.Position))
	
	-- Create path to object
	currentPath = createPath(targetObject.Position)
	if currentPath then
		isWalking = true
		followPath()
	end
end)

stopButton.MouseButton1Click:Connect(function()
	stopWalking()
end)

-- Close button handler
closeButton.MouseButton1Click:Connect(function()
	stopWalking()
	frame.Visible = false
end)

-- Toggle button handler
toggleButton.MouseButton1Click:Connect(function()
	frame.Visible = not frame.Visible
	if frame.Visible then
		updateDebugInfo()
	end
end)

-- Refresh button handler
refreshButton.MouseButton1Click:Connect(function()
	updateDebugInfo()
	updateStatus("Debug info refreshed!", Color3.fromRGB(51, 204, 51))
end)

-- Handle character respawn
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- Stop any ongoing pathfinding
	stopWalking()
	updateStatus("Ready", Color3.fromRGB(204, 204, 204))
	
	-- Update debug info
	updateDebugInfo()
end)

-- Clean up on player leaving
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		stopWalking()
		if screenGui then
			screenGui:Destroy()
		end
	end
end)

-- Keyboard shortcut (F key) to toggle GUI visibility
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.F then
		frame.Visible = not frame.Visible
		if frame.Visible then
			updateDebugInfo()
		end
	end
end)

-- Wait a moment for everything to load
wait(3)

-- Initialize debug info
print("Initializing debug info...")
updateDebugInfo()

-- Test finding the plot
local testPlot = findPlayerPlot()
if testPlot then
	print("Successfully found plot on initialization: " .. testPlot.Name)
	local smallObjects = testPlot:FindFirstChild("SmallObjects")
	if smallObjects then
		print("SmallObjects folder exists with " .. #smallObjects:GetChildren() .. " direct children")
		-- List first few objects
		local count = 0
		for _, obj in pairs(smallObjects:GetChildren()) do
			if count < 5 then
				print("  - " .. obj.Name .. " (" .. obj.ClassName .. ")")
				count = count + 1
			end
		end
	else
		print("SmallObjects folder not found in plot")
	end
else
	print("Failed to find plot on initialization")
end

-- Also print initial status
print("Plot Object Finder initialized. Press F to toggle GUI visibility.")

-- Refresh debug info every 5 seconds
spawn(function()
	while screenGui.Parent do
		wait(5)
		if frame.Visible then
			updateDebugInfo()
		end
	end
end)
