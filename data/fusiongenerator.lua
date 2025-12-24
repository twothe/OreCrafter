local name = "orecrafter-fusiongenerator"

local canCraft = settings.startup["orecrafter_fusiongenerator_craftable"].value
local powerAmount = settings.startup["orecrafter_fusiongenerator_power"].value

local tint = { a=1, r=0.8, g=0.5, b=0.8 }
local icons = { { icon = "__base__/graphics/icons/accumulator.png", tint = tint } }

local fusionGen = {
	collision_box = {	{-0.9, -0.9}, {0.9, 0.9} },
	corpse = "accumulator-remnants",
	damaged_trigger_effect = {
		damage_type_filters = "fire",
		entity_name = "spark-explosion",
		offset_deviation = { {-0.5, -0.5}, {0.5, 0.5} },
		offsets = { {0,	1} },
		type = "create-entity"
	},
	drawing_box = { {-1, -1.5},	{1,	1} },
	dying_explosion = "accumulator-explosion",
	type = "electric-energy-interface",
	energy_production = powerAmount.."kW",
	energy_usage = "0W",
	energy_source = {
	  type = "electric",
	  usage_priority = "primary-output",
    buffer_capacity = powerAmount.."kJ",
	  input_flow_limit = "0W",
	  output_flow_limit = powerAmount.."kW"
	},
	flags = {	"placeable-neutral", "player-creation" },
	icons = icons,
	icon_mipmaps = 4,
	icon_size = 64,
	max_health = 150,
	minable = {	mining_time = 0.5, result = name },
	name = name,
	picture = {
		layers = {
			{
				animation_speed = 0.5,
				filename = "__base__/graphics/entity/accumulator/accumulator.png",
				tint = tint,
				height = 94,
				hr_version = {
					animation_speed = 0.5,
					filename = "__base__/graphics/entity/accumulator/hr-accumulator.png",
					tint = tint,
					height = 189,
					priority = "high",
					scale = 0.5,
					shift = { 0, -0.34375 },
					width = 130
				},
				priority = "high",
				shift = { 0, -0.3125 },
				width = 66
			},
			{
				draw_as_shadow = true,
				filename = "__base__/graphics/entity/accumulator/accumulator-shadow.png",
				height = 54,
				hr_version = {
					draw_as_shadow = true,
					filename = "__base__/graphics/entity/accumulator/hr-accumulator-shadow.png",
					height = 106,
					priority = "high",
					scale = 0.5,
					shift = {	0.90625, 0.1875	},
					width = 234
				},
				priority = "high",
				shift = { 0.875, 0.1875 },
				width = 120
			}
		}
	},
	selection_box = { {-1, -1}, {1, 1} },
	vehicle_impact_sound = {
		{	filename = "__base__/sound/car-metal-impact-2.ogg",	volume = 0.5 },
		{	filename = "__base__/sound/car-metal-impact-3.ogg",	volume = 0.5 },
		{	filename = "__base__/sound/car-metal-impact-4.ogg",	volume = 0.5 },
		{	filename = "__base__/sound/car-metal-impact-5.ogg",	volume = 0.5 },
		{	filename = "__base__/sound/car-metal-impact-6.ogg",	volume = 0.5 }
	},
	water_reflection = {
		orientation_to_variation = false,
		pictures = {
			filename = "__base__/graphics/entity/accumulator/accumulator-reflection.png",
			tint = tint,
			height = 24,
			priority = "extra-high",
			scale = 5,
			shift = { 0, 1.5625 },
			variation_count = 1,
			width = 20
		},
		rotate = false
	},
}

local fusionGenItem = {
	icons = icons,
  icon_mipmaps = 4,
  icon_size = 64,
  name = name,
  order = "a1aaa",
  category = "crafting",
  subgroup = "orecrafter-dupe-bootstrap",
  place_result = name,
  stack_size = 50,
  type = "item"
}

local fusionGenRecipe={
	enabled = false,
	energy_required = 30,
	ingredients = {
		{ "steel-plate", 20 },
		{ "fusion-reactor-equipment", 2 },
		{ "accumulator", 1 },
		{ "copper-cable", 4 },
	},
	name = name,
	results = {
		{ type = "item", name = name, amount = 1 },
	},
	type = "recipe"
}

local fusionGenTech = {
	effects = { { recipe = name, type = "unlock-recipe" } },
	icon_mipmaps = 4,
	icon_size = 256,
	icons = {{ icon = "__base__/graphics/technology/electric-energy-acumulators.png", tint = tint }},
	name = name,
	order = "g-15",
	prerequisites = {
		"fusion-reactor-equipment",
		"electric-energy-accumulators"
	},
	type = "technology",
	unit = {
		count = 500,
		ingredients = {
			{	"automation-science-pack", 1 },
			{	"logistic-science-pack", 1 },
			{ "chemical-science-pack", 1 },
			{	"utility-science-pack", 1	}
		},
		time = 30
	}
}

data:extend{fusionGen, fusionGenItem}
if (canCraft) then
  data:extend{fusionGenRecipe, fusionGenTech}
end
