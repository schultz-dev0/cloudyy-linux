from pathlib import Path


root = Path(__file__).parent
dock = (root / "modules/dock/Dock.qml").read_text()
icon = (root / "modules/dock/DockIcon.qml").read_text()
button = (root / "modules/dock/DockDockButton.qml").read_text()

assert "function advanceFrame()" in icon
assert "function advanceFrame()" in button
assert "FrameAnimation {" in dock
assert "id: dockFrameAnimation" in dock
assert "id: dockFrameTimer" not in dock
assert "Timer {" not in icon
assert "Timer {" not in button
