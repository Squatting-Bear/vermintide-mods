local mod = get_mod("loadout_manager_vt2")
--[[
	Author: Squatting Bear

	Allows you to save and restore gear and talent loadouts.
--]]

local MAX_LOADOUTS = 10

mod.simple_ui = nil --get_mod("SimpleUI")
mod.button_theme = nil
mod.title_theme = nil
mod.cloud_file = nil
mod.loadouts_data = nil
mod.fatshark_view = nil
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

		-- Create a style for the title text of the loadout details window.
		local title_theme = table.merge(table.clone(button_theme), mod.simple_ui.themes.default.textbox)
		title_theme.font = title_font_name
		title_theme.color_text = Colors.get_color_table_with_alpha("font_title", 255)
		title_theme.shadow = { layers = 0 }
		mod.title_theme = title_theme
	else
		mod:echo("Loadout Manager error: missing dependency 'Simple UI'")
	end

	-- Create an object to access the file in which saved loadouts are kept.
	local CloudFile = mod:dofile("scripts/mods/loadout_manager_vt2/cloud_file")
	mod.cloud_file = CloudFile:new(mod, mod:get_name() .. ".data")

	mod.make_loadout_widgets = mod:dofile("scripts/mods/loadout_manager_vt2/make_loadout_widgets")
end

local function get_hero_and_career(fatshark_view)
	local profile_index = FindProfileIndex(fatshark_view.hero_name)
	local profile = SPProfiles[profile_index]
	local career_index = fatshark_view.career_index
	local career_name = profile.careers[career_index].name
	return fatshark_view.hero_name, career_name, career_index
end

local function get_gui_dimensions()
	local scale = UISettings.ui_scale / 100
	local gui_size = { math.floor(511 * scale), math.floor(694 * scale) }
	local gui_x_position = math.floor((UIResolutionWidthFragments() - gui_size[1])/2)
	local gui_y_position = math.floor((UIResolutionHeightFragments() - gui_size[2])/2 + 62*scale)
	local gui_position = { gui_x_position, gui_y_position }
	local loadout_buttons_height = math.floor(46 * scale)
	return gui_size, gui_position, loadout_buttons_height
end

-- Creates the small window showing a numbered button for each loadout.
mod.create_loadouts_window = function(self)
	if not self.loadouts_window and self.simple_ui then
		local gui_size, gui_position, loadout_buttons_height = get_gui_dimensions()
		local window_size = { gui_size[1], loadout_buttons_height }
		local window_position = { gui_position[1], gui_position[2] }
		local window_name = "loadoutmgr_loadouts"
		self.loadouts_window = self.simple_ui:create_window(window_name, window_position, window_size)

		local _, career_name = get_hero_and_career(self.fatshark_view)
		local on_button_click = function(event)
			local button_column = event.params
			mod:create_loadout_details_window(button_column)
		end

		-- Add a button for each loadout, clicking which will open the details
		-- window for that loadout.
		local ui_scale = UISettings.ui_scale / 100
		local button_size = { math.floor(33 * ui_scale), math.floor(33 * ui_scale) }
		local spacing = math.floor(10 * ui_scale)
		local margin = (window_size[1] - (MAX_LOADOUTS * button_size[1]) - ((MAX_LOADOUTS - 1) * spacing)) / 2
		local y_offset = (loadout_buttons_height - button_size[2]) / 2
		for button_column = 1, MAX_LOADOUTS do
			local x_offset = margin + (button_column - 1) * (button_size[1] + spacing);
			local column_string = tostring(button_column)
			local name = (window_name .. "_" .. column_string)
			local button = self.loadouts_window:create_button(name, {x_offset, y_offset}, button_size, nil, column_string, button_column)
			button.theme = self.button_theme
			button.on_click = on_button_click
			local loadout = self:get_loadout(button_column, career_name)
			button.tooltip = "   " .. ((loadout and loadout.name) or self:localize("loadout_details_title_default", button_column))
		end

		self.loadouts_window.on_hover_enter = function(window)
			window:focus()
		end
		self.loadouts_window:init()

		local theme = self.loadouts_window.theme
		theme.color = { 255, 10, 7, 4 }
		theme.color_hover = theme.color
	end
end

-- Creates the window containing the details for a single loadout.
mod.create_loadout_details_window = function(self, loadout_number)
	self:destroy_loadout_details_window()

	local hero_name, career_name, career_index = get_hero_and_career(self.fatshark_view)

	local gui_size, gui_position, loadout_buttons_height = get_gui_dimensions()
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

	local ui_scale = UISettings.ui_scale / 100
	local function scale(value) return math.floor(value * ui_scale) end

	-- Add the title textbox (shows the loadout name).
	local loadout = self:get_loadout(loadout_number, career_name)
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

	-- Add a button which saves the hero's currently equipped stuff into this loadout.
	local save_button = add_button("save_button", {(window_width - button_width)/2, (window_height - scale(80))})
	save_button.on_click = function()
		mod:save_loadout(loadout_number, career_name)
		mod:create_loadout_details_window(loadout_number, career_name)
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
		local delete_gear_button = add_button("delete_gear_button", {(window_width/2 + 5), (window_height - scale(206))})
		delete_gear_button.on_click = function()
			mod:modify_loadout(loadout_number, career_name, function(loadout)
				loadout.gear = nil
			end)
			mod:create_loadout_details_window(loadout_number, career_name)
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
		local delete_talents_button = add_button("delete_talents_button", {(window_width/2 + 5), scale(143)})
		delete_talents_button.on_click = function()
			mod:modify_loadout(loadout_number, career_name, function(loadout)
				loadout.talents = nil
			end)
			mod:create_loadout_details_window(loadout_number, career_name)
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
		local delete_cosmetics_button = add_button("delete_cosmetics_button", {(window_width-button_width - scale(28)), scale(58)})
		delete_cosmetics_button.on_click = function()
			mod:modify_loadout(loadout_number, career_name, function(loadout)
				loadout.cosmetics = nil
			end)
			mod:create_loadout_details_window(loadout_number, career_name)
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
	local widget_populator = mod.make_loadout_widgets(gear_loadout, talents_loadout, cosmetics_loadout)
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

-- Returns the loadout with the given loadout number, for the given career.
mod.get_loadout = function(self, loadout_number, career_name)
	return self.loadouts_data[(career_name .. "/" .. tostring(loadout_number))]
end

-- Modifies and saves the loadout with the given loadout number, for the given
-- career.  The existing loadout is passed to the given function (an empty loadout
-- is created if there isn't one) and then saved after it returns.
mod.modify_loadout = function(self, loadout_number, career_name, modifying_functor)
	local loadout = self:get_loadout(loadout_number, career_name)
	if not loadout then
		loadout = {}
		self.loadouts_data[(career_name .. "/" .. tostring(loadout_number))] = loadout
	end
	modifying_functor(loadout)

	self.cloud_file:cancel()
	self.cloud_file:save(self.loadouts_data)
end

-- Saves the given career's currently equipped gear, talents, and cosmetics to
-- the loadout with the given loadout number.
mod.save_loadout = function(self, loadout_number, career_name)
	local items_backend = Managers.backend:get_interface("items")
	local gear_loadout = {}
	local cosmetics_loadout = {}

	-- Add the current gear.
	for _, slot in ipairs(InventorySettings.slots_by_ui_slot_index) do
		local item_backend_id = items_backend:get_loadout_item_id(career_name, slot.name)
		if item_backend_id then
			gear_loadout[slot.name] = item_backend_id
		end
	end

	-- Add the current cosmetics.
	for _, slot in ipairs(InventorySettings.slots_by_cosmetic_index) do
		local item_backend_id = items_backend:get_loadout_item_id(career_name, slot.name)
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

-- Equips the given career's with the gear, talents, and cosmetics from the
-- loadout with the given loadout number.
mod.restore_loadout = function(self, loadout_number, career_name, exclude_gear, exclude_talents, exclude_cosmetics)
	local name = self:get_name()
	local loadout = self:get_loadout(loadout_number, career_name)
	if not loadout then
		self:echo("Error: loadout #"..tostring(loadout_number).." not found for career "..career_name)
		return
	end

	-- Restore talent selection (code based on HeroWindowTalents.on_exit)
	local talents_loadout = (not exclude_talents) and loadout.talents
	if talents_loadout then
		local talents_backend = Managers.backend:get_interface("talents")
		talents_backend:set_talents(career_name, talents_loadout)
		local unit = Managers.player:local_player().player_unit
		if unit and Unit.alive(unit) then
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
				local current_item_id = items_backend:get_loadout_item_id(career_name, slot.name)
				if not current_item_id or current_item_id ~= item_backend_id then
					equipment_queue[#equipment_queue + 1] = { slot = slot, item = item }
				end
			end
		end
	end
	self:echo("Loadout #"..tostring(loadout_number).." restored for hero "..career_name)
end

-- Hook HeroWindowCharacterPreview.on_enter() to show the loadouts window whenever
-- the "Equipment" or "Cosmetics" screens are shown.
local hook_HeroWindowCharacterPreview_on_enter = function(self)
	mod.fatshark_view = self
	mod.cloud_file:load(function(result)
		mod.loadouts_data = result.data or {}
		mod:reload_windows()
	end)
end

-- Hook HeroWindowCharacterPreview.on_exit() to hide our windows whenever
-- the "Equipment" or "Cosmetics" screens are hidden.
local hook_HeroWindowCharacterPreview_on_exit = function()
	mod:destroy_windows()
	mod.cloud_file:cancel()
	mod.loadouts_data = nil
	mod.fatshark_view = nil
end

-- Hook HeroWindowCharacterPreview.draw() to draw our collection of
-- Fatshark-style widgets.
local hook_HeroWindowCharacterPreview_draw = function(self, dt)
	local window = mod.loadout_details_window
	if window and window.fatshark_widgets then
		local ui_renderer = self.ui_top_renderer
		local input_service = self.parent:window_input_service()
		UIRenderer.begin_pass(ui_renderer, window.scenegraph, input_service, dt, nil, self.render_settings)
		for _, widget_group in pairs(window.fatshark_widgets) do
			for _, widget in pairs(widget_group) do
				UIRenderer.draw_widget(ui_renderer, widget)
			end
		end
		UIRenderer.end_pass(ui_renderer)
	end
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

-- Hook HeroViewStateOverview.post_update() to perform the actual equipping of
-- items when a loadout is restored, one at a time from the equipment queue.
mod:hook_safe(HeroViewStateOverview, "post_update", function(self, dt, t)
	local equipment_queue = mod.equipment_queue
	if equipment_queue[1] then
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
			local busy = inventory_extn:resyncing_loadout() or attachment_extn.resync_id or self.ingame_ui._respawning
			if not busy then
				-- We're good to go.
				local next_equip = equipment_queue[1]
				table.remove(equipment_queue, 1)
		
				local slot_type = next_equip.slot.type
				self:_set_loadout_item(next_equip.item, slot_type)
				if slot_type == ItemType.SKIN then
					self:update_skin_sync()
				end
			end
		end
	elseif mod.is_loading then
		-- We've finished equipping stuff, unblock input.
		mod.is_loading = false
		self:unblock_input()
	end
end)
