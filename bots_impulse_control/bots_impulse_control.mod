return {
	run = function()
		local is_vmf_loaded = rawget(_G, "new_mod")
		fassert(is_vmf_loaded, "Impulse Control mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		if is_vmf_loaded then
			new_mod("bots_impulse_control", {
				mod_script       = "scripts/mods/bots_impulse_control/bots_impulse_control",
				mod_data         = "scripts/mods/bots_impulse_control/bots_impulse_control_data",
				mod_localization = "scripts/mods/bots_impulse_control/bots_impulse_control_localization"
			})
		end
	end,
	packages = {
		"resource_packages/bots_impulse_control/bots_impulse_control"
	}
}
