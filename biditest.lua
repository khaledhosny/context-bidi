kpse.set_program_name("luatex")
require("l-string")
require("bidi.lua")

function doescaped(str)
	local t = {
		["_>"] = 5,
		["_<"] = 6,
		["_R"] = 15,
		["_r"] = 16,
		["_L"] = 17,
		["_l"] = 18,
		["_o"] = 19,
		["__"] = 95,
	}
	for k,v in pairs(t) do
		str = str:gsub(k,string.char(v))
	end
	return str
end

s, f = 0, 0
function dodobidi(str,passed)
	local str     = doescaped(str)
	local result1 = bidi.process(str)
	local cmd     = string.format("echo '%s' | fribidi --caprtl --levels --novisual", str)
	local fribidi = io.popen(cmd, 'r')
	local result2 = fribidi:read('*a'):gsub("\n","")
	if result1 == result2 then
		if passed then
			print("PASSED")
			print(str)
			print(result1)
			print(result2)
		end
		s = s + 1
	else
		print("FAILED")
		print(str)
		print(result1)
		print(result2)
		f = f + 1
	end
end

function main()
	if arg[1] then
		file = io.open(arg[1], "r")
		if file then
		else
			dodobidi(arg[1])
		end
	else
		file = io.open("minitests.txt", "r")
	end
	if file then
		for line in file:lines() do
			local t = line:split("#")
--			print(t[1], t[2])
			dodobidi(t[1])
		end
	end
	print(s.." passed,"..f.." failed.")
end

main()
