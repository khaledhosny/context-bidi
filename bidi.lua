bidi            = bidi or { }

bidi.module     = {
    name        = "bidi",
    version     = 0.002,
    date        = "2010/12/15",
    description = "Unicode Bidirectional Algorithm implementation for LuaTeX",
    author      = "Khaled Hosny",
    copyright   = "Khaled Hosny",
    license     = "CC0",
}

if not modules then modules = { } end modules ['bidi'] = bidi.module

--[[
  This code started as a line for line translation of Arabeyes' minibidi.c from
  C to lua, excluding parts that of no use to us like shaping.

  The C code is Copyright (c) 2004 Ahmad Khalifa, and is distributed under the
  MIT Licence. The full license text:
    http://svn.arabeyes.org/viewvc/projects/adawat/minibidi/LICENCE

  We basically translate node list into an equivalent textual representation
  (glyph nodes are converted to their characters, glue to spaces and the rest
  to a neutral Unicode object character, we might make it smarter later), then
  the text is fed to a function that resolves its embedding levels, that is then
  translated into insertion of begin/enddir nodes into the original node list.
--]]

local get_type = bidi.get_direction
local get_mirr = bidi.get_mirror
local set_mirr = bidi.set_mirror

-- see http://www.unicode.org/versions/corrigendum6.html
for i in next, { 0x2018, 0x201C, 0x301D } do
    set_mirr(i, i+1)
end
for i in next, { 0x2019, 0x201D, 0x301E } do
    set_mirr(i, i-1)
end

local MAX_STACK = 60

local function odd(x)
    return x%2 == 1 and true or false
end

local function least_greater_odd(x)
    return odd(x) and x+2 or x+1
end

local function least_greater_even(x)
    return odd(x) and x+1 or x+2
end

local function find_run_limit(line, run_start, limit, run_type)
    local run_limit
    i = run_start
    while line[i].type == run_type do
        run_limit = i
        i = i + 1
    end
    return run_limit
end

local function get_base_level(line)
    --[[
    Rule (P2), (P3)
    P2. In each paragraph, find the first character of type L, AL, or R.
    P3. If a character is found in P2 and it is of type AL or R, then set
    the paragraph embedding level to one; otherwise, set it to zero.
    --]]
    for _,c in next, line do
        if c.type == "r" or c.type == "al" then
            return 1
        elseif c.type == "l" then
            return 0
        end
    end
    return 0
end

local function resolve_explicit(line, base_level)
    -- Rules (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)

    --[[
    to be checked:
    X1. Begin by setting the current embedding level to the paragraph
        embedding level. Set the directional override status to neutral.
    X8. All explicit directional embeddings and overrides are completely
    terminated at the end of each paragraph. Paragraph separators are not
    included in the embedding. (Useless here) NOT IMPLEMENTED
    X9. Remove all RLE, LRE, RLO, LRO, PDF, and BN codes.
    Here, they're converted to BN.
    --]]

    local curr_level    = base_level
    local curr_override =  "on"
    local stack         = { }

    for _,c in next, line do
        -- X2
        if c.type == "rle" then
            if #stack <= MAX_STACK then
                table.insert  (stack, {curr_level, curr_override})
                curr_level    = least_greater_odd(curr_level)
                curr_override =  "on"
                c.level       = curr_level
                c.type        = "bn"
            end
        -- X3
        elseif c.type == "lre" then
            if #stack < MAX_STACK then
                table.insert  (stack, {curr_level, curr_override})
                curr_level    = least_greater_even(curr_level)
                curr_override =  "on"
                c.level       = curr_level
                c.type        = "bn"
            end
        -- X4
        elseif c.type == "rlo" then
            if #stack <= MAX_STACK then
                table.insert  (stack, {curr_level, curr_override})
                curr_level    = least_greater_odd(curr_level)
                curr_override = "r"
                c.level       = curr_level
                c.type        = "bn"
            end
        -- X5
        elseif c.type == "lro" then
            if #stack < MAX_STACK then
                table.insert  (stack, {curr_level, curr_override})
                curr_level    = least_greater_even(curr_level)
                curr_override = "l"
                c.level       = curr_level
                c.type        = "bn"
            end
        -- X7
        elseif c.type == "pdf" then
            if #stack > 0 then
                curr_level, curr_override = unpack(table.remove(stack))
                c.level = curr_level
                c.type  = "bn"
            end
        -- X6
        else
            c.level = curr_level
            if curr_override ~= "on" then
                c.type  = curr_override
            end
        end
    end
end

local function resolve_weak(line, base_level, start, limit, sor, eor)
    -- W1
    for i = start, limit do
        local c = line[i]
        if c.type == "nsm" then
            if i == start then
                c.type = sor
            else
                c.type = line[i-1].type
            end
        end
    end

    -- W2
    for i = start, limit do
        local c = line[i]
        if c.type == "en" then
            for j = i - 1, start, -1 do
                local bc = line[j]
                if bc.type == "al" then
                    c.type = "an"
                    break
                elseif bc.type == "r" or bc.type == "l" then
                    break
                end
            end
        end
    end

    -- W3
    for i = start, limit do
        local c = line[i]
        if c.type == "al" then
            c.type = "r"
        end
    end

    -- W4
    for i = start, limit do
        local c, pc, nc = line[i], line[i-1], line[i+1]
        if c.type == "es" then
            if (pc and pc.type == "en") and (nc and nc.type == "en") then
                c.type = "en"
            end
        elseif c.type == "cs" then
            if (pc and pc.type == "en") and (nc and nc.type == "en") then
                c.type = "en"
            elseif (pc and pc.type == "an") and (nc and nc.type == "an") then
                c.type = "an"
            end
        end
    end

    -- W5
    local i = start
    while i <= limit do
        local c, pc, nc = line[i], line[i-1], line[i+1]
        if c.type == "et" then
            local et_start = i
            local et_limit = find_run_limit(line, et_start, limit, "et")
            local t = (et_start == start and sor) or line[et_start-1].type
            if t ~= "en"then
                t = (et_limit == limit and eor) or line[et_limit+1].type
            end
            if t == "en" then
                for j = et_start, et_limit do
                    line[j].type = "en"
                end
            end
            i = et_limit
        end
        i = i + 1
    end

    -- W6
    for i = start, limit do
        local c = line[i]
        if c.type == "es" or c.type == "et" or c.type == "cs" then
            c.type = "on"
        end
    end

    -- W7
    for i = start, limit do
        local c = line[i]
        if c.type == "en" then
            for j = i - 1, start, -1 do
                if line[j].type == "l" then
                    c.type = "l"
                    break
                elseif line[j].type == "r" then
                    break
                end
            end
        end
    end
end

local function resolve_neutral(line, base_level, start, limit, sor, eor)
    --[[
    Rule (N1)
    N1. A sequence of neutrals takes the direction of the surrounding
    strong text if the text on both sides has the same direction. European
    and Arabic numbers are treated as though they were R.
    --]]
    for i = start, limit do
        local pre_dir
        local post_dir
        if line[i].type == "on" and line[i-1] and line[i+1] then
            if line[i-1].type == "r" or line[i-1].type == "en" or line[i-1].type == "an" then
                pre_dir = "r"
            elseif line[i-1].type == "l" then
                pre_dir = "l"
            end
            for j = i + 1, limit do
                if line[j].type == "r" or line[j].type == "en" or line[j].type == "an" then
                    post_dir = "r"
                    break
                elseif line[j].type == "l" then
                    post_dir = "l"
                    break
                end
            end
            if pre_dir and post_dir and (pre_dir == post_dir) then
                line[i].type = post_dir
            end
        end
    end

    --[[
    Rule (N2)
    N2. Any remaining neutrals take the embedding direction.
    --]]
    for i = start, limit do
        c = line[i]
        if c.type == "on" then
            if odd(c.level) then
                c.type = "r"
            else
                c.type = "l"
            end
        end
    end
end

local function resolve_implicit(line, base_level, start, limit, sor, eor)
    --[[
    Rule (I1)
    I1. For all characters with an even (left-to-right) embedding
    direction, those of type R go up one level and those of type AN or
    EN go up two levels.
    --]]
    for i = start, limit do
        c = line[i]
        if not odd(c.level) then
            if c.type == "r" then
                c.level = c.level + 1
            elseif c.type == "an" or c.type == "en" then
                c.level = c.level + 2
            end
        end
    end

    --[[
    Rule (I2)
    I2. For all characters with an odd (right-to-left) embedding direction,
    those of type L, EN or AN go up one level.
    --]]
    for i = start, limit do
        c = line[i]
        if odd(c.level) then
            if c.type == "l" or c.type == "en" or c.type == "an" then
                c.level = c.level + 1
            end
        end
    end
end

local function resolve_levels(line, base_level)
    -- Rules X1 to X9
    resolve_explicit(line, base_level)

    -- X10
    local start = 1
    while start < #line do
        local level = line[start].level

        local limit = start + 1
        while limit < #line and line[limit].level == level do
            limit = limit + 1
        end

        local prev_level = (start == 1 and base_level) or line[start-1].level
        local next_level = (limit == #line and base_level) or line[limit+1].level
        local sor = odd(math.max(level, prev_level)) and "r" or "l"
        local eor = odd(math.max(level, next_level)) and "r" or "l"


        -- Rules W1 to W7
        resolve_weak(line, base_level, start, limit, sor, eor)

        -- Rules N1 and N2
        resolve_neutral(line, base_level, start, limit, sor, eor)

        -- Rules I1 and I2
        resolve_implicit(line, base_level, start, limit, sor, eor)

        start = limit
    end

    --[[
    Rule (L1)
    L1. On each line, reset the embedding level of the following characters
    to the paragraph embedding level:
              (1)segment separators, (2)paragraph separators,
              (3)any sequence of whitespace characters preceding
              a segment separator or paragraph separator, NOT IMPLEMENTED
              (4)and any sequence of white space characters
              at the end of the line. NOT IMPLEMENTED
    The types of characters used here are the original types, not those
    modified by the previous phase.
    --]]
    for _,c in next, line do
        if c.orig_type == "s" or c.orig_type == "b" then
            c.level = base_level
        end
    end

    --[[
    Rule (L3)
    L3. Combining marks applied to a right-to-left base character will at
    this point precede their base character. If the rendering engine
    expects them to follow the base characters in the final display
    process, then the ordering of the marks and the base character must
    be reversed.
        Combining marks are reordered to the right of each character on an
        odd level.
    --]]

    return line
end

local glyph   = node.id("glyph")
local glue    = node.id("glue")
local hlist   = node.id("hlist")
local vlist   = node.id("vlist")

local function node_to_table(head)
    --[[
    Takes a node list and returns its textual representation
    --]]

    local whatsit = node.id("whatsit")
    local dir     = node.subtype("dir")

    local line = {}
    for n in node.traverse(head) do
        local c
        if n.id == glyph then
            c = n.char
        elseif n.id == glue then
            c = 0x0020 -- space
        elseif n.id == whatsit and n.subtype == dir then
            -- XXX handle all supported directions
            if n.dir == "+TLT" then
                c = 0x202D -- lro
            elseif n.dir == "+TRT" then
                c = 0x202E -- rlo
            elseif n.dir == "-TLT" or n.dir == "-TRT" then
                c = 0x202C -- pdf
            end
        else
            c = 0xFFFC -- object replacement character
        end
        line[#line+1] = { char = c, type = get_type(c), orig_type = get_type(c), level = 0 }
    end

    return line
end

local function insert_dir_points(line)
    --[[
    Takes a line with resolved embedding levels and inserts begin/enddir marks
    as required.
    --]]

    local max_level = 0

    for _,c in next, line do
        if c.level > max_level then
            max_level = c.level
        end
    end

    for level=max_level,0,-1 do
        for i=#line,1,-1 do
            if line[i].level >= level then
                local seq_end   = i
                local seq_begin
                local j = i
                while j >= 1 and line[j].level >= level do
                    seq_begin = j
                    j = j - 1
                end
                local dir
                if odd(level) then
                    dir = "TRT"
                else
                    dir = "TLT"
                end
                if not line[seq_begin].bdir then
                    line[seq_begin].bdir = "+"..dir
                end
                if not line[seq_end].edir and (not line[seq_end+1] or line[seq_end+1].level < level) then
                    line[seq_end].edir = "-"..dir
                end
            end
        end
    end

    return line
end

local function do_bidi(head, group)
    local base_level
    local line = node_to_table(head)

    if group == "" then
        base_level = get_base_level(line)
    else
        if tex.pardir == "TRT" then
            base_level = 1
        else
            base_level =0
        end
    end

    line = resolve_levels(line, base_level)
    line = insert_dir_points(line)

    return line
end

local function new_dir_node(dir)
    local n = node.new("whatsit","dir")
    n.dir = dir
    return n
end

local function process(head, group)
    local line

    line = do_bidi(head, group)
    assert(#line == node.length(head))

    if group == "fin_row" then
        -- workaround for crash with \halign
        -- see http://tug.org/pipermail/luatex/2011-July/003107.html
        return head
    end

    local i = 1
    local n = head
    while n do
        if n.id == hlist or n.id == vlist then
            n.list = process(n.list)
        else
            if n.id == glyph then
                assert(line[i].char == n.char)
                local v = line[i].level
                if v and odd(v) then
                    local mirror = get_mirr(n.char)
                    if mirror then
                        n.char = mirror
                    end
                end
            end

            local bdir = line[i].bdir
            local edir = line[i].edir

            if bdir then
                head = node.insert_before(head, n, new_dir_node(bdir))
            end

            if edir then
                head, n = node.insert_after(head, n, new_dir_node(edir))
            end
        end

        i = i + 1
        n = n.next
    end

    return head
end

bidi.process = process
