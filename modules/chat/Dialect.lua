local _, ns = ...
local chat = ns.chat

-- The dialect engine: pure text in, mangled text out. Dictionaries.lua
-- holds the tables; array order there is match order here. The only
-- impure input is math.random (variant picks and chance rolls), which
-- the client seeds itself -- this package never reseeds shared
-- randomness -- so headless tests stub it for deterministic lines.

-- A trailing "!" marks a flavor replacement: it applies only when a
-- 1-100 roll stays under chance * 10. Unmarked replacements always
-- apply. Markers strip either way, so stored text never leaks out.
chat.FLAVOR_MARK = "!"

-- The one impure input, defaulting to the shared generator. Tests
-- replace it per module table for deterministic lines; the package
-- never reseeds shared randomness.
chat.random = math.random

-- One variant from an entry: a plain string returns itself, a table
-- of variants returns one at random.
function chat.PickVariant(entry)
  if type(entry) == "table" then
    if #entry == 0 then
      return nil
    end
    return entry[chat.random(#entry)]
  end
  return entry
end

-- Roll one picked replacement against the chance. Flavor thins out
-- below chance 10; at 10 everything applies. Returns nil when the
-- replacement sits this message out.
function chat.Decide(replacement, chance)
  if type(replacement) ~= "string" then
    return nil
  end
  if chance < 10 and replacement:sub(-1) == chat.FLAVOR_MARK and chat.random(100) > chance * 10 then
    return nil
  end
  return (replacement:gsub("[" .. chat.FLAVOR_MARK .. "]+%s*$", ""))
end

-- Rewrite one segment with one pair. All-caps stays untouched, so
-- shouting never comes out mangled. Otherwise the lowercase pattern
-- applies, then the capitalized variant -- except the ^he rule, whose
-- capitalized form would mangle "'E" out of "He".
function chat.TranslateSegment(segment, search, replace)
  if segment:find("^[%u]+$") then
    return segment
  end
  segment = segment:gsub(search, replace)
  if search ~= "^he" then
    local searchCap = search:gsub("%l", string.upper, 1)
    local replaceCap = replace:gsub("%l", string.upper, 1)
    segment = segment:gsub(searchCap, replaceCap)
  end
  return segment
end

-- Mangle one chat line with one dialect table. Hyperlinks shelter
-- behind control-char placeholders first (non-greedy: the 2007 greedy
-- match could swallow two links and the text between them) and come
-- back byte-identical through a function replacement, so a "%" in a
-- link can never read as a capture. Phrases need surrounding spaces,
-- like the original; words split on whitespace with trailing
-- punctuation carried through. A "^"-anchored rule skips a word that
-- follows an apostrophe ending, so "'e ol'" never doubles up.
function chat.Mangle(text, dict, chance)
  if type(text) ~= "string" or type(dict) ~= "table" then
    return text
  end
  local sheltered = {}
  local protected = text:gsub("(|c.-|r)", function(link)
    sheltered[#sheltered + 1] = link
    return "\1" .. #sheltered .. "\1"
  end)
  if type(dict.dict1) == "table" then
    for _, pair in ipairs(dict.dict1) do
      local replace = chat.Decide(chat.PickVariant(pair[2]), chance)
      if replace ~= nil then
        protected = chat.TranslateSegment(protected, "%s+" .. pair[1] .. "%s+", " " .. replace .. " ")
      end
    end
  end
  local out, last = {}, ""
  if type(dict.dict2) == "table" then
    for segment in protected:gmatch("%S+") do
      local tail = segment:match("(%p+)$") or ""
      local core = segment:gsub("%p*$", "")
      for _, pair in ipairs(dict.dict2) do
        local search = pair[1]
        if not (search:sub(1, 1) == "^" and last:sub(-1) == "'") then
          local replace = chat.Decide(chat.PickVariant(pair[2]), chance)
          if replace ~= nil then
            core = chat.TranslateSegment(core, search, replace)
          end
        end
      end
      core = core:gsub("''", "'")
      last = core
      out[#out + 1] = core .. tail
    end
  end
  local message = table.concat(out, " ")
  for i, link in ipairs(sheltered) do
    message = message:gsub("\1" .. i .. "\1", function()
      return link
    end, 1)
  end
  return message
end
