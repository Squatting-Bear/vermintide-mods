return {
	run = function()
		local is_vmf_loaded = rawget(_G, "new_mod")
		fassert(is_vmf_loaded, "Player List Plus mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		if is_vmf_loaded then
			new_mod("player_list_show_loadout", {
				mod_script       = "scripts/mods/player_list_show_loadout/player_list_show_loadout",
				mod_data         = "scripts/mods/player_list_show_loadout/player_list_show_loadout_data",
				mod_localization = "scripts/mods/player_list_show_loadout/player_list_show_loadout_localization"
			})
		end
	end,
	packages = {
		"resource_packages/player_list_show_loadout/player_list_show_loadout"
	}
}
