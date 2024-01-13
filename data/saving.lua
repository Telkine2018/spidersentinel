
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
			flags = {"hidden","not-stackable"},
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
		selection_color = { r=0, g=0, b=1 },
		alt_selection_color = { r=1, g=0, b=0 },
		selection_mode = {"same-force", "any-entity" },
		alt_selection_mode = {"same-force","any-entity"},
		selection_cursor_box_type = "entity",
		alt_selection_cursor_box_type =  "entity",
		flags = {"hidden", "not-stackable", "only-in-cursor", "spawnable"},
		subgroup = "other",
		stack_size = 1,
		entity_type_filters = {"spider-vehicle"},
		alt_entity_type_filters = {"spider-vehicle"},
		stackable = false,
		show_in_library = false
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
    icon =
    {
      filename = "__spidersentinel__/graphics/icons/squad-tool-x32.png",
      priority = "extra-high-no-scale",
      size = 32,
      scale = 1,
      flags = {"gui-icon"}
    },
    small_icon =
    {
      filename = "__spidersentinel__/graphics/icons/squad-tool-x24.png",
      priority = "extra-high-no-scale",
      size = 24,
      scale = 1,
      flags = {"gui-icon"}
    },
  },
}
