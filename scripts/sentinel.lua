local mod_gui = require("mod-gui")

local pfx = "spidersentinel"

---@type {[integer]:Info}
local spiders = {}

local duplicators = nil

local duplicator_name = pfx .. "_duplicator"

local state_stopped = 0
local state_start = 1
local state_scanning = 2
local state_goto_position = 3
local state_attack = 4
local state_retreat = 5
local state_goto_base = 6
local state_local_scanning = 7
local state_wait_path_finding = 8
local state_follow_path_finding = 9

local state_names = {
    "stopped", "start", "scanning", "goto_position", "attack", "retreat",
    "goto_base", "local_scanning", "wait_path_finding", "follow_path_finding"
}

local ntick_delay = 20

local stuck_delta = 1

--[[

structure

radius = 300
attack_distance = 8
min_health = 2000
min_ammo = 400
retreat_if_no_ammo = true
collect_loot = false

state = state_start
start_position
target

--]]

---@param p1 MapPosition
---@param p2 MapPosition
---@return MapPosition
local vect_diff = function(p1, p2)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    return { x = dx, y = dy }
end

---@param p1 MapPosition
---@param p2 MapPosition
---@return MapPosition
local vect_add = function(p1, p2)
    local dx = p2.x + p1.x
    local dy = p2.y + p1.y
    return { x = dx, y = dy }
end

---@param v MapPosition
---@return MapPosition
local vect_normalize = function(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y)
    return { x = v.x / len, y = v.y / len }
end

---@param p1 MapPosition
---@param p2 MapPosition
---@return number
local vect_distance2 = function(p1, p2)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    return dx * dx + dy * dy
end

---@param p1 MapPosition
---@param p2 MapPosition
---@return number
local vect_distance = function(p1, p2)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    return math.sqrt(dx * dx + dy * dy)
end

local function get_vars(player)
    local players = global.players
    if not players then
        players = {}
        global.players = players
    end
    local vars = players[player.index]
    if not vars then
        vars = {}
        players[player.index] = vars
    end
    return vars
end

local tracing = true
local debug_index = 1

---@param msg LocalisedString
local function debug(msg)
    if not tracing then return end
    msg = { "", "[" .. debug_index .. "] ", msg }
    debug_index = debug_index + 1
    game.print(msg)
    log(msg)
end

---@param str string
---@param ending string
---@return boolean
local function ends_with(str, ending)
    return ending == "" or str:sub(- #ending) == ending
end

---@return integer
local function get_id()
    local id = global.id or 1
    id = id + 1
    global.id = id
    return id
end

local on_gui_closed
local update_gui
local remove_radius_circle
local close_player_gui
local get_info_spider

---@param info Info
---@return boolean
local function is_squad_started(info)
    local squad = info.squad
    if not squad or squad == 0 then return info.state ~= state_stopped end
    for _, info2 in pairs(spiders) do
        if info2.squad == squad and info2.state ~= state_stopped then
            return true
        end
    end
    return false
end

---@param info Info
---@param f fun(i:Info)
local function apply_squad(info, f)
    local squad = info.squad
    if not squad then
        f(info)
        return
    else
        for _, info in pairs(spiders) do
            if info.squad == squad then f(info) end
        end
    end
end

---@param squad integer
local function display_squad_id(squad)
    for _, info in pairs(spiders) do
        if info.squad == squad then
            local entity = info.entity
            if entity.valid then
                if info.id_label then
                    rendering.destroy(info.id_label)
                end
                info.id_label = rendering.draw_text {
                    target_offset = { 0, 0 },
                    text = tostring(squad),
                    surface = entity.surface,
                    target = entity,
                    color = { 1, 1, 0 }
                }
            end
        end
    end
end

---@param entity LuaEntity
---@param tags any Tags
local function set_tags(entity, tags)
    ---@param inv LuaInventory?
    ---@param def any
    local function restore_inventory(inv, def)
        if not inv or not def then return end
        for _, stack_info in pairs(def) do
            local type = stack_info.type
            if type == "item" then
                inv.insert { name = stack_info.name, count = stack_info.count }
            elseif type == "export" then
                local empty = inv.find_empty_stack()
                if empty then
                    empty.import_stack(stack_info.value)
                end
            end
        end
    end

    restore_inventory(entity.get_inventory(defines.inventory.spider_trunk), tags.spider_trunk)
    restore_inventory(entity.get_inventory(defines.inventory.spider_ammo), tags.spider_ammo)
    restore_inventory(entity.get_inventory(defines.inventory.spider_trash), tags.spider_trash)
    restore_inventory(entity.get_inventory(defines.inventory.fuel), tags.fuel)

    if tags.grid then
        local grid = entity.grid
        for _, gridelement in pairs(tags.grid) do
            local energy = gridelement.energy
            local shield = gridelement.shield
            gridelement.energy = nil
            gridelement.shield = nil
            local equip = grid.put(gridelement)
            if energy and energy > 0 then
                equip.energy = energy
            end
            if shield and shield > 0 then
                equip.shield = shield
            end
        end
    end

    if tags.logistics then
        for _, slot in pairs(tags.logistics) do
            entity.set_vehicle_logistic_slot(slot.index, {
                name = slot.name,
                min = slot.min,
                max = slot.max
            })
        end
    end

    entity.color = tags.color
    entity.health = tags.health

    local info = get_info_spider(entity)
    if tags.radius then
        info.radius = tags.radius
        info.min_health = tags.min_health
        info.retreat_if_no_ammo = tags.retreat_if_no_ammo
        info.min_ammo = tags.min_ammo
        info.collect_loot = tags.collect_loot
        info.state = tags.state
        info.squad = tags.squad
    end

    if tags.label then entity.entity_label = tags.label end

    local param = entity.vehicle_automatic_targeting_parameters
    param.auto_target_without_gunner = true
    param.auto_target_with_gunner = true
    entity.vehicle_automatic_targeting_parameters = param
end

---@param squad integer
---@param leader_id any
local function make_follow(squad, leader_id)
    local leader_info = spiders[leader_id]
    if not leader_info or not leader_info.entity.valid then return end

    for _, info in pairs(spiders) do
        if info.squad == squad and info.entity.valid and info.entity.unit_number ~= leader_id then
            info.entity.follow_target = leader_info.entity
            info.entity.follow_offset = vect_diff(leader_info.entity.position, info.entity.position) --[[@as Vector]]
            info.state = state_stopped
        end
    end
end

---@return integer
local function allocate_squad_id()
    local map = {}
    for _, spider in pairs(spiders) do
        if spider.squad and spider.squad ~= 0 then
            map[spider.squad] = true
        end
    end
    local index = 1
    while true do
        if not map[index] then return index end
        index = index + 1
    end
end

---@param evt EventData.on_built_entity | EventData.on_robot_built_entity
local function on_built_entity(evt)
    local entity = evt.created_entity or evt.entity
    local force = entity.force
    local surface = entity.surface
    local entity_name = entity.name

    if entity.type == "spider-vehicle" then
        local player = game.players[evt.player_index]
        local tags = evt.stack and evt.stack.is_item_with_tags and
            evt.stack.tags
        if tags and tags.spidersentinel then
            set_tags(entity, tags)

            local info = get_info_spider(entity)
            if tags.squad_spiders then
                local squad = allocate_squad_id()
                info.squad = squad

                for _, def in pairs(tags.squad_spiders --[[@as table]]) do
                    local position = entity.position
                    local entity2 = surface.create_entity {
                        name = def.name,
                        force = force,
                        position = vect_add(position, def.squad_position)
                    }
                    ---@cast entity2 -nil
                    def.squad = squad
                    set_tags(entity2, def)
                end

                local label = evt.stack.label
                if label and not string.find(label, "^Squad%(") then
                    entity.entity_label = label
                end

                make_follow(squad, entity.unit_number)
                display_squad_id(squad)
            end
        end
    elseif entity_name == duplicator_name then
        if not duplicators then
            duplicators = {}
            global.duplicators = duplicators
        end
        -- debug("Add duplicator")
        duplicators[entity.unit_number] = {
            id = entity.unit_number,
            entity = entity,
            tick = game.tick
        }
    end
end

---@param e LuaEntity
local function on_remove_entity(e)
    local entity = e.entity

    if entity.type == "spider-vehicle" then
        spiders[entity.unit_number] = nil
        if game.players then
            for id, vars in pairs(game.players) do
                if vars.selected == entity then
                    remove_radius_circle(game.players[id])
                    close_player_gui(game.players[id])
                end
            end
        end
    elseif entity.name == duplicator_name then
        if not duplicators then return end
        -- debug("Remove duplicator")
        duplicators[entity.unit_number] = nil
    end
end

---@param entity LuaEntity
local function get_tags(entity)
    local entity_name = entity.name
    local spider_trunk = entity.get_inventory(defines.inventory.spider_trunk)
    local spider_ammo = entity.get_inventory(defines.inventory.spider_ammo)
    local spider_trash = entity.get_inventory(defines.inventory.spider_trash)
    local fuel = entity.get_inventory(defines.inventory.fuel)

    local function serialize_inventory(inv)
        if not inv then return {} end

        -- debug("Inventory: #" .. #inv)
        local result = {}
        for i = 1, #inv do
            local stack = inv[i]
            if stack and stack.count > 0 then
                if stack.is_blueprint or stack.is_blueprint_book or
                    stack.is_item_with_tags then
                    local export_stack = stack.export_stack()
                    table.insert(result, { type = "export", value = export_stack })
                else
                    table.insert(result, {
                        type = "item",
                        name = stack.name,
                        count = stack.count
                    })
                end
            end
        end
        if #result == 0 then return nil end
        return result
    end

    local grid = entity.grid
    local equipment_list = {}
    if grid then
        for _, equipment in pairs(grid.equipment) do
            table.insert(equipment_list,
                { name = equipment.name, position = equipment.position, energy = equipment.energy, shield = equipment.shield })
        end
    end

    local logistics = {}
    for i = 1, 100 do
        local slot = entity.get_vehicle_logistic_slot(i)
        if slot.name then
            table.insert(logistics, {
                index = i,
                name = slot.name,
                min = slot.min,
                max = slot.max
            })
        end
    end

    local tags = {
        name = entity_name,
        spider_trunk = serialize_inventory(spider_trunk),
        spider_ammo = serialize_inventory(spider_ammo),
        spider_trash = serialize_inventory(spider_trash),
        fuel = serialize_inventory(fuel),
        grid = equipment_list,
        logistics = logistics,
        color = entity.color,
        spidersentinel = 1,
        health = entity.health,
        label = entity.entity_label
    }

    local info = spiders[entity.unit_number]
    if info then
        tags.radius = info.radius
        tags.min_health = info.min_health
        tags.retreat_if_no_ammo = info.retreat_if_no_ammo
        tags.min_ammo = info.min_ammo
        tags.collect_loot = info.collect_loot
        tags.state = state_stopped
        tags.squad = info.squad
    end

    ---@cast spider_trunk -nil
    ---@cast spider_ammo -nil
    ---@cast spider_trash -nil

    spider_trunk.clear()
    spider_ammo.clear()
    spider_trash.clear()
    if fuel then fuel.clear() end

    return tags
end

---@param tags Tags
---@param content {[string]:integer}?
---@return {[string]:integer}
local function get_required_items_for_tags(tags, content)
    local name = tags.name
    if not content then content = {} end

    local function add_to_inventory(name, count)
        local prev = content[name]
        if prev then
            content[name] = prev + count
        else
            content[name] = count
        end
    end

    local function count_inventory(inv)
        if not inv then return end
        for _, e in ipairs(inv) do add_to_inventory(e.name, e.count) end
    end

    count_inventory(tags.spider_trunk)
    count_inventory(tags.spider_ammo)
    count_inventory(tags.spider_trash)
    count_inventory(tags.fuel)
    if tags.grid then
        for _, e in pairs(tags.grid --[[@as table]]) do add_to_inventory(e.name, 1) end
    end

    add_to_inventory(name, 1)

    if tags.squad_spiders then
        for _, tags2 in pairs(tags.squad_spiders --[[@as table]]) do
            get_required_items_for_tags(tags2, content)
        end
    end

    return content
end

---@param duplicator Duplicator
local function process_duplicator(duplicator)
    -- debug("Process duplicator")
    local chest = duplicator.entity
    if not chest.valid then return end
    local inv = chest.get_inventory(defines.inventory.chest)
    ---@cast inv -nil

    local tags
    for i = 1, #inv do
        local stack = inv[i]
        if stack.is_item_with_tags then
            tags = stack.tags
            if tags.spidersentinel == 1 then break end
        end
    end

    for i = 1, chest.request_slot_count do chest.clear_request_slot(i) end
    if not tags then
        duplicator.previous = nil
        -- debug("No squad")
        return
    end

    local items = get_required_items_for_tags(tags)
    duplicator.items = items

    -- debug(string.gsub(serpent.block(items), "%s", ""))

    local index = 1
    for name, count in pairs(items) do
        if index > 20 then break end
        chest.set_request_slot({ name = name, count = count }, index)
        index = index + 1
    end

    local contents = inv.get_contents()
    for rname, rcount in pairs(items) do
        local count = contents[rname]
        if not count or rcount > count then
            -- debug("Missing: ".. rname)
            return
        end
    end

    local name = "spidersentinel-" .. tags.name .. "-item"
    local stack, stack_index = inv.find_empty_stack(name)
    if not stack then
        -- debug("no room")
        return
    end

    if inv.insert({ name = name, count = 1 }) == 0 then return end
    stack = inv[stack_index]
    if not stack.valid or not stack.valid_for_read then
        stack.clear()
        -- debug("Invalid stack")
        return
    end
    stack.tags = tags

    for rname, rcount in pairs(items) do
        inv.remove({ name = rname, count = rcount })
    end
end

local function on_pre_player_mined_item(e)
    if not settings.global["spidersentinel-conservative-mining"].value then
        return
    end

    local entity = e.entity
    local tags = get_tags(entity)
    local info = spiders[entity.unit_number]
    if info and info.squad then
        local squad_spiders = {}
        local position = entity.position
        local to_remove = {}
        local squad = info.squad

        -- debug("Mine squad:" .. squad)
        for _, info2 in pairs(spiders) do
            if info2 ~= info and info2.squad == squad and
                vect_distance(position, info2.entity.position) < 300 then
                local tags2 = get_tags(info2.entity)
                tags2.squad_position =
                    vect_diff(position, info2.entity.position)
                table.insert(to_remove, info2.entity.unit_number)
                info2.entity.destroy()
                table.insert(squad_spiders, tags2)
            end
        end
        for _, id in pairs(to_remove) do spiders[id] = nil end
        if #to_remove == 0 then
            tags.squad = nil
        else
            tags.squad_spiders = squad_spiders
        end
    end

    if not tags.squad and not tags.spider_trunk and not tags.spider_ammo and
        not tags.spider_trash then
        tags = nil
    end
    global.current_tags = tags
end

local function on_player_mined_entity(e)
    local entity = e.entity
    local surface = entity.surface
    local entity_name = entity.name

    if settings.global["spidersentinel-conservative-mining"].value then
        local tags = global.current_tags
        if tags then
            e.buffer.clear()
            e.buffer.insert {
                name = "spidersentinel-" .. entity_name .. "-item",
                count = 1
            }

            local stack = e.buffer[1]
            stack.tags = tags
            global.current_tags = nil

            local label = entity.entity_label
            if tags.squad_spiders then
                if (not label) then
                    label = "Squad(" .. (#tags.squad_spiders + 1) ..
                        " spidertrons)"
                end
                stack.label = label
            elseif label then
                stack.label = label
            end
            -- debug(string.gsub("TAGS:" .. serpent.block(tags), "%s", ""))
        end
    end
    on_remove_entity(e)
end

local function on_selected_area(event)
    local player = game.players[event.player_index]

    if event.item ~= "spidersentinel-squad-tool" then return end

    local entities = event.entities
    if #entities == 0 then return end

    local squad = allocate_squad_id()
    local nearest
    local nearest_d
    local force_index = player.force_index
    for _, spider in pairs(entities) do
        if spider.force_index == force_index then
            local info = get_info_spider(spider)
            if info.id_label then
                rendering.destroy(info.id_label)
                info.id_label = nil
            end
            info.squad = squad
            local d
            if not nearest then
                nearest = info.entity
                nearest_d = vect_distance(nearest.position, player.position)
            else
                d = vect_distance(info.entity.position, player.position)
                if d < nearest_d then
                    nearest = info.entity
                    nearest_d = d
                end
            end
        end
    end

    display_squad_id(squad)

    local vehicle = player.vehicle
    if vehicle and spiders[vehicle.unit_number] and
        spiders[vehicle.unit_number].squad == squad then
        make_follow(squad, vehicle.unit_number)
    elseif nearest then
        make_follow(squad, nearest.unit_number)
    end

    if (spiders) then
        for _, info in pairs(spiders) do
            local spider = info.entity
            if spider.valid and info.squad ~= squad then
                local follow_target = spider.follow_target
                if follow_target then
                    local follow_info = spiders[follow_target.unit_number]
                    if follow_info then
                        if follow_info.squad ~= info.squad then
                            spider.follow_target = nil
                        end
                    end
                end
            end
        end
    end

    local selected = get_vars(player).selected
    if selected and selected.valid then
        local info = spiders[selected.unit_number]
        update_gui(player, info)
    end
end

---@param event EventData.on_player_alt_selected_area
local function on_player_alt_selected_area(event)
    local player = game.players[event.player_index]

    if event.item ~= "spidersentinel-squad-tool" then return end
    local force_index = player.force_index

    local entities = event.entities
    for _, spider in pairs(entities) do
        if spider.force_index == force_index then
            local info = get_info_spider(spider)
            info.squad = nil
            spider.follow_target = nil
            if info.id_label then
                rendering.destroy(info.id_label)
                info.id_label = nil
            end
        end
    end
end

---@param spider LuaEntity
---@return Info
get_info_spider = function(spider)
    local info = spiders[spider.unit_number]
    if info then return info end

    local _, gun = next(spider.prototype.guns)
    local range = math.ceil(gun.attack_parameters.range * 0.6)

    info = {

        state = state_stopped,
        attack_distance = range,
        radius = 300,
        min_health = spider.prototype.max_health / 4,
        retreat_if_no_ammo = true,
        min_ammo = 300,
        collect_loot = false,
        start_position = spider.position,
        entity = spider
    }

    spiders[spider.unit_number] = info
    return info
end

local check_if_stuck

---@param info Info
---@return LuaEntity?
---@return number?
local find_nearest_ennemi = function(info)
    local current_position = info.entity.position
    info.target            = info.entity.surface.find_nearest_enemy { position = current_position, max_distance = info.radius }
    if not info.target then
        return nil
    end
    local dist = vect_distance(info.target.position, info.start_position)
    if dist > info.radius then
        return nil
    end
    return info.target, dist
end

---@param info Info
---@return LuaEntity?
---@return number?
local find_local_nearest_ennemi = function(info)
    info.target = nil
    local current_position = info.entity.position
    local ennemies = info.entity.surface.find_enemy_units(current_position, 50)
    if #ennemies == 0 then
        return nil
    else
        local found = nil
        local min
        for _, e in ipairs(ennemies) do
            local health_ratio = e.get_health_ratio()
            if health_ratio and health_ratio > 0 then
                if vect_distance(e.position, info.start_position) <= info.radius then
                    local d = vect_distance(e.position, current_position)
                    if not found or d < min then
                        found = e
                        min = d
                    end
                end
            end
        end
        if not found then return nil end

        info.target = found

        -- log("find_nearest_ennemi: position=(" .. found.position.x .. "," .. found.position.y ..")")
        return found, min
    end
end

---@param info Info
---@return boolean
local function start_path_finding(info)
    info.path = nil
    local position = info.entity.position
    local tiles = info.entity.surface.find_tiles_filtered {
        position = position,
        radius = 20
    }

    local found, found_dist, found_key
    local failed_map = info.failed_map
    for _, tile in pairs(tiles) do
        if not tile.collides_with("player-layer") then
            local key = tostring(tile.position.x) .. "/" .. tostring(tile.position.y)
            if not failed_map[key] then
                local d = vect_distance(tile.position --[[@as MapPosition]], position)
                if not found or d < found_dist then
                    found_dist = d
                    found = tile
                    found_key = key
                end
            end
        end
    end

    if not found then
        -- debug("found = nil")
        return false
    end

    -- debug("Search initial position: " .. found.name .. "," .. string.gsub(serpent.block(found.position), "%s", "") .. "," .. string.gsub(serpent.block(info.entity.position), "%s", ""))


    failed_map[found_key] = true
    info.path_start = found.position --[[@as MapPosition]]
    info.path_finder_handle = info.entity.surface.request_path {
        bounding_box = info.bounding_box,
        collision_mask = info.collision_mask,
        start = found.position --[[@as MapPosition]],
        goal = info.path_end,
        force = info.entity.force,
        pathfind_flags = {
            no_break = true,
            allow_paths_through_own_entities = true,
            cache = false,
            prefer_straight_paths = true
        },
        entity_to_ignore = info.entity,
        can_open_gates = true,
        low_priority = true

    }

    return true
end

---@param info Info
---@param target_position MapPosition
---@return boolean
check_if_stuck = function(info, target_position)
    local position = info.entity.position
    if vect_distance(position, target_position) < 10 then return false end

    if info.old_pos and vect_distance(info.old_pos, position) < stuck_delta then
        info.stuck_count = (info.stuck_count or 0) + 1

        if info.stuck_count > 6 then
            info.path = nil
            info.collision_mask = { "water-tile" }
            info.bounding_box = { { -0.01, -0.01 }, { 0.01, 0.01 } }
            info.failed_map = {}
            info.path_middle = nil
            info.path_end = target_position

            if not start_path_finding(info) then
                info.stuck_count = 0
                return false
            end

            info.state = state_wait_path_finding
            info.stuck_count = 0
            return true
        end
    else
        info.stuck_count = 0
        info.old_pos = position
    end
    return false
end

---@param e EventData.on_script_path_request_finished
local function on_script_path_request_finished(e)
    for _, info in pairs(spiders) do
        if info.path_finder_handle == e.id then
            if not e.path then
                local d = vect_distance(info.path_start, info.path_end)

                -- debug("path finder fail, try again="..tostring(e.try_again_later))

                if d > 200 and not info.path_middle then
                    -- debug("path finder fail: try middle")

                    local start = info.path_start
                    local n = vect_normalize(vect_diff(start, info.path_end))
                    d = d / 2
                    local new_end = {
                        x = start.x + d * n.x,
                        y = start.y + d * n.y
                    }
                    info.path_end = new_end
                    info.path_finder_handle =
                        info.entity.surface.request_path {
                            bounding_box = info.bounding_box,
                            collision_mask = info.collision_mask,
                            start = info.path_start,
                            goal = info.path_end,
                            force = info.entity.force,
                            pathfind_flags = {
                                prefer_straight_paths = true,
                                no_break = true
                            },
                            entity_to_ignore = info.entity,
                            can_open_gates = true,
                            low_priority = true
                        }
                    info.path_middle = true
                else
                    if not start_path_finding(info) then
                        info.state = info.return_state
                    end
                end
            else
                info.path = e.path
            end
        end
    end
end

---@param info Info
local function goto_target(info)
    local target_position = info.target.position
    local position = info.entity.position
    local d = vect_diff(position, target_position)
    local n = vect_normalize(d)
    local attack_distance = info.attack_distance - 1
    local dest = {
        x = target_position.x - attack_distance * n.x,
        y = target_position.y - attack_distance * n.y
    }
    info.entity.autopilot_destination = dest
    info.state = state_goto_position

    if check_if_stuck(info, target_position) then
        info.return_state = state_local_scanning
    end

    -- log("goto_target: x=".. dest.x .. ",y=" .. dest.y .. ",target=" .. target_position.x .."," .. target_position.y ..",n=" .. n.x .. "," .. n.y)
end

---@param info Info
local function check_ennemy(info)
    -- log("check_ennemy: start")
    local tick = game.tick / ntick_delay
    if (tick + info.entity.unit_number) % 15 ~= 0 then return false end

    local ennemy, d = find_nearest_ennemi(info)
    if not ennemy then
        -- log("check_ennemy: no ennemy")
        return false
    end

    if d < info.attack_distance + 1 then
        info.state = state_attack
        -- log("check_ennemy: state=state_attack,d="..d)
        return true
    end

    goto_target(info)
    -- log("check_ennemy: state=state_goto_position,d="..d)
    return true
end

---@param info Info
local function check_local_ennemy(info)
    -- log("check_local_ennemy: start")

    local ennemy, d = find_local_nearest_ennemi(info)
    if not ennemy then
        ennemy, d = find_nearest_ennemi(info)
        if not ennemy then
            -- log("check_local_ennemy: no ennemy")
            info.state = state_scanning
            return false
        end
    end

    if d < info.attack_distance + 1 then
        info.state = state_attack
        -- log("check_local_ennemy: state=state_attack,d="..d)
        return true
    end

    goto_target(info)
    -- log("check_local_ennemy: state=state_goto_position,d="..d)
    return true
end

---@param info Info
local function check_target(info)
    if not info.target or not info.target.valid or
        info.target.get_health_ratio() == 0 then
        info.state = state_local_scanning
        info.target = nil
        -- log("check_target: state=state_scanning")
        return false
    end
    return true
end

---@param info Info
local function is_ammo_empty(info)
    local inv = info.entity.get_inventory(defines.inventory.spider_ammo)
    ---@cast inv -nil
    local result = inv.is_empty()
    return result
end

---@param info Info
local function check_retreat(info)
    if info.retreat_if_no_ammo and is_ammo_empty(info) then
        info.state = state_retreat
        info.target = nil
        -- log("check_retreat: ammo empty => retreat")
        return true
    end

    if info.entity.health < info.min_health then
        info.state = state_retreat
        info.target = nil
        -- log("check_retreat: health => retreat")
        return true
    end

    return false
end

---@param info Info
local function process_spider(info)
    if not info.entity.valid then return end

    if info.collect_loot then
        local pos = info.entity.position
        local area_size = 20
        local area = {
            { pos.x - area_size, pos.y - area_size },
            { pos.x + area_size, pos.y + area_size }
        }
        local force = info.entity.force
        local loot_entities = info.entity.surface.find_entities_filtered {
            type = "item-entity",
            area = area,
            force = { "player", "neutral" }
        }
        for _, e in pairs(loot_entities) do e.order_deconstruction(force) end
    end

    local state = info.state
    -- debug("process: state=" .. state_names[state+1] .. ",position=(" .. info.entity.position.x .. "," .. info.entity.position.y ..")")

    if state == state_stopped then return end
    if state == state_start then
        check_ennemy(info)
    elseif state == state_scanning then
        if not check_ennemy(info) then info.state = state_goto_base end
    elseif state == state_local_scanning then
        if not check_local_ennemy(info) then info.state = state_scanning end
    elseif state == state_goto_position then
        if check_retreat(info) then return end
        if not check_target(info) then return end

        local d = vect_distance(info.entity.position, info.target.position)
        if d < info.attack_distance then
            -- log("state = state_attack,d=" .. d)
            info.state = state_attack
            return
        end
        goto_target(info)
    elseif state == state_attack then
        if check_retreat(info) then return end
        if not check_target(info) then return end

        local target_position = info.target.position
        local d = vect_distance(info.entity.position, info.target.position)
        if d > info.attack_distance + 1 then
            info.state = state_goto_position
            return
        end
    elseif state == state_goto_base then
        if not check_ennemy(info) then
            info.entity.autopilot_destination = info.start_position
            if check_if_stuck(info, info.start_position) then
                info.return_state = state_goto_base
            end
        end
    elseif state == state_retreat then
        if vect_distance(info.entity.position, info.start_position) < 2 then
            if info.entity.get_health_ratio() >= 1 then
                local inv = info.entity.get_inventory(defines.inventory.spider_ammo)
                ---@cast inv -nil
                if info.min_ammo > 0 then
                    local contents = inv.get_contents()
                    local count = 0
                    for _, c in pairs(contents) do
                        count = count + c
                    end
                    if count >= info.min_ammo then
                        info.state = state_scanning
                    end
                else
                    info.state = state_scanning
                end
            end
        else
            if check_if_stuck(info, info.start_position) then
                info.return_state = state_retreat
            else
                info.entity.autopilot_destination = info.start_position
            end
        end
    elseif state == state_wait_path_finding then
        local path = info.path
        if path then
            info.path_endpoint = path[#path].position
            info.entity.autopilot_destination = nil
            local dx = 0
            local dy = 0
            local previous = nil
            for _, wp in pairs(path) do
                local position = wp.position
                if not previous then
                    previous = position
                else
                    local newdx = position.x - previous.x
                    local newdy = position.y - previous.y
                    if math.abs(newdx - dx) >= 0.01 or math.abs(newdy - dy) >=
                        0.01 then
                        info.entity.add_autopilot_destination(previous)
                        previous = position
                        dx = newdx
                        dy = newdy
                    else
                        previous = position
                    end
                end
            end
            if previous then
                info.entity.add_autopilot_destination(previous)
            end
            info.path = nil
            info.state = state_follow_path_finding
        end
    elseif state == state_follow_path_finding then
        local position = info.entity.position
        if vect_distance(position, info.path_endpoint) < info.attack_distance then
            info.state = info.return_state
        elseif info.entity.speed > 0.1 then
            local positions = info.entity.autopilot_destinations
            if #positions > 2 then
                local pos1 = positions[1]
                local pos2 = positions[2]
                local ax = (position.x - pos1.x) * (pos2.x - position.x)
                local ay = (position.y - pos1.y) * (pos2.y - position.y)
                local is_dx = math.abs(position.x - pos1.x) >=
                    math.abs(position.x - pos2.x)
                local is_dy = math.abs(position.y - pos1.y) >=
                    math.abs(position.y - pos2.y)

                -- debug("position=[" .. position.x .. "," .. position.y .. "],pos1=[" ..pos1.x .."," .. pos1.y .. "],pos2=[" .. pos2.x .."," .. pos2.y .. "], ax="..ax ..",dy=" .. ay)
                if ax > 0 or ay > 0 or (is_dx and is_dy) then
                    info.entity.autopilot_destination = nil

                    local dx = pos2.x - pos1.x
                    local dy = pos2.y - pos1.y
                    local index = 2
                    while (index < #positions) do
                        local new_dx = positions[index + 1].x -
                            positions[index].x
                        local new_dy = positions[index + 1].y -
                            positions[index].y
                        if math.abs(new_dx - dx) >= 0.01 or
                            math.abs(new_dy - dy) >= 0.01 then
                            break
                        end
                        index = index + 1
                    end

                    -- debug("skip first position")
                    for i = index, #positions do
                        info.entity.add_autopilot_destination(positions[i])
                    end
                end
            end
        end
    end
end

---@param info Info
local function start(info)
    info.state = state_start
    info.start_position = info.entity.position
    local squad = info.squad
    if squad then
        for _, i in pairs(spiders) do
            if i.squad == squad and i ~= info then
                i.state = state_stopped
                i.entity.autopilot_destination = nil
            end
        end
        make_follow(squad, info.entity.unit_number)
    end
end

-- ------------------------------
-- Gui

local tag_signal = "spidersentinel-tag-marker"

---@param player LuaPlayer
remove_radius_circle = function(player)
    local tags = get_vars(player).tags
    if not tags then return end
    get_vars(player).tags = nil

    local radius_id = tags.radius_id
    if radius_id then rendering.destroy(radius_id) end

    if tags.force and tags.surface then
        local force = game.forces[tags.force]
        if tags.surface.valid then
            local tags = force.find_chart_tags(tags.surface)
            for _, t in ipairs(tags) do
                if t.icon and t.icon.name == tag_signal then
                    t.destroy()
                end
            end
        end
    end
end

---@param info Info
---@param player LuaPlayer
local function display_radius_circle(info, player)
    remove_radius_circle(player)

    local tags = {}
    if info.radius < 80 then
        local target
        if is_squad_started(info) then
            target = info.start_position
        else
            target = info.entity
        end
        tags.radius_id = rendering.draw_circle {
            color = { 1, 0, 0, 0.5 },
            radius = info.radius,
            width = 30,
            target = target,
            surface = info.entity.surface,
            draw_on_ground = true
        }
    else
        local position
        if is_squad_started(info) then
            position = info.start_position
        else
            position = info.entity.position
        end
        local surface = info.entity.surface
        local force = info.entity.force
        local count = math.floor(32 * info.radius / 200)

        for i = 0, 2 * count - 1 do
            local angle = i * math.pi / count
            local cos = math.cos(angle)
            local sin = math.sin(angle)

            local x = position.x + info.radius * cos
            local y = position.y + info.radius * sin

            force.add_chart_tag(surface, {
                icon = { type = "virtual", name = tag_signal },
                position = { x, y }
            })
        end
        tags.surface = surface
        tags.force = force.name
        tags.position = position
    end
    tags.info = info
    get_vars(player).tags = tags
end

---@param frame LuaGuiElement
local function add_title(frame)
    local titlebar = frame.add { type = "flow", direction = "horizontal" }
    local title = titlebar.add {
        type = "label",
        style = "caption_label",
        caption = { "parameters_dialog.title" }
    }
    local handle = titlebar.add {
        type = "empty-widget",
        style = "draggable_space"
    }
    handle.style.horizontally_stretchable = true
    handle.style.top_margin = 4
    handle.style.height = 26
    handle.style.width = 200

    local flow_buttonbar = titlebar.add {
        type = "flow",
        direction = "horizontal"
    }
    flow_buttonbar.style.top_margin = 0
    local closeButton = flow_buttonbar.add {
        type = "sprite-button",
        name = pfx .. "_close_button",
        style = "frame_action_button",
        sprite = "utility/close_white",
        mouse_button_filter = { "left" }
    }
end

---@param event EventData.on_gui_opened
local function on_gui_opened(event)
    local player = game.players[event.player_index]
    local entity = event.entity
    if not entity or not entity.valid then return end

    get_vars(player).selected = nil
    if entity.type ~= "spider-vehicle" then
        close_player_gui(player)
        return
    end

    if get_vars(player).no_interface then
        get_vars(player).selected = entity
        return
    end

    remove_radius_circle(player)
    if not spiders then
        spiders = {}
        global.spiders = spiders
    end

    close_player_gui(player)

    get_vars(player).selected = entity
    local info = get_info_spider(entity)
    local enabled = not is_squad_started(info)

    local panel = player.gui.left.add {
        type = "frame",
        name = pfx .. "_frame",
        direction = "vertical"
    }

    add_title(panel)

    local f
    local flow = panel.add { type = "table", column_count = 2 }
    flow.add { type = "label", caption = { "parameters_dialog.radius" } }
    f = flow.add {
        type = "textfield",
        name = pfx .. "_radius",
        text = tostring(info.radius),
        numeric = true,
        allow_negative = false,
        enabled = enabled
    }
    f.style.width = 50

    flow.add { type = "label", caption = { "parameters_dialog.attack_distance" } }
    f = flow.add {
        type = "textfield",
        name = pfx .. "_attack_distance",
        text = tostring(info.attack_distance),
        numeric = true,
        allow_negative = false,
        enabled = enabled
    }
    f.style.width = 50

    flow.add { type = "label", caption = { "parameters_dialog.min_health" } }
    f = flow.add {
        type = "textfield",
        name = pfx .. "_min_health",
        text = tostring(info.min_health),
        numeric = true,
        allow_negative = false,
        enabled = enabled
    }
    f.style.width = 50

    flow.add { type = "label", caption = { "parameters_dialog.min_ammo" } }
    f = flow.add {
        type = "textfield",
        name = pfx .. "_min_ammo",
        text = tostring(info.min_ammo),
        numeric = true,
        allow_negative = false,
        enabled = enabled
    }
    f.style.width = 50

    flow.add {
        type = "label",
        caption = { "parameters_dialog.retreat_if_no_ammo" }
    }
    flow.add {
        type = "checkbox",
        name = pfx .. "_retreat_if_no_ammo",
        state = info.retreat_if_no_ammo,
        enabled = enabled
    }

    flow.add { type = "label", caption = { "parameters_dialog.collect_loot" } }
    flow.add {
        type = "checkbox",
        name = pfx .. "_collect_loot",
        state = not not info.collect_loot,
        enabled = enabled
    }

    local caption
    local can_retreat
    if enabled then
        caption = { "button.start" }
        can_retreat = false
    else
        caption = { "button.stop" }
        can_retreat = true
    end

    -- local flow = panel.add{type="flow",direction="horizontal"}
    local b = panel.add {
        type = "button",
        name = pfx .. "_start",
        caption = caption
    }
    b.style.top_margin = 10
    b.style.horizontally_stretchable = true
    b.style.horizontal_align = "center"

    b = panel.add {
        type = "button",
        name = pfx .. "_retreat",
        caption = { "button.retreat" }
    }
    b.style.horizontally_stretchable = true
    b.style.horizontal_align = "center"
    b.enabled = can_retreat

    display_radius_circle(info, player)
end

---@param player LuaPlayer
close_player_gui = function(player)
    local frame = player.gui.left[pfx .. "_frame"]
    if frame then frame.destroy() end
end

---@param event EventData.on_gui_closed
on_gui_closed = function(event)
    local player = game.players[event.player_index]
    close_player_gui(player)
end

---@param name string
---@param parent LuaGuiElement
---@return LuaGuiElement?
local function get_field(name, parent)
    local elements = parent.children
    for _, e in pairs(elements) do
        if e.name == name then return e end
        local found = get_field(name, e)
        if found then return found end
    end
    return nil
end

---@param player LuaPlayer
---@param info Info
---@return boolean
local function check_field_values(player, info)
    if info.radius < 30 or info.radius > 1000 then
        player.print("radius must  between 30 and 1000")
        return false
    end
    return true
end

---@param player LuaPlayer
---@param info Info
update_gui = function(player, info)
    if not info then return end
    local frame = player.gui.left[pfx .. "_frame"]
    if not frame then return end

    local started = is_squad_started(info)

    local fields = {
        pfx .. "_radius", pfx .. "_attack_distance", pfx .. "_min_health",
        pfx .. "_min_ammo", pfx .. "_retreat_if_no_ammo", pfx .. "_collect_loot"
    }
    local start_button = get_field(pfx .. "_start", frame)
    if started then
        start_button.caption = { "button.stop" }
    else
        start_button.caption = { "button.start" }
    end

    for _, n in ipairs(fields) do get_field(n, frame).enabled = not started end
    get_field(pfx .. "_retreat", frame).enabled = started
    if started then display_radius_circle(info, player) end
end

---@param e EventData.on_gui_click
local function on_gui_click(e)
    local player = game.players[e.player_index]
    if e.element.name == pfx .. "_start" then
        local spider = get_vars(player).selected
        if not spider or not spider.valid then return end

        local info = get_info_spider(spider)
        local stopped = not is_squad_started(info)

        if stopped then
            if not check_field_values(player, info) then return end
            start(info)
        else
            apply_squad(info, function(info2)
                info2.state = state_stopped
            end)

            if info.squad then
                local vehicle = player.vehicle
                if vehicle and spiders[vehicle.unit_number] and
                    spiders[vehicle.unit_number].squad == info.squad then
                    make_follow(info.squad, vehicle.unit_number)
                end
            end
        end
        update_gui(player, info)
    elseif e.element.name == pfx .. "_close_button" then
        remove_radius_circle(player)
        close_player_gui(player)
    elseif e.element.name == pfx .. "_retreat" then
        local spider = get_vars(player).selected
        if not spider or not spider.valid then return end
        local info = get_info_spider(spider)

        if not info.squad then
            info.state = state_retreat
        else
            apply_squad(info, function(info2)
                if info2.state ~= state_stopped then
                    info2.state = state_retreat
                end
            end)
        end
    elseif e.element.name == pfx .. "_onoff" then
        local vars = get_vars(player)
        vars.no_interface = not vars.no_interface
        if vars.no_interface then
            remove_radius_circle(player)
            close_player_gui(player)
        else
            if vars.selected then
                on_gui_opened {
                    player_index = e.player_index,
                    entity = vars.selected
                }
            end
        end
    end
end

---@param e EventData.on_gui_text_changed
local function on_gui_text_changed(e)
    local player = game.players[e.player_index]

    local selected = get_vars(player).selected
    if not selected or not selected.valid then return end
    local element_name = e.element.name
    for _, field_name in ipairs({
        "radius", "attack_distance", "min_health", "min_ammo"
    }) do
        if element_name == pfx .. "_" .. field_name then
            local info = get_info_spider(selected)
            local value = tonumber(e.text)
            if value then info[field_name] = value end

            if element_name == pfx .. "_radius" then
                remove_radius_circle(player)
                if info.radius >= 10 then
                    display_radius_circle(info, player)
                end
            end
            return
        end
    end
end

---@param e EventData.on_gui_checked_state_changed
local function on_gui_checked_state_changed(e)
    local player = game.players[e.player_index]

    local selected = get_vars(player).selected
    if not selected or not selected.valid then return end
    if e.element.name == pfx .. "_retreat_if_no_ammo" then
        local info = get_info_spider(selected)

        info.retreat_if_no_ammo = e.element.state
    elseif e.element.name == pfx .. "_collect_loot" then
        local info = get_info_spider(selected)

        info.collect_loot = e.element.state
    end
end

---@param data NthTickEventData 
local function on_nth_tick(data)
    if spiders then
        for _, info in pairs(spiders) do process_spider(info) end

        for player_index, vars in pairs(global.players) do
            if vars.tags and vars.tags.info and vars.tags.info.state ==
                state_stopped and vars.tags.position and
                vect_distance(vars.tags.position, vars.tags.info.entity.position) >
                2 then
                display_radius_circle(vars.tags.info, game.players[player_index])
            end
        end
    end

    if duplicators then
        local tick = game.tick - 600
        for _, duplicator in pairs(duplicators) do
            if duplicator.tick <= tick then
                process_duplicator(duplicator)
                duplicator.tick = game.tick
            end
        end
    end
end

local function create_player_buttons()
    for _, player in pairs(game.players) do
        local button_flow = mod_gui.get_button_flow(player)
        local button_name = pfx .. "_onoff"
        if button_flow[button_name] then
            button_flow[button_name].destroy()
        end
        if not button_flow[button_name] then
            local button = button_flow.add {
                type = "sprite-button",
                name = button_name,
                sprite = "on_off",
                tooltip = { "tooltip.on_off" }
            }
            button.style.width = 40
            button.style.height = 40
        end

        if player.force.technologies["logistics"].researched then
            player.force.recipes["spidersentinel_duplicator"].enabled = true
        end
    end
end

------------------------------------------------------
script.on_nth_tick(ntick_delay, on_nth_tick)

script.on_event(defines.events.on_gui_opened, on_gui_opened)
-- script.on_event(defines.events.on_gui_closed, on_gui_closed)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)
script.on_event(defines.events.on_gui_checked_state_changed,
    on_gui_checked_state_changed)

local entity_filter1 = { { filter = "type", type = "spider-vehicle" } }
local entity_filter2 = {
    { filter = "type", type = "spider-vehicle" },
    { filter = "name", name = pfx .. "_duplicator" }
}

script.on_event(defines.events.on_built_entity, on_built_entity, entity_filter2)
script.on_event(defines.events.on_robot_built_entity, on_built_entity, entity_filter2)

script.on_event(defines.events.on_pre_player_mined_item, on_pre_player_mined_item, entity_filter1)
script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity, entity_filter2)
script.on_event(defines.events.on_robot_mined_entity, on_remove_entity, entity_filter2)
script.on_event(defines.events.on_entity_died, on_remove_entity, entity_filter2)

script.on_event(defines.events.on_script_path_request_finished, on_script_path_request_finished)

------------------------------------------------------
-- Init

local function on_init()
    global.spiders = {}
    global.players = {}
    create_player_buttons()
end

script.on_init(on_init)

local function on_load()
    spiders = global.spiders
    duplicators = global.duplicators
end

script.on_load(on_load)

local function on_configuration_changed(data) create_player_buttons() end

script.on_configuration_changed(on_configuration_changed)

script.on_event(defines.events.on_player_selected_area, on_selected_area)
script.on_event(defines.events.on_player_alt_selected_area, on_player_alt_selected_area)

------------------------------------------------------

local function on_player_driving_changed_state(e)
    local player = game.players[e.player_index]

    local vehicle = player.vehicle
    if not spiders then return end
    if vehicle and spiders[vehicle.unit_number] and
        spiders[vehicle.unit_number].squad then
        make_follow(spiders[vehicle.unit_number].squad, vehicle.unit_number)
    end
end

script.on_event(defines.events.on_player_driving_changed_state,
    on_player_driving_changed_state)

------------------------------------------------------

local function get_spider_in_squad(id)
    if not spiders then return nil end

    local spider = spiders[id]
    if not spider then return nil end

    local squad = spider.squad
    if not squad then return nil end

    local result = {}
    for _, spider in pairs(spiders) do
        if spider.squad == squad then table.insert(result, spider.entity) end
    end
    return result
end

local function follow(id)
    if not spiders then return end

    local spider = spiders[id]
    if not spider then return end

    local squad = spider.squad
    if not squad then return end

    make_follow(squad, id)
end

remote.add_interface("spidersentinel", {
    get_spider_in_squad = get_spider_in_squad,
    follow = follow
})

------------------------------------------------------

local function on_player_configured_spider_remote(e)
    local vehicle = e.vehicle

    follow(vehicle.unit_number)
end

script.on_event(defines.events.on_player_configured_spider_remote,
    on_player_configured_spider_remote)
