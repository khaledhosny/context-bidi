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
		--[[
		if n.id==glyph then
			print(i, #line,unicode.utf8.char(n.char), line[i].char)
		elseif n.id==glue then
			print(i, #line," ", line[i].char)
		else
			print(i, #line,object, line[i].char)
		end
		--]]

		local before
		local after

		if line[i].dir_begin then
			head, _ = node.insert_before(head, n, newdirnode(line[i].dir_begin))
			table.insert(line,i,{char=object})
			before = true
		end
		if line[i].dir_end then
			head, _ = node.insert_after(head, n, newdirnode(line[i].dir_end))
			table.insert(line,i+1,{char=object})
			after = true
		end
		if before then
			i = i + 2
		elseif after then
			i = i + 1
		else
			i = i + 1
		end
	end
--	print(table.serialize(line))

	return head
end

callback.add("pre_linebreak_filter", process, "BiDi processing", 1)
--callback.register("pre_linebreak_filter", process)
