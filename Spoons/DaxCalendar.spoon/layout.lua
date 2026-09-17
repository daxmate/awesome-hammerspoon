--- === Layout ===
---
--- Everything that defines how the calendar looks: colours, sizes and the shape
--- of the two views, plus the geometry planner that turns "these months" into
--- "this canvas, these block positions".
---
--- All values are points and every position is absolute, so a canvas is created
--- exactly as large as its content and nothing has to be scaled or clipped.
--- (The previous version positioned everything as fractions of a nominal box
--- and then trimmed the canvas height, which silently squashed the grid.)

local M = {}

-- ----------------------------------------------------------------- palette ---
local day_ink = { red = 235 / 255, blue = 235 / 255, green = 235 / 255 }

M.color = {
	day     = day_ink,                    -- normal day number / title / captions
	weekend = { hex = "#FF7878" },        -- 周六 / 周日
	holiday = { hex = "#FFB800" },        -- Chinese holiday
	japan   = { hex = "#4FC3F7" },        -- Japanese holiday
	workday = { hex = "#9AA7B8" },        -- 调休补班 (weekend that is a workday)
	badge   = { hex = "#1B1B1B" },        -- dark glyph on a coloured badge / today circle
	today   = { hex = "#78FF78" },        -- today circle
	header  = { hex = "#78FF78" },        -- weekday header + view toggle
	weeknum = { red = 246 / 255, blue = 246 / 255, green = 246 / 255, alpha = 0.5 },
	panel   = { red = 0, blue = 0, green = 0, alpha = 0.3 },
}

-- ---------------------------------------------------------------- geometry ---
M.pad          = 10                          -- content inset inside the canvas
M.cal_w        = 260                         -- width of one month block
M.cell_w       = (M.cal_w - 2 * M.pad) / 8   -- 30pt: week-number column + 日..六
M.cell_h       = 550 / 24                    -- 22.9pt: a title / weekday / day row
M.block_gap    = 8                           -- vertical space between month blocks
M.legend_h     = 26                          -- legend strip below the grid
M.max_rows     = 6                           -- no month needs more than 6 week rows
M.months       = 3                           -- months in the compact window view
M.panel_radius = 10
M.margin       = 20                          -- canvas inset from the screen corner
M.font         = { title = 16, weekday = 12, day = 16, weeknum = 16, label = 7 }

-- Today marker: a filled circle behind the day number, with the number drawn on
-- top of it in dark ink. A circle, not a capsule: radius 10pt fits inside a
-- 22.9pt day cell with a small margin, and its 20pt width still holds a
-- two-digit 16pt number.
--
-- hs.canvas draws text DOWN FROM THE FRAME'S TOP (it has no vertical alignment),
-- so a 16pt number's ink centre sits ~8.6pt below the top of its cell -- about
-- 3pt ABOVE the cell's own centre (the same effect badge.y_adjust compensates
-- for). The circle is centred on that ink, so the number looks centred in it.
M.today = { radius = 10, ink_offset = 0.54 * M.font.day }

-- 休 / 班 badge geometry, measured against the 16pt day digits.
M.badge = {
	radius   = 4.6,   -- badge ⌀9.2pt; clears the day digits
	margin_x = 5.4,   -- centre distance from the cell's right edge
	margin_y = 5.0,   -- centre distance from the cell's top edge
	box_w    = 16,
	box_h    = 12,
	day_shift = 3.0,  -- badge cells: nudge the day number left so it never clips
	-- hs.canvas draws text DOWN FROM THE FRAME'S TOP (not vertically centred),
	-- so a label box centred on the badge renders ~1.5pt too high. Measured from
	-- a real screenshot (30 badges): ink centre sat 3.77pt below the frame top.
	y_adjust = 2.0,
}

M.legend = {
	radius = 5.5,
	text_size = 8,
	gap = 12,             -- between legend items
	disc_gap = 4,         -- between a disc and its caption
	label_box_h = 13,
	label_y_adjust = 2.2, -- same top-anchored-text correction as the badges
	items = {
		{ glyph = "休", color = M.color.holiday, text = "中国节假日" },
		{ glyph = "休", color = M.color.japan,   text = "日本节假日" },
		{ glyph = "班", color = M.color.workday, text = "调休补班" },
		{ glyph = nil,  color = M.color.weekend, text = "周末" },
	},
}

-- View toggle: a small clickable text element in the canvas' top-right corner.
-- `trackMouseDown` makes its frame the hit area (text elements track by frame).
M.toggle = { id = "cal_view_toggle", w = 56, h = 13, margin = 10, top = 4, text_size = 8 }

M.month_labels = {
	"一月", "二月", "三月", "四月", "五月", "六月",
	"七月", "八月", "九月", "十月", "十一月", "十二月",
}

-- ------------------------------------------------------------------- views ---
--- Both views are the same thing: a grid of month blocks, a legend strip and a
--- clickable toggle. `uniform` keeps every grid row as tall as a six-week month
--- (so the year grid stays aligned); otherwise each row is only as tall as its
--- months need (so the window view stays compact).
M.views = {
	["3month"] = { cols = 1, rows = M.months, uniform = false, toggle_label = "全年 ▸" },
	["year"]   = { cols = 3, rows = 4,       uniform = true,  toggle_label = "三月 ▾" },
}

-- -------------------------------------------------------------- month facts ---
--- Days in a month and the weekday of its 1st (Lua wday: 1 = Sunday).
function M.monthFacts(year, month)
	local first = os.date("*t", os.time({ year = year, month = month, day = 1 }))
	-- Day 0 of the following month is the last day of this one. Lua normalises
	-- both fields, so this covers December and leap Februaries without special
	-- cases (and without subtracting 24h, which DST could shift).
	local days = os.date("*t", os.time({ year = year, month = month + 1, day = 0 })).day
	return days, first.wday
end

--- Week rows a month needs (4..6).
function M.monthRowCount(year, month)
	local days, wday = M.monthFacts(year, month)
	return math.ceil((wday + days - 1) / 7)
end

--- The months of the compact window view: the current month in the middle.
function M.windowMonths()
	local now = os.date("*t")
	local months = {}
	for i = 1, M.months do
		local month = now.month + i - M.months // 2 - 1
		local year = now.year
		while month < 1 do month, year = month + 12, year - 1 end
		while month > 12 do month, year = month - 12, year + 1 end
		months[i] = { year = year, month = month }
	end
	return months
end

--- Height of one month block with `rows` week rows: a title row, a weekday row
--- and one row per week.
function M.blockHeight(rows)
	return M.cell_h * (rows + 2)
end

--- Frame for a canvas of `w` x `h` on `screen`, anchored to the bottom-left
--- corner of that screen. macOS' global origin is the PRIMARY display's
--- top-left and secondary screens extend that space (negative x/y included), so
--- the frame has to come from the target screen's own fullFrame() -- a canvas
--- created without one lands on the primary display.
function M.canvasFrame(screen, w, h)
	local f = screen:fullFrame()
	local y = f.y + f.h - h - M.margin
	if y < f.y + M.margin then
		y = f.y + M.margin   -- screen shorter than the calendar: pin to its top
	end
	return { x = f.x + M.margin, y = y, w = w, h = h }
end

--- Geometry for one view: canvas size, every month block's origin and the legend
--- / toggle anchors. Pure function of the view and the months it shows, so a
--- canvas can be created at its final size before a single element exists.
--- `months` is { { year =, month = }, ... } in block order.
function M.plan(view, months)
	local spec = M.views[view]
	local plan = { view = view, w = spec.cols * M.cal_w, blocks = {}, rows = {} }
	local y = M.pad
	for r = 0, spec.rows - 1 do
		local row_h = 0
		for c = 0, spec.cols - 1 do
			local i = r * spec.cols + c + 1
			local m = months[i]
			-- rows the block itself builds; a uniform grid only pads the cell
			local rows = M.monthRowCount(m.year, m.month)
			plan.rows[i] = rows
			local h = M.blockHeight(spec.uniform and M.max_rows or rows)
			if h > row_h then row_h = h end
		end
		for c = 0, spec.cols - 1 do
			plan.blocks[r * spec.cols + c + 1] = { x = c * M.cal_w, y = y, h = row_h }
		end
		y = y + row_h + M.block_gap
	end
	local grid_bottom = y - M.block_gap
	plan.h = grid_bottom + M.legend_h
	plan.legend_y = grid_bottom + M.legend_h / 2
	plan.toggle = { x = plan.w - M.toggle.margin - M.toggle.w, y = M.toggle.top }
	return plan
end

--- Signature of (months, plan): a cached canvas whose signature changed no
--- longer shows the right months and has to be rebuilt. The week rows are part
--- of it too, because the same months can need a different canvas height (and a
--- block only builds the rows it needs).
function M.planKey(months, plan)
	local parts = {}
	for i, m in ipairs(months) do
		parts[i] = string.format("%04d-%02d/%d", m.year, m.month, plan.rows[i] or 0)
	end
	for i, b in ipairs(plan.blocks) do
		parts[#parts + 1] = string.format("%.0f/%.0f", b.y, b.h)
	end
	return table.concat(parts, ",")
end

return M
