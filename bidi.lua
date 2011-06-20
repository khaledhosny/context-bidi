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

local chardata = bidi.chardata

-- see http://www.unicode.org/versions/corrigendum6.html
chardata[0x2018].mirror = "0x2019"
chardata[0x2019].mirror = "0x2018"
chardata[0x201C].mirror = "0x201D"
chardata[0x201D].mirror = "0x201C"
chardata[0x301D].mirror = "0x301E"
chardata[0x301E].mirror = "0x301D"

local ubyte = unicode.utf8.byte
local ugsub = unicode.utf8.gsub
local uchar = unicode.utf8.char

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

local function get_type(ch)
    return chardata[ubyte(ch)].direction
end

local function resolve_types(line, base_level)
    --[[
    Rule (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)
    X1. Begin by setting the current embedding level to the paragraph
        embedding level. Set the directional override status to neutral.
    X2. With each RLE, compute the least greater odd embedding level.
    X3. With each LRE, compute the least greater even embedding level.
    X4. With each RLO, compute the least greater odd embedding level.
    X5. With each LRO, compute the least greater even embedding level.
    X6. For all types besides RLE, LRE, RLO, LRO, and PDF:
          a.  Set the level of the current character to the current
              embedding level.
          b.  Whenever the directional override status is not neutral,
                  reset the current character type to the directional
                  override status.
    X7. With each PDF, determine the matching embedding or override code.
    If there was a valid matching code, restore (pop) the last
    remembered (pushed) embedding level and directional override.
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

    for i in ipairs(line) do
        local current_type = line[i].type
        if current_type == "rle" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_odd(current_embedding)
                current_overrid           = "on"
                line[i].level             = current_embedding
            end
        elseif current_type == "lre" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_even(current_embedding)
                current_overrid           = "on"
                line[i].level             = current_embedding
            end
        elseif current_type == "rlo" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_odd(current_embedding)
                current_overrid           = "r"
                line[i].level             = current_embedding
            end
        elseif current_type == "lro" then
            if stack_top < MAX_STACK then
                level_stack[stack_top]    = current_embedding
                override_stack[stack_top] = current_overrid
                stack_top                 = stack_top + 1
                current_embedding         = least_greater_even(current_embedding)
                current_overrid           = "l"
                line[i].level             = current_embedding
            end
        elseif current_type == "pdf" then
            if stack_top > 0 then
                current_embedding = level_stack[stack_top-1]
                current_overrid   = override_stack[stack_top-1]
                stack_top         = stack_top - 1
                line[i].level     = current_embedding
            end
        elseif current_type == "ws" or current_type == "b" or current_type == "s" then
            -- Whitespace is treated as neutral for now
            line[i].level = current_embedding
            current_type  = "on"
            if current_overrid ~= "on" then
                current_type = current_overrid
            end
            line[i].type  = current_type
        else
            line[i].level = current_embedding
            if current_overrid ~= "on" then
                current_type = current_overrid
            end
            line[i].type  = current_type
        end
    end
end

local function resolve_levels(line, base_level)
    -- Rule (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)
    resolve_types(line, base_level)

    for i in ipairs(line) do
        if line[i].type == "nsm" then
            if i == 1 then
                line[i].type = base_level
            else
                line[i].type = line[i-1].type
            end
        end
    end

    --[[
    Rule (W2)
    W2. Search backwards from each instance of a European number until the
    first strong type (R, L, AL, or sor) is found.  If an AL is found,
    change the type of the European number to Arabic number.
    --]]
    for i in ipairs(line) do
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
    for i in ipairs(line) do
        if line[i].type == "al" then
            line[i].type = "r"
        end
    end

    --[[
    Rule (W4)
    W4. A single European separator between two European numbers changes
    to a European number. A single common separator between two numbers
    of the same type changes to that type.
    --]]
    for i in ipairs(line) do
        if line[i].type == "es" then
            if (line[i-1] and line[i-1].type == "en") and (line[i+1] and line[i+1].type == "en") then
                line[i].type = "en"
            end
        elseif line[i].type == "cs" then
            if (line[i-1] and line[i-1].type == "en") and (line[i+1] and line[i+1].type == "en") then
                line[i].type = "en"
            elseif (line [i-1] and line[i-1].type == "an") and (line[i+1] and line[i+1].type == "an") then
                line[i].type = "an"
            end
        end
    end

    --[[
    Rule (W5)
    W5. A sequence of European terminators adjacent to European numbers
    changes to all European numbers.
    --]]
    for i in ipairs(line) do
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
    for i in ipairs(line) do
        if line[i].type == "es" or line[i].type == "et" or line[i].type == "cs" then
            line[i].type = "on"
        end
    end

    --[[
    Rule (W7)
    W7. Search backwards from each instance of a European number until
    the first strong type (R, L, or sor) is found. If an L is found,
    then change the type of the European number to L.
    --]]
    for i in ipairs(line) do
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
    for i in ipairs(line) do
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
    for i in ipairs(line) do
        if line[i].type == "on" then
            if odd(line[i].level) then
                line[i].type = "r"
            else
                line[i].type = "l"
            end
        end
    end

    --[[
    Rule (I1)
    I1. For all characters with an even (left-to-right) embedding
    direction, those of type R go up one level and those of type AN or
    EN go up two levels.
    --]]
    for i in ipairs(line) do
        if not odd(line[i].level) then
            if line[i].type == "r" then
                line[i].level = line[i].level + 1
            elseif line[i].type == "an" or line[i].type == "en" then
                line[i].level = line[i].level + 2
            end
        end
    end

    --[[
    Rule (I2)
    I2. For all characters with an odd (right-to-left) embedding direction,
    those of type L, EN or AN go up one level.
    --]]
    for i in ipairs(line) do
        if odd(line[i].level) then
            if line[i].type == "l" or line[i].type == "en" or line[i].type == "an" then
                line[i].level = line[i].level + 1
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
    for i in ipairs(line) do
        local current_type = line[i].orig_type
        if current_type == "s" or current_type == "b" then
            line[i].level = base_level
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
local whatsit = node.id("whatsit")
local dir     = node.subtype("dir")

local object  = "￼"

local function node_string(head)
    --[[
    Takes a node list and returns its textual string representation
    --]]

    local str = ""
    for n in node.traverse(head) do
        if n.id == glyph then
            str = str .. uchar(n.char)
        elseif n.id == glue then
            str = str .. " "
        elseif n.id == whatsit and n.subtype == dir then
            head, _ = node.remove(head, n)
        else
            str = str .. object
        end
    end
    return head, str
end

local function new_dir_node(dir)
    local n = node.new("whatsit","dir")
    n.dir = dir
    return n
end

local level_attribute = bidi.attributes.bidilevel
local bdir_attribute  = bidi.attributes.bidbdir
local edir_attribute  = bidi.attributes.bidedir

local dirs = {
    ["+TRT"] = 1,
    ["-TRT"] = 2,
    ["+TLT"] = 3,
    ["-TLT"] = 4,
}

local function insert_dir_points(line)
    --[[
    Takes a line with resolved embedding levels and inserts begin/enddir marks
    as required.
    --]]

    local max_level = 0

    for i in ipairs(line) do
        if line[i].level > max_level then
            max_level = line[i].level
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

local function line_table(str)
    --[[
    Takes a string of text and convert it to our line data structure
    --]]

    local t = { }
    ugsub(str, ".", function(c)
        t[#t+1] = { char = c, type = get_type(c), orig_type = get_type(c), level = 0 }
    end)
    return t
end

local function get_base_level(line)
    --[[
    Rule (P2), (P3)
    P2. In each paragraph, find the first character of type L, AL, or R.
    P3. If a character is found in P2 and it is of type AL or R, then set
    the paragraph embedding level to one; otherwise, set it to zero.
    --]]

    for i in ipairs(line) do
        local current_type = line[i].type
        if current_type == "r" or current_type == "al" then
            return 1
        elseif current_type == "l" then
            return 0
        end
    end
    return 0
end

local function assign_levels(head, line)
    --[[
    Takes a node list and sets node directional attributes based on
    corresponding line characters.
    --]]

    local i = 1
    for n in node.traverse(head) do
        node.set_attribute(n, level_attribute, line[i].level)
        local bdir = line[i].bdir
        local edir = line[i].edir
        if bdir then
            node.set_attribute(n, bdir_attribute , dirs[bdir])
        else
            node.unset_attribute(n, bdir_attribute)
        end
        if edir then
            node.set_attribute(n, edir_attribute , dirs[edir])
        else
            node.unset_attribute(n, edir_attribute)
        end
        i = i + 1
    end
end

local function process_string(str, group)
    local line, base_level

    line = line_table(str)

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

local function process_node(head, group)
    local str, line

    head, str = node_string(head)
    line      = process_string(str, group)

    assert(#line == node.length(head))

    assign_levels(head, line)

    for n in node.traverse(head) do
        if n.id == glyph then
            local v = node.has_attribute(n, level_attribute)
            if v and odd(v) then
                local mirror = chardata[n.char].mirror
                if mirror then
                    n.char = mirror
                end
            end
        end

        local bdir = node.has_attribute(n, bdir_attribute)
        local edir = node.has_attribute(n, edir_attribute)
        local new
        node.slide(head)
        if bdir then
            if not n.prev and group == "" then
                while n and n.id ~= glyph do
                    n = n.next
                end
            end
            if bdir == 1 then     -- +TRT
                head, new = node.insert_before(head, n, new_dir_node("+TRT"))
            elseif bdir == 3 then -- +TLT
                head, new = node.insert_before(head, n, new_dir_node("+TLT"))
            end
        end
        if edir then
            if not n.next and group == "" then
                while n and n.id ~= glyph do
                    n = n.prev
                end
            end
            if edir == 2 then     -- -TRT
                head, new = node.insert_after(head, n, new_dir_node("-TRT"))
            elseif edir == 4 then -- -TLT
                head, new = node.insert_after(head, n, new_dir_node("-TLT"))
            end
        end
        if new then
            node.unset_attribute(new, bdir_attribute)
            node.unset_attribute(new, edir_attribute)
        end

    end

    return head
end

bidi.process   = process_node
