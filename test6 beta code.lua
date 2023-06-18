local function teleport(id)
	
	local args = {
        [1] = "playerRequest_taximanDave",
        [2] = id
    }
    
    game:GetService("ReplicatedStorage"):WaitForChild("playerRequest"):InvokeServer(unpack(args))

end


local function sell(index)
    local args = {
        [1] = "playerRequest_sellItemToShop",
        [2] = {
            ["id"] = 180,
            ["inventorySlotDataPosition"] = index,
            ["inventorySlotData"] = {
                ["id"] = 180,
                ["stacks"] = 1,
                ["position"] = index
            }
        },
        [3] = 1
    }
    
    game:GetService("ReplicatedStorage"):WaitForChild("playerRequest"):InvokeServer(unpack(args))
    
end

local function blacksmith(count)

	local args = {
	            [1] = "playerRequest_enchantEquipment",
	            [2] = workspace:WaitForChild("Blacksmith Ralph"),
	            [3] = {
	                ["id"] = 7,
	                ["stacks"] = 1,
	                ["serial"] = "{50ddc6cd-97c8-4ae1-bfc1-88e90c2c10ed}{231c35b8-c614-4022-be25-6c2e5d9a759c}",
	                ["position"] = count
	            }
	        }
	        
	        game:GetService("ReplicatedStorage"):WaitForChild("playerRequest"):InvokeServer(unpack(args))

end


local function main()
	
	if game.PlaceId == 2119298605 then
	
	    for count = 1, 21, 1 do
	
	        blacksmith(count)        
	
	    end
	
	    for count_2 = 1, 21, 1 do
            
            sell(count_2)
	
	    end
	
	    teleport(2064647391)
	    teleport(2064647391)
	    
	else
		
	    Workspace.placeFolders.entityManifestCollection:FindFirstChild("DannyTheConqueror"):FindFirstChild("hitbox").CFrame = CFrame.new(44.5641899, 48.0922089, -1107.88306, 0.909049511, 0, -0.416688085, 0, 1, 0, 0.416688085, 0, 0.909049511) 
	
	    for count = 0, 21, 1 do
	
	        local args = {
	            [1] = "playerRequest_buyItemFromShop",
	            [2] = workspace:WaitForChild("Shopkeeper"):WaitForChild("UpperTorso"):WaitForChild("inventory"),
	            [3] = 3,
	            [4] = 1
	        }
	        
	        game:GetService("ReplicatedStorage"):WaitForChild("playerRequest"):InvokeServer(unpack(args))        
	
	    end
	
		Workspace.placeFolders.entityManifestCollection:FindFirstChild("DannyTheConqueror"):FindFirstChild("hitbox").CFrame = CFrame.new(135.890884, 51.4916534, -1213.17395, 0.849822462, 0, -0.527069032, 0, 1, 0, 0.527069032, 0, 0.849822462) 
	
		teleport(2119298605)
		teleport(2119298605)
		teleport(2119298605)
		teleport(2119298605)
		teleport(2119298605)
		teleport(2119298605)
	
	end
end

print("here")
main()
