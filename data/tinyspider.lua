local item = table.deepcopy(data.raw["item-with-entity-data"]["spidertron"])
item.name = "spidersentinel_tinyspider"
item.enabled = true
item.place_result = "spidersentinel_tinyspider"
item.icon = "__spidersentinel__/graphics/icons/tinyspider.png"
item.icon_size = 64

local entity = create_spidertron {

	name = "spidersentinel_tinyspider",
	scale = 0.7,
	leg_scale = 0.75, -- relative to scale
	leg_thickness = 1.2, -- relative to leg_scale
	leg_movement_speed = 8
}

entity = data.raw["spider-vehicle"]["spidersentinel_tinyspider"]
entity.guns = { "vehicle-machine-gun", "vehicle-machine-gun" }
entity.icon = "__spidersentinel__/graphics/icons/tinyspider.png"
entity.icon_size = 64
entity.minable = {
	mining_time = 0.1,
	result = "spidersentinel_tinyspider"
}
entity.max_health = 1000
entity.inventory_size = 20
entity.trash_inventory_size = 10

local recipe = table.deepcopy(data.raw["recipe"]["spidertron"])
recipe.name = "spidersentinel_tinyspider"
recipe.icon = "__spidersentinel__/graphics/icons/tinyspider.png"
recipe.icon_size = 64
recipe.enabled = false
recipe.results = {{ type = "item", name = "spidersentinel_tinyspider", amount = 1 }}
recipe.ingredients = {
	{ type = "item", name = "electronic-circuit", amount = 50 },
	{ type = "item", name = "iron-plate",         amount = 100 },
	{ type = "item", name = "iron-stick",         amount = 50 },
	{ type = "item", name = "steel-plate",        amount = 200 }
}

data:extend { item, entity, recipe }

local tech = table.deepcopy(data.raw["technology"]["spidertron"])
tech.name = "spidersentinel_tinyspider"
tech.prerequisites = { "chemical-science-pack" }
tech.icon = "__spidersentinel__/graphics/technology/tinyspider.png"
tech.unit = {
	count = 200,
	ingredients = {
		{ 'automation-science-pack', 1 },
		{ 'logistic-science-pack',   1 },
		{ 'chemical-science-pack',   1 }
	},
	time = 15
}
tech.effects =
{
	{ type = "unlock-recipe", recipe = "spidersentinel_tinyspider" },
	{ type = "give-item",     item = "roboport",                        count = 5 },
	{ type = "give-item",     item = "logistic-robot",                  count = 10 },
	{ type = "give-item",     item = "construction-robot",              count = 10 },
	{ type = "give-item",     item = "passive-provider-chest", count = 5 }
}
data:extend { tech }
