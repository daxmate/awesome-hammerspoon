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

-- Per-month canvas element block size (58 + 42 holiday labels)
local MONTH_BLOCK = 100

obj.calw = 260
obj.months = 3
obj.calh = 190 * obj.months
obj.cellw = (obj.calw - 20) / 8
obj.cellh = (obj.calh - 20) / 8 / obj.months
-- Holiday label font size (overlaid at top-left of date cells)
local LABEL_FONT_SIZE = 7

local function sunday_first_weekday(date)
	local wday = date.wday
	if wday == 7 then
		return 1
	else
		return wday + 1
	end
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
				else
					obj.canvas[9 + caltable_idx].text = day_number
					-- Apply holiday / weekend coloring
					-- Priority: Chinese holiday > Japanese holiday > weekend > normal
					local isHol, holData = holidays:isHoliday(year, month, day_number)
					local isJpHol, jpHolData = holidays:isJapaneseHoliday(year, month, day_number)
					-- Update abbreviation label (starts at index 58 within each month block)
					local label_idx = 9 + caltable_idx + 48  -- 58 - (9+42_first_cell) offset
					-- equivalent to: 57 + 7*(row_i-1) + col_i + (month_index-1)*MONTH_BLOCK
					if isHol then
						obj.canvas[9 + caltable_idx].textColor = holiday_color
						obj.canvas[label_idx].text = holData.abbr or ""
						obj.canvas[label_idx].textColor = holiday_color
					elseif isJpHol then
						obj.canvas[9 + caltable_idx].textColor = japan_holiday_color
						obj.canvas[label_idx].text = jpHolData.abbr or ""
						obj.canvas[label_idx].textColor = japan_holiday_color
					else
						obj.canvas[label_idx].text = ""
						if col_i == 1 or col_i == 7 then
							obj.canvas[9 + caltable_idx].textColor = weekend_color
						else
							obj.canvas[9 + caltable_idx].textColor = calcolor
						end
					end
				end
				if month == current_month and day_number == current_day then
					-- col_i maps directly to canvas column (1=Sun, 7=Sat)
					obj.canvas[MONTH_BLOCK * month_index].frame.x = tostring((10 + obj.cellw * col_i) / obj.calw)
					obj.canvas[MONTH_BLOCK * month_index].frame.y =
						tostring((10 + obj.cellh * (row_i + 1) + offset * (month_index - 1)) / obj.calh)
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
		-- trim the canvas
		obj.canvas:size({
			w = obj.calw,
			h = 20 + (obj.calh - 20) / 8 * (needed_rownum + 2),
		})
	end
end

function obj:init()
	local caltodaycolor = { red = 1, blue = 1, green = 1, alpha = 0.3 }
	local cal_header_color = { hex = "#78FF78" }
	local calbgcolor = { red = 0, blue = 0, green = 0, alpha = 0.3 }
	local cal_transparent_bg = { red = 0, blue = 0, green = 0, alpha = 0 }
	local weeknumcolor = { red = 246 / 255, blue = 246 / 255, green = 246 / 255, alpha = 0.5 }
	local cscreen = hs.screen.mainScreen()
	local cres = cscreen:fullFrame()
	local offset = obj.calh / obj.months

	obj.canvas = hs.canvas
		.new({
			x = 20,
			y = cres.h - obj.calh - 20,
			w = obj.calw,
			h = obj.calh,
		})
		:show()

	obj.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
	obj.canvas:level(hs.canvas.windowLevels.desktopIcon)

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
				y = tostring((10 + offset * (month_index - 1)) / obj.calh),
				w = tostring(1 - 20 / obj.calw),
				h = tostring((obj.calh - 20) / 8 / obj.calh / 3),
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
					y = tostring((10 + obj.cellh + offset * (month_index - 1)) / obj.calh),
					w = tostring(obj.cellw / obj.calw),
					h = tostring(obj.cellh / obj.calh),
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
						y = tostring((10 + obj.cellh * (row + 1) + offset * (month_index - 1)) / obj.calh),
						w = tostring(obj.cellw / obj.calw),
						h = tostring(obj.cellh / obj.calh),
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
					y = tostring((10 + obj.cellh * (i + 1) + offset * (month_index - 1)) / obj.calh),
					w = tostring(obj.cellw / obj.calw),
					h = tostring(obj.cellh / obj.calh),
				},
			}
		end

		-- today cover rectangle
		-- Create holiday abbreviation labels (overlaid at top-left of each date cell)
		-- NOTE: must be created BEFORE today-cover to maintain sequential index order
		for row = 1, 6 do
			for col = 1, 7 do
				-- label index = 58 + 7*(row-1) + (col-1) + (month_index-1)*MONTH_BLOCK
				--              = 57 + 7*(row-1) + col + (month_index-1)*MONTH_BLOCK
				obj.canvas[57 + 7 * (row - 1) + col + (month_index - 1) * MONTH_BLOCK] = {
					type = "text",
					text = "",
					textFont = "Courier",
					textSize = LABEL_FONT_SIZE,
					textColor = holiday_color,
					textAlignment = "right",
					frame = {
						x = tostring((10 + obj.cellw * col) / obj.calw),
						y = tostring((10 + obj.cellh * (row + 1) + 1 + offset * (month_index - 1)) / obj.calh),
						w = tostring(obj.cellw / obj.calw),
						h = tostring(obj.cellh / 2 / obj.calh),
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
				y = tostring((10 + obj.cellh * 2 + offset * (month_index - 1)) / obj.calh),
				w = tostring(obj.cellw / obj.calw),
				h = tostring(obj.cellh / obj.calh),
			},
		}
	end

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
			updateCalCanvas()
		end)
		obj.timer:setNextTrigger(0)
	else
		obj.timer:start()
	end
end

return obj
