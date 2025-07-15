local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local IndexModule = {}
IndexModule.IndexStores = {}

-- Get or create DataStore for group
function IndexModule:GetIndexStore(groupName)
	if not self.IndexStores[groupName] then
		self.IndexStores[groupName] = DataStoreService:GetDataStore("BBIndex_" .. groupName)
	end
	return self.IndexStores[groupName]
end

-- Fetch the index list from DataStore
function IndexModule:GetIndex(groupName)
	local store = self:GetIndexStore(groupName)
	local success, data = pcall(function()
		return store:GetAsync("UserIds")
	end)
	if success and data then
		return data
	end
	return {}
end

-- Save the index list to DataStore
function IndexModule:SetIndex(groupName, list)
	local store = self:GetIndexStore(groupName)
	local success, err = pcall(function()
		store:SetAsync("UserIds", list)
	end)
	if not success then
		warn("Failed to save index for group:", groupName, err)
	end
	return success
end

-- Add a userId to a group index (if not present)
function IndexModule:AddToGroupIndex(userId, groupName)
	local indexList = self:GetIndex(groupName)
	for _, id in ipairs(indexList) do
		if id == userId then
			return true
		end
	end
	table.insert(indexList, userId)
	return self:SetIndex(groupName, indexList)
end

-- Remove a userId from a group index
function IndexModule:RemoveFromGroupIndex(userId, groupName)
	local indexList = self:GetIndex(groupName)
	for i, id in ipairs(indexList) do
		if id == userId then
			table.remove(indexList, i)
			break
		end
	end
	return self:SetIndex(groupName, indexList)
end

-- Check if userId is in a group index
function IndexModule:IsUserInGroup(userId, groupName)
	local indexList = self:GetIndex(groupName)
	for _, id in ipairs(indexList) do
		if id == userId then return true end
	end
	return false
end

return IndexModule
