--- === Month block ===
---
--- One month of the calendar: the today circle, the month title, the weekday
--- header, the day grid, the week-number column and the 休 / 班 badges.
---
--- Elements are created once, in order (hs.canvas only accepts contiguous
--- appends), and every later update goes through the handles that build()
--- returns -- no other file has to know the element order or how many there are.
--- build() + update() are deliberately content-only: positions come from the
--- block's own origin, which the layout planner decided.

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(DIR .. "/layout.lua")

local M = {}

--- Monday-based week number of a date ("00" for days before the year's first
--- Monday). Identical to BSD `date +%W` (verified against it for 2024-2028
--- including year boundaries) but computed in-process -- the previous code
--- spawned a `date` subprocess for every calendar row (72 per year render).
local function weekNumberOf(year, month, day)
	return tonumber(os.date("%W", os.time({ year = year, month = month, day = day, hour = 12 })))
end

--- Centre of the badge circle of the cell at (col, row), both 0-based. A day
--- cell spans x + pad + cell_w*(col+1) .. +cell_w, so the badge hugs its right
--- edge (margin_x from it) and its top edge (margin_y from it).
local function badgeCenter(x, y, col, row)
	return {
		x = x + L.pad + L.cell_w * (col + 2) - L.badge.margin_x,
		y = y + L.cell_h * (row + 2) + L.badge.margin_y,
	}
end

--- Create a month block's elements at (x, y) -- the block's content top-left
--- corner -- and return handles to everything update() needs. Only the `rows`
--- week rows the month actually needs are created, so a block never holds
--- elements that would fall outside the canvas it lives on.
function M.build(canvas, x, y, rows)
	local function add(el)
		canvas[canvas:elementCount() + 1] = el
		return canvas[canvas:elementCount()]
	end

	local block = { x = x, y = y, rows = rows, days = {}, badges = {}, labels = {}, weeknums = {}, weekdays = {} }

	-- today marker: a filled circle behind today's number, positioned on the
	-- first cell by default and moved by update(). It is the block's first element,
	-- i.e. before the digits, so the number lands on top of it.
	block.today = add({
		type = "circle",
		action = "skip",
		radius = L.today.radius,
		center = {
			x = x + L.pad + L.cell_w * 1.5,
			y = y + L.cell_h * 2.5,
		},
		fillColor = L.color.today,
	})

	block.title = add({
		id = "cal_title",
		type = "text",
		text = "",
		textFont = "Courier",
		textSize = L.font.title,
		textColor = L.color.day,
		textAlignment = "center",
		frame = { x = x + L.pad, y = y, w = L.cal_w - 2 * L.pad, h = L.cell_h },
	})

	for i = 1, 7 do
		block.weekdays[i] = add({
			id = "cal_weekday",
			type = "text",
			text = ({ "日", "一", "二", "三", "四", "五", "六" })[i],
			textFont = "Courier",
			textSize = L.font.weekday,
			textColor = L.color.header,
			textAlignment = "center",
			frame = { x = x + L.pad + L.cell_w * i, y = y + L.cell_h, w = L.cell_w, h = L.cell_h },
		})
	end

	for row = 0, rows - 1 do
		for col = 0, 6 do
			block.days[row * 7 + col + 1] = add({
				type = "text",
				text = "",
				textFont = "Courier",
				textSize = L.font.day,
				textColor = (col == 0 or col == 6) and L.color.weekend or L.color.day,
				textAlignment = "center",
				frame = {
					x = x + L.pad + L.cell_w * (col + 1),
					y = y + L.cell_h * (row + 2),
					w = L.cell_w,
					h = L.cell_h,
				},
			})
		end
	end

	for i = 1, rows do
		block.weeknums[i] = add({
			type = "text",
			text = "",
			textFont = "Courier",
			textSize = L.font.weeknum,
			textColor = L.color.weeknum,
			textAlignment = "center",
			frame = { x = x + L.pad, y = y + L.cell_h * (i + 1), w = L.cell_w, h = L.cell_h },
		})
	end

	-- badges first, then their 休 / 班 labels on top
	for row = 0, rows - 1 do
		for col = 0, 6 do
			local center = badgeCenter(x, y, col, row)
			block.badges[row * 7 + col + 1] = add({
				type = "circle",
				action = "skip",   -- update() shows it on holiday / workday cells
				radius = L.badge.radius,
				center = { x = center.x, y = center.y },
				fillColor = L.color.holiday,
			})
		end
	end

	for row = 0, rows - 1 do
		for col = 0, 6 do
			local center = badgeCenter(x, y, col, row)
			block.labels[row * 7 + col + 1] = add({
				type = "text",
				text = "",
				textFont = "Courier",
				textSize = L.font.label,
				textColor = L.color.badge,
				textAlignment = "center",
				frame = {
					x = center.x - L.badge.box_w / 2,
					y = center.y - L.badge.box_h / 2 + L.badge.y_adjust,
					w = L.badge.box_w,
					h = L.badge.box_h,
				},
			})
		end
	end

	return block
end

--- Fill the block in for `ctx.month` of `ctx.year`: title, day numbers with
--- their holiday / weekend colour, 休 / 班 badges, week numbers and today's circle.
---
--- Every cell is written on every pass, empty ones included, so a month that
--- needs fewer rows than the month it replaced cannot leave stale numbers
--- behind (the window view rolls over once a month).
function M.update(block, ctx)
	local days, first_wday = L.monthFacts(ctx.year, ctx.month)
	local rows = math.ceil((first_wday + days - 1) / 7)
	local today = ctx.today
	local holidays = ctx.holidays
	local is_current_month = (ctx.year == today.year and ctx.month == today.month)

	block.title.text = string.format("%d年 %s", ctx.year, L.month_labels[ctx.month])
	block.today.action = "skip"

	for row = 0, block.rows - 1 do
		for col = 0, 6 do
			local cell = row * 7 + col + 1
			-- col 0 = Sunday column, col 6 = Saturday column
			local day_num = row * 7 + col - first_wday + 2
			local day_el, badge_el, label_el = block.days[cell], block.badges[cell], block.labels[cell]
			if row >= rows or day_num < 1 or day_num > days then
				day_el.text = ""
				label_el.text = ""
				badge_el.action = "skip"
			else
				day_el.text = day_num
				-- Priority: Chinese holiday > 调休补班 > Japanese holiday > weekend
				local is_holiday, holiday_data = holidays:isHoliday(ctx.year, ctx.month, day_num)
				local is_workday, workday_data = holidays:isWorkday(ctx.year, ctx.month, day_num)
				local is_jp, jp_data = holidays:isJapaneseHoliday(ctx.year, ctx.month, day_num)
				local label_text, badge_color
				if is_holiday then
					day_el.textColor = L.color.holiday
					label_text, badge_color = holiday_data.abbr or "休", L.color.holiday
				elseif is_workday then
					-- 调休补班：数字用正常工作日的颜色，角标「班」提示这天要上班
					day_el.textColor = L.color.day
					label_text, badge_color = workday_data.abbr or "班", L.color.workday
				elseif is_jp then
					day_el.textColor = L.color.japan
					label_text, badge_color = jp_data.abbr or "休", L.color.japan
				elseif col == 0 or col == 6 then
					day_el.textColor = L.color.weekend
				else
					day_el.textColor = L.color.day
				end
				if label_text then
					badge_el.action = "fill"
					badge_el.fillColor = badge_color
					label_el.text = label_text
				else
					badge_el.action = "skip"
					label_el.text = ""
				end
				-- 有角标时把日期数字左移一点，避免被圆底压住
				local shift = label_text and L.badge.day_shift or 0
				day_el.frame.x = block.x + L.pad + L.cell_w * (col + 1) - shift
				if is_current_month and day_num == today.day then
					-- 今天：亮色圆点画在数字下面（与数字同幅左移，保证数字在圆里居中），
					-- 数字换成深色墨水，对比度拉满
					block.today.action = "fill"
					block.today.center = {
						x = block.x + L.pad + L.cell_w * (col + 1.5) - shift,
						y = block.y + L.cell_h * (row + 2.5),
					}
					day_el.textColor = L.color.badge
				end
			end
		end
	end

	-- week numbers: %W of the Monday of each grid row (column 一 = Monday), the
	-- same number Apple Calendar shows in zh_CN. Rows without a Monday fall back
	-- to their first day in the month.
	for i = 1, block.rows do
		local value
		if i <= rows then
			local monday = 7 * (i - 1) + 2 - first_wday + 1
			local ref_day
			if monday >= 1 and monday <= days then
				ref_day = monday
			else
				ref_day = math.max(7 * (i - 1) - first_wday + 2, 1)
			end
			value = weekNumberOf(ctx.year, ctx.month, ref_day)
		end
		block.weeknums[i].text = value or ""
	end
end

return M
