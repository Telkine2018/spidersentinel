local def = {
	{
		type = "item-with-tags",
		name = "spidersentinel-item",
		icon_size = 64,
		icons = {
			{
				icon = "__spidersentinel__/graphics/icons/spidertron.png",
			}
		},
		icon_mipmaps = 4,
		subgroup = "transport",
		order = "s[pidersentinel]",
		place_result = "spidertron",
		flags = { "not-stackable" },
		stack_size = 1,
		extends_inventory_by_default = true
	}
}

data:extend(def)


local squad_tool = {

	type = "selection-tool",
	name = "spidersentinel-squad-tool",
	icon = "__spidersentinel__/graphics/icons/squad-tool.png",
	icon_size = 32,
	select = {
		border_color = { r = 0, g = 0, b = 1 },
		mode = { "same-force", "any-entity" },
		cursor_box_type = "entity",
		entity_type_filters = { "spider-vehicle" }
	},
	alt_select = {
		border_color = { r = 1, g = 0, b = 0 },
		mode = { "same-force", "any-entity" },
		cursor_box_type = "entity",
		entity_type_filters = { "spider-vehicle" },
	},
	flags = { "not-stackable", "only-in-cursor", "spawnable" },
	subgroup = "other",
	stack_size = 1,
	stackable = false
}

data:extend { squad_tool }

data:extend
{
	{
		type = "shortcut",
		name = "spidersentinel-squad-shortcut",
		order = "h[hotkeys]-s[c-chest]",
		action = "spawn-item",
		item_to_spawn = "spidersentinel-squad-tool",
		icon = "__spidersentinel__/graphics/icons/squad-tool-x32.png",
		icon_size = 32,
		small_icon = "__spidersentinel__/graphics/icons/squad-tool-x24.png",
		small_icon_size = 24
	}
}
