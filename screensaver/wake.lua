-- Every key or mouse click wakes the desktop. Ignore the initial pointer
-- movement caused by mapping the fullscreen window, then wake on movement too.
local pointer_ready = false
mp.add_timeout(0.75, function() pointer_ready = true end)

local function wake()
    mp.commandv("quit")
end

mp.add_forced_key_binding("ANY_UNICODE", "wake-text", wake)
mp.add_forced_key_binding("UNMAPPED", "wake-input", wake)
mp.add_forced_key_binding("MOUSE_MOVE", "wake-pointer", function()
    if pointer_ready then wake() end
end)
mp.add_forced_key_binding("MOUSE_ENTER", "ignore-pointer-enter", function() end)
mp.add_forced_key_binding("MOUSE_LEAVE", "ignore-pointer-leave", function() end)
