

local spider_trons = data.raw ["spider-vehicle"]
local defs = {}

for _, spider in pairs(spider_trons) do

	--log(serpent.block(spider))
	if (spider.icon_size and spider.icon_size <= 64) or (type(spider.icons) == "table") then
		local def = 
			{
				type = "item-with-tags",
				name = "spidersentinel-" .. spider.name .. "-item",
				icon_size = spider.icon_size,
				icons = spider.icons,
				icon = spider.icon,
				icon_mipmaps = spider.icon_mimaps,
				subgroup = "transport",
				order = "s[pidersentinel]",
				place_result = spider.name,
				flags = {"not-stackable"},
				stack_size = 1,
				extends_inventory_by_default = true
			}

		if (type(def.icon)=="string") then
			def.icons = { {icon=def.icon},{icon="__spidersentinel__/graphics/icons/tag.png" }}
			def.icon = nil
		elseif type(def.icons) == "table" then
			table.insert(def.icons, {icon="__spidersentinel__/graphics/icons/tag.png", icon_size=64 })
		end

		table.insert(defs, def)
	end
end

data:extend(defs)


