local mod = get_mod("bots_impulse_control")
local vmf = get_mod("VMF")

-- Non-DRY with the same definitions in bots_impulse_control_data.lua.
local MANUAL_HEALING_DISABLED = 1
local MANUAL_HEALING_OPTIONAL = 2
local MANUAL_HEALING_MANDATORY = 3

-- Cached setting values.
local setting_no_chasing_specials = false
local setting_no_seeking_cover = false
local setting_no_reviving_bots = false
local setting_manual_healing = MANUAL_HEALING_DISABLED
local setting_manual_healing_hotkeys = {}

-- A set of breed objects containing those specials which the bots should not pursue in order to
-- melee when setting_no_chasing_specials is enabled.
local breeds_to_not_chase = {
	--[Breeds.chaos_corruptor_sorcerer] = true,
	[Breeds.chaos_vortex_sorcerer] = true,
	[Breeds.skaven_poison_wind_globadier] = true,
	[Breeds.skaven_ratling_gunner] = true,
	[Breeds.skaven_warpfire_thrower] = true,
}

-- A flag set when any manual healing keybind is pressed (not really necessary but provides
-- a small optimisation for the common case where no such key is pressed).
local was_manual_heal_pressed = false

-- The player unit of the bot currently performing manually-controlled healing, if any.
mod.healing_player_unit = nil

-- When manual healing is being performed, indicates whether the healing bot is healing itself.
mod.is_healing_self = false

-- A flag used to indicate when bots' knocked-down status should be ignored, as part of the
-- implementation of the setting_no_reviving_bots option.
mod.override_bot_knocked_down = false

-- Perform initial setup: fetch and cache our setting values.
mod.on_all_mods_loaded = function()
	setting_no_chasing_specials = mod:get("no_chasing_specials")
	setting_no_seeking_cover = mod:get("no_seeking_cover")
	setting_no_reviving_bots = mod:get("no_reviving_bots")
	setting_manual_healing = mod:get("manual_healing")
	for i = 1, 4 do
		setting_manual_healing_hotkeys[i] = mod:get("manual_healing_hotkey_" .. tostring(i))
	end
end

mod.on_setting_changed = mod.on_all_mods_loaded

mod.on_manual_heal_pressed = function()
	was_manual_heal_pressed = true
end

-- Helper function to test whether the given hotkey is currently pressed.
local function is_hotkey_down(hotkey)
	local input_service = vmf.keybind_input_service
	if not input_service or not hotkey or #hotkey == 0 then
		return false
	end

	for _, key in ipairs(hotkey) do
		if not input_service:get(key) then
			return false
		end
	end
	return true
end

-- Helper function to check whether any of the manual-healing hotkeys are currently pressed.
local function get_selected_player()
	if was_manual_heal_pressed then
		local ingame_ui = Managers.matchmaking._ingame_ui
		local unit_frames_handler = ingame_ui and ingame_ui.ingame_hud.unit_frames_handler
		if unit_frames_handler then
			-- The unit frames and player_data are never nil, although player might be.
			for index, unit_frame in ipairs(unit_frames_handler._unit_frames) do
				if is_hotkey_down(setting_manual_healing_hotkeys[index]) then
					return unit_frame.player_data.player
				end
			end
		end
		was_manual_heal_pressed = false
	end
	return nil
end

-- Helper function that checks whether a player can perform healing on either itself (if heal_self
-- is true) or on another player (if heal_self is false).
local function can_perform_heal(inventory_extn, heal_self)
	local health_slot_data = inventory_extn:get_slot_data("slot_healthkit")
	if health_slot_data then
		local item_template = inventory_extn:get_item_template(health_slot_data)
		return (heal_self and item_template.can_heal_self) or ((not heal_self) and item_template.can_heal_other)
	end
	return false
end

-- Hook PlayerBotBase._enemy_path_allowed to prevent bots running off to melee specials if
-- setting_no_chasing_specials is enabled.
mod:hook(PlayerBotBase, "_enemy_path_allowed", function(hooked_function, self, enemy_unit)
	if setting_no_chasing_specials and breeds_to_not_chase[Unit.get_data(enemy_unit, "breed")] then
		return false
	end
	return hooked_function(self, enemy_unit)
end)

-- Hook PlayerBotBase._in_line_of_fire to prevent bots seeking cover from gunner fire if
-- setting_no_seeking_cover is enabled.
mod:hook(PlayerBotBase, "_in_line_of_fire", function(hooked_function, ...)
	if setting_no_seeking_cover then
		return false, false
	end
	return hooked_function(...)
end)

-- The PlayerBotBase._select_ally_by_utility function decides, for a bot, which ally is most in need of the
-- bot's assistance, for example to be healed or revived by the bot.  We hook it to force bots to heal who
-- we want them to heal when manual healing is in effect, and also to prevent bots reviving other bots if
-- setting_no_reviving_bots is enabled.
mod:hook(PlayerBotBase, "_select_ally_by_utility", function(hooked_function, self, unit, blackboard, ...)
	if MANUAL_HEALING_DISABLED == setting_manual_healing then
		return hooked_function(self, unit, blackboard, ...)
	end

	-- First check whether any of the manual-heal keys are currently pressed.
	local selected_player = get_selected_player()
	local selected_unit = selected_player and selected_player.player_unit
	local inventory_extn = blackboard.inventory_extension

	-- If we want to manually heal this bot and it can heal itself, tell it to do so.
	if (selected_unit == unit) and can_perform_heal(inventory_extn, true) then
		mod.healing_player_unit = unit
		mod.is_healing_self = true
		return nil, math.huge, nil, false

	-- If we want to manually heal another player, check whether this bot can and should heal it.
	elseif selected_unit and ((selected_unit ~= unit and not mod.healing_player_unit) or mod.healing_player_unit == unit)
			and can_perform_heal(inventory_extn, false)
			and not (selected_player.bot_player and can_perform_heal(ScriptUnit.extension(selected_unit, "inventory_system"), true)) then

		mod.healing_player_unit = unit
		mod.is_healing_self = false
		local distance = Vector3.distance(POSITION_LOOKUP[unit], POSITION_LOOKUP[selected_unit])
		return selected_unit, distance, "in_need_of_heal", false

	-- Otherwise there is no manual healing for this bot to do. Tidy up state if it was previously healing.
	elseif mod.healing_player_unit == unit then
		mod.healing_player_unit = nil
		mod.is_healing_self = false
	end

	-- Stop this bot from using a medkit on someone else if only manual healing is allowed.
	local saved_medkit = nil
	if ((MANUAL_HEALING_MANDATORY == setting_manual_healing and can_perform_heal(inventory_extn, false)) or mod.healing_player_unit) then
		local slots = inventory_extn._equipment.slots
		saved_medkit = slots["slot_healthkit"]
		slots["slot_healthkit"] = nil
	end
	mod.override_bot_knocked_down = setting_no_reviving_bots

	-- Call the real _select_ally_by_utility.
	local ally_unit, real_dist, in_need_type, ally_look_at = hooked_function(self, unit, blackboard, ...)

	-- Restore any state we temporarily altered.
	if saved_medkit then
		inventory_extn._equipment.slots["slot_healthkit"] = saved_medkit
	end
	mod.override_bot_knocked_down = false

	return ally_unit, real_dist, in_need_type, ally_look_at
end)

-- Hook BTConditions.bot_should_heal to prevent bots from healing themselves when manual healing is in effect.
mod:hook(BTConditions, "bot_should_heal", function(hooked_function, blackboard)
	if MANUAL_HEALING_MANDATORY == setting_manual_healing
			or (MANUAL_HEALING_OPTIONAL == setting_manual_healing and mod.healing_player_unit) then

		return mod.is_healing_self and (mod.healing_player_unit == blackboard.unit)
	end
	return hooked_function(blackboard)
end)

-- Hook GenericStatusExtension.is_knocked_down to return false when we're checking whether a bot needs
-- reviving (in PlayerBotBase._select_ally_by_utility) even if it actually is knocked down.
mod:hook_origin(GenericStatusExtension, "is_knocked_down", function(self)
	return self.knocked_down and not (mod.override_bot_knocked_down and self.player.bot_player)
end)
