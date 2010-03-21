require("bidi")

bidi                = bidi or { }

bidi.module         = {
	name        = "bidi",
	version     = 0.1,
	date        = "2010/3/21",
	description = "Unicode Bidirectional Algorithm implementation for LuaTeX",
	author      = "Khaled Hosny",
	copyright   = "Khaled Hosny",
	license     = "CC0",
}

local odd     = bidi.odd
local resolve = bidi.process

local uchar   = unicode.utf8.char

local hlist   = node.id("hlist")
local glyph   = node.id("glyph")
local glue    = node.id("glue")
local whatsit = node.id("whatsit")
local dir     = node.subtype("dir")

local object  = "￼"

local function node2string(head)
	local str = ""
	for n in node.traverse(head) do
		if n.id == glyph then
			str = str .. uchar(n.char)
		elseif n.id == glue then
			str = str .. " "
--		elseif n.id == hlist then
--			str[#str+1] = node2string(n)
--		elseif n.id == whatsit and n.subtype == 7 then
--			str[#str+1] = n.dir
		else
			str = str .. object
		end
	end
	return str
end

local function newdirnode(dir)
	local n = node.new("whatsit","dir")
	n.dir = dir
	return n
end

local function process(head)
	-- remove existing directional nodes, should be done in a more clever way
	for n in node.traverse(head) do
		if n.id == whatsit and n.subtype == dir then
			head, _ = node.remove(head, n)
		end
	end
	local str = node2string(head)
	local line = resolve(str)
	assert(node.length(head) == #line)

	local i = 1
	for n in node.traverse(head) do
		local currlevel = line[i].level
		local prevlevel = line[i-1] and line[i-1].level
		local nextlevel = line[i+1] and line[i+1].level
		if not prevlevel or (prevlevel and prevlevel ~= currlevel) then
			if prevlevel then
				if odd(prevlevel) then
					head, _ = node.insert_before(head, n, newdirnode("-TRT"))
				else
					head, _ = node.insert_before(head, n, newdirnode("-TLT"))
				end
			end
			if odd(currlevel) then
				head, _ = node.insert_before(head, n, newdirnode("+TRT"))
			else
				head, _ = node.insert_before(head, n, newdirnode("+TLT"))
			end
			if not nextlevel then
				if odd(currlevel) then
					head, _ = node.insert_after(head, n, newdirnode("-TRT"))
				else
					head, _ = node.insert_after(head, n, newdirnode("-TLT"))
				end
			end
		end
		i = i + 1
	end

	return head
end

callback.add("pre_linebreak_filter", process, "BiDi processing", 1)
--callback.register("pre_linebreak_filter", process)
