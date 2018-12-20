pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- constants
colors = {
    black = 0,
    dark_blue = 1,
    dark_purple = 2,
    dark_green = 3,
    brown = 4,
    dark_gray = 5,
    light_gray = 6,
    white = 7,
    red = 8,
    orange = 9,
    yellow = 10,
    green = 11,
    blue = 12,
    indigo = 13,
    pink = 14,
    peach = 15,
}

buttons = {
    left = 0,
    right = 1,
    up = 2,
    down = 3,
    z = 4,
    x = 5,
}

local sprites = {
    left_gun = 0,
    left_snake = 1,
    line = 2,
    right_gun = 3,
    right_snake = 4,
    square = 5,
    tee = 6,

    title = 8,
}

local sounds = {
    rotate = 0,
    move = 1,
    land = 2,
    clear = 3,
    quad = 4,
    lose = 5,
}

-- game data
local board_width = 10
local board_height = 20
local block_size = 6
local board_offset = 4

local cleared_to_score = { 40, 100, 300, 1200 }
local done_period = 60
local fast_move_initial_delay = 10
local fast_move_period = 6
local first_drop_period = 60
local fast_drop_period = 2
local next_piece_delay = 10
local clear_delay = 20
local drop_periods = { 48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1 }

local piece_sprites = {
    sprites.left_snake,
    sprites.right_snake,
    sprites.left_gun,
    sprites.right_gun,
    sprites.square,
    sprites.line,
    sprites.tee,
}
local piece_widths = { 3, 3, 3, 3, 2, 4, 3 }
local piece_offsets = { 1, 1, 1, 1, 1, 0, 1 }
local piece_heights = { 2, 2, 2, 2, 2, 1, 2 }
local pieces = {
    {   { { 1, 0 }, { 2, 0 }, { 2, -1 }, { 3, -1 } },
        { { 3, 1 }, { 2, 0 }, { 3, 0 },  { 2, -1 } }, },
    {   { { 2, 0 }, { 3, 0 }, { 1, -1 }, { 2, -1 } },
        { { 2, 1 }, { 2, 0 }, { 3, 0 },  { 3, -1 } }, },
    {   { { 1, 0 }, { 2, 0 }, { 3, 0 },  { 3, -1 } },
        { { 2, 1 }, { 2, 0 }, { 1, -1 }, { 2, -1 } },
        { { 1, 1 }, { 1, 0 }, { 2, 0 },  { 3,  0 } },
        { { 2, 1 }, { 3, 1 }, { 2, 0 },  { 2, -1 } }, },
    {   { { 1, 0 }, { 2, 0 }, { 3, 0 },  { 1, -1 } },
        { { 1, 1 }, { 2, 1 }, { 2, 0 },  { 2, -1 } },
        { { 3, 1 }, { 1, 0 }, { 2, 0 },  { 3,  0 } },
        { { 2, 1 }, { 2, 0 }, { 2, -1 }, { 3, -1 } }, },
    {   { { 1, 0 }, { 2, 0 }, { 1, -1 },  { 2, -1 } }, },
    {   { { 0, 0 }, { 1, 0 }, { 2, 0 },  { 3,  0 } },
        { { 2, 2 }, { 2, 1 }, { 2, 0 },  { 2, -1 } }, },
    {   { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 2, -1 } },
        { { 2, 1 }, { 1, 0 }, { 2, 0 }, { 2, -1 } },
        { { 2, 1 }, { 1, 0 }, { 2, 0 }, { 3,  0 } },
        { { 2, 1 }, { 2, 0 }, { 3, 0 }, { 2, -1 } }, },
}

-- debugging
local debug = true
local debug_message = nil

-- game state
local board = {}
local score = 0
local lines = 0
local level = 0
local game_over = false
local game_paused = false

local input_last_left = false
local input_last_right = false
local input_last_down = false
local input_last_cw = false
local input_last_ccw = false

local first_drop = false
local fast_drop = false
local fast_drop_row = 0
local fast_move = false

local timer_next_piece = 0
local timer_fast_move = 0
local timer_drop = 0

local piece = {
    index = 1,
    next_index = 1,
    rotation_index = 1,
    i = 0,
    j = 0,
}

-- game logic
function board_reset()
    for j=1, board_height do
        for i=1, board_width do
            board[j][i] = 0
        end
    end
end

function board_remove_row(j)
    board[j].deleted = true
end

function board_expunge_rows()
    local destination = 0
    for j=1, board_height do
        local deleted = board[j].deleted
        if deleted then
            board[j].deleted = false
        else
            destination = destination + 1
        end

        if not deleted then
            for i=1, board_width do
                board[destination][i] = board[j][i]
            end
        end
    end

    for j=destination + 1, board_height do
        for i=1, board_width do
            board[j][i] = 0
        end
    end
end

function board_clean()
    local cleared = 0

    for j=1, board_height do
        local completed = true
        for i=1, board_width do
            if not board_occupied(i, j) then
                completed = false
                break
            end
        end

        if completed then
            board_remove_row(j)
            cleared = cleared + 1
        end
    end

    return cleared
end

function game_score_update(cleared)
    local fast_drop_points = 0
    if fast_drop then
        fast_drop_points = fast_drop_row - piece.j
        score = score + fast_drop_points
    end

    if cleared >= 1 and cleared <= #cleared_to_score then
        score = score + cleared_to_score[cleared] * (level + 1)
        lines = lines + cleared
        if level < flr(lines / 10) then
            level = level + 1
        end
    end
end

function game_end()
    sfx(sounds.lose)
    game_paused = true
    game_over = true
end

function piece_hide()
    piece.index = 0
end

function piece_choose_next()
    piece.next_index = flr(rnd(#pieces)) + 1
end

function piece_advance()
    piece_hide()
    if piece.next_index == 0 then
        piece_choose_next()
    end

    piece.index = piece.next_index
    piece.rotation_index = 1
    piece_choose_next()
    piece.i = 4
    piece.j = 20
end

function board_occupied(i, j)
    return board[j][i] ~= 0
end

function piece_for_each_block(callback, i, j, rotation_index)
    local i0 = i or piece.i
    local j0 = j or piece.j
    local rotation_index = rotation_index or piece.rotation_index

    local piece_blocks = pieces[piece.index][rotation_index]
    for n=1, #piece_blocks do
        local offsets = piece_blocks[n]
        local i = i0 + offsets[1]
        local j = j0 + offsets[2]

        if not callback(i, j) then
            break
        end
    end
end

function piece_validate(i, j, rotation_index)
    local valid = true
    piece_for_each_block(function (i, j)
        -- note: overflowing the vertical bound is acceptable
        if i >= 1 and i <= board_width and j >= 1 then
            if j <= board_height and board_occupied(i, j) then
                valid = false
            end
        else
            valid = false
        end

        return valid
    end, i, j, rotation_index)

    return valid
end

function piece_test_move(di, dj)
    return piece_validate(piece.i + di, piece.j + dj)
end

function piece_try_move(di, dj)
    if piece_test_move(di, dj) then
        piece.i = piece.i + di
        piece.j = piece.j + dj
        return true
    end

    return false
end

function piece_try_move_down()
    return piece_try_move(0, -1)
end

function piece_move_left()
    if piece_try_move(-1, 0) then
        sfx(sounds.move)
    end
end

function piece_move_right()
    if piece_try_move(1, 0) then
        sfx(sounds.move)
    end
end

function piece_complete()
    piece_for_each_block(function (i, j)
        if i >= 1 and i <= board_width and j >= 1 and j <= board_height then
            board[j][i] = piece.index
        end
        return true
    end)
end

function piece_move_down()
    if piece.index > 0 then
        if piece_try_move_down() then
            -- check for slide underneath
            if btn(buttons.left) and not piece_test_move(-1, 1) and piece_test_move(-1, 0) then
                piece_move_left()
            elseif btn(buttons.right) and not piece_test_move(1, 1) and piece_test_move(1, 0) then
                piece_move_right()
            end
        else
            piece_complete()
            sfx(sounds.land)

            local cleared = board_clean()
            game_score_update(cleared)
            -- todo: scoring, next piece

            fast_drop = false
            piece_hide()
            timer_next_piece = next_piece_delay

            if cleared > 0 then
                timer_next_piece = timer_next_piece + clear_delay
                if cleared == 4 then
                    sfx(sounds.quad)
                else
                    sfx(sounds.clear)
                end
            end
        end
    end
end

function piece_try_rotate(offset)
    local rotation_index = (piece.rotation_index - 1 + offset) % #pieces[piece.index] + 1
    if piece_validate(nil, nil, rotation_index) then
        piece.rotation_index = rotation_index
        return true
    end
    return false
end

function piece_rotate_cw()
    if piece_try_rotate(-1) then
        sfx(sounds.rotate)
    end
end

function piece_rotate_ccw()
    if piece_try_rotate(1) then
        sfx(sounds.rotate)
    end
end

function get_drop_period()
    if level < #drop_periods then
        return drop_periods[level + 1]
    else
        return drop_periods[#drop_periods]
    end
end

function reset()
    board_reset()
    piece.index = 0
    piece.next_index = 0
    piece_advance()
    score = 0
    lines = 0
    level = 0
    game_over = false
    game_paused = false

    first_drop = true
    fast_drop = false
    fast_drop_row = 0
    fast_move = false

    timer_drop = 0
end

function _init()
    for j=1, board_height do
        board[j] = {}
    end

    reset()
end

function _update60()
    if not game_paused then
        if piece.index == 0 and timer_next_piece > 0 then
            timer_next_piece = timer_next_piece - 1
        else
            if piece.index == 0 then
                board_expunge_rows()
                piece_advance()
                if piece.index > 0 and not piece_validate() then
                    game_end()
                end
            end

            -- game may be paused due to loss
            if not game_paused then
                -- input
                local left_pressed = btn(buttons.left)
                local right_pressed = btn(buttons.right)
                local down_pressed = btn(buttons.down)
                local cw_pressed = btn(buttons.z)
                local ccw_pressed = btn(buttons.x)

                if left_pressed and not input_last_left then
                    piece_move_left()
                    timer_fast_move = -fast_move_initial_delay
                end

                if right_pressed and not input_last_right then
                    piece_move_right()
                    timer_fast_move = -fast_move_initial_delay
                end

                if left_pressed or right_pressed then
                    timer_fast_move = timer_fast_move + 1
                    while timer_fast_move >= fast_move_period do
                        timer_fast_move = timer_fast_move - fast_move_period
                        if left_pressed then piece_move_left() end
                        if right_pressed then piece_move_right() end
                    end
                end

                if down_pressed and not input_last_down then
                    fast_drop = true
                    fast_drop_row = piece.j

                    -- don't drop multiple times
                    timer_drop = min(min(timer_drop, fast_drop_period), get_drop_period())
                elseif not down_pressed and input_last_down then
                    fast_drop = false
                end

                if cw_pressed and not input_last_cw then
                    piece_rotate_cw()
                end

                if ccw_pressed and not input_last_ccw then
                    piece_rotate_ccw()
                end

                -- drop
                local drop_period = get_drop_period(level)
                if first_drop then drop_period = first_drop_period end
                if fast_drop then drop_period = min(fast_drop_period, drop_period) end

                timer_drop = timer_drop + 1
                while timer_drop >= drop_period do
                    piece_move_down()
                    timer_drop = timer_drop - drop_period
                    first_drop = false
                end

                input_last_left = left_pressed
                input_last_right = right_pressed
                input_last_down = down_pressed
                input_last_cw = cw_pressed
                input_last_ccw = ccw_pressed
            end
        end
    end
end

function map_position(i ,j)
    return board_offset + block_size * (i - 1), board_offset + block_size * (20 -  j)
end

function draw_block_absolute(x, y, v)
    spr(piece_sprites[v], x, y)
end

function draw_block(i, j, v)
    local x, y = map_position(i, j)
    draw_block_absolute(x, y, v)
end

function draw_piece_absolute(x, y, index, rotation_index)
    if index > 0 then
        local piece_blocks = pieces[index][rotation_index]
        for i=1, #piece_blocks do
            local block = piece_blocks[i]
            draw_block_absolute(x + block_size * block[1], y - block_size * block[2], index)
        end
    end
end

function draw_piece(i, j, index, rotation_index)
    local x, y = map_position(i, j)
    draw_piece_absolute(x, y, index, rotation_index)
end

function draw_box(x1, y1, x2, y2, label)
    local border_color = colors.light_gray
    rectfill(x1 - 1, y1 - 1, x2 + 1, y1 - 1, border_color)
    rectfill(x1 - 1, y1, x1 - 1, y2, border_color)
    rectfill(x2 + 1, y1, x2 + 1, y2, border_color)
    rectfill(x1 - 1, y2 + 1, x2 + 1, y2 + 1, border_color)
    rectfill(x1, y1, x2, y2, colors.black)

    if label ~= nil then
        print(label, x1 + (x2 - x1) / 2 - #label * 4 / 2 + 1, y1 + 1, colors.white)
    end
end

function draw_box_number(x, y, label, number, digits)
    local x1 = x - 1
    local y1 = y - 1
    local x2 = x1 + 4 * max(#label, digits)
    local y2 = y + 11
    draw_box(x1, y1, x2, y2, label)
    local number_string = "" .. number
    print(number_string, x1 + (x2 - x1) / 2 - 2 * #number_string + 1, y + 6, colors.white)
end

local palette_fades = {
    { colors.yellow, colors.orange, colors.brown, colors.dark_purple },
    { colors.blue, colors.indigo, colors.dark_blue },
}

function fade_palette(offset)
    for i=1, #palette_fades do
        local fade = palette_fades[i]
        for j=1, #fade do
            local index = j + offset
            local c = (index <= #fade) and fade[index] or colors.black
            pal(fade[j], c)
        end
    end
end

function _draw()
    cls(colors.indigo)

    -- title
    palt(colors.black, false)
    spr(sprites.title, 64, 0, 8, 4)
    palt()

    -- board
    local x2, y2 = board_offset + block_size * board_width - 1, board_offset + block_size * board_height - 1
    draw_box(board_offset, board_offset, x2, y2)
    clip(board_offset, board_offset, block_size * board_width, block_size * board_height)
    local deleted_count = 0
    for j=1, board_height do if board[j].deleted then deleted_count = deleted_count + 1 end end

    local t = 1 - (timer_next_piece / (next_piece_delay + clear_delay))
    local flash = t >= 0 and t < 0.5 and (flr(t * 8) % 2 == 1)
    for j=1, board_height do
        local deleted = board[j].deleted
        local draw = true
        if deleted then
            if t <= 0.1 then
                fade_palette(1)
            elseif t <= 0.3 then
                fade_palette(2)
            elseif t <= 0.5 then
                fade_palette(3)
            else
                draw = false
            end
        end

        if draw then
            for i=1, board_width do
                local v = board[j][i]
                if v > 0 then
                    draw_block(i, j, v)
                end
            end
        end

        if deleted then
            pal()
        end

        -- quad effect
        if flash and deleted and deleted_count >= 4 then
            local x, y = map_position(1, j)
            rectfill(x, y, x + board_width * block_size, y + block_size, colors.white)
        end
    end

    -- pieces
    draw_piece(piece.i, piece.j, piece.index, piece.rotation_index)
    clip()

    local x, y = 96 - 2 * block_size, 32 + board_offset + 9 * 6
    draw_box(x - 1, y - 1, x + 4 * block_size, y + 6 + 4 + 2 * block_size, "next")
    local next_index = piece.next_index
    draw_piece_absolute(96 - piece_offsets[next_index] * block_size - piece_widths[next_index] * block_size / 2, y + 6 + 2 + (2 - piece_heights[next_index]) * block_size / 2, piece.next_index, 1)

    -- score
    draw_box_number(64 + board_offset + 1, 32 + board_offset + 6, "level", level, 2)
    draw_box_number(128 - board_offset - 4 * 5, 32 + board_offset + 6, "lines", level, 3)
    draw_box_number(96 - 7 * 2, 32 + board_offset + 5 * 6, "score", score, 7)

    if game_over then
        rectfill(32 - 5 * 4, 64 - 3, 32 + 5 * 4, 64 + 3, colors.black)
        print("game over!", 32 - 5 * 4 + 1, 64 - 2, colors.white)
    end

    if debug and debug_message ~= nil then
        print(debug_message, 0, 122, colors.white)
    end
end
__gfx__
dddddd00aaaaaa0011111100aaaaaa0099999900aaaaa900cccccd0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dcccc100aaaaaa001cccc100a999940099999900aaaa9900ccccdd0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dcccc100aa99aa001cddd100a999940099449900aaa99900cccddd0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dcccc100aa99aa001cddd100a999940099449900aa449900cc11dd0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dcccc100a4444a001cddd100a999940092222900a4444900c1111d0000000000ddddddd000dddddd0d0dddddddddddddddd0000dd0ddddddddddd0dddddddddd
d11111004444440011111100a444440022222200444444001111110000000000dddddd07770d00d070700ddddddddddddd077770070ddddddddd070ddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddd0700d077007070700d0ddd00ddd5070007070d00ddd0000700dddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddd07000700707070007070d0770d560777700700770d077707070ddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddd077700777070707077070700706a0700070707007070000770dddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddd07000700707070707007070070aa07000707070070700007070ddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddd070d0777707070707007007770aa0777700700770d0777070070dddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddd0ddd0000d0d0d0d0dd0dd0070aaa0000dd0dd00ddd000d0dd0ddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddddd0770994444465dddddddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddd560099944446a65ddddddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddd56aaa6990006aaa65dddddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddd56aaaaa607770aa006500000dd00dddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddd56aaaaaa07000aa077007707700770ddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddd56999944407090007007070707070070dddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddd569994440700770077707070707770ddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddd56994440700070700707070707000ddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddd56944650777007777070707007770dddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddd56465dd000560000a0a0a00d000ddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddddd565ddddddd5699994444465dddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddd5ddddddddd56999444465ddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddddddddddddddddd569944465dddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddd5694465ddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddddddddddddddddddd56465dddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddd565ddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000ddddddddddddddddddddddddddddddddddddddddddd5dddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
0000000000000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
__sfx__
010500002135500305213500030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305
010200002d34000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500000234500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005
010200001d3602136024360293601f3602336026360000001e3602236025360000001d3502135024350000001c3502035023350000001b3401f34022340000001a3301e3302133000000193201d3202032000000
0104000021362000022836200002213520000228352000022d3420000228342000022d3320000228332000022d3220000228322000022d312000022d312000020000200002000020000200002000000000000000
015a00000065500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605000050000500005
