--[[
	Creates a set of widgets (in the Fatshark sense) that can be used
	to display the contents of a loadout: gear, talents, and cosmetics.

	Returns an object containing a UI scenegraph ("scenegraph"),
	a collection of widgets for displaying a loadout ("fatshark_widgets"),
	and two functions for populating the widgets ("populate_items" for the
	gear and cosmetics, and "populate_talents" for the talents).
]]
return function(include_gear, include_talents, include_cosmetics)
	local width = 522
	local top_margin = 91
	local category_spacing = 47

	local gear_grid_spacing = 18
	local gear_icon_size = 80
	local gear_slot_count = #InventorySettings.equipment_slots
	local cosmetic_slot_count = 3

	-- Determine talent row height by scaling value from hero_window_talents_definitions (100)
	local talent_row_scaling = 0.475
	local talent_row_height = math.floor(100 * talent_row_scaling)
	local talent_row_x_offset = math.floor(26 * talent_row_scaling)
	local talent_row_spacing = 4

	local scenegraph_definition = {
		root = {
			is_root = true,
			size = { 1920, 1080 },
			position = { 0, 0, UILayer.default },
		},
		background_texture = {
			parent = "root",
			vertical_alignment = "center",
			horizontal_alignment = "center",
			size = { width, 654 },
			position = { 0, 83, 0 },
		},
		-- A row of icons showing the gear in the loadout
		gear_grid = {
			parent = "background_texture",
			vertical_alignment = "top",
			horizontal_alignment = "center",
			size = { width, gear_icon_size },
			position = { 0, -top_margin, 1 }
		},
		-- Five rows showing the selected talents in the loadout
		talent_row_1 = {
			parent = "gear_grid",
			vertical_alignment = "bottom",
			horizontal_alignment = "center",
			size = { width, talent_row_height },
			position = { talent_row_x_offset, -(talent_row_height + category_spacing), 0 },
		},
		talent_row_2 = {
			parent = "talent_row_1",
			vertical_alignment = "bottom",
			horizontal_alignment = "center",
			size = { width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_3 = {
			parent = "talent_row_2",
			vertical_alignment = "bottom",
			horizontal_alignment = "center",
			size = { width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_4 = {
			parent = "talent_row_3",
			vertical_alignment = "bottom",
			horizontal_alignment = "center",
			size = { width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		talent_row_5 = {
			parent = "talent_row_4",
			vertical_alignment = "bottom",
			horizontal_alignment = "center",
			size = { width, talent_row_height },
			position = { 0, -(talent_row_height + talent_row_spacing), 0 },
		},
		-- A row of icons showing the cosmetics in the loadout
		cosmetics_grid = {
			parent = "talent_row_5",
			vertical_alignment = "bottom",
			horizontal_alignment = "left",
			size = { width, gear_icon_size },
			position = { (-talent_row_x_offset - gear_icon_size - gear_grid_spacing), -(gear_icon_size + category_spacing), 0 },
		},
	}

	local fatshark_widgets = {}

	-- Background texture. "demo_bg_01" also looks ok, it's translucent.
	local background_widget = UIWidgets.create_background_with_frame("background_texture", {math.huge, math.huge}, "menu_frame_bg_04")
	fatshark_widgets.background = { background = UIWidget.init(background_widget) }

	-- Add the row of gear icons.
	if include_gear then
		local gear_icons = UIWidgets.create_loadout_grid("gear_grid", scenegraph_definition.gear_grid.size, gear_slot_count, gear_grid_spacing, true)
		fatshark_widgets.gear = { loadout_grid = UIWidget.init(gear_icons) }
	end

	-- Add the row of cosmetics icons.
	if include_cosmetics then
		local cosmetics_icons = UIWidgets.create_loadout_grid("cosmetics_grid", scenegraph_definition.cosmetics_grid.size, cosmetic_slot_count, gear_grid_spacing, true)
		fatshark_widgets.cosmetics = { loadout_grid = UIWidget.init(cosmetics_icons) }
	end

	-- Add the five rows of selected talents.
	if include_talents then
		-- Get a copy of the widgets from the talent selection screen.
		local raw_widgets = dofile("scripts/ui/views/hero_view/windows/definitions/hero_window_talents_definitions").widgets

		local function rescale_vector(vector)
			if vector and not vector.seen then
				vector[1] = math.ceil(vector[1] * talent_row_scaling)
				vector[2] = math.ceil(vector[2] * talent_row_scaling)
				vector.seen = true
			end
		end

		-- Extract the widgets we want, rescaling to our desired size as we go.
		local talents_widgets = {}
		for i = 1, 5 do
			local widget_name = ("talent_row_" .. tostring(i))
			local widget = raw_widgets[widget_name]
			for _, style in pairs(widget.style) do
				rescale_vector(style.size)
				rescale_vector(style.offset)
				if not style.texture_sizes then
					rescale_vector(style.texture_size)
				end
				if style.font_size then
					style.font_size = math.ceil(style.font_size * talent_row_scaling)
				end
			end
			talents_widgets[widget_name] = UIWidget.init(widget)
		end
		fatshark_widgets.talents = talents_widgets
	end

	return {
		scenegraph = UISceneGraph.init_scenegraph(scenegraph_definition),
		fatshark_widgets = fatshark_widgets,
		_equip_item_gear = HeroWindowLoadout._equip_item_presentation,
		_equip_item_cosmetics = HeroWindowCosmeticsLoadout._equip_item_presentation,
		_populate_talents_by_hero = HeroWindowTalents._populate_talents_by_hero,
		_clear_talents = HeroWindowTalents._clear_talents,
		_equipment_items = {},
		hero_level = 30,

		-- Populates the row of gear icons (or cosmetic icons) with the items from a loadout.
		populate_items = function(self, items_kind, item_ids_by_slot_name)
			self._widgets_by_name = self.fatshark_widgets[items_kind]
			local items_backend = Managers.backend:get_interface("items")
			local equipper_function = self[("_equip_item_" .. items_kind)]
			for _, slot in pairs(InventorySettings.slots_by_slot_index) do
				local item_backend_id = item_ids_by_slot_name[slot.name]
				local item = item_backend_id and items_backend:get_item_from_id(item_backend_id)
				if item then
					equipper_function(self, item, slot)
				end
			end
		end,

		-- Populates the rows of selected talents with the talents from a loadout.
		populate_talents = function(self, hero_name, career_index, selected_talents)
			self._widgets_by_name = self.fatshark_widgets.talents
			self.hero_name = hero_name
			self.career_index = career_index
			self._selected_talents = selected_talents
			self:_populate_talents_by_hero(false)
		end,
	}
end
