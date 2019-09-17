local mod = get_mod("casual_mode")

return {
	name = "Casual Mode",
	description = mod:localize("mod_description"),
	is_togglable = false,
	options = {
		widgets = {
			{
				setting_id = "progression_enabled",
				type = "dropdown",
				title = "setting_enable_title",
				tooltip = "setting_enable_tooltip",
				options = {
						{ text = "setting_enable_option_simple", value = true, show_widgets = { 1 } },
						{ text = "setting_enable_option_none", value = false },
				},
				default_value = true,
				sub_widgets = {
					{
						setting_id = "use_official_progression",
						type = "checkbox",
						title = "setting_use_official_title",
						tooltip = "setting_use_official_tooltip",
						default_value = true,
					},
				},
			},
		},
	},
}
