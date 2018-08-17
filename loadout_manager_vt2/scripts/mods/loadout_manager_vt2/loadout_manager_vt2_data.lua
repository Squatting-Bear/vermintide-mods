local mod = get_mod("loadout_manager_vt2")

return {
	name = "Loadout Manager",       -- Readable mod name
	description = mod:localize("mod_description"),  -- Mod description
	is_togglable = true,            -- If the mod can be enabled/disabled
	is_mutator = false,             -- If the mod is mutator
	mutator_settings = {},          -- Extra settings, if it's mutator
	options_widgets = {},
}
