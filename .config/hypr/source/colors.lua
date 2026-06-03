-- Explicit bridge to the shared color loader while Task 2 still relies on
-- the existing .hyprlua implementation.
return dofile(os.getenv("HOME") .. "/.config/hypr/.hyprlua/colors.lua")
