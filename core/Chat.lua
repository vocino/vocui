local name, ns = ...

-- Chat voice shared by every Voc addon: one line, the package name as
-- a colored prefix, then the message. A chat line is a fact or a next
-- step, never a greeting, and never ends in a period.
ns.PREFIX_COLOR = "ff66ccff"
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end
