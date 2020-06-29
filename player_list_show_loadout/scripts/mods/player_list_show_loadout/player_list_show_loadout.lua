local mod = get_mod("player_list_show_loadout")

local weave_ui_passes = mod:dofile("scripts/mods/player_list_show_loadout/weave_ui_passes")

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

local weave_info_by_slot = {
	slot_necklace = {
		properties = table.set(WeaveProperties.categories.defence_accessory),
		traits = table.set(WeaveTraits.categories.defence_accessory),
		default_item_key = "necklace",
	},
	slot_ring = {
		properties = table.set(WeaveProperties.categories.offence_accessory),
		traits = table.set(WeaveTraits.categories.offence_accessory),
		default_item_key = "ring",
	},
	slot_trinket_1 = {
		properties = table.set(WeaveProperties.categories.utility_accessory),
		traits = table.set(WeaveTraits.categories.utility_accessory),
		default_item_key = "trinket",
	},
}

-- Fetches the item equipped in the given slot.
local function get_item_in_slot(slot_name, item_custom_data, inventory_extn, attachment_extn, is_for_display)
	local item = nil
	local is_in_weave = (Managers.state.game_mode:game_mode_key() == "weave")
	local weaves_backend = is_in_weave and Managers.backend:get_interface("weaves")

	if not is_in_weave or weaves_backend._valid_loadout_slots[slot_name] then
		local slot_data = inventory_extn:get_slot_data(slot_name) or attachment_extn:get_slot_data(slot_name)
		local slot_item = slot_data and slot_data.item_data
		if slot_item then
			if item_custom_data then
				-- This item is on a remote player; use the custom data sent
				-- by their instance of this mod, if they're running it.
				item = { CustomData = item_custom_data[slot_name], ItemId = slot_item.key }
				PlayFabMirrorBase._update_data(nil, item)
			else
				local items_backend = Managers.backend:get_interface("items")
				item = slot_item.backend_id and items_backend:get_item_from_id(slot_item.backend_id)

				if item and is_in_weave and not is_for_display and item.CustomData then
					-- We need to add this item's traits and properties to its CustomData
					-- object so they can be sent to remote players.
					item.CustomData.properties = (item.properties and cjson.encode(item.properties)) or nil
					item.CustomData.traits = (item.traits and cjson.encode(item.traits)) or nil
				end	
			end
		end
	else
		-- We are in a weave and this slot isn't actually used, since the 'amulet' defines
		-- those traits and properties instead.  We create a fake item containing the
		-- relevant traits and properties for display in the loadout grid.
		local weave_slot_info = weave_info_by_slot[slot_name]
		if item_custom_data then
			item = { CustomData = item_custom_data[slot_name], ItemId = weave_slot_info.default_item_key }
		else
			local career_name = inventory_extn.career_extension:career_name()
			local properties = weaves_backend:get_loadout_properties(career_name)
			local traits = weaves_backend:get_loadout_traits(career_name)

			local item_properties = {}
			local weave_properties_for_slot = weave_slot_info.properties
			for property_key, property_slots_allocated in pairs(properties) do
				if weave_properties_for_slot[property_key] then
					local costs = weaves_backend:get_property_mastery_costs(property_key)
					item_properties[property_key] = (#property_slots_allocated / #costs)
				end
			end

			local item_traits = {}
			local weave_traits_for_slot = weave_slot_info.traits
			for trait_key, _ in pairs(traits) do
				if weave_traits_for_slot[trait_key] then
					table.insert(item_traits, trait_key)
					inventory_icon = WeaveTraits.traits[trait_key].icon
				end
			end

			local encoded_props = next(item_properties) and cjson.encode(item_properties)
			local custom_data = { properties = (encoded_props or nil), traits = cjson.encode(item_traits) }
			item = { CustomData = custom_data, ItemId = weave_slot_info.default_item_key }
		end

		PlayFabMirrorBase._update_data(nil, item)
	end

	-- If the item is about to be displayed, we remove its slot_type to prevent the
	-- side-by-side comparison tooltip from showing.  Also, if it is a jewellery item
	-- we set the item icon to be the trait icon (if it has a trait).
	if item and is_for_display then
		item = table.clone(item)
		item.data.slot_type = nil
		if InventorySettings.slots_by_name[slot_name].category == "attachment" then
			local trait_key = item and item.traits and item.traits[1]
			if trait_key then
				item.data.inventory_icon = ((is_in_weave and WeaveTraits) or WeaponTraits).traits[trait_key].icon
			end
		end
	end
	return item
end

-- Fetches the items equipped in each slot.
local function get_items_by_slot(item_custom_data, inventory_extn, attachment_extn, is_for_display)
	local result = {}
	for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
		local item = get_item_in_slot(slot.name, item_custom_data, inventory_extn, attachment_extn, is_for_display)
		result[slot] = item
	end
	return result
end

-- Loads the Fatshark widgets used by the talent selection window in the hero view, and extracts
-- from them the ones that we need in order to display talents on the player list.  While doing
-- so the widgets are scaled and tweaked to make them do what we want.
mod.extract_talent_widgets = function(self)
	local raw_widgets = dofile("scripts/ui/views/hero_view/windows/definitions/hero_window_talents_definitions").widgets

	-- Get the widgets from each of the 6 talent rows.
	local talents_widgets = {}
	for i = 1, 6 do
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

	-- Determine talent row height by scaling value from hero_window_talents_definitions (80)
	local talent_row_width = 200
	local talent_row_height = math.floor(80 * TALENT_WIDGET_SCALING)
	local talent_row_spacing = 3

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
			position = { 0, 5, (UILayer.ingame_player_list + 1) },
		},
		-- A row of icons showing the gear in the loadout
		gear_grid = {
			parent = "working_area",
			horizontal_alignment = "center",
			vertical_alignment = "top",
			size = gear_grid_size,
			position = { 5, 0, 0 }
		},
		-- Five rows showing the selected talents in the loadout
		talent_row_1 = {
			parent = "working_area",
			horizontal_alignment = "center",
			vertical_alignment = "top",
			size = { talent_row_width, talent_row_height },
			position = { 98, -215, 0 },
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
		talent_row_6 = {
			parent = "talent_row_5",
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

	-- We need to use a different gear-icons widget depending on whether we are in
	-- weave mode or adventure mode.
	local gear_icons_weave = weave_ui_passes.make_weave_loadout_grid(gear_icons)
	gear_widgets = { loadout_grid_adv = UIWidget.init(gear_icons), loadout_grid_weave = UIWidget.init(gear_icons_weave) }
	widgets.gear = { }

	-- Add the five rows of selected talents.
	widgets.talents = {}
	for widget_name, widget in pairs(self.talents_widgets) do
		widgets.talents[widget_name] = UIWidget.init(table.clone(widget))
	end

	return {
		scenegraph = UISceneGraph.init_scenegraph(scenegraph_definition),
		widgets = widgets,
		gear_widgets = gear_widgets,
		_equip_item_gear = HeroWindowLoadout._equip_item_presentation,
		_populate_talents_by_hero = HeroWindowTalents._populate_talents_by_hero,
		_clear_talents = HeroWindowTalents._clear_talents,
		_equipment_items = {},
		hero_level = 35,

		-- Populates the column of gear icons with items obtained from the given extensions.
		populate_items = function(self, inventory_extn, attachment_extn, item_custom_data)
			self._widgets_by_name = self.widgets.gear
			local is_in_weave = (Managers.state.game_mode:game_mode_key() == "weave")
			local loadout_grid = (is_in_weave and self.gear_widgets.loadout_grid_weave) or self.gear_widgets.loadout_grid_adv
			self._widgets_by_name.loadout_grid = loadout_grid

			local items = get_items_by_slot(item_custom_data, inventory_extn, attachment_extn, true)
			for slot, item in pairs(items) do
				if item then
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
				local item_custom_data = player.remote and ((is_human and mod.custom_data_by_peer[player.peer_id]) or {})
				loadout_display:populate_items(inventory_extn, attachment_extn, item_custom_data)

				-- Populate the talent boxes.
				local selected_talents
				if player.remote then
					selected_talents = (is_human and mod.talents_by_peer[player.peer_id]) or {}
				else
					local talents_backend = Managers.backend:get_talents_interface()
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

		-- The MAX_NUMBER_OF_PLAYERS check is due to a bug in the game that sometimes
		-- causes num_players to be greater than the actual number of players.
		for i = 1, math.min(self.num_players, MatchmakingSettings.MAX_NUMBER_OF_PLAYERS) do
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
local function network_send_custom_data(player, items_by_slot, peer_id)
	if not player.bot_player then
		for slot, item in pairs(items_by_slot) do
			if slot.ui_slot_index and item.CustomData then
				local message_data = { [slot.name] = item.CustomData }
				mod:network_send("rpc_plsl_item_custom_data", (peer_id or "others"), message_data)
			end
		end
	end
end

-- Hook SimpleInventoryExtension._spawn_resynced_loadout to send CustomData from inventory
-- items to other players when we change our equipped items.
mod:hook_safe(SimpleInventoryExtension, "_spawn_resynced_loadout", function(self, equipment_to_spawn)
	local slot = InventorySettings.slots_by_name[equipment_to_spawn.slot_id]
	local attachment_extn = ScriptUnit.extension(self.player.player_unit, "attachment_system")
	local item = get_item_in_slot(slot.name, nil, self, attachment_extn, false)
	network_send_custom_data(self.player, { [slot] = item })
end)

-- Hook PlayerUnitAttachmentExtension.spawn_resynced_loadout to send CustomData from attached
-- items to other players when we change our equipped items.
mod:hook_safe(PlayerUnitAttachmentExtension, "spawn_resynced_loadout", function(self, item_to_spawn)
	local slot = InventorySettings.slots_by_name[item_to_spawn.slot_id]
	local inventory_extn = ScriptUnit.extension(self._player.player_unit, "inventory_system")
	local item = get_item_in_slot(slot.name, nil, inventory_extn, self, false)
	network_send_custom_data(self._player, { [slot] = item })
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
		local talents = Managers.backend:get_talents_interface():get_talents(career_name)
		mod:network_send("rpc_plsl_player_talents", (peer_id or "others"), talents)
	end
end

-- Sends our currently selected talents, and the custom data for all our equipped
-- items, to remote players.
local function network_send_everything(player, optional_peer_id)
	local our_unit = player.player_unit
	if our_unit then
		local peer_id = (optional_peer_id or "others")
		local inventory_extn = ScriptUnit.extension(our_unit, "inventory_system")
		local attachment_extn = ScriptUnit.extension(our_unit, "attachment_system")
		local items_by_slot = get_items_by_slot(nil, inventory_extn, attachment_extn, false)
		network_send_custom_data(player, items_by_slot, peer_id)

		local talent_extn = ScriptUnit.extension(our_unit, "talent_system")
		network_send_talents(player, talent_extn._career_name, peer_id)
	end
end

-- Hook BulldozerPlayer.spawn to send our talent loadout to other players when we
-- connect to a host, start a mission or switch heroes.
mod:hook_safe(BulldozerPlayer, "spawn", function(self, optional_position, optional_rotation, is_initial_spawn, ...)
	network_send_everything(self)
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

-- Handle the on_user_joined event so we can send our gear CustomData and talent loadout to
-- the player who just joined.  Note that if we're getting this notification because *we* just
-- connected, our player unit won't be set yet so network_send_everything will do nothing.
mod.on_user_joined = function(player)
	local our_player = Managers.player:local_player()
	network_send_everything(our_player, player.peer_id)
end

-- Handle the on_user_left event to release the player's data for garbage collection.
mod.on_user_left = function(player)
	local peer_id = player.peer_id
	mod.custom_data_by_peer[peer_id] = nil
	mod.talents_by_peer[peer_id] = nil
end
