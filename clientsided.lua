print("[Tail Script] Execution started...")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

local config = {
    wagSpeed = 16,
    wagAmplitude = 0.4,
    toggleKey = Enum.KeyCode.F,
    debugEnabled = false,
    
    stiffness = 14.0,
    damping = 0.38,
    mass = 0.18,
    
    naturalSag = 0.05,       
    physicsWeight = 2.2,     
}

local state = {
    rotX = 0, rotY = 0, rotZ = 0,
    velX = 0, velY = 0, velZ = 0,
    
    lastRootCFrame = CFrame.new(),
    wagWeight = 0,
    wagEnabled = false,
    accessoryStatus = "Initializing...",
    isSimulating = false
}

local originalJointC0s = {}

local function findActiveCharacter()
    if player.Character then return player.Character end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and (obj.Name == player.Name or string.find(obj.Name, "^0x")) then
            if obj:FindFirstChild("HumanoidRootPart") then
                return obj
            end
        end
    end
    return nil
end

local function getTailAccessory(char)
    if not char then return nil end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Accessory") and string.find(string.lower(item.Name), "tail") then
            return item
        end
    end
    return nil
end

local function findAccessoryHandle(accessory)
    local standardHandle = accessory:FindFirstChild("Handle")
    if standardHandle and standardHandle:IsA("BasePart") then
        return standardHandle
    end
    for _, child in ipairs(accessory:GetChildren()) do
        if child:IsA("BasePart") then
            return child
        end
    end
    return nil
end

print("[Tail Script] Spawning directional rotational loop...")
RunService.RenderStepped:Connect(function(dt)
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    local char = findActiveCharacter()
    if not char then
        state.accessoryStatus = "No Character Found"
        state.isSimulating = false
        return
    end

    local accessory = getTailAccessory(char)
    if not accessory then
        state.accessoryStatus = "Missing (No Tail)"
        state.isSimulating = false
        return
    end

    local handle = findAccessoryHandle(accessory)
    if not handle then
        state.accessoryStatus = "No BasePart Found"
        state.isSimulating = false
        return
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp then
        state.accessoryStatus = "Missing RootPart"
        state.isSimulating = false
        return
    end

    local joint = handle:FindFirstChildOfClass("Weld") or handle:FindFirstChildOfClass("ManualWeld") or handle:FindFirstChildOfClass("Motor6D")
    if not joint or joint:IsA("WeldConstraint") then
        state.accessoryStatus = "Unsupported Joint Type"
        state.isSimulating = false
        return
    end

    if not originalJointC0s[joint] then
        originalJointC0s[joint] = joint.C0
        state.lastRootCFrame = hrp.CFrame
    end
    state.accessoryStatus = "Simulating"
    state.isSimulating = true

    local targetWagWeight = state.wagEnabled and 1 or 0
    state.wagWeight = state.wagWeight + (targetWagWeight - state.wagWeight) * (dt * 8)

    local currentCFrame = hrp.CFrame
    local rawVelocity = hrp.AssemblyLinearVelocity
    
    if rawVelocity.Magnitude < 0.5 and humanoid and humanoid.MoveDirection.Magnitude > 0 then
        rawVelocity = humanoid.MoveDirection * (humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16)
    end
    
    local localVelocity = currentCFrame:VectorToObjectSpace(rawVelocity)

    local relativeCFrame = state.lastRootCFrame:ToObjectSpace(currentCFrame)
    local axis, angle = relativeCFrame:ToAxisAngle()
    local angularVelocityY = (axis.Y * angle) / dt
    
    state.lastRootCFrame = currentCFrame

    -- Inverted localVelocity.X signs to handle proper counter-inertial strafing reaction forces
    local targetRotX = (math.abs(localVelocity.Z) * 0.03) + (math.abs(localVelocity.Y) * 0.04) - config.naturalSag
    local targetRotY = (localVelocity.X * 0.05) - (angularVelocityY * 0.22)
    local targetRotZ = (localVelocity.X * 0.02)

    targetRotX *= config.physicsWeight
    targetRotY *= config.physicsWeight
    targetRotZ *= config.physicsWeight

    targetRotX = math.clamp(targetRotX, -config.naturalSag, 0.85)
    targetRotY = math.clamp(targetRotY, -0.9, 0.9)
    targetRotZ = math.clamp(targetRotZ, -0.4, 0.4)

    local forceX = (targetRotX - state.rotX) * config.stiffness
    local forceY = (targetRotY - state.rotY) * config.stiffness
    local forceZ = (targetRotZ - state.rotZ) * config.stiffness

    state.velX = (state.velX + (forceX / config.mass) * dt) * (1 - config.damping)
    state.velY = (state.velY + (forceY / config.mass) * dt) * (1 - config.damping)
    state.velZ = (state.velZ + (forceZ / config.mass) * dt) * (1 - config.damping)

    state.rotX += state.velX * dt
    state.rotY += state.velY * dt
    state.rotZ += state.velZ * dt

    local activeWag = 0
    if state.wagWeight > 0.001 then
        activeWag = math.sin(os.clock() * config.wagSpeed) * (config.wagAmplitude * state.wagWeight)
    end

    pcall(function()
        local orig = originalJointC0s[joint] or CFrame.new()
        local transform = CFrame.Angles(0, state.rotY + activeWag, 0) 
                        * CFrame.Angles(state.rotX, 0, state.rotZ)
        joint.C0 = orig * transform
    end)
end)

print("[Tail Script] Constructing UI Elements...")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TailPhysicsController"
screenGui.ResetOnSpawn = false

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 95)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local textButton = Instance.new("TextButton")
textButton.Size = UDim2.new(1, 0, 0, 35)
textButton.BackgroundTransparency = 1
textButton.TextColor3 = Color3.fromRGB(255, 255, 255)
textButton.TextSize = 14
textButton.Font = Enum.Font.SourceSansBold
textButton.Text = "Tail Wag: OFF (F)"
textButton.Parent = frame

local debugButton = Instance.new("TextButton")
debugButton.Size = UDim2.new(1, 0, 0, 25)
debugButton.Position = UDim2.new(0, 0, 0, 35)
debugButton.BackgroundTransparency = 1
debugButton.TextColor3 = Color3.fromRGB(180, 180, 180)
debugButton.TextSize = 12
debugButton.Font = Enum.Font.SourceSans
debugButton.Text = "Toggle Debug Info"
debugButton.Parent = frame

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(1, -10, 0, 65)
debugLabel.Position = UDim2.new(0, 5, 0, 60)
debugLabel.BackgroundTransparency = 1
debugLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
debugLabel.TextSize = 10
debugLabel.Font = Enum.Font.Code
debugLabel.TextXAlignment = Enum.TextXAlignment.Left
debugLabel.TextWrapped = true
debugLabel.Visible = false
debugLabel.Parent = frame

textButton.MouseButton1Click:Connect(function()
    state.wagEnabled = not state.wagEnabled
end)

debugButton.MouseButton1Click:Connect(function()
    config.debugEnabled = not config.debugEnabled
    debugLabel.Visible = config.debugEnabled
    frame.Size = config.debugEnabled and UDim2.new(0, 200, 0, 155) or UDim2.new(0, 200, 0, 95)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == config.toggleKey then
        state.wagEnabled = not state.wagEnabled
    end
end)

task.spawn(function()
    while task.wait(0.05) do
        textButton.Text = "Tail Wag: " .. (state.wagEnabled and "ON" or "OFF") .. " (" .. config.toggleKey.Name .. ")"
        if config.debugEnabled then
            debugLabel.Text = string.format(
                "Status: %s\nRotVector: X:%.2f Y:%.2f Z:%.2f\nActive Loop: %s",
                state.accessoryStatus,
                state.rotX,
                state.rotY,
                state.rotZ,
                tostring(state.isSimulating)
            )
        end
    end
end)

local parentTarget = CoreGui:FindFirstChild("RobloxGui") or CoreGui or player:FindFirstChildOfClass("PlayerGui")
screenGui.Parent = parentTarget
print("[Tail Script] Execution completed successfully.")
