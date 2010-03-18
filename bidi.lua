kpse.set_program_name("luatex")
require("l-table")

function odd(x)
	return x%2 == 1 and true or false
end

function leastGreaterOdd(x)
	return odd(x) and x+2 or x+ 1
end

function leastGreaterEven(x)
	return odd(x) and x+ 1 or x+2
end

function flipThisRun(from, level, max, count)
end

local CAPRtl = {
  "ON", "ON", "ON", "ON", "L",  "R",  "ON", "ON", "ON", "ON", "ON", "ON", "ON", "B",  "RLO","RLE", -- 00-0f
  "LRO","LRE","PDF","WS", "ON", "ON", "ON", "ON", "ON", "ON", "ON", "ON", "ON", "ON", "ON", "ON",  -- 10-1f
  "WS", "ON", "ON", "ON", "ET", "ON", "ON", "ON", "ON", "ON", "ON", "ET", "CS", "ON", "ES", "ES",  -- 20-2f
  "EN", "EN", "EN", "EN", "EN", "EN", "AN", "AN", "AN", "AN", "CS", "ON", "ON", "ON", "ON", "ON",  -- 30-3f
  "R",  "AL", "AL", "AL", "AL", "AL", "AL", "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",   -- 40-4f
  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "R",  "ON", "B",  "ON", "ON", "ON",  -- 50-5f
  "NSM","L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",   -- 60-6f
  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "L",  "ON", "S",  "ON", "ON", "ON",  -- 70-7f
}

function GetCAPRtl(ch)
	return CAPRtl[string.byte(ch)+ 1] or "R"
end

GetType = GetCAPRtl

function GetParagraphLevel(line)
	for c in line:gmatch(".") do
		if GetType(c) == "R" or GetType(c) == "AL" then
			return 1
		elseif GetType(c) == "L" then
			return 0
		end
	end
	return -1
end

local MAX_STACK = 60

-- Rule (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)
function doTypes(line, paragraphLevel, types, levels, fX)
	local currentEmbedding = paragraphLevel
	local currentOverride  = "ON"
	local levelStack       = { }
	local overrideStack    = { }
	local stackTop         = 0

	if fX then
		local i = 1
		for c in line:gmatch(".") do
			local currType = GetType(c)
			if currType == "RLE" then
				if stackTop < MAX_STACK then
					levelStack[stackTop]    = currentEmbedding
					overrideStack[stackTop] = currentOverride
					stackTop                = stackTop + 1
					currentEmbedding        = leastGreaterOdd(currentEmbedding)
					currentOverride         = "ON"
				end
			elseif currType == "LRE" then
				if stackTop < MAX_STACK then
					levelStack[stackTop]    = currentEmbedding
					overrideStack[stackTop] = currentOverride
					stackTop                = stackTop + 1
					currentEmbedding        = leastGreaterEven(currentEmbedding)
					currentOverride         = "ON"
				end
			elseif currType == "RLO" then
				if stackTop < MAX_STACK then
					levelStack[stackTop]    = currentEmbedding
					overrideStack[stackTop] = currentOverride
					stackTop                = stackTop + 1
					currentEmbedding        = leastGreaterOdd(currentEmbedding)
					currentOverride         = "R"
				end
			elseif currType == "LRO" then
				if stackTop < MAX_STACK then
					levelStack[stackTop]    = currentEmbedding
					overrideStack[stackTop] = currentOverride
					stackTop                = stackTop + 1
					currentEmbedding        = leastGreaterEven(currentEmbedding)
					currentOverride         = "L"
				end
			elseif currType == "PDF" then
				if stackTop > 0 then
					currentEmbedding = levelStack[stackTop-1]
					currentOverride  = overrideStack[stackTop-1]
					stackTop         = stackTop - 1
				end
			elseif currType == "WS" or currType == "B" or currType == "S" then
				-- Whitespace is treated as neutral for now
				levels[i] = currentEmbedding
				currType = "ON"
				if currentOverride ~= "ON" then
					currType = currentOverride
				end
				types[i] = currType
				i = i + 1
			else
				levels[i] = currentEmbedding
				if currentOverride ~= "ON" then
					currType = currentOverride
				end
				types[i] = currType
				i = i + 1
			end
		end
	else
		local i = 1
		for c in line:gmatch(".") do
			local currType = GetType(c)
			if currType == "WS" or currType == "B" or currType == "S" then
				levels[i] = currentEmbedding
				currType = "ON"
				if currentOverride ~= "ON" then
					currType = currentOverride
				end
			else
				levels[i] = currentEmbedding
				if currentOverride ~= "ON" then
					currType = currentOverride
				end
			end
			types[i] = currType
			i = i + 1
		end
	end
end

function doBidi(line)
	local types = { }
	local levels = { }
	local paragraphLevel
	local tempType, tempTypeSec
	local i, j, imax
	local fX, fAL, fET, fNSM

	for c in line:gmatch(".") do
		local Type = GetType(c)
		if Type == "AL" or Type == "R" then
			fAL = 1
		elseif Type == "LRE" or Type == "LRO" or Type == "RLE" or Type == "RLO" or Type == "PDF" or Type == "BN" then
			fX = 1
		elseif Type == "ET" then
			fET = 1
		elseif Type == "NSM" then
			fNSM = 1
		end
	end

	if (not fAL) and (not fX) then
		return 0
	end

	--[[
	Rule (P2), (P3)
	P2. In each paragraph, find the first character of type L, AL, or R.
	P3. If a character is found in P2 and it is of type AL or R, then set
	the paragraph embedding level to one; otherwise, set it to zero.
	--]]
	paragraphLevel = GetParagraphLevel(line)

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
        doTypes(line, paragraphLevel, types, levels, fX)

	if fNSM then
		if types[1] == "NSM" then
			types[1] = paragraphLevel
		end
		for i=1, #line do
			if types[i] == "NSM" then
				types[i] = types[i-1]
			end
		end
	end

	--[[
	Rule (W2)
	W2. Search backwards from each instance of a European number until the
	first strong type (R, L, AL, or sor) is found.  If an AL is found,
	change the type of the European number to Arabic number.
	--]]
	for i=1, #line do
		if types[i] == "EN" then
			tempType = levels[i]
			for j=i,1,-1 do
				if types[j] == "AL" then
					types[i] = "AN"
					break
				elseif types[j] == "R" or types[j] == "L" then
					break
				end
			end
		end
	end

	--[[
	Rule (W3)
	W3. Change all ALs to R.
	
	Optimization: on Rule Xn, we might set a flag on AL type
	to prevent this loop in L R lines only...
	--]]
	for i=1, #types do
		if types[i] == "AL" then
			types[i] = "R"
		end
	end

	--[[
	Rule (W4)
	W4. A single European separator between two European numbers changes
	to a European number. A single common separator between two numbers
	of the same type changes to that type.
	--]]
	for i=1,#line-1 do
		if types[i] == "ES" then
			if types[i-1] == "EN" and types[i+1] == "EN" then
				types[i] = "EN"
			end
		elseif types[i] == "CS" then
			if types[i-1] == "EN" and types[i+1] == "EN" then
				types[i] = "EN"
			elseif types[i-1] == "AN" and types[i+1] == "AN" then
				types[i] = "AN"
			end
		end
	end

	--[[
	Rule (W5)
	W5. A sequence of European terminators adjacent to European numbers
	changes to all European numbers.
	FIXME: continue
	--]]
	if fET then
		for i=1, #line do
			if types[i] == "ET" then
				if types[i-1] == "EN" then
					types[i] = "EN"
				elseif types[i+1] == "EN" then
					types[i] = "EN"
				elseif types[i+1] == "ET" then
					j = i
					while j < #line and types[j] == "ET" do
						j = j + 1
					end
					if types[j] == "EN" then
						types[i] = "EN"
					end
				end
			end
		end
	end

	--[[
	Rule (W6)
	W6. Otherwise, separators and terminators change to Other Neutral:
	--]]
	for i=1,#line do
		if types[i] == "ES" or types[i] == "ET" or types[i] == "CS" then
			types[i] = "ON"
		end
	end

	--[[
	Rule (W7)
	W7. Search backwards from each instance of a European number until
	the first strong type (R, L, or sor) is found. If an L is found,
	then change the type of the European number to L.
	--]]
	for i=1,#line do
		if types[i] == "EN" then
			tempType = levels[i]
			j=i
			while j>0 and levels[j] == tempType do
				if types[j] == "L" then
					types[i] = "L"
					j = j - 1
					break
				elseif types[j] == "R" or types == "AL" then
					j = j - 1
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
	for i=1,#line do
		local preDir
		local postDir
		if types[i] == "ON" then
			if types[i-1] == "R" or types[i-1] == "EN" or types[i-1] == "AN" then
				preDir = "R"
			elseif types[i-1] == "L" then
				preDir = "L"
			end
			for j=i+1,#line do
				if types[j] == "R" or types[j] == "EN" or types[j] == "AN" then
					postDir = "R"
					break
				elseif types[j] == "L" then
					postDir = "L"
					break
				end
			end
			if preDir and postDir and (preDir == postDir) then
				types[i] = postDir
			end
		end
	end

	--[[
	Rule (N2)
	N2. Any remaining neutrals take the embedding direction.
	--]]
	for i=1,#line do
		if types[i] == "ON" then
			if odd(levels[i]) then
				types[i] = "R"
			else
				types[i] = "L"
			end
		end
	end

	--[[
	Rule (I1)
	I1. For all characters with an even (left-to-right) embedding
	direction, those of type R go up one level and those of type AN or
	EN go up two levels.
	--]]
	for i=1,#line do
		if odd(levels[i]) then
			if types[i] == "L" or types[i] == "EN" or types[i] == "AN" then
				levels[i] = levels[i] + 1
			end
		else
			if types[i] == "R" then
				levels[i] = levels[i] + 1
			elseif types[i] == "AN" or types[i] == "EN" then
				levels[i] = levels[i] + 2
			end
		end
	end

	--[[
	Rule (I2)
	I2. For all characters with an odd (right-to-left) embedding direction,
	those of type L, EN or AN go up one level.
	--]]
	for i=1,#line do
		if odd(levels[i]) then
			if types[i] == "L" or types[i] == "EN" or types[i] == "AN" then
				levels[i] = levels[i] + 1
			end
		end
	end
	local l = ""
	for i=1,#levels do l = l..levels[i].." "  end
	return l
end
