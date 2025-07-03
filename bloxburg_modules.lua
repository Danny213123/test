local DataService = game:GetService("ReplicatedStorage").Modules.DataService

local Hashes = {} 
local Remotes = {}
local AllHashMappings = {} -- Store all hash->name mappings found

-- Create GUI
local player = game.Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DataServiceInspector"
gui.ResetOnSpawn = false
gui.Parent = player.PlayerGui

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 800, 0, 700)
mainFrame.Position = UDim2.new(0.5, -400, 0.5, -350)
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
titleLabel.Text = "DataService Inspector"
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
searchBox.Size = UDim2.new(0.6, -10, 0, 30)
searchBox.Position = UDim2.new(0, 10, 0, 40)
searchBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
searchBox.BorderSizePixel = 0
searchBox.Text = ""
searchBox.PlaceholderText = "Search results..."
searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
searchBox.TextScaled = true
searchBox.Font = Enum.Font.SourceSans
searchBox.ClearTextOnFocus = false
searchBox.Parent = mainFrame

-- Hash Lookup Box
local hashLookupBox = Instance.new("TextBox")
hashLookupBox.Size = UDim2.new(0.4, -10, 0, 30)
hashLookupBox.Position = UDim2.new(0.6, 0, 0, 40)
hashLookupBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
hashLookupBox.BorderSizePixel = 0
hashLookupBox.Text = ""
hashLookupBox.PlaceholderText = "Enter hash to lookup..."
hashLookupBox.TextColor3 = Color3.fromRGB(255, 255, 255)
hashLookupBox.TextScaled = true
hashLookupBox.Font = Enum.Font.SourceSans
hashLookupBox.ClearTextOnFocus = false
hashLookupBox.Parent = mainFrame

-- Results Container
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -90)
scrollFrame.Position = UDim2.new(0, 10, 0, 80)
scrollFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 10
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
scrollFrame.CanvasPosition = Vector2.new(0, 0)
scrollFrame.Parent = mainFrame

-- Create multiple text labels to handle large content
local textLabels = {}
local currentLabelIndex = 1
local maxCharsPerLabel = 50000 -- Limit per TextBox to avoid cutoff

local function createNewTextLabel()
    local label = Instance.new("TextBox")
    label.Size = UDim2.new(1, -10, 0, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Font = Enum.Font.Code
    label.TextSize = 14
    label.TextEditable = false
    label.ClearTextOnFocus = false
    label.MultiLine = true
    label.RichText = true
    label.Parent = scrollFrame
    table.insert(textLabels, label)
    return label
end

-- Initialize first label
createNewTextLabel()

-- Store all log entries
local allLogs = {}
local fullText = ""

local function updateDisplay()
    -- Clear all labels
    for _, label in ipairs(textLabels) do
        label.Text = ""
        label.Visible = false
    end
    
    -- Split text across multiple labels if needed
    local remainingText = fullText
    local labelIndex = 1
    local totalHeight = 0
    
    while #remainingText > 0 do
        if labelIndex > #textLabels then
            createNewTextLabel()
        end
        
        local label = textLabels[labelIndex]
        local chunk = remainingText:sub(1, maxCharsPerLabel)
        
        -- Find last newline to avoid cutting mid-line
        local lastNewline = chunk:find("\n[^\n]*$")
        if lastNewline and #remainingText > maxCharsPerLabel then
            chunk = chunk:sub(1, lastNewline)
        end
        
        label.Text = chunk
        label.Visible = true
        remainingText = remainingText:sub(#chunk + 1)
        
        -- Wait for TextBounds to update
        wait()
        
        label.Size = UDim2.new(1, -10, 0, label.TextBounds.Y + 10)
        label.Position = UDim2.new(0, 0, 0, totalHeight)
        totalHeight = totalHeight + label.TextBounds.Y + 10
        
        labelIndex = labelIndex + 1
    end
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 50)
end

local function addLog(...)
    local args = {...}
    local str = ""
    for i, v in ipairs(args) do
        str = str .. tostring(v) .. (i < #args and " " or "")
    end
    table.insert(allLogs, str)
    fullText = table.concat(allLogs, "\n")
end

local function filterLogs(searchTerm)
    if searchTerm == "" then
        fullText = table.concat(allLogs, "\n")
    else
        local filtered = {}
        searchTerm = searchTerm:lower()
        for _, log in ipairs(allLogs) do
            if log:lower():find(searchTerm, 1, true) then
                table.insert(filtered, log)
            end
        end
        fullText = table.concat(filtered, "\n")
    end
    
    updateDisplay()
end

-- Hash lookup function
local function lookupHash(hash)
    if hash == "" then return end
    
    local results = {}
    
    -- Check in Hashes table
    for k, v in pairs(Hashes) do
        if tostring(k) == hash or tostring(v) == hash then
            table.insert(results, string.format("Found in Hashes: [%s] = %s", tostring(k), tostring(v)))
        end
    end
    
    -- Check in Remotes table
    for name, remote in pairs(Remotes) do
        if tostring(remote) == hash then
            table.insert(results, string.format("Found in Remotes: %s => %s", name, tostring(remote)))
        end
    end
    
    -- Check in AllHashMappings
    if AllHashMappings[hash] then
        table.insert(results, string.format("Hash mapping found: %s => %s", hash, AllHashMappings[hash]))
    end
    
    -- Search through logs for the hash
    for _, log in ipairs(allLogs) do
        if log:find(hash, 1, true) and not log:find("Hash lookup result", 1, true) then
            table.insert(results, "Log entry: " .. log)
        end
    end
    
    -- Display results
    if #results > 0 then
        addLog("\n=== Hash lookup results for: " .. hash .. " ===")
        for _, result in ipairs(results) do
            addLog(result)
        end
        addLog("=== End of hash lookup ===\n")
    else
        addLog("\n=== No results found for hash: " .. hash .. " ===\n")
    end
    
    updateDisplay()
    
    -- Scroll to bottom to show results
    wait()
    scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.CanvasSize.Y.Offset)
end

-- Search functionality
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterLogs(searchBox.Text)
end)

-- Hash lookup functionality
hashLookupBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        lookupHash(hashLookupBox.Text)
        hashLookupBox.Text = ""
    end
end)

-- Close button functionality
closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- Make frame draggable
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

-- Start inspection (collect all logs first, then display)
addLog("=== Starting DataService Inspection ===")
addLog("Timestamp:", os.date("%Y-%m-%d %H:%M:%S"))
addLog("DataService module:", DataService)

-- Additional modules to check
local PlayerModules = game:GetService("Players").LocalPlayer.PlayerScripts:FindFirstChild("Modules")
local ReplicatedModules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")

addLog("\n--- Checking Additional Module Locations ---")
addLog("PlayerScripts Modules:", PlayerModules and tostring(PlayerModules) or "Not found")
addLog("ReplicatedStorage Modules:", ReplicatedModules and tostring(ReplicatedModules) or "Not found")

-- Function to scan module for upvalues
local function scanModuleUpvalues(module, moduleName)
    addLog(string.format("\n--- Scanning %s ---", moduleName))
    local success, result = pcall(function()
        return require(module)
    end)
    
    if not success then
        addLog("  Failed to require module:", result)
        return
    end
    
    if type(result) == "table" then
        for funcName, func in pairs(result) do
            if type(func) == "function" then
                addLog(string.format("  Function: %s", tostring(funcName)))
                for i, v in next, getupvalues(func) do
                    addLog(string.format("    Upvalue [%d]: %s", i, type(v)))
                    if type(v) == "table" then
                        local count = 0
                        for _ in pairs(v) do count = count + 1 end
                        addLog(string.format("      -> Table with %d entries", count))
                        
                        -- Print all table entries
                        if count > 0 then
                            addLog("      -> Table contents:")
                            for key, value in pairs(v) do
                                local valueStr = tostring(value)
                                local valueType = typeof(value)
                                
                                -- For instances, show more detail
                                if valueType == "Instance" then
                                    valueStr = string.format("%s (%s)", value:GetFullName(), value.ClassName)
                                elseif type(value) == "function" then
                                    local info = debug.getinfo(value)
                                    if info then
                                        valueStr = string.format("function: %s", info.name or "anonymous")
                                    end
                                elseif type(value) == "table" then
                                    local subCount = 0
                                    for _ in pairs(value) do subCount = subCount + 1 end
                                    valueStr = string.format("table (%d items)", subCount)
                                end
                                
                                addLog(string.format("        [%s] = %s (%s)", tostring(key), valueStr, valueType))
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Scan all modules in PlayerScripts
if PlayerModules then
    addLog("\n--- Scanning PlayerScripts Modules ---")
    for _, module in ipairs(PlayerModules:GetDescendants()) do
        if module:IsA("ModuleScript") then
            scanModuleUpvalues(module, "PlayerScripts/" .. module.Name)
        end
    end
else
    addLog("\n--- PlayerScripts Modules not found, skipping ---")
end

-- Scan all modules in ReplicatedStorage
if ReplicatedModules then
    addLog("\n--- Scanning ReplicatedStorage Modules ---")
    for _, module in ipairs(ReplicatedModules:GetDescendants()) do
        if module:IsA("ModuleScript") then
            scanModuleUpvalues(module, "ReplicatedStorage/" .. module.Name)
        end
    end
else
    addLog("\n--- ReplicatedStorage Modules not found, skipping ---")
end

-- First section: Looking for hashes in all modules
addLog("\n--- Section 1: Searching for Hashes ---")

-- Function to search for hashes in a module's FireServer function
local function searchForHashesInModule(module, moduleName)
    local success, moduleData = pcall(function() return require(module) end)
    if not success then
        addLog(string.format("  Could not require %s: %s", moduleName, tostring(moduleData)))
        return
    end
    
    if type(moduleData) == "table" and rawget(moduleData, "FireServer") then
        addLog(string.format("\n  Checking %s.FireServer", moduleName))
        for i, v in next, getupvalues(rawget(moduleData, "FireServer")) do
            addLog(string.format("    Upvalue [%d]: %s", i, type(v)))
            
            if type(v) == "function" then
                addLog("      -> Found function, checking its upvalues...")
                
                for k, x in next, getupvalues(v) do
                    addLog(string.format("        Upvalue [%d]: %s", k, type(x)))
                    
                    if type(x) == "table" then
                        local tableSize = 0
                        for _ in pairs(x) do tableSize = tableSize + 1 end
                        addLog(string.format("          -> Found table with %d entries, checking contents...", tableSize))
                        
                        -- Print all entries in the table
                        for a, b in next, x do
                            local bStr = tostring(b)
                            local bType = typeof(b)
                            
                            if bType == "Instance" then
                                bStr = string.format("%s (%s)", b:GetFullName(), b.ClassName)
                                addLog(string.format("            [%s] = %s (%s) [INSTANCE FOUND!]", tostring(a), bStr, bType))
                                addLog("              -> Found Instance! Setting as Hashes table")
                                Hashes = x
                                
                                -- Continue to show all entries in the Hashes table
                                addLog("              -> Full Hashes table contents:")
                                for hashKey, hashValue in pairs(x) do
                                    local hvStr = tostring(hashValue)
                                    if typeof(hashValue) == "Instance" then
                                        hvStr = string.format("%s (%s)", hashValue:GetFullName(), hashValue.ClassName)
                                    end
                                    addLog(string.format("                [%s] = %s", tostring(hashKey), hvStr))
                                end
                                
                                return true
                            else
                                if type(b) == "function" then
                                    local info = debug.getinfo(b)
                                    if info then
                                        bStr = string.format("function: %s", info.name or "anonymous")
                                    end
                                elseif type(b) == "table" then
                                    local subCount = 0
                                    for _ in pairs(b) do subCount = subCount + 1 end
                                    bStr = string.format("table (%d items)", subCount)
                                end
                                
                                addLog(string.format("            [%s] = %s (%s)", tostring(a), bStr, bType))
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Check DataService first
addLog("\n  Checking DataService...")
if not searchForHashesInModule(DataService, "DataService") then
    -- Check PlayerScripts modules
    if PlayerModules then
        addLog("\n  Checking PlayerScripts modules...")
        for _, module in ipairs(PlayerModules:GetDescendants()) do
            if module:IsA("ModuleScript") then
                if searchForHashesInModule(module, "PlayerScripts/" .. module.Name) then
                    break
                end
            end
        end
    end
    
    -- If still not found, check ReplicatedStorage modules
    if next(Hashes) == nil and ReplicatedModules then
        addLog("\n  Checking ReplicatedStorage modules...")
        for _, module in ipairs(ReplicatedModules:GetDescendants()) do
            if module:IsA("ModuleScript") then
                if searchForHashesInModule(module, "ReplicatedStorage/" .. module.Name) then
                    break
                end
            end
        end
    end
end

addLog("\nHashes table found:", next(Hashes) ~= nil)
addLog("Hashes count:", #Hashes)

-- Print all hashes with details
if next(Hashes) ~= nil then
    addLog("\nFull Hashes table contents:")
    local hashIndex = 0
    for k, v in pairs(Hashes) do
        hashIndex = hashIndex + 1
        local vStr = tostring(v)
        if typeof(v) == "Instance" then
            vStr = string.format("%s (%s)", v:GetFullName(), v.ClassName)
        end
        addLog(string.format("  Hash[%s] = %s", tostring(k), vStr))
    end
    addLog(string.format("Total unique hashes: %d", hashIndex))
else
    addLog("No hashes found in any checked modules")
end

-- Second section: Finding remoteAdded function
addLog("\n--- Section 2: Searching for remoteAdded function ---")
local remoteAdded
local registryCount = 0

-- First check the registry
for i, v in next, getreg() do 
    registryCount = registryCount + 1
    
    if type(v) == "function" and islclosure(v) and getinfo(v).name == "remoteAdded" then 
        addLog(string.format("Found remoteAdded at registry index %d", i))
        remoteAdded = v 
    end 
end

addLog("Total registry entries scanned:", registryCount)

-- If not found in registry, check module upvalues
if not remoteAdded then
    addLog("remoteAdded not found in registry, checking module upvalues...")
    
    local function checkModuleForRemoteAdded(module, moduleName)
        local success, moduleData = pcall(function() return require(module) end)
        if success and type(moduleData) == "table" then
            addLog(string.format("  Checking module: %s", moduleName))
            local funcCount = 0
            for name, func in pairs(moduleData) do
                if type(func) == "function" then
                    funcCount = funcCount + 1
                end
            end
            addLog(string.format("    Found %d functions in module", funcCount))
            
            for name, func in pairs(moduleData) do
                if type(func) == "function" then
                    local upvalCount = 0
                    for _ in getupvalues(func) do upvalCount = upvalCount + 1 end
                    addLog(string.format("    Checking function '%s' with %d upvalues", tostring(name), upvalCount))
                    
                    for i, upval in next, getupvalues(func) do
                        if type(upval) == "function" then
                            local info = debug.getinfo(upval)
                            if info and info.name == "remoteAdded" then
                                addLog(string.format("      -> Found remoteAdded in %s.%s upvalue[%d]", moduleName, tostring(name), i))
                                return upval
                            end
                        end
                    end
                end
            end
        end
        return nil
    end
    
    -- Check all module locations
    remoteAdded = checkModuleForRemoteAdded(DataService, "DataService")
    
    if not remoteAdded and PlayerModules then
        for _, module in ipairs(PlayerModules:GetDescendants()) do
            if module:IsA("ModuleScript") then
                remoteAdded = checkModuleForRemoteAdded(module, "PlayerScripts/" .. module.Name)
                if remoteAdded then break end
            end
        end
    end
    
    if not remoteAdded and ReplicatedModules then
        for _, module in ipairs(ReplicatedModules:GetDescendants()) do
            if module:IsA("ModuleScript") then
                remoteAdded = checkModuleForRemoteAdded(module, "ReplicatedStorage/" .. module.Name)
                if remoteAdded then break end
            end
        end
    end
end

addLog("remoteAdded function found:", remoteAdded ~= nil)

-- Third section: Building Remotes table
addLog("\n--- Section 3: Building Remotes table ---")
if remoteAdded then
    for i, v in next, getupvalues(remoteAdded) do
        addLog(string.format("remoteAdded upvalue [%d]: %s", i, type(v)))
        
        if type(v) == "table" then
            local tableCount = 0
            for _ in pairs(v) do tableCount = tableCount + 1 end
            addLog(string.format("  -> Found table with %d entries", tableCount))
            
            -- Print table contents
            if tableCount > 0 then
                addLog("  -> Table contents:")
                for tKey, tValue in pairs(v) do
                    local tValueStr = tostring(tValue)
                    if typeof(tValue) == "Instance" then
                        tValueStr = string.format("%s (%s)", tValue:GetFullName(), tValue.ClassName)
                    elseif type(tValue) == "function" then
                        local info = debug.getinfo(tValue)
                        if info then
                            tValueStr = string.format("function: %s", info.name or "anonymous")
                        end
                    elseif type(tValue) == "table" then
                        local subCount = 0
                        for _ in pairs(tValue) do subCount = subCount + 1 end
                        tValueStr = string.format("table (%d items)", subCount)
                    end
                    addLog(string.format("    [%s] = %s (%s)", tostring(tKey), tValueStr, typeof(tValue)))
                end
            end
        elseif type(v) == "function" then
            addLog("  -> Found function, checking its upvalues...")
            
            for k, x in next, getupvalues(v) do
                addLog(string.format("    Upvalue [%d]: %s", k, type(x)))
                
                if type(x) == "table" then
                    local xCount = 0
                    for _ in pairs(x) do xCount = xCount + 1 end
                    addLog(string.format("      -> Found table with %d entries, processing...", xCount))
                    
                    for a, b in next, x do
                        local logEntry = string.format("        Entry: [%s] = %s", tostring(a), tostring(b))
                        addLog(logEntry)
                        
                        -- Store hash mapping
                        AllHashMappings[tostring(a)] = tostring(b)
                        
                        local remote = Hashes[a]
                        if remote then
                            local remoteName = b:sub(1, 2) == "F_" and b:sub(3) or b
                            Remotes[remoteName] = remote
                            AllHashMappings[tostring(remote)] = remoteName
                            addLog(string.format("          -> Mapped: %s => %s", remoteName, tostring(remote)))
                        else
                            addLog("          -> No matching hash found")
                        end
                    end
                end
            end
        end
    end
else
    addLog("remoteAdded function not found, cannot build Remotes table")
end

-- Final summary
addLog("\n=== Final Results ===")
addLog("Total Hashes found:", #Hashes)
addLog("Total Remotes mapped:", #Remotes)
addLog("Total Hash Mappings collected:", #AllHashMappings)

addLog("\nRemotes table contents:")
for name, remote in next, Remotes do
    addLog(string.format("  %s => %s", name, tostring(remote)))
end

addLog("\n=== Module Check Summary ===")
addLog("Modules checked:")
addLog("  - DataService (ReplicatedStorage)")
addLog("  - PlayerScripts.Modules (all descendants)")
addLog("  - ReplicatedStorage.Modules (all descendants)")

addLog("\n=== Hash Lookup Instructions ===")
addLog("Enter a hash in the right text box and press Enter to look it up.")
addLog("The inspector will search for the hash in all collected data.")

addLog("\n=== Inspection Complete ===")

-- Display all results at once
updateDisplay()

-- Make results available globally for querying
_G.DataServiceInspectorResults = {
    Hashes = Hashes,
    Remotes = Remotes,
    HashMappings = AllHashMappings,
    Logs = allLogs
}

print("DataService Inspector GUI loaded. Results also available in _G.DataServiceInspectorResults")
print("To lookup a hash: Enter it in the right text box and press Enter")
