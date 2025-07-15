local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService('DataStoreService')

local IndexModule = require(script.Parent.Parent.IndexModule)

local DataManagement = {}

function DataManagement.GetDataId(DataIdStore)
	local key = "BBLITE_DATA"

	local success, result = pcall(function()
		return DataIdStore:GetAsync(key)
	end)

	if success then
		if result then
			return result
		else
			local newId = HttpService:GenerateGUID(false)

			pcall(function()
				DataIdStore:SetAsync(key, newId)
			end)

			return newId
		end
	else
		warn("DataStore error:", result)
		return nil
	end
end

function DataManagement.ChangeDataId(DataIdStore, DataId)
	local key = "BBLITE_DATA"
	
	local success, result = pcall(function()
		return DataIdStore:GetAsync(key)
	end)
	
	local NewDataId = DataId
	
	pcall(function()
		DataIdStore:SetAsync(key, NewDataId)
	end)
	
	return NewDataId
end

return DataManagement
