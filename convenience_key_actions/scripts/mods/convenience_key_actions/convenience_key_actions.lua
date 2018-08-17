local mod = get_mod("convenience_key_actions")
local vmf = get_mod("VMF")

-- The wait time between attack commands when the continuous attack key is held down.
-- 170ms is roughly how fast I can comfortably click my mouse button.
local ATTACK_INTERVAL = 0.170

-- Cached value of the "continuous_attack_hotkey" setting.
local continuous_attack_hotkey = nil

-- Cached value of the "continuous_attack_block_option" setting.
local block_option = 2

-- Information required to implement the "use item" hotkeys, including cached values of
-- the relevant hotkey settings.
local item_hotkeys_by_setting_id = {
	use_healing_item_hotkey = {
		slot = InventorySettings.slots_by_name["slot_healthkit"],
	},
	drink_potion_hotkey = {
		slot = InventorySettings.slots_by_name["slot_potion"],
	},
	throw_bomb_hotkey = {
		slot = InventorySettings.slots_by_name["slot_grenade"],
	},
}

-- Perform initial setup: fetch and cache our setting values.
mod.on_all_mods_loaded = function()
	continuous_attack_hotkey = mod:get("continuous_attack_hotkey")
	block_option = mod:get("continuous_attack_block_option")
	for setting_id, hotkey_info in pairs(item_hotkeys_by_setting_id) do
		hotkey_info.hotkey = mod:get(setting_id)
	end
end

mod.on_setting_changed = mod.on_all_mods_loaded

-- Hook PlayerInputExtension.init to initialize extra data members required by this mod.
mod:hook_safe(PlayerInputExtension, "init", function(self, ...)
	self._cka_mod_data = {
		-- The state we're pretending the attack button ("action_one") is currently in.
		-- The possible states are:
		-- 4: action_one pressed this frame, and will be held down
		-- 3: action_one pressed this frame, and will be released next frame
		-- 2: action_one is held down
		-- 1: action_one released this frame
		-- <=0: action_one not faked
		action_one_fake_state = -1,

		-- The time at which we last sent a fake action_one command.
		last_fake_change_time = 0,

		-- The "use item" hotkey currently being held down, if any.
		current_item_hotkey = false,

		-- The "item wield" action we are currently faking, if any.
		fake_wield_action = false,
	}
end)

-- Hook PlayerInputExtension.get to return "fake" results when one of our hotkeys is pressed.
mod:hook(PlayerInputExtension, "get", function(hooked_function, self, input_key, consume)
	local value = hooked_function(self, input_key, consume)

	local mod_data = self._cka_mod_data
	local action_one_fake_state = mod_data.action_one_fake_state
	local fake_wield_action = mod_data.fake_wield_action

	if not value and (action_one_fake_state > 0 or fake_wield_action) then
		local fake_it = (action_one_fake_state >= 3 and ("action_one" == input_key or "action_one_hold" == input_key))
				or (action_one_fake_state == 2 and "action_one_hold" == input_key)
				or (action_one_fake_state == 1 and "action_one_release" == input_key)
				or (fake_wield_action == input_key)
		if fake_it and self.enabled and PlayerInputExtension.get_window_is_in_focus() then
			return true
		end
	end
	return value
end)

-- Hook PlayerInputExtension.add_buffer to handle the case where one of our hotkeys is pressed.
mod:hook(PlayerInputExtension, "add_buffer", function(hooked_function, self, input_key, doubleclick_window)
	local mod_data = self._cka_mod_data
	local action_one_fake_state = mod_data.action_one_fake_state

	if ((action_one_fake_state >= 3 and "action_one" == input_key)
			or (action_one_fake_state == 1 and "action_one_release" == input_key))
			and not self.priority_input[self.buffer_key] then

		-- Add a buffer for the fake action_one or action_one_release input.
		self.new_input_buffer_timer = 0.6
		self.new_input_buffer = true
		self.new_buffer_key = input_key
		self.new_buffer_key_doubleclick_window = doubleclick_window

	elseif mod_data.fake_wield_action == input_key then
		-- Wield actions are priority inputs.
		self.input_buffer_timer = 1
		self.input_buffer = true
		self.buffer_key = input_key
	else
		return hooked_function(self, input_key, doubleclick_window)
	end
end)

-- Hook PlayerInputExtension.reset_input_buffer to handle the case where one of our hotkeys is pressed.
mod:hook(PlayerInputExtension, "reset_input_buffer", function(hooked_function, self)
	if self.buffer_key == "action_one" and self._cka_mod_data.action_one_fake_state >= 2 then
		-- Here we replicate the part of the original reset_input_buffer function
		-- which would be skipped if we weren't faking the action_one input.
		if self.added_stun_buffer then
			self.added_stun_buffer = false
		else
			self.input_buffer_timer = 0
			self.input_buffer = nil
			self.buffer_key = nil
		end
	else
		hooked_function(self)
	end
end)

-- Hook PlayerInputExtension.released_input to handle the case where one of our hotkeys is pressed.
mod:hook(PlayerInputExtension, "released_input", function(hooked_function, self, input)
	if input == "action_one_hold" then
		local action_one_fake_state = self._cka_mod_data.action_one_fake_state
		if action_one_fake_state == 2 or action_one_fake_state == 4 then
			return false
		end
	end
	return hooked_function(self, input)
end)

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

-- Hook PlayerInputExtension.update to check for and process changes in the state of our hotkeys.
mod:hook_safe(PlayerInputExtension, "update", function(self, unit, input, dt, context, t)
	local mod_data = self._cka_mod_data
	local action_one_fake_state = mod_data.action_one_fake_state
	local current_item_hotkey = mod_data.current_item_hotkey
	mod_data.fake_wield_action = false

	if action_one_fake_state > 0 then
		-- We are currently in the process of faking an action_one command, check whether
		-- we need to change action_one_fake_state.
		if action_one_fake_state ~= 2 then
			-- action_one is not (fake) held down, proceed to the next state.
			mod_data.action_one_fake_state = action_one_fake_state - 2

		elseif current_item_hotkey then
			-- action_one is (fake) held down for the sake of a "use item" hotkey, do nothing
			-- unless the hotkey has been released (in which case proceed to fake-release action_one).
			if not is_hotkey_down(current_item_hotkey) then
				mod_data.current_item_hotkey = false
				mod_data.action_one_fake_state = 1
			end

		-- Otherwise action_one is (fake) held down for the sake of the continuous attack
		-- hotkey, do nothing unless the hotkey has been released (in which case proceed to
		-- fake-release action_one).
		elseif not ScriptUnit.extension(unit, "status_system"):is_blocking() then
			mod_data.action_one_fake_state = 1
			mod_data.last_fake_change_time = t
		end

	elseif is_hotkey_down(continuous_attack_hotkey) then
		-- The continuous attack hotkey is held down, check whether it is time to send the
		-- next fake action_one command.  We also have to check whether the user is currently
		-- blocking, and if so take their choice of block_option into account in our decision.
		if block_option == 3 and ScriptUnit.extension(unit, "status_system"):is_blocking() then
			mod_data.action_one_fake_state = 4
		elseif (mod_data.last_fake_change_time + ATTACK_INTERVAL < t)
					and (block_option ~= 1 or not self.input_service:get("action_two_hold")
					or ScriptUnit.extension(unit, "inventory_system"):get_wielded_slot_name() ~= "slot_melee") then
			mod_data.action_one_fake_state = 3
			mod_data.last_fake_change_time = t
		end

	else
		-- Check whether the user is pressing any of our "use item" hotkeys.
		for _, hotkey_info in pairs(item_hotkeys_by_setting_id) do
			if is_hotkey_down(hotkey_info.hotkey) then
				-- A "use item" hotkey is pressed; first check whether the user is
				-- currently wielding the desired item slot.
				local inventory_extn = ScriptUnit.extension(unit, "inventory_system")
				local slot_name = hotkey_info.slot.name
				if inventory_extn:get_wielded_slot_name() ~= slot_name then
					-- They're not wielding that slot; check whether they actually have
					-- anything in that slot, and if so send a command to wield it.
					if inventory_extn:get_slot_data(slot_name) then
						mod_data.fake_wield_action = hotkey_info.slot.wield_input
					end

				-- They're wielding the right slot, so check whether they actually have
				-- an item in it, and if so send a fake action_one command to use it.
				elseif inventory_extn:get_slot_data(slot_name) then
					mod_data.current_item_hotkey = hotkey_info.hotkey
					mod_data.action_one_fake_state = 4
				end
			end
		end
	end
end)
