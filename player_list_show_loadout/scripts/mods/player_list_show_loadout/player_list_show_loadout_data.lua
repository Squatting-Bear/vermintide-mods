local mod = get_mod("player_list_show_loadout")

-- Everything here is optional. You can remove unused parts.
return {
	name = "Player List Plus",                      -- Readable mod name
	description = mod:localize("mod_description"),  -- Mod description
	is_togglable = true,                            -- If the mod can be enabled/disabled
	is_mutator = false,                             -- If the mod is mutator
}
