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

-- Both views keep their own canvas alive: switching only shows/hides, so no
-- element is ever built twice. A cached canvas is redrawn only when its content
-- is older than this many seconds (or when the date rolled over).
local STALE_AFTER_S   = 600
-- Seconds after init before the year canvas is built in the background (hidden),
-- so the first manual switch does not pay the build cost.
local PREWARM_DELAY_S = 3

-- One month block is exactly the block the 3-month view has always drawn:
-- BLOCK_W x BLOCK_H points, its internal spacing included.
local BLOCK_W = obj.calw                 -- 260pt
local BLOCK_H = obj.calh / obj.months    -- 190pt

-- ---- year view: 12 full month blocks in 3 columns x 4 rows -----------------
-- Each row is one quarter (1-3 / 4-6 / 7-9 / 10-12 月). Every block is built by
-- drawMonthBlock() -- the same function the 3-month view uses -- so the two
-- views cannot drift apart. The blocks tile the canvas exactly: 3 x 260 = 780
-- wide and 4 x 190 = 760 tall, with the legend strip below.
local YEAR_COLS    = 3
local YEAR_ROWS    = 4
local YEAR_W       = YEAR_COLS * BLOCK_W                 -- 780pt
local YEAR_TOTAL_H = YEAR_ROWS * BLOCK_H + LEGEND_H      -- 786pt

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

-- Month names for the block titles (一月 .. 十二月)
local MONTH_LABELS = {
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

--- Canvas height when the grid needs `needed_rownum` rows: the grid keeps its
--- usual proportions and the legend strip goes in the extra space. Shared by
--- both views, so the year canvas ends up exactly as tall as the 3-month one.
local function canvasHeightForRows(needed_rownum)
	local content_h = 20 + (obj.calh - 20) / 8 * (needed_rownum + 2)
	return content_h / obj.calh * TOTAL_H
end

--- Year/month of 3-month window slot `month_index` (1..obj.months).
local function windowMonth(month_index)
	local current_date = os.date("*t")
	local month = current_date.month + month_index - obj.months // 2 - 1
	local year = month < 1 and current_date.year - 1 or month > 12 and current_date.year + 1 or current_date.year
	month = (month + 12) % 12
	if month == 0 then
		month = 12
	end
	return year, month
end

--- Canvas-point centre of a day cell's badge circle inside a month block.
local function blockBadgeCenter(x_origin, y_origin, col, row)
	return {
		x = x_origin + 10 + obj.cellw * (col + 1) - BADGE_MARGIN_X,
		y = y_origin + 10 + obj.cellh * (row + 1) + BADGE_MARGIN_Y,
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
local function drawLegend(canvas, start_idx, legend_y, total_h, layout_w)
	layout_w = layout_w or obj.calw
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
	local legend_x = (layout_w - legend_w) / 2
	local legend_idx = start_idx
	for _, item in ipairs(items) do
		item.disc_cx = legend_x + LEGEND_RADIUS
		item.text_x = legend_x + 2 * LEGEND_RADIUS + LEGEND_DISC_GAP
		legend_idx = legend_idx + 1
		canvas[legend_idx] = {
			type = "circle",
			action = "fill",
			radius = LEGEND_RADIUS,
			center = { x = frac(item.disc_cx, layout_w), y = frac(legend_y, total_h) },
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
					x = frac(item.disc_cx - LABEL_BOX_W / 2, layout_w),
					y = frac(legend_y - LABEL_BOX_H / 2 + LABEL_Y_ADJUST, total_h),
					w = frac(LABEL_BOX_W, layout_w),
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
				x = frac(item.text_x, layout_w),
				y = frac(legend_y - LEGEND_LABEL_BOX_H / 2 + LEGEND_LABEL_Y_ADJUST, total_h),
				w = frac(item.text_w + 6, layout_w),
				h = frac(LEGEND_LABEL_BOX_H, total_h),
			},
		}
	end
	return legend_idx
end

--- Append the clickable view-toggle label (canvas' top-right corner). It is
--- the LAST element of both views, so the canvas indices stay contiguous.
local function drawViewToggle(canvas, index, total_h, mode, layout_w)
	layout_w = layout_w or obj.calw
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
			x = frac(layout_w - TOGGLE_MARGIN - TOGGLE_W, layout_w),
			y = frac(TOGGLE_TOP, total_h),
			w = frac(TOGGLE_W, layout_w),
			h = frac(TOGGLE_H, total_h),
		},
	}
	obj.toggle_ix[mode] = i
	return i
end

--- Create every element of one month block, in index order (hs.canvas only
--- accepts contiguous appends). `(x_origin, y_origin)` is the block's top-left
--- corner in canvas points and `layout` holds the fraction denominators, so the
--- same function serves the 3-month view (x_origin = 0) and the year grid.
---
--- Block layout, as offsets from `base`:
---   1                   : rounded panel
---   2                   : month title (2026年 一月)
---   3 .. 9              : weekday header 日一二三四五六
---   10 .. 51            : 42 day numbers
---   52 .. 57            : 6 week numbers
---   58 .. 99            : 42 badge circles
---   100 .. 141          : 42 休 / 班 labels
---   142 (= MONTH_BLOCK) : today highlight
local function createMonthBlock(canvas, base, x_origin, y_origin, layout, panel)
	local w, h = layout.w, layout.h
	local cellw, cellh = obj.cellw, obj.cellh

	-- 1: rounded panel. The 3-month view keeps its single frame-less panel
	-- covering the whole canvas; the year grid draws one per month block.
	canvas[base + 1] = {
		id = "cal_bg",
		type = "rectangle",
		action = "fill",
		fillColor = panel.color,
		roundedRectRadii = { xRadius = 10, yRadius = 10 },
	}
	if panel.framed then
		canvas[base + 1].frame = {
			x = frac(x_origin, w),
			y = frac(y_origin, h),
			w = frac(BLOCK_W, w),
			h = frac(BLOCK_H, h),
		}
	end

	-- 2: month title
	canvas[base + 2] = {
		id = "cal_title",
		type = "text",
		text = "",
		textFont = "Courier",
		textSize = 16,
		textColor = calcolor,
		textAlignment = "center",
		frame = {
			x = frac(x_origin + 10, w),
			y = frac(10 + y_origin, h),
			w = frac(BLOCK_W - 20, w),
			-- same operation order as the original title box:
			-- (calh - 20) / 8 / layout_h / months, so the 3-month element stays
			-- bit-identical and the year block gets the same nominal height
			h = frac((obj.calh - 20) / 8 / h, obj.months),
		},
	}

	-- 3..9: weekday header
	local weeknames = { "日", "一", "二", "三", "四", "五", "六" }
	for i = 1, #weeknames do
		canvas[base + 2 + i] = {
			id = "cal_weekday",
			type = "text",
			text = weeknames[i],
			textFont = "Courier",
			textSize = 12,
			textColor = cal_header_color,
			textAlignment = "center",
			frame = {
				x = frac(x_origin + 10 + cellw * i, w),
				y = frac(10 + cellh + y_origin, h),
				w = frac(cellw, w),
				h = frac(cellh, h),
			},
		}
	end

	-- 10..51: 7x6 day grid
	for row = 1, 6 do
		for col = 1, 7 do
			canvas[base + 9 + 7 * (row - 1) + col] = {
				type = "text",
				text = "",
				textFont = "Courier",
				textSize = 16,
				textColor = (col == 1 or col == 7) and weekend_color or calcolor,
				textAlignment = "center",
				frame = {
					x = frac(x_origin + 10 + cellw * col, w),
					y = frac(10 + cellh * (row + 1) + y_origin, h),
					w = frac(cellw, w),
					h = frac(cellh, h),
				},
			}
		end
	end

	-- 52..57: week-number column
	for i = 1, 6 do
		canvas[base + 51 + i] = {
			type = "text",
			text = "",
			textFont = "Courier",
			textSize = 16,
			textColor = weeknumcolor,
			textAlignment = "center",
			frame = {
				x = frac(x_origin + 10, w),
				y = frac(10 + cellh * (i + 1) + y_origin, h),
				w = frac(cellw, w),
				h = frac(cellh, h),
			},
		}
	end

	-- 58..99: badge circles behind the 休/班 labels
	for row = 1, 6 do
		for col = 1, 7 do
			local center = blockBadgeCenter(x_origin, y_origin, col, row)
			canvas[base + IDX_BADGE_BASE + 7 * (row - 1) + col] = {
				type = "circle",
				action = "skip",   -- updateMonthBlock shows it on holiday / workday cells
				radius = BADGE_RADIUS,
				center = { x = frac(center.x, w), y = frac(center.y, h) },
				fillColor = holiday_color,
			}
		end
	end

	-- 100..141: 休 / 班 labels, centred inside their badge circle
	for row = 1, 6 do
		for col = 1, 7 do
			local center = blockBadgeCenter(x_origin, y_origin, col, row)
			canvas[base + IDX_LABEL_BASE + 7 * (row - 1) + col] = {
				type = "text",
				text = "",
				textFont = "Courier",
				textSize = LABEL_FONT_SIZE,
				textColor = badge_text_color,
				textAlignment = "center",
				frame = {
					x = frac(center.x - LABEL_BOX_W / 2, w),
					y = frac(center.y - LABEL_BOX_H / 2 + LABEL_Y_ADJUST, h),
					w = frac(LABEL_BOX_W, w),
					h = frac(LABEL_BOX_H, h),
				},
			}
		end
	end

	-- 142: today highlight (the block's last index)
	canvas[base + MONTH_BLOCK] = {
		type = "rectangle",
		action = "fill",
		fillColor = caltodaycolor,
		roundedRectRadii = { xRadius = 3, yRadius = 3 },
		frame = {
			x = frac(x_origin + 10 + cellw, w),
			y = frac(10 + cellh * 2 + y_origin, h),
			w = frac(cellw, w),
			h = frac(cellh, h),
		},
	}
end

--- Fill one month block in: title, day numbers with holiday/weekend colours,
--- 休/班 badges, week numbers and the today highlight. Returns the number of grid
--- rows the month needs (the 3-month canvas is sized from its last block).
--- Monday-based week number of a date ("00" for days before the year's first
--- Monday). Identical to BSD `date +%W` (verified against it for 2024-2028
--- including year boundaries) but computed in-process -- the previous code
--- spawned a `date` subprocess for every calendar row (72 of them per year
--- view render), which caused a visible hitch.
local function weekNumberOf(year, month, day)
	return tonumber(os.date("%W", os.time({ year = year, month = month, day = day, hour = 12 })))
end

local function updateMonthBlock(canvas, base, x_origin, y_origin, layout, year, month)
	local w, h = layout.w, layout.h
	local cellw, cellh = obj.cellw, obj.cellh
	local current_date = os.date("*t")
	local current_month = current_date.month
	local current_day = current_date.day

	local next_month = (month + 1) % 12
	local firstday_of_next_month = os.time({ year = year, month = next_month, day = 1 })
	local maxday_of_month = os.date("*t", firstday_of_next_month - 24 * 60 * 60).day
	local title_string = tostring(year) .. "年" .. " " .. MONTH_LABELS[month]
	local weekday_of_firstday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
	local needed_rownum = math.ceil((weekday_of_firstday + maxday_of_month - 1) / 7)
	canvas[base + 2].text = title_string

	for row_i = 1, needed_rownum do
		for col_i = 1, 7 do
			-- col_i: 1=Sunday col, 2=Monday, ..., 7=Saturday
			-- Lua wday: 1=Sunday, ..., 7=Saturday
			local day_number = 7 * (row_i - 1) + col_i - weekday_of_firstday + 1
			local cell = 7 * (row_i - 1) + col_i
			local day_idx = base + 9 + cell
			local badge_idx = base + IDX_BADGE_BASE + cell
			local label_idx = base + IDX_LABEL_BASE + cell
			if day_number <= 0 or day_number > maxday_of_month then
				canvas[day_idx].text = ""
				canvas[label_idx].text = ""
				canvas[badge_idx].action = "skip"
			else
				canvas[day_idx].text = day_number
				-- Apply holiday / weekend coloring
				-- Priority: Chinese holiday > 调休补班 > Japanese holiday > weekend > normal
				local isHol, holData = holidays:isHoliday(year, month, day_number)
				local isWork, workData = holidays:isWorkday(year, month, day_number)
				local isJpHol, jpHolData = holidays:isJapaneseHoliday(year, month, day_number)
				local label_text, badge_color
				if isHol then
					canvas[day_idx].textColor = holiday_color
					label_text, badge_color = holData.abbr or "休", holiday_color
				elseif isWork then
					-- 调休补班：数字用正常工作日的颜色，角标"班"提示这天要上班
					canvas[day_idx].textColor = calcolor
					label_text, badge_color = workData.abbr or "班", workday_color
				elseif isJpHol then
					canvas[day_idx].textColor = japan_holiday_color
					label_text, badge_color = jpHolData.abbr or "休", japan_holiday_color
				elseif col_i == 1 or col_i == 7 then
					canvas[day_idx].textColor = weekend_color
				else
					canvas[day_idx].textColor = calcolor
				end
				if label_text then
					-- 圆圈底色取原文字色，文字换成反差色
					canvas[badge_idx].action = "fill"
					canvas[badge_idx].fillColor = badge_color
					canvas[label_idx].text = label_text
				else
					canvas[badge_idx].action = "skip"
					canvas[label_idx].text = ""
				end
				-- 有角标时把日期数字左移一点，避免被圆底压住（实测 3pt 即可完全不遮挡）
				local day_shift = label_text and DAY_NUMBER_SHIFT or 0
				canvas[day_idx].frame.x = frac(x_origin + 10 + cellw * col_i - day_shift, w)
			end
			if month == current_month and day_number == current_day then
				-- col_i maps directly to canvas column (1=Sun, 7=Sat)
				canvas[base + MONTH_BLOCK].frame.x = frac(x_origin + 10 + cellw * col_i, w)
				canvas[base + MONTH_BLOCK].frame.y = frac(y_origin + 10 + cellh * (row_i + 1), h)
			elseif month ~= current_month then
				canvas[base + MONTH_BLOCK].fillColor = cal_transparent_bg
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
			yearweek_rowvalue = weekNumberOf(year, month, ref_day)
		end
		canvas[base + 51 + i].text = yearweek_rowvalue or ""
	end
	return needed_rownum
end

--- Create + fill one month block in a single pass (the year grid does both).
local function drawMonthBlock(canvas, base, x_origin, y_origin, year, month, layout, panel)
	createMonthBlock(canvas, base, x_origin, y_origin, layout, panel)
	return updateMonthBlock(canvas, base, x_origin, y_origin, layout, year, month)
end

--- Redraw the 3-month view: three stacked month blocks. The canvas is trimmed
--- to the content plus the legend strip after every block (as it always was).
local function updateCalCanvas(canvas)
	local layout = { w = obj.calw, h = TOTAL_H }
	for month_index = 1, obj.months do
		local year, month = windowMonth(month_index)
		local needed_rownum = updateMonthBlock(canvas, (month_index - 1) * MONTH_BLOCK, 0,
			(month_index - 1) * BLOCK_H, layout, year, month)
		-- trim the canvas: the grid plus the legend strip below it
		canvas:size({
			w = obj.calw,
			h = canvasHeightForRows(needed_rownum),
		})
	end
end

--- Create the canvas window sized to `height` points, showing on all spaces at
--- the desktop-icon level. A fresh canvas is created per rebuild because
--- hs.canvas elements can only be appended contiguously.
-- Diagnostics: phase timings and errors are appended to a plain file, so the
-- real behaviour can be inspected without relying on the console buffer or on
-- hs.configdir resolving the way we expect.
local DIAG_PATH = "/tmp/daxcalendar.log"
local function diag(msg)
	local f = io.open(DIAG_PATH, "a")
	if f then
		f:write(os.date("%H:%M:%S") .. "  " .. msg .. "\n")
		f:close()
	end
	if hs.printf then hs.printf("[DaxCalendar] " .. msg) end
end

local function nowMs()
	return hs.timer.secondsSinceEpoch() * 1000
end

local function elementCountOf(canvas)
	if not canvas or not canvas.elementCount then return "?" end
	local ok, n = pcall(function() return canvas:elementCount() end)
	if not ok or type(n) ~= "number" then return "?" end
	return n
end

--- Create a canvas window. It stays hidden unless `show_now` is true: the year
--- canvas is built (and drawn) in the background before it is ever displayed.
local function createCanvas(width, height, show_now)
	local cscreen = hs.screen.mainScreen()
	local cres = cscreen:fullFrame()
	local canvas = hs.canvas
		.new({
			x = 20,
			y = cres.h - height - 20,
			w = width,
			h = height,
		})
	if show_now then
		canvas:show()
	end
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

--- Build the 3-month view: three stacked month blocks, the legend strip and the
--- clickable toggle. Every month goes through createMonthBlock(), so the year
--- grid gets the very same block. The canvas is created hidden and cached.
local function buildThreeMonthCanvas()
	local layout = { w = obj.calw, h = TOTAL_H }

	local canvas = createCanvas(obj.calw, obj.calh, false)

	for month_index = 1, obj.months do
		-- one dark rounded panel behind the whole 3-month calendar (as before)
		local panel = {
			color = month_index == 1 and calbgcolor or cal_transparent_bg,
			framed = false,
		}
		createMonthBlock(canvas, (month_index - 1) * MONTH_BLOCK, 0, (month_index - 1) * BLOCK_H, layout, panel)
	end

	-- Legend strip, exactly as before (first grid index is the block count)
	local legend_end = drawLegend(canvas, MONTH_BLOCK * obj.months, obj.calh + LEGEND_H / 2, TOTAL_H, obj.calw)
	-- clickable view toggle, appended last
	drawViewToggle(canvas, legend_end, TOTAL_H, VIEW_3MONTH, obj.calw)

	obj.canvas_3month = canvas
	return canvas
end

--- Build the year view: 12 full month blocks in 3 columns x 4 rows (one row per
--- quarter), then the legend strip and the toggle. Every block goes through
--- drawMonthBlock(), the same function the 3-month view uses. The canvas is
--- created hidden and cached -- the switch only shows/hides it.
local function buildYearCanvas()
	local layout = { w = YEAR_W, h = YEAR_TOTAL_H }
	local year = os.date("*t").year

	local canvas = createCanvas(YEAR_W, YEAR_TOTAL_H, false)

	for month = 1, 12 do
		local col = (month - 1) % YEAR_COLS
		local row = math.floor((month - 1) / YEAR_COLS)
		-- one rounded panel per block: the 12 blocks tile the canvas exactly, so
		-- the whole year panel stays dark like the 3-month view's
		drawMonthBlock(canvas, (month - 1) * MONTH_BLOCK, col * BLOCK_W, row * BLOCK_H, year, month, layout,
			{ color = calbgcolor, framed = true })
	end

	local legend_end = drawLegend(canvas, MONTH_BLOCK * 12, YEAR_TOTAL_H - LEGEND_H / 2, YEAR_TOTAL_H, YEAR_W)
	-- clickable view toggle, appended last (same as the 3-month view)
	drawViewToggle(canvas, legend_end, YEAR_TOTAL_H, VIEW_YEAR, YEAR_W)

	obj.canvas_year = canvas
	return canvas
end

--- Redraw the year view: every month of the current year, same blocks.
local function updateYearCanvas(canvas)
	local layout = { w = YEAR_W, h = YEAR_TOTAL_H }
	local year = os.date("*t").year

	for month = 1, 12 do
		local col = (month - 1) % YEAR_COLS
		local row = math.floor((month - 1) / YEAR_COLS)
		updateMonthBlock(canvas, (month - 1) * MONTH_BLOCK, col * BLOCK_W, row * BLOCK_H, layout, year, month)
	end

	canvas:size({ w = YEAR_W, h = YEAR_TOTAL_H })
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

--- The canvas cached for `view` (nil before it has been built).
local function canvasFor(view)
	if view == VIEW_YEAR then
		return obj.canvas_year
	end
	return obj.canvas_3month
end

--- True when `view`'s content is older than STALE_AFTER_S or the date changed.
local function isStale(view)
	local last = obj.rendered_at and obj.rendered_at[view]
	if not last then return true end
	local today = os.date("*t")
	if last.day ~= today.day or last.month ~= today.month or last.year ~= today.year then
		return true
	end
	return (os.time() - last.time) >= STALE_AFTER_S
end

--- Draw one view's content into its canvas. No element is created here, so this
--- is the only work a switch can do on a cached canvas.
local function renderView(view, canvas)
	if view == VIEW_YEAR then
		updateYearCanvas(canvas)
	else
		updateCalCanvas(canvas)
	end
	-- keep the toggle caption in sync with the view this canvas draws
	local ix = obj.toggle_ix and obj.toggle_ix[view]
	if ix and canvas[ix] then
		canvas[ix].text = TOGGLE_LABELS[view]
	end
	local today = os.date("*t")
	obj.rendered_at = obj.rendered_at or {}
	obj.rendered_at[view] = {
		time = os.time(),
		day = today.day,
		month = today.month,
		year = today.year,
	}
end

--- Redraw the visible canvas (timer tick + first paint).
function obj:render()
	if obj.canvas then
		renderView(obj.view_mode, obj.canvas)
	end
end

--- The canvas for `view`, built on first use. `built` says whether this call
--- created it (so the caller knows its content still needs a first draw).
local function ensureCanvas(view)
	local canvas = canvasFor(view)
	if canvas then return canvas, false end
	if view == VIEW_YEAR then
		return buildYearCanvas(), true
	end
	return buildThreeMonthCanvas(), true
end

--- Show `view`: hide the other canvas and redraw only when the target's content
--- is stale (a freshly built canvas always renders once). Nothing is deleted.
function obj:switchTo(view)
	local t0 = nowMs()
	local target, built = ensureCanvas(view)
	local t_build = nowMs()
	local previous = canvasFor(obj.view_mode)
	-- draw while the target is still hidden, then swap: never show stale content
	local drew = built or isStale(view)
	if drew then
		renderView(view, target)
	end
	local t_render = nowMs()
	if previous and previous ~= target then
		previous:hide()
	end
	target:show()
	local t_show = nowMs()
	obj.view_mode = view
	obj.canvas = target
	bindToggleHotkey()
	local t_hotkey = nowMs()
	diag(string.format(
		"switch %s: build=%.1f render=%s (%.1f) hide/show=%.1f hotkey=%.1f total=%.1f ms, %s elements%s",
		view, t_build - t0, drew and "yes" or "SKIPPED - content still fresh",
		t_render - t_build, t_show - t_render, t_hotkey - t_show, t_hotkey - t0,
		tostring(elementCountOf(target)), built and " (newly built)" or ""))
	return target
end

--- Switch between the 3-month and year views.
function obj:toggleView()
	obj:switchTo(obj.view_mode == VIEW_YEAR and VIEW_3MONTH or VIEW_YEAR)
	return obj.view_mode
end

--- Build (and draw) the year canvas while it is still hidden, so the first
--- manual switch is instant. Nothing is shown here.
local function prewarmYearCanvas()
	local t0 = nowMs()
	if canvasFor(VIEW_YEAR) then
		diag(string.format("prewarm year: already built, %.1f ms", nowMs() - t0))
		return
	end
	local canvas = ensureCanvas(VIEW_YEAR)
	local t_build = nowMs()
	renderView(VIEW_YEAR, canvas)
	local t_render = nowMs()
	diag(string.format("prewarm year: build=%.1f render=%.1f total=%.1f ms, %s elements (stays hidden)",
		t_build - t0, t_render - t_build, t_render - t0, tostring(elementCountOf(canvas))))
end

function obj:init()
	local t0 = nowMs()
	diag("init start")
	obj.view_mode = VIEW_3MONTH
	obj.toggle_ix = {}
	obj.rendered_at = {}

	local canvas = buildThreeMonthCanvas()
	canvas:show()
	obj.canvas = canvas
	diag(string.format("init: 3-month canvas built in %.1f ms (%s elements)", nowMs() - t0, tostring(elementCountOf(canvas))))

	-- Toggle hotkey: _G.daxcalendar_keys, else alt+, (also re-bound on rebuild)
	bindToggleHotkey()
	diag(string.format("init: hotkey bound at %.1f ms", nowMs() - t0))

	-- Holiday data. Wrapped: a lookup problem must not abort the rest of init.
	local currentYear = os.date("*t").year
	local okFetch, fetchErr = pcall(function()
		holidays:fetchYear(currentYear - 1)
		holidays:fetchYear(currentYear)
		holidays:fetchYear(currentYear + 1)
		holidays:fetchJapaneseYear(currentYear - 1)
		holidays:fetchJapaneseYear(currentYear)
		holidays:fetchJapaneseYear(currentYear + 1)
	end)
	diag("init: fetch scheduled ok=" .. tostring(okFetch)
		.. (okFetch and "" or (" err=" .. tostring(fetchErr))) .. string.format(" (%.1f ms)", nowMs() - t0))

	-- Prewarm the year canvas a few seconds later (built and drawn while hidden)
	-- so the first manual switch is instant instead of ~350ms.
	if hs.timer and hs.timer.doAfter then
		-- keep the handle: an unreferenced doAfter timer can be collected before firing
		obj.prewarm_timer = hs.timer.doAfter(PREWARM_DELAY_S, prewarmYearCanvas)
		diag(string.format("init: year prewarm scheduled in %ds", PREWARM_DELAY_S))
	end

	if obj.timer == nil then
		obj.timer = hs.timer.doEvery(1800, function()
			obj:render()   -- refresh only the visible canvas
		end)
		obj.timer:setNextTrigger(0)
	else
		obj.timer:start()
	end
	diag(string.format("init done in %.1f ms", nowMs() - t0))
end

return obj
