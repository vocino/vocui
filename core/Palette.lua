local _, ns = ...

-- Palette, defined once and loaded first. Every color the package
-- paints is a name from this table; nothing writes an RGB triple at
-- a call site. The tokens are the family's: gold for titles and
-- emphasis, white for body, gray for secondary text, red and green
-- for state only.
ns.COLORS = {
  gold = { 1, 0.82, 0 }, -- titles, emphasis, the one accent per screen
  text = { 1, 1, 1 }, -- body
  muted = { 0.5, 0.5, 0.5 }, -- hints, secondary text
  red = { 0.9, 0.3, 0.25 }, -- warnings only, never decoration
  green = { 0.25, 0.9, 0.35 }, -- valid state only
}

-- r, g, b (and alpha when given) for a token, so a SetTextColor or
-- SetColorTexture call reads as the token's name.
function ns.rgb(token, alpha)
  return token[1], token[2], token[3], alpha
end
