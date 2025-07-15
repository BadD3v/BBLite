local HttpService = game:GetService("HttpService")
local DataModule = require(script.BBLite_Functions)
local BBConfig = require(script.BBLite_Functions.BBConfig)

local DEFAULT_SLOT = 1
local CurrentSlot = script.BBLite_Functions.CurrentSlot.Value

game.Players.PlayerAdded:Connect(function(player)
	local data = DataModule.Load(player.UserId, DEFAULT_SLOT)
	
	if data then
		print("Loaded data for", player.Name, data)
	else
		print("No save found — starting new profile")
		DataModule.CreateData(player)
	end
	
	player:SetAttribute("Loaded", true)	
	DataModule.MonitorAndAutoSave(60)
end)

game.Players.PlayerRemoving:Connect(function(player)
	CurrentSlot = script.BBLite_Functions.CurrentSlot.Value

	local save = DataModule.Load(player.UserId, CurrentSlot)
	if not save then
		warn("No save found for userId", player.UserId, "slot", CurrentSlot)
		return
	end
end)

