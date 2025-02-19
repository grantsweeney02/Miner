pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
cam_y = 0
SURFACE_HEIGHT = 32 -- row=4 => y=32 is grass
GRID_SIZE = 8
MAP_WIDTH = 16
MAP_HEIGHT = 32
BEDROCK_LEVEL = MAP_HEIGHT - 2

local surface_row = flr(SURFACE_HEIGHT / GRID_SIZE) -- =4

--------------------------------------------------------------------------------
-- TILE & SPRITE DEFINITIONS
--------------------------------------------------------------------------------
TILE_GRASS   = 0  
TILE_EMPTY   = 1
TILE_DIRT    = 2
TILE_STONE   = 3
TILE_GOLD    = 4
TILE_DIAMOND = 5
TILE_BEDROCK = 6
TILE_GAS_PUMP= 7
TILE_TRADER  = 8
TILE_UPGRADE_HUT = 9

SPR_MINER_RIGHT = 33
SPR_MINER_LEFT  = 34
SPR_MINER_UP    = 49
SPR_MINER_DOWN  = 50
SPR_GAS_PUMP    = 35
SPR_TRADER      = 51
SPR_GRASS_FULL  = 36
SPR_GRASS_BROKEN= 37
SPR_DIRT        = {38,39}
SPR_STONE       = {52,53,54}
SPR_GOLD        = {55,56,57}
SPR_DIAMOND     = {40,41,42,43}
SPR_BEDROCK     = 58
SPR_UPGRADE_HUT = 59

game_over = false

--------------------------------------------------------------------------------
-- ORE INFO
--------------------------------------------------------------------------------
ore_info = {
  [TILE_DIRT] = {
      sprites = SPR_DIRT,
      durability = 2
  },
  [TILE_STONE] = {
      sprites = SPR_STONE,
      durability = 3
  },
  [TILE_GOLD] = {
      sprites = SPR_GOLD,
      durability = 3
  },
  [TILE_DIAMOND] = {
      sprites = SPR_DIAMOND,
      durability = 4
  },
  [TILE_GRASS] = {
      sprites = {SPR_GRASS_FULL, SPR_GRASS_BROKEN},
      durability = 2
  }
}

--------------------------------------------------------------------------------
-- ORE VALUES
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
-- CHANGED: Start with 50 fuel and 100 minerBucks for testing
miner = {
    x = 6 * GRID_SIZE,
    y = (surface_row - 1) * GRID_SIZE,  -- row=3 => y=24
    speed = GRID_SIZE,

    sprite_right = SPR_MINER_RIGHT,
    sprite_left  = SPR_MINER_LEFT,
    sprite_up    = SPR_MINER_UP,
    sprite_down  = SPR_MINER_DOWN,
    current_sprite = SPR_MINER_LEFT,
    move_delay = 10,
    move_timer = 0,
    was_moving_up = false,

    inventory = {
        [TILE_DIRT]    = 0, 
        [TILE_STONE]   = 0,
        [TILE_GOLD]    = 0,
        [TILE_DIAMOND] = 0
    },

    minerBucks = 100,  -- CHANGED
    fuel = 50,         -- CHANGED
    max_fuel = 100
}

--------------------------------------------------------------------------------
-- MAP GENERATION
--------------------------------------------------------------------------------
map = {}
for y = 0, MAP_HEIGHT - 1 do
    map[y] = {}
    for x = 0, MAP_WIDTH - 1 do
        if y < surface_row then
            map[y][x] = TILE_EMPTY
        elseif y == surface_row then
            map[y][x] = {
                t = TILE_GRASS,
                d = ore_info[TILE_GRASS].durability,
                sprite = ore_info[TILE_GRASS].sprites[1]
            }
        elseif y >= BEDROCK_LEVEL then
            map[y][x] = TILE_BEDROCK
        else
            local r = rnd()
            if y > 16 and r < 0.03 then
                map[y][x] = { t = TILE_DIAMOND, d = ore_info[TILE_DIAMOND].durability, sprite = ore_info[TILE_DIAMOND].sprites[1] }
            elseif y > 12 and r < 0.15 then
                map[y][x] = { t = TILE_GOLD, d = ore_info[TILE_GOLD].durability, sprite = ore_info[TILE_GOLD].sprites[1] }
            elseif y > 7 and r < 0.35 then
                map[y][x] = { t = TILE_STONE, d = ore_info[TILE_STONE].durability, sprite = ore_info[TILE_STONE].sprites[1] }
            else
                map[y][x] = { t = TILE_DIRT, d = ore_info[TILE_DIRT].durability, sprite = ore_info[TILE_DIRT].sprites[1] }
            end
        end
    end
end

local building_row = surface_row - 1
map[building_row][1] = TILE_GAS_PUMP
map[building_row][MAP_WIDTH - 2] = TILE_UPGRADE_HUT
map[building_row][flr(MAP_WIDTH * 3/4)] = TILE_TRADER

--------------------------------------------------------------------------------
-- CAN_MOVE + COLLISION
--------------------------------------------------------------------------------
function can_move(new_x, new_y)
    local grid_x = new_x / GRID_SIZE
    local grid_y = new_y / GRID_SIZE

    if grid_x < 0 or grid_x >= MAP_WIDTH or grid_y < 0 or grid_y >= MAP_HEIGHT then
        return false
    end

    local cell = map[grid_y][grid_x]
    if type(cell) == "table" then
        local info = ore_info[cell.t]
        cell.d -= 1
        if cell.d > 0 then
            local stage = (info.durability - cell.d) + 1
            cell.sprite = info.sprites[stage]
            return false
        else
            if cell.t == TILE_GRASS then
                miner.inventory[TILE_DIRT] += 1
            else
                miner.inventory[cell.t] += 1
            end
            map[grid_y][grid_x] = TILE_EMPTY
            sfx(0) -- optional
            return true
        end
    elseif cell == TILE_BEDROCK then
        return false
    else
        return true
    end
end

--------------------------------------------------------------------------------
-- AUTO-CONVERT (Deposit ores at/above grass => row=4 => y=32)
--------------------------------------------------------------------------------
function auto_convert()
    if miner.y <= (surface_row * GRID_SIZE) then
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
    if game_over then return end

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
        local surface_px   = surface_row * GRID_SIZE

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
            -- only move up if miner is below surface row
            if miner.y > surface_px - GRID_SIZE then
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

    -- clamp if you just came up to surface
    local surface_px = surface_row * GRID_SIZE
    if miner.y <= surface_px - GRID_SIZE and miner.was_moving_up then
        miner.y = surface_px - GRID_SIZE
        miner.current_sprite = miner.sprite_right
        miner.was_moving_up = false
    end

    -- sell ore if at/above surface
    auto_convert()

    -- fueling at gas pump
    local pump_x = 1 * GRID_SIZE
    local pump_y = (surface_row - 1) * GRID_SIZE
    if miner.x == pump_x and miner.y == pump_y then
        if btnp(5) then  -- Press (X) to refuel
            
            local missing_fuel = miner.max_fuel - miner.fuel
            if missing_fuel > 0 then
                
                local cost = ceil(missing_fuel / 10)  -- 1 MB per 10 fuel (rounded up)

                if miner.minerBucks >= cost then
                    -- Enough money → Full refill
                    miner.minerBucks -= cost
                    miner.fuel = miner.max_fuel
                    print("Refueled for " .. cost .. " MB!", 1, 120, 11)
                elseif miner.minerBucks > 0 then
                    -- Partial refill if short on money
                    local affordable_fuel = miner.minerBucks * 10
                    miner.fuel += affordable_fuel
                    miner.minerBucks = 0
                    print("Partial refuel: +" .. affordable_fuel .. " fuel", 1, 120, 10)
                else
                    print("Not enough MB to refuel!", 1, 120, 8)
                end
            end
        end
    end

    local max_cam = MAP_HEIGHT * GRID_SIZE - 128
    cam_y = mid(0, miner.y - 32, max_cam)
end

--------------------------------------------------------------------------------
-- DRAW
--------------------------------------------------------------------------------
function _draw()
    cls(12)

    camera(0, cam_y)

    local surface_px = surface_row * GRID_SIZE
    local bedrock_px = BEDROCK_LEVEL * GRID_SIZE

    rectfill(0, 0, 127, surface_px - 1, 12)       -- sky
    rectfill(0, surface_px, 127, bedrock_px - 1, 4) -- dirt
    rectfill(0, bedrock_px, 127, (MAP_HEIGHT*GRID_SIZE) - 1, 0) -- bedrock

    -- draw map
    for y = 0, MAP_HEIGHT - 1 do
        for x = 0, MAP_WIDTH - 1 do
            local cell = map[y][x]
            local draw_x = x * GRID_SIZE
            local draw_y = y * GRID_SIZE
            if type(cell) == "table" then
                spr(cell.sprite, draw_x, draw_y)
            elseif cell == TILE_BEDROCK then
                spr(SPR_BEDROCK, draw_x, draw_y)
            elseif cell == TILE_GAS_PUMP then
                spr(SPR_GAS_PUMP, draw_x, draw_y)
            elseif cell == TILE_TRADER then
                spr(SPR_TRADER, draw_x, draw_y)
            elseif cell == TILE_UPGRADE_HUT then
                spr(SPR_UPGRADE_HUT, draw_x, draw_y)
            end
        end
    end

    -- draw miner
    palt()
    palt(13, true)  -- invisible color
    palt(0, false)
    spr(miner.current_sprite, miner.x, miner.y)

    camera()

    -- UI: minerbucks
    print("minerbucks: "..miner.minerBucks, 1, 1, 7)

    -- UI: fuel bar
    local bar_x = 70
    local bar_y = 1
    local bar_width = 50
    local bar_height = 6
    local fuel_ratio = miner.fuel / miner.max_fuel
    local fill_width = flr(bar_width * fuel_ratio)
    local bar_color = 11 -- green

    if fuel_ratio <= 0.3 then
        bar_color = 8  -- red
    elseif fuel_ratio < 0.7 then
        bar_color = 10 -- yellow
    end

    rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 5)
    rectfill(bar_x, bar_y, bar_x + fill_width, bar_y + bar_height, bar_color)
    rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 7)
    print("fuel", bar_x, bar_y + bar_height + 1, 7)

    -- refuel prompt
    local pump_x = 1 * GRID_SIZE
    local pump_y = (surface_row - 1) * GRID_SIZE
        -- Refuel Prompt with Dynamic Cost
    if miner.x == pump_x and miner.y == pump_y then
        local missing_fuel = miner.max_fuel - miner.fuel
        if missing_fuel > 0 then
            local cost = ceil(missing_fuel / 10)  -- Dynamic cost calculation
            print("Hold X to refuel (" .. cost .. " MB)", 1, 14, 10)
        else
            print("Fuel tank full!", 1, 14, 11)
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
00000000ddddddddddddddddd888888d33333333343343434443444f4443444fc55cc55cc55cc55cc55cc55cc55cc55c00000000000000000000000000000000
00000000dddddddddddddddd0886668d33333333333343344f443444444444445c5c55c55c5c55c55c5555c5555555c500000000000000000000000000000000
00000000dddddddddddddddd0886068d3333333334343343444f444f43444444c555cc55c555cc55c5555c555555555500000000000000000000000000000000
00000000111155dddd5511110886608d3333333343443f334f344f3444444f3455cc555c555c555c555c555c555c555500000000000000000000000000000000
000000001111556dd655111108c6668d34434434444444444444444444444444c5c5c5ccc5c5c5c5c5c5c555c555c55500000000000000000000000000000000
00000000111111666611111108c8888d4f344344444444444f44434444f444445c55555c5c55555c5c55555c5c55555c00000000000000000000000000000000
000000000010016dd61001000008888d4444f34f444444444444f34f44444444555c5cc5555c5c55555c5c555555555500000000000000000000000000000000
0000000000d00dddddd00d00d888888d343444443444f4443434444434444344cc55c555cc5555555c5555555c555c5500000000000000000000000000000000
00000000dddd6dddd01110ddd77777dd655665566556555665555555a55aa55aa555a55aa555555a05050020ddd82ddd00000000000000000000000000000000
00000000ddd666ddd01110dd7777777d5655556555555565555555655a5a55a5555a5555555a555502005000dd8882dd00000000000000000000000000000000
00000000dd15551ddd111ddddf0f0fdd555565555555655555555555a555aa5555555a5555555a5550020050d888882d00000000000000000000000000000000
00000000dd05550dd01110dddfffffdd65655555655555556555555555aa555a55a5555a55a55555200000208888888200000000000000000000000000000000
00000000dd01110dd05550ddd6a6a6dd555565555555655555555565a5a5a5aaa55555a555555555000200009999999400000000000000000000000000000000
00000000ddd111ddd15551dddfa6afdd5655555656555556565555555a55555a5a55555a5a55555a020005009449c19400000000000000000000000000000000
00000000dd01110ddd666ddddfa6afdd655656555556565555555555555a5aa5555a5a55555a5a550050000294a91c9400000000000000000000000000000000
00000000dd01110dddd6dddddd000ddd565555655555555555555555aa55a5555a55555555555555250020509449999400000000000000000000000000000000
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
0005000021050000002a0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 01424344

