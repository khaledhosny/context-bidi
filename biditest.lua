require("bidi")

function string:split(pattern)
	if #self > 0 then
		local t = { }
		for s in string.gmatch(self..pattern,"(.-)"..pattern) do
			t[#t+1] = s
		end
		return t
	else
		return { }
	end
end

function doescaped(str)
	local t = {
		["_>"] = 5,
		["_<"] = 6,
		["_R"] = 14,
		["_r"] = 15,
		["_L"] = 16,
		["_l"] = 17,
		["_o"] = 18,
		["__"] = 95,
	}
	for k,v in pairs(t) do
		str = str:gsub(k,string.char(v))
	end
	return str
end

p, f = 0, 0
function dodobidi(str,passed)
	local cstr    = doescaped(str) or str
	local result1 = bidi.process(cstr)
	local cmd     = string.format("echo '%s' | fribidi --caprtl --levels --novisual", cstr)
	local fribidi = io.popen(cmd, 'r')
	local result2 = fribidi:read('*a'):gsub("\n","")
	if result1 == result2 then
		if passed then
			print("PASSED")
			print(str)
			print(result1)
--			print(cstr)
			print(result2)
		end
		p = p + 1
	else
		print("FAILED")
		print(str)
		print(result1)
--		print(cstr)
		print(result2)
		f = f + 1
	end
end

function main()
	if arg[1] then
		file = io.open(arg[1], "r")
		if file then
			for line in file:lines() do
				dodobidi(line,false)
			end
		else
			dodobidi(arg[1],true)
		end
	else
		file = io.open("minitests.txt", "r")
		for line in file:lines() do
			local t = line:split("#")
			dodobidi(t[1])
		end
	end
	print(string.format("%s passed, %s failed.", p, f))
end

main()
