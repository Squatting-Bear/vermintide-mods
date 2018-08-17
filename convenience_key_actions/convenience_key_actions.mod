return {
	run = function()
		local is_vmf_loaded = rawget(_G, "new_mod")
		fassert(is_vmf_loaded, "Convenience Key Actions mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		if is_vmf_loaded then
			new_mod("convenience_key_actions", {
				mod_script       = "scripts/mods/convenience_key_actions/convenience_key_actions",
				mod_data         = "scripts/mods/convenience_key_actions/convenience_key_actions_data",
				mod_localization = "scripts/mods/convenience_key_actions/convenience_key_actions_localization"
			})
		end
	end,
	packages = {
		"resource_packages/convenience_key_actions/convenience_key_actions"
	}
}
