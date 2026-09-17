-- Headless behaviour tests for the DaxCalendar spoon.
--
--   tests/run.sh                     # every scenario
--   lua tests/harness.lua            # today (real date)
--   DATE_Y=2026 DATE_M=12 DATE_D=31 lua tests/harness.lua
--
-- Loads init.lua against stub hs.* APIs (tests/stub_hs.lua) and asserts what a
-- refactor must not break: one canvas per screen anchored to that screen, the
-- grid content for every month shown, exactly one today marker, element counts,
-- that nothing is clipped, view switching, display changes and month rollovers.
--
-- Expectations are computed here from first principles (not read from the
-- modules), so the tests stay a real second opinion.

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local SPOON_DIR = here .. "/.."
local stub = dofile(here .. "/stub_hs.lua")

local MARGIN = 20          -- the canvas is anchored this far inside the screen
local BLOCK_BASE = 9       -- one month block: today pill + title + 7 weekday headers
local BLOCK_PER_ROW = 22   -- ... plus 7 day numbers + 1 week number + 7 badges + 7 labels
local LEGEND_ELEMENTS = 11 -- 4 discs + 3 glyphs + 4 captions
local TOGGLE_ELEMENTS = 1

-- ----------------------------------------------------------- controllable date ---
local real_date, real_time = os.date, os.time
local now = real_date("*t")
local today = {
	year = tonumber(os.getenv("DATE_Y") or now.year),
	month = tonumber(os.getenv("DATE_M") or now.month),
	day = tonumber(os.getenv("DATE_D") or now.day),
}
os.date = function(fmt, t)
	if t == nil and (fmt == "*t" or fmt == "!*t") then
		local d = { year = today.year, month = today.month, day = today.day, hour = 12, min = 0, sec = 0 }
		d.wday = real_date("*t", real_time(d)).wday
		return d
	end
	return real_date(fmt, t)
end

local function goTo(year, month, day)
	today.year, today.month, today.day = year, month, day
end

-- ------------------------------------------------------- independent expectations ---
--- Days in a month and the weekday of its 1st (1 = Sunday), and the week rows a
--- month needs: recomputed here so the tests do not trust the spoon's own maths.
local function monthFacts(year, month)
	local first = real_date("*t", real_time({ year = year, month = month, day = 1 }))
	local days = real_date("*t", real_time({ year = year, month = month + 1, day = 0 })).day
	return days, first.wday
end

local function monthRows(year, month)
	local days, wday = monthFacts(year, month)
	return math.ceil((wday + days - 1) / 7)
end

--- Elements a view must hold: the panel, every block (only the week rows a month
--- needs are built), the legend and the toggle.
local function expectedElements(months)
	local n = 1 + LEGEND_ELEMENTS + TOGGLE_ELEMENTS
	for _, m in ipairs(months) do
		n = n + BLOCK_BASE + BLOCK_PER_ROW * monthRows(m.year, m.month)
	end
	return n
end

--- The day number that belongs in cell (row, col) (0-based) of a month grid, or
--- nil for a cell outside the month.
local function expectedDay(year, month, row, col)
	local days, wday = monthFacts(year, month)
	if row >= monthRows(year, month) then return nil end
	local n = row * 7 + col - wday + 2
	if n < 1 or n > days then return nil end
	return n
end

--- The three months the window view shows: the current one in the middle.
local function windowMonths()
	local months = {}
	for i = 1, 3 do
		local month, year = today.month + i - 2, today.year
		while month < 1 do month, year = month + 12, year - 1 end
		while month > 12 do month, year = month - 12, year + 1 end
		months[i] = { year = year, month = month }
	end
	return months
end

local function yearMonths()
	local months = {}
	for m = 1, 12 do months[m] = { year = today.year, month = m } end
	return months
end

-- ------------------------------------------------------------------ harness ---
local checks, failures = 0, {}
local function check(ok, label, detail)
	checks = checks + 1
	if not ok then failures[#failures + 1] = label .. (detail and (" -- " .. detail) or "") end
	print(string.format("  %s %s%s", ok and "ok  " or "FAIL", label,
		(not ok and detail) and (" -- " .. detail) or ""))
end

local BUILT_IN = stub.newScreen("Built-in Retina Display", "built-in", 0, 0, 1512, 982)
local EXTERNAL = stub.newScreen("DELL U2720Q", "external", 1512, -300, 2560, 1440)

local function boot(screens)
	local hs, state = stub.build({ screens = screens })
	_G.hs = hs
	local obj = dofile(SPOON_DIR .. "/init.lua")
	obj:init()
	return obj, state
end

local function setFor(obj, view)
	return obj:debugState().canvas_sets[view] or {}
end

local function elementCount(canvas)
	return canvas:elementCount()
end

--- Every element must land inside the canvas: the calendar is laid out in
--- absolute points and sized to its content, so nothing may stick out.
local function checkFits(canvas, label)
	local f = canvas:frame()
	local over, worst, worst_el = 0, 0, "-"
	for i = 1, canvas:elementCount() do
		local e = canvas[i]
		if e and e.frame then
			local r = canvas:resolvedFrame(i)
			local past = math.max(r.x + r.w - f.w, r.y + r.h - f.h, -r.x, -r.y)
			if past > 0.5 then over = over + 1 end
			if past > worst then worst, worst_el = past, tostring(e.text or e.type) end
		end
	end
	check(over == 0, label .. ": every element fits inside the canvas",
		string.format("%d outside, worst %.1fpt past the edge (%s)", over, worst, worst_el))
end

--- The pill must always be the designed size (it used to be squashed whenever a
--- month needed fewer than six week rows, so a 16pt number overflowed it).
local function checkTodayMarker(canvas, label)
	local elems = {}
	for i = 1, canvas:elementCount() do elems[i] = canvas[i] end
	local pills = {}
	for _, e in ipairs(elems) do
		if e.type == "rectangle" and e.action == "fill" and e.fillColor and e.fillColor.hex == "#78FF78" then
			pills[#pills + 1] = e
		end
	end
	check(#pills == 1, label .. ": exactly one today pill", "found " .. #pills)
	if #pills ~= 1 then return end
	local pill = pills[1]
	local f = canvas:frame()
	-- resolve the pill frame (points here)
	local pcx = pill.frame.x + pill.frame.w / 2
	local pcy = pill.frame.y + pill.frame.h / 2
	check(math.abs(pill.frame.h - 18.9) < 0.2 and math.abs(pill.frame.w - 22) < 0.2,
		label .. ": today pill is the designed size",
		string.format("%.1fx%.1f", pill.frame.w, pill.frame.h))

	local under
	for _, e in ipairs(elems) do
		if e.type == "text" and tostring(e.text) == tostring(today.day) and e.frame then
			local cx = e.frame.x + e.frame.w / 2
			local cy = e.frame.y + e.frame.h / 2
			if math.abs(cx - pcx) < 0.05 and math.abs(cy - pcy) < 0.05 then under = e end
		end
	end
	check(under ~= nil, label .. ": pill sits exactly under a day number")
	if under then
		check(under.textColor and under.textColor.hex == "#1B1B1B",
			label .. ": today's digit is dark ink on the pill",
			under.textColor and tostring(under.textColor.hex))
	end
end

--- Every cell of every month block must show the day number that belongs there,
--- and nothing where the month has no day (a stale number is a real bug: the
--- window rolls over once a month and the block it reuses can be shorter).
local function checkGrid(entry, months, label)
	local view = entry.view
	local wrong, total = 0, 0
	for i, m in ipairs(months) do
		local block = view.blocks[i]
		if not block then
			check(false, label .. ": block " .. i .. " exists")
			return
		end
		local rows = monthRows(m.year, m.month)
		if block.rows ~= rows then
			wrong = wrong + 1
			print(string.format("       %04d-%02d: block built for %s rows, needs %d",
				m.year, m.month, tostring(block.rows), rows))
		end
		for row = 0, 5 do
			for col = 0, 6 do
				total = total + 1
				local cell = row * 7 + col + 1
				local el = block.days[cell]
				local got = el and el.text or nil
				local want = expectedDay(m.year, m.month, row, col)
				local ok
				if want then
					ok = got ~= nil and tostring(got) == tostring(want)
				else
					ok = (got == nil or got == "")   -- no cell, or a blank one
				end
				if not ok then
					wrong = wrong + 1
					if wrong <= 3 then
						print(string.format("       %04d-%02d r%d c%d: want %s, got %s",
							m.year, m.month, row, col, want and tostring(want) or "(blank)",
							got == nil and "(no cell)" or tostring(got)))
					end
				end
			end
		end
	end
	check(wrong == 0, label .. ": grid content matches for all " .. #months .. " month(s)",
		wrong .. " wrong of " .. total)
end

-- ------------------------------------------------------------------ scenarios ---
print(string.format("== single screen, today = %04d-%02d-%02d ==", today.year, today.month, today.day))
local obj = boot({ BUILT_IN })

local three = setFor(obj, "3month")
check(#three == 1, "3-month: one canvas per screen", "got " .. #three)
local f3 = three[1].canvas:frame()
check(f3.x == MARGIN and f3.y + f3.h == 982 - MARGIN,
	"3-month: bottom-left anchored inside its screen (20pt margin)",
	string.format("%.0f,%.0f %.0fx%.0f", f3.x, f3.y, f3.w, f3.h))
check(three[1].canvas._visible == true, "3-month: shown at startup")
check(elementCount(three[1].canvas) == expectedElements(windowMonths()),
	"3-month: element count (only the rows each month needs)",
	tostring(elementCount(three[1].canvas)) .. " vs " .. expectedElements(windowMonths()))
print(string.format("  (3-month canvas %.0fx%.0f, %d elements)", f3.w, f3.h, elementCount(three[1].canvas)))
checkTodayMarker(three[1].canvas, "3-month")
checkGrid(three[1], windowMonths(), "3-month")
checkFits(three[1].canvas, "3-month")

print("# year view")
obj:switchTo("year")
local year = setFor(obj, "year")
check(#year == 1, "year: one canvas per screen", "got " .. #year)
local fy = year[1].canvas:frame()
check(fy.x == MARGIN and fy.y + fy.h == 982 - MARGIN, "year: bottom-left anchored inside its screen",
	string.format("%.0f,%.0f %.0fx%.0f", fy.x, fy.y, fy.w, fy.h))
check(year[1].canvas._visible == true, "year: shown after switch")
check(three[1].canvas._visible == false, "switch: 3-month hidden")
check(elementCount(year[1].canvas) == expectedElements(yearMonths()),
	"year: element count (only the rows each month needs)",
	tostring(elementCount(year[1].canvas)) .. " vs " .. expectedElements(yearMonths()))
checkTodayMarker(year[1].canvas, "year")
checkGrid(year[1], yearMonths(), "year")
checkFits(year[1].canvas, "year")

obj:toggleView()
check(obj:debugState().view_mode == "3month", "toggle switches back to the 3-month view")

print("# month rollover")
-- Advance one month: the window shifts, and the first block now shows a month
-- that may need fewer week rows than the one it replaced.
local next_month, next_year = today.month + 1, today.year
if next_month > 12 then next_month, next_year = 1, today.year + 1 end
goTo(next_year, next_month, 1)
obj:render()
local after = setFor(obj, "3month")
check(#after == 1, "rollover: canvases still one per screen", "got " .. #after)
checkGrid(after[1], windowMonths(), "rollover")
checkTodayMarker(after[1].canvas, "rollover")

-- ----------------------------------------------------------------- 2 screens ---
print("== two screens ==")
goTo(tonumber(os.getenv("DATE_Y") or now.year), tonumber(os.getenv("DATE_M") or now.month), tonumber(os.getenv("DATE_D") or now.day))
local obj2, state2 = boot({ BUILT_IN, EXTERNAL })
local three2 = setFor(obj2, "3month")
check(#three2 == 2, "two screens: two 3-month canvases", "got " .. #three2)
local placed = {}
for _, entry in ipairs(three2) do placed[entry.id] = entry.canvas:frame() end
check(placed["built-in"] and placed["built-in"].x == MARGIN and placed["built-in"].y + placed["built-in"].h == 982 - MARGIN,
	"primary screen: anchored to its own bottom-left corner",
	placed["built-in"] and string.format("%.0f,%.0f", placed["built-in"].x, placed["built-in"].y))
check(placed["external"] and placed["external"].x == 1512 + MARGIN
	and placed["external"].y + placed["external"].h == 1440 - 300 - MARGIN,
	"second screen: anchored to its own bottom-left corner",
	placed["external"] and string.format("%.0f,%.0f", placed["external"].x, placed["external"].y))
check(placed["built-in"].w == placed["external"].w and placed["built-in"].h == placed["external"].h,
	"both screens: same canvas size")
check(three2[1].canvas._visible and three2[2].canvas._visible, "both screens shown")

print("# display change is followed")
state2.setScreens({ BUILT_IN })
state2.fireAfterTimers()
local after_unplug = setFor(obj2, "3month")
check(#after_unplug == 1, "unplug: canvases rebuilt for the screens that remain", "got " .. #after_unplug)
check(after_unplug[1].canvas._deleted ~= true, "unplug: the surviving canvas is live")
check(three2[2].canvas._deleted == true, "unplug: the removed screen's canvas is deleted")

state2.setScreens({ BUILT_IN, EXTERNAL })
state2.fireAfterTimers()
check(#setFor(obj2, "3month") == 2, "replug: canvases rebuilt for both screens again")

print("")
print(string.format("%d checks, %d failure(s)", checks, #failures))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(#failures == 0 and 0 or 1)
