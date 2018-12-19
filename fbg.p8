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
}

-- game data
local board_width = 10
local board_height = 20
local block_size = 6
local board_offset = 3

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
    piece_index = 1,
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

function board_remove_row(j0)
    for j=j0, board_height do
        for i=1, board_width do
            local v = 0
            if j < board_height then v = board[j + 1][i] end
            board[j][i] = v
        end
    end
end

function board_clean()
    local cleared = 0
    local top = 0
    local j = 1

    while j + cleared <= board_height do
        local completed = true
        for i=1, board_width do
            if not board_occupied(i, j) then
                completed = false
                break
            end
        end

        if completed then
            board_remove_row(j)
            top = j + cleared
            cleared = cleared + 1
        else
            j = j + 1
        end
    end

    return cleared, top
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
    game_paused = true
    game_over = true
end

function switch_piece()
    piece.piece_index = flr(rnd(#pieces)) + 1
    piece.rotation_index = 1
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

    local piece_blocks = pieces[piece.piece_index][rotation_index]
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
    piece_try_move(-1, 0)
end

function piece_move_right()
    piece_try_move(1, 0)
end

function piece_complete()
    piece_for_each_block(function (i, j)
        if i >= 1 and i <= board_width and j >= 1 and j <= board_height then
            board[j][i] = piece.piece_index
        end
        return true
    end)
end

function piece_move_down()
    if piece.piece_index > 0 then
        if piece_try_move_down() then
            -- check for slide underneath
            if btn(buttons.left) and not piece_test_move(-1, 1) and piece_test_move(-1, 0) then
                piece_move_left()
            elseif btn(buttons.right) and not piece_test_move(1, 1) and piece_test_move(1, 0) then
                piece_move_right()
            end
        else
            piece_complete()

            local cleared = board_clean()
            game_score_update(cleared)
            -- todo: scoring, next piece

            fast_drop = false
            piece.piece_index = 0
            timer_next_piece = next_piece_delay

            if cleared > 0 then
                timer_next_piece = timer_next_piece + clear_delay
            end
        end
    end
end

function piece_try_rotate(offset)
    local rotation_index = (piece.rotation_index - 1 + offset) % #pieces[piece.piece_index] + 1
    if piece_validate(nil, nil, rotation_index) then
        piece.rotation_index = rotation_index
        return true
    end
    return false
end

function piece_rotate_cw()
    return piece_try_rotate(-1)
end

function piece_rotate_ccw()
    return piece_try_rotate(1)
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
    switch_piece()
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
        if piece.piece_index == 0 and timer_next_piece > 0 then
            timer_next_piece = timer_next_piece - 1
        else
            if piece.piece_index == 0 then
                switch_piece()
                if piece.piece_index > 0 and not piece_validate() then
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

function draw_block(i, j, v)
    local x, y = board_offset + block_size * (i - 1), board_offset + block_size * (20 -  j)
    spr(piece_sprites[v], x, y)
end

function _draw()
    cls(colors.dark_blue)

    local x2, y2 = 3 + block_size * board_width - 1, 3 + block_size * board_height - 1
    rectfill(board_offset, board_offset, x2, y2, colors.black)

    -- board
    clip(board_offset, board_offset, block_size * board_width, block_size * board_height)
    for j=1, board_height do
        for i=1, board_width do
            local v = board[j][i]
            if v > 0 then
                draw_block(i, j, v)
            end
        end
    end

    -- piece
    if piece.piece_index > 0 then
        local piece_blocks = pieces[piece.piece_index][piece.rotation_index]
        local i1 = piece.i
        local j1 = piece.j
        for i=1, #piece_blocks do
            local block = piece_blocks[i]
            draw_block(i1 + block[1], j1 + block[2], piece.piece_index)
        end
    end
    clip()

    cursor(64 + board_offset, board_offset)
    color(colors.white)
    print("level: " .. level)
    print("lines: " .. lines)
    print("score: " .. score)

    if game_over then
        print("")
        print("game over!")
    end

    if debug and debug_message ~= nil then
        print(debug_message, 0, 122, colors.white)
    end
end
__gfx__
dddddd00aaaaaa0011111100aaaaaa0099999900aaaaa900cccccd00000000000000000000000000000000000000000000000000000000000000000000000000
dcccc100aaaaaa001cccc100a999940099999900aaaa9900ccccdd00000000000000000000000000000000000000000000000000000000000000000000000000
dcccc100aa99aa001cddd100a999940099449900aaa99900cccddd00000000000000000000000000000000000000000000000000000000000000000000000000
dcccc100aa99aa001cddd100a999940099449900aa449900cc11dd00000000000000000000000000000000000000000000000000000000000000000000000000
dcccc100a4444a001cddd100a999940092222900a4444900c1111d00000000000000000000000000000000000000000000000000000000000000000000000000
d11111004444440011111100a4444400222222004444440011111100000000000000000000000000000000000000000000000000000000000000000000000000
