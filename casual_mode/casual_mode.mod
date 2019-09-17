return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Casual Mode` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("casual_mode", {
			mod_script       = "scripts/mods/casual_mode/casual_mode",
			mod_data         = "scripts/mods/casual_mode/casual_mode_data",
			mod_localization = "scripts/mods/casual_mode/casual_mode_localization",
		})
	end,
	packages = {
		"resource_packages/casual_mode/casual_mode",
	},
}
