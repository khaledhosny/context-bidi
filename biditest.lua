kpse.set_program_name("luatex")
require("l-string")
require("bidi.lua")

file = io.open("minitests.txt", "r")

for line in file:lines() do
	local t = line:split("#")
--	print(t[1], t[2])
	print(t[1])
	doBidi(t[1])
end
