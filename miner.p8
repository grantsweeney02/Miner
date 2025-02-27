pico-8 cartridge // http://www.pico-8.com
version 42
__lua__


SURFACE_HEIGHT = 32
GRID_SIZE = 8
MAP_WIDTH = 16
MAP_HEIGHT = 32
BEDROCK_LEVEL = 30
MAX_BOOST_METER = 100
BOOST_DEPLETION_RATE = MAX_BOOST_METER / 90 -- lasts 3 seconds
BOOST_RECHARGE_RATE = MAX_BOOST_METER / 180 -- recharges in 6 seconds
FUEL_COST = 0.1
DURABILITY_COST = 0.2



-- I got some of these sprites from this library https://nerdyteachers.com/PICO-8/Sprites/
TILE_GRASS       = 0  
TILE_EMPTY       = 1
TILE_DIRT        = 2
TILE_STONE       = 3
TILE_GOLD        = 4
TILE_DIAMOND     = 5
TILE_BEDROCK     = 6
TILE_GAS_PUMP    = 7
TILE_UPGRADE_HUT = 9
SPR_MINER_RIGHT = 33
SPR_MINER_LEFT  = 34
SPR_MINER_UP    = 49
SPR_MINER_DOWN  = 50
SPR_GAS_PUMP    = 35
SPR_TRADER      = 51
SPR_GRASS       = {36,37}
SPR_DIRT        = {38,39}
SPR_STONE       = {52,53,54}
SPR_GOLD        = {55,56,57}
SPR_DIAMOND     = {40,41,42,43}
SPR_BEDROCK     = 58
SPR_UPGRADE_HUT = 59

surface_row = flr(SURFACE_HEIGHT / GRID_SIZE)
cam_y = 0
game_over = false
music_playing = false
show_instructions = true;

ore_info = {
  [TILE_DIRT]    = { sprites = SPR_DIRT, durability = 2 },
  [TILE_STONE]   = { sprites = SPR_STONE, durability = 3 },
  [TILE_GOLD]    = { sprites = SPR_GOLD, durability = 3 },
  [TILE_DIAMOND] = { sprites = SPR_DIAMOND, durability = 4 },
  [TILE_GRASS]   = { sprites = SPR_GRASS, durability = 2 }
}

ore_values = {
  [TILE_DIRT]    = 1,
  [TILE_STONE]   = 2,
  [TILE_GOLD]    = 5,
  [TILE_DIAMOND] = 10
}

miner = {
    x = 6 * GRID_SIZE,
    y = (surface_row - 1) * GRID_SIZE,
    speed_pixels = 1,
    direction = "right",
    anim_frame = 1,
    anim_timer = 0,
    sprites_right = {67, 68, 69, 70},
    sprites_left  = {83, 84, 85, 86},
    sprites_up    = {99, 100, 101, 102},
    sprites_down  = {115,116,117,118},
    current_sprite = 67,
    inventory = {
        [TILE_DIRT]    = 0,
        [TILE_STONE]   = 0,
        [TILE_GOLD]    = 0,
        [TILE_DIAMOND] = 0
    },
    minerBucks = 10,
    fuel = 50,
    max_fuel = 100,
    interacting_with_trader = false,
    boostActive = false,
    boostMeter = MAX_BOOST_METER
}


-- I ended up creating my own map in code because of the randomized ore spawning
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
            r = rnd()
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

building_row = surface_row - 1
map[building_row][1] = TILE_GAS_PUMP
map[building_row][MAP_WIDTH - 2] = TILE_UPGRADE_HUT

trader = {
    x = flr(MAP_WIDTH * 3/4) * GRID_SIZE,
    y = (surface_row - 1) * GRID_SIZE,
    speed = 1,
    move_delay = 3,
    move_timer = 0,
    current_sprite = SPR_TRADER,
    direction = 1
}

function update_trader()
    if miner.interacting_with_trader then return end
    
    trader.move_timer -= 1
    if trader.move_timer <= 0 then
        if rnd() < 0.05 then trader.direction = -trader.direction end
        left_bound = 2 * GRID_SIZE
        right_bound = (MAP_WIDTH - 3) * GRID_SIZE
        new_x = trader.x + trader.direction * trader.speed
        if new_x < left_bound or new_x > right_bound then
            trader.direction = -trader.direction
            new_x = trader.x + trader.direction * trader.speed
        end
        trader.x = new_x
        trader.move_timer = trader.move_delay
    end
end

function trade_with_trader()
    total = 0
    for tile, count in pairs(miner.inventory) do
        total = total + count * ore_values[tile]
        miner.inventory[tile] = 0
    end
    miner.minerBucks = miner.minerBucks + total
    print("trade complete: +" .. total .. " mb!", 1, 110, 11)
    miner.interacting_with_trader = false
end

function draw_trade_menu()
    menu_x = 16
    menu_y = 16
    menu_width = 96
    menu_height = 74
    rectfill(menu_x, menu_y, menu_x + menu_width, menu_y + menu_height, 0)
    rect(menu_x, menu_y, menu_x + menu_width, menu_y + menu_height, 7)
    text_y = menu_y + 4
    print("trader menu", menu_x + 8, text_y, 7)
    text_y = text_y + 8
    order = {TILE_DIRT, TILE_STONE, TILE_GOLD, TILE_DIAMOND}
    inv_names = {
      [TILE_DIRT]    = "dirt",
      [TILE_STONE]   = "stone",
      [TILE_GOLD]    = "gold",
      [TILE_DIAMOND] = "diamond"
    }
    for i = 1, #order do -- https://www.lua.org/manual/5.3/manual.html#3.4.7 # gives you the length 
      tile = order[i]
      name = inv_names[tile]
      count = miner.inventory[tile] or 0
      print(name .. ": " .. count .. " @ " .. ore_values[tile], menu_x + 4, text_y, 7)
      text_y = text_y + 8
    end
    trade_total = 0
    for tile, count in pairs(miner.inventory) do
        trade_total = trade_total + count * ore_values[tile]
    end
    print("total: " .. trade_total, menu_x + 4, text_y, 7)
    text_y = text_y + 8
    print("press z to trade", menu_x + 4, text_y, 3)
    text_y = text_y + 16
    print("press x to cancel", menu_x + 4, text_y, 8)
end

function tnt_explosion()
    miner_cell_x = flr(miner.x / GRID_SIZE)
    miner_cell_y = flr(miner.y / GRID_SIZE)
    for oy = -1, 1 do
        for ox = -1, 1 do
            cx = miner_cell_x + ox
            cy = miner_cell_y + oy
            if cx >= 0 and cx < MAP_WIDTH and cy >= 0 and cy < MAP_HEIGHT then
                cell = map[cy][cx]
                if type(cell) == "table" then
                    if cell.t == TILE_GRASS then
                        miner.inventory[TILE_DIRT] = miner.inventory[TILE_DIRT] + 1
                    else
                        miner.inventory[cell.t] = miner.inventory[cell.t] + 1
                    end
                    map[cy][cx] = TILE_EMPTY
                    sfx(0)
                end
            end
        end
    end
end

function can_move(new_x, new_y)
    checked = {}
    corners = {
        {new_x, new_y},
        {new_x + GRID_SIZE - 1, new_y},
        {new_x, new_y + GRID_SIZE - 1},
        {new_x + GRID_SIZE - 1, new_y + GRID_SIZE - 1}
    }
    for i, corner in ipairs(corners) do    -- https://pico-8.fandom.com/wiki/IPairs
        cx, cy = corner[1], corner[2]
        cell_x = flr(cx / GRID_SIZE)
        cell_y = flr(cy / GRID_SIZE)
        key = cell_x .. "," .. cell_y
        if not checked[key] then
            checked[key] = true
            if cell_x < 0 or cell_x >= MAP_WIDTH or cell_y < 0 or cell_y >= MAP_HEIGHT then
                return false
            end
            cell = map[cell_y][cell_x]
            if type(cell) == "table" then
                info = ore_info[cell.t]
                cell.d = cell.d - DURABILITY_COST
                if cell.d > 0 then
                    stage = flr((info.durability - cell.d) + 1)
                    if stage < 1 then stage = 1 end
                    if stage > #info.sprites then stage = #info.sprites end
                    cell.sprite = info.sprites[stage]
                    return false
                else
                    if cell.t == TILE_GRASS then
                        miner.inventory[TILE_DIRT] = miner.inventory[TILE_DIRT] + 1
                    else
                        miner.inventory[cell.t] = miner.inventory[cell.t] + 1
                    end
                    map[cell_y][cell_x] = TILE_EMPTY
                    sfx(0)
                end
            elseif cell == TILE_BEDROCK then
                return false
            end
        end
    end
    return true
end


function miner_near_pump()
    return abs(miner.x - (1 * GRID_SIZE)) < GRID_SIZE and abs(miner.y - ((surface_row - 1) * GRID_SIZE)) < GRID_SIZE
end

function miner_near_trader()
    return abs(miner.x - trader.x) < GRID_SIZE and abs(miner.y - trader.y) < GRID_SIZE
end


function draw_instructions()
    cls(0)

    print("how to play", 32, 10, 7)
    print("- move: arrow keys", 10, 30, 7)
    print("- dig: walk into blocks", 10, 40, 7)
    print("- tnt + boost: press 'z'", 10, 50, 7)
    print("- trade: press 'x' on trader", 10, 60, 7)
    print("- refuel: press 'x' on pump", 10, 70, 7)
    print("- earn money by selling ores", 10, 80, 7)
    print("press x to start", 40, 100, 11)

end


function _init()
    show_instructions = false
    game_over = false
    music_playing = false
    cam_y = 0

    miner.x = 6 * GRID_SIZE
    miner.y = (surface_row - 1) * GRID_SIZE
    miner.speed_pixels = 1
    miner.direction = "right"
    miner.anim_frame = 1
    miner.anim_timer = 0
    miner.current_sprite = 67
    miner.fuel = 40
    miner.boostMeter = MAX_BOOST_METER
    miner.minerBucks = 10
    miner.inventory = {
        [TILE_DIRT] = 0,
        [TILE_STONE] = 0,
        [TILE_GOLD] = 0,
        [TILE_DIAMOND] = 0
    }

    trader.x = flr(MAP_WIDTH * 3/4) * GRID_SIZE
    trader.y = (surface_row - 1) * GRID_SIZE

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
                r = rnd()
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

    building_row = surface_row - 1
    map[building_row][1] = TILE_GAS_PUMP
    map[building_row][MAP_WIDTH - 2] = TILE_UPGRADE_HUT
end

function _update()
    if show_instructions then
        if btnp(5) then
            show_instructions = false
        end
    end

    if game_over then
        if btnp(5) then
            _init()
        end
        return 
    end

    if music_playing == false then 
        music(0,0)  -- I got the music from Gruber here https://www.lexaloffle.com/bbs/?pid=38442
        music_playing = true
    end

    if miner.fuel <= 0 then
        game_over = true
        return
    end

    if not miner.interacting_with_trader then
        if btnp(4) and miner.boostMeter >= MAX_BOOST_METER then
            miner.boostActive = true
            tnt_explosion()
        end
    end

    if miner.boostActive then
        miner.boostMeter = miner.boostMeter - BOOST_DEPLETION_RATE
        if miner.boostMeter <= 0 then
            miner.boostMeter = 0
            miner.boostActive = false
        end
    else
        miner.boostMeter = mid(0, miner.boostMeter + BOOST_RECHARGE_RATE, MAX_BOOST_METER)
    end

    if miner_near_trader() then
        if btnp(5) then
            miner.interacting_with_trader = not miner.interacting_with_trader
        end
    end

    if miner.interacting_with_trader then
        if btnp(4) then
            trade_with_trader()
        end
        return
    end

    dx, dy = 0, 0
    if btn(0) then 
        dx = -1 
        if miner.direction ~= "left" then 
            miner.direction = "left"
            miner.current_sprite = miner.sprites_left[1]
            miner.anim_frame = 1
            miner.anim_timer = 0
        end
    end
    if btn(1) then 
        dx =  1 
        if miner.direction ~= "right" then 
            miner.direction = "right"
            miner.current_sprite = miner.sprites_right[1]
            miner.anim_frame = 1
            miner.anim_timer = 0
        end
    end
    if btn(2) then 
        dy = -1 
        if miner.direction ~= "up" then 
            miner.direction = "up"
            miner.current_sprite = miner.sprites_up[1]
            miner.anim_frame = 1
            miner.anim_timer = 0
        end
    end
    if btn(3) then 
        dy =  1 
        if miner.direction ~= "down" then 
            miner.direction = "down"
            miner.current_sprite = miner.sprites_down[1]
            miner.anim_frame = 1
            miner.anim_timer = 0
        end
    end

    if dx ~= 0 then
        miner.y = flr(miner.y / GRID_SIZE) * GRID_SIZE
    elseif dy ~= 0 then
        miner.x = flr(miner.x / GRID_SIZE) * GRID_SIZE
    end

    if dx ~= 0 or dy ~= 0 then
        px_speed = miner.boostActive and (miner.speed_pixels * 2) or miner.speed_pixels
        for i = 1, px_speed do
            new_x = miner.x + dx
            new_y = miner.y + dy
            if can_move(new_x, new_y) then
                miner.x = new_x
                miner.y = new_y
                miner.fuel = max(0, miner.fuel - FUEL_COST)
                miner.anim_timer = miner.anim_timer + 1
                if miner.anim_timer >= 2 then
                    miner.anim_timer = 0
                    miner.anim_frame = (miner.anim_frame % 4) + 1
                end
                if miner.direction == "left" then
                    miner.current_sprite = miner.sprites_left[miner.anim_frame]
                elseif miner.direction == "right" then
                    miner.current_sprite = miner.sprites_right[miner.anim_frame]
                elseif miner.direction == "up" then
                    miner.current_sprite = miner.sprites_up[miner.anim_frame]
                elseif miner.direction == "down" then
                    miner.current_sprite = miner.sprites_down[miner.anim_frame]
                end
            end
        end
    end

    if miner.direction == "up" and miner.y < (surface_row * GRID_SIZE) then
        miner.was_moving_up = true
    else
        miner.was_moving_up = false
    end

    if miner.y <= (surface_row * GRID_SIZE) - GRID_SIZE and miner.was_moving_up then
        miner.y = (surface_row * GRID_SIZE) - GRID_SIZE
        miner.current_sprite = miner.sprites_right[miner.anim_frame]
        miner.was_moving_up = false
    end

    
    if miner_near_pump() then
        if btnp(5) then
            missing_fuel = miner.max_fuel - miner.fuel
            if missing_fuel > 0 then
                cost = ceil(missing_fuel / 10)
                if miner.minerBucks >= cost then
                    miner.minerBucks = miner.minerBucks - cost
                    miner.fuel = miner.max_fuel
                    print("refueled for " .. cost .. " mb!", 1, 110, 11)
                elseif miner.minerBucks > 0 then
                    affordable_fuel = miner.minerBucks * 10
                    miner.fuel = miner.fuel + affordable_fuel
                    miner.minerBucks = 0
                    print("partial refuel: +" .. affordable_fuel .. " fuel", 1, 110, 10)
                else
                    print("not enough mb to refuel!", 1, 110, 8)
                end
            end
        end
    end

    update_trader()
    cam_y = mid(0, miner.y - 32, MAP_HEIGHT * GRID_SIZE - 128)
end

function _draw()
    if show_instructions then
        draw_instructions()
    else
        cls(12)
        camera(0, cam_y)
        surface_px = surface_row * GRID_SIZE
        bedrock_px = BEDROCK_LEVEL * GRID_SIZE
        rectfill(0, 0, 127, surface_px - 1, 12)
        rectfill(0, surface_px, 127, bedrock_px - 1, 4)
        rectfill(0, bedrock_px, 127, MAP_HEIGHT * GRID_SIZE - 1, 0)
        for y = 0, MAP_HEIGHT - 1 do
            for x = 0, MAP_WIDTH - 1 do
                cell = map[y][x]
                draw_x = x * GRID_SIZE
                draw_y = y * GRID_SIZE
                if type(cell) == "table" then
                    spr(cell.sprite, draw_x, draw_y)
                elseif cell == TILE_BEDROCK then
                    spr(SPR_BEDROCK, draw_x, draw_y)
                elseif cell == TILE_GAS_PUMP then
                    spr(SPR_GAS_PUMP, draw_x, draw_y)
                elseif cell == TILE_UPGRADE_HUT then
                    spr(SPR_UPGRADE_HUT, draw_x, draw_y)
                end
            end
        end

        spr(trader.current_sprite, trader.x, trader.y)
        palt()
        palt(13, true)
        palt(0, false)
        spr(miner.current_sprite, miner.x, miner.y)
        camera()

        print("minerbucks: " .. miner.minerBucks, 1, 1, 7)

        bar_x = 70
        bar_y = 1
        bar_width = 50
        bar_height = 6
        fuel_ratio = miner.fuel / miner.max_fuel
        fill_width = flr(bar_width * fuel_ratio)
        bar_color = 11
        if fuel_ratio <= 0.3 then
            bar_color = 8
        elseif fuel_ratio < 0.7 then
            bar_color = 10
        end
        rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 5)
        rectfill(bar_x, bar_y, bar_x + fill_width, bar_y + bar_height, bar_color)
        rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 7)
        print("fuel", bar_x, bar_y + bar_height + 1, 7)

        if miner_near_trader() then
            print("press x to trade", 1, 14, 10)
        end

        if game_over then
            msg = "game over-press x to play again"
            msg_width = #msg * 4
            msg_x = (128 - msg_width) / 2
            msg_y = 64
            rectfill(0, msg_y - 4, 128, msg_y + 8, 0)
            print(msg, msg_x, msg_y, 8)
        end

        if miner.interacting_with_trader then
            draw_trade_menu()
        end

        boost_bar_width = 40
        boost_bar_height = 8
        boost_bar_x = 128 - boost_bar_width - 2
        boost_bar_y = 128 - boost_bar_height - 2
        boost_ratio = miner.boostMeter / MAX_BOOST_METER
        boost_fill_width = flr(boost_bar_width * boost_ratio)
        rectfill(boost_bar_x, boost_bar_y, boost_bar_x + boost_bar_width, boost_bar_y + boost_bar_height, 5)
        rectfill(boost_bar_x, boost_bar_y, boost_bar_x + boost_fill_width, boost_bar_y + boost_bar_height, 8)
        rect(boost_bar_x, boost_bar_y, boost_bar_x + boost_bar_width, boost_bar_y + boost_bar_height, 7)
        if miner.boostMeter >= MAX_BOOST_METER then
            text = "tnt - 'z'"
            text_w = #text * 4
            text_x = boost_bar_x + (boost_bar_width - text_w) / 2
            text_y = boost_bar_y + (boost_bar_height - 4) / 2
            print(text, text_x, text_y, 0)  -- black text
        end

        if miner_near_pump() then
            missing_fuel = miner.max_fuel - miner.fuel
            if missing_fuel > 0 then
                cost = ceil(missing_fuel / 10)
                print("hold x to refuel (" .. cost .. " mb)", 1, 14, 10)
            else
                print("fuel tank full!", 1, 14, 11)
            end
        end
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
00000000ddddddddddddddddd888888d333333333333d3334443444f44dd444dc55cc55cc55cd55cc55cd55cc55cd5dc00000000000000000000000000000000
00000000dddddddddddddddd0886668d333333333d3d33d34f4434444f443d445c5c55c55d5c55c55d5d55cd5d5d55dd00000000000000000000000000000000
00000000dddddddddddddddd0886068d3333333333d3d333444f444fd44f44dfc555cc55c555cc55d555cd55d555dd5500000000000000000000000000000000
00000000111155dddd5511110886608d33333333d33333d34f344f344f34df3455cc555c55dc555c55dc555c55dd55dd00000000000000000000000000000000
000000001111556dd65511110806668d34434434344344d44444444444d44444c5c5c5ccc5c5c5cdc5c5d5cdcdc5d5cd00000000000000000000000000000000
0000000011111166661111110808888d4f3443444d3d43444f4443444f44434d5c55555c5c555d5c5d5d5d5c5d5d5d5d00000000000000000000000000000000
000000000010016dd61001000008858d4444f34f4d44f34f4444f34fd444fd4f555c5cc55d5c5cc55d5c5ccd5d5c5dcd00000000000000000000000000000000
0000000000d00dddddd00d00d888888d34344444343d4d443434444434d4444dcc55c555cc55d555cc55d5d5dcd5d5d500000000000000000000000000000000
00000000dddd6dddd01110ddd77777dd6556655665566556d55d655da55aa55aa55da55aad5dad5a05050020ddd82ddd00000000000000000000000000000000
00000000ddd666ddd01110dd7777777d565555655d5555d5dd5555d55a5a55a5da5a55a5da5d55d502005000dd8882dd00000000000000000000000000000000
00000000dd15551ddd111ddddf0f0fdd555565555555d55555d5d55da555aa55a555aa55d555dd5550020050d888882d00000000000000000000000000000000
00000000dd05550dd01110dddfffffdd65655555656555d5656555d555aa555a55da55da55da55da200000208888888200000000000000000000000000000000
00000000dd01110dd05550ddd6a6a6dd5555655555d5655555d5d555a5a5a5aaa5a5a5ada5a5d5ad000200009999999400000000000000000000000000000000
00000000ddd111ddd15551dddfa6afdd565555565655555656d555d65a55555a5a555d5a5d5d5d5a020005009449c19400000000000000000000000000000000
00000000dd01110ddd666ddddfa6afdd65565655d5565655d55d5d55555a5aa5d55d5aa5d55d5ad50050000294a91c9400000000000000000000000000000000
00000000dd01110dddd6dddddd000ddd565555655655d5655655d565aa55a555ad55ad55ad55ad5d250020509449999400000000000000000000000000000000
dddddddddddddddd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
dddddddddddddddd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
dddddddddddddddd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
111155dddd5511110000000011100ddd11100ddd11100ddd11100ddd000000000000000000000000000000000000000000000000000000000000000000000000
1111556dd6551111000000001110016d1110016d1110016d1110016d000000000000000000000000000000000000000000000000000000000000000000000000
11111166661111110000000011111166111111661111116611111166000000000000000000000000000000000000000000000000000000000000000000000000
0010016dd6100100000000005010516d0510016d0010016d0015016d000000000000000000000000000000000000000000000000000000000000000000000000
00d00dddddd00d000000000000d00ddd00d05ddd05d50ddd50d00ddd000000000000000000000000000000000000000000000000000000000000000000000000
dddd6dddd01110dd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
ddd666ddd01110dd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
dd15551ddd111ddd00000000dddddddddddddddddddddddddddddddd000000000000000000000000000000000000000000000000000000000000000000000000
dd05550dd01110dd00000000ddd00111ddd00111ddd00111ddd00111000000000000000000000000000000000000000000000000000000000000000000000000
dd01110dd05550dd00000000d6100111d6100111d6100111d6100111000000000000000000000000000000000000000000000000000000000000000000000000
ddd111ddd15551dd0000000066111111661111116611111166111111000000000000000000000000000000000000000000000000000000000000000000000000
dd01110ddd666ddd00000000d6150105d6100150d6100100d6105100000000000000000000000000000000000000000000000000000000000000000000000000
dd01110dddd6dddd00000000ddd00d00ddd50d00ddd05d50ddd00d05000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dddd6ddddddd6ddddddd6ddddddd6ddd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddd666ddddd666ddddd666ddddd666dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddd111ddddd111ddddd111ddddd111dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd51015ddd01010ddd01010ddd01010d000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd01110ddd01110ddd01110ddd51115d000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddd111ddddd111ddddd111ddddd111dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd01110ddd51115ddd01110ddd01110d000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd51115ddd01110ddd01110ddd01110d000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000d51115ddd01110ddd01110ddd01110dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000d01110ddd51115ddd01110ddd01110dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd111ddddd111ddddd111ddddd111ddd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000d01110ddd01110ddd01110ddd51115dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000d51015ddd01010ddd01010ddd01010dd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd111ddddd111ddddd111ddddd111ddd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000dd666ddddd666ddddd666ddddd666ddd000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddd6ddddddd6ddddddd6ddddddd6dddd000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
0005000021050000002a0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0112000003744030250a7040a005137441302508744080251b7110a704037440302524615080240a7440a02508744087250a7040c0241674416025167251652527515140240c7440c025220152e015220150a525
011200000c033247151f5152271524615227151b5051b5151f5201f5201f5221f510225212252022522225150c0331b7151b5151b715246151b5151b5051b515275202752027522275151f5211f5201f5221f515
__music__
01 01024344
02 01024344

-- https://www.lexaloffle.com/bbs/?uid=11292 the background music is from GRUBER, he did such an awesome job with his playlists

