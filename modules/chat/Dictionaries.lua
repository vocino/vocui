local _, ns = ...
local chat = ns.chat

-- The two dialect tables, ported from Dwarvenizer/Trollizer 1.10 by
-- Carlo Zottmann (MIT, https://github.com/czottmann/wow-dwarvenizer-trollizer):
-- dict1 phrases apply to the whole line first, dict2 words apply per
-- word after. Array order is match order; the engine tries each pair
-- in turn. Variant tables pick one replacement at random per message.
--
-- Markers, remapped for file hygiene: the original suffixed flavor
-- replacements with a two-byte section sign (UTF-8 0xC2 0xA7, which is
-- why its gate read the last TWO bytes) and stripped it after the
-- roll. This port writes that marker as "!" instead; behavior is
-- identical. The original's "@" suffix never gated anything (its gate
-- read two bytes against a one-byte marker, so it could never match)
-- and only stripped, so "@" is dropped here with identical output.
-- The one real fix: the original's {"on its" = "onna", "onni's"}
-- entry carried a stray array element that replaced the DIGIT 1 with
-- "onni's" wherever it appeared; it is ported as true variants.
chat.DICTIONARIES = {
  dwarf = {
    dict1 = {
      { "I am", "I'mma" },
      { "Good day", "G'day" },
      { "don't know", "dunnae" },
      { "it's a", "issa" },
      { "it's like", "'slike!" },
      { "in the", "inna" },
      { "and a", "anna" },
      { "what do you", "whad'ya" },
      { "into it", "innit" },
      { "on it", "onnit" },
      { "is that", "issat" },
      { "on its", { "onna", "onni's" } },
      { "let me", "lemme" },
      { "isn't it", { "innit", "ain't" } },
      { "have to", "hafta" },
      { "going to (%l+)", "gonna %1" },
      { "you are", "ye'r" },
      { "come here", "c'mere" },
      { "little friend", "wee buddy!" },
      { "let me", "lemme" },
      { "this is", "tis'" },
    },
    dict2 = {
      { "^kek$", "OMG I JUST FARTED" },
      { "^lolz$", "OMG WHY DIDN'T I PICK HORDE WTF" },
      { "^I'm$", "I'mma!" },
      { "girl", { "lass!", "missy!" } },
      { "boy", "lad" },
      { "hello", "G'day" },
      { "just", "jes" },
      { "^old$", { "ol'!", "ole!" } },
      { "^for$", "fer!" },
      { "^and$", "an'" },
      { "^your", "yer" },
      { "^you're$", "ye'r" },
      { "^you$", { "ya!", "yeh!" } },
      { "^them$", "'em!" },
      { "^their$", "'eir" },
      { "^there[^%w]*", "ther'!" },
      { "that", "tha'" },
      { "before", "afore" },
      { "^to$", { "ta!", "t'!" } },
      { "^the$", { "tha!", "th'!" } },
      { "little", { "li'l", "wee", "tiny" } },
      { "on't$", { "unnae!", "un'!" } },
      { "([a-z]+)([nlkp]+)ing$", "%1%2in'" },
      { "^of$", "o'!" },
      { "until", "'til" },
      { "ldn't$", "ldnae!" },
      { "dn't$", "nnae!" },
      { "^are$", "is!" },
      { "^he", "'e" },
      { "ffe", "ff'" },
      { "ows", "ers!" },
      { "ever", "ev'r" },
      { "what", "wot" },
      { "^with$", "wit'!" },
      { "^my", { "me!", "m'!" } },
      { "^were$", "was!" },
      { "^yes$", { "oh aye!", "aye!", "yeah!", "yep!" } },
      { "some", "sum" },
    },
  },
  troll = {
    dict1 = {
      { "i am", { "me is!", "me be!", "i be!", "i!" } },
      { "you are", "you be!" },
      { "are you", "ya bein'!" },
      { "will be", "gonna be" },
      { "have to", "hafta" },
      { "going to", "gonna" },
      { "want to", "wanna" },
      { "need to", "needta" },
      { "let me", "lemme!" },
      { "is this", "dis be" },
      { "will (%w-([ptg]-))([%s%p])", "be %1%2in'%3!" },
      { "i'll (%w-([ptg]-))([%s%p])", "be %1%2in'%3!" },
      { "what's", "wha's" },
      { "what is", "wha's" },
    },
    dict2 = {
      { "^kek$", "OMG I JUST FARTED" },
      { "^lolz$", "OMG WHY DIDN'T I PICK ALLIANCE WTF" },
      { "little", "li'l!" },
      { "^is$", "be!" },
      { "^for$", "fo'!" },
      { "^yes$", { "yah, mon!", "yeah, mon!", "yes, mon!", "yah!", "yeah!" } },
      { "^you$", "ya" },
      { "^are$", "be!" },
      { "^to$", "ta" },
      { "^and$", "an'" },
      { "([a-z]+)([nlkp]+)ing$", "%1%2in'" },
      { "^must$", "mus'!" },
      { "other", "odda!" },
      { "^over$", "ove'" },
      { "^man$", "mon" },
      { "^girl$", "gal" },
      { "^hello$", { "'ello!", "yo!", "ey!", "peace!" } },
      { "^me$", "mi!" },
      { "^my$", { "mi!", "me!" } },
      { "^the$", { "da", "de" } },
      { "^the(%w+)", "de%1" },
      { "^tha(%w+)", "da%1" },
      { "^this$", "dis" },
      { "th", "t'!" },
      { "frostshock", "froshooogg" },
    },
  },
}
