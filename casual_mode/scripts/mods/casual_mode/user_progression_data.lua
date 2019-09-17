local mod = get_mod("casual_mode")

local CloudFile = local_require("scripts/mods/casual_mode/cloud_file")

local progression_file = CloudFile:new(mod, "user_progression.data")
local DEBUG_RESET_PROGRESSION = false

-- The initial progression state, mostly consists of specifying which
-- features are unlocked by default.
local initial_state = {
	xp_earned = 0,
	xp_spent = 0,

	unlocked = {
		properties = {
			melee = {
				crit_chance = true,
				block_cost = true,
			},
			ranged = {
				crit_chance = true,
				power_vs_chaos = true,
			},
			offence_accessory ={
				crit_boost = true,
				power_vs_skaven = true,
			},
			defence_accessory = {
				health = true,
				block_cost = true,
			},
			utility_accessory = {
				curse_resistance = true,
				fatigue_regen = true,
			},
		},
		traits = {
			melee = {
				melee_reduce_cooldown_on_crit = true,
			},
			ranged_ammo = {
				ranged_replenish_ammo_headshot = true,
			},
			ranged_heat = {
				ranged_reduced_overcharge = true,
			},
			offence_accessory ={
				ring_potion_spread = true,
			},
			defence_accessory = {
				necklace_increased_healing_received = true,
			},
			utility_accessory = {
				trinket_not_consume_grenade = true,
			},
		},
		weapons = {
			dr_2h_hammer = true,
			dr_crossbow = true,
			we_1h_sword = true,
			we_longbow = true,
			es_2h_sword = true,
			es_blunderbuss = true,
			wh_brace_of_pistols = true,
			wh_fencing_sword = true,
			bw_sword = true,
			bw_skullstaff_fireball = true,
		},
		talents = {
			dr_ranger = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			dr_slayer = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			dr_ironbreaker = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			we_waywatcher = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			we_shade = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			we_maidenguard = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			es_huntsman = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			es_mercenary = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			es_knight = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			bw_adept = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			bw_scholar = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			bw_unchained = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			wh_captain = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			wh_bountyhunter = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
			wh_zealot = { { true, }, { true, }, { true, }, { true, }, { true, }, { true, }, },
		},
		careers = {
			dr_ranger = true,
			we_waywatcher = true,
			es_mercenary = true,
			bw_adept = true,
			wh_captain = true,
		},
	},
}

-- XP cost of unlocking each kind of feature.
local unlock_costs = {
	property = 240,
	trait = 620,
	weapon = 450,
	talent_1 = 400,
	talent_2 = 460,
	talent_3 = 520,
	talent_4 = 580,
	talent_5 = 640,
	talent_6 = 700,
	career = 950,
}

local data = nil

-- Load the current user progression state from persistent storage.
progression_file:load(function(result)
	data = result.data or table.clone(initial_state)
	if DEBUG_RESET_PROGRESSION then
		data = table.clone(initial_state)
	end
end)

return {
	defaults = initial_state,
	is_progression_enabled = true,

	get_available_xp = function(self)
		return data.xp_earned - data.xp_spent
	end,

	get_unlock_cost = function(self, category)
		fassert(unlock_costs[category], "Unknown category '%s'", category)
		return unlock_costs[category]
	end,

	add_xp_earned = function(self, additional_xp)
		data.xp_earned = data.xp_earned + additional_xp
		progression_file:save(data)
	end,

	set_progression_enabled = function(self, enabled)
		self.is_progression_enabled = enabled
	end,

	-- Returns true if the given feature is unlocked.  The feature is
	-- specified as a path within the progression state, e.g.
	-- foo:is_feature_locked("properties", "melee", "crit_chance")
	is_feature_locked = function(self, ...)
		if not self.is_progression_enabled then
			return false
		end

		local path = data.unlocked
		local segment_count = select('#', ...)
		for i = 1, segment_count do
			local segment = select(i, ...)
			path = path[segment]
			if not path then
				return true
			end
		end
		return not path
	end,

	-- Unlocks the given feature at the given XP cost.  The feature is
	-- specified as a path within the progression state, e.g.
	-- foo:unlock_feature(100, "properties", "melee", "crit_chance")
	unlock_feature = function(self, xp_cost, ...)
		local xp_available = self:get_available_xp()
		fassert(xp_cost <= xp_available, "Not enough XP to unlock (%d < %d)", xp_available, xp_cost)

		local path = data.unlocked
		local segment_count = select('#', ...)
		for i = 1, (segment_count - 1) do
			local segment = select(i, ...)
			path = path[segment]
			fassert(path, "Unlock segment not found: %s", segment)
		end
		path[select(segment_count, ...)] = true
		data.xp_spent = data.xp_spent + xp_cost

		progression_file:save(data)
	end,

	get_default_unlocks = function(self)
		return self.defaults.unlocked
	end,
}
