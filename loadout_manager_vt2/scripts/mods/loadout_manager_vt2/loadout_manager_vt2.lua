local mod = get_mod("loadout_manager_vt2")
--[[
	Author: Squatting Bear

	Allows you to save and restore gear and talent loadouts.
--]]

local NUM_LOADOUT_BUTTONS = 10
local NUM_LOADOUTS_BUTTONS_PAGES = 3
local InventorySettings = InventorySettings
local SPProfiles = SPProfiles

-- Workaround for deletion (in patch 1.5) of a function required by SimpleUI.
UIResolutionScale = UIResolutionScale or UIResolutionScale_pow2

mod.simple_ui = nil --get_mod("SimpleUI")
mod.button_theme = nil
mod.title_theme = nil
mod.checkbox_theme = nil
mod.cloud_file = nil
mod.loadouts_data = nil
mod.fatshark_view = nil
mod.profile_picker_info = nil
mod.loadouts_window = nil
mod.loadout_details_window = nil
mod.equipment_queue = {}
mod.is_loading = false

-- Perform initial setup.
mod.on_all_mods_loaded = function()
	mod.simple_ui = get_mod("SimpleUI")
	if mod.simple_ui then
		-- Create the fonts we need.
		local normal_font_name = "loadoutmgr_font"
		mod.simple_ui.fonts:create(normal_font_name, "hell_shark", 13)
		local title_font_name = "loadoutmgr_title_font"
		mod.simple_ui.fonts:create(title_font_name, "hell_shark_header", 20)

		-- Create a style for buttons.
		local button_theme = table.clone(mod.simple_ui.themes.default.default)
		button_theme.font = normal_font_name
		button_theme.color = Colors.get_color_table_with_alpha("black", 255)
		button_theme.color_hover = button_theme.color
		button_theme.color_clicked = button_theme.color
		button_theme.color_text = Colors.get_color_table_with_alpha("font_button_normal", 255)
		button_theme.color_text_hover = Colors.get_color_table_with_alpha("white", 255)
		button_theme.color_text_clicked = Colors.get_color_table_with_alpha("font_default", 255)
		button_theme.shadow = { layers = 4, border = 0, color = Colors.get_color_table_with_alpha("white", 35) }
		mod.button_theme = button_theme

		-- Create a style for the next/prev loadouts page buttons.
		local change_page_button_theme = table.clone(button_theme)
		change_page_button_theme.shadow = { layers = 0 }
		mod.change_page_button_theme = change_page_button_theme

		-- Create a style for the title text of the loadout details window.
		local title_theme = table.merge(table.clone(button_theme), mod.simple_ui.themes.default.textbox)
		title_theme.font = title_font_name
		title_theme.color_text = Colors.get_color_table_with_alpha("font_title", 255)
		title_theme.shadow = { layers = 0 }
		mod.title_theme = title_theme

		-- Create a style for the checkbox in the loadout details window.
		local checkbox_theme = table.merge(table.clone(button_theme), mod.simple_ui.themes.default.checkbox)
		checkbox_theme.color = { 255, 40, 40, 40 }
		checkbox_theme.color_hover = checkbox_theme.color
		checkbox_theme.shadow.layers = 1
		mod.checkbox_theme = checkbox_theme
	else
		mod:echo("Loadout Manager error: missing dependency 'Simple UI'")
	end

	-- Create an object to access the file in which saved loadouts are kept.
	local CloudFile = mod:dofile("scripts/mods/loadout_manager_vt2/cloud_file")
	mod.cloud_file = CloudFile:new(mod, mod:get_name() .. ".data")
	mod.cloud_file:load(function(result)
		mod.loadouts_data = result.data or {}
	end)

	mod.make_loadout_widgets = mod:dofile("scripts/mods/loadout_manager_vt2/make_loadout_widgets")
end

-- Returns the hero name, career name, and career index of the career whose loadouts
-- should be displayed.
mod.get_hero_and_career = function(self)
	local fatshark_view = self.fatshark_view
	if self.profile_picker_info then
		local career = self.profile_picker_info.selected_career
		return self.profile_picker_info.selected_profile.name, career.name, career.index
	else
		local profile_index = FindProfileIndex(fatshark_view.hero_name)
		local profile = SPProfiles[profile_index]
		local career_index = fatshark_view.career_index
		local career_name = profile.careers[career_index].name
		return fatshark_view.hero_name, career_name, career_index
	end
end

-- Returns the size and position of the loadout buttons window.
mod.get_gui_dimensions = function(self)
	local scale = (UISettings.ui_scale or 100) / 100
	local gui_size = { math.floor(511 * scale), math.floor(694 * scale) }
	local align_right = not not self.profile_picker_info
	local gui_x_position = math.floor((UIResolutionWidthFragments() - gui_size[1]) / ((align_right and 1) or 2))
	local gui_y_position = math.floor((UIResolutionHeightFragments() - gui_size[2])/2 + 62*scale)
	local gui_position = { gui_x_position, gui_y_position }
	local loadout_buttons_height = math.floor(46 * scale)
	return gui_size, gui_position, loadout_buttons_height
end

-- Checks for mouse right-click events within the loadout buttons window
-- and propagates them to the appropriate widget.
local function dispatch_right_click(window)
	if stingray.Mouse.pressed(stingray.Mouse.button_id("right")) then
		local simple_ui = mod.simple_ui
		local position = simple_ui.mouse:cursor()
		for _, widget in pairs(window.widgets) do
			if simple_ui:point_in_bounds(position, widget:extended_bounds()) and widget.on_right_click then
				widget:on_right_click()
				break
			end
		end
	end
end

-- Creates the small window showing a numbered button for each loadout.
mod.create_loadouts_window = function(self)
	if not self.loadouts_window and self.simple_ui then
		local gui_size, gui_position, loadout_buttons_height = self:get_gui_dimensions()
		local window_size = { gui_size[1], loadout_buttons_height }
		local window_position = { gui_position[1], gui_position[2] }
		local window_name = "loadoutmgr_loadouts"
		self.loadouts_window = self.simple_ui:create_window(window_name, window_position, window_size)

		self.loadouts_window.loadouts_page_index = 0
		local compute_loadout_number = function(button_column)
			return (self.loadouts_window.loadouts_page_index * NUM_LOADOUT_BUTTONS) + button_column
		end

		local _, career_name = self:get_hero_and_career()
		local on_button_click = function(event)
			local button_column = event.params
			mod:create_loadout_details_window(compute_loadout_number(button_column))
		end
		local on_button_right_click = function(button)
			local button_column = button.params
			local loadout_number = compute_loadout_number(button_column)
			if self:get_loadout(loadout_number, career_name) then
				mod:restore_loadout(loadout_number, career_name)
				mod:destroy_loadout_details_window()
			end
		end

		-- Add a button for each loadout, clicking which will open the details
		-- window for that loadout.
		local ui_scale = (UISettings.ui_scale or 100) / 100
		local button_size = { math.floor(33 * ui_scale), math.floor(33 * ui_scale) }
		local spacing = math.floor(10 * ui_scale)
		local margin = (window_size[1] - (NUM_LOADOUT_BUTTONS * button_size[1]) - ((NUM_LOADOUT_BUTTONS - 1) * spacing)) / 2
		local y_offset = (loadout_buttons_height - button_size[2]) / 2
		local loadout_buttons = {}
		for button_column = 1, NUM_LOADOUT_BUTTONS do
			local x_offset = margin + (button_column - 1) * (button_size[1] + spacing);
			local name = (window_name .. "_" .. button_column)
			local button = self.loadouts_window:create_button(name, {x_offset, y_offset}, button_size, nil, "", button_column)
			button.theme = self.button_theme
			button.on_click = on_button_click
			button.on_right_click = on_button_right_click
			loadout_buttons[button_column] = button
		end

		-- Add buttons to move between 'pages' of loadout buttons.
		local btn_x = spacing
		local prev_page_button = self.loadouts_window:create_button((window_name .. "_prev_btn"), {btn_x, y_offset}, button_size, nil, "", -1)
		prev_page_button.theme = self.change_page_button_theme
		btn_x = window_size[1] - button_size[1] - spacing
		local next_page_button = self.loadouts_window:create_button((window_name .. "_next_btn"), {btn_x, y_offset}, button_size, nil, "", 1)
		next_page_button.theme = self.change_page_button_theme

		local set_button_texts = function()
			for button_column = 1, NUM_LOADOUT_BUTTONS do
				local button = loadout_buttons[button_column]
				local loadout_number = compute_loadout_number(button_column)
				button.text = tostring(loadout_number)
				local loadout = self:get_loadout(loadout_number, career_name)
				button.tooltip = "   " .. ((loadout and loadout.name) or self:localize("loadout_details_title_default", loadout_number))
			end
			prev_page_button.text = (self.loadouts_window.loadouts_page_index > 0 and "<<") or ""
			next_page_button.text = (self.loadouts_window.loadouts_page_index < (NUM_LOADOUTS_BUTTONS_PAGES - 1) and ">>") or ""
		end
		set_button_texts()

		local on_change_page_button_click = function(button)
			local new_index = self.loadouts_window.loadouts_page_index + button.params
			self.loadouts_window.loadouts_page_index = math.clamp(new_index, 0, NUM_LOADOUTS_BUTTONS_PAGES - 1)
			set_button_texts()
		end
		prev_page_button.on_click = on_change_page_button_click
		next_page_button.on_click = on_change_page_button_click

		self.loadouts_window.on_hover_enter = function(window)
			window:focus()
		end
		self.loadouts_window.after_update = dispatch_right_click
		self.loadouts_window:init()

		local theme = self.loadouts_window.theme
		theme.color = { 255, 10, 7, 4 }
		theme.color_hover = theme.color
	end
end

-- Creates the window containing the details for a single loadout.
mod.create_loadout_details_window = function(self, loadout_number)
	self:destroy_loadout_details_window()

	local hero_name, career_name, career_index = self:get_hero_and_career()
	local is_editable = not self.profile_picker_info

	local gui_size, gui_position, loadout_buttons_height = self:get_gui_dimensions()
	local window_height = gui_size[2] - loadout_buttons_height
	local window_width = gui_size[1]
	local window_size = { window_width, window_height }
	local window_position = { gui_position[1], (gui_position[2] + loadout_buttons_height) }
	local window_name = "loadoutmgr_loadout_details"
	local window = self.simple_ui:create_window(window_name, window_position, window_size)
	self.loadout_details_window = window

	-- We customize rendering of this window to avoid drawing a background.
	window.render = function(self)
		self:render_widgets()
	end

	local ui_scale = (UISettings.ui_scale or 100) / 100
	local function scale(value) return math.floor(value * ui_scale) end

	-- Add the title textbox (shows the loadout name).
	local loadout = self:get_loadout(loadout_number, career_name)
	if is_editable then
		local title_text = (loadout and loadout.name) or self:localize("loadout_details_title_default", loadout_number)
		local title = window:create_textbox((window_name .. "_title"), {scale(10), (window_height - scale(40))}, {(window_width - scale(20)), scale(30)}, nil, title_text)
		title.tooltip = self:localize("loadout_details_tooltip")
		title.theme = self.title_theme
		title.update_info = { original_text = title_text, original_unfocus = title.unfocus }
		title.unfocus = function(textbox)
			textbox.update_info.original_unfocus(textbox)
			if textbox.text ~= textbox.update_info.original_text then
				textbox.update_info.original_text = textbox.text
				mod:echo("Renaming loadout " .. tostring(loadout_number) .. " to " .. textbox.text)
				mod:modify_loadout(loadout_number, career_name, function(loadout)
					loadout.name = textbox.text
				end)
			end
		end
		title.on_text_changed = function(textbox)
			-- The loadout name is limited to 24 characters so it won't protrude from the window area.
			if string.len(textbox.text) > 24 then
				textbox.text = string.sub(textbox.text, 1, 24)
			end
		end
	end

	-- Helper function for adding a single button.
	local button_width = scale(150)
	local function add_button(id, position, omit_tooltip)
		local size = { button_width, scale(30) }
		local button_label = self:localize(id .. "_label")
		local button = window:create_button((window_name .. "_" .. id), position, size, nil, button_label)
		if not omit_tooltip then
			button.tooltip = self:localize(id .. "_tooltip")
		end
		button.theme = self.button_theme
		return button
	end

	if is_editable then
		-- Add a button which saves the hero's currently equipped stuff into this loadout.
		local save_button = add_button("save_button", {(window_width/3 - button_width/2), (window_height - scale(80))})
		save_button.on_click = function()
			mod:save_loadout(loadout_number, career_name)
			mod:create_loadout_details_window(loadout_number, career_name)
		end
	
		-- Add a checkbox which allows this loadout to be set as the 'bot override' loadout.
		local bot_override_size = {scale(25), scale(25)}
		local bot_override_pos = {(window_width*4/5 - button_width/2), (window_height - scale(80))}
		local bot_override_text = self:localize("bot_override_box_label")
		local bot_override_value = self:is_bot_override(loadout_number, career_name, hero_name)
		local bot_override_box = window:create_checkbox("bot_override_box", bot_override_pos, bot_override_size, nil, bot_override_text, bot_override_value)
		bot_override_box.theme = self.checkbox_theme
		bot_override_box.tooltip = self:localize("bot_override_box_tooltip")
		bot_override_box.on_value_changed = function()
			self:set_bot_override(loadout_number, career_name, hero_name, bot_override_box.value)
		end
	end

	-- Add a button for loading just the gear from this loadout, and a button for
	-- modifying this loadout so it doesn't contain gear.
	local gear_loadout = loadout and loadout.gear
	local talents_loadout = loadout and loadout.talents
	local cosmetics_loadout = loadout and loadout.cosmetics
	if gear_loadout then
		local restore_gear_button = add_button("restore_gear_button", {(window_width/2 - button_width - 5), (window_height - scale(206))})
		restore_gear_button.on_click = function()
			mod:restore_loadout(loadout_number, career_name, false, true, true)
			mod:destroy_loadout_details_window()
		end
		if is_editable then
			local delete_gear_button = add_button("delete_gear_button", {(window_width/2 + 5), (window_height - scale(206))})
			delete_gear_button.on_click = function()
				mod:modify_loadout(loadout_number, career_name, function(loadout)
					loadout.gear = nil
				end)
				mod:create_loadout_details_window(loadout_number, career_name)
			end
		end
	end

	-- Add a button for loading just the talents from this loadout, and a button for
	-- modifying this loadout so it doesn't contain talents.
	if talents_loadout then
		local restore_talents_button = add_button("restore_talents_button", {(window_width/2 - button_width - 5), scale(143)})
		restore_talents_button.on_click = function()
			mod:restore_loadout(loadout_number, career_name, true, false, true)
			mod:destroy_loadout_details_window()
		end
		if is_editable then
			local delete_talents_button = add_button("delete_talents_button", {(window_width/2 + 5), scale(143)})
			delete_talents_button.on_click = function()
				mod:modify_loadout(loadout_number, career_name, function(loadout)
					loadout.talents = nil
				end)
				mod:create_loadout_details_window(loadout_number, career_name)
			end
		end
	end

	-- Add a button for loading just the cosmetics from this loadout, and a button for
	-- modifying this loadout so it doesn't contain cosmetics.
	if cosmetics_loadout then
		local restore_cosmetics_button = add_button("restore_cosmetics_button", {(window_width-button_width - scale(28)), scale(99)})
		restore_cosmetics_button.on_click = function()
			mod:restore_loadout(loadout_number, career_name, true, true, false)
			mod:destroy_loadout_details_window()
		end
		if is_editable then
			local delete_cosmetics_button = add_button("delete_cosmetics_button", {(window_width-button_width - scale(28)), scale(58)})
			delete_cosmetics_button.on_click = function()
				mod:modify_loadout(loadout_number, career_name, function(loadout)
					loadout.cosmetics = nil
				end)
				mod:create_loadout_details_window(loadout_number, career_name)
			end
		end
	end

	-- Add a button for loading all the stuff from this loadout.
	if gear_loadout or talents_loadout or cosmetics_loadout then
		local restore_button = add_button("restore_button", {8, 13})
		restore_button.on_click = function()
			mod:restore_loadout(loadout_number, career_name)
			mod:destroy_loadout_details_window()
		end
	end

	-- Add a button for closing the window.
	local close_button = add_button("close_button", {(window_width - button_width - 8), 13}, true)
	close_button.on_click = function()
		mod:destroy_loadout_details_window()
	end

	-- Add the (fatshark) widgets that display the contents of this loadout.
	local widget_populator = mod.make_loadout_widgets(gear_loadout, talents_loadout, cosmetics_loadout, not not self.profile_picker_info)
	window.scenegraph = widget_populator.scenegraph
	window.fatshark_widgets = widget_populator.fatshark_widgets

	if gear_loadout then
		widget_populator:populate_items("gear", gear_loadout)
	end
	if talents_loadout then
		widget_populator:populate_talents(hero_name, career_index, talents_loadout)
	end
	if cosmetics_loadout then
		widget_populator:populate_items("cosmetics", cosmetics_loadout)
	end

	window.on_hover_enter = function(hovered_window)
		hovered_window:focus()
	end
	window:init()
end

-- Show the loadouts window, after closing any windows already open.
mod.reload_windows = function(self)
	self:destroy_windows()
	self:create_loadouts_window()
end

-- Closes any windows currently open.
mod.destroy_windows = function(self)
	self:destroy_loadout_details_window()
	if self.loadouts_window then
		self.loadouts_window:destroy()
		self.loadouts_window = nil
	end
end

-- Closes the loadout details window if currently open.
mod.destroy_loadout_details_window = function(self)
	if self.loadout_details_window then
		self.loadout_details_window:destroy()
		self.loadout_details_window = nil
	end
end

-- Returns the collection of loadouts relevant to the current game mode.
mod.get_loadouts = function(self)
	local data_root = self.loadouts_data
	if Managers.mechanism:current_mechanism_name() ~= "deus" then
		return data_root
	else
		local deus_loadouts = data_root.deus_loadouts
		if not deus_loadouts then
			deus_loadouts = {}
			data_root.deus_loadouts = deus_loadouts
		end
		return deus_loadouts
	end
end

-- Returns the loadout with the given loadout number, for the given career.
mod.get_loadout = function(self, loadout_number, career_name)
	return self:get_loadouts()[(career_name .. "/" .. tostring(loadout_number))]
end

-- Modifies and saves the loadout with the given loadout number, for the given
-- career.  The existing loadout is passed to the given function (an empty loadout
-- is created if there isn't one) and then saved after it returns.
mod.modify_loadout = function(self, loadout_number, career_name, modifying_functor)
	local loadout = self:get_loadout(loadout_number, career_name)
	if not loadout then
		loadout = {}
		self:get_loadouts()[(career_name .. "/" .. tostring(loadout_number))] = loadout
	end
	modifying_functor(loadout)

	self.cloud_file:cancel()
	self.cloud_file:save(self.loadouts_data)
end

-- Saves the given career's currently equipped gear, talents, and cosmetics to
-- the loadout with the given loadout number.
mod.save_loadout = function(self, loadout_number, career_name)
	local gear_loadout = {}
	local cosmetics_loadout = {}

	-- Add the current gear.
	for _, slot in ipairs(InventorySettings.slots_by_ui_slot_index) do
		local item_backend_id = BackendUtils.get_loadout_item_id(career_name, slot.name)
		if item_backend_id then
			gear_loadout[slot.name] = item_backend_id
		end
	end

	-- Add the current cosmetics.
	for _, slot in ipairs(InventorySettings.slots_by_cosmetic_index) do
		local item_backend_id = BackendUtils.get_loadout_item_id(career_name, slot.name)
		if item_backend_id then
			cosmetics_loadout[slot.name] = item_backend_id
		end
	end

	-- Add the current talents.
	local talents_backend = Managers.backend:get_interface("talents")
	local talents_loadout = table.clone(talents_backend:get_talents(career_name))

	self:modify_loadout(loadout_number, career_name, function(loadout)
		loadout.gear = gear_loadout
		loadout.talents = talents_loadout
		loadout.cosmetics = cosmetics_loadout
	end)
end

-- This check is required to eliminate a couple of exploits that allowed players to equip items on careers
-- for which they weren't intended.  (One exploit relied on quickly switching careers mid-restore, another
-- involved creating loadouts in the modded realm then using them in the official realm.)
local function is_equipment_valid(item, career_name, slot_name)
	-- First check that the current career can wield the item being equipped.
	local item_data = item.data
	local is_valid = table.contains(item_data.can_wield, career_name)
	if not is_valid then
		mod:echo("ERROR: cannot equip item " .. item_data.display_name .. " on career " .. career_name)
	else
		-- Also check that the item is going into an appropriate slot.
		local actual_slot_type = item_data.slot_type
		local expected_slot_type = InventorySettings.slots_by_name[slot_name].type
		is_valid = (actual_slot_type == expected_slot_type)

		if not is_valid and (career_name == "dr_slayer" or career_name == "es_questingknight") and expected_slot_type == ItemType.RANGED then
			-- Special case: Slayer and Grail Knight can equip a melee weapon in the ranged slot.
			is_valid = (actual_slot_type == ItemType.MELEE)
		end

		if not is_valid then
			mod:echo("ERROR: cannot equip item " .. item_data.display_name .. " in this slot type: " .. expected_slot_type)
		end
	end
	return is_valid
end

-- Equips the given career's with the gear, talents, and cosmetics from the
-- loadout with the given loadout number.
mod.restore_loadout = function(self, loadout_number, career_name, exclude_gear, exclude_talents, exclude_cosmetics)
	local name = self:get_name()
	local loadout = self:get_loadout(loadout_number, career_name)
	if not loadout then
		self:echo("Error: loadout #"..tostring(loadout_number).." not found for career "..career_name)
		return
	end
	local is_active_career = not self.profile_picker_info

	-- Restore talent selection (code based on HeroWindowTalents.on_exit)
	local talents_loadout = (not exclude_talents) and loadout.talents
	if talents_loadout then
		local talents_backend = Managers.backend:get_interface("talents")
		talents_backend:set_talents(career_name, talents_loadout)
		local unit = Managers.player:local_player().player_unit
		if unit and Unit.alive(unit) and is_active_career then
			ScriptUnit.extension(unit, "talent_system"):talents_changed()
			ScriptUnit.extension(unit, "inventory_system"):apply_buffs_to_ammo()
		end
	end

	-- Restore the gear and cosmetics. Part of each equipment change may be done
	-- asynchronously, so we add each item to a queue and perform the next change
	-- only when the current one is finished (in the hook of
	-- HeroViewStateOverview.post_update() below).
	local gear_loadout = (not exclude_gear) and loadout.gear
	local cosmetics_loadout = (not exclude_cosmetics) and loadout.cosmetics
	if gear_loadout or cosmetics_loadout then
		local equipment_queue = self.equipment_queue
		local items_backend = Managers.backend:get_interface("items")

		for _, slot in pairs(InventorySettings.slots_by_slot_index) do
			local item_backend_id = (gear_loadout and gear_loadout[slot.name]) or (cosmetics_loadout and cosmetics_loadout[slot.name])
			local item = item_backend_id and items_backend:get_item_from_id(item_backend_id)
			if item then
				local current_item_id = BackendUtils.get_loadout_item_id(career_name, slot.name)
				if not current_item_id or current_item_id ~= item_backend_id then
					if is_active_career then
						equipment_queue[#equipment_queue + 1] = { slot = slot, item = item }
					elseif is_equipment_valid(item, career_name, slot.name) then
						BackendUtils.set_loadout_item(item_backend_id, career_name, slot.name)
					end
				end
			end
		end
	end

	local completion_message = sprintf("Loadout #%d restored for hero %s", loadout_number, career_name)
	if #self.equipment_queue > 0 then
		self:echo(sprintf("Restoring loadout #%d for hero %s ...", loadout_number, career_name))
		self.completion_message = completion_message
	else
		self:echo(completion_message)
	end
end

-- Returns true if the given loadout is the currently selected 'bot override' for
-- the given career.
mod.is_bot_override = function(self, loadout_number, career_name, hero_name)
	local bot_overrides = self:get_loadouts().bot_overrides
	local hero_override = bot_overrides and bot_overrides[hero_name]
	return hero_override and (hero_override[1] == career_name) and (hero_override[2] == loadout_number)
end

-- Selects or deselects the given loadout as the 'bot override' for the given career.
mod.set_bot_override = function(self, loadout_number, career_name, hero_name, is_enabled)
	local bot_overrides = self:get_loadouts().bot_overrides
	if not bot_overrides then
		bot_overrides = {}
		self:get_loadouts().bot_overrides = bot_overrides
	end
	bot_overrides[hero_name] = (is_enabled and { career_name, loadout_number }) or nil

	self.cloud_file:cancel()
	self.cloud_file:save(self.loadouts_data)
end

-- Hook HeroWindowCharacterPreview.on_enter() to show the loadouts window whenever
-- the "Equipment" or "Cosmetics" screens are shown.
local hook_HeroWindowCharacterPreview_on_enter = function(self)
	mod.fatshark_view = self
	if mod.loadouts_data then
		mod:reload_windows()
	end
end

-- Hook HeroWindowCharacterPreview.on_exit() to hide our windows whenever
-- the "Equipment" or "Cosmetics" screens are hidden.
local hook_HeroWindowCharacterPreview_on_exit = function()
	mod:destroy_windows()
	mod.cloud_file:cancel()
	mod.fatshark_view = nil
end

-- Draws the fatshark-style widgets which are part of the loadout details
-- window.  Should be called on each update while that window is shown.
local function draw_fatshark_widgets(ui_renderer, render_settings, input_service, dt)
	local window = mod.loadout_details_window
	if window and window.fatshark_widgets then
		UIRenderer.begin_pass(ui_renderer, window.scenegraph, input_service, dt, nil, render_settings)
		for _, widget_group in pairs(window.fatshark_widgets) do
			for _, widget in pairs(widget_group) do
				UIRenderer.draw_widget(ui_renderer, widget)
			end
		end
		UIRenderer.end_pass(ui_renderer)
	end
end

-- Hook HeroWindowCharacterPreview.draw() to draw our collection of
-- Fatshark-style widgets.
local hook_HeroWindowCharacterPreview_draw = function(self, dt)
	draw_fatshark_widgets(self.ui_top_renderer, self.render_settings, self.parent:window_input_service(), dt)
end

local is_hero_preview_hooked = false

-- Hook HeroViewStateOverview._setup_menu_layout to add our hooks to the HeroWindowCharacterPreview
-- class, since it is lazy-loaded at that point.
mod:hook(HeroViewStateOverview, "_setup_menu_layout", function(hooked_function, ...)
	local use_gamepad_layout = hooked_function(...)
	if not use_gamepad_layout and not is_hero_preview_hooked then
		mod:hook_safe(HeroWindowCharacterPreview, "on_enter", hook_HeroWindowCharacterPreview_on_enter)
		mod:hook_safe(HeroWindowCharacterPreview, "on_exit", hook_HeroWindowCharacterPreview_on_exit)
		mod:hook_safe(HeroWindowCharacterPreview, "draw", hook_HeroWindowCharacterPreview_draw)
		is_hero_preview_hooked = true
	end
	return use_gamepad_layout
end)

-- -- Hook PopupProfilePicker.update to show the loadouts window for the
-- -- currently selected hero in the popup shown when an alternate hero must be
-- -- chosen while joining a game.
mod:hook_safe(PopupProfilePicker, "update", function(popup, dt, ...)
	local picker_info = mod.profile_picker_info
	if not picker_info then
		picker_info = {}
		mod.profile_picker_info = picker_info
		mod.fatshark_view = popup
	end

	if picker_info.selected_profile ~= popup._selected_profile or picker_info.selected_career ~= popup._selected_career then
		picker_info.selected_profile = popup._selected_profile
		picker_info.selected_career = popup._selected_career
		mod:destroy_windows()
		
		if not picker_info.selected_profile.unavailable and not picker_info.selected_career.locked then
			mod:create_loadouts_window()
		end
	end

	draw_fatshark_widgets(popup._ui_top_renderer, StrictNil, popup:input_service(), dt)
end)

-- Hook PopupProfilePicker.hide to hide the loadouts window when the popup goes away.
mod:hook_safe(PopupProfilePicker, "hide", function(self)
	mod:destroy_windows()
	mod.fatshark_view = nil
	mod.profile_picker_info = nil
end)

-- Checks whether the next item in the equipment queue can be validly equipped
-- in the specified slot by the current career.
local function is_next_equip_valid(next_equip)
	local fatshark_view = mod.fatshark_view
	if not fatshark_view then
		return false
	end

	local _, career_name = mod:get_hero_and_career()
	return is_equipment_valid(next_equip.item, career_name, next_equip.slot.name)
end

-- Hook HeroViewStateOverview.post_update() to perform the actual equipping of
-- items when a loadout is restored, one at a time from the equipment queue.
mod:hook_safe(HeroViewStateOverview, "post_update", function(self, dt, t)
	local equipment_queue = mod.equipment_queue
	local busy = false
	if equipment_queue[1] or mod.completion_message then
		-- Block input while we are processing the queue to prevent the
		-- hero view being closed while we're still equipping stuff.
		if not mod.is_loading then
			mod.is_loading = true
			self:block_input()
		end

		-- Check whether we're ready to equip the next item.
		local unit = Managers.player:local_player().player_unit
		if unit and Unit.alive(unit) then
			local inventory_extn = ScriptUnit.extension(unit, "inventory_system")
			local attachment_extn = ScriptUnit.extension(unit, "attachment_system")
			busy = inventory_extn:resyncing_loadout() or attachment_extn.resync_id or self.ingame_ui._respawning
			if not busy and equipment_queue[1] then
				-- We're good to go.
				local next_equip = equipment_queue[1]
				table.remove(equipment_queue, 1)
				busy = true

				if is_next_equip_valid(next_equip) then
					local slot = next_equip.slot
					self:_set_loadout_item(next_equip.item, slot.name)
					if slot.type == ItemType.SKIN then
						self:update_skin_sync()
					end
				end
			end
		end
	elseif mod.is_loading then
		-- We've finished equipping stuff, unblock input.
		mod.is_loading = false
		self:unblock_input()
	end

	-- Print the completion message once we're no longer busy.
	if mod.completion_message and not busy then
		mod:echo(mod.completion_message)
		mod.completion_message = nil
	end
end)

-- The number of 'bot override loadouts' currently in effect.
local bot_override_active_count = 0

-- When a 'bot override loadout' is in effect, this maps from career name to loadout.
local bot_override_loadouts = {}

-- Returns the index corresponding to the career with the given name.
local function get_career_index_from_name(profile, career_name)
	for career_index, career in ipairs(profile.careers) do
		if career.name == career_name then
			return career_index
		end
	end
	return nil
end

-- To implement bot override loadouts, we hook a few functions that may be called
-- frequently, so to save a bit of cpu when they're not in use we keep those hooks
-- disabled until we actually need them.
local function check_bot_override_hooks()
	if bot_override_active_count == 1 then
		mod:hook_enable(BackendUtils, "get_loadout_item")
		mod:hook_enable(BackendInterfaceTalentsPlayfab, "get_talents")
	elseif bot_override_active_count == 0 then
		mod:hook_disable(BackendUtils, "get_loadout_item")
		mod:hook_disable(BackendInterfaceTalentsPlayfab, "get_talents")
	end
end

-- Hook GameModeAdventure._get_first_available_bot_profile to put a bot override loadout
-- into effect if applicable for the bot.
local function on_bot_spawned(hooked_function, self)
	local profile_index, career_index = hooked_function(self)

	local profile = SPProfiles[profile_index]
	local hero_name = profile.display_name
	local bot_overrides = mod.loadouts_data and mod:get_loadouts().bot_overrides
	local bot_override = bot_overrides and bot_overrides[hero_name]

	if bot_override then
		local override_career_name = bot_override[1]
		career_index = get_career_index_from_name(profile, override_career_name)
		bot_override_active_count = bot_override_active_count + 1
		bot_override_loadouts[override_career_name] = mod:get_loadout(bot_override[2], override_career_name)
		check_bot_override_hooks()
	end
	return profile_index, career_index
end
mod:hook(GameModeAdventure, "_get_first_available_bot_profile", on_bot_spawned)
mod:hook(GameModeDeus, "_get_first_available_bot_profile", on_bot_spawned)

-- Hook GameModeAdventure._clear_bots to clear any bot override loadouts in use.
local function on_bots_cleared(self)
	bot_override_active_count = 0
	bot_override_loadouts = {}
	check_bot_override_hooks()
end
mod:hook_safe(GameModeAdventure, "_clear_bots", on_bots_cleared)
mod:hook_safe(GameModeDeus, "_clear_bots", on_bots_cleared)

-- Hook BackendUtils.get_loadout_item to return the equipment from the bot override
-- loadout if one is in effect.
mod:hook(BackendUtils, "get_loadout_item", function(hooked_function, career_name, slot_name)
	local override_loadout = bot_override_loadouts[career_name]
	if override_loadout then
		local backend_id = (override_loadout.gear and override_loadout.gear[slot_name]) or
				(override_loadout.cosmetics and override_loadout.cosmetics[slot_name])
		local item = backend_id and Managers.backend:get_interface("items"):get_item_from_id(backend_id)
		if item and is_equipment_valid(item, career_name, slot_name) then
			return item
		end
	end
	return hooked_function(career_name, slot_name)
end)

-- Hook BackendInterfaceTalentsPlayfab.get_talents to return the talents from the bot
-- override loadout if one is in effect.
mod:hook(BackendInterfaceTalentsPlayfab, "get_talents", function(hooked_function, self, career_name)
	local override_loadout = bot_override_loadouts[career_name]
	return (override_loadout and override_loadout.talents) or hooked_function(self, career_name)
end)

check_bot_override_hooks()
