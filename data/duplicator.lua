
local prefix = "spidersentinel"


-- Item definition
local item = table.deepcopy(data.raw["item"]["requester-chest"])
item.name = prefix .. "_duplicator"
item.icon = "__" .. prefix .. "__/graphics/icons/duplicator.png"
item.stack_size = 10
item.enabled = true
item.place_result = prefix .. "_duplicator"
item.subgroup = "production-machine"
item.order = "b[personal-transport]-x[" .. prefix .. "-duplicator]"

-- Entity definition
local entity = table.deepcopy(data.raw["logistic-container"]["requester-chest"])
entity.name = prefix .. "_duplicator"
entity.icon = "__"..prefix.."__/graphics/icons/duplicator.png"
entity.animation.layers[1].filename = "__"..prefix.."__/graphics/entity/duplicator/hr-duplicator.png"
entity.minable = {
    mining_time = 0.1,
    result = prefix .. "_duplicator"
  }

-- Recipe definition
local recipe = table.deepcopy(data.raw["recipe"]["requester-chest"])
recipe.name = prefix .. "_duplicator"
recipe.enabled = false
recipe.results = {{ type="item", name=prefix .."_duplicator", amount=1}}

-- Add all
data:extend { item, entity, recipe }


local sp_tech = data.raw["technology"]["logistics"]
table.insert(sp_tech.effects, {
        type = "unlock-recipe",
        recipe = prefix .. "_duplicator"
      })
data:extend { sp_tech }
