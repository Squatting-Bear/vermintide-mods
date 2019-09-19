local mod = get_mod("casual_mode")

-- Experimental hack to enable weave crafting in modded realm.
mod:hook(PlayFabRequestQueue, "enqueue", function(orig_func, self, request, success_callback, send_eac_challenge)
	local request_name = request.FunctionName
	local request_args = request.FunctionParameter
	if request_name == "upgradeCareerMagicLevel" then
		local result = {
			FunctionResult = {
				career_name = request_args.career_name,
				new_magic_level = request_args.new_magic_level,
				new_essence = 9999,
				upgrade_all_career_magic_levels = true,
			},
		}
		success_callback(result)

	elseif request_name == "upgradeItemMagicLevel" then
		local result = {
			FunctionResult = {
				item_backend_id = request_args.item_backend_id,
				new_magic_level = request_args.new_magic_level,
				new_essence = 9999,
			},
		}
		success_callback(result)

	elseif request_name == "buyMagicItem" then
		local result = {
			FunctionResult = {
				item_grant_results = {
					{
						ItemId = request_args.item_id,
						ItemInstanceId = Application.guid(),
						CustomData = {
							rarity = "magic",
							magic_level = "5",
						},
					},
				},
				new_essence = 9999,
			},
		}
		success_callback(result)

	elseif request_name == "upgradeWeaveForge" then
		local result = {
			FunctionResult = {
				new_forge_level = request_args.new_forge_level,
				new_essence = 9999,
			},
		}
		success_callback(result)

	else
		return orig_func(self, request, success_callback, send_eac_challenge)
	end
end)

--[[
__ todo
- support for unlocking cosmetics
]]
