-- @cloud-center-state = {"animations:animation": "windows,1,1,myBezier3;workspaces,1,1,myBezier2,slide", "animations:bezier": "myBezier3,0.084,1.119,0.829,0.723", "animations:enabled": "true"}

-- Animations: bezier curves and animation tree

hl.config({ animations = { enabled = true } })

hl.curve("pro", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("snap", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "snap", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "snap", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "snap" })
hl.animation({ leaf = "layers", enabled = true, speed = 2, bezier = "pro", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "pro" })
hl.animation({ leaf = "layersOut", enabled = false, speed = 0 })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "pro" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "pro", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "pro", style = "slide" })

-- --- Cloud Center managed animation settings ---
hl.config({ animations = { enabled = true } })
hl.curve("myBezier3", { type = "bezier", points = { { 0.084, 1.119 }, { 0.829, 0.723 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 1, bezier = "myBezier3" })
-- --- End Cloud Center managed animation settings ---
