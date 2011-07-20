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

    local current_embedding = base_level
    local current_overrid   = "on"
    local level_stack       = { }
    local override_stack    = { }
    local stack_top         = 0

    for _,c in next, line do
        local current_type = c.type
        -- X2
        if current_type == "rle" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_odd(current_embedding)
                current_overrid           = "on"
                c.level                   = current_embedding
                c.type                    = "bn"
            end
        -- X3
        elseif current_type == "lre" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_even(current_embedding)
                current_overrid           = "on"
                c.level                   = current_embedding
                c.type                    = "bn"
            end
        -- X4
        elseif current_type == "rlo" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_odd(current_embedding)
                current_overrid           = "r"
                c.level                   = current_embedding
                c.type                    = "bn"
            end
        -- X5
        elseif current_type == "lro" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_even(current_embedding)
                current_overrid           = "l"
                c.level                   = current_embedding
                c.type                    = "bn"
            end
        -- X7
        elseif current_type == "pdf" then
            if stack_top > 0 then
                current_embedding = level_stack[stack_top-1]
                current_overrid   = override_stack[stack_top-1]
                stack_top         = stack_top - 1
                c.level           = current_embedding
                c.type            = "bn"
            end
        -- X6
        else
            c.level = current_embedding
            if current_overrid ~= "on" then
                current_type = current_overrid
            end
            c.type  = current_type
        end
    end
end

local function resolve_levels(line, base_level)
    -- Rules (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)
    resolve_explicit(line, base_level)

    for i,c in next, line do
        if c.type == "nsm" then
            if i == 1 then
                c.type = base_level
            else
                c.type = line[i-1].type
            end
        end
    end

    --[[
    Rule (W2)
    W2. Search backwards from each instance of a European number until the
    first strong type (R, L, AL, or sor) is found.  If an AL is found,
    change the type of the European number to Arabic number.
    --]]
    for i in next, line do
        if line[i].type == "en" then
            for j=i,1,-1 do
                if line[j].type == "al" then
                    line[i].type = "an"
                    break
                elseif line[j].type == "r" or line[j].type == "l" then
                    break
                end
            end
        end
    end

    --[[
    Rule (W3)
    W3. Change all ALs to R.
    --]]
    for _,c in next, line do
        if c.type == "al" then
            c.type = "r"
        end
    end

    --[[
    Rule (W4)
    W4. A single European separator between two European numbers changes
    to a European number. A single common separator between two numbers
    of the same type changes to that type.
    --]]
    for i,c in next, line do
        local pc, nc = line[i-1], line[i+1]
        if c.type == "es" then
            if (pc and pc.type == "en") and (nc and nc.type == "en") then
                c.type = "en"
            end
        elseif line[i].type == "cs" then
            if (pc and pc.type == "en") and (nc and nc.type == "en") then
                c.type = "en"
            elseif (pc and pc.type == "an") and (nc and nc.type == "an") then
                c.type = "an"
            end
        end
    end

    --[[
    Rule (W5)
    W5. A sequence of European terminators adjacent to European numbers
    changes to all European numbers.
    --]]
    for i in next, line do
        if line[i].type == "et" then
            if line[i-1] and line[i-1].type == "en" then
                line[i].type = "en"
            elseif line[i+1] and line[i+1].type == "en" then
                line[i].type = "en"
            elseif line[i+1] and line[i+1].type == "et" then
                local j = i
                while j < #line and line[j].type == "et" do
                    j = j + 1
                end
                if line[j].type == "en" then
                    line[i].type = "en"
                end
            end
        end
    end

    --[[
    Rule (W6)
    W6. Otherwise, separators and terminators change to Other Neutral:
    --]]
    for _,c in next, line do
        if c.type == "es" or c.type == "et" or c.type == "cs" then
            c.type = "on"
        end
    end

    --[[
    Rule (W7)
    W7. Search backwards from each instance of a European number until
    the first strong type (R, L, or sor) is found. If an L is found,
    then change the type of the European number to L.
    --]]
    for i in next, line do
        if line[i].type == "en" then
            local j = i
            while j>0 and line[j].level == line[i].level do
                if line[j].type == "l" then
                    line[i].type = "l"
                    break
                elseif line[j].type == "r" or line[j].type == "al" then
                    break
                end
                j = j - 1
            end
        end
    end

    --[[
    Rule (N1)
    N1. A sequence of neutrals takes the direction of the surrounding
    strong text if the text on both sides has the same direction. European
    and Arabic numbers are treated as though they were R.
    --]]
    for i in next, line do
        local pre_dir
        local post_dir
        if line[i].type == "on" and line[i-1] and line[i+1] then
            if line[i-1].type == "r" or line[i-1].type == "en" or line[i-1].type == "an" then
                pre_dir = "r"
            elseif line[i-1].type == "l" then
                pre_dir = "l"
            end
            for j=i+1,#line do
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
    for _,c in next, line do
        if c.type == "on" then
            if odd(c.level) then
                c.type = "r"
            else
                c.type = "l"
            end
        end
    end

    --[[
    Rule (I1)
    I1. For all characters with an even (left-to-right) embedding
    direction, those of type R go up one level and those of type AN or
    EN go up two levels.
    --]]
    for _,c in next, line do
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
    for _,c in next, line do
        if odd(c.level) then
            if c.type == "l" or c.type == "en" or c.type == "an" then
                c.level = c.level + 1
            end
        end
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
