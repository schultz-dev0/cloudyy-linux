-- Monitor layout and workspace assignments
-- Source: user-configs/user_monitors.conf

hl.monitor({ output = "DP-1",       mode = "2560x1440@155.00", position = "0x0",      scale = "1" })
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@0.06",   position = "-1920x360", scale = "1" })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@0.06",   position = "-1920x360", scale = "1" })
hl.monitor({ output = "HEADLESS-4", mode = "1920x1080@0.06",   position = "-1920x360", scale = "1" })
hl.monitor({ output = "HEADLESS-5", mode = "1920x1080@0.06",   position = "-1920x360", scale = "1" })
hl.monitor({ output = "HEADLESS-6", mode = "1920x1080@0.06",   position = "-1920x193", scale = "1" })

-- Workspace pinning
hl.workspace_rule({ workspace = "1",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "2",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "3",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "4",  monitor = "DP-1" })
hl.workspace_rule({ workspace = "5",  monitor = "HEADLESS-2" })
hl.workspace_rule({ workspace = "6",  monitor = "HEADLESS-2" })
hl.workspace_rule({ workspace = "7",  monitor = "HEADLESS-2" })
hl.workspace_rule({ workspace = "8",  monitor = "HEADLESS-2" })
hl.workspace_rule({ workspace = "9",  monitor = "HEADLESS-2" })
hl.workspace_rule({ workspace = "10", monitor = "HEADLESS-2" })
