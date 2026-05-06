-- Animations: bezier curves and animation tree
-- Sources: source/animations.conf + user-configs/user_animations.conf (CC override wins)

hl.config({ animations = { enabled = true } })

-- Bezier curves (source/animations.conf)
hl.curve("pro", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("snap", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

-- Cloud Center override bezier (user_animations.conf)
hl.curve("myBezier6", { type = "bezier", points = { { 0.833, -1.102 }, { 1.0, -1.175 } } })

-- Animation tree — CC override on windows, rest from source defaults
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "myBezier6" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "snap", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "snap" })
hl.animation({ leaf = "layers", enabled = true, speed = 2, bezier = "pro", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "pro" })
hl.animation({ leaf = "layersOut", enabled = false, speed = 0 }) -- fix screenshot gray capture
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "pro" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "pro", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "pro", style = "slide" })
