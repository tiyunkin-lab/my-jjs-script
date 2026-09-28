--// SPIRO TARGET
--// R15
--// ФИНАЛЬНАЯ ВЕРСИЯ (30 итерация: фиксы вылетов Xeno + критические баги)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- VirtualInputManager берём через pcall, чтобы скрипт не падал, если сервис недоступен
local VirtualInputManager = nil
pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

if not VirtualInputManager then
	warn("[PIANO] VirtualInputManager недоступен. Пианино не будет работать, но меню загрузится.")
end

local LocalPlayer = Players.LocalPlayer

--==================================================
-- FORWARD DECLARATIONS
--==================================================

local ToggleFreecam
local ToggleSpectate
local StartSpiroCamera
local StopSpiroCamera
local StartFly
local StopFly
local StopSpiro
local StopSpectate
local DisableTargetBecauseDead
local UpdateHelpLabel
local SpiroButton, FlyButton, ESPButton, FreecamButton, SpectateButton, PianoButton
local StatusLabel, HelpLabel
local PianoNotesBox

--==================================================
-- ФЛАГИ
--==================================================

local SpiroEnabled = false
local FlyEnabled = false
local ESPEnabled = false
local SpectateEnabled = false
local FreecamEnabled = false
local PianoPlaying = false

--==================================================
-- НАСТРОЙКИ
--==================================================

local APPROACH_SPEED = 100
local ORBIT_SPEED = 150
local TARGET_DISTANCE = 6

local FLY_SPEED = 150

local HEALTH_UPDATE_RATE = 0.1
local FRIEND_CACHE_TTL = 30

local FREECAM_SPEED = 100
local FREECAM_ROTATION = 1.0
local FREECAM_BOOST = 3
local FREECAM_SENSITIVITY = 0.0025

local SPECTATE_DISTANCE = 10
local SPECTATE_HEIGHT_OFFSET = 2
local SPECTATE_SENSITIVITY = 0.005
local SPECTATE_LERP = 0.25

local SPIRO_CAM_DISTANCE = 12
local SPIRO_CAM_HEIGHT_OFFSET = 1.5
local SPIRO_CAM_SENSITIVITY = 0.005
local SPIRO_CAM_LERP = 0.3

local CAM_ZOOM_SPEED = 2

-- PIANO
local PIANO_BASE_DURATION = 0.05
local PIANO_NOTES = ""

local MOVEMENT_UPDATE_RATE = 30

local SPIRO_KEY = Enum.KeyCode.Z
local FLY_KEY = Enum.KeyCode.X
local ESP_KEY = Enum.KeyCode.C
local MENU_KEY = Enum.KeyCode.RightShift
local FREECAM_KEY = Enum.KeyCode.B
local SPECTATE_KEY = Enum.KeyCode.V
local PIANO_KEY = Enum.KeyCode.F1

local FULL_MENU_HEIGHT = 600
local COLLAPSED_MENU_HEIGHT = 45

--==================================================
-- АНИМАЦИИ
--==================================================

local ANIM = {
	MenuOpen = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	MenuClose = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
	SectionOpen = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	SectionClose = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Arrow = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pulse = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

--==================================================
-- ПЕРЕМЕННЫЕ
--==================================================

local Character
local Humanoid
local RootPart

local TargetPlayer = nil

local FlyLinearVelocity = nil
local FlyAlignOrientation = nil
local FlyAttachment = nil

local ESPHighlights = {}
local ESPNameTags = {}
local ESPPlayerConnections = {}
local ESPGlobalConnections = {}
local FriendCache = {}
local FriendCacheTimestamp = 0

local TargetCharacterConnection = nil
local TargetHumanoidConnection = nil
local LocalHumanoidConnection = nil

local CurrentPoint = 1
local MovementAccumulator = 0
local HealthAccumulator = 0

local WaitingForKey = nil
local KeybindButtons = {}

local MenuCollapsed = true
local MenuTweening = false
local DeadHandled = false

local SpectateYaw = 0
local SpectatePitch = 0
local SpectateDistance = 10
local SpectateOldCameraType = nil
local SpectateOldCameraSubject = nil
local SpectateOldMouseBehavior = nil
local SpectateOldMouseIconEnabled = nil
local SpectateCurrentPos = nil

local SpiroCamYaw = 0
local SpiroCamPitch = 0
local SpiroCamDistance = 12
local SpiroCamOldCameraType = nil
local SpiroCamOldCameraSubject = nil
local SpiroCamOldMouseBehavior = nil
local SpiroCamOldMouseIconEnabled = nil
local SpiroCamCurrentPos = nil

local FreecamCFrame = nil
local FreecamYaw = 0
local FreecamPitch = 0
local FreecamOldCameraType = nil
local FreecamOldCameraSubject = nil
local FreecamOldMouseBehavior = nil
local FreecamOldMouseIconEnabled = nil

local FreecamWasSpiroEnabled = false
local FreecamWasFlyEnabled = false
local FreecamRootWasAnchored = false
local FreecamOldWalkSpeed = 16
local FreecamOldJumpPower = 50
local FreecamOldJumpHeight = 7.2

-- PIANO SLOTS
local PIANO_SLOTS = {"", "", "", ""}
local CURRENT_SLOT = 1

--==================================================
-- ПЕРСОНАЖ
--==================================================

local function SetupCharacter(NewCharacter)

	Character = NewCharacter

	if LocalHumanoidConnection then
		LocalHumanoidConnection:Disconnect()
		LocalHumanoidConnection = nil
	end

	if SpectateEnabled and StopSpectate then StopSpectate() end
	if FreecamEnabled and ToggleFreecam then ToggleFreecam() end
	if SpiroCamOldCameraType and StopSpiroCamera then StopSpiroCamera() end

	Humanoid = Character:WaitForChild("Humanoid", 5)
	RootPart = Character:WaitForChild("HumanoidRootPart", 5)

	if not Humanoid or not RootPart then
		warn("[SPIRO] Не удалось найти Humanoid или HumanoidRootPart")
		Humanoid = nil
		RootPart = nil
		return
	end

	SpiroEnabled = false
	FlyEnabled = false
	DeadHandled = false

	if FlyLinearVelocity then FlyLinearVelocity:Destroy() FlyLinearVelocity = nil end
	if FlyAlignOrientation then FlyAlignOrientation:Destroy() FlyAlignOrientation = nil end
	if FlyAttachment then FlyAttachment:Destroy() FlyAttachment = nil end

	Humanoid.PlatformStand = false
	Humanoid.AutoRotate = true

	if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
	if FlyButton then FlyButton.Text = "FLY: OFF" end
	if SpectateButton then SpectateButton.Text = "SPECTATE: OFF" end
	if FreecamButton then FreecamButton.Text = "FREECAM: OFF" end

	LocalHumanoidConnection = Humanoid.Died:Connect(function()
		if StopFly then StopFly() end
		if StopSpiro then StopSpiro() end
		if StopSpectate then StopSpectate() end
		if FreecamEnabled and ToggleFreecam then ToggleFreecam() end

		if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
		if FlyButton then FlyButton.Text = "FLY: OFF" end
		if StatusLabel then StatusLabel.Text = "Вы умерли" end
	end)
end

if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(NewCharacter) SetupCharacter(NewCharacter) end)

--==================================================
-- STOP SPIRO
--==================================================

StopSpiro = function()
	if SpiroEnabled then SpiroEnabled = false end
	if SpiroCamOldCameraType and StopSpiroCamera then StopSpiroCamera() end
	CurrentPoint = 1
	MovementAccumulator = 0
	if Humanoid then Humanoid.AutoRotate = true end
	if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
end

--==================================================
-- TARGET ROOT
--==================================================

local function GetTargetRoot()
	if not TargetPlayer then return nil end
	local TargetCharacter = TargetPlayer.Character
	if not TargetCharacter then return nil end
	local TargetHumanoid = TargetCharacter:FindFirstChildOfClass("Humanoid")
	local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart")
	if not TargetHumanoid or not TargetRoot then return nil end
	if TargetHumanoid.Health <= 0 then return nil end
	return TargetRoot
end

--==================================================
-- GUI
--==================================================

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local OldGui = PlayerGui:FindFirstChild("SpiroTargetGUI")
if OldGui then OldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpiroTargetGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

--==================================================
-- MAIN FRAME
--==================================================

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Size = UDim2.new(0, 420, 0, COLLAPSED_MENU_HEIGHT)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

--==================================================
-- TITLE BAR
--==================================================

local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 45)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "KILL AURA + PIANO"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

--==================================================
-- КНОПКА СВОРАЧИВАНИЯ
--==================================================

local HideButton = Instance.new("TextButton")
HideButton.Name = "CollapseButton"
HideButton.Size = UDim2.new(0, 35, 0, 35)
HideButton.Position = UDim2.new(1, -40, 0, 5)
HideButton.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
HideButton.Text = "+"
HideButton.TextColor3 = Color3.fromRGB(255, 255, 255)
HideButton.TextSize = 22
HideButton.Font = Enum.Font.GothamBold
HideButton.Parent = TitleBar

local HideCorner = Instance.new("UICorner")
HideCorner.CornerRadius = UDim.new(0, 8)
HideCorner.Parent = HideButton

HideButton.MouseEnter:Connect(function()
	TweenService:Create(HideButton, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(75, 75, 90) }):Play()
end)

HideButton.MouseLeave:Connect(function()
	TweenService:Create(HideButton, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(55, 55, 65) }):Play()
end)

--==================================================
-- DRAG
--==================================================

local Dragging = false
local DragStart = nil
local StartPosition = nil
local DragInput = nil

local function UpdateDrag(Input)
	if not Dragging then return end
	if not DragStart or not StartPosition then return end
	local Delta = Input.Position - DragStart
	MainFrame.Position = UDim2.new(
		StartPosition.X.Scale,
		StartPosition.X.Offset + Delta.X,
		StartPosition.Y.Scale,
		StartPosition.Y.Offset + Delta.Y
	)
end

TitleBar.InputBegan:Connect(function(Input)
	if UserInputService:GetFocusedTextBox() then return end
	if Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch then
		Dragging = true
		DragStart = Input.Position
		StartPosition = MainFrame.Position
		DragInput = Input
	end
end)

TitleBar.InputChanged:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseMovement
		or Input.UserInputType == Enum.UserInputType.Touch then
		DragInput = Input
	end
end)

UserInputService.InputChanged:Connect(function(Input)
	if Input == DragInput then UpdateDrag(Input) end
end)

UserInputService.InputEnded:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch then
		Dragging = false
		DragInput = nil
	end
end)

--==================================================
-- CONTENT
--==================================================

local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, 0, 1, -45)
Content.Position = UDim2.new(0, 0, 0, 45)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 5
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.CanvasSize = UDim2.new(0, 0, 0, 0)
Content.Visible = false
Content.Parent = MainFrame

local ContentPadding = Instance.new("UIPadding")
ContentPadding.PaddingTop = UDim.new(0, 10)
ContentPadding.PaddingBottom = UDim.new(0, 10)
ContentPadding.PaddingLeft = UDim.new(0, 10)
ContentPadding.PaddingRight = UDim.new(0, 10)
ContentPadding.Parent = Content

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 8)
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Parent = Content

--==================================================
-- БАЗОВЫЕ ЭЛЕМЕНТЫ
--==================================================

local function CreateCorner(ParentObject, Radius)
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, Radius or 8)
	Corner.Parent = ParentObject
	return Corner
end

local function CreateButton(Text, Height, ParentOverride)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, Height or 40)
	Button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Text = Text
	Button.TextSize = 14
	Button.Font = Enum.Font.GothamSemibold
	Button.AutoButtonColor = false
	Button.Parent = ParentOverride or Content

	CreateCorner(Button, 8)

	Button.MouseEnter:Connect(function()
		TweenService:Create(Button, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(58, 58, 72) }):Play()
	end)

	Button.MouseLeave:Connect(function()
		TweenService:Create(Button, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(45, 45, 55) }):Play()
	end)

	return Button
end

--==================================================
-- СВОРАЧИВАЕМАЯ СЕКЦИЯ
--==================================================

local Sections = {}

local function CreateSection(TitleText, DefaultOpen)
	local Section = {}

	local Container = Instance.new("Frame")
	Container.Name = "SectionContainer"
	Container.Size = UDim2.new(1, 0, 0, 38)
	Container.BackgroundTransparency = 1
	Container.ClipsDescendants = false
	Container.Parent = Content

	local ContainerLayout = Instance.new("UIListLayout")
	ContainerLayout.Padding = UDim.new(0, 0)
	ContainerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ContainerLayout.Parent = Container

	local Header = Instance.new("TextButton")
	Header.Name = "SectionHeader"
	Header.Size = UDim2.new(1, 0, 0, 38)
	Header.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	Header.Text = ""
	Header.TextColor3 = Color3.fromRGB(255, 255, 255)
	Header.TextSize = 14
	Header.Font = Enum.Font.GothamBold
	Header.TextXAlignment = Enum.TextXAlignment.Left
	Header.AutoButtonColor = false
	Header.LayoutOrder = 1
	Header.Parent = Container

	CreateCorner(Header, 8)

	local Arrow = Instance.new("TextLabel")
	Arrow.Name = "Arrow"
	Arrow.Size = UDim2.new(0, 20, 0, 38)
	Arrow.Position = UDim2.new(0, 10, 0, 0)
	Arrow.BackgroundTransparency = 1
	Arrow.Text = "▶"
	Arrow.TextColor3 = Color3.fromRGB(120, 180, 255)
	Arrow.TextSize = 14
	Arrow.Font = Enum.Font.GothamBold
	Arrow.TextXAlignment = Enum.TextXAlignment.Left
	Arrow.TextYAlignment = Enum.TextYAlignment.Center
	Arrow.Parent = Header

	local TitleLabel = Instance.new("TextLabel")
	TitleLabel.Name = "TitleLabel"
	TitleLabel.Size = UDim2.new(1, -40, 1, 0)
	TitleLabel.Position = UDim2.new(0, 34, 0, 0)
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Text = TitleText
	TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TitleLabel.TextSize = 14
	TitleLabel.Font = Enum.Font.GothamBold
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.Parent = Header

	local Body = Instance.new("Frame")
	Body.Name = "SectionBody"
	Body.Size = UDim2.new(1, 0, 0, 0)
	Body.AutomaticSize = Enum.AutomaticSize.Y
	Body.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	Body.BorderSizePixel = 0
	Body.LayoutOrder = 2
	Body.Visible = false
	Body.Parent = Container

	CreateCorner(Body, 8)

	local BodyPadding = Instance.new("UIPadding")
	BodyPadding.PaddingTop = UDim.new(0, 8)
	BodyPadding.PaddingBottom = UDim.new(0, 8)
	BodyPadding.PaddingLeft = UDim.new(0, 8)
	BodyPadding.PaddingRight = UDim.new(0, 8)
	BodyPadding.Parent = Body

	local BodyLayout = Instance.new("UIListLayout")
	BodyLayout.Padding = UDim.new(0, 6)
	BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	BodyLayout.Parent = Body

	Section.Container = Container
	Section.Header = Header
	Section.Arrow = Arrow
	Section.Body = Body
	Section.Open = false
	Section.Title = TitleText
	Section.Tweening = false

	local function UpdateArrow(Target, Instant)
		local Rotation = Target and 90 or 0
		if Instant then Arrow.Rotation = Rotation
		else TweenService:Create(Arrow, ANIM.Arrow, { Rotation = Rotation }):Play() end
	end

	local function OpenSection()
		if Section.Tweening or Section.Open then return end
		Section.Tweening = true
		Section.Open = true
		Body.Visible = true

		task.spawn(function()
			RunService.Heartbeat:Wait()
			local BodyHeight = Body.AbsoluteSize.Y
			local FinalHeight = 38 + BodyHeight
			Container.ClipsDescendants = true

			local Tween = TweenService:Create(Container, ANIM.SectionOpen, {
				Size = UDim2.new(1, 0, 0, FinalHeight),
			})
			Tween:Play()
			UpdateArrow(true, false)

			Tween.Completed:Connect(function()
				Container.ClipsDescendants = false
				Section.Tweening = false
			end)
		end)
	end

	local function CloseSection()
		if Section.Tweening or not Section.Open then return end
		Section.Tweening = true
		Section.Open = false
		Container.ClipsDescendants = true

		local Tween = TweenService:Create(Container, ANIM.SectionClose, {
			Size = UDim2.new(1, 0, 0, 38),
		})
		Tween:Play()
		UpdateArrow(false, false)

		Tween.Completed:Connect(function()
			Body.Visible = false
			Container.ClipsDescendants = false
			Section.Tweening = false
		end)
	end

	Header.MouseButton1Click:Connect(function()
		if Section.Open then CloseSection() else OpenSection() end
	end)

	Header.MouseEnter:Connect(function()
		TweenService:Create(Header, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(52, 52, 66) }):Play()
	end)

	Header.MouseLeave:Connect(function()
		TweenService:Create(Header, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(40, 40, 50) }):Play()
	end)

	if DefaultOpen then
		Body.Visible = true
		Section.Open = true
		UpdateArrow(true, true)

		task.spawn(function()
			RunService.Heartbeat:Wait()
			local BodyHeight = Body.AbsoluteSize.Y
			Container.Size = UDim2.new(1, 0, 0, 38 + BodyHeight)
		end)
	end

	table.insert(Sections, Section)
	return Section
end

--==================================================
-- ПОДЗАГОЛОВОК
--==================================================

local function CreateSubHeader(Text, Parent)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 26)
	Label.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
	Label.Text = "  " .. Text
	Label.TextColor3 = Color3.fromRGB(120, 180, 255)
	Label.TextSize = 12
	Label.Font = Enum.Font.GothamBold
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Parent
	CreateCorner(Label, 6)
	return Label
end

--==================================================
-- STATUS
--==================================================

StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 45)
StatusLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
StatusLabel.Text = "Цель: не выбрана"
StatusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
StatusLabel.TextSize = 14
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Parent = Content

CreateCorner(StatusLabel, 8)

--==================================================
-- СЕКЦИЯ: УПРАВЛЕНИЕ
--==================================================

local ControlSection = CreateSection("УПРАВЛЕНИЕ", false)

SpiroButton = CreateButton("SPIRO: OFF", 42, ControlSection.Body)
FlyButton = CreateButton("FLY: OFF", 42, ControlSection.Body)
ESPButton = CreateButton("ESP: OFF", 42, ControlSection.Body)
FreecamButton = CreateButton("FREECAM: OFF", 42, ControlSection.Body)
SpectateButton = CreateButton("SPECTATE: OFF", 42, ControlSection.Body)
PianoButton = CreateButton("PIANO: STOP", 42, ControlSection.Body)

HelpLabel = Instance.new("TextLabel")
HelpLabel.Size = UDim2.new(1, 0, 0, 130)
HelpLabel.BackgroundColor3 = Color3.fromRGB(32, 32, 39)
HelpLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
HelpLabel.TextSize = 13
HelpLabel.Font = Enum.Font.Gotham
HelpLabel.TextWrapped = true
HelpLabel.TextXAlignment = Enum.TextXAlignment.Left
HelpLabel.Parent = ControlSection.Body

CreateCorner(HelpLabel, 8)

--==================================================
-- СЕКЦИЯ: НАСТРОЙКИ
--==================================================

local SettingsSection = CreateSection("НАСТРОЙКИ", false)

local function CreateSetting(Name, DefaultValue, Callback, ParentOverride)
	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 40)
	Holder.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	Holder.Parent = ParentOverride or SettingsSection.Body
	CreateCorner(Holder, 8)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.55, 0, 1, 0)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = Name
	Label.TextColor3 = Color3.fromRGB(220, 220, 220)
	Label.TextSize = 13
	Label.Font = Enum.Font.Gotham
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(0.35, 0, 0, 28)
	Box.Position = UDim2.new(0.62, 0, 0.5, -14)
	Box.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	Box.TextColor3 = Color3.fromRGB(255, 255, 255)
	Box.Text = tostring(DefaultValue)
	Box.TextSize = 13
	Box.Font = Enum.Font.Gotham
	Box.ClearTextOnFocus = false
	Box.Parent = Holder

	CreateCorner(Box, 6)

	Box.FocusLost:Connect(function()
		local Number = tonumber(Box.Text)
		if Number then Callback(Number)
		else Box.Text = tostring(DefaultValue) end
	end)

	return Box
end

CreateSubHeader("SPIRO", SettingsSection.Body)
CreateSetting("Скорость подхода", APPROACH_SPEED, function(Value) APPROACH_SPEED = math.clamp(Value, 1, 500) end)
CreateSetting("Скорость треугольника", ORBIT_SPEED, function(Value) ORBIT_SPEED = math.clamp(Value, 1, 500) end)
CreateSetting("Расстояние", TARGET_DISTANCE, function(Value) TARGET_DISTANCE = math.clamp(Value, 2, 100) end)

CreateSubHeader("FLY", SettingsSection.Body)
CreateSetting("Скорость полёта", FLY_SPEED, function(Value) FLY_SPEED = math.clamp(Value, 1, 500) end)

CreateSubHeader("ESP", SettingsSection.Body)
CreateSetting("Обновление HP (сек)", HEALTH_UPDATE_RATE, function(Value)
	HEALTH_UPDATE_RATE = math.clamp(Value, 0.02, 1)
	HealthAccumulator = 0
end)
CreateSetting("TTL кэша друзей (сек)", FRIEND_CACHE_TTL, function(Value) FRIEND_CACHE_TTL = math.clamp(Value, 5, 300) end)

CreateSubHeader("FREECAM", SettingsSection.Body)
CreateSetting("Скорость камеры", FREECAM_SPEED, function(Value) FREECAM_SPEED = math.clamp(Value, 1, 1000) end)
CreateSetting("Скорость поворота", FREECAM_ROTATION, function(Value) FREECAM_ROTATION = math.clamp(Value, 0.1, 10) end)
CreateSetting("Ускорение (Ctrl)", FREECAM_BOOST, function(Value) FREECAM_BOOST = math.clamp(Value, 1, 20) end)

CreateSubHeader("SPECTATE", SettingsSection.Body)
CreateSetting("Дистанция от цели", SPECTATE_DISTANCE, function(Value)
	SPECTATE_DISTANCE = math.clamp(Value, 2, 50)
	SpectateDistance = SPECTATE_DISTANCE
end)
CreateSetting("Высота", SPECTATE_HEIGHT_OFFSET, function(Value) SPECTATE_HEIGHT_OFFSET = math.clamp(Value, -20, 20) end)
CreateSetting("Скорость поворота", SPECTATE_SENSITIVITY * 1000, function(Value) SPECTATE_SENSITIVITY = math.clamp(Value / 1000, 0.001, 0.05) end)
CreateSetting("Плавность (0-1)", SPECTATE_LERP, function(Value) SPECTATE_LERP = math.clamp(Value, 0.02, 1) end)

CreateSubHeader("SPIRO CAM", SettingsSection.Body)
CreateSetting("Дистанция", SPIRO_CAM_DISTANCE, function(Value)
	SPIRO_CAM_DISTANCE = math.clamp(Value, 2, 50)
	SpiroCamDistance = SPIRO_CAM_DISTANCE
end)
CreateSetting("Высота", SPIRO_CAM_HEIGHT_OFFSET, function(Value) SPIRO_CAM_HEIGHT_OFFSET = math.clamp(Value, -20, 20) end)
CreateSetting("Скорость поворота", SPIRO_CAM_SENSITIVITY * 1000, function(Value) SPIRO_CAM_SENSITIVITY = math.clamp(Value / 1000, 0.001, 0.05) end)
CreateSetting("Плавность (0-1)", SPIRO_CAM_LERP, function(Value) SPIRO_CAM_LERP = math.clamp(Value, 0.02, 1) end)

CreateSubHeader("PIANO", SettingsSection.Body)
CreateSetting("Базовая нота (сек)", PIANO_BASE_DURATION, function(Value)
	PIANO_BASE_DURATION = math.clamp(Value, 0.01, 0.5)
end)

--==================================================
-- СЕКЦИЯ: PIANO (закрыта по умолчанию)
--==================================================

local PianoSection = CreateSection("PIANO (4 СЛОТА)", false)

local SlotButtons = {}

local SlotsRow = Instance.new("Frame")
SlotsRow.Size = UDim2.new(1, 0, 0, 36)
SlotsRow.BackgroundTransparency = 1
SlotsRow.Parent = PianoSection.Body

local SlotsLayout = Instance.new("UIListLayout")
SlotsLayout.FillDirection = Enum.FillDirection.Horizontal
SlotsLayout.Padding = UDim.new(0, 4)
SlotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
SlotsLayout.Parent = SlotsRow

for i = 1, 4 do
	local Btn = Instance.new("TextButton")
	Btn.Name = "Slot" .. i
	Btn.Size = UDim2.new(0.24, 0, 1, 0)
	Btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	Btn.Text = "Слот " .. i
	Btn.TextSize = 13
	Btn.Font = Enum.Font.GothamSemibold
	Btn.AutoButtonColor = false
	Btn.LayoutOrder = i
	Btn.Parent = SlotsRow
	CreateCorner(Btn, 6)

	Btn.MouseEnter:Connect(function()
		TweenService:Create(Btn, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(58, 58, 72) }):Play()
	end)
	Btn.MouseLeave:Connect(function()
		local IsActive = (CURRENT_SLOT == i)
		TweenService:Create(Btn, ANIM.Pulse, {
			BackgroundColor3 = IsActive and Color3.fromRGB(60, 110, 180) or Color3.fromRGB(45, 45, 55)
		}):Play()
	end)

	Btn.MouseButton1Click:Connect(function()
		if PianoNotesBox then
			PIANO_SLOTS[CURRENT_SLOT] = PianoNotesBox.Text
		end

		CURRENT_SLOT = i

		if PianoNotesBox then
			PianoNotesBox.Text = PIANO_SLOTS[i] or ""
		end

		for j, b in ipairs(SlotButtons) do
			b.BackgroundColor3 = (j == i) and Color3.fromRGB(60, 110, 180) or Color3.fromRGB(45, 45, 55)
		end

		StatusLabel.Text = "PIANO: активен слот " .. i
	end)

	table.insert(SlotButtons, Btn)
end

SlotButtons[1].BackgroundColor3 = Color3.fromRGB(60, 110, 180)

local NotesLabel = Instance.new("TextLabel")
NotesLabel.Size = UDim2.new(1, 0, 0, 22)
NotesLabel.BackgroundTransparency = 1
NotesLabel.Text = "Вставь ноты (Ctrl+V). До ~10000 символов на слот."
NotesLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
NotesLabel.TextSize = 12
NotesLabel.Font = Enum.Font.Gotham
NotesLabel.TextXAlignment = Enum.TextXAlignment.Left
NotesLabel.Parent = PianoSection.Body

PianoNotesBox = Instance.new("TextBox")
PianoNotesBox.Name = "NotesBox"
PianoNotesBox.Size = UDim2.new(1, 0, 0, 280)
PianoNotesBox.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
PianoNotesBox.TextColor3 = Color3.fromRGB(255, 255, 255)
PianoNotesBox.Text = PIANO_SLOTS[1] or ""
PianoNotesBox.PlaceholderText = "Вставь ноты сюда (Ctrl+V)"
PianoNotesBox.TextSize = 11
PianoNotesBox.Font = Enum.Font.Code
PianoNotesBox.ClearTextOnFocus = false
PianoNotesBox.MultiLine = true
PianoNotesBox.TextWrapped = true
PianoNotesBox.TextXAlignment = Enum.TextXAlignment.Left
PianoNotesBox.TextYAlignment = Enum.TextYAlignment.Top
PianoNotesBox.Parent = PianoSection.Body
CreateCorner(PianoNotesBox, 6)

local NotesPadding = Instance.new("UIPadding")
NotesPadding.PaddingTop = UDim.new(0, 6)
NotesPadding.PaddingBottom = UDim.new(0, 6)
NotesPadding.PaddingLeft = UDim.new(0, 8)
NotesPadding.PaddingRight = UDim.new(0, 8)
NotesPadding.Parent = PianoNotesBox

local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, 0, 0, 20)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text = "Символов: 0"
InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
InfoLabel.TextSize = 11
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.TextXAlignment = Enum.TextXAlignment.Right
InfoLabel.Parent = PianoSection.Body

PianoNotesBox:GetPropertyChangedSignal("Text"):Connect(function()
	InfoLabel.Text = "Символов: " .. #PianoNotesBox.Text
end)

PianoNotesBox.FocusLost:Connect(function()
	PIANO_SLOTS[CURRENT_SLOT] = PianoNotesBox.Text
	PIANO_NOTES = PianoNotesBox.Text
	StatusLabel.Text = "PIANO: слот " .. CURRENT_SLOT .. " сохранён (" .. #PIANO_NOTES .. " символов)"
end)

local LoadNotesButton = CreateButton("ЗАГРУЗИТЬ НОТЫ ИЗ СЛОТА", 36, PianoSection.Body)
LoadNotesButton.MouseButton1Click:Connect(function()
	PIANO_SLOTS[CURRENT_SLOT] = PianoNotesBox.Text
	PIANO_NOTES = PianoNotesBox.Text
	local Count = 0
	for _ in string.gmatch(PIANO_NOTES, "%S") do Count += 1 end
	StatusLabel.Text = "PIANO: слот " .. CURRENT_SLOT .. " — " .. Count .. " символов"
end)

local PlayPianoButton = CreateButton("ИГРАТЬ / СТОП", 36, PianoSection.Body)

local ClearNotesButton = CreateButton("ОЧИСТИТЬ ТЕКУЩИЙ СЛОТ", 32, PianoSection.Body)
ClearNotesButton.MouseButton1Click:Connect(function()
	PianoNotesBox.Text = ""
	PIANO_SLOTS[CURRENT_SLOT] = ""
	PIANO_NOTES = ""
	InfoLabel.Text = "Символов: 0"
end)

--==================================================
-- СЕКЦИЯ: КЛАВИШИ
--==================================================

local KeybindSection = CreateSection("КЛАВИШИ", false)

local function CreateKeyButton(Name, CurrentKey)
	local Button = CreateButton(Name .. ": " .. CurrentKey.Name, 38, KeybindSection.Body)
	KeybindButtons[Name] = Button
	return Button
end

local SpiroKeyButton = CreateKeyButton("SPIRO", SPIRO_KEY)
local FlyKeyButton = CreateKeyButton("FLY", FLY_KEY)
local ESPKeyButton = CreateKeyButton("ESP", ESP_KEY)
local MenuKeyButton = CreateKeyButton("MENU", MENU_KEY)
local FreecamKeyButton = CreateKeyButton("FREECAM", FREECAM_KEY)
local SpectateKeyButton = CreateKeyButton("SPECTATE", SPECTATE_KEY)
local PianoKeyButton = CreateKeyButton("PIANO", PIANO_KEY)

local function IsKeyAlreadyUsed(Key)
	if Key == SPIRO_KEY then return "SPIRO" end
	if Key == FLY_KEY then return "FLY" end
	if Key == ESP_KEY then return "ESP" end
	if Key == MENU_KEY then return "MENU" end
	if Key == FREECAM_KEY then return "FREECAM" end
	if Key == SPECTATE_KEY then return "SPECTATE" end
	if Key == PIANO_KEY then return "PIANO" end
	return nil
end

UpdateHelpLabel = function()
	if not HelpLabel then return end
	HelpLabel.Text =
		"SPIRO (" .. SPIRO_KEY.Name .. ") — движение вокруг цели\n" ..
		"FLY (" .. FLY_KEY.Name .. ") — WASD + Space / Ctrl\n" ..
		"ESP (" .. ESP_KEY.Name .. ") — подсветка + HP\n" ..
		"FREECAM (" .. FREECAM_KEY.Name .. ") — свободная камера\n" ..
		"SPECTATE (" .. SPECTATE_KEY.Name .. ") — orbit вокруг цели\n" ..
		"PIANO (" .. PIANO_KEY.Name .. ") — автоигра на пианино"
end

local function UpdateKeyButtons()
	SpiroKeyButton.Text = "SPIRO: " .. SPIRO_KEY.Name
	FlyKeyButton.Text = "FLY: " .. FLY_KEY.Name
	ESPKeyButton.Text = "ESP: " .. ESP_KEY.Name
	MenuKeyButton.Text = "MENU: " .. MENU_KEY.Name
	FreecamKeyButton.Text = "FREECAM: " .. FREECAM_KEY.Name
	SpectateKeyButton.Text = "SPECTATE: " .. SPECTATE_KEY.Name
	PianoKeyButton.Text = "PIANO: " .. PIANO_KEY.Name
	UpdateHelpLabel()
end

local function StartKeybindChange(Name)
	if WaitingForKey == Name then
		WaitingForKey = nil
		UpdateKeyButtons()
		return
	end
	if WaitingForKey then return end
	WaitingForKey = Name
	local Button = KeybindButtons[Name]
	if Button then Button.Text = Name .. ": нажмите клавишу..." end
end

SpiroKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("SPIRO") end)
FlyKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("FLY") end)
ESPKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("ESP") end)
MenuKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("MENU") end)
FreecamKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("FREECAM") end)
SpectateKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("SPECTATE") end)
PianoKeyButton.MouseButton1Click:Connect(function() StartKeybindChange("PIANO") end)

UpdateHelpLabel()

--==================================================
-- СЕКЦИЯ: ИГРОКИ
--==================================================

local PlayersSection = CreateSection("ИГРОКИ", false)

local PlayerListFrame = Instance.new("Frame")
PlayerListFrame.Size = UDim2.new(1, 0, 0, 0)
PlayerListFrame.AutomaticSize = Enum.AutomaticSize.Y
PlayerListFrame.BackgroundTransparency = 1
PlayerListFrame.Parent = PlayersSection.Body

local PlayerListLayout = Instance.new("UIListLayout")
PlayerListLayout.Padding = UDim.new(0, 5)
PlayerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
PlayerListLayout.Parent = PlayerListFrame

--==================================================
-- ESP
--==================================================

local function IsFriendCached(Player)
	local Now = os.time()
	if Now - FriendCacheTimestamp > FRIEND_CACHE_TTL then
		table.clear(FriendCache)
		FriendCacheTimestamp = Now
	end
	if FriendCache[Player] == nil then
		local Success, Result = pcall(function()
			return LocalPlayer:IsFriendsWith(Player.UserId)
		end)
		FriendCache[Player] = Success and Result or false
	end
	return FriendCache[Player]
end

local function GetESPColor(Player)
	if TargetPlayer == Player then return Color3.fromRGB(0, 140, 255) end
	if IsFriendCached(Player) then return Color3.fromRGB(0, 255, 100) end
	return Color3.fromRGB(255, 60, 60)
end

local function GetHealthColor(Current, Max)
	if Max <= 0 then return Color3.fromRGB(255, 60, 60) end
	local Ratio = Current / Max
	if Ratio > 0.5 then return Color3.fromRGB(0, 255, 100)
	elseif Ratio > 0.25 then return Color3.fromRGB(255, 200, 0)
	else return Color3.fromRGB(255, 60, 60) end
end

local function RemovePlayerESP(Player)
	local Highlight = ESPHighlights[Player]
	if Highlight then Highlight:Destroy() ESPHighlights[Player] = nil end
	local NameTag = ESPNameTags[Player]
	if NameTag then NameTag:Destroy() ESPNameTags[Player] = nil end
	local Connection = ESPPlayerConnections[Player]
	if Connection and typeof(Connection) == "RBXScriptConnection" then
		Connection:Disconnect()
		ESPPlayerConnections[Player] = nil
	end
	FriendCache[Player] = nil
end

local function AddPlayerESP(Player)
	if not ESPEnabled then return end
	if Player == LocalPlayer then return end

	local ExistingConnection = ESPPlayerConnections[Player]
	if ExistingConnection and typeof(ExistingConnection) == "RBXScriptConnection" then
		ExistingConnection:Disconnect()
		ESPPlayerConnections[Player] = nil
	end

	local OldHighlight = ESPHighlights[Player]
	if OldHighlight then OldHighlight:Destroy() ESPHighlights[Player] = nil end
	local OldNameTag = ESPNameTags[Player]
	if OldNameTag then OldNameTag:Destroy() ESPNameTags[Player] = nil end

	local CharacterOfPlayer = Player.Character
	if not CharacterOfPlayer then return end

	local Highlight = Instance.new("Highlight")
	Highlight.Name = "SpiroWallhackHighlight"
	Highlight.Adornee = CharacterOfPlayer
	Highlight.FillColor = GetESPColor(Player)
	Highlight.OutlineColor = GetESPColor(Player)
	Highlight.FillTransparency = 0.45
	Highlight.OutlineTransparency = 0
	Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	Highlight.Parent = CharacterOfPlayer

	local Adornee = CharacterOfPlayer:FindFirstChild("Head")
		or CharacterOfPlayer:FindFirstChild("HumanoidRootPart")
		or CharacterOfPlayer:FindFirstChildWhichIsA("BasePart")

	local NameTag = Instance.new("BillboardGui")
	NameTag.Name = "SpiroWallhackUsername"
	NameTag.Adornee = Adornee
	NameTag.Size = UDim2.new(0, 220, 0, 50)
	NameTag.StudsOffset = Vector3.new(0, 3.2, 0)
	NameTag.AlwaysOnTop = true
	NameTag.MaxDistance = 10000
	NameTag.Parent = CharacterOfPlayer

	local NameLabel = Instance.new("TextLabel")
	NameLabel.Name = "Username"
	NameLabel.BackgroundTransparency = 1
	NameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	NameLabel.Position = UDim2.new(0, 0, 0, 0)
	NameLabel.Font = Enum.Font.GothamBold
	NameLabel.Text = Player.Name
	NameLabel.TextColor3 = GetESPColor(Player)
	NameLabel.TextSize = 16
	NameLabel.TextStrokeTransparency = 0
	NameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	NameLabel.Parent = NameTag

	local HPLabel = Instance.new("TextLabel")
	HPLabel.Name = "HP"
	HPLabel.BackgroundTransparency = 1
	HPLabel.Size = UDim2.new(1, 0, 0.5, 0)
	HPLabel.Position = UDim2.new(0, 0, 0.5, 0)
	HPLabel.Font = Enum.Font.GothamBold
	HPLabel.Text = "HP: ?"
	HPLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	HPLabel.TextSize = 14
	HPLabel.TextStrokeTransparency = 0
	HPLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	HPLabel.Parent = NameTag

	ESPHighlights[Player] = Highlight
	ESPNameTags[Player] = NameTag
end

local function UpdateESPColors()
	if not ESPEnabled then return end
	for Player, Highlight in pairs(ESPHighlights) do
		local NameTag = ESPNameTags[Player]
		if Player and Player.Parent == Players and Highlight and Highlight.Parent then
			local Color = GetESPColor(Player)
			Highlight.FillColor = Color
			Highlight.OutlineColor = Color
			if NameTag and NameTag.Parent then
				local NameLabel = NameTag:FindFirstChild("Username")
				if NameLabel then
					NameLabel.TextColor3 = Color
					NameLabel.Text = Player.Name
				end
			end
		else
			ESPHighlights[Player] = nil
		end
	end
end

local function UpdateESPHealth()
	if not ESPEnabled then return end
	for Player, NameTag in pairs(ESPNameTags) do
		if Player and Player.Parent == Players
			and NameTag and NameTag.Parent then
			local HPLabel = NameTag:FindFirstChild("HP")
			if HPLabel then
				local CharacterOfPlayer = Player.Character
				local Hum = nil
				if CharacterOfPlayer then
					Hum = CharacterOfPlayer:FindFirstChildOfClass("Humanoid")
				end
				if Hum then
					local Current = math.floor(Hum.Health + 0.5)
					local Max = math.floor(Hum.MaxHealth + 0.5)
					HPLabel.Text = "HP: " .. Current .. " / " .. Max
					HPLabel.TextColor3 = GetHealthColor(Hum.Health, Hum.MaxHealth)
				else
					HPLabel.Text = "HP: мёртв"
					HPLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
				end
			end
		end
	end
end

local function RemoveESP()
	for Player, Connection in pairs(ESPPlayerConnections) do
		if typeof(Connection) == "RBXScriptConnection" then Connection:Disconnect() end
		ESPPlayerConnections[Player] = nil
	end
	for Key, Connection in pairs(ESPGlobalConnections) do
		if typeof(Connection) == "RBXScriptConnection" then Connection:Disconnect() end
		ESPGlobalConnections[Key] = nil
	end
	for Player, Highlight in pairs(ESPHighlights) do
		if Highlight then Highlight:Destroy() end
		ESPHighlights[Player] = nil
	end
	for Player, NameTag in pairs(ESPNameTags) do
		if NameTag then NameTag:Destroy() end
		ESPNameTags[Player] = nil
	end
	table.clear(FriendCache)
	FriendCacheTimestamp = 0
end

local function CreateESP()
	RemoveESP()
	if not ESPEnabled then return end

	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer then
			AddPlayerESP(Player)
			ESPPlayerConnections[Player] = Player.CharacterAdded:Connect(function()
				if ESPEnabled then
					task.wait(0.2)
					AddPlayerESP(Player)
				end
			end)
		end
	end

	ESPGlobalConnections.PlayerAdded = Players.PlayerAdded:Connect(function(Player)
		if Player == LocalPlayer then return end
		if ESPEnabled then
			AddPlayerESP(Player)
			ESPPlayerConnections[Player] = Player.CharacterAdded:Connect(function()
				if ESPEnabled then
					task.wait(0.2)
					AddPlayerESP(Player)
				end
			end)
		end
	end)

	ESPGlobalConnections.PlayerRemoving = Players.PlayerRemoving:Connect(function(Player)
		RemovePlayerESP(Player)
	end)

	UpdateESPColors()
	UpdateESPHealth()
end

--==================================================
-- ОТКЛЮЧЕНИЕ TARGET
--==================================================

DisableTargetBecauseDead = function()
	if DeadHandled then return end
	DeadHandled = true

	if SpiroEnabled then SpiroEnabled = false end
	if SpiroCamOldCameraType and StopSpiroCamera then StopSpiroCamera() end

	CurrentPoint = 1
	MovementAccumulator = 0

	if Humanoid then Humanoid.AutoRotate = true end
	if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
	if TargetPlayer then StatusLabel.Text = "Цель: мертва — SPIRO выключен" end

	UpdateESPColors()
end

--==================================================
-- ПОДКЛЮЧЕНИЕ К HUMANOID ЦЕЛИ
--==================================================

local function ConnectTargetDeath(Player)
	if TargetHumanoidConnection then
		TargetHumanoidConnection:Disconnect()
		TargetHumanoidConnection = nil
	end

	if not Player then return end

	local function ConnectToCharacter(CharacterOfTarget)
		if TargetHumanoidConnection then
			TargetHumanoidConnection:Disconnect()
			TargetHumanoidConnection = nil
		end
		if not CharacterOfTarget then return end

		local TargetHumanoid = CharacterOfTarget:FindFirstChildOfClass("Humanoid")
		if not TargetHumanoid then
			TargetHumanoid = CharacterOfTarget:WaitForChild("Humanoid", 5)
		end
		if not TargetHumanoid then return end

		TargetHumanoidConnection = TargetHumanoid.Died:Connect(function()
			if TargetPlayer == Player then DisableTargetBecauseDead() end
		end)
	end

	if Player.Character then ConnectToCharacter(Player.Character) end

	if TargetCharacterConnection then
		TargetCharacterConnection:Disconnect()
		TargetCharacterConnection = nil
	end

	TargetCharacterConnection = Player.CharacterAdded:Connect(function(NewCharacter)
		if TargetPlayer ~= Player then return end
		ConnectToCharacter(NewCharacter)
		CurrentPoint = 1
		MovementAccumulator = 0
		DeadHandled = false
		if ESPEnabled then
			task.wait(0.2)
			if TargetPlayer == Player then
				AddPlayerESP(Player)
				UpdateESPColors()
			end
		end
		StatusLabel.Text = "Цель: " .. Player.Name .. " — готова"
	end)
end

--==================================================
-- SELECT TARGET
--==================================================

local function SelectTarget(Player)
	if Player == TargetPlayer then return end

	if TargetHumanoidConnection then
		TargetHumanoidConnection:Disconnect()
		TargetHumanoidConnection = nil
	end
	if TargetCharacterConnection then
		TargetCharacterConnection:Disconnect()
		TargetCharacterConnection = nil
	end

	local WasSpectating = SpectateEnabled
	if WasSpectating and StopSpectate then StopSpectate() end

	SpiroEnabled = false
	CurrentPoint = 1
	MovementAccumulator = 0
	DeadHandled = false

	if Humanoid then Humanoid.AutoRotate = true end

	TargetPlayer = Player
	if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
	StatusLabel.Text = "Цель: " .. Player.Name

	ConnectTargetDeath(Player)

	if ESPEnabled then UpdateESPColors() end

	if WasSpectating then
		task.delay(0.2, function()
			if TargetPlayer and ToggleSpectate then ToggleSpectate() end
		end)
	end
end

--==================================================
-- PLAYER LIST
--==================================================

local function RefreshPlayerList()
	for _, Object in ipairs(PlayerListFrame:GetChildren()) do
		if Object:IsA("TextButton") then Object:Destroy() end
	end

	local SortedPlayers = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer then table.insert(SortedPlayers, Player) end
	end

	table.sort(SortedPlayers, function(a, b)
		local an, bn = a.Name:lower(), b.Name:lower()
		if an == bn then return a.UserId < b.UserId end
		return an < bn
	end)

	for i, Player in ipairs(SortedPlayers) do
		local Button = Instance.new("TextButton")
		Button.Name = "PlayerButton_" .. Player.UserId
		Button.LayoutOrder = i
		Button.Size = UDim2.new(1, 0, 0, 36)
		Button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		Button.Text = Player.Name
		Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Button.TextSize = 13
		Button.Font = Enum.Font.GothamSemibold
		Button.AutoButtonColor = false
		Button.Parent = PlayerListFrame
		CreateCorner(Button, 7)

		Button.MouseEnter:Connect(function()
			TweenService:Create(Button, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(58, 58, 72) }):Play()
		end)
		Button.MouseLeave:Connect(function()
			TweenService:Create(Button, ANIM.Pulse, { BackgroundColor3 = Color3.fromRGB(45, 45, 55) }):Play()
		end)
		Button.MouseButton1Click:Connect(function() SelectTarget(Player) end)
	end
end

RefreshPlayerList()

Players.PlayerAdded:Connect(function()
	task.wait(0.2)
	RefreshPlayerList()
end)

Players.PlayerRemoving:Connect(function(Player)
	if TargetPlayer == Player then
		SpiroEnabled = false
		CurrentPoint = 1
		if Humanoid then Humanoid.AutoRotate = true end
		if TargetHumanoidConnection then
			TargetHumanoidConnection:Disconnect()
			TargetHumanoidConnection = nil
		end
		if TargetCharacterConnection then
			TargetCharacterConnection:Disconnect()
			TargetCharacterConnection = nil
		end
		if SpectateEnabled and StopSpectate then StopSpectate() end
		TargetPlayer = nil
		DeadHandled = false
		RemovePlayerESP(Player)
		if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
		StatusLabel.Text = "Цель: не выбрана"
	end
	task.defer(RefreshPlayerList)
end)

--==================================================
-- TRIANGLE
--==================================================

local function GetTrianglePoints(Center)
	local Distance = TARGET_DISTANCE
	local Height = math.clamp(Distance * 0.33, 2, 10)
	return {
		Center + Vector3.new(0, Height, -Distance),
		Center + Vector3.new(Distance * 0.866, Height, Distance * 0.5),
		Center + Vector3.new(-Distance * 0.866, Height, Distance * 0.5)
	}
end

--==================================================
-- MOVE
--==================================================

local function MoveTowards(Position, Speed, DeltaTime, LookAtPosition)
	if not RootPart then return end
	local CurrentPosition = RootPart.Position
	local Direction = Position - CurrentPosition
	local Distance = Direction.Magnitude
	if Distance <= 0.05 then return end
	local MaxMove = Speed * DeltaTime
	local NewPosition
	if Distance <= MaxMove then NewPosition = Position
	else NewPosition = CurrentPosition + Direction.Unit * MaxMove end
	local FacePosition = LookAtPosition or Position
	local LookDir = Vector3.new(FacePosition.X, NewPosition.Y, FacePosition.Z)
	local LookVector = LookDir - NewPosition
	LookVector = Vector3.new(LookVector.X, 0, LookVector.Z)
	if LookVector.Magnitude < 0.001 then
		LookVector = RootPart.CFrame.LookVector
		LookVector = Vector3.new(LookVector.X, 0, LookVector.Z)
		if LookVector.Magnitude < 0.001 then
			LookVector = Vector3.new(0, 0, -1)
		end
	end
	local TargetCFrame
	local Success = pcall(function()
		TargetCFrame = CFrame.lookAt(NewPosition, NewPosition + LookVector.Unit)
	end)
	if not Success or not TargetCFrame then return end
	RootPart.CFrame = TargetCFrame
end

--==================================================
-- SPIRO CAMERA
--==================================================

StartSpiroCamera = function()
	if not TargetPlayer then return end
	local TargetCharacter = TargetPlayer.Character
	if not TargetCharacter then return end
	local TargetHead = TargetCharacter:FindFirstChild("Head")
		or TargetCharacter:FindFirstChild("HumanoidRootPart")
	if not TargetHead then return end
	local Camera = workspace.CurrentCamera
	if not Camera then return end

	SpiroCamOldCameraType = Camera.CameraType
	SpiroCamOldCameraSubject = Camera.CameraSubject
	SpiroCamOldMouseBehavior = UserInputService.MouseBehavior
	SpiroCamOldMouseIconEnabled = UserInputService.MouseIconEnabled

	SpiroCamYaw = 0
	SpiroCamPitch = math.rad(-15)
	SpiroCamDistance = SPIRO_CAM_DISTANCE
	SpiroCamCurrentPos = nil

	Camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

StopSpiroCamera = function()
	if not SpiroCamOldCameraType then return end
	local Camera = workspace.CurrentCamera
	if Camera then
		Camera.CameraType = SpiroCamOldCameraType or Enum.CameraType.Custom
		if SpiroCamOldCameraSubject then
			Camera.CameraSubject = SpiroCamOldCameraSubject
		elseif Humanoid then
			Camera.CameraSubject = Humanoid
		end
	end
	UserInputService.MouseBehavior = SpiroCamOldMouseBehavior or Enum.MouseBehavior.Default
	if SpiroCamOldMouseIconEnabled == nil then
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseIconEnabled = SpiroCamOldMouseIconEnabled
	end
	SpiroCamOldCameraType = nil
	SpiroCamOldCameraSubject = nil
	SpiroCamOldMouseBehavior = nil
	SpiroCamOldMouseIconEnabled = nil
	SpiroCamCurrentPos = nil
	SpiroCamYaw = 0
	SpiroCamPitch = 0
end

--==================================================
-- TOGGLE SPIRO
--==================================================

local function ToggleSpiro()
	if not TargetPlayer then
		StatusLabel.Text = "Сначала выберите игрока!"
		task.delay(1.5, function()
			if not TargetPlayer then StatusLabel.Text = "Цель: не выбрана" end
		end)
		return
	end

	local TargetRoot = GetTargetRoot()
	if not TargetRoot then
		SpiroEnabled = false
		if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
		StatusLabel.Text = "Цель мертва — выберите/дождитесь возрождения"
		return
	end

	SpiroEnabled = not SpiroEnabled
	CurrentPoint = 1
	MovementAccumulator = 0

	if Humanoid then Humanoid.AutoRotate = not SpiroEnabled end

	if SpiroEnabled then
		if SpiroButton then SpiroButton.Text = "SPIRO: ON" end
		StatusLabel.Text = "SPIRO активен: " .. TargetPlayer.Name
		if SpectateEnabled and StopSpectate then StopSpectate() end
		if FreecamEnabled and ToggleFreecam then ToggleFreecam() end
		StartSpiroCamera()
	else
		if SpiroButton then SpiroButton.Text = "SPIRO: OFF" end
		StatusLabel.Text = "SPIRO выключен"
		StopSpiroCamera()
	end
end

SpiroButton.MouseButton1Click:Connect(ToggleSpiro)

--==================================================
-- FLY
--==================================================

StopFly = function()
	FlyEnabled = false
	if FlyLinearVelocity then FlyLinearVelocity:Destroy() FlyLinearVelocity = nil end
	if FlyAlignOrientation then FlyAlignOrientation:Destroy() FlyAlignOrientation = nil end
	if FlyAttachment then FlyAttachment:Destroy() FlyAttachment = nil end
	if Humanoid then
		Humanoid.PlatformStand = false
		Humanoid.AutoRotate = true
	end
	if FlyButton then FlyButton.Text = "FLY: OFF" end
end

StartFly = function()
	if FlyEnabled then return end
	if not RootPart or not RootPart.Parent then return end
	if not Humanoid or not Humanoid.Parent or Humanoid.Health <= 0 then return end

	if FlyLinearVelocity then FlyLinearVelocity:Destroy() FlyLinearVelocity = nil end
	if FlyAlignOrientation then FlyAlignOrientation:Destroy() FlyAlignOrientation = nil end
	if FlyAttachment then FlyAttachment:Destroy() FlyAttachment = nil end

	FlyAttachment = Instance.new("Attachment")
	FlyAttachment.Name = "SpiroFlyAttachment"
	FlyAttachment.Parent = RootPart

	FlyLinearVelocity = Instance.new("LinearVelocity")
	FlyLinearVelocity.Name = "SpiroFlyLinearVelocity"
	FlyLinearVelocity.Attachment0 = FlyAttachment
	FlyLinearVelocity.MaxForce = math.huge
	FlyLinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	FlyLinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	FlyLinearVelocity.VectorVelocity = Vector3.zero
	FlyLinearVelocity.Parent = RootPart

	FlyAlignOrientation = Instance.new("AlignOrientation")
	FlyAlignOrientation.Name = "SpiroFlyAlignOrientation"
	FlyAlignOrientation.Attachment0 = FlyAttachment
	FlyAlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	FlyAlignOrientation.MaxTorque = math.huge
	FlyAlignOrientation.Responsiveness = 200
	FlyAlignOrientation.PrimaryAxisOnly = false
	FlyAlignOrientation.Parent = RootPart

	FlyEnabled = true
	if Humanoid then
		Humanoid.PlatformStand = true
		Humanoid.AutoRotate = false
	end
	if FlyButton then FlyButton.Text = "FLY: ON" end
end

local function ToggleFly()
	if FlyEnabled then StopFly() else StartFly() end
end

FlyButton.MouseButton1Click:Connect(ToggleFly)

--==================================================
-- FLY UPDATE
--==================================================

local function UpdateFly()
	if not FlyEnabled then return end
	if not RootPart or not FlyLinearVelocity or not FlyAlignOrientation then return end
	if not Humanoid or Humanoid.Health <= 0 then return end

	local Camera = workspace.CurrentCamera
	if not Camera then return end

	local MoveDirection = Vector3.zero
	local Forward = Camera.CFrame.LookVector
	local Right = Camera.CFrame.RightVector

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then MoveDirection += Forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then MoveDirection -= Forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then MoveDirection += Right end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then MoveDirection -= Right end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then MoveDirection += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		MoveDirection -= Vector3.new(0, 1, 0)
	end

	if MoveDirection.Magnitude > 0 then MoveDirection = MoveDirection.Unit end

	FlyLinearVelocity.VectorVelocity = MoveDirection * FLY_SPEED

	local CameraLook = Camera.CFrame.LookVector
	local CameraUp = Camera.CFrame.UpVector
	if CameraLook.Magnitude > 0.001 then
		FlyAlignOrientation.CFrame = CFrame.lookAt(
			RootPart.Position,
			RootPart.Position + CameraLook,
			CameraUp
		)
	end
end

--==================================================
-- ESP TOGGLE
--==================================================

local function ToggleESP()
	ESPEnabled = not ESPEnabled
	if ESPEnabled then
		ESPButton.Text = "ESP: ON"
		CreateESP()
	else
		ESPButton.Text = "ESP: OFF"
		RemoveESP()
	end
end

ESPButton.MouseButton1Click:Connect(ToggleESP)

--==================================================
-- SPECTATE
--==================================================

local function StartSpectate()
	if SpectateEnabled then return end
	if not TargetPlayer then
		StatusLabel.Text = "Сначала выберите игрока!"
		task.delay(1.5, function()
			if not TargetPlayer then StatusLabel.Text = "Цель: не выбрана" end
		end)
		return
	end
	local TargetRoot = GetTargetRoot()
	if not TargetRoot then
		StatusLabel.Text = "Цель мертва — spectate недоступен"
		return
	end
	local Camera = workspace.CurrentCamera
	if not Camera then return end

	SpectateOldCameraType = Camera.CameraType
	SpectateOldCameraSubject = Camera.CameraSubject
	SpectateOldMouseBehavior = UserInputService.MouseBehavior
	SpectateOldMouseIconEnabled = UserInputService.MouseIconEnabled

	SpectateYaw = 0
	SpectatePitch = math.rad(-15)
	SpectateDistance = SPECTATE_DISTANCE
	SpectateCurrentPos = nil

	Camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	SpectateEnabled = true
	if SpectateButton then SpectateButton.Text = "SPECTATE: ON" end
	StatusLabel.Text = "SPECTATE: orbit вокруг " .. TargetPlayer.Name
end

StopSpectate = function()
	if not SpectateEnabled then return end
	SpectateEnabled = false

	local Camera = workspace.CurrentCamera
	if Camera then
		Camera.CameraType = SpectateOldCameraType or Enum.CameraType.Custom
		if SpectateOldCameraSubject then
			Camera.CameraSubject = SpectateOldCameraSubject
		elseif Humanoid then
			Camera.CameraSubject = Humanoid
		end
	end

	UserInputService.MouseBehavior = SpectateOldMouseBehavior or Enum.MouseBehavior.Default
	if SpectateOldMouseIconEnabled == nil then
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseIconEnabled = SpectateOldMouseIconEnabled
	end

	SpectateYaw = 0
	SpectatePitch = 0
	SpectateCurrentPos = nil
	SpectateOldCameraType = nil
	SpectateOldCameraSubject = nil

	if SpectateButton then SpectateButton.Text = "SPECTATE: OFF" end
	StatusLabel.Text = "SPECTATE выключен"
end

ToggleSpectate = function()
	if SpectateEnabled then
		StopSpectate()
	else
		if SpiroEnabled then StopSpiro() end
		if FreecamEnabled and ToggleFreecam then ToggleFreecam() end
		StartSpectate()
	end
end

SpectateButton.MouseButton1Click:Connect(function() ToggleSpectate() end)

--==================================================
-- SPECTATE UPDATE
--==================================================

RunService.RenderStepped:Connect(function(DeltaTime)
	if not SpectateEnabled then return end
	local Camera = workspace.CurrentCamera
	if not Camera then return end

	local MenuOpen = not MenuCollapsed

	if not MenuOpen then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
		local MouseDelta = UserInputService:GetMouseDelta()
		SpectateYaw = SpectateYaw - MouseDelta.X * SPECTATE_SENSITIVITY
		SpectatePitch = math.clamp(
			SpectatePitch - MouseDelta.Y * SPECTATE_SENSITIVITY,
			-math.rad(85),
			math.rad(85)
		)
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
	end

	local ZoomDelta = UserInputService:GetMouseWheelDelta()
	if ZoomDelta ~= 0 and not MenuOpen then
		SpectateDistance = math.clamp(
			SpectateDistance - ZoomDelta * CAM_ZOOM_SPEED,
			2, 50
		)
	end

	local TargetRoot = GetTargetRoot()
	local FocusPosition
	if TargetRoot then
		FocusPosition = TargetRoot.Position + Vector3.new(0, SPECTATE_HEIGHT_OFFSET, 0)
	else
		if SpectateCurrentPos then FocusPosition = SpectateCurrentPos
		else return end
	end

	local Rotation = CFrame.Angles(0, SpectateYaw, 0) * CFrame.Angles(SpectatePitch, 0, 0)
	local Offset = Rotation * Vector3.new(0, 0, SpectateDistance)
	local DesiredPos = FocusPosition + Offset
	local DesiredCFrame = CFrame.lookAt(DesiredPos, FocusPosition)

	if not SpectateCurrentPos then
		SpectateCurrentPos = DesiredPos
		Camera.CFrame = DesiredCFrame
	else
		SpectateCurrentPos = SpectateCurrentPos:Lerp(DesiredPos, SPECTATE_LERP)
		Camera.CFrame = CFrame.lookAt(SpectateCurrentPos, FocusPosition)
	end
end)

--==================================================
-- SPIRO CAMERA UPDATE
--==================================================

RunService.RenderStepped:Connect(function(DeltaTime)
	if not SpiroEnabled then return end
	if SpectateEnabled then return end
	if FreecamEnabled then return end

	local Camera = workspace.CurrentCamera
	if not Camera then return end

	local MenuOpen = not MenuCollapsed

	if not MenuOpen then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
		local MouseDelta = UserInputService:GetMouseDelta()
		SpiroCamYaw = SpiroCamYaw - MouseDelta.X * SPIRO_CAM_SENSITIVITY
		SpiroCamPitch = math.clamp(
			SpiroCamPitch - MouseDelta.Y * SPIRO_CAM_SENSITIVITY,
			-math.rad(85),
			math.rad(85)
		)
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
	end

	local ZoomDelta = UserInputService:GetMouseWheelDelta()
	if ZoomDelta ~= 0 and not MenuOpen then
		SpiroCamDistance = math.clamp(
			SpiroCamDistance - ZoomDelta * CAM_ZOOM_SPEED,
			2, 50
		)
	end

	local TargetCharacter = TargetPlayer and TargetPlayer.Character
	local TargetHead = nil
	if TargetCharacter then
		TargetHead = TargetCharacter:FindFirstChild("Head")
			or TargetCharacter:FindFirstChild("HumanoidRootPart")
	end

	local FocusPosition
	if TargetHead then
		FocusPosition = TargetHead.Position + Vector3.new(0, SPIRO_CAM_HEIGHT_OFFSET, 0)
	else
		if SpiroCamCurrentPos then FocusPosition = SpiroCamCurrentPos
		else return end
	end

	local Rotation = CFrame.Angles(0, SpiroCamYaw, 0) * CFrame.Angles(SpiroCamPitch, 0, 0)
	local Offset = Rotation * Vector3.new(0, 0, SpiroCamDistance)
	local DesiredPos = FocusPosition + Offset
	local DesiredCFrame = CFrame.lookAt(DesiredPos, FocusPosition)

	if not SpiroCamCurrentPos then
		SpiroCamCurrentPos = DesiredPos
		Camera.CFrame = DesiredCFrame
	else
		SpiroCamCurrentPos = SpiroCamCurrentPos:Lerp(DesiredPos, SPIRO_CAM_LERP)
		Camera.CFrame = CFrame.lookAt(SpiroCamCurrentPos, FocusPosition)
	end
end)

--==================================================
-- AUTO PIANO
--==================================================

local CHAR_TO_KEY = {
	["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
	["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
	["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine,
	["0"] = Enum.KeyCode.Zero,
	["q"] = Enum.KeyCode.Q, ["w"] = Enum.KeyCode.W, ["e"] = Enum.KeyCode.E,
	["r"] = Enum.KeyCode.R, ["t"] = Enum.KeyCode.T, ["y"] = Enum.KeyCode.Y,
	["u"] = Enum.KeyCode.U, ["i"] = Enum.KeyCode.I, ["o"] = Enum.KeyCode.O,
	["p"] = Enum.KeyCode.P,
	["a"] = Enum.KeyCode.A, ["s"] = Enum.KeyCode.S, ["d"] = Enum.KeyCode.D,
	["f"] = Enum.KeyCode.F, ["g"] = Enum.KeyCode.G, ["h"] = Enum.KeyCode.H,
	["j"] = Enum.KeyCode.J, ["k"] = Enum.KeyCode.K, ["l"] = Enum.KeyCode.L,
	["z"] = Enum.KeyCode.Z, ["x"] = Enum.KeyCode.X, ["c"] = Enum.KeyCode.C,
	["v"] = Enum.KeyCode.V, ["b"] = Enum.KeyCode.B, ["n"] = Enum.KeyCode.N,
	["m"] = Enum.KeyCode.M,

	["!"] = Enum.KeyCode.One, ["@"] = Enum.KeyCode.Two, ["#"] = Enum.KeyCode.Three,
	["$"] = Enum.KeyCode.Four, ["%"] = Enum.KeyCode.Five, ["^"] = Enum.KeyCode.Six,
	["&"] = Enum.KeyCode.Seven, ["*"] = Enum.KeyCode.Eight, ["("] = Enum.KeyCode.Nine,
	[")"] = Enum.KeyCode.Zero,

	["Q"] = Enum.KeyCode.Q, ["W"] = Enum.KeyCode.W, ["E"] = Enum.KeyCode.E,
	["R"] = Enum.KeyCode.R, ["T"] = Enum.KeyCode.T, ["Y"] = Enum.KeyCode.Y,
	["U"] = Enum.KeyCode.U, ["I"] = Enum.KeyCode.I, ["O"] = Enum.KeyCode.O,
	["P"] = Enum.KeyCode.P, ["A"] = Enum.KeyCode.A, ["S"] = Enum.KeyCode.S,
	["D"] = Enum.KeyCode.D, ["F"] = Enum.KeyCode.F, ["G"] = Enum.KeyCode.G,
	["H"] = Enum.KeyCode.H, ["J"] = Enum.KeyCode.J, ["K"] = Enum.KeyCode.K,
	["L"] = Enum.KeyCode.L, ["Z"] = Enum.KeyCode.Z, ["X"] = Enum.KeyCode.X,
	["C"] = Enum.KeyCode.C, ["V"] = Enum.KeyCode.V, ["B"] = Enum.KeyCode.B,
	["N"] = Enum.KeyCode.N, ["M"] = Enum.KeyCode.M,
}

local PAUSE_TABLE = {
	["-"] = 0.05,
	["_"] = 0.15,
	["."] = 0.02,
	[","] = 0.07,
	[";"] = 0.20,
	[":"] = 0.35,
	["|"] = 0.25,
}

local SHIFT_SYMBOLS = {
	["!"] = true, ["@"] = true, ["#"] = true, ["$"] = true, ["%"] = true,
	["^"] = true, ["&"] = true, ["*"] = true, ["("] = true, [")"] = true,
}

local function SendKeyDown(KeyCode, Shift)
	if not VirtualInputManager then return end
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, KeyCode, Shift or false, game)
	end)
end

local function SendKeyUp(KeyCode, Shift)
	if not VirtualInputManager then return end
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, KeyCode, Shift or false, game)
	end)
end

local function PressKey(Char, HoldTime)
	local KeyCode = CHAR_TO_KEY[Char]
	if not KeyCode then return end
	local Shift = SHIFT_SYMBOLS[Char] or false
	SendKeyDown(KeyCode, Shift)
	task.wait(HoldTime or 0.02)
	SendKeyUp(KeyCode, Shift)
end

local function PressChord(Chars, HoldTime)
	local PressedKeys = {}
	for Char in string.gmatch(Chars, ".") do
		local KeyCode = CHAR_TO_KEY[Char]
		if KeyCode then
			local Shift = SHIFT_SYMBOLS[Char] or false
			table.insert(PressedKeys, { key = KeyCode, shift = Shift })
			SendKeyDown(KeyCode, Shift)
		end
	end
	task.wait(HoldTime or 0.02)
	for _, Info in ipairs(PressedKeys) do
		SendKeyUp(Info.key, Info.shift)
	end
end

local function TokenizeNotes(RawNotes)
	local Tokens = {}
	RawNotes = RawNotes:gsub("[\r\n]+", " ")
	local i = 1
	while i <= #RawNotes do
		local Char = RawNotes:sub(i, i)
		if Char == "[" then
			local EndPos = RawNotes:find("]", i)
			if EndPos then
				local Chord = RawNotes:sub(i + 1, EndPos - 1)
				local NextChar = RawNotes:sub(EndPos + 1, EndPos + 1)
				local Multiplier = 1
				if NextChar == "-" then
					local j = EndPos + 1
					while RawNotes:sub(j, j) == "-" do
						Multiplier += 1
						j += 1
					end
					i = j
				elseif NextChar == "_" then
					local j = EndPos + 1
					while RawNotes:sub(j, j) == "_" do
						Multiplier += 3
						j += 1
					end
					i = j
				else
					i = EndPos + 1
				end
				table.insert(Tokens, { type = "chord", value = Chord, multiplier = Multiplier })
			else
				i = i + 1
			end
		elseif PAUSE_TABLE[Char] then
			local StartPos = i
			while i <= #RawNotes and RawNotes:sub(i, i) == Char do
				i += 1
			end
			local Pause = RawNotes:sub(StartPos, i - 1)
			table.insert(Tokens, { type = "pause", value = PAUSE_TABLE[Char] * #Pause })
		elseif Char:match("[%w]") or SHIFT_SYMBOLS[Char] then
			local Note = Char
			i += 1
			local Multiplier = 1
			if RawNotes:sub(i, i) == "-" then
				local j = i
				while RawNotes:sub(j, j) == "-" do
					Multiplier += 1
					j += 1
				end
				i = j
			elseif RawNotes:sub(i, i) == "_" then
				local j = i
				while RawNotes:sub(j, j) == "_" do
					Multiplier += 3
					j += 1
				end
				i = j
			end
			table.insert(Tokens, { type = "note", value = Note, multiplier = Multiplier })
		else
			i = i + 1
		end
	end
	return Tokens
end

local function PlayPiano()
	if PianoPlaying then
		PianoPlaying = false
		if PianoButton then PianoButton.Text = "PIANO: STOP" end
		StatusLabel.Text = "PIANO: остановлено"
		return
	end

	PIANO_NOTES = PianoNotesBox.Text
	PIANO_SLOTS[CURRENT_SLOT] = PIANO_NOTES

	if PIANO_NOTES == "" then
		StatusLabel.Text = "PIANO: слот " .. CURRENT_SLOT .. " пуст"
		return
	end

	local Tokens = TokenizeNotes(PIANO_NOTES)
	local Total = #Tokens

	PianoPlaying = true
	if PianoButton then PianoButton.Text = "PIANO: PLAYING" end
	StatusLabel.Text = "PIANO: слот " .. CURRENT_SLOT .. " — " .. Total .. " токенов"

	task.spawn(function()
		for i, Token in ipairs(Tokens) do
			if not PianoPlaying then break end
			if Token.type == "note" then
				PressKey(Token.value, PIANO_BASE_DURATION * 0.4)
				task.wait(PIANO_BASE_DURATION * (Token.multiplier or 1))
			elseif Token.type == "chord" then
				PressChord(Token.value, PIANO_BASE_DURATION * 0.4)
				task.wait(PIANO_BASE_DURATION * (Token.multiplier or 1))
			elseif Token.type == "pause" then
				task.wait(Token.value)
			end
		end
		PianoPlaying = false
		if PianoButton then PianoButton.Text = "PIANO: STOP" end
		StatusLabel.Text = "PIANO: песня закончена"
	end)
end

PianoButton.MouseButton1Click:Connect(PlayPiano)
PlayPianoButton.MouseButton1Click:Connect(PlayPiano)

--==================================================
-- MENU
--==================================================

local function SetMenuCollapsed(Collapsed)
	if MenuTweening then return end
	if Collapsed == MenuCollapsed then return end

	MenuTweening = true
	MenuCollapsed = Collapsed

	if Collapsed then
		HideButton.Text = "+"
		local FrameTween = TweenService:Create(
			MainFrame,
			ANIM.MenuClose,
			{ Size = UDim2.new(0, 420, 0, COLLAPSED_MENU_HEIGHT) }
		)
		FrameTween:Play()
		FrameTween.Completed:Connect(function(State)
			if State == Enum.PlaybackState.Completed then
				Content.Visible = false
			end
			MenuTweening = false
		end)
	else
		Content.Visible = true
		HideButton.Text = "-"
		if FreecamEnabled or SpectateEnabled or SpiroEnabled then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		local FrameTween = TweenService:Create(
			MainFrame,
			ANIM.MenuOpen,
			{ Size = UDim2.new(0, 420, 0, FULL_MENU_HEIGHT) }
		)
		FrameTween:Play()
		FrameTween.Completed:Connect(function(State)
			MenuTweening = false
		end)
	end
end

HideButton.MouseButton1Click:Connect(function()
	SetMenuCollapsed(not MenuCollapsed)
end)

--==================================================
-- KEYBOARD
--==================================================

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
	if WaitingForKey then
		if GameProcessed then return end
		if Input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		if Input.KeyCode == Enum.KeyCode.Escape then
			WaitingForKey = nil
			UpdateKeyButtons()
			return
		end

		local NewKey = Input.KeyCode
		local UsedBy = IsKeyAlreadyUsed(NewKey)

		if UsedBy and UsedBy ~= WaitingForKey then
			local Button = KeybindButtons[WaitingForKey]
			if Button then Button.Text = WaitingForKey .. ": уже занято" end
			task.delay(1, function()
				if WaitingForKey then UpdateKeyButtons() end
			end)
			return
		end

		if WaitingForKey == "SPIRO" then SPIRO_KEY = NewKey
		elseif WaitingForKey == "FLY" then FLY_KEY = NewKey
		elseif WaitingForKey == "ESP" then ESP_KEY = NewKey
		elseif WaitingForKey == "MENU" then MENU_KEY = NewKey
		elseif WaitingForKey == "FREECAM" then FREECAM_KEY = NewKey
		elseif WaitingForKey == "SPECTATE" then SPECTATE_KEY = NewKey
		elseif WaitingForKey == "PIANO" then PIANO_KEY = NewKey
		end

		WaitingForKey = nil
		UpdateKeyButtons()
		return
	end

	if GameProcessed then return end
	if Input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if Input.KeyCode == SPIRO_KEY then ToggleSpiro() return end
	if Input.KeyCode == FLY_KEY then ToggleFly() return end
	if Input.KeyCode == ESP_KEY then ToggleESP() return end
	if Input.KeyCode == MENU_KEY then SetMenuCollapsed(not MenuCollapsed) return end
	if Input.KeyCode == FREECAM_KEY then
		if ToggleFreecam then ToggleFreecam() end
		return
	end
	if Input.KeyCode == SPECTATE_KEY then
		if ToggleSpectate then ToggleSpectate() end
		return
	end
	if Input.KeyCode == PIANO_KEY then
		PlayPiano()
		return
	end
end)

--==================================================
-- ОСНОВНОЙ ЦИКЛ
--==================================================

RunService.Heartbeat:Connect(function(DeltaTime)
	UpdateFly()

	HealthAccumulator += DeltaTime
	if HealthAccumulator >= HEALTH_UPDATE_RATE then
		HealthAccumulator = 0
		UpdateESPHealth()
	end

	if not SpiroEnabled then return end
	if not TargetPlayer then StopSpiro() return end

	local TargetRoot = GetTargetRoot()
	if not TargetRoot then
		if not DeadHandled then DisableTargetBecauseDead() end
		return
	end

	if not RootPart then return end
	if not Humanoid or Humanoid.Health <= 0 then return end

	MovementAccumulator += DeltaTime
	if MovementAccumulator < (1 / MOVEMENT_UPDATE_RATE) then return end

	local MovementDelta = MovementAccumulator
	MovementAccumulator = 0

	local TargetPosition = TargetRoot.Position
	local DistanceFromTarget = (RootPart.Position - TargetPosition).Magnitude

	if DistanceFromTarget > TARGET_DISTANCE + 2 then
		MoveTowards(TargetPosition, APPROACH_SPEED, MovementDelta, TargetPosition)
		return
	end

	local Points = GetTrianglePoints(TargetPosition)
	local CurrentTargetPoint = Points[CurrentPoint]
	local DistanceToPoint = (RootPart.Position - CurrentTargetPoint).Magnitude

	if DistanceToPoint < 2 then
		CurrentPoint += 1
		if CurrentPoint > #Points then CurrentPoint = 1 end
		CurrentTargetPoint = Points[CurrentPoint]
	end

	MoveTowards(CurrentTargetPoint, ORBIT_SPEED, MovementDelta, TargetPosition)
end)

--==================================================
-- FREECAM
--==================================================

local function FreezeCharacter()
	if not RootPart or not RootPart.Parent then return end
	if not Humanoid or Humanoid.Health <= 0 then return end

	FreecamWasSpiroEnabled = SpiroEnabled
	FreecamWasFlyEnabled = FlyEnabled
	FreecamRootWasAnchored = RootPart.Anchored
	FreecamOldWalkSpeed = Humanoid.WalkSpeed
	FreecamOldJumpPower = Humanoid.JumpPower
	FreecamOldJumpHeight = Humanoid.JumpHeight

	if FlyEnabled then StopFly() end
	if SpiroEnabled then
		SpiroEnabled = false
		if SpiroCamOldCameraType and StopSpiroCamera then StopSpiroCamera() end
	end

	Humanoid.AutoRotate = false
	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0
	Humanoid.JumpHeight = 0
	RootPart.AssemblyLinearVelocity = Vector3.zero
	RootPart.AssemblyAngularVelocity = Vector3.zero
	RootPart.Anchored = true
end

local function UnfreezeCharacter()
	if not RootPart or not RootPart.Parent then return end
	if not Humanoid or not Humanoid.Parent then return end

	RootPart.Anchored = FreecamRootWasAnchored
	Humanoid.WalkSpeed = FreecamOldWalkSpeed
	Humanoid.JumpPower = FreecamOldJumpPower
	Humanoid.JumpHeight = FreecamOldJumpHeight
	Humanoid.AutoRotate = true

	if FreecamWasFlyEnabled and not FlyEnabled then StartFly() end

	if FreecamWasSpiroEnabled and not SpiroEnabled and TargetPlayer then
		SpiroEnabled = true
		DeadHandled = false
		CurrentPoint = 1
		MovementAccumulator = 0
		if SpiroButton then SpiroButton.Text = "SPIRO: ON" end
		Humanoid.AutoRotate = false
		if StartSpiroCamera then StartSpiroCamera() end
		StatusLabel.Text = "SPIRO активен: " .. TargetPlayer.Name
	end

	FreecamWasSpiroEnabled = false
	FreecamWasFlyEnabled = false
end

local function StartFreecam()
	if FreecamEnabled then return end
	if not RootPart or not Humanoid or Humanoid.Health <= 0 then return end

	local Camera = workspace.CurrentCamera
	if not Camera then return end

	FreecamEnabled = true
	if FreecamButton then FreecamButton.Text = "FREECAM: ON" end

	local Look = Camera.CFrame.LookVector
	FreecamYaw = math.atan2(-Look.X, -Look.Z)
	FreecamPitch = math.asin(math.clamp(Look.Y, -1, 1))

	FreecamCFrame = CFrame.new(Camera.CFrame.Position)
		* CFrame.Angles(0, FreecamYaw, 0)
		* CFrame.Angles(FreecamPitch, 0, 0)

	FreecamOldCameraType = Camera.CameraType
	FreecamOldCameraSubject = Camera.CameraSubject
	FreecamOldMouseBehavior = UserInputService.MouseBehavior
	FreecamOldMouseIconEnabled = UserInputService.MouseIconEnabled

	Camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	FreezeCharacter()
end

local function StopFreecam()
	if not FreecamEnabled then return end

	local Camera = workspace.CurrentCamera
	FreecamEnabled = false
	if FreecamButton then FreecamButton.Text = "FREECAM: OFF" end

	UnfreezeCharacter()

	if Camera then
		Camera.CameraType = FreecamOldCameraType or Enum.CameraType.Custom
		if FreecamOldCameraSubject then
			Camera.CameraSubject = FreecamOldCameraSubject
		elseif Humanoid then
			Camera.CameraSubject = Humanoid
		end
	end

	UserInputService.MouseBehavior = FreecamOldMouseBehavior or Enum.MouseBehavior.Default
	if FreecamOldMouseIconEnabled == nil then
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseIconEnabled = FreecamOldMouseIconEnabled
	end

	FreecamCFrame = nil
	FreecamOldCameraType = nil
	FreecamOldCameraSubject = nil
end

ToggleFreecam = function()
	if FreecamEnabled then
		StopFreecam()
	else
		if SpiroEnabled then StopSpiro() end
		if SpectateEnabled and StopSpectate then StopSpectate() end
		StartFreecam()
	end
end

FreecamButton.MouseButton1Click:Connect(function() ToggleFreecam() end)

RunService.RenderStepped:Connect(function(DeltaTime)
	if not FreecamEnabled then return end
	if SpiroEnabled then return end
	if SpectateEnabled then return end

	local Camera = workspace.CurrentCamera
	if not Camera or not FreecamCFrame then return end

	local MenuOpen = not MenuCollapsed

	if not MenuOpen then
		local Sensitivity = FREECAM_SENSITIVITY * FREECAM_ROTATION
		local MouseDelta = UserInputService:GetMouseDelta()
		FreecamYaw = FreecamYaw - MouseDelta.X * Sensitivity
		FreecamPitch = math.clamp(
			FreecamPitch - MouseDelta.Y * Sensitivity,
			-math.rad(89),
			math.rad(89)
		)
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
	end

	local Rotation = CFrame.Angles(0, FreecamYaw, 0) * CFrame.Angles(FreecamPitch, 0, 0)
	FreecamCFrame = CFrame.new(FreecamCFrame.Position) * Rotation

	local MoveDirection = Vector3.zero
	if not MenuOpen then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then MoveDirection += FreecamCFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then MoveDirection -= FreecamCFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then MoveDirection += FreecamCFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then MoveDirection -= FreecamCFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then MoveDirection += Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then MoveDirection -= Vector3.new(0, 1, 0) end
	end

	if MoveDirection.Magnitude > 0 then
		MoveDirection = MoveDirection.Unit
		local Speed = FREECAM_SPEED
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			Speed *= FREECAM_BOOST
		end
		FreecamCFrame = CFrame.new(FreecamCFrame.Position + MoveDirection * Speed * DeltaTime) * Rotation
	end

	Camera.CFrame = FreecamCFrame
end)

--==================================================
-- ЗАПУСК
--==================================================

print("KILL AURA + AUTO PIANO (4 СЛОТА) успешно запущен")
print("Меню центрировано, VIM защищён через pcall")
print("Клавиша PIANO: " .. PIANO_KEY.Name)