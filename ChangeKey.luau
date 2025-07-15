local to_shuffle = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()"
local function shuffleString(input)
	local characters = {}
	local result = {}
	for i = 1, #input do
		table.insert(characters, input:sub(i, i))
	end
	for i = #characters, 2, -1 do
		local j = math.random(1, i) 
		characters[i], characters[j] = characters[j], characters[i]
	end
	for _, char in ipairs(characters) do
		table.insert(result, char)
	end

	return table.concat(result)
end

math.randomseed(tick())

local shuffled = shuffleString(to_shuffle)
script.Parent.Key.Value = shuffled.."+/"
warn(script.Parent.Key.Value)
