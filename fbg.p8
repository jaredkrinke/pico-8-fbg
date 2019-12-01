pico-8 cartridge // http://www.pico-8.com
version 18
__lua__
-- Falling Block Game
-- v0.1

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

-- utilities
big_int = {}
big_int_mt = {
    __index = big_int,
    __concat = function (a, b)
        if type(a) == "string" and getmetatable(b) == big_int_mt then
            return a .. b:to_string()
        end
    end,
}

function big_int.create()
    local instance = {
        digits = {},
    }
    setmetatable(instance, big_int_mt)

    return instance
end

function big_int:reset()
    local digits = self.digits
    local count = #digits
    for i=1, count do
        digits[i] = nil
    end
end

function big_int:add(x)
    local digits = self.digits
    local i = 1
    local carry = 0
    while x > 0 or carry > 0 do
        local sum = carry + (digits[i] or 0) + (x % 10)
        digits[i] = sum % 10
        carry = flr(sum / 10)
        x = flr(x / 10)
        i = i + 1
    end
end

function big_int:to_string()
    local digits = self.digits
    local count = #digits

    if count > 0 then
        local s = ""
        for i=count, 1, -1 do
            s = s .. digits[i]
        end
    
        return s
    end

    return "0"
end

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

-- random number generator
xorwow = {
    new = function ()
        local function random_uint32()
            return bor(flr(rnd(256)),
                bor(shl(flr(rnd(256)), 8),
                bor(lshr(flr(rnd(256)), 8),
                bor(lshr(flr(rnd(256)), 16)))))
        end
        
        return xorwow.new_with_seed(random_uint32(), random_uint32(), random_uint32(), random_uint32())
    end,

    new_with_seed = function (a, b, c, d)
        local counter = 0

        return {
            a = a,
            b = b,
            c = c,
            d = d,

            next = function()
                local t = d

                d = c
                c = b
                b = a

                t = bxor(t, lshr(t, 2))
                t = bxor(t, shl(t, 1))
                t = bxor(t, bxor(a, shl(a, 4)))
                a = t

                counter = counter + 0x0005.87c5
                return t + counter
            end,

            random_byte = function(self, max_exclusive)
                -- Throw out values that wrap around to avoid bias
                while true do
                    local number = self:next()
                    local byte = band(0xff, flr(bxor(number, bxor(lshr(number, 8), bxor(shl(number, 8), bxor(shl(number, 16)))))))
                    if byte + (256 % max_exclusive) < 256 then
                        return byte % max_exclusive
                    end
                end
            end,
        }
    end,
}

local prng = xorwow.new()

-- communication
local comm_gpio_base = {
    client = 0,
    host = 64,
}

function comm_set_gpio(index, byteOrBytes)
    if type(byteOrBytes) == "number" then
        poke(0x5f80 + index, byteOrBytes)
    else
        for i = 1, #byteOrBytes, 1 do
            poke(0x5f80 + index + i - 1, byteOrBytes[i])
        end
    end
end

function comm_get_gpio(index, count)
    if count == nil then
        return peek(0x5f80 + index)
    else
        local bytes = {}
        for i = 1, count, 1 do
            bytes[i] = peek(0x5f80 + index + i - 1)
        end
        return bytes
    end
end

local comm_payload_read_id = 0
function comm_read_messages()
    local index = comm_gpio_base.host
    local pid = comm_get_gpio(index)
    local messages = {}
    if pid ~= comm_payload_read_id then
        -- todo: check to see if any messages were dropped/ignored?
        comm_payload_read_id = pid

        local count = comm_get_gpio(index + 1)
        index = index + 2
        for i = 1, count, 1 do
            local size = comm_get_gpio(index)
            local type = comm_get_gpio(index + 1)
            messages[#messages + 1] = {
                type = type,
                body = comm_get_gpio(index + 2, size),
            }

            index = index + 2 + size
        end
    end
    return messages
end

local comm_payload_send_id = 0
function comm_send_messages(messages)
    comm_payload_send_id = (comm_payload_send_id + 1) % 256
    local index = comm_gpio_base.client
    comm_set_gpio(index, comm_payload_send_id)
    comm_set_gpio(index + 1, #messages)
    index = index + 2
    for i = 1, #messages, 1 do
        comm_set_gpio(index, #messages[i].body)
        comm_set_gpio(index + 1, messages[i].type)
        comm_set_gpio(index + 2, messages[i].body)
        index = index + 2 + #messages[i]
    end
end

function comm_send_message(type, body)
    comm_send_messages({ { type = type, body = body } })
end

local comm_message_types = {
    initialize = 1,
    start_record = 2,
    start_replay = 3,
    record_frame = 4,
    end_record = 5,
    replay_frame = 6,
}

local comm_enabled = false
function comm_initialize()
    -- check to see if host is able to communicate
    comm_enabled = false
    comm_send_message(comm_message_types.initialize, {})
    local responses = comm_read_messages()
    if #responses > 0 and responses[1].type == comm_message_types.initialize then
        local body = responses[1].body
        if #body > 0 then
            comm_enabled = (body[1] ~= 0)
        end
    end
end

function comm_start_record(seeds)
    local body = {}
    for i = 1, #seeds, 1 do
        local seed = seeds[i]
        body[#body + 1] = band(0xff, shl(seed, 16))
        body[#body + 1] = band(0xff, shl(seed, 8))
        body[#body + 1] = band(0xff, seed)
        body[#body + 1] = band(0xff, lshr(seed, 8))
    end

    comm_send_message(comm_message_types.start_record, body)
end

function comm_record_frame(up_pressed, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed)
    local byte = 0
    if up_pressed then byte += 1 end
    if down_pressed then byte += 2 end
    if left_pressed then byte += 4 end
    if right_pressed then byte += 8 end
    if cw_pressed then byte += 16 end
    if ccw_pressed then byte += 32 end

    comm_send_message(comm_message_types.record_frame, {byte})
end

function comm_end_record(score)
    -- TODO: Enforce max score of 999999
    -- TODO: This is only for testing high scores!
    local digits = score.digits
    comm_send_message(comm_message_types.end_record, { digits[1], digits[2], digits[3], digits[4], digits[5], digits[6] })
end

function comm_start_replay()
    comm_send_message(comm_message_types.start_replay, {})

    local responses = comm_read_messages()
    if #responses > 0 then
        local bytes = responses[1].body
        local seeds = {}
        for i = 1, 4, 1 do
            local seed = 0
            seed = bor(seed, lshr(bytes[4 * (i - 1) + 1], 16))
            seed = bor(seed, lshr(bytes[4 * (i - 1) + 2], 8))
            seed = bor(seed, bytes[4 * (i - 1) + 3])
            seed = bor(seed, shl(bytes[4 * (i - 1) + 4], 8))
            seeds[i] = seed
        end
        
        prng = xorwow.new_with_seed(seeds[1], seeds[2], seeds[3], seeds[4])
        piece_advance()
        piece_advance()
    end
end

function comm_replay_frame()
    comm_send_message(comm_message_types.replay_frame, {})

    local responses = comm_read_messages()
    if #responses > 0 then
        local byte = responses[1].body[1]
        local up_pressed = (band(0x01, byte) ~= 0)
        local down_pressed = (band(0x02, byte) ~= 0)
        local left_pressed = (band(0x04, byte) ~= 0)
        local right_pressed = (band(0x08, byte) ~= 0)
        local cw_pressed = (band(0x10, byte) ~= 0)
        local ccw_pressed = (band(0x20, byte) ~= 0)

        return up_pressed, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed
    end

    return false, false, false, false, false, false
end

-- game state
score = big_int.create()

local board = {}
local lines = 0
local level = 0
local game_over = false
local game_paused = false
local game_started = false

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
local replay = false

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
    local points = 0
    if fast_drop then
        points = fast_drop_row - piece.j
    end

    if cleared >= 1 and cleared <= #cleared_to_score then
        points = points + cleared_to_score[cleared] * (level + 1)
        lines = lines + cleared
        if level < flr(lines / 10) then
            level = level + 1
        end
    end

    if points > 0 then
        score:add(points)
    end
end

function game_end()
    sfx(sounds.lose)
    game_paused = true
    game_over = true

    if comm_enabled and not replay then
        comm_end_record(score)
    end
end

function piece_hide()
    piece.index = 0
end

function piece_choose_next()
    piece.next_index = prng:random_byte(#pieces) + 1
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

function piece_move_down(left_pressed, right_pressed)
    if piece.index > 0 then
        if piece_try_move_down() then
            -- check for slide underneath
            if left_pressed and not piece_test_move(-1, 1) and piece_test_move(-1, 0) then
                piece_move_left()
            elseif right_pressed and not piece_test_move(1, 1) and piece_test_move(1, 0) then
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
    score:reset()
    lines = 0
    level = 0
    game_over = false
    game_paused = true
    game_started = false

    first_drop = true
    fast_drop = false
    fast_drop_row = 0
    fast_move = false

    timer_drop = 0
end

local initialized = false -- used to select record or playback
function _init()
    comm_initialize()
    if not comm_enabled then
        initialized = true
    end

    for j=1, board_height do
        board[j] = {}
    end

    reset()
end

function _update60()
    if initialized then
        -- Already initialized
        if game_paused then
            if not game_started and btn() ~= 0 then
                game_started = true
                game_paused = false
                music(0)
            end
        else
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
                    local up_pressed
                    local left_pressed
                    local right_pressed
                    local down_pressed
                    local cw_pressed
                    local ccw_pressed

                    if comm_enabled and replay then
                        up_pressed, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed = comm_replay_frame()
                    else
                        left_pressed = btn(buttons.left)
                        right_pressed = btn(buttons.right)
                        down_pressed = btn(buttons.down)
                        cw_pressed = btn(buttons.z)
                        ccw_pressed = btn(buttons.x)

                        -- TODO: Only for testing recording right now
                        comm_record_frame(false, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed)
                    end

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
                        piece_move_down(left_pressed, right_pressed)
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
    else
        -- Initialization
        if btnp(buttons.right) then
            // record
            replay = false
            comm_start_record({ prng.a, prng.b, prng.c, prng.d })
            initialized = true
        elseif btnp(buttons.left) then
            // replay
            replay = true
            comm_start_replay()
            initialized = true
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
__label__
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd66666666666666666666666666666666666666666666666666666666666666ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddd000dddddd0d0dddddddddddddddd0000dd0ddddddddddd0dddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd07770d00d070700ddddddddddddd077770070ddddddddd070ddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd0700d077007070700d0ddd00ddd5070007070d00ddd0000700dddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd07000700707070007070d0770d560777700700770d077707070ddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd077700777070707077070700706a0700070707007070000770dddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd07000700707070707007070070aa07000707070070700007070ddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddd070d0777707070707007007770aa0777700700770d0777070070dddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddd0ddd0000d0d0d0d0dd0dd0070aaa0000dd0dd00ddd000d0dd0ddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddddd0770994444465dddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddd560099944446a65ddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddd56aaa6990006aaa65dddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddd56aaaaa607770aa006500000dd00dddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddd56aaaaaa07000aa077007707700770ddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddd56999944407090007007070707070070dddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddd569994440700770077707070707770ddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddd56994440700070700707070707000ddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddd56944650777007777070707007770dddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddd56465dd000560000a0a0a00d000ddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddddd565ddddddd5699994444465dddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddd5ddddddddd56999444465ddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddddddddddddddddd569944465dddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddd5694465ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddddddddddddddddddd56465dddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddd565ddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006dddddddddddddddddddddddddddddddddddddddddd5dddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001111116dd66666666666666666666666dddddddddddd66666666666666666666666ddd
ddd60000000000000000000000000000000000000000000000000000001cccc16dd60000000000000000000006dddddddddddd60000000000000000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60700077707070777070006dddddddddddd60700077707700777007706ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60700070007070700070006dddddddddddd60700007007070700070006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60700077007070770070006dddddddddddd60700007007070770077706ddd
ddd60000000000000000000000000000000000000000000000000000001111116dd60700070007770700070006dddddddddddd60700007007070700000706ddd
ddd60000000000000000000000000000000000000000000000000000001111116dd60777077700700777077706dddddddddddd60777077707070777077006ddd
ddd60000000000000000000000000000000000000000000000000000001cccc16dd60000000000000000000006dddddddddddd60000000000000000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60000000007770000000006dddddddddddd60000000007770000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60000000007070000000006dddddddddddd60000000007070000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd60000000007070000000006dddddddddddd60000000007070000000006ddd
ddd60000000000000000000000000000000000000000000000000000001111116dd60000000007070000000006dddddddddddd60000000007070000000006ddd
ddd60000000000000000000000000000000000000000000000000000001111116dd60000000007770000000006dddddddddddd60000000007770000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cccc16dd60000000000000000000006dddddddddddd60000000000000000000006ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16dd66666666666666666666666dddddddddddd66666666666666666666666ddd
ddd60000000000000000000000000000000000000000000000000000001cddd16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001cddd16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001111116ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001111116ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001cccc16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001cddd16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001cddd16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001cddd16ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000001111116ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6666666666666666666666666666666ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6000000000000000000000000000006ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6000000770077007707770777000006ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6000007000700070707070700000006ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6000007770700070707700770000006ddddddddddddddddd
ddd60000000000000000000000000000000000000000000000000000000000006ddddddddddddddd6000000070700070707070700000006ddddddddddddddddd
ddd6111111000000000000000000aaaaa9aaaaa90000000000000000000000006ddddddddddddddd6000007700077077007070777000006ddddddddddddddddd
ddd61cccc1000000000000000000aaaa99aaaa990000000000000000000000006ddddddddddddddd6000000000000000000000000000006ddddddddddddddddd
ddd61cddd1000000000000000000aaa999aaa9990000000000000000000000006ddddddddddddddd6000000000770077707770000000006ddddddddddddddddd
ddd61cddd1000000000000000000aa4499aa44990000000000000000000000006ddddddddddddddd6000000000070000700070000000006ddddddddddddddddd
ddd61cddd1000000000000000000a44449a444490000000000000000000000006ddddddddddddddd6000000000070007700070000000006ddddddddddddddddd
ddd61111110000000000000000004444444444440000000000000000000000006ddddddddddddddd6000000000070000700070000000006ddddddddddddddddd
ddd6111111000000000000000000aaaaa9aaaaa90000000000000000000000006ddddddddddddddd6000000000777077700070000000006ddddddddddddddddd
ddd61cccc1000000000000000000aaaa99aaaa990000000000000000000000006ddddddddddddddd6000000000000000000000000000006ddddddddddddddddd
ddd61cddd1000000000000000000aaa999aaa9990000000000000000000000006ddddddddddddddd6666666666666666666666666666666ddddddddddddddddd
ddd61cddd1000000000000000000aa4499aa44990000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1000000000000000000a44449a444490000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61111110000000000000000004444444444440000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6111111000000000000000000dddddddddddd0000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cccc1000000000000000000dcccc1dcccc10000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1000000000000000000dcccc1dcccc10000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1000000000000000000dcccc1dcccc10000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1000000000000000000dcccc1dcccc10000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6111111000000000000000000d11111d111110000000000000000000000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6111111dddddddddddd000000dddddddddddd0000000000000000000000006ddddddddddddddddd6666666666666666666666666666dddddddddddddddddd
ddd61cccc1dcccc1dcccc1000000dcccc1dcccc10000000000000000000000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000000000000000000000006ddddddddddddddddd6000007700777070707770000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000000000000000000000006ddddddddddddddddd6000007070700070700700000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000000000000000000000006ddddddddddddddddd6000007070770007000700000006dddddddddddddddddd
ddd6111111d11111d11111000000d11111d111110000000000000000000000006ddddddddddddddddd6000007070700070700700000006dddddddddddddddddd
ddd6111111dddddddddddd000000dddddddddddd0000009999990000000000006ddddddddddddddddd6000007070777070700700000006dddddddddddddddddd
ddd61cccc1dcccc1dcccc1000000dcccc1dcccc10000009999990000000000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000009944990000000000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000009944990000000000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1000000dcccc1dcccc10000009222290000000000006ddddddddddddddddd60000000aaaaa9aaaaa900000006dddddddddddddddddd
ddd6111111d11111d11111000000d11111d111110000002222220000000000006ddddddddddddddddd60000000aaaa99aaaa9900000006dddddddddddddddddd
ddd6111111ddddddddddddcccccdddddddddddddaaaaaa9999999999990000006ddddddddddddddddd60000000aaa999aaa99900000006dddddddddddddddddd
ddd61cccc1dcccc1dcccc1ccccdddcccc1dcccc1aaaaaa9999999999990000006ddddddddddddddddd60000000aa4499aa449900000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1cccddddcccc1dcccc1aa99aa9944999944990000006ddddddddddddddddd60000000a44449a4444900000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1cc11dddcccc1dcccc1aa99aa9944999944990000006ddddddddddddddddd6000000044444444444400000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1c1111ddcccc1dcccc1a4444a9222299222290000006ddddddddddddddddd60000000aaaaa9aaaaa900000006dddddddddddddddddd
ddd6111111d11111d11111111111d11111d111114444442222222222220000006ddddddddddddddddd60000000aaaa99aaaa9900000006dddddddddddddddddd
ddd6111111ddddddddddddcccccdcccccdaaaaaaaaaaaa9999999999990000006ddddddddddddddddd60000000aaa999aaa99900000006dddddddddddddddddd
ddd61cccc1dcccc1dcccc1ccccddccccddaaaaaaaaaaaa9999999999990000006ddddddddddddddddd60000000aa4499aa449900000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1cccdddcccdddaa99aaaa99aa9944999944990000006ddddddddddddddddd60000000a44449a4444900000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1cc11ddcc11ddaa99aaaa99aa9944999944990000006ddddddddddddddddd6000000044444444444400000006dddddddddddddddddd
ddd61cddd1dcccc1dcccc1c1111dc1111da4444aa4444a9222299222290000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd6111111d11111d111111111111111114444444444442222222222220000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd6111111999999999999cccccdaaaaaaaaaaaacccccd9999999999990000006ddddddddddddddddd6000000000000000000000000006dddddddddddddddddd
ddd61cccc1999999999999ccccdda99994aaaaaaccccdd9999999999990000006ddddddddddddddddd6666666666666666666666666666dddddddddddddddddd
ddd61cddd1994499994499cccddda99994aa99aacccddd9944999944990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1994499994499cc11dda99994aa99aacc11dd9944999944990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd61cddd1922229922229c1111da99994a4444ac1111d9222299222290000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6111111222222222222111111a444444444441111112222222222220000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6999999999999aaaaaaaaaaaaaaaaaacccccdcccccdcccccd9999990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6999999999999a99994a99994a99994ccccddccccddccccdd9999990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6994499994499a99994a99994a99994cccdddcccdddcccddd9944990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6994499994499a99994a99994a99994cc11ddcc11ddcc11dd9944990000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6922229922229a99994a99994a99994c1111dc1111dc1111d9222290000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd6222222222222a44444a44444a444441111111111111111112222220000006ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddd66666666666666666666666666666666666666666666666666666666666666ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd

__sfx__
010500002135500305213500030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305003050030500305
010200002d34000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500000234500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005
010200001d3602136024360293601f3602336026360000001e3602236025360000001d3502135024350000001c3502035023350000001b3401f34022340000001a3301e3302133000000193201d3202032000000
0104000021362000022836200002213520000228352000022d3420000228342000022d3320000228332000022d3220000228322000022d312000022d312000020000200002000020000200002000000000000000
015a00000065500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605000050000500005
010c00001d53000000000001d530185300000019530000001b5300000000000000001953000000185300000016530000000000016535165300000019530000001d53022500000001d5301b530000001953000000
010c000018530000000000000000000000000019530000001b5300000000000000001d53000000000000000019530000000000000000165300000000000000001653000000000000000000000000000000000000
010c00001b530000001b5300000000000000001e530000002253000000000002253020530000001e530000001d530000000000000000000000000019530000001d53000000000001d5301b530000001953000000
010c000018530000000000000000185300000019530000001b5300000000000000001d53000000000000000019530000000000000000165300000000000000001653000000000000000000000000000000000000
010c000024120001002912000100291200010000100001002d120001002e120001002d120291202712024120221201610021120221202210024120251202e1002e1202912025120221201d120191201512011120
010c000016120001000510015100151200010011120001001d1202912018120001001b1202e1252d120001001d120001001e12000100211200010022100001002512024120221201e1201b120181201612011100
010c00001e12018100221201e120181001d1201b120161200010016120221202e1202512024120221201d120221201d1251d120221201d1251d12025120221202912025120221201d12019120001001d12022120
010c00002112000100001002412000100001002912000100291200010027120001002912000100241200010025120001000010000100241200010000100001002212000100001000010000100001000010000100
010c0000117200070000700007000c72000700007000070009720007000070000700057200070011720007000d7200070000700007000a7200070000700007000572000700007000070001720007000070000700
010c0000117200070000700007000c72000700007000070009720007000070000700057200070011720007000d7200070000700007000a720007000070000700057200070016720007000a720007000070000700
010c00000f7200070000700007000a7200070000700007000672000700007000070003720007000f720007000d7200070000700007000a7200070000700007000572000700007000070001720007000070000700
010c00001854000500155400050000500005001d540005001b540005001654015540005001d5402154024540225401d5401954016540115400d5400a5400554001540055400a5400d54011540165401954016540
010c0000115400d5400a5400d540115401854015540115400c540095400c54011540155401854015540115401954016540115400d54016540115400d540095400a54000000185400000019540000001854000000
010c0000125400000000000000000f5400a5400654003540065400000016540000001954000000185400000011540000000000000000115400d5400a54005540015400000011540000000f540000000d54000000
010c00000c540000000000000000115400c5400954005540005400000011540000001854000000000001554016540000000000000000165401854019540000001854016540115400a54000000000000000000000
010c0000115300c5300953005530115300c5300953005530115300c5300953005530115300c53009530055300d5300a53005530015300d5300a53005530015300d5300a53005530015300d5300a5300553001530
010c00000c54000000000000954015540000000c540000000c540000001554000000000000000000000000001154000000000001654011540000000c540000000000000000165401154016540115401654011540
010c00000f5300a53006530035300f5300a53006530035300f5300a53006530035300f5300a5300653003530115300d5300a53005530115300d5300a53005530115300d5300a53005530115300d5300a53005530
010c00001254000000000000f54016540000000f5400000000000000001654000000125400f540000000a5400d54000000000000a54016540000001154000000000000000019540000001654011540000000d540
010c00000f5300c53009530055300f5300c53009530055300f5300c53009530055300f5300c53009530055300d5300a53005530015300d5300a53005530015300d5300a53005530015300d5300a5300553001530
010c00000c53000000000000953015530000000c530000000c530000001553000000000000000000000000001153000000000001653011530000000c530000000000000000165301153016530115301653011530
010300001250012500125401254012540125400050000500005000050000500005000f5400f5400f5400f54011540115401154011540000000000000000000000f5400f5400f5400f54000000000000000000000
__music__
00 1b4e4544
01 060e4544
00 070f4344
00 08104344
00 090f4344
00 060e4544
00 070f4344
00 08104344
00 090f4344
00 0a0e4344
00 0b0f4344
00 0c104344
00 0d0f4344
00 110e4344
00 120f4344
00 13104344
00 140f4344
00 15164e44
00 15164f44
00 17185044
02 191a4f44

