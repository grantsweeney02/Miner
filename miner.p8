pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
cam_y = 0
SURFACE_HEIGHT = 32
GRID_SIZE = 16
MAP_WIDTH = 8
MAP_HEIGHT = 32
BEDROCK_LEVEL = MAP_HEIGHT - 2
local surface_row = flr(SURFACE_HEIGHT / GRID_SIZE) -- usually 2, given 32/16=2

-- tile IDs
TILE_GRASS   = 0  
TILE_EMPTY   = 1
TILE_DIRT    = 2
TILE_STONE   = 3
TILE_GOLD    = 4
TILE_DIAMOND = 5
TILE_BEDROCK = 6
TILE_GAS_PUMP= 7

SPRITE_BEDROCK = 110
SPRITE_GAS_PUMP = 9

game_over = false

--------------------------------------------------------------------------------
-- ORE INFO
--------------------------------------------------------------------------------
ore_info = {
    [TILE_DIRT] = {
        sprites = { 64, 66 },
        durability = 2
    },
    [TILE_STONE] = {
        sprites = { 68, 70, 72 },
        durability = 3
    },
    [TILE_GOLD] = {
        sprites = { 96, 98, 100 },
        durability = 3
    },
    [TILE_DIAMOND] = {
        sprites = { 102, 104, 106, 108 },
        durability = 4
    },
    [TILE_GRASS] = {
        -- behaves like dirt, but different sprites
        sprites = { 74, 76 },
        durability = 2
    }
}

--------------------------------------------------------------------------------
-- ORE VALUES: Grass merges with dirt in inventory, so no separate grass entry
--------------------------------------------------------------------------------
ore_values = {
    [TILE_DIRT]    = 1,
    [TILE_STONE]   = 2,
    [TILE_GOLD]    = 5,
    [TILE_DIAMOND] = 10
}

--------------------------------------------------------------------------------
-- MINER
--------------------------------------------------------------------------------
miner = {
    x = 48,
    y = SURFACE_HEIGHT - GRID_SIZE,
    speed = GRID_SIZE,

    sprite_right = 1,
    sprite_left  = 3,
    sprite_up    = 5,
    sprite_down  = 7,
    current_sprite = 3,
    move_delay = 10,
    move_timer = 0,
    was_moving_up = false,

    inventory = {
        [TILE_DIRT]    = 0, -- used for both dirt and grass
        [TILE_STONE]   = 0,
        [TILE_GOLD]    = 0,
        [TILE_DIAMOND] = 0
    },

    minerBucks = 0,
    fuel = 40,
    max_fuel = 100
}

--------------------------------------------------------------------------------
-- MAP GENERATION
--------------------------------------------------------------------------------
map = {}
for y = 0, MAP_HEIGHT - 1 do
    map[y] = {}
    for x = 0, MAP_WIDTH - 1 do

        -- SKY
        if y < surface_row then
            map[y][x] = TILE_EMPTY

        -- SURFACE ROW (y == surface_row)
        elseif y == surface_row then
            map[y][x] = {
                t = TILE_GRASS,
                d = ore_info[TILE_GRASS].durability,
                sprite = ore_info[TILE_GRASS].sprites[1]
            }

        -- BEDROCK
        elseif y >= BEDROCK_LEVEL then
            map[y][x] = TILE_BEDROCK

        -- UNDERGROUND (random dirt / stone / gold / diamond)
        else
            local r = rnd()
            if y > 10 and r < 0.05 then
                map[y][x] = {
                    t = TILE_DIAMOND,
                    d = ore_info[TILE_DIAMOND].durability,
                    sprite = ore_info[TILE_DIAMOND].sprites[1]
                }
            elseif y > 6 and r < 0.20 then
                map[y][x] = {
                    t = TILE_GOLD,
                    d = ore_info[TILE_GOLD].durability,
                    sprite = ore_info[TILE_GOLD].sprites[1]
                }
            elseif y > 4 and r < 0.40 then
                map[y][x] = {
                    t = TILE_STONE,
                    d = ore_info[TILE_STONE].durability,
                    sprite = ore_info[TILE_STONE].sprites[1]
                }
            else
                map[y][x] = {
                    t = TILE_DIRT,
                    d = ore_info[TILE_DIRT].durability,
                    sprite = ore_info[TILE_DIRT].sprites[1]
                }
            end
        end
    end
end

-- place gas pump near the top
map[1][MAP_WIDTH - 2] = TILE_GAS_PUMP

--------------------------------------------------------------------------------
-- CAN_MOVE + COLLISION
--------------------------------------------------------------------------------
function can_move(new_x, new_y)
    local grid_x = new_x / GRID_SIZE
    local grid_y = new_y / GRID_SIZE
    local cell = map[grid_y][grid_x]

    if type(cell) == "table" then
        -- it's some ore or grass
        local info = ore_info[cell.t]
        cell.d -= 1
        if cell.d > 0 then
            local stage = (info.durability - cell.d) + 1
            cell.sprite = info.sprites[stage]
            return false
        else
            -- fully mined
            if cell.t == TILE_GRASS then
                -- store as dirt in inventory
                miner.inventory[TILE_DIRT] += 1
            else
                miner.inventory[cell.t] += 1
            end
            map[grid_y][grid_x] = TILE_EMPTY
            sfx(0)
            return true
        end

    elseif cell == TILE_BEDROCK then
        return false

    else
        -- empty or gas pump
        return true
    end
end

--------------------------------------------------------------------------------
-- AUTO-CONVERT (surface => deposit ores => get minerbucks)
--------------------------------------------------------------------------------
function auto_convert()
    if miner.y <= SURFACE_HEIGHT - GRID_SIZE then
        for tile_id, tile_value in pairs(ore_values) do
            local count = miner.inventory[tile_id]
            if count and count > 0 then
                miner.minerBucks += count * tile_value
                miner.inventory[tile_id] = 0
            end
        end
    end
end

--------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------
function _update()
    if game_over then
        return
    end

    if miner.fuel <= 0 then
        game_over = true
        return
    end

    if miner.move_timer > 0 then
        miner.move_timer -= 1
        return
    end

    if miner.x % GRID_SIZE == 0 and miner.y % GRID_SIZE == 0 then
        local old_x, old_y = miner.x, miner.y
        local new_x, new_y = old_x, old_y

        -- left
        if btn(0) and miner.x > 0 then
            new_x -= miner.speed
            miner.current_sprite = miner.sprite_left
            miner.was_moving_up = false
        end
        -- right
        if btn(1) and miner.x < (MAP_WIDTH - 1) * GRID_SIZE then
            new_x += miner.speed
            miner.current_sprite = miner.sprite_right
            miner.was_moving_up = false
        end
        -- up
        if btn(2) then
            -- only move up if miner is below the surface
            if miner.y > SURFACE_HEIGHT - GRID_SIZE then
                new_y -= miner.speed
                miner.current_sprite = miner.sprite_up
                miner.was_moving_up = true
            else
                miner.was_moving_up = false
                miner.current_sprite = miner.sprite_right
            end
        end
        -- down
        if btn(3) and miner.y < (BEDROCK_LEVEL - 1) * GRID_SIZE then
            new_y += miner.speed
            miner.current_sprite = miner.sprite_down
            miner.was_moving_up = false
        end

        if can_move(new_x, new_y) then
            if (new_x ~= old_x or new_y ~= old_y) then
                miner.x = new_x
                miner.y = new_y
                miner.fuel = max(0, miner.fuel - 1)
            end
        end

        miner.move_timer = miner.move_delay
    end

    -- if the miner reached the surface from below, clamp them there
    if miner.y <= SURFACE_HEIGHT - GRID_SIZE and miner.was_moving_up then
        miner.y = SURFACE_HEIGHT - GRID_SIZE
        miner.current_sprite = miner.sprite_right
        miner.was_moving_up = false
    end

    -- auto-convert ore -> minerbucks at surface
    auto_convert()

    -- handle fueling at gas pump
    local pump_x = (MAP_WIDTH - 2) * GRID_SIZE
    local pump_y = 1 * GRID_SIZE
    if miner.x == pump_x and miner.y == pump_y then
        if btnp(5) and miner.minerBucks >= 10 then
            miner.minerBucks -= 10
            miner.fuel = miner.max_fuel
        end
    end

    -- camera clamp
    local max_cam = MAP_HEIGHT * GRID_SIZE - 128
    cam_y = mid(0, miner.y - 32, max_cam)
end

--------------------------------------------------------------------------------
-- DRAW
--------------------------------------------------------------------------------
function _draw()
    cls(12)
    camera(0, cam_y)

    -- background sections
    rectfill(0, 0, 127, MAP_HEIGHT * GRID_SIZE, 12)  -- sky
    rectfill(0, SURFACE_HEIGHT, 127, BEDROCK_LEVEL * GRID_SIZE, 4)  -- main dirt region
    rectfill(0, BEDROCK_LEVEL * GRID_SIZE, 127, MAP_HEIGHT * GRID_SIZE, 0)  -- bedrock region

    -- draw map
    for y = 0, MAP_HEIGHT - 1 do
        for x = 0, MAP_WIDTH - 1 do
            local cell = map[y][x]
            if type(cell) == "table" then
                spr(cell.sprite, x * GRID_SIZE, y * GRID_SIZE, 2, 2)
            elseif cell == TILE_BEDROCK then
                spr(SPRITE_BEDROCK, x * GRID_SIZE, y * GRID_SIZE, 2, 2)
            elseif cell == TILE_GAS_PUMP then
                spr(SPRITE_GAS_PUMP, x * GRID_SIZE, y * GRID_SIZE, 2, 2)
            end
        end
    end

    -- draw miner
    palt()
    palt(15, true)
    palt(0, false)
    spr(miner.current_sprite, miner.x, miner.y, 2, 2)

    camera()

    -- UI: MinerBucks
    print("minerbucks: " .. miner.minerBucks, 1, 1, 7)

    -- UI: fuel bar
    local bar_x = 70
    local bar_y = 1
    local bar_width = 50
    local bar_height = 6
    local fuel_ratio = miner.fuel / miner.max_fuel
    local percentage = fuel_ratio * 100
    local fill_width = flr(bar_width * fuel_ratio)
    local bar_color
    if percentage <= 30 then
        bar_color = 8  -- red
    elseif percentage < 70 then
        bar_color = 10 -- yellow
    else
        bar_color = 11 -- green
    end

    rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 5)
    rectfill(bar_x, bar_y, bar_x + fill_width, bar_y + bar_height, bar_color)
    rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 7)
    print("fuel", bar_x, bar_y + bar_height + 1, 7)

    -- UI: refuel prompt
    local pump_x = (MAP_WIDTH - 2) * GRID_SIZE
    local pump_y = 1 * GRID_SIZE
    if miner.x == pump_x and miner.y == pump_y then
        if miner.minerBucks >= 10 then
            print("hold x to refuel (10 MB)", 1, 12, 10)
        else
            print("need 10 mb to refuel", 1, 12, 8)
        end
    end

    -- game over message
    if game_over then
        local msg = "game over"
        local msg_width = #msg * 4
        local msg_x = (128 - msg_width) / 2
        local msg_y = 64
        rectfill(0, msg_y - 4, 128, msg_y + 8, 0)
        print(msg, msg_x, msg_y, 8)
    end
end


__gfx__
00000000fffffffffffffffffffffffffffffffffffffff6ffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000
00000000ffffffffffffffffffffffffffffffffffffff666fffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000
00700700fffffffffffffffffffffffffffffffffffff66666ffffffffffffffffffffffffff88888888ffff0000000000000000000000000000000000000000
00077000fffffffffffffffffffffffffffffffffffff11111fffffffffff11111ffffffffff88888888ffff0000000000000000000000000000000000000000
00077000ffffffffffffffffffffffffffffffffffff0100010fffffffff0111110ffffffff088666688ffff0000000000000000000000000000000000000000
00700700ffffffffffffffffffffffffffffffffffff0100010fffffffff0111110ffffffff088606688ffff0000000000000000000000000000000000000000
00000000ffffffffffffffffffffffffffffffffffff0111110fffffffff0111110ffffffff088660688ffff0000000000000000000000000000000000000000
00000000fffffffffffffffffffffffffffffffffffff11111fffffffffff11111fffffffff088666688ffff0000000000000000000000000000000000000000
00000000fffffffffffffffffffffffffffffffffffff11111fffffffffff11111fffffffff088666688ffff0000000000000000000000000000000000000000
00000000ffffffffffffffffffffffffffffffffffff0111110fffffffff0111110ffffffff08c888888ffff0000000000000000000000000000000000000000
00000000ffff11111100f6ffff6f00111111ffffffff0111110fffffffff0100010ffffffff08c885588ffff0000000000000000000000000000000000000000
00000000ffff11111100166ff66100111111ffffffff0111110fffffffff0100010ffffffff080885588ffff0000000000000000000000000000000000000000
00000000fff11111111116666661111111111ffffffff11111fffffffffff11111fffffffff000888888ffff0000000000000000000000000000000000000000
00000000fff100011000166ff661000110001ffffffffffffffffffffffff66666ffffffffff88888888ffff0000000000000000000000000000000000000000
00000000fff10501105016ffff61050110501fffffffffffffffffffffffff666fffffffffff88888888ffff0000000000000000000000000000000000000000
00000000ffff000ff000ffffffff000ff000fffffffffffffffffffffffffff6ffffffffff555555555555ff0000000000000000000000000000000000000000
00000000fffffffffffffffff888888f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ffffffffffffffff0886668f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ffffffffffffffff0886068f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111155ffff55111108c6608f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000001111556ff65511110806668f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000011111166661111110008888f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000010016ff6100100f888888f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000f00ffffff00f0055555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000fff6ffffff01110f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff666fffff01110f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000f15551fffff111ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000f05550ffff01110f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000f01110ffff05550f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff111fffff15551f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000f01110fffff666ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000f01110ffffff6fff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4443444f4443444f4443444f44434444655665566556655665565556655665566555555565555556333333333333333334334343334334330000000000000000
4f4434444f4434444444444444444444565555655655556555555565565555655555556556555565333333333333333333334334343333330000000000000000
444f444f444f444f4444444444444444555565555555655555556555555555555555555555555555333333333333333334343343433444340000000000000000
4f344f344f344f3444444f344f444f44656555556565555565555555655555556555555555555555333333333333333343443f334f4343430000000000000000
44444444444444444444444444444444555565555555655555556555555555555555556555556555344344343443344344444444444444440000000000000000
4f4443444f44434444444444444443445655555656555556565555565655555656555555555555554f3443444f44434444444444444443440000000000000000
4444f34f4444f34f444444444444444f6556565565565655555656555555555555555555555556554444f34f4444f34f444444444444444f0000000000000000
3434444434344444344444444444444456555565565555655555555555555565555555555555555534344444343444443444f444444444440000000000000000
4443444f4443444f44444444444444446556655665566556655655556556555665565555655555554443444f4443444f44444444444444440000000000000000
4f4434444f4434444f4444444f4444445655556556555565565555655655556555555555555555554f4434444f443444444444444f4444440000000000000000
444f444f444f444f4444444f44444444555565555555655555555555555565555555555555555555444f444f444f444f4444444f444444440000000000000000
4f344f344f344f3444444444444444446565555565655555656555556565555565555555655555554f344f344f344f3444444444444444440000000000000000
44444444444444444444444444444444555565555555655555556555555555555555655555555555444444444444444444444444444444440000000000000000
4f4443444f4443444f444344444443445655555656555556555555555655555655555555555555554f4443444f4443444f444344444443440000000000000000
4444f34f4444f34f4444444f4444f4446556565565565655655656555556565555555655555655554444f34f4444f34f4444444f4444f4440000000000000000
34344444343444444444444434444444565555655655556556555565565555655655555556555565343444443434444444444444344444440000000000000000
a55aa55aa55aa55aa555a55a55a5555aa555555a5555555ac55cc55cc55cc55cc55cc55cc555c55cc55cc55cc555c55cc55cc55cc555c55c0505002005050020
5a5a55a55a5a55a5555a5555555a5555555a5555555a55555c5c55c55c5c55c55c5c55c55c5c55c55c5555c55c5c55c5555555c55c5c55c50200500002005000
a555aa55a555aa5555555a55a5555a5555555a55a5555a55c555cc55c555cc55c555cc55c555cc55c5555c55c5555c555555555555555c555002005050020050
55aa555a55aa555a55a5555a555a555a55a55555555a555a55cc555c55cc555c55cc555c55cc555c555c555c555c555c555c5555555555552000002020000020
a5a5a5aaa5a5a5aaa55555a5a5a5a5a55555555555555555c5c5c5ccc5c5c5ccc5c5c5c5c5c5c5ccc5c5c555c5c5c5c5c555c5555555c5c50002000000020000
5a55555a5a55555a5a55555a5a55555a5a55555a5a5555a55c55555c5c55555c5c55555c5c55555c5c55555c5c55555c5c55555c5c5555550200050002000500
555a5aa5555a5aa5555a5a5555555a55555a5a5555555555555c5cc5555c5cc5555c5c55555c55c5555c5c55555c55c555555555555555c50050000200500002
aa55a555aa55a5555a5555555a55a555555555555a55a555cc55c555cc55c555cc555555cc55c5555c555555c555c5555c555555c55555552500205025002050
a55aa55aa55aa55aa555a55a5555555aa555a55a55555555c55cc55cc55cc55cc55c5555555c555c555c5555555c555c555c5555555c555c0505002005050020
5a5a55a55a5a55a55a5a55a55a5a55a5555555a55a5555a55c5c55c55c5c55c55c5c55c55c5c55c55c5555c55c5555c55c5555c55c5555550200500002005000
a555aa55a555aa55a555a555a555a5555a5a55555555a555c555cc55c555cc55c5555c55c555cc55c5555c55c555cc55c5555555555555555002005050020050
55aa555a55aa555a555a555a555a555a555555555a55555a55cc555c55cc555c55cc555c55cc555c555c555c555c555c555c555c555555552000002020000020
a5a5a5aaa5a5a5aaa5a5a5a55555a5a55555a5a555555555c5c5c5ccc5c5c5ccc5c5c5ccc5c5c5ccc5c5c55555c5c5c5c55555555555c5550002000000020000
5a55555a5a55555a5a55555a5a55555a5a5555555a55555a5c55555c5c55555c5c55555c5c55555c5c55555c5c55555c5c55555c5c55555c0200050002000500
555a5aa5555a5aa5555a5a55555a5aa5555a5a55555a5a55555c5cc5555c5cc5555c5cc5555c5cc5555c5c55555c5cc555555555555c55c50050000200500002
aa55a555aa55a555a555a555aa55a555a5555555aa555555cc55c555cc55c555cc55c555cc55c555cc55c555cc55c555cc55c555cc55c5552500205025002050
__sfx__
0005000000000090500b0500f0501705020050270502d050320503f05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 01424344

