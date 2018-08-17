local mod = get_mod("convenience_key_actions")

mod.no_op = function() end

return {
	name = "Convenience Key Actions",               -- Readable mod name
	description = mod:localize("mod_description"),  -- Mod description
	is_togglable = true,                            -- If the mod can be enabled/disabled
	is_mutator = false,                             -- If the mod is mutator
	options_widgets = {                             -- Widget settings for the mod options menu
		{
			["setting_name"] = "continuous_attack_hotkey",
			["widget_type"] = "keybind",
			["text"] = mod:localize("continuous_attack_hotkey_text"),
			["tooltip"] = mod:localize("continuous_attack_hotkey_tooltip"),
			["default_value"] = {},
			["action"] = "no_op",
		},
		{
			["setting_name"] = "continuous_attack_block_option",
			["widget_type"] = "dropdown",
			["text"] = mod:localize("continuous_attack_block_option_text"),
			["tooltip"] = mod:localize("continuous_attack_block_option_tooltip"),
			["options"] = {
				{text = mod:localize("continuous_attack_block_option_block"), value = 1},
				{text = mod:localize("continuous_attack_block_option_push"), value = 2},
				{text = mod:localize("continuous_attack_block_option_pushattack"), value = 3},
			},
			["default_value"] = 2,
		},
		{
			["setting_name"] = "use_healing_item_hotkey",
			["widget_type"] = "keybind",
			["text"] = mod:localize("use_healing_item_hotkey_text"),
			["tooltip"] = mod:localize("use_healing_item_hotkey_tooltip"),
			["default_value"] = {},
			["action"] = "no_op"
		},
		{
			["setting_name"] = "drink_potion_hotkey",
			["widget_type"] = "keybind",
			["text"] = mod:localize("drink_potion_hotkey_text"),
			["tooltip"] = mod:localize("drink_potion_hotkey_tooltip"),
			["default_value"] = {},
			["action"] = "no_op"
		},
		{
			["setting_name"] = "throw_bomb_hotkey",
			["widget_type"] = "keybind",
			["text"] = mod:localize("throw_bomb_hotkey_text"),
			["tooltip"] = mod:localize("throw_bomb_hotkey_tooltip"),
			["default_value"] = {},
			["action"] = "no_op"
		},
	}
}
