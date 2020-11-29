local mod = get_mod("casual_mode")

-- Imports.
local ExtraWidgetsManager = mod:dofile("scripts/mods/casual_mode/extra_widgets_manager")
local crafting_handler = mod:dofile("scripts/mods/casual_mode/crafting_handler")
local user_progression = mod:dofile("scripts/mods/casual_mode/user_progression_data")
local widget_hacks = mod:dofile("scripts/mods/casual_mode/widget_hacks")
-- mod:dofile("scripts/mods/casual_mode/dev_stuff")

-- Cached references to global objects.
local ExperienceSettings = ExperienceSettings
local Localize = Localize
local Managers = Managers
local NumTalentColumns = NumTalentColumns
local NumTalentRows = NumTalentRows
local UIUtils = UIUtils
local WeaponTraits = WeaponTraits
local table = table

-- Cached setting value.
local setting_use_official_progress = false

mod.on_setting_changed = function()
	setting_use_official_progress = mod:get("use_official_progression")
	user_progression:set_progression_enabled(mod:get("progression_enabled"))
end

mod.on_all_mods_loaded = function()
	mod.on_setting_changed()
	crafting_handler.init(user_progression)
	mod.crafting_extra_info = {}
end

-- _________________________________________________________________________ --
-- FALSIFY HERO LEVEL

mod:hook(BackendInterfaceHeroAttributesPlayFab, "get", function(orig_func, self, hero, attribute)
	if attribute == "experience" then
		return ExperienceSettings.max_experience
	elseif attribute == "experience_pool" then
		return 0
	end
	return orig_func(self, hero, attribute)
end)

local function get_real_level(hero_name)
	local xp = Managers.backend:get_interface("hero_attributes")._attributes[hero_name .. "_experience"]
	return ExperienceSettings.get_level(xp)
end

-- Since the hero level isn't meaningful, show the available XP instead
-- in the inventory screen.
mod:hook_safe(HeroWindowOptions, "_update_experience_presentation", function (self)
	local text = mod:localize("available_xp_label", user_progression:get_available_xp())
	self._widgets_by_name.level_text.content.text = text
end)

-- Give user access to all difficulty levels.
mod:hook(BulldozerPlayer, "best_aquired_power_level", function(orig_func, self)
	return DifficultySettings.cataclysm_3.required_power_level
end)

-- _________________________________________________________________________ --
-- ENABLE CRAFTING IN MODDED REALM

-- Enable the "CRAFTING" button in the inventory screen.
mod:hook_safe(HeroWindowOptions, "create_ui_elements", function(self, ...)
	self._widgets_by_name.game_option_3.content.button_hotspot.disable_button = false
end)

-- Ensure that there are always enough crafting materials to perform the crafting
-- operations we support.
mod:hook(BackendInterfaceItemPlayfab, "get_item_amount", function(orig_func, self, backend_id)
	local item = self:get_item_from_id(backend_id)
	if item.data and item.data.item_type == "crafting_material" then
		return (item.data.name == "crafting_material_dust_4" and 0) or 10
	end
	return item.RemainingUses or 1
end)

-- _________________________________________________________________________ --
-- DISABLE UNUSED CRAFTING PAGES

-- These two hooks disable the unused crafting pages (convert dust, upgrade item),
-- but the implementation is kind of dodgy and may not be worth it if maintenance
-- becomes a hassle in the future.

mod:hook(HeroWindowCrafting, "on_enter", function(orig_func, self, ...)
	local ui_improvements_mod = get_mod("ui_improvements")
	if ui_improvements_mod and #ui_improvements_mod.button_list == 7 then
		table.remove(ui_improvements_mod.button_list, 7)
		table.remove(ui_improvements_mod.button_list, 5)
	end
	crafting_handler.ensure_crafting_materials_created()
	orig_func(self, ...)
	self:_change_recipe_page(2)
end)

mod:hook(HeroWindowCrafting, "_change_recipe_page", function(orig_func, self, current_page)
	if current_page == 5 then
		current_page = (self._current_page == 6 and 4) or 6
	elseif current_page == 7 then
		current_page = (self._current_page == 6 and 1) or 6
	end

	orig_func(self, current_page)

	if current_page > 5 then
		self._widgets_by_name.page_text_left.content.text = tostring(5)
	end
	self._widgets_by_name.page_text_right.content.text = tostring(5)
end)

-- _________________________________________________________________________ --
-- ADAPT INVENTORY ITEM GRID

local is_fake_items_only_page = {
	salvage = true,
	reroll_weapon_properties = true,
	reroll_weapon_traits = true,
	apply_weapon_skin = true,
}

-- Apply an extra filter in the item grid, so that only items created by this mod
-- will be shown in the grid for crafting pages that operate solely on "our" items.
mod:hook_safe(ItemGridUI, "init", function(self, category_settings, widget, hero_name, career_index)
	-- The item filter primitives (e.g. can_wield_by_current_career) are in backend_interface_common.lua.
	-- Unfortunately they're held in a local so we can't add our own.  The only one suitable
	-- for our purposes is 'is_fake_item' (but that's kind of appropriate I guess).
	if category_settings then
		for _, recipe in ipairs(category_settings) do
			if is_fake_items_only_page[recipe.name] then
				local item_filter = recipe.item_filter
				if not item_filter:find("is_fake_item") then
					recipe.item_filter = "is_fake_item and " .. item_filter
				end
			end
		end
	end
end)

-- When showing the 'craft item' page, replace the fatshark item grid widget with
-- one that supports our additional requirements.  Specifically, we add the
-- ability to show a 'lock' icon on locked weapon templates.
-- (See widget_hacks.make_hacked_item_grid_widget() for the code that makes the changes.)
mod:hook(HeroWindowInventory, "_change_category_by_name", function(orig_func, self, name)
	local function replace_item_grid_widget(new_item_grid_widget)
		local old_item_grid_widget = self._widgets_by_name.item_grid
		self._widgets_by_name.item_grid = new_item_grid_widget
		self._widgets[table.index_of(self._widgets, old_item_grid_widget)] = new_item_grid_widget
		self._item_grid._widget = new_item_grid_widget
	end

	if name == "craft_random_item" then
		-- We are showing the 'craft item' page, so replace the item grid with our
		-- hacked one.
		fassert(not self._mod_casual_data, "Extra data for Casual Mode mod already set.")
		self._mod_casual_data = {
			real_item_grid_widget = self._item_grid._widget,
			extra_widgets_mgr = ExtraWidgetsManager:new(self.parent.wwise_world)
		}
		replace_item_grid_widget(widget_hacks.make_hacked_item_grid_widget())

	elseif self._mod_casual_data then
		-- We are no longer showing the 'craft item' page, so restore the unhacked
		-- item grid.
		replace_item_grid_widget(self._mod_casual_data.real_item_grid_widget)
		self._mod_casual_data = nil
	end

	orig_func(self, name)
end)

mod:hook_safe(HeroWindowInventory, "on_exit", function(self, params)
	self._mod_casual_data = nil
end)

-- Helper function that prepares the arguments to be passed to
-- ExtraWidgetsManager.show_popup when showing an 'unlock feature' popup.
local function get_unlock_popup_args(feature_string_key, xp_cost, optional_popup_id)
	local popup_id = optional_popup_id or "unlock_popup"
	local feature_type = mod:localize(feature_string_key)
	local popup_title = mod:localize("unlock_popup_title", feature_type)
	local xp_available = user_progression:get_available_xp()
	local popup_text = mod:localize("unlock_popup_text", feature_type, xp_cost, xp_available)
	local cancel_button_text = Localize("popup_choice_cancel")
	local popup_args = { popup_id, popup_text, popup_title, "cancel", cancel_button_text }
	if xp_available >= xp_cost then
		table.insert(popup_args, 4, "unlock")
		table.insert(popup_args, 5, mod:localize("unlock_button_text"))
	end
	return popup_args
end

-- Handle mouse clicks on locked weapon templates, by showing a popup allowing the
-- user to unlock the clicked weapon.
mod:hook_safe(HeroWindowInventory, "_handle_input", function(self, dt, t)
	if self._mod_casual_data then
		local allow_single_press = true
		local clicked_item = self._item_grid:is_item_pressed(allow_single_press)
		if clicked_item and clicked_item.is_casual_locked then
			-- We will handle this click, so cancel the usual handling.
			self.parent:set_pressed_item_backend_id(nil)

			-- Show an 'unlock feature' popup.
			local xp_cost = user_progression:get_unlock_cost("weapon")
			local extra_widgets_mgr = self._mod_casual_data.extra_widgets_mgr
			extra_widgets_mgr.cb_unlock_popup = function(inner_self, result)
				if result == "unlock" then
					user_progression:unlock_feature(xp_cost, "weapons", clicked_item.key)
					clicked_item.is_casual_locked = nil

					-- The item we have is a clone of the real one, so get the real one
					-- from the backend (BackendInterfaceCommon.filter_items does the cloning).
					local backend_items = Managers.backend:get_interface("items")
					backend_items:get_item_from_id(clicked_item.backend_id).is_casual_locked = nil
				end
			end

			extra_widgets_mgr:show_popup(unpack(get_unlock_popup_args("the_weapon", xp_cost)))
		end

		-- Call ExtraWidgetsManager.handle_input to handle input to the popup.
		self._mod_casual_data.extra_widgets_mgr:handle_input(dt)
	end
end)

-- _________________________________________________________________________ --
-- NEW ITEM CRAFTING

local is_weapon_slot_type = {
	ranged = true,
	melee = true,
}

-- Helper function to hide the widgets that show crafting ingredients.
local function hide_recipe_grid(craft_page)
	for _, widget in ipairs(craft_page._widgets) do
		if widget.scenegraph_id == "recipe_grid" then
			widget.content.visible = false
		end
	end
end

-- Disable the ability to craft random items.
mod:hook_safe(CraftPageCraftItem, "setup_recipe_requirements", function(self)
	self._has_all_requirements = self._craft_items[1] and self._has_all_requirements
	self:_set_craft_button_disabled(not self._has_all_requirements)
end)

mod:hook_safe(CraftPageCraftItem, "create_recipe_grid_by_amount", function(self, amount)
	hide_recipe_grid(self)
end)

-- Add fake items for weapon templates the user doesn't have (i.e. hasn't unlocked
-- in the official realm).
mod:hook_safe(CraftPageCraftItem, "create_ui_elements", function(self, params)
	-- Get a list of all the weapon templates.
	local default_items = table.shallow_copy(UISettings.default_items)
	default_items["we_longbow_trueflight"] = nil
	local backend_items = Managers.backend:get_interface("items")

	-- Eliminate templates the user already has.
	local crafting_items = backend_items:get_filtered_items("can_craft_with")
	for _, crafting_item in ipairs(crafting_items) do
		default_items[crafting_item.key] = nil

		local real_item = backend_items:get_item_from_id(crafting_item.backend_id)
		if (not setting_use_official_progress) and is_weapon_slot_type[crafting_item.data.slot_type]
					and user_progression:is_feature_locked("weapons", crafting_item.key) then
			real_item.is_casual_locked = true
		else
			real_item.is_casual_locked = nil
		end
	end

	-- Add a fake item for each remaining template.
	self._mod_casual_weapon_templates = {}
	local backend_mirror = backend_items._backend_mirror
	for item_key, item_info in pairs(default_items) do
		local backend_id = Application.guid()
		local item = {
			ItemId = item_key,
			CustomData = {
				rarity = "default",
				power_level = "5",
			},
			-- If the weapon hasn't been unlocked in our progression, mark
			-- it as locked (a lock icon will be shown).
			is_casual_locked = user_progression:is_feature_locked("weapons", item_key),
		}
		self._mod_casual_weapon_templates[backend_id] = item
		crafting_handler.add_item_to_backend(backend_mirror, backend_id, item)
	end
end)

-- Clean up our stuff on exit.
mod:hook_safe(CraftPageCraftItem, "on_exit", function(self, params)
	local backend_mirror = Managers.backend:get_interface("items")._backend_mirror
	for backend_id, _ in pairs(self._mod_casual_weapon_templates) do
		backend_mirror:remove_item(backend_id)
	end
	self._mod_casual_weapon_templates = nil
end)

-- _________________________________________________________________________ --
-- MODIFY ITEM PROPERTIES

local lock_button_size = { 40, 40 }
local lock_button_x_offset = 240

local function get_craft_item(craft_page)
	local backend_items = Managers.backend:get_interface("items")
	local item_backend_id = craft_page._craft_items[1]
	return item_backend_id and backend_items:get_item_from_id(item_backend_id)
end

-- Returns a list of all the properties that are contained in the property table
-- with the given name, optionally excluding those which don't appear in combination
-- with a given companion_property.
local function get_possible_properties(property_table_name, companion_property)
	local combinations = WeaponProperties.combinations[property_table_name].exotic
	local result = {}
	for _, combination in ipairs(combinations) do
		if not companion_property then
			result[combination[1]] = true
			result[combination[2]] = true
		elseif companion_property == combination[1] then
			result[combination[2]] = true
		elseif companion_property == combination[2] then
			result[combination[1]] = true
		end
	end
	return result
end

-- Show stepper widgets on the 're-roll properties' page that allow the user to
-- select the specific properties they want.  Also add buttons that will appear
-- when locked properties are selected, which allow the user to unlock them.
mod:hook_safe(CraftPageRollProperties, "create_ui_elements", function(self, params)
	local extra_widgets_mgr = ExtraWidgetsManager:new(params.wwise_world)
	self._mod_casual_widget_mgr = extra_widgets_mgr
	hide_recipe_grid(self)

	-- Change the craft button's label from 're-roll properties' to 'apply'.
	self._widgets_by_name.craft_button.content.title_text = Localize("input_description_apply")

	-- Update the state of the 'unlock' buttons (showing them if the properties
	-- are locked, hiding them otherwise).
	local function update_buttons()
		local item = get_craft_item(self)
		local function update_unlock_button(index)
			local new_prop_name = ("new_property_" .. index)
			local new_prop = mod.crafting_extra_info[new_prop_name]
			local is_locked = user_progression:is_feature_locked("properties", item.data.property_table_name, new_prop)
			local button_name = ("unlock_button_" .. index)
			if is_locked then
				local button_tooltip = mod:localize("property_unlock_button_tooltip")
				local y_offset = (index == 1 and 95) or 10
				extra_widgets_mgr:add_button_widget(button_name, "recipe_grid", "locked_icon_01",
									{ lock_button_x_offset, y_offset, 0 }, lock_button_size, button_tooltip)
			else
				extra_widgets_mgr:remove_button_widget(button_name)
			end
			return is_locked
		end

		local is_property_1_locked = update_unlock_button(1)
		local is_property_2_locked = update_unlock_button(2)
		local current_props = item.properties
		local changed = not current_props[mod.crafting_extra_info.new_property_1]
						or not current_props[mod.crafting_extra_info.new_property_2]
		self:_set_craft_button_disabled(is_property_1_locked or is_property_2_locked or not changed)
	end

	-- Handle a click on an unlock button by showing an unlock popup.
	function handle_unlock_button(index)
		local popup_id = ("unlock_popup_" .. index)
		local xp_cost = user_progression:get_unlock_cost("property")
		extra_widgets_mgr:show_popup(unpack(get_unlock_popup_args("the_property", xp_cost, popup_id)))
	end

	-- Handle the outcome of an unlock popup.
	function handle_unlock_popup(index, result)
		if result == "unlock" then
			local item = get_craft_item(self)
			local property_to_unlock = mod.crafting_extra_info["new_property_" .. index]
			local xp_cost = user_progression:get_unlock_cost("property")
			user_progression:unlock_feature(xp_cost, "properties", item.data.property_table_name, property_to_unlock)
			update_buttons()
		end
	end

	-- Perform initial setup of the first property stepper.
	extra_widgets_mgr.cb_property_1_stepper_setup = function(inner_self)
		local item = get_craft_item(self)
		if item and item.properties then
			local current_properties = item.properties
			local current_property_1 = next(current_properties)
			if current_property_1 then
				-- Find the index of our item's current property in the list of available properties.
				local all_properties = get_possible_properties(item.data.property_table_name)
				local options = {}
				local current_property_index = 1
				local i = 1
				for property, _ in pairs(all_properties) do
					local text = UIUtils.get_property_description(property, 1)
					local option = {
						value = property,
						text = text
					}
					table.insert(options, option)
	
					if property == current_property_1 then
						current_property_index = i
					end
					i = i + 1
				end
				mod.crafting_extra_info.new_property_1 = current_property_1

				-- returns (selected option, options, label, default value)
				return current_property_index, options, "", current_property_index
			end
		end
		return 1, {}, "", 1
	end

	-- Handle a change in the first property selection.
	extra_widgets_mgr.cb_property_1_stepper = function(inner_self, content)
		mod.crafting_extra_info.new_property_1 = content.options_values[content.current_selection]

		-- Changing the first property may change which properties are available as
		-- the second property, so re-create the second property stepper (this will
		-- also cause the unlock buttons to be updated).
		inner_self:add_stepper_widget("property_2_stepper", "recipe_grid", 5)
	end

	extra_widgets_mgr.cb_unlock_button_1 = function(inner_self, content)
		handle_unlock_button(1)
	end

	extra_widgets_mgr.cb_unlock_popup_1 = function(inner_self, result)
		handle_unlock_popup(1, result)
	end

	-- Perform setup of the second property stepper (which is required whenever the
	-- first property selection changes).
	extra_widgets_mgr.cb_property_2_stepper_setup = function(inner_self)
		local item = get_craft_item(self)
		if item and item.properties then
			local current_properties = item.properties
			local current_property_1 = next(current_properties)
			local current_property_2, _ = next(current_properties, current_property_1)
			local new_property_1 = mod.crafting_extra_info.new_property_1
			local new_property_2 = mod.crafting_extra_info.new_property_2
			if current_property_2 then
				-- Find the index of our item's current property in the list of available properties.
				local all_properties = get_possible_properties(item.data.property_table_name, (new_property_1 or current_property_1))
				local options = {}
				local current_index = nil
				local new_index = nil
				local i = 1
				for property, _ in pairs(all_properties) do
					local text = UIUtils.get_property_description(property, 1)
					local option = {
						value = property,
						text = text
					}
					table.insert(options, option)
	
					if property == current_property_2 then
						current_index = i
					end
					if property == new_property_2 then
						new_index = i
					end
					i = i + 1
				end
				local selected_index = (new_index or current_index or 1)
				mod.crafting_extra_info.new_property_2 = options[selected_index].value
				update_buttons()

				-- returns (selected option, options, label, default value)
				return selected_index, options, "", current_index
			end
		end
		return 1, {}, "", 1
	end

	-- Handle a change in the second property selection.
	extra_widgets_mgr.cb_property_2_stepper = function(inner_self, content)
		mod.crafting_extra_info.new_property_2 = content.options_values[content.current_selection]
		update_buttons()
	end

	extra_widgets_mgr.cb_unlock_button_2 = function(inner_self, content)
		handle_unlock_button(2)
	end

	extra_widgets_mgr.cb_unlock_popup_2 = function(inner_self, result)
		handle_unlock_popup(2, result)
	end
end)

-- When an item is selected for crafting, show the property stepper widgets.
mod:hook_safe(CraftPageRollProperties, "_add_craft_item", function(self, backend_id, slot_index, ignore_sound)
	if self._num_craft_items > 0 then
		self._mod_casual_widget_mgr:add_stepper_widget("property_1_stepper", "recipe_grid", 90)
		self._mod_casual_widget_mgr:add_stepper_widget("property_2_stepper", "recipe_grid", 5)
	end
end)

-- When no item is selected for crafting, hide the property stepper widgets.
mod:hook_safe(CraftPageRollProperties, "_remove_craft_item", function(self, backend_id, slot_index)
	if self._num_craft_items == 0 then
		self._mod_casual_widget_mgr:remove_stepper_widget("property_1_stepper")
		self._mod_casual_widget_mgr:remove_stepper_widget("property_2_stepper")
		self._mod_casual_widget_mgr:remove_button_widget("unlock_button_1")
		self._mod_casual_widget_mgr:remove_button_widget("unlock_button_2")
	end
end)

-- Draw our widgets.
mod:hook_safe(CraftPageRollProperties, "draw", function (self, dt)
	local input_service = self.super_parent:window_input_service()
	self._mod_casual_widget_mgr:update(dt, self.ui_top_renderer, self.ui_scenegraph, input_service, self.render_settings)
end)

-- _________________________________________________________________________ --
-- MODIFY ITEM TRAITS

-- Show a stepper widget on the 're-roll trait' page that allows the user to
-- select the specific trait they want.  Also add a button that will appear
-- when a locked trait is selected, which allows the user to unlock it.
mod:hook_safe(CraftPageRollTrait, "create_ui_elements", function(self, params)
	local extra_widgets_mgr = ExtraWidgetsManager:new(params.wwise_world)
	self._mod_casual_widget_mgr = extra_widgets_mgr
	hide_recipe_grid(self)

	-- Change the craft button's label from 're-roll trait' to 'apply'.
	self._widgets_by_name.craft_button.content.title_text = Localize("input_description_apply")

	-- Update the state of the 'unlock' button (showing it if the trait is
	-- locked, hiding it otherwise).
	local function update_buttons(is_current_trait_selected)
		local item = get_craft_item(self)
		local new_trait = mod.crafting_extra_info.new_trait
		local is_locked = user_progression:is_feature_locked("traits", item.data.trait_table_name, new_trait)
		if is_locked then
			local button_tooltip = mod:localize("trait_unlock_button_tooltip")
			extra_widgets_mgr:add_button_widget("unlock_button", "recipe_grid", "locked_icon_01",
								{ lock_button_x_offset, 75, 0 }, lock_button_size, button_tooltip)
		else
			extra_widgets_mgr:remove_button_widget("unlock_button")
		end

		self:_set_craft_button_disabled(is_locked or is_current_trait_selected)
	end

	-- Perform initial setup of the trait stepper.
	extra_widgets_mgr.cb_trait_stepper_setup = function(inner_self)
		local item = get_craft_item(self)
		if item then
			local current_traits = item.traits
			local current_trait = current_traits and current_traits[1]
			-- Find the index of our item's current trait in the table of allowed traits.
			local traits_table = WeaponTraits.combinations[item.data.trait_table_name]
			local options = {}
			local current_trait_index = 1
			for i, traits in ipairs(traits_table) do
				local trait = traits[1]
				local option = {
					value = trait,
					text = Localize(WeaponTraits.traits[trait].display_name)
				}
				table.insert(options, option)

				if trait == current_trait then
					current_trait_index = i
				end
			end
			mod.crafting_extra_info.new_trait = current_trait
			update_buttons(true)

			-- returns (selected option, options, label, default value)
			return current_trait_index, options, "", current_trait_index
		end
		return 1, {}, "", 1
	end

	-- Handle a change in the selected trait in the stepper.
	extra_widgets_mgr.cb_trait_stepper = function(inner_self, content)
		local new_trait_index = content.current_selection
		mod.crafting_extra_info.new_trait = content.options_values[new_trait_index]

		inner_self:cb_trait_stepper_set_tooltip(content)
		update_buttons(new_trait_index == content.default_value)
	end

	extra_widgets_mgr.cb_trait_stepper_set_tooltip = function(inner_self, content)
		local trait = content.options_values[content.current_selection]
		local trait_data = WeaponTraits.traits[trait]
		content.tooltip_text = Localize(trait_data.display_name) .. "\n" .. UIUtils.get_trait_description(trait, trait_data)
	end

	-- Handle the unlock button being clicked, by showing an unlock popup.
	extra_widgets_mgr.cb_unlock_button = function(inner_self, content)
		local xp_cost = user_progression:get_unlock_cost("trait")
		inner_self:show_popup(unpack(get_unlock_popup_args("the_trait", xp_cost)))
	end

	-- Handle the outcome of the unlock popup.
	extra_widgets_mgr.cb_unlock_popup = function(inner_self, result)
		if result == "unlock" then
			local item = get_craft_item(self)
			local new_trait = mod.crafting_extra_info.new_trait
			local xp_cost = user_progression:get_unlock_cost("trait")
			user_progression:unlock_feature(xp_cost, "traits", item.data.trait_table_name, new_trait)
			update_buttons(new_trait == item.traits[1])
		end
	end
end)

-- When an item is selected for crafting, show the trait stepper widget.
mod:hook_safe(CraftPageRollTrait, "_add_craft_item", function(self, backend_id, slot_index, ignore_sound)
	if self._num_craft_items > 0 then
		self._mod_casual_widget_mgr:add_stepper_widget("trait_stepper", "recipe_grid", 70)
	end
end)

-- When no item is selected for crafting, hide the trait stepper widget.
mod:hook_safe(CraftPageRollTrait, "_remove_craft_item", function(self, backend_id, slot_index)
	if self._num_craft_items == 0 then
		self._mod_casual_widget_mgr:remove_stepper_widget("trait_stepper")
		self._mod_casual_widget_mgr:remove_button_widget("unlock_button")
	end
end)

-- Draw our widgets.
mod:hook_safe(CraftPageRollTrait, "draw", function (self, dt)
	local input_service = self.super_parent:window_input_service()
	self._mod_casual_widget_mgr:update(dt, self.ui_top_renderer, self.ui_scenegraph, input_service, self.render_settings)
end)

-- _________________________________________________________________________ --
-- APPLY WEAPON SKINS

-- All we need to do here is hide the crafting ingredient icon.
mod:hook_safe(CraftPageApplySkin, "create_ui_elements", function(self, params)
	hide_recipe_grid(self)
end)

-- _________________________________________________________________________ --
-- UNLOCK TALENTS

-- Add lock icons to the talent buttons, shown when buttons are disabled.
mod:hook_safe(HeroWindowTalents, "create_ui_elements", function(self, params, offset)
	widget_hacks.add_lock_buttons_to_talents(self._widgets, self._widgets_by_name)
end)

-- Disable the talent buttons for talents which aren't unlocked.
mod:hook_safe(HeroWindowTalents, "_populate_talents_by_hero", function(self, initialize)
	local career_name = self._career_name
	local real_level = get_real_level(self.hero_name)
	local widgets_by_name = self._widgets_by_name
	for i = 1, NumTalentRows, 1 do
		local talent_row = widgets_by_name["talent_row_" .. i]
		local content = talent_row.content
		local is_row_unlocked = setting_use_official_progress and ProgressionUnlocks.is_unlocked(("talent_point_" .. i), real_level)
		for j = 1, NumTalentColumns, 1 do
			local hotspot = content["hotspot_" .. j]
			hotspot.disabled = (not is_row_unlocked) and user_progression:is_feature_locked("talents", career_name, i, j)
		end
	end
end)

-- Handle mouse clicks on disabled talent buttons, by showing an unlock popup.
mod:hook_safe(HeroWindowTalents, "_handle_input", function(self, dt, t)
	local widgets_by_name = self._widgets_by_name
	for i = 1, NumTalentRows, 1 do
		local talent_row = widgets_by_name["talent_row_" .. i]
		if talent_row then
			local content = talent_row.content
			for j = 1, NumTalentColumns, 1 do
				local hotspot = content["hotspot_" .. j]
				if hotspot.on_release and hotspot.disabled then

					-- Show an 'unlock feature' popup.
					local extra_widgets_mgr = ExtraWidgetsManager:new(self.parent.wwise_world)
					self._mod_casual_widget_mgr = extra_widgets_mgr
					local xp_cost = user_progression:get_unlock_cost("talent_" .. i)

					extra_widgets_mgr.cb_unlock_popup = function(inner_self, result)
						if result == "unlock" then
							user_progression:unlock_feature(xp_cost, "talents", self._career_name, i, j)
							hotspot.disabled = false
						end
						self._mod_casual_widget_mgr = nil
					end

					extra_widgets_mgr:show_popup(unpack(get_unlock_popup_args("the_talent", xp_cost)))
				end
			end
		end
	end

	-- Call ExtraWidgetsManager.handle_input to handle input to the popup.
	if self._mod_casual_widget_mgr then
		self._mod_casual_widget_mgr:handle_input(dt)
	end
end)

-- _________________________________________________________________________ --
-- UNLOCK CAREERS

-- Replace the official progression for unlocking talents with our own.
mod:hook(ProgressionUnlocks, "is_unlocked_for_profile", function(orig_func, unlock_name, profile, level)
	local is_locked = user_progression:is_feature_locked("careers", unlock_name)
	if is_locked and setting_use_official_progress then
		local real_level = get_real_level(profile)
		is_locked = not orig_func(unlock_name, profile, real_level)
	end
	return not is_locked
end)

-- When the user clicks on a locked career, show an unlock popup.
mod:hook_safe(CharacterSelectionStateCharacter, "_select_hero", function(self, profile_index, career_index, is_initializing)
	if not is_initializing then
		-- Find the index of the selected hero's widget in the grid.
		local widget_index = 0
		for i = 1, self._selected_hero_row - 1, 1 do
			widget_index = widget_index + self._num_hero_columns[i]
		end
		widget_index = widget_index + self._selected_hero_column
	
		local content = self._hero_widgets[widget_index].content
		if content.locked then
			-- Show an 'unlock feature' popup.
			local extra_widgets_mgr = ExtraWidgetsManager:new(self.wwise_world)
			self._mod_casual_widget_mgr = extra_widgets_mgr
			local xp_cost = user_progression:get_unlock_cost("career")

			extra_widgets_mgr.cb_unlock_popup = function(inner_self, result)
				if result == "unlock" then
					local career_name = SPProfiles[profile_index].careers[career_index].name
					user_progression:unlock_feature(xp_cost, "careers", career_name)
					content.locked = false
				end
				self._mod_casual_widget_mgr = nil
			end

			extra_widgets_mgr:show_popup(unpack(get_unlock_popup_args("the_career", xp_cost)))
		end
	end

	-- Hide the 'Unlocked at level N' text.
	self._widgets_by_name.locked_info_text.content.visible = false
end)

-- Call ExtraWidgetsManager.handle_input to handle input to the popup.
mod:hook_safe(CharacterSelectionStateCharacter, "_handle_input", function(self, dt, t)
	if self._mod_casual_widget_mgr then
		self._mod_casual_widget_mgr:handle_input(dt)
	end
end)

-- _________________________________________________________________________ --
-- END-OF-MISSION REWARDS

-- Pretend we are trusted so that the experience reward screen will be shown.
mod:hook_safe(StateInGameRunning, "on_enter", function(self, params)
	self._booted_eac_untrusted = false
end)

-- This hook is just to stop weaves crashing at the end screen.
mod:hook(StateInGameRunning, "_submit_weave_scores", function (self)
end)

-- Pretend we are trusted so that the end-mission rewards will be computed.
mod:hook(LevelEndViewBase, "init", function(orig_func, self, context)
	local real_eac_untrusted = script_data["eac-untrusted"]
	script_data["eac-untrusted"] = false
	orig_func(self, context)
	script_data["eac-untrusted"] = real_eac_untrusted
end)

-- Prevent the backend from being accessed, since we're not actually trusted.
mod:hook(BackendInterfaceLootPlayfab, "generate_end_of_level_loot", function(orig_func, self, ...)
	local fake_id = "loot!"
	self._loot_requests[fake_id] = {}
	return fake_id
end)

-- We use our own per-difficulty XP multipliers, since the game currently uses
-- the same multiplier (2) for all difficulties. (We're actually using the same
-- multipliers the game used on release.)
local difficulty_xp_multipliers = {
	normal = 1,
	hard = 1.25,
	harder = 1.5,
	hardest = 2,
	cataclysm = 2.5,
	cataclysm_2 = 2.75,
	cataclysm_3 = 3,
}

mod:hook_safe(EndViewStateSummary, "on_enter", function(self, params)
	-- Calculate the per-difficulty multiplier.
	local difficulty = params.context.difficulty
	local xp_mult = difficulty_xp_multipliers[difficulty] or 1
	local xp_adjustment = xp_mult / DifficultySettings[difficulty].xp_multiplier

	-- Calculate the max XP the user could have gained from surviving heroes,
	-- tomes and grimoires. Below, we use this to figure out how much of that XP
	-- they missed out on (which we just use to compute how much empty space to
	-- leave at the end of the progress bar.)
	local xp_missed = {}
	local tome_mission = Missions.tome_bonus_mission
	xp_missed[tome_mission.text] = (xp_mult * tome_mission.experience_per_amount * tome_mission.collect_amount)
	local grim_mission = Missions.grimoire_hidden_mission
	xp_missed[grim_mission.text] = (xp_mult * grim_mission.experience_per_amount * grim_mission.collect_amount)
	local alive_mission = Missions.players_alive_mission
	xp_missed[alive_mission.text] = (xp_mult * alive_mission.experience_per_amount * 4)

	-- Go through all the mission rewards, adjust the xp according to our
	-- multiplier, and add it all up to get the total.
	local total_xp_gained = 0
	for index, mission_reward in ipairs(self._context.rewards.mission_results) do
		local text = mission_reward.text
		local experience = mission_reward.experience
		if experience then
			local adjusted_xp = math.round(experience * xp_adjustment)
			mission_reward.experience = adjusted_xp
			total_xp_gained = total_xp_gained + adjusted_xp

			-- Record this XP in 'xp_missed' if appropriate.
			if text:find("mission_failed_") then
				-- The number 400 comes from EXPERIENCE_REWARD in rewards.lua
				xp_missed["failure"] = (xp_mult * 400) - adjusted_xp
			elseif xp_missed[text] then
				xp_missed[text] = xp_missed[text] - adjusted_xp
			end
		end
	end

	-- Add the XP earned to the user's cumulative total (which is persisted to file).
	user_progression:add_xp_earned(total_xp_gained)

	-- Compute how much XP they could have had if they hadn't missed any.
	local total_xp_possible = total_xp_gained
	for _, xp_amount in pairs(xp_missed) do
		total_xp_possible = total_xp_possible + math.max(xp_amount, 0)
	end

	local min_time = UISettings.summary_screen.bar_progress_min_time
	local max_time = UISettings.summary_screen.bar_progress_max_time
	local time_multiplier = UISettings.summary_screen.bar_progress_experience_time_multiplier

	-- Compute values for the XP progress bar.  Note that these calculations assume we have
	-- faked user experience to be the amount for level 35, and the 'experience pool' as zero.
	local total_progress = (total_xp_gained / total_xp_possible)
	-- (2900 is the value of 'experience_for_extra_levels' in experience_settings.lua.)
	local experience_to_add = total_progress * 2900
	local time = math.min(math.max(time_multiplier * experience_to_add, min_time), max_time)
	self._progress_data = {
		time = 0,
		complete = false,
		current_experience = ExperienceSettings.max_experience,
		experience_to_add = experience_to_add,
		total_progress = (total_xp_gained / total_xp_possible),
		start_progress = 0,
		total_time = time,
	}

	-- Don't show the user's level, since we fake it and it never changes.
	self._widgets_by_name.current_level_text.content.visible = false
	self._widgets_by_name.next_level_text.content.visible = false
end)
