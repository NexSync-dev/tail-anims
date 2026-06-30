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
    isSetup = false,
    alignOri = nil,
    alignPos = nil,
    tailAttachment = nil,
    baseOffset = CFrame.new(),
    pivotOffset = CFrame.new(),
    handle = nil,
    anchorPart = nil,
    torso = nil,
}

local function getTailAccessory(char)
    if not char then return nil end
    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("Accessory") and string.find(string.lower(item.Name), "tail") then
            return item
        end
    end
    return nil
end

local function findTorso(char)
    if not char then return nil end
    local priority = {"LowerTorso", "Torso", "UpperTorso", "HumanoidRootPart"}
    local bestMatch = nil
    local bestIndex = 999
    
    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("BasePart") then
            for i, name in ipairs(priority) do
                if item.Name == name and i < bestIndex then
                    bestMatch = item
                    bestIndex = i
                    break
                end
            end
        end
    end
    return bestMatch
end

local function findCharacter()
    local char = player.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        return char
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Health > 0 then
            if obj.DisplayName == player.DisplayName or obj.Name == player.Name then
                local model = obj.Parent
                if model and model:IsA("Model") then
                    player.Character = model
                    return model
                end
            end
        end
    end
    return nil
end

local function buildRig(char, accessory, handle)
    state.handle = handle

    local torso = findTorso(char)
    if not torso then return end
    state.torso = torso

    local anchorPart = torso
    for _, joint in ipairs(handle:GetJoints()) do
        if joint:IsA("Weld") or joint:IsA("Motor6D") then
            if joint.Part0 == handle and joint.Part1 then
                anchorPart = joint.Part1
            elseif joint.Part1 == handle and joint.Part0 then
                anchorPart = joint.Part0
            end
            break
        end
    end
    state.anchorPart = anchorPart
    
    state.baseOffset = anchorPart.CFrame:ToObjectSpace(handle.CFrame)
    local att = handle:FindFirstChildWhichIsA("Attachment")
    state.pivotOffset = att and att.CFrame or CFrame.new()

    for _, joint in ipairs(handle:GetJoints()) do
        if joint:IsA("Weld") or joint:IsA("Motor6D") then
            joint:Destroy()
        end
    end

    for _, part in ipairs(accessory:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.Massless = true
        end
    end

    local tailAtt = handle:FindFirstChild("TailMover")
    if not tailAtt then
        tailAtt = Instance.new("Attachment")
        tailAtt.Name = "TailMover"
        tailAtt.Parent = handle
    end
    tailAtt.CFrame = CFrame.new()
    state.tailAttachment = tailAtt

    local alignPos = handle:FindFirstChild("TailPosAlign")
    if not alignPos then
        alignPos = Instance.new("AlignPosition")
        alignPos.Name = "TailPosAlign"
        alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
        alignPos.Attachment0 = tailAtt
        alignPos.MaxForce = 50000
        alignPos.Responsiveness = 200
        alignPos.RigidityEnabled = true
        alignPos.ReactionForceEnabled = false
        alignPos.Parent = handle
    end
    state.alignPos = alignPos

    local alignOri = handle:FindFirstChild("TailOriAlign")
    if not alignOri then
        alignOri = Instance.new("AlignOrientation")
        alignOri.Name = "TailOriAlign"
        alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
        alignOri.Attachment0 = tailAtt
        alignOri.MaxTorque = 50000
        alignOri.Responsiveness = 200
        alignOri.RigidityEnabled = true
        alignOri.ReactionTorqueEnabled = false
        alignOri.Parent = handle
    end
    state.alignOri = alignOri

    state.lastRootCFrame = torso.CFrame
    state.isSetup = true
end

local function huntForTail()
    state.isSetup = false
    state.alignOri = nil
    state.alignPos = nil
    
    task.spawn(function()
        while not state.isSetup and task.wait(0.5) do
            local char = findCharacter()
            if not char then continue end
            
            local accessory = getTailAccessory(char)
            if not accessory then continue end
            
            local handle = accessory:FindFirstChild("Handle")
            if not handle or not handle:IsA("BasePart") then continue end
            
            local hasWeld = false
            for _, joint in ipairs(handle:GetJoints()) do
                if joint:IsA("Weld") or joint:IsA("Motor6D") then
                    hasWeld = true
                    break
                end
            end
            
            if hasWeld then
                buildRig(char, accessory, handle)
                return
            end
        end
    end)
end

huntForTail()
player.CharacterAdded:Connect(function()
    huntForTail()
end)

RunService.Heartbeat:Connect(function(dt)
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    if not state.isSetup or not state.alignOri or not state.alignOri.Parent then
        if state.isSetup then huntForTail() end
        return
    end

    local anchorPart = state.anchorPart
    local torso = state.torso
    if not anchorPart or not anchorPart.Parent or not torso or not torso.Parent then return end

    local currentPos = state.handle.Position
    local safeTargetPos = (anchorPart.CFrame * state.baseOffset).Position
    local dist = (currentPos - safeTargetPos).Magnitude

    if dist > 15 then
        state.handle:PivotTo(anchorPart.CFrame * state.baseOffset)
        state.handle.AssemblyLinearVelocity = Vector3.zero
        state.handle.AssemblyAngularVelocity = Vector3.zero
    elseif dist > 3 then
        state.handle.AssemblyLinearVelocity = Vector3.zero
        state.handle.AssemblyAngularVelocity = Vector3.zero
    end
    
    pcall(function()
        state.handle:SetNetworkOwner(player)
    end)

    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    local targetWagWeight = state.wagEnabled and 1 or 0
    state.wagWeight = state.wagWeight + (targetWagWeight - state.wagWeight) * math.min(dt * 12, 1)

    local anchorCF = anchorPart.CFrame
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

    local primaryWag = 0
    local secondaryWag = 0
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

    local originalWorldCF = anchorCF * state.baseOffset
    local pivotWorldCF = originalWorldCF * state.pivotOffset
    local targetWorldCF = pivotWorldCF * localTransform * state.pivotOffset:Inverse()

    state.alignPos.Position = targetWorldCF.Position
    state.alignOri.CFrame = targetWorldCF
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
