local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local config = {
    wagSpeed = 16,                 
    wagAmplitude = 0.4,             
    wagSecondaryAmplitude = 0.15,   
    wagVerticalBounce = 0.08,       
    toggleKey = Enum.KeyCode.F,


    stiffness = 120,               
    damping = 18,                   
    naturalSag = 0.04,             
    

    velocityPitch = 0.01,          
    velocityYaw = 0.03,            
    velocityRoll = 0.015,          
    turnYaw = 0.15,                
    turnRoll = 0.03,               

    velocityWagBoost = 0.4,
}

local state = {
    rotX = 0, rotY = 0, rotZ = 0,
    velX = 0, velY = 0, velZ = 0,
    lastRootCFrame = CFrame.new(),
    wagWeight = 0,
    wagEnabled = false,
    

    weld = nil,
    originalC0 = CFrame.new(),
    originalC1 = CFrame.new(),
    modifyC0 = false, 
    
    handle = nil,
    torso = nil,
}

local function getTailAccessory(char)
    if not char then return nil end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Accessory") and string.find(string.lower(item.Name), "tail") then
            return item
        end
    end
    return nil
end

local function isBodyPart(part)
    if not part then return false end
    local bodyParts = {
        "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso",
        "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
        "LeftHand", "RightHand", "LeftFoot", "RightFoot",
        "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
        "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"
    }
    for _, name in ipairs(bodyParts) do
        if part.Name == name then return true end
    end
    return false
end

local function setupTail(char)
    -- Reset all state
    state.weld = nil
    state.rotX, state.rotY, state.rotZ = 0, 0, 0
    state.velX, state.velY, state.velZ = 0, 0, 0
    state.wagWeight = 0

    -- Wait for character to be fully loaded
    if not char:FindFirstChild("HumanoidRootPart") then
        char:WaitForChild("HumanoidRootPart", 5)
    end

    -- Wait for the tail accessory to load
    local accessory = nil
    local timeout = 0
    while not accessory and timeout < 10 do
        accessory = getTailAccessory(char)
        task.wait(0.1)
        timeout += 0.1
    end

    if not accessory then
        warn("[Tail Script] No tail accessory found!")
        return
    end

    local handle = accessory:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then
        warn("[Tail Script] No Handle found!")
        return
    end

    state.handle = handle

    local torso = char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    if not torso then return end
    state.torso = torso

    local foundWeld = nil
    for _, joint in ipairs(handle:GetJoints()) do
        if joint:IsA("Weld") or joint:IsA("Motor6D") then
            foundWeld = joint
            break
        end
    end

    if not foundWeld then
        warn("[Tail Script] No existing weld found on tail!")
        return
    end


    state.weld = foundWeld
    state.originalC0 = foundWeld.C0
    state.originalC1 = foundWeld.C1

    if isBodyPart(foundWeld.Part0) then
        state.modifyC0 = false 
    else
        state.modifyC0 = true 
    end


    handle.CanCollide = false
    handle.Massless = true
    handle.CanTouch = false

    for _, part in ipairs(accessory:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Massless = true
            part.CanTouch = false
        end
    end

    state.lastRootCFrame = torso.CFrame

    print("[Tail Script v8] Hooked into existing weld!")
    print("  Part0:", foundWeld.Part0 and foundWeld.Part0.Name or "nil")
    print("  Part1:", foundWeld.Part1 and foundWeld.Part1.Name or "nil")
    print("  Modifying:", state.modifyC0 and "C0" or "C1")
end


if player.Character then
    task.spawn(function() setupTail(player.Character) end)
end

player.CharacterAdded:Connect(function(char)
    task.spawn(function() setupTail(char) end)
end)

RunService.Heartbeat:Connect(function(dt)
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    -- If weld doesn't exist, bail out
    if not state.weld or not state.weld.Parent then
        state.weld = nil
        return
    end

    local char = player.Character
    if not char then return end

    local torso = state.torso
    if not torso or not torso.Parent then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")


    local targetWagWeight = state.wagEnabled and 1 or 0
    state.wagWeight = state.wagWeight + (targetWagWeight - state.wagWeight) * math.min(dt * 12, 1)

    local currentCFrame = torso.CFrame
    local linearVelocity = torso.AssemblyLinearVelocity


    if linearVelocity.Magnitude < 0.5 and humanoid and humanoid.MoveDirection.Magnitude > 0 then
        linearVelocity = humanoid.MoveDirection * (humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16)
    end

    local localVelocity = currentCFrame:VectorToObjectSpace(linearVelocity)
    local speed = linearVelocity.Magnitude


    local relativeCFrame = state.lastRootCFrame:ToObjectSpace(currentCFrame)
    local axis, angle = relativeCFrame:ToAxisAngle()
    local angularVelocityY = (axis.Y * angle) / dt

    state.lastRootCFrame = currentCFrame

    local targetRotX = (localVelocity.Y * -config.velocityPitch) - config.naturalSag
    local targetRotY = (localVelocity.X * config.velocityYaw) - (angularVelocityY * config.turnYaw)
    local targetRotZ = (localVelocity.X * config.velocityRoll) + (angularVelocityY * config.turnRoll)


    targetRotX = math.clamp(targetRotX, -0.6, 0.6)
    targetRotY = math.clamp(targetRotY, -0.7, 0.7)
    targetRotZ = math.clamp(targetRotZ, -0.4, 0.4)


    local forceX = (targetRotX - state.rotX) * config.stiffness - state.velX * config.damping
    state.velX = state.velX + forceX * dt
    state.rotX = state.rotX + state.velX * dt

    local forceY = (targetRotY - state.rotY) * config.stiffness - state.velY * config.damping
    state.velY = state.velY + forceY * dt
    state.rotY = state.rotY + state.velY * dt

    local forceZ = (targetRotZ - state.rotZ) * config.stiffness - state.velZ * config.damping
    state.velZ = state.velZ + forceZ * dt
    state.rotZ = state.rotZ + state.velZ * dt


    if state.rotX ~= state.rotX or math.abs(state.rotX) > 10 then state.rotX = 0; state.velX = 0 end
    if state.rotY ~= state.rotY or math.abs(state.rotY) > 10 then state.rotY = 0; state.velY = 0 end
    if state.rotZ ~= state.rotZ or math.abs(state.rotZ) > 10 then state.rotZ = 0; state.velZ = 0 end

    local primaryWag     = 0
    local secondaryWag   = 0
    local verticalBounce = 0

    if state.wagWeight > 0.001 then
        local t = os.clock()
        local intensityMult = 1 + math.clamp(speed / 30, 0, 1) * config.velocityWagBoost

        primaryWag = math.sin(t * config.wagSpeed) *
                     config.wagAmplitude * state.wagWeight * intensityMult

        secondaryWag = math.sin(t * config.wagSpeed * 2 + 0.6) *
                       config.wagSecondaryAmplitude * state.wagWeight * intensityMult

        verticalBounce = math.abs(math.sin(t * config.wagSpeed)) *
                         config.wagVerticalBounce * state.wagWeight
    end

    local localTransform = CFrame.Angles(state.rotX - verticalBounce, 0, 0)
                         * CFrame.Angles(0, state.rotY + primaryWag, 0)
                         * CFrame.Angles(0, 0, state.rotZ + secondaryWag)
    if state.modifyC0 then
        state.weld.C0 = state.originalC0 * localTransform
    else
        state.weld.C1 = state.originalC1 * localTransform
    end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TailPhysicsController"
screenGui.ResetOnSpawn = false

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 60)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local textButton = Instance.new("TextButton")
textButton.Size = UDim2.new(1, 0, 1, 0)
textButton.BackgroundTransparency = 1
textButton.TextColor3 = Color3.fromRGB(255, 255, 255)
textButton.TextSize = 14
textButton.Font = Enum.Font.SourceSansBold
textButton.Text = "Tail Wag: OFF (F)"
textButton.Parent = frame

local function refreshButtonText()
    textButton.Text = "Tail Wag: " .. (state.wagEnabled and "ON" or "OFF") .. " (" .. config.toggleKey.Name .. ")"
end

textButton.MouseButton1Click:Connect(function()
    state.wagEnabled = not state.wagEnabled
    refreshButtonText()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == config.toggleKey then
        state.wagEnabled = not state.wagEnabled
        refreshButtonText()
    end
end)

local parentTarget = CoreGui:FindFirstChild("RobloxGui") or CoreGui or player:FindFirstChildOfClass("PlayerGui")
screenGui.Parent = parentTarget

print("[Tail Script v8] Execution completed successfully.")
