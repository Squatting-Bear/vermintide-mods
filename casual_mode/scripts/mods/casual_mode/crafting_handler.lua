local mod = get_mod("casual_mode")

local CloudFile = local_require("scripts/mods/casual_mode/cloud_file")

-- This is in case of mod reload, which messes up CloudFile internal state.
CloudFile.global_reset()

local Managers = Managers

local user_progression = nil
local saved_items_file = CloudFile:new(mod, "saved_items.data")
local saved_items_by_id = nil
local are_items_loaded = false
local DEBUG_RESET_ITEMS = false

-- Add an item to the backend cache (this is essentially PlayFabMirror.add_item()
--  minus a couple of steps).
local function add_item_to_backend(backend_mirror, backend_id, raw_item, is_fake)
	backend_mirror:_update_data(raw_item, backend_id)
	backend_mirror._inventory_items[backend_id] = raw_item
	backend_mirror:_re_evaluate_best_power_level(raw_item)
	if is_fake then
		backend_mirror._fake_inventory_items[backend_id] = raw_item
	end
end

-- Add all the items in the given list to the backend cache.
local function add_all_items_to_backend(backend_mirror, raw_items_by_id)
	for backend_id, raw_item in pairs(raw_items_by_id) do
		add_item_to_backend(backend_mirror, backend_id, table.clone(raw_item), true)
	end
end

-- Helper function that retrieves the item from the given item_id_and_amount object.
local function get_mod_created_item(item_id_and_amount, optional_backend_items)
	local item_backend_id = item_id_and_amount.backend_id
	local backend_items = optional_backend_items or Managers.backend:get_interface("items")
	local item = backend_items:get_item_from_id(item_backend_id)

	-- Ensure that the item is one of ours.
	fassert(backend_items:get_all_fake_backend_items()[item_backend_id], "Attempt to perform crafting function on non-mod item")
	return item_backend_id, item, backend_items
end

-- Handle a 'salvage items' crafting request, by just deleting the items.
local function salvage(crafting_backend_playfab, recipe, item_backend_ids_and_amounts)
	local backend_items = Managers.backend:get_interface("items")
	local deleted_item_id = nil

	for _, item_id_and_amount in ipairs(item_backend_ids_and_amounts) do
		local backend_id = get_mod_created_item(item_id_and_amount, backend_items)
		backend_items._backend_mirror:remove_item(backend_id)
		backend_items._backend_mirror._fake_inventory_items[backend_id] = nil
		saved_items_by_id[backend_id] = nil
		deleted_item_id = backend_id
	end
	backend_items:make_dirty()

	return deleted_item_id, {}
end

-- Handle a 'craft item' crafting request.
local function craft_item(crafting_backend_playfab, recipe, item_backend_ids_and_amounts)
	local backend_items = Managers.backend:get_interface("items")
	local template_backend_id = item_backend_ids_and_amounts[3].backend_id
	local masterlist_data = backend_items:get_item_masterlist_data(template_backend_id)
	fassert(masterlist_data, "Master list data not found for id %s", tostring(template_backend_id))

	local new_backend_id = Application.guid()

	-- Use defaults for the item's properties and trait.
	local unlocked_by_default = user_progression:get_default_unlocks()
	local default_traits = unlocked_by_default.traits[masterlist_data.trait_table_name]
	local default_trait = next(default_traits)
	local traits = {
		default_trait,
	}
	local default_properties = unlocked_by_default.properties[masterlist_data.property_table_name]
	local default_property_1 = next(default_properties)
	local properties = {
		[default_property_1] = 1,
		[next(default_properties, default_property_1)] = 1,
	}

	-- Create the new item, in the format that would be sent by the actual remote backend.
	new_item = {
		ItemId = masterlist_data.key,
		ItemInstanceId = new_backend_id,
		CustomData = {
			rarity = "exotic",
			power_level = tostring(DifficultySettings.hardest.max_chest_power_level),
			properties = cjson.encode(properties),
			traits = cjson.encode(traits),
		},
	}
	-- Save a copy to (the in-memory cache of) our persistent data.
	saved_items_by_id[new_backend_id] = table.clone(new_item)

	-- The add_item function will set up the item in the format used by the game code
	-- (setting item.backend_id and item.data, copying properties from item.CustomData
	-- to item itself, etc.).
	backend_items._backend_mirror:add_item(new_backend_id, new_item)

	-- We also mark the item as "fake", so that in UI code we will know it's one of ours.
	backend_items._backend_mirror._fake_inventory_items[new_backend_id] = new_item

	backend_items:make_dirty()
	local amount = new_item.UsesIncrementedBy or 1
	return new_backend_id, { { new_backend_id, nil, amount } }
end

-- Handle a 'change item properties' crafting request.
local function reroll_item_properties(crafting_backend_playfab, recipe, item_backend_ids_and_amounts)
	local item_backend_id, item, backend_items = get_mod_created_item(item_backend_ids_and_amounts[3])
	local new_property_1 = mod.crafting_extra_info.new_property_1
	local new_property_2 = mod.crafting_extra_info.new_property_2
	if new_property_1 and new_property_2 then

		-- Update the item with its new properties.
		item.properties = { [new_property_1] = 1, [new_property_2] = 1 }
		local encoded_properties = cjson.encode(item.properties)
		item.CustomData.properties = encoded_properties
		saved_items_by_id[item_backend_id].CustomData.properties = encoded_properties
		backend_items:make_dirty()

		return item_backend_id, { { item_backend_id } }
	end
end

-- Handle a 'change item trait' crafting request.
local function reroll_item_traits(crafting_backend_playfab, recipe, item_backend_ids_and_amounts)
	local item_backend_id, item, backend_items = get_mod_created_item(item_backend_ids_and_amounts[2])
	local item_traits = item.traits
	local current_trait = item_traits and item_traits[1]
	local new_trait = mod.crafting_extra_info.new_trait
	if new_trait and current_trait then

		-- Update the item with its new trait.
		item_traits[1] = new_trait
		local encoded_traits = cjson.encode(item_traits)
		item.CustomData.traits = encoded_traits
		saved_items_by_id[item_backend_id].CustomData.traits = encoded_traits
		backend_items:make_dirty()

		return item_backend_id, { { item_backend_id } }
	end
end

-- Handle a 'change item skin' crafting request.
local function apply_weapon_skin(crafting_backend_playfab, recipe, item_backend_ids_and_amounts)
	local item_backend_id, item, backend_items = get_mod_created_item(item_backend_ids_and_amounts[1])
	local saved_custom_data = saved_items_by_id[item_backend_id].CustomData

	local skin_name = item_backend_ids_and_amounts[2].skin_name
	local skin_info = WeaponSkins.skins[skin_name]
	item.skin = skin_name
	item.CustomData.skin = skin_name
	saved_custom_data.skin = skin_name

	local rarity = (skin_info.rarity == "unique" and "unique") or "exotic"
	item.rarity = rarity
	item.CustomData.rarity = rarity
	saved_custom_data.rarity = rarity
	backend_items:make_dirty()

	return item_backend_id, { { item_backend_id } }
end

local crafting_functions = {
	salvage = salvage,
	craft_weapon = craft_item,
	craft_jewellery = craft_item,
	reroll_weapon_properties = reroll_item_properties,
	reroll_jewellery_properties = reroll_item_properties,
	reroll_weapon_traits = reroll_item_traits,
	reroll_jewellery_traits = reroll_item_traits,
	apply_weapon_skin = apply_weapon_skin,
}

-- Handle a crafting request.
mod:hook(BackendInterfaceCraftingPlayfab, "craft", function(orig_func, self, career_name, item_backend_ids, recipe_override)
	fassert(user_progression and saved_items_by_id, "Crafting handler not initialized")

	local recipe, item_backend_ids_and_amounts = self:_get_valid_recipe(item_backend_ids, recipe_override)
	local recipe_name = recipe and recipe.name

	-- Direct the request to the appropriate handler, if any
	local crafting_function = recipe_name and crafting_functions[recipe_name]
	if crafting_function and item_backend_ids_and_amounts then
		local item_backend_id, craft_request = crafting_function(self, recipe, item_backend_ids_and_amounts)
		if item_backend_id then

			-- The request was successful, so persist the changes.
			saved_items_file:save({ items = saved_items_by_id })
			self._craft_requests[item_backend_id] = craft_request
			return item_backend_id, recipe
		end
	end
end)

-- Hook PlayFabMirror._request_characters_adventure since it is called just after the real
-- items are added to the backend cache, so it's a good point to add our fake ones.
mod:hook(PlayFabMirror, "_request_characters_adventure", function(orig_func, self)
	if saved_items_by_id then
		add_all_items_to_backend(self, saved_items_by_id)
		are_items_loaded = true
		orig_func(self)
	end
	-- If our items haven't been loaded from file yet, do nothing - this function
	-- will be called again later from ready(), when the file's been loaded.
end)

-- Prevent the backend cache from considering itself 'ready' until after we have
-- added our items.
mod:hook(PlayFabMirror, "ready", function(orig_func, self)
	if not are_items_loaded and saved_items_by_id and self._inventory_items then
		self:_request_characters_adventure()
	end
	return are_items_loaded and orig_func(self)
end)

-- Load our items from persistent storage.
saved_items_file:load(function(result)
	saved_items_by_id = (result.data and result.data.items) or {}
	if DEBUG_RESET_ITEMS then
		saved_items_by_id = {}
	end
end)

return {
	init = function(user_progression_in)
		user_progression = user_progression_in
	end,

	add_item_to_backend = add_item_to_backend,
}
