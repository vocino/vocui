local _, ns = ...
local chat = ns.chat

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative chat.OPTIONS table through the core settings service
-- (settings.BuildPage), so the module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.
chat.panelBuilt = false

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Only the toggle acts: it installs or
-- removes the send wrapper. Dialect, chance, and channels read live
-- at send time, so their rows need no callback.
function chat.RowChanged(key)
  if key == "enabled" then
    if chat.ApplyEnabledImpl then
      chat.ApplyEnabledImpl()
    end
  end
end

function chat.BuildPanelImpl(page)
  ns.settings.BuildModulePage(chat, page, "Lines starting with (( stay untouched, emotes never change")
end
