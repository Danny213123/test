local DataService = game:GetService("ReplicatedStorage").Modules.DataService

local player = game.Players.LocalPlayer

-- Create GUI
local gui = Instance.new("ScreenGui")
gui.Name = "DataServiceEventViewer"
gui.ResetOnSpawn = false
gui.Parent = player.PlayerGui

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 700, 0, 600)
mainFrame.Position = UDim2.new(0.5, -350, 0.5, -300)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -30, 1, 0)
titleLabel.Position = UDim2.new(0, 5, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "DataService Event Viewer"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = titleBar

-- Close Button
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -30, 0, 0)
closeButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.SourceSansBold
closeButton.Parent = titleBar

-- Search Box
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -20, 0, 30)
searchBox.Position = UDim2.new(0, 10, 0, 40)
searchBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
searchBox.BorderSizePixel = 0
searchBox.Text = ""
searchBox.PlaceholderText = "Search events..."
searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
searchBox.TextScaled = true
searchBox.Font = Enum.Font.SourceSans
searchBox.ClearTextOnFocus = false
searchBox.Parent = mainFrame

-- Header Frame
local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, -20, 0, 30)
headerFrame.Position = UDim2.new(0, 10, 0, 80)
headerFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
headerFrame.BorderSizePixel = 0
headerFrame.Parent = mainFrame

-- Headers
local headers = {
    {text = "Path", size = 0.3},
    {text = "Name", size = 0.3},
    {text = "Type", size = 0.2},
    {text = "Children", size = 0.2}
}

local xOffset = 0
for _, header in ipairs(headers) do
    local headerLabel = Instance.new("TextLabel")
    headerLabel.Size = UDim2.new(header.size, -5, 1, 0)
    headerLabel.Position = UDim2.new(xOffset, 5, 0, 0)
    headerLabel.BackgroundTransparency = 1
    headerLabel.Text = header.text
    headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    headerLabel.TextScaled = true
    headerLabel.Font = Enum.Font.SourceSansBold
    headerLabel.Parent = headerFrame
    xOffset = xOffset + header.size
end

-- Scrolling Frame
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -120)
scrollFrame.Position = UDim2.new(0, 10, 0, 110)
scrollFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 10
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
scrollFrame.Parent = mainFrame

-- Store all events
local allEvents = {}
local eventFrames = {}

-- Function to create event row
local function createEventRow(eventData, index)
    local rowFrame = Instance.new("Frame")
    rowFrame.Size = UDim2.new(1, -10, 0, 30)
    rowFrame.Position = UDim2.new(0, 0, 0, (index - 1) * 35)
    rowFrame.BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(35, 35, 35) or Color3.fromRGB(45, 45, 45)
    rowFrame.BorderSizePixel = 0
    rowFrame.Parent = scrollFrame
    
    -- Path
    local pathLabel = Instance.new("TextLabel")
    pathLabel.Size = UDim2.new(0.3, -5, 1, 0)
    pathLabel.Position = UDim2.new(0, 5, 0, 0)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Text = eventData.path
    pathLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextScaled = true
    pathLabel.Font = Enum.Font.Code
    pathLabel.Parent = rowFrame
    
    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0.3, -5, 1, 0)
    nameLabel.Position = UDim2.new(0.3, 5, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = eventData.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.SourceSans
    nameLabel.Parent = rowFrame
    
    -- Type
    local typeLabel = Instance.new("TextLabel")
    typeLabel.Size = UDim2.new(0.2, -5, 1, 0)
    typeLabel.Position = UDim2.new(0.6, 5, 0, 0)
    typeLabel.BackgroundTransparency = 1
    typeLabel.Text = eventData.type
    typeLabel.TextColor3 = eventData.type == "RemoteEvent" and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(200, 255, 100)
    typeLabel.TextXAlignment = Enum.TextXAlignment.Left
    typeLabel.TextScaled = true
    typeLabel.Font = Enum.Font.SourceSans
    typeLabel.Parent = rowFrame
    
    -- Children count
    local childrenLabel = Instance.new("TextLabel")
    childrenLabel.Size = UDim2.new(0.2, -5, 1, 0)
    childrenLabel.Position = UDim2.new(0.8, 5, 0, 0)
    childrenLabel.BackgroundTransparency = 1
    childrenLabel.Text = tostring(eventData.childrenCount)
    childrenLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    childrenLabel.TextXAlignment = Enum.TextXAlignment.Left
    childrenLabel.TextScaled = true
    childrenLabel.Font = Enum.Font.SourceSans
    childrenLabel.Parent = rowFrame
    
    -- Copy button
    local copyButton = Instance.new("TextButton")
    copyButton.Size = UDim2.new(0, 60, 0, 20)
    copyButton.Position = UDim2.new(1, -65, 0.5, -10)
    copyButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    copyButton.Text = "Copy"
    copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyButton.TextScaled = true
    copyButton.Font = Enum.Font.SourceSans
    copyButton.Parent = rowFrame
    
    copyButton.MouseButton1Click:Connect(function()
        -- Generate the code
        local code = string.format('local Event = game:GetService("ReplicatedStorage").Modules.DataService:GetChildren()[%d]', eventData.parentIndex)
        if eventData.childIndex then
            code = code .. string.format(':GetChildren()[%d]', eventData.childIndex)
        end
        
        setclipboard(code)
        copyButton.Text = "Copied!"
        copyButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        wait(1)
        copyButton.Text = "Copy"
        copyButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end)
    
    return rowFrame
end

-- Scan DataService
local function scanDataService()
    allEvents = {}
    
    -- First level children
    local firstLevelChildren = DataService:GetChildren()
    for i, child in ipairs(firstLevelChildren) do
        -- Add first level item
        table.insert(allEvents, {
            path = string.format("[%d]", i),
            name = child.Name,
            type = child.ClassName,
            instance = child,
            parentIndex = i,
            childrenCount = #child:GetChildren()
        })
        
        -- Second level children
        local secondLevelChildren = child:GetChildren()
        for j, subChild in ipairs(secondLevelChildren) do
            table.insert(allEvents, {
                path = string.format("[%d][%d]", i, j),
                name = subChild.Name,
                type = subChild.ClassName,
                instance = subChild,
                parentIndex = i,
                childIndex = j,
                childrenCount = #subChild:GetChildren()
            })
        end
    end
    
    -- Sort by path
    table.sort(allEvents, function(a, b)
        return a.path < b.path
    end)
end

-- Update display
local function updateDisplay(filter)
    -- Clear existing frames
    for _, frame in ipairs(eventFrames) do
        frame:Destroy()
    end
    eventFrames = {}
    
    -- Filter events
    local filteredEvents = {}
    filter = filter:lower()
    
    for _, event in ipairs(allEvents) do
        if filter == "" or 
           event.name:lower():find(filter, 1, true) or 
           event.path:lower():find(filter, 1, true) or
           event.type:lower():find(filter, 1, true) then
            table.insert(filteredEvents, event)
        end
    end
    
    -- Create rows
    for i, event in ipairs(filteredEvents) do
        local frame = createEventRow(event, i)
        table.insert(eventFrames, frame)
    end
    
    -- Update canvas size
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #filteredEvents * 35 + 10)
    
    -- Update title with count
    titleLabel.Text = string.format("DataService Event Viewer (%d events)", #filteredEvents)
end

-- Initial scan
scanDataService()
updateDisplay("")

-- Search functionality
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    updateDisplay(searchBox.Text)
end)

-- Refresh button
local refreshButton = Instance.new("TextButton")
refreshButton.Size = UDim2.new(0, 100, 0, 25)
refreshButton.Position = UDim2.new(1, -110, 1, -30)
refreshButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
refreshButton.Text = "Refresh"
refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshButton.TextScaled = true
refreshButton.Font = Enum.Font.SourceSansBold
refreshButton.Parent = mainFrame

refreshButton.MouseButton1Click:Connect(function()
    scanDataService()
    updateDisplay(searchBox.Text)
    refreshButton.Text = "Refreshed!"
    wait(1)
    refreshButton.Text = "Refresh"
end)

-- Close functionality
closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- Make draggable
local dragging = false
local dragStart = nil
local startPos = nil

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- Store results globally
_G.DataServiceEvents = allEvents

print("DataService Event Viewer loaded. Found", #allEvents, "events/functions")
print("Results also available in _G.DataServiceEvents")
