local function peformance_1()
    local a = game
    local b = a.Workspace
    local c = a.Lighting
    local d = b.Terrain
    d.WaterWaveSize = 0
    d.WaterWaveSpeed = 0
    d.WaterReflectance = 0
    d.WaterTransparency = 0
    c.GlobalShadows = false
    c.FogEnd = 9e9
    c.Brightness = 0
    settings().Rendering.QualityLevel = "Level01"
    for e, f in pairs(a:GetDescendants()) do
    if f:IsA("Part") or f:IsA("Union") or f:IsA("CornerWedgePart") or f:IsA("TrussPart") then
        f.Material = "Plastic"
        f.Reflectance = 0
    elseif f:IsA("Decal") or f:IsA("Texture") then
        f.Transparency = 0
    elseif f:IsA("ParticleEmitter") or f:IsA("Trail") then
        f.Lifetime = NumberRange.new(0)
    elseif f:IsA("Explosion") then
        f.BlastPressure = 0
        f.BlastRadius = 0
    elseif f:IsA("Fire") or f:IsA("SpotLight") or f:IsA("Smoke") or f:IsA("Sparkles") then
        f.Enabled = false
    elseif f:IsA("MeshPart") then
        f.Material = "Plastic"
        f.Reflectance = 0
        f.TextureID = 10385902758728957
    end
    end
    for e, g in pairs(c:GetChildren()) do
    if
        g:IsA("BlurEffect") or g:IsA("SunRaysEffect") or g:IsA("ColorCorrectionEffect") or g:IsA("BloomEffect") or
            g:IsA("DepthOfFieldEffect")
        then
        g.Enabled = false
    end
    end
    sethiddenproperty(game.Lighting, "Technology", "Compatibility")
end

local function peformance_2()

    local timeBegan = tick()
    for i,v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") then
        v.Material = "SmoothPlastic"
        end
    end
    for i,v in ipairs(game:GetService("Lighting"):GetChildren()) do
        v:Destroy()
    end
    local timeEnd = tick() - timeBegan
    local timeMS = math.floor(timeEnd*1000)
    print("SmoothFPS loaded successfully in " .. timeMS .. "ms")

end

local function peformance_3()

    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    
    local WindowFocusReleasedFunction = function()
        RunService:Set3dRenderingEnabled(false)
        return
    end
    
    local WindowFocusedFunction = function()
        RunService:Set3dRenderingEnabled(true)
        return
    end
    
    local Initialize = function()
        UserInputService.WindowFocusReleased:Connect(WindowFocusReleasedFunction)
        UserInputService.WindowFocused:Connect(WindowFocusedFunction)
        return
    end
    Initialize()

end

peformance_1()
peformance_2()
peformance_3()

while true do
	Workspace.placeFolders.entityManifestCollection:FindFirstChild("DannyTheConqueror"):FindFirstChild("hitbox").CFrame = CFrame.new(232.64415, -32.8644066, -347.427185, -0.691770136, 0, -0.722117782, 0, 1, 0, 0.722117782, 0, -0.691770136) 
end
