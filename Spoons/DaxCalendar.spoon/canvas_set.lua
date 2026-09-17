--- === Canvas set ===
---
--- One canvas per attached screen: a canvas window cannot span displays, so
--- "draw on every screen" means one canvas per screen -- same size, same
--- content, each anchored to its own screen's bottom-left corner.
---
--- A set is an array of entries; `build` lets the caller decide what an entry
--- holds (the calendar stores its view handle in there too).

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(DIR .. "/layout.lua")

local M = {}

--- Build a set, one entry per attached screen: `new_entry(screen)` returns the
--- entry to keep.
function M.build(new_entry)
	local set = {}
	for _, screen in ipairs(hs.screen.allScreens()) do
		set[#set + 1] = new_entry(screen)
	end
	return set
end

--- Create the canvas window for `screen`, `w` x `h` points, anchored to that
--- screen's bottom-left corner and shown on every space at the desktop-icon
--- level. `on_toggle` runs when the view toggle is clicked; clicks anywhere else
--- fall through to the desktop as before (only elements flagged trackMouseDown
--- call back).
function M.newCanvas(screen, w, h, on_toggle)
	local canvas = hs.canvas.new(L.canvasFrame(screen, w, h))
	canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
	-- hs.canvas only delivers mouse clicks at desktopIcon + 1 or higher; that is
	-- still far below normal window level, so the calendar stays behind windows.
	canvas:level(hs.canvas.windowLevels.desktopIcon + 1)
	canvas:mouseCallback(function(_, message, element_id)
		if message == "mouseDown" and element_id == L.toggle.id and on_toggle then
			on_toggle()
		end
	end)
	return canvas
end

function M.show(set)
	for _, entry in ipairs(set) do entry.canvas:show() end
end

function M.hide(set)
	for _, entry in ipairs(set) do entry.canvas:hide() end
end

function M.delete(set)
	for _, entry in ipairs(set) do
		pcall(function() entry.canvas:delete() end)
	end
end

return M
