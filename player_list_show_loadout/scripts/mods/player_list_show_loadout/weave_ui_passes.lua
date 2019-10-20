local Localize = Localize
local UIPasses = UIPasses
local get_text_height = UIUtils.get_text_height
local get_trait_description = UIUtils.get_trait_description

-- From DEFAULT_START_LAYER in ui_passes_tooltips.lua
local DEFAULT_START_LAYER = 994

-- Creates a brief description string for a given property on a weave item.
local function get_property_description(lerp_value, property_data)
	local description_text = Localize(property_data.display_name)
	local description_values = property_data.description_values
	if description_values then
        local display_value = math.abs(lerp_value * description_values[1].value)
        local value_type = description_values[1].value_type

        if value_type == "percent" then
			display_value = math.abs(100 * display_value)
		elseif value_type == "baked_percent" then
			display_value = math.abs(100 * (display_value - 1))
		end
		return string.format(description_text, display_value)
	end
    return description_text
end

-- Draws a weave item property in a tooltip (code is based on UITooltipPasses.properties).
UITooltipPasses.properties_weave_plsl = {
    setup_data = function ()
        local data = {
            frame_name = "item_tooltip_frame_01",
            background_color = { 240, 3, 3, 3 },
            title_text_pass_data = {
                text_id = "title",
            },
            text_pass_data = {},
            text_size = { 0, 0 },
            icon_pass_data = {},
            icon_pass_definition = {
                texture_id = "icon",
                style_id = "icon",
            },
            icon_size = { 13, 13 },
            content = {
                icon = "tooltip_marker",
                title = Localize("tooltips_properties") .. ":",
            },
            style = {
                property_title = {
                    vertical_alignment = "center",
                    horizontal_alignment = "left",
                    word_wrap = true,
                    font_type = "hell_shark",
                    font_size = 18,
                    text_color = Colors.get_color_table_with_alpha("font_default", 255),
                },
                property_text = {
                    vertical_alignment = "center",
                    horizontal_alignment = "left",
                    word_wrap = true,
                    font_type = "hell_shark",
                    font_size = 16,
                    text_color = Colors.get_color_table_with_alpha("corn_flower_blue", 255),
                    color_override = {},
                    color_override_table = {
                        start_index = 0,
                        end_index = 0,
                        color = Colors.get_color_table_with_alpha("font_default", 255),
                    },
                },
                property_advanced_description = {
                    vertical_alignment = "top",
                    horizontal_alignment = "left",
                    word_wrap = true,
                    font_type = "hell_shark",
                    font_size = 16,
                    text_color = Colors.get_color_table_with_alpha("font_default", 255),
                },
                icon = {
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 2 },
                },
            }
        }
        return data
    end,
    draw = function (data, draw, draw_downwards, ui_renderer, pass_data, ui_scenegraph, pass_definition, ui_style, ui_content, position, size, input_service, dt, ui_style_global, item)
        local alpha = 255 * pass_data.alpha_multiplier
        local start_layer = pass_data.start_layer or DEFAULT_START_LAYER
        local bottom_spacing = 20
        local frame_margin = data.frame_margin or 0
        local properties = item.properties
        local style = data.style
        local content = data.content
        local position_x = position[1]
        local position_y = position[2]
        local position_z = position[3]
        local total_height = 0
        position[3] = start_layer + 2
        local loop_func = pairs

        if properties then
            position[1] = position[1] + frame_margin
            local text_style = style.property_title
            local title_text_pass_data = data.title_text_pass_data
            local title_text = content.title
            local text_size = data.text_size
            text_size[1] = size[1] - (frame_margin * 2 + frame_margin)
            text_size[2] = 0
            local title_text_height = get_text_height(ui_renderer, text_size, text_style, title_text, ui_style_global)
            text_size[2] = title_text_height
            position[2] = position[2] - title_text_height
            total_height = total_height + title_text_height

            if draw then
                local text_color = text_style.text_color
                text_color[1] = alpha
                UIPasses.text.draw(ui_renderer, title_text_pass_data, ui_scenegraph, pass_definition, text_style, content, position, text_size, input_service, dt, ui_style_global)
            end

            local index = 1
            for property_key, property_values in loop_func(properties) do
                local property_data = WeaveProperties.properties[property_key]
                if not property_data then
                    break
                end
                local text_id = "property_title_" .. index
                local text_style = style.property_text
                local text_pass_data = data.text_pass_data
                text_pass_data.text_id = text_id
                local property_name = property_data.display_name
                local text = get_property_description(property_values, property_data)
                local text_length = (text and UTF8Utils.string_length(text)) or 0
                local color_override_table = text_style.color_override_table
                color_override_table.start_index = text_length + 1
                color_override_table.end_index = text_length
                text_style.color_override[1] = color_override_table
                local text_size = data.text_size
                text_size[2] = 0
                local text_height = get_text_height(ui_renderer, text_size, text_style, text, ui_style_global)
                text_size[2] = text_height
                position[2] = position[2] - text_height
                local old_y_position = position[2]
                content[text_id] = text

                if draw then
                    local icon_pass_definition = data.icon_pass_definition
                    local icon_pass_data = data.icon_pass_data
                    local icon_style = style.icon
                    local icon_size = data.icon_size
                    local icon_color = icon_style.color
                    icon_color[1] = alpha
                    position[2] = position[2] + (text_height * 0.5) - (icon_size[2] * 0.5 + 2)

                    UIPasses.texture.draw(ui_renderer, icon_pass_data, ui_scenegraph, icon_pass_definition, icon_style, content, position, icon_size, input_service, dt)

                    position[2] = old_y_position
                    position[1] = position[1] + icon_size[1]
                    local text_color = text_style.text_color
                    text_color[1] = alpha

                    UIPasses.text.draw(ui_renderer, text_pass_data, ui_scenegraph, pass_definition, text_style, content, position, data.text_size, input_service, dt, ui_style_global)

                    position[1] = position[1] - icon_size[1]
                end

                total_height = total_height + text_height
                position[2] = old_y_position
            end

            index = index + 1
            total_height = total_height + bottom_spacing
        end

        position[1] = position_x
        position[2] = position_y
        position[3] = position_z
        return total_height
    end
}

-- Draws a weave item trait in a tooltip (code is based on UITooltipPasses.traits).
UITooltipPasses.traits_weave_plsl = {
    setup_data = function ()
        local frame_name = "item_tooltip_frame_01"
        local frame_settings = UIFrameSettings[frame_name]
        local data = {
            default_icon = "icons_placeholder",
            frame_name = frame_name,
            background_color = { 240, 3, 3, 3 },
            text_pass_data = {},
            text_size = { 0, 0 },
            icon_pass_data = {},
            icon_pass_definition = {
                texture_id = "icon",
                style_id = "icon",
            },
            icon_size = { 40, 40 },
            frame_pass_data = {},
            frame_pass_definition = {
                texture_id = "frame",
                style_id = "frame",
            },
            frame_size = { 0, 0 },
            content = {
                icon = "icons_placeholder",
                frame = frame_settings.texture,
            },
            style = {
                trait_title = {
                    vertical_alignment = "center",
                    horizontal_alignment = "left",
                    word_wrap = true,
                    font_type = "hell_shark",
                    font_size = 16,
                    text_color = Colors.get_color_table_with_alpha("font_default", 255),
                    line_colors = {
                        Colors.get_color_table_with_alpha("font_title", 255),
                        Colors.get_color_table_with_alpha("font_default", 255),
                    },
                },
                trait_advanced_description = {
                    vertical_alignment = "top",
                    horizontal_alignment = "left",
                    word_wrap = true,
                    font_type = "hell_shark",
                    font_size = 16,
                    text_color = Colors.get_color_table_with_alpha("font_default", 255)
                },
                frame = {
                    texture_size = frame_settings.texture_size,
                    texture_sizes = frame_settings.texture_sizes,
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 1 },
                },
                icon = {
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 2 },
                },
                background = {
                    color = { 255, 10, 10, 10 },
                    offset = { 0, 0, 1 },
                }
            }
        }

        return data
    end,
    draw = function (data, draw, draw_downwards, ui_renderer, pass_data, ui_scenegraph, pass_definition, ui_style, ui_content, position, size, input_service, dt, ui_style_global, item)
        local alpha = 255 * pass_data.alpha_multiplier
        local start_layer = pass_data.start_layer or DEFAULT_START_LAYER
        local bottom_spacing = 20
        local top_spacing = 20
        local frame_margin = data.frame_margin or 0
        local traits = item.traits
        local total_height = 0

        if traits then
            local style = data.style
            local content = data.content
            local position_x = position[1]
            local position_y = position[2]
            local position_z = position[3]
            position[1] = position[1] + frame_margin
            position[2] = position[2]
            position[3] = start_layer + 2
            local trait_spacing = 10
            local loop_func = (draw_downwards and ipairs) or ripairs

            for index, trait_key in loop_func(traits) do
                local trait_data = WeaveTraits.traits[trait_key]
                if not trait_data then
                    break
                end
                local text_id = "trait_title_" .. index
                local text_style = style.trait_title
                local text_pass_data = data.text_pass_data
                text_pass_data.text_id = text_id
                local trait_name = trait_data.display_name
                local trait_has_description = trait_data.advanced_description
                local trait_icon = trait_data.icon
                local title_text = Localize(trait_name)
                local description_text = (trait_has_description and get_trait_description(trait_key, trait_data)) or ""
                local icon_pass_definition = data.icon_pass_definition
                local icon_pass_data = data.icon_pass_data
                local icon_style = data.style.icon
                local icon_size = data.icon_size
                content.icon = trait_icon or data.default_icon

                local text = title_text .. "\n" .. description_text
                local text_size = data.text_size
                text_size[1] = size[1] - frame_margin * 3 - icon_size[1]
                text_size[2] = 0
                local text_height = get_text_height(ui_renderer, text_size, text_style, text, ui_style_global)
                text_size[2] = text_height
                local old_x_position = position[1]
                local old_y_position = position[2]
                content[text_id] = text

                if draw then
                    local icon_color = icon_style.color
                    icon_color[1] = alpha
                    position[2] = old_y_position - icon_size[2]
                    position[1] = old_x_position

                    UIPasses.texture.draw(ui_renderer, icon_pass_data, ui_scenegraph, icon_pass_definition, icon_style, content, position, icon_size, input_service, dt)

                    position[2] = old_y_position - text_height
                    position[1] = old_x_position + icon_size[1] + frame_margin
                    local text_color = text_style.text_color
                    local line_colors = text_style.line_colors
                    text_color[1] = alpha
                    line_colors[1][1] = alpha
                    line_colors[2][1] = alpha

                    UIPasses.text.draw(ui_renderer, text_pass_data, ui_scenegraph, pass_definition, text_style, content, position, text_size, input_service, dt, ui_style_global)
                end

                total_height = total_height + text_height
                if index ~= #traits then
                    total_height = total_height + trait_spacing
                    position[2] = old_y_position - (text_height + trait_spacing)
                    position[1] = old_x_position
                end
            end

            position[1] = position_x
            position[2] = position_y
            position[3] = position_z
            total_height = total_height + bottom_spacing
        end
        return total_height
    end
}

local weave_content_passes = {
    "equipped_item_title",
    "item_titles",
    "skin_applied",
    "deed_mission",
    "deed_difficulty",
    "mutators",
    "deed_rewards",
    "ammunition",
    "fatigue",
    "item_power_level",
    "properties_weave_plsl",
    "traits_weave_plsl",
    "weapon_skin_title",
    "item_information_text",
    "loot_chest_difficulty",
    "loot_chest_power_range",
    "unwieldable",
    "keywords",
    "item_description",
    "light_attack_stats",
    "heavy_attack_stats",
    "detailed_stats_light",
    "detailed_stats_heavy",
    "detailed_stats_push",
    "detailed_stats_ranged_light",
    "detailed_stats_ranged_heavy",
}

-- Creates a loadout grid widget for weave items.
local function make_weave_loadout_grid(adventure_loadout_grid)
    local weave_loadout_grid = table.clone(adventure_loadout_grid)
    local passes = weave_loadout_grid.element.passes
    for i = 1, #passes do
        local pass = passes[i]
        if pass.pass_type == "item_tooltip" then
            pass.content_passes = weave_content_passes
        end
    end
    return weave_loadout_grid
end

return {
    make_weave_loadout_grid = make_weave_loadout_grid,
}
