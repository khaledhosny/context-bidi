kpse.set_program_name("luatex")
require("l-string")
require("bidi.lua")

file = io.open("minitests.txt", "r")

function dodobidi(str)
	print(str)
	doBidi(str)
	os.execute(string.format("echo '%s' | fribidi --caprtl --levels --novisual", str))
end

function main()
	for line in file:lines() do
		local t = line:split("#")
--		print(t[1], t[2])
		dodobidi(t[1])
	end
end
--dodobidi("A TEST FOR WEAK TYPES. 123+,456")
main()
