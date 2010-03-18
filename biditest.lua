kpse.set_program_name("luatex")
require("l-string")
require("bidi.lua")

file = io.open("minitests.txt", "r")

s, f = 0, 0
function dodobidi(str)
	local result1 = bidi.process(str)
	local cmd     = string.format("echo '%s' | fribidi --caprtl --levels --novisual", str)
	local fribidi = io.popen(cmd, 'r')
	local result2 = fribidi:read('*a'):gsub("\n","")
	if result1 == result2 then
--		print(str)
--		print("sucess")
		s = s + 1
	else
		print(str)
		print(result1)
		print(result2)
		f = f + 1
	end
end

function main()
	for line in file:lines() do
		local t = line:split("#")
--		print(t[1], t[2])
		dodobidi(t[1])
	end
	print(s.." sucesses,"..f.." failures.")
end

if arg[1] then
	dodobidi(arg[1])
else
	main()
end
