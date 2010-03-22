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

local chardata= characters.data

local function node_string(head)
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

local function new_dir_node(dir)
	local n = node.new("whatsit","dir")
	n.dir = dir
	return n
end

local alvl = tex.attributenumber["alvl"]
local bdir = tex.attributenumber["bdir"]
local edir = tex.attributenumber["edir"]

local dirs = {
	["+TRT"] = 1,
	["-TRT"] = 2,
	["+TLT"] = 3,
	["-TLT"] = 4,
}

local function assign_levels(head, line)
	local i = 1
	for n in node.traverse(head) do
		node.set_attribute(n, alvl, line[i].level)
		local b = line[i].bdir
		local e = line[i].edir
		if b then
			node.set_attribute(n, bdir , dirs[b])
		end
		if e then
			node.set_attribute(n, edir , dirs[e])
		end
		i = i + 1
	end
end

local function process(head)
	-- remove existing directional nodes, should be done in a more clever way
	for n in node.traverse(head) do
		if n.id == whatsit and n.subtype == dir then
			head, _ = node.remove(head, n)
		end
	end
	-- convert node list to its string reprisentation, then resolve its bidi levels
	local str = node_string(head)
	local line = resolve(str)
	assert(node.length(head) == #line)

	assign_levels(head, line)

	for n in node.traverse(head) do
		if n.id == glyph then
			local v = node.has_attribute(n, alvl)
			if v and odd(v) then
				local mirror = chardata[n.char].mirror
				if mirror then
					n.char = mirror
				end
			end
		end

		local b = node.has_attribute(n, bdir)
		local e = node.has_attribute(n, edir)
		local new
		if b then
			if b == 1 then     -- +TRT
				head, new = node.insert_before(head, n, new_dir_node("+TRT"))
			elseif b == 3 then -- +TLT
				head, new = node.insert_before(head, n, new_dir_node("+TLT"))
			end
		end
		if e then
			if e == 2 then     -- -TRT
				head, new = node.insert_after(head, n, new_dir_node("-TRT"))
			elseif e == 4 then -- -TLT
				head, new = node.insert_after(head, n, new_dir_node("-TLT"))
			end
		end
		if new and b then
			node.unset_attribute(new, bdir)
		elseif new and e then
			node.unset_attribute(new, edir)
		end
	end

	return head
end

callback.add("pre_linebreak_filter", process, "BiDi processing", 1)
callback.add("hpack_filter", process, "BiDi processing", 1)
--callback.add("buildpage_filter",     process, "BiDi processing", 1)
--callback.register("pre_linebreak_filter", process)
