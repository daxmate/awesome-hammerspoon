--- === Log ===
---
--- Optional diagnostics for DaxCalendar: phase timings and canvas descriptions.
--- A module of its own so the drawing code never touches file handles, and so a
--- silent failure or a slow build can still be inspected afterwards (the
--- Hammerspoon console buffer is easy to miss).
---
--- Path: /tmp/daxcalendar.log (append). Anything else uses hs.printf.

local M = {}

M.path = "/tmp/daxcalendar.log"

function M.diag(msg)
	local f = io.open(M.path, "a")
	if f then
		f:write(os.date("%H:%M:%S") .. "  " .. msg .. "\n")
		f:close()
	end
	if hs.printf then hs.printf("[DaxCalendar] " .. msg) end
end

--- Milliseconds since the epoch (hs.timer's clock), for phase timings.
function M.nowMs()
	return hs.timer.secondsSinceEpoch() * 1000
end

local function elementCount(canvas)
	if not canvas or not canvas.elementCount then return "?" end
	local ok, n = pcall(function() return canvas:elementCount() end)
	if not ok or type(n) ~= "number" then return "?" end
	return n
end

--- "screen name frame=x,y wxh N elements", one per canvas, joined by " | ".
function M.describeSet(set)
	local parts = {}
	for _, entry in ipairs(set) do
		local f = entry.canvas:frame()
		parts[#parts + 1] = string.format("%s frame=%.0f,%.0f %.0fx%.0f %s elements",
			entry.screen:name(), f.x, f.y, f.w, f.h, tostring(elementCount(entry.canvas)))
	end
	return table.concat(parts, " | ")
end

return M
