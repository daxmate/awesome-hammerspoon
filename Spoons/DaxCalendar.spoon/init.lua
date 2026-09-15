--- === Calendar ===
---
--- A calendar inset into the desktop
---
--- Download: [https://github.com/Hammerspoon/Spoons/raw/master/Spoons/Calendar.spoon.zip](https://github.com/Hammerspoon/Spoons/raw/master/Spoons/Calendar.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Calendar"
obj.version = "1.0"
obj.author = "ashfinal <ashfinal@gmail.com>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Load Chinese holidays module
local holidays = dofile(hs.configdir .. "/Spoons/DaxCalendar.spoon/holidays.lua"):load()

-- Calendar color palette (shared by init and updateCalCanvas)
local calcolor              = { red = 235/255, blue = 235/255, green = 235/255 }
local weekend_color         = { hex = "#FF7878" }
local holiday_color         = { hex = "#FFB800" }   -- bright amber/gold, distinct from weekend pink-red
local japan_holiday_color   = { hex = "#4FC3F7" }   -- sky blue, distinct from both
local workday_color         = { hex = "#9AA7B8" }   -- slate blue-grey: 调休补班 (weekend that is a workday)
local badge_text_color      = { hex = "#1B1B1B" }   -- dark glyph on top of the coloured badge

-- Badge circle geometry (canvas points)
local BADGE_RADIUS   = 4.6   -- badge ⌀9.2pt; measured to clear the 16pt day digits
local BADGE_MARGIN_X = 5.4   -- centre distance from the cell's right edge
local BADGE_MARGIN_Y = 5.0   -- centre distance from the cell's top edge
local LABEL_BOX_W    = 16
local LABEL_BOX_H    = 12
local DAY_NUMBER_SHIFT = 3.0 -- badge cells: nudge the day number left so the badge never clips it
-- hs.canvas draws text DOWN FROM THE FRAME'S TOP (not vertically centred), so a
-- label box centred on the badge renders ~1.5pt too high. Measured from a real
-- screenshot (30 badges): ink centre sat 3.77pt below the frame top for 7pt text.
local LABEL_Y_ADJUST  = 2.0

-- Legend strip drawn below the grid
local LEGEND_H              = 26    -- nominal height of the strip
local LEGEND_RADIUS         = 5.5
local LEGEND_TEXT_SIZE      = 8
local LEGEND_GAP            = 12    -- between legend items
local LEGEND_DISC_GAP       = 4     -- between a disc and its caption
local LEGEND_LABEL_BOX_H    = 13
local LEGEND_LABEL_Y_ADJUST = 2.2   -- same top-anchored-text correction as above

-- Per-month canvas element block layout (index bases inside one month block):
--   1                         : background rectangle
--   2                         : month title
--   3 .. 9                    : weekday header
--   10 .. 51                  : day numbers
--   52 .. 57                  : week numbers
--   58 .. 99                  : holiday / workday badge circles
--   100 .. 141                : holiday / workday labels (休 / 班)
--   142                       : today highlight (the block's last index)
-- NOTE: hs.canvas only accepts contiguous appends (index <= elementCount()+1),
-- so a block must create every index in order, with no gaps.
local MONTH_BLOCK = 142
local IDX_BADGE_BASE = 57
local IDX_LABEL_BASE = 99

obj.calw = 260
obj.months = 3
obj.calh = 190 * obj.months
obj.cellw = (obj.calw - 20) / 8
obj.cellh = (obj.calh - 20) / 8 / obj.months
-- Nominal height = grid + legend strip. Every vertical position is a fraction
-- of TOTAL_H and the canvas is sized to content_h / calh * TOTAL_H, which keeps
-- the grid at its usual proportions and puts the legend in the extra strip.
local TOTAL_H = obj.calh + LEGEND_H
-- Holiday label font size (overlaid at top-left of date cells)
local LABEL_FONT_SIZE = 7

-- Canvas-scoped colours (hoisted out of init() so both views share them)
local calbgcolor         = { red = 0, blue = 0, green = 0, alpha = 0.3 }
local cal_transparent_bg = { red = 0, blue = 0, green = 0, alpha = 0 }
local caltodaycolor      = { red = 1, blue = 1, green = 1, alpha = 0.3 }
local cal_header_color   = { hex = "#78FF78" }
local weeknumcolor       = { red = 246 / 255, blue = 246 / 255, green = 246 / 255, alpha = 0.5 }

-- View modes: obj.view_mode holds one of these
local VIEW_3MONTH = "3month"
local VIEW_YEAR   = "year"

-- ---- year view geometry: 12 mini months in 3 columns x 4 rows -------------
-- A mini month is one small title line plus up to 6 rows of day numbers.
-- No 休/班 badges, no week-number column and no weekday header row: there is
-- no room for them at this scale.
local YEAR_COLS        = 3
local YEAR_ROWS        = 4
local MINI_W           = (obj.calw - 20) / YEAR_COLS    -- ~80pt
local MINI_TITLE_H     = 12
local MINI_CELL_H      = 11
local MINI_CELL_W      = MINI_W / 7                     -- ~11.4pt
local MINI_BODY_H      = 6 * MINI_CELL_H
local MINI_H           = MINI_TITLE_H + MINI_BODY_H     -- ~78pt
-- Top strip: room for the clickable view toggle in the canvas' top-right corner
local YEAR_TOP         = 22
local YEAR_ROW_GAP     = 6
local YEAR_GRID_BOTTOM = YEAR_TOP + YEAR_ROWS * MINI_H + (YEAR_ROWS - 1) * YEAR_ROW_GAP
local YEAR_TOTAL_H     = YEAR_GRID_BOTTOM + LEGEND_H    -- grid + legend strip
local MINI_TITLE_SIZE  = 8
local MINI_DAY_SIZE    = 8
-- Per-mini-month element block (index base inside the block):
--   1        : title line
--   2 .. 43  : day numbers (6 rows x 7 cols)
--   44       : today highlight (the block's last index)
local MINI_BLOCK       = 44

-- View-toggle label: a small clickable text element in the canvas' top-right
-- corner. `trackMouseDown` makes its frame the hit area (text elements track by
-- frame -- see hs.canvas docs); the click is handled in createCanvas().
local TOGGLE_ID        = "cal_view_toggle"
local TOGGLE_W         = 56
local TOGGLE_H         = 13
local TOGGLE_MARGIN    = 10    -- from the canvas' right edge
local TOGGLE_TOP       = 4
local TOGGLE_TEXT_SIZE = 8
local TOGGLE_LABELS    = {
	[VIEW_3MONTH] = "全年 ▸",
	[VIEW_YEAR]   = "三月 ▾",
}

-- Legend items, shared by both views
local LEGEND_ITEMS = {
	{ glyph = "休", color = holiday_color,       text = "中国节假日" },
	{ glyph = "休", color = japan_holiday_color, text = "日本节假日" },
	{ glyph = "班", color = workday_color,       text = "调休补班" },
	{ glyph = nil,  color = weekend_color,       text = "周末" },
}

local function sunday_first_weekday(date)
	local wday = date.wday
	if wday == 7 then
		return 1
	else
		return wday + 1
	end
end

--- Canvas-point centre of a cell's badge circle
local function cellBadgeCenter(col, row, month_index)
	local offset = obj.calh / obj.months
	return {
		x = 10 + obj.cellw * (col + 1) - BADGE_MARGIN_X,
		y = 10 + obj.cellh * (row + 1) + BADGE_MARGIN_Y + offset * (month_index - 1),
	}
end

--- Canvas coordinates are given as decimal fractions (1.0 = 100%%)
local function frac(value, total)
	return tostring(value / total)
end

--- Approximate rendered width of a CJK caption (full-width glyphs)
local function textWidth(str, size)
	local n = utf8 and utf8.len and utf8.len(str)
	return (n or #str) * size
end

--- Append the legend strip to `canvas` starting after index `start_idx`.
--- `legend_y` is the strip's centre in canvas points and `total_h` the
--- denominator the y fractions resolve against (calh + LEGEND_H for the
--- 3-month view, YEAR_TOTAL_H for the year view). Returns the last index used.
local function drawLegend(canvas, start_idx, legend_y, total_h)
	local items = {}
	local legend_w = LEGEND_GAP * (#LEGEND_ITEMS - 1)
	for i = 1, #LEGEND_ITEMS do
		local src = LEGEND_ITEMS[i]
		local item = { glyph = src.glyph, color = src.color, text = src.text }
		item.text_w = textWidth(item.text, LEGEND_TEXT_SIZE)
		item.w = 2 * LEGEND_RADIUS + LEGEND_DISC_GAP + item.text_w
		legend_w = legend_w + item.w
		items[i] = item
	end
	local legend_x = (obj.calw - legend_w) / 2
	local legend_idx = start_idx
	for _, item in ipairs(items) do
		item.disc_cx = legend_x + LEGEND_RADIUS
		item.text_x = legend_x + 2 * LEGEND_RADIUS + LEGEND_DISC_GAP
		legend_idx = legend_idx + 1
		canvas[legend_idx] = {
			type = "circle",
			action = "fill",
			radius = LEGEND_RADIUS,
			center = { x = frac(item.disc_cx, obj.calw), y = frac(legend_y, total_h) },
			fillColor = item.color,
		}
		if item.glyph then
			legend_idx = legend_idx + 1
			canvas[legend_idx] = {
				type = "text",
				text = item.glyph,
				textFont = "Courier",
				textSize = LABEL_FONT_SIZE,
				textColor = badge_text_color,
				textAlignment = "center",
				frame = {
					x = frac(item.disc_cx - LABEL_BOX_W / 2, obj.calw),
					y = frac(legend_y - LABEL_BOX_H / 2 + LABEL_Y_ADJUST, total_h),
					w = frac(LABEL_BOX_W, obj.calw),
					h = frac(LABEL_BOX_H, total_h),
				},
			}
		end
		legend_x = legend_x + item.w + LEGEND_GAP
	end
	for _, item in ipairs(items) do
		legend_idx = legend_idx + 1
		canvas[legend_idx] = {
			type = "text",
			text = item.text,
			textFont = "Courier",
			textSize = LEGEND_TEXT_SIZE,
			textColor = calcolor,
			textAlignment = "left",
			frame = {
				x = frac(item.text_x, obj.calw),
				y = frac(legend_y - LEGEND_LABEL_BOX_H / 2 + LEGEND_LABEL_Y_ADJUST, total_h),
				w = frac(item.text_w + 6, obj.calw),
				h = frac(LEGEND_LABEL_BOX_H, total_h),
			},
		}
	end
	return legend_idx
end

--- Append the clickable view-toggle label (canvas' top-right corner). It is
--- the LAST element of both views, so the canvas indices stay contiguous.
local function drawViewToggle(canvas, index, total_h, mode)
	local i = index + 1
	canvas[i] = {
		id = TOGGLE_ID,
		type = "text",
		text = TOGGLE_LABELS[mode],
		textFont = "Courier",
		textSize = TOGGLE_TEXT_SIZE,
		textColor = cal_header_color,
		textAlignment = "right",
		trackMouseDown = true,   -- frame == hit area for text elements
		frame = {
			x = frac(obj.calw - TOGGLE_MARGIN - TOGGLE_W, obj.calw),
			y = frac(TOGGLE_TOP, total_h),
			w = frac(TOGGLE_W, obj.calw),
			h = frac(TOGGLE_H, total_h),
		},
	}
	obj.toggle_idx = i
	return i
end

local function updateCalCanvas()
	local offset = obj.calh / obj.months
	local chinese_months = {
		"一月",
		"二月",
		"三月",
		"四月",
		"五月",
		"六月",
		"七月",
		"八月",
		"九月",
		"十月",
		"十一月",
		"十二月",
	}
	local current_date = os.date("*t")
	local current_year = current_date.year
	local current_month = current_date.month
	local current_day = current_date.day

	for month_index = 1, obj.months do
		local month_diff = month_index - obj.months // 2 - 1
		local month = current_month + month_diff
		local year = month < 1 and current_year - 1 or month > 12 and current_year + 1 or current_year
		month = (month + 12) % 12
		if month == 0 then
			month = 12
		end
		local next_month = (month + 1) % 12
		local firstday_of_next_month = os.time({ year = year, month = next_month, day = 1 })
		local maxday_of_month = os.date("*t", firstday_of_next_month - 24 * 60 * 60).day
		local title_string = tostring(year) .. "年" .. " " .. chinese_months[month]
		local weekday_of_firstday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
		local needed_rownum = math.ceil((weekday_of_firstday + maxday_of_month - 1) / 7)
		obj.canvas[2 + (month_index - 1) * MONTH_BLOCK].text = title_string

		for row_i = 1, needed_rownum do
			for col_i = 1, 7 do
				-- col_i: 1=Sunday col, 2=Monday, ..., 7=Saturday
				-- Lua wday: 1=Sunday, ..., 7=Saturday
				local day_number = 7 * (row_i - 1) + col_i - weekday_of_firstday + 1
				local caltable_idx = 7 * (row_i - 1) + col_i + (month_index - 1) * MONTH_BLOCK
				if day_number <= 0 or day_number > maxday_of_month then
					obj.canvas[9 + caltable_idx].text = ""
					obj.canvas[IDX_LABEL_BASE + 7 * (row_i - 1) + col_i + (month_index - 1) * MONTH_BLOCK].text = ""
					obj.canvas[IDX_BADGE_BASE + 7 * (row_i - 1) + col_i + (month_index - 1) * MONTH_BLOCK].action = "skip"
				else
					obj.canvas[9 + caltable_idx].text = day_number
					-- Apply holiday / weekend coloring
					-- Priority: Chinese holiday > 调休补班 > Japanese holiday > weekend > normal
					local isHol, holData = holidays:isHoliday(year, month, day_number)
					local isWork, workData = holidays:isWorkday(year, month, day_number)
					local isJpHol, jpHolData = holidays:isJapaneseHoliday(year, month, day_number)
					-- Badge circle + label (indexes must match the ones created in init())
					local badge_idx = IDX_BADGE_BASE + 7 * (row_i - 1) + col_i + (month_index - 1) * MONTH_BLOCK
					local label_idx = IDX_LABEL_BASE + 7 * (row_i - 1) + col_i + (month_index - 1) * MONTH_BLOCK
					local label_text, badge_color
					if isHol then
						obj.canvas[9 + caltable_idx].textColor = holiday_color
						label_text, badge_color = holData.abbr or "休", holiday_color
					elseif isWork then
						-- 调休补班：数字用正常工作日的颜色，角标"班"提示这天要上班
						obj.canvas[9 + caltable_idx].textColor = calcolor
						label_text, badge_color = workData.abbr or "班", workday_color
					elseif isJpHol then
						obj.canvas[9 + caltable_idx].textColor = japan_holiday_color
						label_text, badge_color = jpHolData.abbr or "休", japan_holiday_color
					elseif col_i == 1 or col_i == 7 then
						obj.canvas[9 + caltable_idx].textColor = weekend_color
					else
						obj.canvas[9 + caltable_idx].textColor = calcolor
					end
					if label_text then
						-- 圆圈底色取原文字色，文字换成反差色
						obj.canvas[badge_idx].action = "fill"
						obj.canvas[badge_idx].fillColor = badge_color
						obj.canvas[label_idx].text = label_text
					else
						obj.canvas[badge_idx].action = "skip"
						obj.canvas[label_idx].text = ""
					end
					-- 有角标时把日期数字左移一点，避免被圆底压住（实测 3pt 即可完全不遮挡）
					local day_shift = label_text and DAY_NUMBER_SHIFT or 0
					obj.canvas[9 + caltable_idx].frame.x = frac(10 + obj.cellw * col_i - day_shift, obj.calw)
				end
				if month == current_month and day_number == current_day then
					-- col_i maps directly to canvas column (1=Sun, 7=Sat)
					obj.canvas[MONTH_BLOCK * month_index].frame.x = tostring((10 + obj.cellw * col_i) / obj.calw)
					obj.canvas[MONTH_BLOCK * month_index].frame.y =
						tostring((10 + obj.cellh * (row_i + 1) + offset * (month_index - 1)) / TOTAL_H)
				elseif month ~= current_month then
					obj.canvas[MONTH_BLOCK * month_index].fillColor = { red = 0, blue = 0, green = 0, alpha = 0 }
				end
			end
		end
		-- update yearweek
		-- For each grid row, compute the week number (%W) of the Monday (column 2 = 一).
		-- %W = Monday-based, first Monday of January = W01 (same as Apple Calendar in zh_CN).
		for i = 1, 6 do
			local yearweek_rowvalue
			if i <= needed_rownum then
				-- Grid columns: 1=日(Sun), 2=一(Mon), ..., 7=六(Sat)
				-- Day number at (row_i, col_2): 7*(i-1) + 2 - weekday_of_firstday + 1
				local monday_day = 7 * (i - 1) + 2 - weekday_of_firstday + 1
				local ref_day
				if monday_day >= 1 and monday_day <= maxday_of_month then
					ref_day = monday_day
				else
					-- Row has no Monday (e.g. row starts Tue-Sat); use its first day instead
					ref_day = 7 * (i - 1) - weekday_of_firstday + 2
					if ref_day < 1 then ref_day = 1 end
				end
				local date_str = string.format("%d-%02d-%02d", year, month, ref_day)
				local week_str = hs.execute("date -j -f '%Y-%m-%d' '" .. date_str .. "' +'%W'")
				yearweek_rowvalue = math.tointeger(week_str)
			end
			obj.canvas[51 + i + (month_index - 1) * MONTH_BLOCK].text = yearweek_rowvalue or ""
		end
		-- trim the canvas: the grid plus the legend strip below it
		local content_h = 20 + (obj.calh - 20) / 8 * (needed_rownum + 2)
		obj.canvas:size({
			w = obj.calw,
			h = content_h / obj.calh * TOTAL_H,
		})
	end
end

--- Create the canvas window sized to `height` points, showing on all spaces at
--- the desktop-icon level. A fresh canvas is created per rebuild because
--- hs.canvas elements can only be appended contiguously.
local function createCanvas(height)
	local cscreen = hs.screen.mainScreen()
	local cres = cscreen:fullFrame()
	local canvas = hs.canvas
		.new({
			x = 20,
			y = cres.h - height - 20,
			w = obj.calw,
			h = height,
		})
		:show()
	canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
	-- hs.canvas only delivers mouse clicks at desktopIcon + 1 or higher; that is
	-- still far below normal window level, so the calendar stays behind windows.
	canvas:level(hs.canvas.windowLevels.desktopIcon + 1)
	-- Only elements flagged trackMouseDown call back; areas not covered by such
	-- an element keep the canvasMouseEvents default (no callbacks), so clicks on
	-- the rest of the panel fall through to the desktop as before.
	canvas:mouseCallback(function(_, message, element_id)
		if message == "mouseDown" and element_id == TOGGLE_ID then
			obj:toggleView()
		end
	end)
	return canvas
end

--- Build the 3-month view: three month blocks + the legend strip.
local function buildThreeMonthCanvas()
	local offset = obj.calh / obj.months

	obj.canvas = createCanvas(obj.calh)

	for month_index = 1, obj.months do
		obj.canvas[1 + (month_index - 1) * MONTH_BLOCK] = {
			id = "cal_bg",
			type = "rectangle",
			action = "fill",
			fillColor = month_index == 1 and calbgcolor or cal_transparent_bg,
			roundedRectRadii = { xRadius = 10, yRadius = 10 },
		}

		obj.canvas[2 + (month_index - 1) * MONTH_BLOCK] = {
			id = "cal_title",
			type = "text",
			text = "",
			textFont = "Courier",
			textSize = 16,
			textColor = calcolor,
			textAlignment = "center",
			frame = {
				x = tostring(10 / obj.calw),
				y = tostring((10 + offset * (month_index - 1)) / TOTAL_H),
				w = tostring(1 - 20 / obj.calw),
				h = tostring((obj.calh - 20) / 8 / TOTAL_H / 3),
			},
		}

		-- 绘制星期表头
		-- local weeknames = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
		local weeknames = { "日", "一", "二", "三", "四", "五", "六" }
		for i = 1, #weeknames do
			obj.canvas[2 + i + (month_index - 1) * MONTH_BLOCK] = {
				id = "cal_weekday",
				type = "text",
				text = weeknames[i],
				textFont = "Courier",
				textSize = 12,
				textColor = cal_header_color,
				textAlignment = "center",
				frame = {
					x = tostring((10 + obj.cellw * i) / obj.calw),
					y = tostring((10 + obj.cellh + offset * (month_index - 1)) / TOTAL_H),
					w = tostring(obj.cellw / obj.calw),
					h = tostring(obj.cellh / TOTAL_H),
				},
			}
		end

		-- Create 7x6 calendar table
		for row = 1, 6 do
			for col = 1, 7 do
				obj.canvas[9 + 7 * (row - 1) + col + (month_index - 1) * MONTH_BLOCK] = {
					type = "text",
					text = "",
					textFont = "Courier",
					textSize = 16,
					textColor = (col == 1 or col == 7) and weekend_color or calcolor,
					textAlignment = "center",
					frame = {
						x = tostring((10 + obj.cellw * col) / obj.calw),
						y = tostring((10 + obj.cellh * (row + 1) + offset * (month_index - 1)) / TOTAL_H),
						w = tostring(obj.cellw / obj.calw),
						h = tostring(obj.cellh / TOTAL_H),
					},
				}
			end
		end

		-- Create yearweek column
		for i = 1, 6 do
			obj.canvas[51 + i + (month_index - 1) * MONTH_BLOCK] = {
				type = "text",
				text = "",
				textFont = "Courier",
				textSize = 16,
				textColor = weeknumcolor,
				textAlignment = "center",
				frame = {
					x = tostring(10 / obj.calw),
					y = tostring((10 + obj.cellh * (i + 1) + offset * (month_index - 1)) / TOTAL_H),
					w = tostring(obj.cellw / obj.calw),
					h = tostring(obj.cellh / TOTAL_H),
				},
			}
		end

		-- today cover rectangle
		-- Badge circles behind the 休/班 labels (drawn over the day numbers)
		-- NOTE: created BEFORE the labels and the today-cover to keep index order
		for row = 1, 6 do
			for col = 1, 7 do
				local center = cellBadgeCenter(col, row, month_index)
				obj.canvas[IDX_BADGE_BASE + 7 * (row - 1) + col + (month_index - 1) * MONTH_BLOCK] = {
					type = "circle",
					action = "skip",   -- updateCalCanvas shows it on holiday / workday cells
					radius = BADGE_RADIUS,
					center = { x = frac(center.x, obj.calw), y = frac(center.y, TOTAL_H) },
					fillColor = holiday_color,
				}
			end
		end

		-- 休 / 班 labels, centred inside the badge circle
		for row = 1, 6 do
			for col = 1, 7 do
				local center = cellBadgeCenter(col, row, month_index)
				obj.canvas[IDX_LABEL_BASE + 7 * (row - 1) + col + (month_index - 1) * MONTH_BLOCK] = {
					type = "text",
					text = "",
					textFont = "Courier",
					textSize = LABEL_FONT_SIZE,
					textColor = badge_text_color,
					textAlignment = "center",
					frame = {
						x = frac(center.x - LABEL_BOX_W / 2, obj.calw),
						y = frac(center.y - LABEL_BOX_H / 2 + LABEL_Y_ADJUST, TOTAL_H),
						w = frac(LABEL_BOX_W, obj.calw),
						h = frac(LABEL_BOX_H, TOTAL_H),
					},
				}
			end
		end

		obj.canvas[MONTH_BLOCK * month_index] = {
			type = "rectangle",
			action = "fill",
			fillColor = caltodaycolor,
			roundedRectRadii = { xRadius = 3, yRadius = 3 },
			frame = {
				x = tostring((10 + obj.cellw) / obj.calw),
				y = tostring((10 + obj.cellh * 2 + offset * (month_index - 1)) / TOTAL_H),
				w = tostring(obj.cellw / obj.calw),
				h = tostring(obj.cellh / TOTAL_H),
			},
		}
	end

	-- Legend strip, exactly as before (first grid index is the block count)
	local legend_end = drawLegend(obj.canvas, MONTH_BLOCK * obj.months, obj.calh + LEGEND_H / 2, TOTAL_H)
	-- clickable view toggle, appended last
	drawViewToggle(obj.canvas, legend_end, TOTAL_H, VIEW_3MONTH)
end

--- Build the year view: 12 mini months in 3 columns x 4 rows, then the legend.
--- Like the 3-month view every index is created in order (no gaps).
local function buildYearCanvas()
	obj.canvas = createCanvas(YEAR_TOTAL_H)

	for month = 1, 12 do
		local mini_col = (month - 1) % YEAR_COLS
		local mini_row = math.floor((month - 1) / YEAR_COLS)
		local origin_x = 10 + mini_col * MINI_W
		local origin_y = YEAR_TOP + mini_row * (MINI_H + YEAR_ROW_GAP)
		local base = (month - 1) * MINI_BLOCK

		-- 1: mini month title (e.g. "9月")
		obj.canvas[base + 1] = {
			id = "cal_mini_title",
			type = "text",
			text = tostring(month) .. "月",
			textFont = "Courier",
			textSize = MINI_TITLE_SIZE,
			textColor = cal_header_color,
			textAlignment = "center",
			frame = {
				x = frac(origin_x, obj.calw),
				y = frac(origin_y, YEAR_TOTAL_H),
				w = frac(MINI_W, obj.calw),
				h = frac(MINI_TITLE_H, YEAR_TOTAL_H),
			},
		}

		-- 2..43: 6 rows x 7 columns of day numbers (no weekday header, no week numbers)
		for row_i = 1, 6 do
			for col_i = 1, 7 do
				obj.canvas[base + 1 + 7 * (row_i - 1) + col_i] = {
					type = "text",
					text = "",
					textFont = "Courier",
					textSize = MINI_DAY_SIZE,
					textColor = (col_i == 1 or col_i == 7) and weekend_color or calcolor,
					textAlignment = "center",
					frame = {
						x = frac(origin_x + (col_i - 1) * MINI_CELL_W, obj.calw),
						y = frac(origin_y + MINI_TITLE_H + (row_i - 1) * MINI_CELL_H, YEAR_TOTAL_H),
						w = frac(MINI_CELL_W, obj.calw),
						h = frac(MINI_CELL_H, YEAR_TOTAL_H),
					},
				}
			end
		end

		-- 44: today highlight (positioned by updateYearCanvas, block's last index)
		obj.canvas[base + MINI_BLOCK] = {
			type = "rectangle",
			action = "fill",
			fillColor = cal_transparent_bg,
			roundedRectRadii = { xRadius = 2, yRadius = 2 },
			frame = {
				x = frac(origin_x, obj.calw),
				y = frac(origin_y + MINI_TITLE_H, YEAR_TOTAL_H),
				w = frac(MINI_CELL_W, obj.calw),
				h = frac(MINI_CELL_H, YEAR_TOTAL_H),
			},
		}
	end

	local legend_end = drawLegend(obj.canvas, MINI_BLOCK * 12, YEAR_GRID_BOTTOM + LEGEND_H / 2, YEAR_TOTAL_H)
	-- clickable view toggle, appended last (same as the 3-month view)
	drawViewToggle(obj.canvas, legend_end, YEAR_TOTAL_H, VIEW_YEAR)
end

--- Redraw the year view: every month of the current year.
local function updateYearCanvas()
	local current_date = os.date("*t")
	local year = current_date.year
	local current_month = current_date.month
	local current_day = current_date.day

	for month = 1, 12 do
		local base = (month - 1) * MINI_BLOCK
		local mini_col = (month - 1) % YEAR_COLS
		local mini_row = math.floor((month - 1) / YEAR_COLS)
		local origin_x = 10 + mini_col * MINI_W
		local origin_y = YEAR_TOP + mini_row * (MINI_H + YEAR_ROW_GAP)
		local weekday_of_firstday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
		-- os.time() normalises month 13 into January of the next year
		local maxday_of_month = os.date("*t", os.time({ year = year, month = month + 1, day = 1 }) - 24 * 60 * 60).day

		obj.canvas[base + 1].text = tostring(month) .. "月"

		for row_i = 1, 6 do
			for col_i = 1, 7 do
				local day_number = 7 * (row_i - 1) + col_i - weekday_of_firstday + 1
				local cell_idx = base + 1 + 7 * (row_i - 1) + col_i
				if day_number < 1 or day_number > maxday_of_month then
					obj.canvas[cell_idx].text = ""
				else
					obj.canvas[cell_idx].text = day_number
					-- Same priority as the 3-month view; with no badge circles the
					-- colour alone carries the meaning here.
					-- 中国节假日 > 调休补班 > 日本节假日 > 周末 > 平常
					local isHol = holidays:isHoliday(year, month, day_number)
					local isWork = holidays:isWorkday(year, month, day_number)
					local isJpHol = holidays:isJapaneseHoliday(year, month, day_number)
					if isHol then
						obj.canvas[cell_idx].textColor = holiday_color
					elseif isWork then
						obj.canvas[cell_idx].textColor = workday_color
					elseif isJpHol then
						obj.canvas[cell_idx].textColor = japan_holiday_color
					elseif col_i == 1 or col_i == 7 then
						obj.canvas[cell_idx].textColor = weekend_color
					else
						obj.canvas[cell_idx].textColor = calcolor
					end
				end
			end
		end

		-- today highlight (only the month containing today)
		local highlight = obj.canvas[base + MINI_BLOCK]
		if month == current_month then
			local cell_n = (weekday_of_firstday - 1) + (current_day - 1)
			local col_i = cell_n % 7 + 1
			local row_i = math.floor(cell_n / 7) + 1
			highlight.fillColor = caltodaycolor
			highlight.frame.x = frac(origin_x + (col_i - 1) * MINI_CELL_W, obj.calw)
			highlight.frame.y = frac(origin_y + MINI_TITLE_H + (row_i - 1) * MINI_CELL_H, YEAR_TOTAL_H)
		else
			highlight.fillColor = cal_transparent_bg
		end
	end

	obj.canvas:size({ w = obj.calw, h = YEAR_TOTAL_H })
end

--- Bind the view-toggle hotkey. `_G.daxcalendar_keys` (e.g. { {"alt"}, "," })
--- overrides the default; any previous handle is deleted first so repeated
--- rebuilds and spoon reloads never leak hotkeys.
local function bindToggleHotkey()
	if _G.daxcalendar_hotkey then
		pcall(function()
			_G.daxcalendar_hotkey:delete()
		end)
		_G.daxcalendar_hotkey = nil
	end
	obj.toggle_hotkey = nil
	if not (hs.hotkey and hs.hotkey.bind) then
		return nil
	end
	local keys = _G.daxcalendar_keys or { { "alt" }, "," }
	local mods, key = keys[1], keys[2]
	if type(mods) ~= "table" then
		mods = { mods }   -- accept the flat form { "alt", "," } too
	end
	obj.toggle_hotkey = hs.hotkey.bind(mods, key, function()
		obj:toggleView()
	end)
	_G.daxcalendar_hotkey = obj.toggle_hotkey
	return obj.toggle_hotkey
end

--- Redraw whichever view is active (timer tick + first paint).
function obj:render()
	if obj.view_mode == VIEW_YEAR then
		updateYearCanvas()
	else
		updateCalCanvas()
	end
	-- keep the toggle caption in sync with the active view
	local toggle = obj.toggle_idx and obj.canvas and obj.canvas[obj.toggle_idx]
	if toggle then
		toggle.text = TOGGLE_LABELS[obj.view_mode]
	end
end

--- Rebuild the canvas from scratch for the active view. hs.canvas elements can
--- only be appended contiguously, so a view switch cannot reuse or patch the
--- old element indices: the old canvas is deleted and a new one is drawn.
function obj:rebuild()
	if obj.canvas then
		obj.canvas:delete()
		obj.canvas = nil
	end
	if obj.view_mode == VIEW_YEAR then
		buildYearCanvas()
	else
		buildThreeMonthCanvas()
	end
	obj:render()
	bindToggleHotkey()
	return obj.canvas
end

--- Switch between the 3-month and year views.
function obj:toggleView()
	if obj.view_mode == VIEW_YEAR then
		obj.view_mode = VIEW_3MONTH
	else
		obj.view_mode = VIEW_YEAR
	end
	obj:rebuild()
	return obj.view_mode
end

function obj:init()
	obj.view_mode = VIEW_3MONTH

	buildThreeMonthCanvas()

	-- Toggle hotkey: _G.daxcalendar_keys, else alt+, (also re-bound on rebuild)
	bindToggleHotkey()

	-- Fetch Chinese holiday data for current and neighboring years
	local currentYear = os.date("*t").year
	holidays:fetchYear(currentYear - 1)
	holidays:fetchYear(currentYear)
	holidays:fetchYear(currentYear + 1)

	-- Fetch Japanese holiday data for current and neighboring years
	holidays:fetchJapaneseYear(currentYear - 1)
	holidays:fetchJapaneseYear(currentYear)
	holidays:fetchJapaneseYear(currentYear + 1)

	if obj.timer == nil then
		obj.timer = hs.timer.doEvery(1800, function()
			obj:render()
		end)
		obj.timer:setNextTrigger(0)
	else
		obj.timer:start()
	end
end

return obj
