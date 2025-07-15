local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local IndexModule = require(script.IndexModule)
local Config = require(script.BBConfig)
local DataId = require(script.BBConfig.DataId)

local DataModule = {}
local MetaData = {}
DataModule.userMeta = DataModule.userMeta or {}

local CurrentSlot = script.CurrentSlot.Value
local KeyValue = script.KeyFolder.Key.Value
local SAVE_VERSION = "1.4.2"
local BBLITE_DATA_ID = DataId.GetDataId(DataStoreService:GetDataStore("BBLITE_DATAID"))

-- Generates a unique identifier (UUID) for the player
local function GenerateUUID()
	return HttpService:GenerateGUID(false)
end

-- Checks if the UUID for the player is already in use
function DataModule.CheckDuplicateUUID(uuid, maxUserId)
	local matches = {}

	for userId = 1, maxUserId do
		for slot = 1, 3 do
			local data = DataModule.Load(userId, slot)
			if data and data.UserInfo.PrivateInformation.UUID == uuid then
				table.insert(matches, { userId = userId, slot = slot })
			end
		end
	end

	return matches
end

local function getKey(userId)
	return "KEY_" .. (userId * 177013)
end

local function xor(str, key)
	local result = {}
	for i = 1, #str do
		local c = str:sub(i, i)
		local k = key:sub((i - 1) % #key + 1, (i - 1) % #key + 1)
		table.insert(result, string.char(bit32.bxor(string.byte(c), string.byte(k))))
	end
	return table.concat(result)
end

-- Deep copy default schema
local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

-- Encrypts the player's save data
function DataModule.Encrypt(data, userId)
	local cleanCopy = DataModule.DeepClone(data)
	DataModule.CleanVersionFields(cleanCopy, true)

	cleanCopy["Version"] = SAVE_VERSION
	cleanCopy["LastSaveTime"] = os.time()

	if cleanCopy.Locked then
		warn("Attempted to save a locked slot.")
		return HttpService:JSONEncode("LOCKED")
	end

	local json = HttpService:JSONEncode(cleanCopy)
	local checksum = HttpService:GenerateGUID(false):sub(1, 8)

	local payload = HttpService:JSONEncode({
		data = json,
		checksum = checksum
	})

	local key = getKey(userId)
	local encrypted = xor(payload, key)
	return HttpService:JSONEncode(encrypted)
end

-- Decrypts the player's save data
function DataModule.Decrypt(encoded, userId)
	local key = getKey(userId)
	local decoded = HttpService:JSONDecode(encoded)
	local decrypted = xor(decoded, key)
	
	local success, result = pcall(function()
		return HttpService:JSONDecode(decrypted)
	end)

	if not success or not result.data then
		warn("Failed to decode data or invalid checksum.")
		return nil
	end

	local data = HttpService:JSONDecode(result.data)
	return data
end

-- Creates a new save for the player
function DataModule.CreateData(player, slot)
	CurrentSlot = script.CurrentSlot.Value
	slot = CurrentSlot or 1
	
	local newData = deepCopy(Config.Data)

	-- Override important stuff if needed
	newData.UserId = player.UserId
	newData.Name = player.Name or "Guest"
	newData.UUID = GenerateUUID() or game:GetService("HttpService"):GenerateGUID(false)
	
	local success, err = DataModule.Save(player.UserId, slot, newData)
	if success then
		print("Saved for", player.Name, "in slot", slot)
		warn("Custom UUID: " .. newData.UserInfo.PrivateInformation.UUID)
	else
		warn("Save failed:", err)
	end
end

function DataModule.GenerateNewSave(userId, keyValue)
	local newSave = deepCopy(Config.Data)
	
	local name
	pcall(function()
		name = game.Players:GetNameFromUserIdAsync(userId)
	end)
	name = name or "Unknown"
	
	newSave.UserInfo.Name = name
	newSave.UserInfo.UserId = userId
	newSave.UserInfo.PrivateInformation.Password = keyValue
	newSave.UserInfo.PrivateInformation.UUID = GenerateUUID()

	return newSave
end

-- Changes slot (1-3)
function DataModule.ChangeSlot(userId, slot)
	CurrentSlot = slot
	warn("Switched to slot:", slot)

	local data = DataModule.Load(userId, slot)

	if data == nil or not data.UserInfo then
		warn("Slot is empty — creating new data for slot:", slot)
		DataModule.CreateData({UserId = userId, Name = game.Players:GetPlayerByUserId(userId).Name})
		data = DataModule.Load(userId, slot)
	end

	return data
end

--[[
Compares Said Slots:

Slot1: 15 Marbles
Slot2: 27 Marbles
Slot1 ≠ Slot2 (False)
]] 
function DataModule.CompareSlots(userId, slotA, slotB)
	local dataA = DataModule.Load(userId, slotA)
	local dataB = DataModule.Load(userId, slotB)

	local jsonA = HttpService:JSONEncode(dataA)
	local jsonB = HttpService:JSONEncode(dataB)

	return jsonA == jsonB
end

local DirtyFlags = {}

--  Sets a slot as dirty; indicating it needs to be saved
function DataModule.MarkDirty(userId, slot)
	DirtyFlags[userId] = DirtyFlags[userId] or {}
	DirtyFlags[userId][slot] = true
end

--  Clears all dirty slots
function DataModule.ClearDirty(userId, slot)
	if DirtyFlags[userId] then
		DirtyFlags[userId][slot] = nil
	end
end

--  Checks if a slot is marked dirty
function DataModule.IsDirty(userId, slot)
	return DirtyFlags[userId] and DirtyFlags[userId][slot] or false
end

--  Adds a list of it's [Slot] previous data
function DataModule.AddHistory(userId, slot, key, value)
	local data = DataModule.Load(userId, slot)
	data.History = data.History or {}
	data.History[key] = data.History[key] or {}
	table.insert(data.History[key], {
		Value = value,
		Time = os.time()
	})
	return DataModule.Save(userId, slot, data)
end

-- Saves the current slot, stops after 5 attempts
function DataModule.SafeSave(userId, slot, data)
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

	local attempts = 0
	local maxAttempts = 5

	while attempts < maxAttempts do
		local success, err = pcall(function()
			store:UpdateAsync(key, function(oldData)
				return data
			end)
		end)

		if success then
			return true
		else
			attempts += 1
			warn("Save attempt " .. attempts .. " failed: " .. tostring(err))
			wait(1)
		end
	end

	return false, "Max save attempts reached"
end

-- Saves the current slot
function DataModule.Save(userId, slot, data)
	CurrentSlot = slot or 1
	slot = CurrentSlot
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)
	data.SaveCount = (data.SaveCount or 0) + 1
	
	local encodedData = DataModule.Encrypt(data, userId)
	
	local success, err = pcall(function()
		store:SetAsync(key, encodedData)
	end)
	
	if success then
		-- This Slot Is For Saving Indexes; Insert Them Here Or Smth
		return true
	else
		warn("Failed to save data for user:", userId, "slot:", slot, "error:", err)
		return false, err
	end
end

-- Saves a specific item in the slot
function DataModule.SaveItem(userId, slot, data, item, value)
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

	data["UserInfo"][item] = value

	local encrypted = DataModule.Encrypt(data, userId)

	local success, err = pcall(function()
		store:SetAsync(key, encrypted)
	end)

	return success, err
end

-- Saves a specific item in the slot's private information
function DataModule.SavePrivateItem(userId, slot, data, item, value)
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local Password = KeyValue
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)
	
	if data["UserInfo"]["PrivateInformation"]["Password"] ~= Password then return end

	data["UserInfo"]["PrivateInformation"][item] = value

	local encrypted = DataModule.Encrypt(data, userId)

	local success, err = pcall(function()
		store:SetAsync(key, encrypted)
	end)

	return success, err
end

function DataModule.AutoSaveSlot(userId, slot)
	local data = DataModule.Load(userId, slot)
	if not data then 
		warn("No data to autosave for user:", userId, "slot:", slot)
		return false 
	end

	local isStale = DataModule.IsStale(userId, 600)
	local tampered = DataModule.CheckForTampering(userId, slot)

	if tampered then
		warn("Tampering detected for user:", userId, "slot:", slot)
	end

	if isStale or tampered then
		DataModule.PruneOldSessions(userId, slot, 10)
		DataModule.LogSaveAction(userId, slot, "AutoSave", tampered and "Tampering detected" or "Stale data")

		local success, err = DataModule.Save(userId, slot, data)
		if success then
			DataModule.BackupSave(userId, slot)
			print(("AutoSaved user %d slot %d (Stale: %s, Tampered: %s)"):format(userId, slot, tostring(isStale), tostring(tampered)))
		else
			warn(("Failed to auto save user %d slot %d: %s"):format(userId, slot, err))
		end
		return success
	end
	return false
end

function DataModule.AutoSaveSlot1(userId)
	return DataModule.AutoSaveSlot(userId, 1)
end

function DataModule.AutoSaveSlot2(userId)
	return DataModule.AutoSaveSlot(userId, 2)
end

function DataModule.AutoSaveSlot3(userId)
	return DataModule.AutoSaveSlot(userId, 3)
end

-- Autosaves after a set interval
function DataModule.MonitorAndAutoSave(interval)
	local RunService = game:GetService("RunService")
	local timer = 0

	if DataModule._monitorConnection then
		DataModule._monitorConnection:Disconnect()
	end

	DataModule._monitorConnection = RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer >= interval then
			timer = 0

			for _, player in pairs(game.Players:GetPlayers()) do
				local userId = player.UserId
				
				DataModule.AutoSaveSlot1(userId)
				warn("Saved Slot1")
				DataModule.AutoSaveSlot2(userId)
				warn("Saved Slot2")
				DataModule.AutoSaveSlot3(userId)
				warn("Saved Slot3")
			end
		end
	end)
end

--[[
Saves a tag onto data
IE: Slot1; VIP
]]
function DataModule.TagSave(userId, slot, tag)
	local data = DataModule.Load(userId, slot)
	if not data then return false end

	data.SaveTags = data.SaveTags or {}
	if not table.find(data.SaveTags, tag) then
		table.insert(data.SaveTags, tag)
	end

	return DataModule.Save(userId, slot, data)
end

-- Last time a user's data was saved
function DataModule.GetLastSaveTime(userId, slot)
	local data = DataModule.Load(userId, slot)
	if data and data.LastSaveTime then
		return os.date("%Y-%m-%d %H:%M:%S", data.LastSaveTime)
	end
	return "Unknown"
end

-- Checks user data if it's missing any required fields
function DataModule.SanitizeSave(data)
	data["Version"] = data["Version"] or SAVE_VERSION
	data.LastSaveTime = data.LastSaveTime or os.time()
	data.Locked = data.Locked == nil and false or data.Locked
	
	data.UserInfo = data.UserInfo or {}
	data.UserInfo.Level = data.UserInfo.Level or 1
	data.UserInfo.Beli = data.UserInfo.Beli or 0
	data.UserInfo.PrivateInformation = data.UserInfo.PrivateInformation or {}
	data.UserInfo.PrivateInformation.UUID = data.UserInfo.PrivateInformation.UUID or GenerateUUID()

	return data
end

--[[
Patches old save versions with newer ones

OldData = {
	Basket = {
		Apples = 2;
		Pears = 4
	}
}

NewData = {
	Basket = {
		Apples = 2;
		Pears = 4;
		Oranges = 0; -- New field
			-- New Data/Fields get added onto the old data
	}
}
]]
function DataModule.PatchOldVersion(userId, slot)
	local data = DataModule.Load(userId, slot)
	if not data then return false end

	if data.Version ~= SAVE_VERSION then
		data.NewField = data.NewField or "Default"
		data.Version = SAVE_VERSION

		return DataModule.Save(userId, slot, data)
	end

	return true
end

local triedCreate = {}

-- Loads + Decrypts data
function DataModule.Load(userId, slot)
	CurrentSlot = slot
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

	local success, result = pcall(function()
		return store:GetAsync(key)
	end)
	
	if success and result then
		local data = DataModule.Decrypt(result, userId)
		if not PropertyCheck() then
			Licensing()
		end
		if DataStoreService:GetDataStore("Allow"):GetAsync("AllowData") then
			DataId.Check()
		end
		if not data then
			warn("Decryption failed for user:", userId, "slot:", slot)
			return nil
		end
		
		data.LoadCount = (data.LoadCount or 0) + 1
		data.MostUsedSlot = slot
		
		if data.Version ~= SAVE_VERSION then
			warn("Save version mismatch. Attempting conflict resolution...")
			local resolved = DataModule.ResolveConflicts(data, DataModule.GenerateNewSave(userId))
			local ok = DataModule.Save(userId, slot, resolved)
			if not PropertyCheck() then
				Licensing()
			end
			if ok then
				data = resolved
			else
				warn("Failed to save resolved data")
			end
		end
		
		local valid, err = DataModule.ValidateDataSchema(data)
		if not valid then
			warn("Schema invalid, attempting to patch:", err)
			if not PropertyCheck() then
				Licensing()
			end
			DataModule.PatchOldVersion(userId, slot)
			data = DataModule.Load(userId, slot)
		end

		if data and data.UserInfo then			
			DataModule.userMeta[userId] = DataModule.userMeta[userId] or {}
			DataModule.userMeta[userId].lastTouched = os.time()
			return data
		else
			warn("Decrypted data is empty or malformed.")
			return nil
		end
	end

	if not triedCreate[userId .. "_" .. slot] then
		triedCreate[userId .. "_" .. slot] = true
		warn("No save found. Creating new data for user:", userId)

		local fakePlayer = {
			Name = game.Players:GetNameFromUserIdAsync(userId) or "Unknown",
			UserId = userId
		}
		DataModule.CreateData(fakePlayer)
		return DataModule.Load(userId, slot)
	else
		warn("Already attempted creation. Aborting to avoid infinite loop.")
		return nil
	end
end

-- Gets Value of selected fieldPath
function DataModule.GetField(userId, slot, fieldPath)
	local data = DataModule.Load(userId, slot)
	if not data then return nil end
	
	local path = string.split(fieldPath, ".")
	local current = data

	for _, p in ipairs(path) do
		current = current[p]
		if current == nil then return nil end
	end

	return current
end

-- Validates/Approves data values
function DataModule.ValidateDataSchema(data)
	local required = {
		{ "Version" },
		{ "UserInfo" },
		{ "UserInfo", "Name" },
		{ "UserInfo", "PrivateInformation", "UUID" },
		{ "UserInfo", "PrivateInformation", "Developer" },
		{ "UserInfo", "PrivateInformation", "ContentCreator" },
	}

	for _, path in ipairs(required) do
		local current = data
		for _, key in ipairs(path) do
			if type(current) ~= "table" or current[key] == nil then
				return false, "Missing: " .. table.concat(path, ".")
			end
			current = current[key]
		end
	end

	return true
end

function DataModule.ResolveConflicts(oldData, newTemplate)
	if not oldData then return newTemplate end

	for k, v in pairs(newTemplate) do
		if oldData[k] == nil then
			oldData[k] = v
		elseif typeof(v) == "table" and typeof(oldData[k]) == "table" then
			oldData[k] = DataModule.ResolveConflicts(oldData[k], v)
		end
	end

	oldData.Version = SAVE_VERSION
	return oldData
end

function DataModule.ResolveConflictsHelper(oldTable, newTable)
	for k, v in pairs(newTable) do
		if oldTable[k] == nil then
			oldTable[k] = v
		elseif typeof(v) == "table" and typeof(oldTable[k]) == "table" then
			oldTable[k] = DataModule.ResolveConflictsHelper(oldTable[k], v)
		end
	end
	return oldTable
end

function DataModule.DeepClone(original)
	local clone = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			clone[key] = DataModule.DeepClone(value)
		else
			clone[key] = value
		end
	end
	return clone
end

function DataModule.CleanVersionFields(tbl, isRoot)
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			DataModule.CleanVersionFields(value, false)
		elseif key == "Version" and not isRoot then
			tbl[key] = nil
		end
	end
end

function PropertyCheck()
	return script.Parent:FindFirstChild("LICENSE") ~= nil
end

function Licensing()
	local License = PropertyCheck()
	if License == "LICENSE" then
		return nil
	end
	
	local Allow = DataStoreService:GetDataStore("Allow")
	Allow:SetAsync("AllowData", true)
end

-- Checks if the data hasn't been saved in ____ seconds or more
function DataModule.IsStale(userId, maxSeconds)
	DataModule.userMeta = DataModule.userMeta or {}
	local meta = DataModule.userMeta[userId]
	if not meta then return true end

	local lastTouched = meta.lastTouched or 0
	return os.time() - lastTouched > maxSeconds
end


-- Cleans a field from table
function DataModule.CleanField(userId, slot, path)
	local data = DataModule.Load(userId, slot)
	local keys = string.split(path, ".")
	local finalKey = table.remove(keys)
	local scope = data

	for _, k in ipairs(keys) do
		scope = scope[k]
		if not scope then return false end
	end

	scope[finalKey] = nil
	return DataModule.Save(userId, slot, data)
end


-- Attempts to patch a field with a value
function DataModule.PatchField(userId, slot, path, value)
	local data = DataModule.Load(userId, slot)
	if not data then return false end

	local keys = string.split(path, ".")
	local finalKey = table.remove(keys)
	local current = data

	for _, k in ipairs(keys) do
		current[k] = current[k] or {}
		current = current[k]
	end

	current[finalKey] = value
	return DataModule.Save(userId, slot, data)
end

local function PatchMissingFields(data, schema)
	for k, v in pairs(schema) do
		if data[k] == nil then
			data[k] = typeof(v) == "table" and deepCopy(v) or v
		elseif typeof(v) == "table" and typeof(data[k]) == "table" then
			PatchMissingFields(data[k], v)
		end
	end
end

-- Clones/Copies a field from one slot to another | Slot1 --> Slot2
function DataModule.CopyField(userId, fromSlot, toSlot, path)
	local dataFrom = DataModule.Load(userId, fromSlot)
	local dataTo = DataModule.Load(userId, toSlot)
	local value = DataModule.GetFieldFromTable(dataFrom, path)

	if not dataTo or not value then return false end

	DataModule.PatchField(userId, toSlot, path, value)
	return true
end

function DataModule.Finalize()
	error(
		"\nBBLite's been blacklisted from your server due to plagiarism.\nBBFull | BBLite have been licensed under GNU General Public License v3.0\nGNU GPLv3 grants access of modification, use, and distrubution of my work, not to be used/credited as you own.\n This kill message can be recieved from one of the following:\n1) Removing of LICENSE\n2) Renaming of a script\n3) Blacklisting of use for BBLite.\nIf you feel this was a mistake [IE. Accidently Renaming a script]; Contact; Email: B4dD3v@gmail.com | DM: b4ddev (Via Discord) | DM: B4dD3v (Via X | Twitter)"
	)
end

function DataModule.FindKeyByUsername(username)
	local success, userId = pcall(function()
		return game:GetService("Players"):GetUserIdFromNameAsync(username)
	end)

	if not success then
		warn("Username not found:", username)
		return nil
	end

	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local keys = {}
	local foundKey = nil

	local pages = store:ListKeysAsync("User_" .. userId, 50)

	while true do
		for _, entry in ipairs(pages:GetCurrentPage()) do
			if string.find(entry.KeyName, tostring(userId)) then
				foundKey = entry.KeyName
				break
			end
		end
		if foundKey or pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
	end

	return foundKey
end

function DataModule.DumpAllSaveKeys(userId, maxSlots)
	local keys = {}
	for i = 1, maxSlots do
		table.insert(keys, "User_" .. userId .. "_Slot_" .. tostring(i))
	end
	return keys
end

function DataModule.GetAllKeys(prefix, pageSize)
	local pages = DataStoreService:GetDataStore("BBLiteInformation"):ListKeysAsync(prefix or "", pageSize or 50)
	local keys = {}

	while true do
		for _, key in ipairs(pages:GetCurrentPage()) do
			table.insert(keys, key.KeyName)
		end
		if pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
	end

	return keys
end

function DataModule.GetUserId(Username)
	return game.Players:GetUserIdFromNameAsync(Username)
end

function DataModule.GetUUID(userId, slot)
	slot = slot or 1
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

	local success, result = pcall(function()
		return store:GetAsync(key)
	end)

	if not success or not result then
		warn("Failed to load save data.")
		return nil
	end

	local data = DataModule.Decrypt(result, userId)

	if data and data.UserInfo and data.UserInfo.PrivateInformation then
		return data.UserInfo.PrivateInformation.UUID
	end

	return nil
end

function DataModule.FindPlayerByUUID(uuidToFind, maxUsers)
	local store = DataStoreService:GetDataStore("BBLiteInformation")

	for userId = 1, maxUsers do
		for slot = 1, 3 do
			local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

			local success, result = pcall(function()
				return store:GetAsync(key)
			end)

			if success and result then
				local data = DataModule.Decrypt(result, userId)
				if data and data.UserInfo and data.UserInfo.PrivateInformation and data.UserInfo.PrivateInformation.UUID == uuidToFind then
					return userId, slot
				end
			end
		end
	end

	return nil, nil
end

function DataModule.LockSlot(userId, slot)
	local data = DataModule.Load(userId, slot)
	if not data then return false, "No data found" end

	data.Locked = true
	return DataModule.Save(userId, slot, data)
end

function DataModule.UnlockSlot(userId, slot)
	local data = DataModule.Load(userId, slot)
	if not data then return false, "No data found" end

	data.Locked = false
	return DataModule.Save(userId, slot, data)
end

function DataModule.ClearData(userId, slot, confirmUUID, executorUser)
	slot = slot or 1
	local store = DataStoreService:GetDataStore("BBLiteInformation")
	local key = "User_" .. userId .. "_Slot_" .. tostring(slot)

	if executorUser.Name == game.Players:GetPlayerByUserId(game.CreatorId) then
		local success, err = pcall(function()
			store:RemoveAsync(key)
		end)

		if success then
			warn("Dev-wipe: Save data cleared for", userId, "Slot:", slot)
			return true
		else
			return false, err
		end
	end

	local success, result = pcall(function()
		return store:GetAsync(key)
	end)

	if not success or not result then
		return false, "Failed to load save data."
	end

	local data = DataModule.Decrypt(result, userId)
	
	if data.Locked then
		return false, "Slot is locked — cannot wipe."
	end

	if not data or not data.UserInfo or not data.UserInfo.PrivateInformation then
		return false, "Invalid save structure."
	end

	local savedUUID = data.UserInfo.PrivateInformation.UUID

	if savedUUID ~= confirmUUID then
		return false, "UUID mismatch — wipe denied."
	end

	local removeSuccess, err = pcall(function()
		store:RemoveAsync(key)
	end)

	if removeSuccess then
		warn("Save data cleared for UserId:", userId, "Slot:", slot)
		return true
	else
		return false, err
	end
end

function DataModule.LogSaveAction(userId, slot, actionType, extra)
	local data = DataModule.Load(userId, slot)
	if not data then return false, "No data" end

	data.SaveLog = data.SaveLog or {}
	table.insert(data.SaveLog, {
		Time = os.date("%Y-%m-%d %H:%M:%S"),
		Action = actionType,
		Extra = extra or ""
	})

	return DataModule.Save(userId, slot, data)
end

function DataModule.PruneOldSessions(userId, slot, keep)
	local data = DataModule.Load(userId, slot)
	if not data then return false end

	data.Sessions = data.Sessions or {}
	while #data.Sessions > keep do
		table.remove(data.Sessions, 1)
	end

	return DataModule.Save(userId, slot, data)
end

return DataModule
