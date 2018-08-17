return {
	run = function()
		local is_vmf_loaded = rawget(_G, "new_mod")
		fassert(is_vmf_loaded, "Loadout Manager mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		if is_vmf_loaded then
			local mod_resources = {
				mod_script       = "scripts/mods/loadout_manager_vt2/loadout_manager_vt2",
				mod_data         = "scripts/mods/loadout_manager_vt2/loadout_manager_vt2_data",
				mod_localization = "scripts/mods/loadout_manager_vt2/loadout_manager_vt2_localization"
			}
			new_mod("loadout_manager_vt2", mod_resources)
		end
	end,
	packages = {
		"resource_packages/loadout_manager_vt2/loadout_manager_vt2"
	}
}
