local mod = get_mod("player_list_show_loadout")

local TALENT_WIDGET_SCALING = 0.5

-- Holds CustomData objects from other players' items.  These objects contain
-- information about item traits and properties.
mod.custom_data_by_peer = {}

-- Holds talent loadout information from other players.
mod.talents_by_peer = {}

-- Perform initial setup.
mod.on_all_mods_loaded = function()
	mod:extract_talent_widgets()
end

-- Scales the given 2d vector by the given amount.  Also swaps the x and y axes
-- if swap_axes is true.
local function rescale_vector(vector, scaling, swap_axes)
	if vector and not vector.seen then
		local x = math.ceil(vector[1] * scaling)
		local y = math.ceil(vector[2] * scaling)
		vector[1] = (swap_axes and y) or x
		vector[2] = (swap_axes and -x) or y
		vector.seen = true
	end
end

-- Scales all the sizes and offsets in the given style value by the given amount.
-- Also swaps the x and y axes of offsets if swap_offset_axes is true.
local function rescale_style_value(style_value, scaling, swap_offset_axes)
	rescale_vector(style_value.size, scaling, false)
	rescale_vector(style_value.offset, scaling, swap_offset_axes)
	if not style_value.texture_sizes then
		rescale_vector(style_value.texture_size, scaling, false)
	end
	if style_value.font_size then
		style_value.font_size = math.ceil(style_value.font_size * scaling)
	end
end

-- Adds a content check function to the given widget pass that ensures it is only
-- shown if the associated hotspot is selected.
local function add_selection_check(pass, hotspot_id)
	if pass.pass_type ~= "hotspot" then
		local original_check = pass.content_check_function
		pass.content_check_function = function(content, ...)
			local hotspot = (pass.content_id and content) or content[hotspot_id]
			return hotspot.is_selected and (not original_check or original_check(content, ...))
		end
	end
end

-- Loads the Fatshark widgets used by the talent selection window in the hero view, and extracts
-- from them the ones that we need in order to display talents on the player list.  While doing
-- so the widgets are scaled and tweaked to make them do what we want.
mod.extract_talent_widgets = function(self)
	local raw_widgets = dofile("scripts/ui/views/hero_view/windows/definitions/hero_window_talents_definitions").widgets

	-- Get the widgets from each of the 5 talent rows.
	local talents_widgets = {}
	for i = 1, 5 do
		local widget_name = ("talent_row_" .. tostring(i))
		local raw_widget = raw_widgets[widget_name]
		local raw_style = raw_widget.style
		local raw_content = raw_widget.content
		local passes = {}
		local style = { level_text = {}, glow_frame = { color = {} } }
		local content = {}

		-- Traverse the widget's passes and gather the ones we want, as well as
		-- the styles and content to which they refer.
		for _, pass in ipairs(raw_widget.element.passes) do
			local style_id = pass.style_id
			local style_id_suffix = string.sub(style_id, -2)

			-- The ones we want end with suffixes like _1, _2, etc.
			if string.find(style_id_suffix, "_%d") then
				passes[#passes + 1] = pass
				content[style_id] = raw_content[style_id]

				-- We make all the passes of a given kind use the style from the first
				-- pass of that kind (i.e. the one with the "_1" suffix) so that all
				-- the talent boxes are drawn in the same place.
				local style_value = raw_style[(string.sub(style_id, 1, -3) .. "_1")]
				if style_id_suffix == "_1" then
					rescale_style_value(style_value, TALENT_WIDGET_SCALING)
				end
				style[style_id] = style_value

				-- Add a content check to ensure that only one talent box is drawn at any
				-- given time (i.e. the one for the hero's selected talent in that row).
				add_selection_check(pass, ("hotspot" .. style_id_suffix))
			end
		end

		local widget = {
			element = { passes = passes },
			content = content,
			style = style,
			offset = raw_widget.offset,
			scenegraph_id = raw_widget.scenegraph_id
		}
		talents_widgets[widget_name] = widget
	end
	self.talents_widgets = talents_widgets
end

-- Creates a scenegraph and set of widgets which can be used to display the gear and talents
-- of a single hero.
mod.create_loadout_display = function(self, player_list_scenegraph)
	local size = player_list_scenegraph.player_list.size

	local gear_icon_size = 80
	local gear_grid_size = { gear_icon_size, 300 }
	local gear_slot_count = #InventorySettings.equipment_slots
	local gear_grid_scaling = 0.605
	local gear_grid_spacing = 6
	local gear_hover_frame_size = 128

	-- Determine talent row height by scaling value from hero_window_talents_definitions (100)
	local talent_row_width = 200
	local talent_row_height = math.floor(100 * TALENT_WIDGET_SCALING)
	local talent_row_spacing = 2

	local scenegraph_definition = {
		root = {
			is_root = true,
			size = { 1920, 1080 },
			position = { 0, 0, UILayer.default },
		},
		working_area = {
			parent = "root",
			horizontal_alignment = "center",
			vertical_alignment = "center",
			size = { size[1], size[2] },
			position = { 0, 0, (UILayer.ingame_player_list + 1) },
		},
		-- A row of icons showing the gear in the loadout
		gear_grid = {
			parent = "working_area",
			horizontal_alignment = "center",
			vertical_alignment = "top",
			size = gear_grid_size,
			position = { 5, -4, 0 }
		},
		-- Five rows showing the selected talents in the loadout
		talent_row_1 = {
			parent = "working_area",
			horizontal_alignment = "center",
			vertical_alignment = "top",
			size = { talent_row_width, talent_row_height },
			position = { 98, -217, 0 },
		},
		talent_row_2 = {
			parent = "talent_row_1",
			horizontal_alignment = "center",
			vertical_alignment = "bottom",
			size = { talent_row_width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_3 = {
			parent = "talent_row_2",
			horizontal_alignment = "center",
			vertical_alignment = "bottom",
			size = { talent_row_width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_4 = {
			parent = "talent_row_3",
			horizontal_alignment = "center",
			vertical_alignment = "bottom",
			size = { talent_row_width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_5 = {
			parent = "talent_row_4",
			horizontal_alignment = "center",
			vertical_alignment = "bottom",
			size = { talent_row_width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
	}

	local widgets = {}

	-- Add the column of gear icons.  We do this by creating a row of them then swapping
	-- their x and y axes (while scaling them).  The create_loadout_grid function actually
	-- has an option to create a column, but using that gives the widgets different names
	-- than the names expected by HeroWindowLoadout._equip_item_presentation.
	local gear_icons = UIWidgets.create_loadout_grid("gear_grid", { gear_grid_size[2], gear_grid_size[1] }, gear_slot_count, gear_grid_spacing, true)
	for style_key, style_value in pairs(gear_icons.style) do
		-- Special adjustment for the hover frame - not entirely sure why this is
		-- necessary, I think maybe the frame image isn't centred within the texture.
		if string.find(style_key, "slot_hover_") then
			local offset = style_value.offset
			offset[1] = offset[1] + (gear_hover_frame_size - gear_icon_size)
		end

		rescale_style_value(style_value, gear_grid_scaling, true)
	end
	widgets.gear = { loadout_grid = UIWidget.init(gear_icons) }

	-- Add the five rows of selected talents.
	widgets.talents = {}
	for widget_name, widget in pairs(self.talents_widgets) do
		widgets.talents[widget_name] = UIWidget.init(table.clone(widget))
	end

	return {
		scenegraph = UISceneGraph.init_scenegraph(scenegraph_definition),
		widgets = widgets,
		_equip_item_gear = HeroWindowLoadout._equip_item_presentation,
		_populate_talents_by_hero = HeroWindowTalents._populate_talents_by_hero,
		_clear_talents = HeroWindowTalents._clear_talents,
		_equipment_items = {},
		hero_level = 30,

		-- Populates the column of gear icons with items obtained from the given extensions.
		populate_items = function(self, inventory_extn, attachment_extn, item_custom_data)
			self._widgets_by_name = self.widgets.gear
			local items_backend = Managers.backend:get_interface("items")
			for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
				local slot_data = inventory_extn:get_slot_data(slot.name) or attachment_extn:get_slot_data(slot.name)
				local slot_item = slot_data and slot_data.item_data
				if slot_item then
					local item = slot_item.backend_id and items_backend:get_item_from_id(slot_item.backend_id)
					if not item then
						-- Presumably this item is on a remote player; use the custom data sent
						-- by their instance of this mod, if they're running it.
						item = { CustomData = item_custom_data[slot.name], ItemId = slot_item.key }
						PlayFabMirror._update_data(nil, item)
					end
					self:_equip_item_gear(item, slot)
				end
			end
		end,

		-- Populates the column of selected talents with the given talents.
		populate_talents = function(self, hero_name, career_index, selected_talents)
			self._widgets_by_name = self.widgets.talents
			self.hero_name = hero_name
			self.career_index = career_index
			self._selected_talents = selected_talents
			self:_populate_talents_by_hero(false)
		end,
	}
end

-- Hook IngamePlayerListUI.update_widgets to set a flag indicating we need to update our widgets.
mod:hook_safe(IngamePlayerListUI, "update_widgets", function(self)
	mod.needs_widget_update = true
end)

-- Hook IngamePlayerListUI.update_player_information to update our widgets.  We do that here
-- instead of in our update_widgets hook because update_player_information sets up some stuff
-- we want to use (specifically, the x-offsets of the player areas in the UI).
mod:hook_safe(IngamePlayerListUI, "update_player_information", function(self)
	if mod.needs_widget_update then
		mod.needs_widget_update = false
		if not mod.loadout_displays then
			-- We haven't created our widgets yet, so do it now.
			local loadout_displays = {}
			for i = 1, MatchmakingSettings.MAX_NUMBER_OF_PLAYERS do
				loadout_displays[i] = mod:create_loadout_display(self.ui_scenegraph)
			end
			mod.loadout_displays = loadout_displays
		end

		local profiles = SPProfiles
		local profile_synchronizer = self.profile_synchronizer
		local players = self.players
		local working_area_x_offset = -250
		for i = 1, self.num_players do
			local player_data = players[i]

			-- Set the x-offsets of the player areas.
			local loadout_display = mod.loadout_displays[i]
			loadout_display.scenegraph.working_area.position[1] = (player_data.widget.offset[1] + working_area_x_offset)
			UISceneGraph.update_scenegraph(loadout_display.scenegraph)

			local player = player_data.player
			local player_unit = player.player_unit
			if Unit.alive(player_unit) then
				-- Populate the gear icons.
				local inventory_extn = ScriptUnit.extension(player_unit, "inventory_system")
				local attachment_extn = ScriptUnit.extension(player_unit, "attachment_system")
				local is_human = player:is_player_controlled()
				local item_custom_data = (is_human and mod.custom_data_by_peer[player.peer_id]) or {}
				loadout_display:populate_items(inventory_extn, attachment_extn, item_custom_data)

				-- Populate the talent boxes.
				local selected_talents
				if player.remote then
					selected_talents = (is_human and mod.talents_by_peer[player.peer_id]) or {}
				else
					local talents_backend = Managers.backend:get_interface("talents")
					local talent_extn = ScriptUnit.extension(player_unit, "talent_system")
					selected_talents = talents_backend:get_talents(talent_extn._career_name)
				end
				loadout_display:populate_talents(player_data.hero_name, player_data.career_index, selected_talents)
			end
		end
	end
end)

-- Hook IngamePlayerListUI.draw to draw our widgets.
mod:hook_safe(IngamePlayerListUI, "draw", function(self, dt)
	local loadout_displays = mod.loadout_displays
	if loadout_displays then
		local ui_renderer = self.ui_top_renderer
		local input_service = self.input_manager:get_service("player_list_input")
		local render_settings = self.render_settings
		for i = 1, self.num_players do
			local loadout_display = loadout_displays[i]
			UIRenderer.begin_pass(ui_renderer, loadout_display.scenegraph, input_service, dt, nil, render_settings)
			for _, widget_group in pairs(loadout_display.widgets) do
				for _, widget in pairs(widget_group) do
					UIRenderer.draw_widget(ui_renderer, widget)
				end
			end
			UIRenderer.end_pass(ui_renderer)
		end
	end
end)

-- Hook IngamePlayerListUI.set_active to set a flag indicating we need to update our
-- widgets, since players may have changed their loadouts since the last time the
-- player list was shown.
mod:hook_safe(IngamePlayerListUI, "set_active", function(self, is_active)
	if is_active then
		-- Update the widgets in case the player's loadout has changed.
		mod.needs_widget_update = true
	end
end)

-- Helper function to send the CustomData objects from the given items to other players.
local function network_send_custom_data(player, items_by_slot_name, peer_id)
	if not player.bot_player then
		local items_backend = Managers.backend:get_interface("items")
		local message_data = {}
		for slot_name, item_holder in pairs(items_by_slot_name) do
			if InventorySettings.slots_by_name[slot_name].ui_slot_index then
				local item_data = item_holder.item_data
				local item = item_data and item_data.backend_id and items_backend:get_item_from_id(item_data.backend_id)
				local custom_data = item and item.CustomData
				if custom_data then
					message_data[slot_name] = item.CustomData
				end
			end
		end
		mod:network_send("rpc_plsl_item_custom_data", (peer_id or "others"), message_data)
	end
end

-- Hook SimpleInventoryExtension.game_object_initialized to send CustomData from inventory
-- items to other players when we switch heroes.
mod:hook_safe(SimpleInventoryExtension, "game_object_initialized", function(self, unit, unit_go_id)
	network_send_custom_data(self.player, self._equipment.slots)
end)

-- Hook SimpleInventoryExtension._spawn_resynced_loadout to send CustomData from inventory
-- items to other players when we change our equipped items.
mod:hook_safe(SimpleInventoryExtension, "_spawn_resynced_loadout", function(self, equipment_to_spawn)
	network_send_custom_data(self.player, { [equipment_to_spawn.slot_id] = equipment_to_spawn })
end)

-- Hook PlayerUnitAttachmentExtension.game_object_initialized to send CustomData from attached
-- items to other players when we switch heroes.
mod:hook_safe(PlayerUnitAttachmentExtension, "game_object_initialized", function(self, unit, unit_go_id)
	network_send_custom_data(self._player, self._attachments.slots)
end)

-- Hook PlayerUnitAttachmentExtension.spawn_resynced_loadout to send CustomData from attached
-- items to other players when we change our equipped items.
mod:hook_safe(PlayerUnitAttachmentExtension, "spawn_resynced_loadout", function(self, item_to_spawn)
	network_send_custom_data(self._player, { [item_to_spawn.slot_id] = item_to_spawn })
end)

-- Add an RPC handler for receiving CustomData objects from other players.
mod:network_register("rpc_plsl_item_custom_data", function(sender_peer_id, new_custom_data)
	local custom_data = mod.custom_data_by_peer[sender_peer_id]
	if not custom_data then
		custom_data = {}
		mod.custom_data_by_peer[sender_peer_id] = custom_data
	end
	table.merge(custom_data, new_custom_data)
end)

-- Helper function to send our talent loadout to other players.
local function network_send_talents(player, career_name, peer_id)
	if not player.bot_player then
		local talents = Managers.backend:get_interface("talents"):get_talents(career_name)
		mod:network_send("rpc_plsl_player_talents", (peer_id or "others"), talents)
	end
end

-- Hook TalentExtension.game_object_initialized to send our talent loadout to other
-- players when we switch heroes.
mod:hook_safe(TalentExtension, "game_object_initialized", function(self, unit, unit_go_id)
	network_send_talents(self.player, self._career_name)
end)

-- Hook TalentExtension.talents_changed to send our talent loadout to other players when
-- we change our selected talents.
mod:hook_safe(TalentExtension, "talents_changed", function(self)
	network_send_talents(self.player, self._career_name)
end)

-- Add an RPC handler for receiving talent loadouts from other players.
mod:network_register("rpc_plsl_player_talents", function(sender_peer_id, talents)
	mod.talents_by_peer[sender_peer_id] = talents
end)

-- Handle the on_user_joined event so we can send our gear CustomData and talent loadout
-- to the player who just joined.
mod.on_user_joined = function(player)
	local our_player = Managers.player:local_player()
	local our_unit = our_player.player_unit
	if our_unit and Unit.alive(our_unit) then
		local peer_id = player.peer_id
		local inventory_extn = ScriptUnit.extension(our_unit, "inventory_system")
		network_send_custom_data(our_player, inventory_extn:equipment().slots, peer_id)

		local attachment_extn = ScriptUnit.extension(our_unit, "attachment_system")
		network_send_custom_data(our_player, attachment_extn:attachments().slots, peer_id)

		local talent_extn = ScriptUnit.extension(our_unit, "talent_system")
		network_send_talents(our_player, talent_extn._career_name, peer_id)
	end
end

-- Handle the on_user_left event to release the player's data for garbage collection.
mod.on_user_left = function(player)
	local peer_id = player.peer_id
	mod.custom_data_by_peer[peer_id] = nil
	mod.talents_by_peer[peer_id] = nil
end
