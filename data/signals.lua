


---@diagnostic disable-next-line: undefined-field
local signal = table.deepcopy(data.raw["virtual-signal"]["signal-A"])


signal=  {
    type = "virtual-signal",
    name = "spidersentinel-tag-marker",
    icon = "__spidersentinel__/graphics/icons/tag-marker.png",
	icon_size = 64,
    subgroup = "virtual-signal",
    order = "s[spider-sentinel]-a"
  }
  
 local on_off  = {
	type = "sprite",
	name = "on_off",
	filename = "__spidersentinel__/graphics/sprites/on_off.png",
	width = 40,
	height = 40
 }

data:extend { signal, on_off } 
