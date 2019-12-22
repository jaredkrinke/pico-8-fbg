pico-8 cartridge // http://www.pico-8.com
version 18
__lua__
-- Falling Block Game
-- Block-stacking game with global high scores

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
    level_up = 6,
}

-- utilities
uint32 = {}
uint32_mt = {
    __index = uint32,

    __concat = function (a, b)
        if getmetatable(a) == uint32_mt then a = a:to_string() end
        if getmetatable(b) == uint32_mt then b = b:to_string() end
        return a .. b
    end,

    __eq = function (x, y)
        return x.value == y.value
    end,

    __lt = function (x, y)
        return x.value < y.value
    end,
}

local function uint32_number_to_value(n)
    return lshr(n, 16)
end

function uint32.create()
    local instance = { value = 0 }
    setmetatable(instance, uint32_mt)
    return instance
end

function uint32:get_raw()
    return self.value
end

function uint32:set_raw(x)
    if self.value ~= x then
        self.value = x
        self.formatted = false
    end
    return self
end

function uint32:set(a)
    return self:set_raw(a.value)
end

function uint32.create_raw(x)
    local instance = uint32.create()
    if instance.value ~= x then
        instance:set_raw(x)
    end
    return instance
end

function uint32.create_from_uint32(b)
    return uint32.create_raw(b.value)
end

function uint32.create_from_number(n)
    return uint32.create_raw(uint32_number_to_value(n))
end

function uint32.create_from_bytes(a, b, c, d)
    return uint32.create_raw(bor(lshr(a, 16), bor(lshr(b, 8), bor(c, bor(shl(d, 8))))))
end

function uint32:set_number(n)
    return self:set_raw(uint32_number_to_value(n))
end

function uint32:add_raw(y)
    self:set_raw(self.value + y)
    return self
end

function uint32:add(b)
    return self:add_raw(b.value)
end

function uint32:add_number(n)
    return self:add_raw(uint32_number_to_value(n))
end

function uint32:multiply_raw(y)
    local x = self.value
    if x < y then x, y = y, x end
    local acc = 0

    for i = y, 0x0000.0001, -0x0000.0001 do
        acc = acc + x
    end
    self:set_raw(acc)
    return self
end

function uint32:multiply(b)
    return self:multiply_raw(b.value)
end

function uint32:multiply_number(n)
    return self:multiply_raw(uint32_number_to_value(n))
end

local function decimal_digits_add_in_place(a, b)
    local carry = 0
    local i = 1
    local digits = max(#a, #b)
    while i <= digits or carry > 0 do
        local left = a[i]
        local right = b[i]
        if left == nil then left = 0 end
        if right == nil then right = 0 end
        local sum = left + right + carry
        a[i] = sum % 10
        carry = flr(sum / 10)
        i = i + 1
    end
end

local function decimal_digits_double(a)
    local result = {}
    for i = 1, #a, 1 do result[i] = a[i] end
    decimal_digits_add_in_place(result, a)
    return result
end

local uint32_binary_digits = { { 1 } }
function uint32:format_decimal()
    local result_digits = { 0 }
    local value = self.value

    -- find highest bit
    local max_index = 0
    local v = value
    while v ~= 0 do
        v = lshr(v, 1)
        max_index = max_index + 1
    end

    -- compute the value
    for i = 1, max_index, 1 do
        -- make sure decimal representation of this binary bit is cached
        local binary_digits = uint32_binary_digits[i]
        if binary_digits == nil then
            binary_digits = decimal_digits_double(uint32_binary_digits[i - 1])
            uint32_binary_digits[i] = binary_digits
        end

        -- find the bit
        local mask = 1
        if i <= 16 then
            mask = lshr(mask, 16 - (i - 1))
        elseif i > 17 then
            mask = shl(mask, (i - 1) - 16)
        end

        local bit = false
        if band(mask, value) ~= 0 then bit = true end

        -- add, if necessary
        if bit then
            decimal_digits_add_in_place(result_digits, binary_digits)
        end
    end

    -- concatenate the digits
    local str = ""
    for i = #result_digits, 1, -1 do
        str = str .. result_digits[i]
    end
    return str
end

function uint32:to_string(raw)
    if raw == true then
        return tostr(self.value, true)
    else
        -- cache format_decimal result
        if self.formatted ~= true then
            self.str = self:format_decimal()
            self.formatted = true
        end
        return self.str
    end
end

function uint32:to_bytes()
    local value = self.value
    return band(0xff, shl(value, 16)),
        band(0xff, shl(value, 8)),
        band(0xff, value),
        band(0xff, lshr(value, 8))
end

function number_to_bytes(value)
    return {
        band(0xff, shl(value, 16)),
        band(0xff, shl(value, 8)),
        band(0xff, value),
        band(0xff, lshr(value, 8)),
    }
end

function bytes_to_number(bytes)
    return bor(lshr(bytes[1], 16),
        bor(lshr(bytes[2], 8),
        bor(bytes[3],
        bor(shl(bytes[4], 8)))))
end

-- game data
local board_width = 10
local board_height = 20
local block_size = 6
local board_offset = 4

local cleared_to_score = { 40, 100, 300, 1200 }
local transition_period = 60
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

local prng = nil -- initialized later

-- communication library
local comm_gpio = {
    size = 0,
    base = 1,
}

local gpio_address = 0x5f80
function comm_gpio_write(index, byte)
    poke(gpio_address + index, byte)
end

function comm_gpio_read(index)
    return peek(gpio_address + index)
end

function comm_send(bytes)
    comm_gpio_write(comm_gpio.size, #bytes)
    local index = comm_gpio.base
    for i = 1, #bytes, 1 do
        comm_gpio_write(index, bytes[i])
        index = index + 1
    end
end

function comm_receive()
    local bytes = {}
    local size = comm_gpio_read(comm_gpio.size)
    local index = comm_gpio.base
    for i = 1, size, 1 do
        bytes[i] = comm_gpio_read(index)
        index = index + 1
    end
    return bytes
end

function comm_process(bytes)
    comm_send(bytes)
    return comm_receive()
end

-- cartdata
cartdata("jk_fallingblockgame")
local cartdata_indexes = {
    initials = 0,
    settings = 1,
    scores = 4, -- through 63
}
-- high scores
local game_modes = {
    -- infinite mode:
    endless = 1,

    -- finite modes:
    countdown = 2,
    cleanup = 3,
}

local high_scores_stores = {
    cart = 1,
    web = 2,
}
local high_scores = {
    {
        [game_modes.endless] = {},
        [game_modes.countdown] = {},
        [game_modes.cleanup] = {},
    },
    {
        [game_modes.endless] = {},
        [game_modes.countdown] = {},
        [game_modes.cleanup] = {},
    },
}

function high_scores_save()
    local index = cartdata_indexes.scores
    local scores = high_scores[high_scores_stores.cart]
    for i = 1, #scores, 1 do
        local store = scores[i]
        for j = 1, 10, 1 do
            local initials = 0
            local score = 0
            local entry = store[j]
            if entry ~= nil then
                initials = bytes_to_number({entry.initials[1], entry.initials[2], entry.initials[3], 0})
                score = entry.score:get_raw()
            end
            dset(index, initials)
            dset(index + 1, score)
            index = index + 2
        end
    end
end

function high_scores_load()
    local index = cartdata_indexes.scores
    local scores = high_scores[high_scores_stores.cart]
    for i = 1, #scores, 1 do
        local store = scores[i]
        for j = 1, 10, 1 do
            local initials = dget(index)
            if initials == 0 then
                store[j] = nil
            else
                local score = dget(index + 1)
                store[j] = {
                    initials = number_to_bytes(initials),
                    score = uint32.create_raw(score),
                }
            end
            index = index + 2
        end
    end
end

local function initials_copy(initials)
    local new_initials = {}
    for i = 1, #initials, 1 do new_initials[i] = initials[i] end
    return new_initials
end

local function score_copy(score)
    return uint32.create_from_uint32(score)
end

function high_scores_update(mode, initial_indexes, score)
    local store = high_scores[high_scores_stores.cart][mode]
    local added = false
    local previous = nil
    for i = 1, 10, 1 do
        local entry = store[i]
        if added then
            store[i] = previous
            previous = entry
        elseif entry == nil or entry.score < score then
            added = true
            previous = entry
            store[i] = {
                initials = initials_copy(initial_indexes),
                score = score_copy(score),
            }
        end
    end

    high_scores_save()
end

-- communication
local host_message_types = {
    initialize = 1,
    start_record = 2,
    start_replay = 3,
    record_frame = 4,
    end_record = 5,
    replay_frame = 6,
    load_scores = 7, -- potentially kick off asynchronous request
    check_scores = 8, -- check for result of asynchronous request
}

function host_send(type, body)
    local bytes = { type }
    if body ~= nil then
        for i = 1, #body, 1 do
            bytes[i + 1] = body[i]
        end
    end
    comm_send(bytes)
end

function host_process(type, body)
    host_send(type, body)
    local bytes = comm_receive()
    if #bytes >= 1 and bytes[1] == type then
        local response = {}
        for i = 2, #bytes, 1 do
            response[i - 1] = bytes[i]
        end
        return response
    end
end

local host_enabled = false
local host_replay_available = false

-- todo: consider invalidating cached web scores after a timer or after each round...
local load_states = {
    loading = 1,
    loaded = 2,
    failed = 3,
    unavailable = 4,
}
local host_score_load_states = {}

function host_initialize()
    -- check to see if host is able to communicate
    host_enabled = false
    local response = host_process(host_message_types.initialize)
    if #response >= 1 then host_enabled = (response[1] ~= 0) end
    if #response >= 2 then host_replay_available = (response[2] ~= 0) end
end

function host_start_record()
    local response = host_process(host_message_types.start_record, {
        game_mode,
        level_initial,
    })

    if host_enabled and #response == 16 then
        -- got seed from host
        local seeds = {}
        for i = 1, #response, 4 do
            seeds[#seeds + 1] = bytes_to_number({ response[i], response[i + 1], response[i + 2], response[i + 3] })
        end
        prng = xorwow.new_with_seed(seeds[1], seeds[2], seeds[3], seeds[4])
    else
        -- no host
        prng = xorwow.new()
    end
end

function host_record_frame(up_pressed, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed)
    local byte = 0
    if up_pressed then byte += 1 end
    if down_pressed then byte += 2 end
    if left_pressed then byte += 4 end
    if right_pressed then byte += 8 end
    if cw_pressed then byte += 16 end
    if ccw_pressed then byte += 32 end

    host_send(host_message_types.record_frame, { byte })
end

function host_end_record(score)
    local a, b, c, d = score:to_bytes()
    host_send(host_message_types.end_record, {
        a,
        b,
        c,
        d,
        player_initial_indexes[1],
        player_initial_indexes[2],
        player_initial_indexes[3],
    })

    -- sending the score will automatically start loading scores in the host
    host_score_load_states[game_mode] = load_states.loading
end

function host_start_replay()
    local response = host_process(host_message_types.start_replay)
    if #response >= 18 then
        local seeds = {}
        for i = 1, 4, 1 do
            local seed = 0
            seed = bor(seed, lshr(response[4 * (i - 1) + 1], 16))
            seed = bor(seed, lshr(response[4 * (i - 1) + 2], 8))
            seed = bor(seed, response[4 * (i - 1) + 3])
            seed = bor(seed, shl(response[4 * (i - 1) + 4], 8))
            seeds[i] = seed
        end
        
        prng = xorwow.new_with_seed(seeds[1], seeds[2], seeds[3], seeds[4])

        -- todo: this will change settings for the next launch but not update the ui...
        set_game_mode(response[17])
        level_initial = response[18]
    end
end

function host_replay_frame()
    local response = host_process(host_message_types.replay_frame)
    if #response >= 1 then
        local byte = response[1]
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

function host_load_scores(mode)
    if host_enabled then
        host_send(host_message_types.load_scores, { mode })
        host_score_load_states[mode] = load_states.loading
    else
        host_score_load_states[mode] = load_states.unavailable
    end
end

function host_check_scores(mode)
    if host_score_load_states[mode] == load_states.loading then
        local response = host_process(host_message_types.check_scores, { mode })
        if #response == 1 and response[1] == 0xff then
            host_score_load_states[mode] = load_states.failed
        elseif #response >= 7 then
            host_score_load_states[mode] = load_states.loaded

            local scores = high_scores[high_scores_stores.web][mode]
            for i = 1, 10, 1 do scores[i] = nil end

            local index = 0
            for i = 1, #response, 7 do
                index = index + 1
                scores[index] = {
                    initials = { response[i], response[i + 1], response[i + 2] },
                    score = uint32.create_from_bytes(response[i + 3], response[i + 4], response[i + 5], response[i + 6]),
                }
            end
        end
    end
end

-- overall state
local game_states = {
    initializing = 1,
    main_menu = 2,
    started = 3,
    scores = 4,
    first_run_menu = 5,
}

local game_state = game_states.initializing

-- game state
local board = {}
local lines = 0
local level = 0
local game_result = nil
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
local timer_end = 0

local piece = {
    index = 1,
    next_index = 1,
    rotation_index = 1,
    i = 0,
    j = 0,
}

-- game logic
local replay = false
local score = uint32.create()

local game_types = {
    infinite = 1,
    finite = 2,
}

local game_mode_to_type = {
    [game_modes.endless] = game_types.infinite,
    [game_modes.countdown] = game_types.finite,
    [game_modes.cleanup] = game_types.finite,
}

local game_type = game_types.infinite
game_mode = game_modes.endless

function board_reset()
    for j=1, board_height do
        for i=1, board_width do
            board[j][i] = 0
        end
    end
end

function board_add_garbage()
    for j=1, 12 do
        -- ensure row is not completely full
        local valid = false

        repeat
            for i=1, board_width do
                if prng:random_byte(100) < 45 then
                    board[j][i] = prng:random_byte(#pieces) + 1
                else
                    board[j][i] = 0
                    valid = true
                end
            end
        until valid
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

local uint32_zero = uint32.create()
local uint32_999999 = uint32.create_raw(0x000F.423F)
local points = uint32.create()
function game_score_update(cleared)
    points:set_raw(0)

    if cleared >= 1 and cleared <= #cleared_to_score then
        points:set_number(cleared_to_score[cleared])
        points:multiply_number(level + 1)

        if game_type == game_types.infinite then
            -- infinite games count up and advance levels
            lines = lines + cleared
            if level < flr(lines / 10) then
                level = level + 1
            end
        else
            -- finite games count down and end in a win or loss
            lines = max(0, lines - cleared)
        end
    end

    if fast_drop then
        points:add_number(fast_drop_row - piece.j)
    end

    if points > uint32_zero then
        score:add(points)

        -- Max score is 999999
        if score > uint32_999999 then
            score:set(uint32_999999)
        end
    end

    if game_type == game_types.finite and lines == 0 then
        game_end(true, true)
    end
end

function game_end(eligible_for_high_score, successful)
    if successful then
        sfx(sounds.quad)
    else
        sfx(sounds.lose)
    end

    game_paused = true
    game_result = successful

    if host_enabled and not replay and eligible_for_high_score then
        host_end_record(score)
    end

    if eligible_for_high_score then
        high_scores_update(game_mode, player_initial_indexes, score)
    end

    timer_transition = transition_period
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

            local previous_level = level
            local cleared = board_clean()
            game_score_update(cleared)

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

                if previous_level < level then
                    sfx(sounds.level_up)
                end
            else
                sfx(sounds.land)
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

function game_reset()
    board_reset()
    if game_mode == game_modes.cleanup then
        board_add_garbage()
    end

    piece.index = 0
    piece.next_index = 0

    piece_advance()
    score:set_raw(0)

    if game_type == game_types.infinite then
        lines = 0
    else
        lines = 25
    end

    level = level_initial
    game_result = nil
    game_paused = true

    input_last_left = false
    input_last_right = false
    input_last_down = false
    input_last_cw = false
    input_last_ccw = false

    first_drop = true
    fast_drop = false
    fast_drop_row = 0
    fast_move = false

    timer_drop = 0
    timer_transition = transition_period
end

-- menu
menu_item = {}
menu_item_mt = { __index = menu_item }

function menu_item.create(item)
    setmetatable(item, menu_item_mt)
    return item
end

function menu_item.create_choice(label, choices)
    local index = 1
    return menu_item.create({
        label = label,
        choices = choices,
        set_index = function (self, new_index)
            -- todo: persist across runs
            if new_index ~= index then
                index = new_index
                self.choices[index].callback()
                return true
            end
            return false
        end,
        handle_input = function (self)
            local handled = false
            if btnp(buttons.z) or btnp(buttons.left) or btnp(buttons.right) then
                handled = true
                local new_index = index
                local choices = self.choices
                if btnp(buttons.z) then
                    new_index = index % #choices + 1
                else
                    local offset = 1
                    if btnp(buttons.left) then offset = -1 end
                    new_index = min(#choices, max(1, new_index + offset))
                end

                self:set_index(new_index)
            end
            return handled
        end,
        draw = function (self, x, y, focused)
            menu_item.draw(self, x, y, focused)
            x = x + 4 * #self.label

            color(colors.dark_gray)
            if focused and index > 1 then
                print("<", x, y)
            end
            x = x + 5

            local choices = self.choices
            local choice_label = choices[index].label
            color(colors.white)
            if focused then color(colors.green) end
            print(choice_label, x, y)
            x = x + 4 * #choice_label + 1

            color(colors.dark_gray)
            if focused and index < #choices then
                print(">", x, y)
            end
        end,
    })
end

function menu_item:draw(x, y, focused)
    color(colors.white)
    if focused then color(colors.green) end
    print(self.label, x, y)
end

function menu_item:should_show()
    return true
end

function menu_item:handle_input()
    if btnp(buttons.z) then
        self:activate()
        return true
    end
    return false
end

local music_muted = false
level_initial = 0
function game_start()
    game_reset()
    game_paused = false
    game_state = game_states.started

    if not music_muted then
        -- reserve last 2 channels for music
        music(0, 0, 0xc)
    end
end

-- player initials
player_initial_indexes = { 1, 2, 3 }
local letters = "abcdefghijklmnopqrstuvwxyz"

function player_initials_save()
    local number =
        bor(lshr(player_initial_indexes[1], 16),
        bor(lshr(player_initial_indexes[2], 8),
        bor(player_initial_indexes[3])))

    dset(cartdata_indexes.initials, number)
end

function player_initials_load()
    local number = dget(cartdata_indexes.initials)
    if number ~= 0 then
        player_initial_indexes[1] = band(0xff, shl(number, 16))
        player_initial_indexes[2] = band(0xff, shl(number, 8))
        player_initial_indexes[3] = band(0xff, number)
        return true
    end
    return false
end

function initial_index_to_string(index)
    return sub(letters, index, index)
end

-- mode, level, etc.
local function create_level_choices()
    local choices = {}
    for i = 0, 9, 1 do
        choices[#choices + 1] = {
            label = "" .. i,
            callback = function () level_initial = i end,
        }
    end
    return choices
end

local choice_mode = menu_item.create_choice("mode:", {
    { label = "endless", callback = function () set_game_mode(game_modes.endless) end },
    { label = "countdown", callback = function () set_game_mode(game_modes.countdown) end },
    { label = "cleanup", callback = function () set_game_mode(game_modes.cleanup) end },
})

local choice_level = menu_item.create_choice("level:", create_level_choices())
local choice_music = menu_item.create_choice("music:", {
    { label = "on", callback = function () music_muted = false end },
    { label = "off", callback = function () music_muted = true end },
})

local settings = {
    choice_mode,
    choice_level,
    choice_music,
}

function settings_initialize()
    -- load previous values
    local x = dget(cartdata_indexes.settings)
    if x ~= 0 then
        local bytes = number_to_bytes(x)
        for i = 1, #settings, 1 do
            local value = bytes[i]
            local setting = settings[i]
            local choices = setting.choices
            if value >= 1 and value <= #choices then
                setting:set_index(value)
            end
        end
    end

    -- make settings persistent
    for i = 1, #settings, 1 do
        local choices = settings[i].choices
        for j = 1, #choices, 1 do
            local choice = choices[j]
            local callback_original = choice.callback
            choice.callback = function ()
                local bytes = number_to_bytes(dget(cartdata_indexes.settings))
                bytes[i] = j
                dset(cartdata_indexes.settings, bytes_to_number(bytes))
                callback_original()
            end
        end
    end
end

-- menus
function set_game_mode(new_mode)
    game_mode = new_mode
    game_type = game_mode_to_type[game_mode]
end

local choice_initials = menu_item.create({
    label = "initials:",
    initials = player_initial_indexes,
    index = 0,
    handle_input = function (self)
        local handled = false
        local editing = false
        local done = false
        if self.index > 0 then editing = true end
        if btnp(buttons.x) then
            handled = true
            done = true
        elseif btnp(buttons.z) or btnp(buttons.left) or btnp(buttons.right) then
            handled = true
            local offset = 1
            if btnp(buttons.left) then offset = -1 end
            self.index = (self.index + offset) % (1 + #self.initials)
            if self.index == 0 then done = true end
        elseif editing then
            if btnp(buttons.up) or btnp(buttons.down) then
                handled = true
                local offset = -1
                if btnp(buttons.down) then offset = 1 end
                self.initials[self.index] = (self.initials[self.index] + offset - 1) % #letters + 1
            end
        end

        if done then
            player_initials_save()
            self.index = 0
        end
        return handled
    end,
    draw = function (self, x, y, focused)
        color(colors.white)
        if focused and self.index <= 0 then color(colors.green) end
        print(self.label, x, y)

        for i = 1, #self.initials, 1 do
            local x2 = x + 4 * #self.label + 4 * i
            local letter_index = self.initials[i]

            if self.index == i then
                print("^", x2, y + 6, colors.light_gray)
                color(colors.green)
            else
                color(colors.white)
            end

            print(initial_index_to_string(letter_index), x2, y)
        end
    end,
})

function show_high_scores(mode, score)
    game_state = game_states.scores
    menu_scores.index = 1
    if mode ~= nil then
        menu_scores.index = 2
        menu_scores_choice:set_index(mode)
    end

    menu_high_scores_highlight_mode = mode
    menu_high_scores_highlight_score = score
end

local menu_main = {
    menu_item.create({
        label = "start game",
        activate = function ()
            replay = false
            host_start_record() -- note: this will initialize prng
            game_start()
        end,
    }),
    choice_mode,
    choice_level,
    choice_initials,
    choice_music,
    menu_item.create({
        label = "view high scores",
        activate = function ()
            show_high_scores()
        end,
    }),
    -- todo: re-enable, if desired
    -- menu_item.create({
    --     label = "watch replay",
    --     should_show = function () return host_enabled and host_replay_available end,
    --     activate = function ()
    --         replay = true
    --         host_start_replay() -- note: this will initialize prng
    --         game_start()
    --     end,
    -- }),
}
menu_main.index = 1

menu_first_run = {
    menu_item.create({
        label = "enter your initials",
        activate = function () menu_first_run.index = 2 end,
    }),
    choice_initials,
    menu_item.create({
        label = "done",
        activate = function ()
            game_state = game_states.main_menu
        end,
    }),
}
menu_first_run.index = 2

local menu_scores_mode = game_modes.endless
menu_scores_choice = menu_item.create_choice("mode:", {
    { label = "endless", callback = function () menu_scores_mode = game_modes.endless end },
    { label = "countdown", callback = function () menu_scores_mode = game_modes.countdown end },
    { label = "cleanup", callback = function () menu_scores_mode = game_modes.cleanup end },
})

menu_high_scores_highlight_mode = nil
menu_high_scores_highlight_score = nil
menu_scores = {
    menu_scores_choice,
    menu_item.create({
        label = "done",
        activate = function ()
            game_state = game_states.main_menu
        end,
    }),
}
menu_scores.index = 2

function _init()
    local initials_set = player_initials_load()
    settings_initialize()

    host_initialize()
    high_scores_load()

    if initials_set then
        game_state = game_states.main_menu
    else
        game_state = game_states.first_run_menu
    end

    for j=1, board_height do
        board[j] = {}
    end
end

function update_menu(menu_items)
    local menu_item = menu_items[menu_items.index]
    local handled = menu_item:handle_input()

    if not handled and (btnp(buttons.up) or btnp(buttons.down)) then
        handled = true
        local offset = -1
        if btnp(buttons.down) then offset = 1 end

        -- find next menu item
        local new_menu_item_index = menu_items.index
        while true do
            new_menu_item_index = (new_menu_item_index + offset - 1) % #menu_items + 1
            if new_menu_item_index >= 1 and new_menu_item_index <= #menu_items then
                if menu_items[new_menu_item_index]:should_show() then
                    menu_items.index = new_menu_item_index
                    break
                end
            else
                break
            end
        end
    end

    if handled then
        sfx(sounds.move)
    end
end

local update_handlers = {
    [game_states.main_menu] = function () update_menu(menu_main) end,

    [game_states.started] = function ()
        if piece.index == 0 and timer_next_piece > 0 then
            timer_next_piece = timer_next_piece - 1
        else
            if piece.index == 0 then
                board_expunge_rows()
                piece_advance()
                if piece.index > 0 and not piece_validate() then
                    game_end(game_type == game_types.infinite, false)
                end
            end

            if timer_transition > 0 then
                timer_transition = timer_transition - 1
            end

            if timer_transition == 0 then
                -- game may be paused due to game end
                if game_paused then
                    if game_result ~= nil then
                        if btnp(buttons.z) or btnp(buttons.x) then
                            music(-1)
                            show_high_scores(game_mode, score)
                        end
                    end
                else
                    -- input
                    local up_pressed
                    local left_pressed
                    local right_pressed
                    local down_pressed
                    local cw_pressed
                    local ccw_pressed
    
                    if host_enabled and replay then
                        up_pressed, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed = host_replay_frame()
                    else
                        left_pressed = btn(buttons.left)
                        right_pressed = btn(buttons.right)
                        down_pressed = btn(buttons.down)
                        cw_pressed = btn(buttons.z)
                        ccw_pressed = btn(buttons.x)
    
                        host_record_frame(false, down_pressed, left_pressed, right_pressed, cw_pressed, ccw_pressed)
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
    end,

    [game_states.scores] = function ()
        update_menu(menu_scores)

        local load_state = host_score_load_states[menu_scores_mode]
        if load_state == nil then
            host_load_scores(menu_scores_mode)
        elseif load_state == load_states.loading then
            host_check_scores(menu_scores_mode)
        end
    end,

    [game_states.first_run_menu] = function () update_menu(menu_first_run) end,
}

function _update60()
    update_handlers[game_state]()
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
    { colors.white, colors.light_gray, colors.dark_gray },
    { colors.green, colors.dark_green, colors.dark_blue },
    { colors.pink, colors.red, colors.dark_purple },
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

function draw_clear()
    cls(colors.dark_green)
end

function draw_title(x, y)
    palt(colors.black, false)
    spr(sprites.title, x, y, 8, 4)
    palt()
end

function draw_title_and_box(x, y)
    draw_clear()
    draw_title(32, 0)

    local x, y = 19, 38
    draw_box(x - 16, y - 8, 124, 124)

    return x, y
end

function draw_menu_items(menu_items, x, y, bias)
    if bias == nil then bias = 0 end
    for i = 1, #menu_items, 1 do
        local menu_item = menu_items[i]
        if menu_item:should_show() then
            local focused = i == menu_items.index
            if focused then
                print(">", x - 8, y, colors.light_gray)
                color(colors.white)
            end
            menu_item:draw(x, y, focused);
            y = y + 9 + bias
        end
    end
end

local function draw_menu(menu_items)
    return function ()
        local x, y = draw_title_and_box()
        draw_menu_items(menu_items, x, y)
        print("(use arrow keys, z, x)", 20, 116, colors.white)
    end
end

local draw_handlers = {
    [game_states.main_menu] = draw_menu(menu_main),

    [game_states.started] = function ()
        draw_clear()
        draw_title(64, 0)

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
        draw_box_number(128 - board_offset - 4 * 5, 32 + board_offset + 6, "lines", lines, 3)
        draw_box_number(96 - 7 * 2, 32 + board_offset + 5 * 6, "score", score, 7)

        if game_result ~= nil then
            local message = "game over!"
            if game_result == true then message = "you win!" end

            rectfill(32 - 5 * 4, 64 - 3, 32 + 5 * 4, 64 + 3, colors.black)
            print(message, 32 - #message * 2 + 1, 64 - 2, colors.white)
        end
    end,

    [game_states.scores] = function ()
        local x, y = draw_title_and_box()
        color(colors.white)
        print("high scores", 42, y - 6)
        line(x, y + 1, 127 - (x + 1), y + 1)
        draw_menu_items(menu_scores, x, 111, -2)

        y = y + 3
        color(colors.white)
        print("local", x + 20 - 10, y)
        print("global", x + 49 + 20 - 12, y)
        y = y + 7

        local highlighted = { false, false }
        for i = 1, 10, 1 do
            local sx = x
            for j = 1, #high_scores, 1 do
                local entry = high_scores[j][menu_scores_mode][i]
                if entry ~= nil then
                    local score = entry.score:to_string()
                    local dx = 0
                    local initials = entry.initials

                    if not highlighted[j]
                        and menu_scores_mode == menu_high_scores_highlight_mode
                        and entry.initials[1] == player_initial_indexes[1]
                        and entry.initials[2] == player_initial_indexes[2]
                        and entry.initials[3] == player_initial_indexes[3]
                        and entry.score == menu_high_scores_highlight_score
                    then
                        color(colors.green)
                        highlighted[j] = true
                    else
                        color(colors.light_gray)
                    end

                    for k = 1, #initials, 1 do
                        print(initial_index_to_string(initials[k]), sx + dx, y)
                        dx = dx + 4
                    end
                    print(score, sx + 40 - 4 * #score, y)
                end
                sx = sx + 49
            end
            y = y + 6
        end
    end,

    [game_states.first_run_menu] = draw_menu(menu_first_run),
}

function _draw()
    draw_handlers[game_state]()

    if debug and debug_message ~= nil then
        print(debug_message, 0, 122, colors.white)
    end
end
__gfx__
666666008888880055555500eeeeee007777770088888200bbbbb600000000003333333333333333333333333333333333333333333333333333333333333333
6bbbb300888888005bbbb500e88882007777770088882200bbbb6600000000003333333333333333333333333333333333333333333333333333333333333333
6bbbb300888888005b333500e88882007766770088822200bbb66600000000003333333333333333333333333333333333333333333333333333333333333333
6bbbb300888888005b333500e88882007766770088112200bb336600000000003333333333333333333333333333333333333333333333333333333333333333
6bbbb300822228005b333500e88882007555570081111200b3333600000000003333333000333333030333333333333333300003303333333333303333333333
633333002222220055555500e2222200555555001111110033333300000000003333330777030030707003333333333333077770070333333333070333333333
00000000000000000000000000000000000000000000000000000000000000003333330700d07700707070030333003335070007070300333000070033333333
00000000000000000000000000000000000000000000000000000000000000003333330700070070707000707030770356077770070077030777070703333333
00000000000000000000000000000000000000000000000000000000000000003333330777007770707070770707007068070007070700707000077033333333
00000000000000000000000000000000000000000000000000000000000000003333330700070070707070700707007088070007070700707000070703333333
00000000000000000000000000000000000000000000000000000000000000003333330703077770707070700700777088077770070077030777070070333333
00000000000000000000000000000000000000000000000000000000000000003333333033300003030303033033007088800003303300333000303303333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333330770221111165333333333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333356002221111686533333333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333568886220006888653333333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333335688888607770880065000003300333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333356888888070008807700770770077033333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333562222111070200070070707070700703333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333356222111070077007770707070777033333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333335622111070007070070707070700033333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333562116507770077770707070077703333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333356165330005600002010100d00033333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333335653333333562222111116533333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333533333333356222111165333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333335622111653333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333562116533333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333356165333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333335653333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333333533333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333333333333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333333333333333333333333333
00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333333333333333333333333333
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
01040000343553c0053c0053030530355343053000534355303053000537305303553430530005373553000534305343553730530005373550000500005343550000500005373550000500005343553730534305
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010e00001f5401f5451f5451e5401f5401f5451f5401f5401c5401c5401a5401a54018540185401c5401c5401a5401a5451a545195401a5401a5451a5401a540175401754015540155401354013540175401a540
010e00001554015545155401a5401354013545135401a5401254012545125401a5401554015545155401a5401754017545175401a5401354013545135401a54015540155451354013540155401a5401c5401e540
010e00001554015545155401a5401354013545135401a5401254012545125401a5401554015545155401a5401754017545175401a5401554015545155401a5401354013540105401054013540135400000000000
010e00001a5401a5451a540195401a5401a540185401854017540175401754017540105401054010540105401554015545155401454015540155401354013540125401254012540125400b5400b5400b5400b540
010e00001054010545105400e5401254012545125401054013540135451354012540145401454514540125401554017540195401a5401c5401b5401c5401d5401e5401e5451e5401a54012540125401254012545
010e00001054010545105400e5401254012545125401054013540135451354012540145401454514540125401554015545155401354017540175451754015540195401954519540175401a540000002654026540
010e000027540275401c5401b5401c540000001c5401c5401c5401c5401d5401d5401d5401d540265402654027540275401c5401b5401c540000001c5401c5401c5401c5401d5401d5401d5401d5402654026540
000e000027540275401c5001b5001c50000000265402654027540275401d5001d5001d5001d500265402654027540275402654026540275402754026540265402754027540265402654027540275402654026540
010e000007020070200e0200e02007020070200e0200e02004020040200b0200b02004020040200b0200b02002020020200902009020020200202009020090200b0200b02006020060200b0200b0200602006020
010e0000090201502009020090200702007020070200702006020060200602006020090200902009020090200b0200b0200b0200b020070200702007020070200902009020070200702006020060200402004020
010e0000090200902009020090200702007020070200702006020060200602006020090200902009020090200b0200b0200b0200b020090200902009020090200702007020040200402007020070200000000000
010e000009020090200202002020090200902002020020200b0200b02004020040200b0200b02004020040200c0200c02006020060200c0200c02006020060200e0200e02007020070200e0200e0200702007020
010e00001302013020130201302012020120201202012020100201002010020100200e0200e0200e0200e0200d0200d0200d0200d0200b0200b0200b0200b0200902009020090200902009020090200902009025
010e00000f0200f0200f0200f020000000000000000000000f0200f0200f0200f0200e0200e0200e0200e0200f0200f0200f0200f020000000000000000000000f0200f0200f0200f0200e0200e0200e0200e025
010e00000e0200e02012020120200e0200e02012020120200b0200b0200e0200e0200b0200b0200e0200e02007020070200b0200b02007020070200b0200b0200402004020070200702004020040200702007025
__music__
01 41421810
00 41421911
00 41421810
00 41421a12
00 41421b13
00 41421c14
00 41421b13
00 41421c15
00 41421d16
02 41421e17

