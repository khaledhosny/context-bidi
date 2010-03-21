bidi = { }

local function odd(x)
	return x%2 == 1 and true or false
end

local function GreaterOdd(x)
	return odd(x) and x+2 or x+1
end

local function GreaterEven(x)
	return odd(x) and x+1 or x+2
end

local function flipThisRun(from, level, max, count)
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

local function GetCAPRtl(ch)
	return CAPRtl[string.byte(ch)+ 1] or "R"
end

local GetType = GetCAPRtl

local function Line2Table(line)
	local t = { }
	line:gsub(".", function(c)
		t[#t+1] = { char = c, type = GetType(c), orig_type = GetType(c), level = 0 }
	end)
	return t
end

local function GetBaseLevel(line)
	--[[
	Rule (P2), (P3)
	P2. In each paragraph, find the first character of type L, AL, or R.
	P3. If a character is found in P2 and it is of type AL or R, then set
	the paragraph embedding level to one; otherwise, set it to zero.
	--]]
	for i in ipairs(line) do
		local currType = line[i].type
		if currType == "R" or currType == "AL" then
			return 1
		elseif currType == "L" then
			return 0
		end
	end
	return 0
end

local mirror = {
	["("] = ")",
	[")"] = "(",
	["["] = "]",
	["]"] = "[",
	["{"] = "}",
	["}"] = "{",
	["<"] = ">",
	[">"] = "<",
}

local function doMirroring(line)
	--[[
	Rule (L4)
	L4. A character that possesses the mirrored property as specified by
	Section 4.7, Mirrored, must be depicted by a mirrored glyph if the
	resolved directionality of that character is R.
	--]]
	for i in ipairs(line) do
		if odd(line[i].level) then
			if mirror[line[i].char] then
				line[i].char = mirror[line[i].char]
			end
		end
	end

	return line
end

local MAX_STACK = 60

local function ResolveTypes(line, baseLevel)
	-- Rule (X1), (X2), (X3), (X4), (X5), (X6), (X7), (X8), (X9)
	local currentEmbedding = baseLevel
	local currentOverride  = "ON"
	local levelStack       = { }
	local overrideStack    = { }
	local stackTop         = 0

	for i in ipairs(line) do
		local currType = line[i].type
		if currType == "RLE" then
			if stackTop < MAX_STACK then
				levelStack[stackTop]    = currentEmbedding
				overrideStack[stackTop] = currentOverride
				stackTop                = stackTop + 1
				currentEmbedding        = GreaterOdd(currentEmbedding)
				currentOverride         = "ON"
			end
		elseif currType == "LRE" then
			if stackTop < MAX_STACK then
				levelStack[stackTop]    = currentEmbedding
				overrideStack[stackTop] = currentOverride
				stackTop                = stackTop + 1
				currentEmbedding        = GreaterEven(currentEmbedding)
				currentOverride         = "ON"
			end
		elseif currType == "RLO" then
			if stackTop < MAX_STACK then
				levelStack[stackTop]    = currentEmbedding
				overrideStack[stackTop] = currentOverride
				stackTop                = stackTop + 1
				currentEmbedding        = GreaterOdd(currentEmbedding)
				currentOverride         = "R"
			end
		elseif currType == "LRO" then
			if stackTop < MAX_STACK then
				levelStack[stackTop]    = currentEmbedding
				overrideStack[stackTop] = currentOverride
				stackTop                = stackTop + 1
				currentEmbedding        = GreaterEven(currentEmbedding)
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
			line[i].level = currentEmbedding
			currType = "ON"
			if currentOverride ~= "ON" then
				currType = currentOverride
			end
			line[i].type  = currType
		else
			line[i].level = currentEmbedding
			if currentOverride ~= "ON" then
				currType = currentOverride
			end
			line[i].type  = currType
		end
	end
end

local function ResolveLevels(line, paragraphLevel)

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
        ResolveTypes(line, paragraphLevel)

	for i in ipairs(line) do
		if line[i].type == "NSM" then
			if i == 1 then
				line[i].type = paragraphLevel
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
		if line[i].type == "EN" then
			for j=i,1,-1 do
				if line[j].type == "AL" then
					line[i].type = "AN"
					break
				elseif line[j].type == "R" or line[j].type == "L" then
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
		if line[i].type == "AL" then
			line[i].type = "R"
		end
	end

	--[[
	Rule (W4)
	W4. A single European separator between two European numbers changes
	to a European number. A single common separator between two numbers
	of the same type changes to that type.
	--]]
	for i in ipairs(line) do
		if line[i].type == "ES" then
			if (line[i-1] and line[i-1].type == "EN") and (line[i+1] and line[i+1].type == "EN") then
				line[i].type = "EN"
			end
		elseif line[i].type == "CS" then
			if (line[i-1] and line[i-1].type == "EN") and (line[i+1] and line[i+1].type == "EN") then
				line[i].type = "EN"
			elseif (line [i-1] and line[i-1].type == "AN") and (line[i+1] and line[i+1].type == "AN") then
				line[i].type = "AN"
			end
		end
	end

	--[[
	Rule (W5)
	W5. A sequence of European terminators adjacent to European numbers
	changes to all European numbers.
	FIXME: continue
	--]]
	for i in ipairs(line) do
		if line[i].type == "ET" then
			if line[i-1] and line[i-1].type == "EN" then
				line[i].type = "EN"
			elseif line[i+1] and line[i+1].type == "EN" then
				line[i].type = "EN"
			elseif line[i+1] and line[i+1].type == "ET" then
				local j = i
				while j < #line and line[j].type == "ET" do
					j = j + 1
				end
				if line[j].type == "EN" then
					line[i].type = "EN"
				end
			end
		end
	end

	--[[
	Rule (W6)
	W6. Otherwise, separators and terminators change to Other Neutral:
	--]]
	for i in ipairs(line) do
		if line[i].type == "ES" or line[i].type == "ET" or line[i].type == "CS" then
			line[i].type = "ON"
		end
	end

	--[[
	Rule (W7)
	W7. Search backwards from each instance of a European number until
	the first strong type (R, L, or sor) is found. If an L is found,
	then change the type of the European number to L.
	--]]
	for i in ipairs(line) do
		if line[i].type == "EN" then
			local j = i
			while j>0 and line[j].level == line[i].level do
				if line[j].type == "L" then
					line[i].type = "L"
					break
				elseif line[j].type == "R" or line[j].type == "AL" then
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
		local preDir
		local postDir
		if line[i].type == "ON" and line[i-1] and line[i+1] then
			if line[i-1].type == "R" or line[i-1].type == "EN" or line[i-1].type == "AN" then
				preDir = "R"
			elseif line[i-1].type == "L" then
				preDir = "L"
			end
			for j=i+1,#line do
				if line[j].type == "R" or line[j].type == "EN" or line[j].type == "AN" then
					postDir = "R"
					break
				elseif line[j].type == "L" then
					postDir = "L"
					break
				end
			end
			if preDir and postDir and (preDir == postDir) then
				line[i].type = postDir
			end
		end
	end

	--[[
	Rule (N2)
	N2. Any remaining neutrals take the embedding direction.
	--]]
	for i in ipairs(line) do
		if line[i].type == "ON" then
			if odd(line[i].level) then
				line[i].type = "R"
			else
				line[i].type = "L"
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
		if odd(line[i].level) then
			if line[i].type == "L" or line[i].type == "EN" or line[i].type == "AN" then
				line[i].level = line[i].level + 1
			end
		else
			if line[i].type == "R" then
				line[i].level = line[i].level + 1
			elseif line[i].type == "AN" or line[i].type == "EN" then
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
			if line[i].type == "L" or line[i].type == "EN" or line[i].type == "AN" then
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
		local currType = line[i].orig_type
		if currType == "S" or currType == "B" then
			line[i].level = paragraphLevel
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

local function HasArabic(line)
	for i in ipairs(line) do
		if line[i].type == "AL" or line[i].type == "R" then
			return true
		end
	end
	return false
end

local function Process(line)
	local t
	t = Line2Table(line)
	if HasArabic(t) then
		t = ResolveLevels(t, GetBaseLevel(t))
		t = doMirroring(t)
	end

	local l = ""
	for i in ipairs(t) do
		local currType = t[i].orig_type
		if currType == "LRE" or currType == "LRO" or currType == "RLE" or currType == "RLO" or currType == "PDF" then
		else
			l = l..t[i].level.." "
		end
	end
	return l
end

bidi.baselevel = GetBaseLevel
bidi.resolve   = ResolveLevels
bidi.process   = Process
