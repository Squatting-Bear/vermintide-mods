local mod = get_mod("bots_impulse_control")

-- Non-DRY with the same definitions in bots_impulse_control.lua.
local MANUAL_HEALING_DISABLED = 1
local MANUAL_HEALING_OPTIONAL = 2
local MANUAL_HEALING_MANDATORY = 3

return {
	name = "Bot Improvements - Impulse Control",    -- Readable mod name
	description = mod:localize("mod_description"),  -- Mod description
	is_togglable = true,                            -- If the mod can be enabled/disabled
	is_mutator = false,                             -- If the mod is mutator
	options_widgets = {                             -- Widget settings for the mod options menu
		{
			["setting_name"] = "no_chasing_specials",
			["widget_type"] = "checkbox",
			["text"] = mod:localize("no_chasing_specials_text"),
			["tooltip"] = mod:localize("no_chasing_specials_tooltip"),
			["default_value"] = false,
		},
		{
			["setting_name"] = "no_seeking_cover",
			["widget_type"] = "checkbox",
			["text"] = mod:localize("no_seeking_cover_text"),
			["tooltip"] = mod:localize("no_seeking_cover_tooltip"),
			["default_value"] = false,
		},
		{
			["setting_name"] = "no_reviving_bots",
			["widget_type"] = "checkbox",
			["text"] = mod:localize("no_reviving_bots_text"),
			["tooltip"] = mod:localize("no_reviving_bots_tooltip"),
			["default_value"] = false,
		},
		{
			["setting_name"] = "manual_healing",
			["widget_type"] = "dropdown",
			["text"] = mod:localize("manual_healing_text"),
			["tooltip"] = mod:localize("manual_healing_tooltip"),
			["options"] = {
					{ text = mod:localize("manual_healing_disabled"), value = MANUAL_HEALING_DISABLED },
					{ text = mod:localize("manual_healing_optional"), value = MANUAL_HEALING_OPTIONAL },
					{ text = mod:localize("manual_healing_mandatory"), value = MANUAL_HEALING_MANDATORY },
			},
			["default_value"] = MANUAL_HEALING_DISABLED,
			["sub_widgets"] = {
				{
					["show_widget_condition"] = { MANUAL_HEALING_OPTIONAL, MANUAL_HEALING_MANDATORY },
					["setting_name"] = "manual_healing_hotkey_1",
					["widget_type"] = "keybind",
					["text"] = mod:localize("manual_healing_hotkey_1_text"),
					["tooltip"] = mod:localize("manual_healing_hotkey_1_tooltip"),
					["default_value"] = { "numpad 0" },
					["action"] = "on_manual_heal_pressed",
				},
				{
					["show_widget_condition"] = { MANUAL_HEALING_OPTIONAL, MANUAL_HEALING_MANDATORY },
					["setting_name"] = "manual_healing_hotkey_2",
					["widget_type"] = "keybind",
					["text"] = mod:localize("manual_healing_hotkey_2_text"),
					["tooltip"] = mod:localize("manual_healing_hotkey_2_tooltip"),
					["default_value"] = { "numpad 1" },
					["action"] = "on_manual_heal_pressed",
				},
				{
					["show_widget_condition"] = { MANUAL_HEALING_OPTIONAL, MANUAL_HEALING_MANDATORY },
					["setting_name"] = "manual_healing_hotkey_3",
					["widget_type"] = "keybind",
					["text"] = mod:localize("manual_healing_hotkey_3_text"),
					["tooltip"] = mod:localize("manual_healing_hotkey_3_tooltip"),
					["default_value"] = { "numpad 2" },
					["action"] = "on_manual_heal_pressed",
				},
				{
					["show_widget_condition"] = { MANUAL_HEALING_OPTIONAL, MANUAL_HEALING_MANDATORY },
					["setting_name"] = "manual_healing_hotkey_4",
					["widget_type"] = "keybind",
					["text"] = mod:localize("manual_healing_hotkey_4_text"),
					["tooltip"] = mod:localize("manual_healing_hotkey_4_tooltip"),
					["default_value"] = { "numpad 3" },
					["action"] = "on_manual_heal_pressed",
				},
			},
		},
	}
}
