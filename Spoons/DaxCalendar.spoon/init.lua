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

obj.calw = 260
obj.months = 3
obj.calh = 190 * obj.months
obj.cellw = (obj.calw - 20) / 8
obj.cellh = (obj.calh - 20) / 8 / obj.months

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
		local next_month = (month + 1) % 12
		local firstday_of_next_month = os.time({ year = year, month = next_month, day = 1 })
		local maxday_of_month = os.date("*t", firstday_of_next_month - 24 * 60 * 60).day
		local title_string = tostring(year) .. "年" .. " " .. chinese_months[month]
		local weekday_of_firstday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
		local needed_rownum = math.ceil((weekday_of_firstday + maxday_of_month - 1) / 7)
		obj.canvas[2 + (month_index - 1) * 58].text = title_string

		local row, col
		for i = 1, needed_rownum do
			for k = 1, 7 do
				if k == 7 then
					row = i + 1
					col = 1
				else
					row = i
					col = k + 1
				end
				local caltable_idx = 7 * (i - 1) + k + (month_index - 1) * 58
				local pushbacked_value = 7 * (i - 1) + k - weekday_of_firstday + 1
				if pushbacked_value <= 0 or pushbacked_value > maxday_of_month then
					obj.canvas[9 + caltable_idx].text = ""
				else
					obj.canvas[9 + caltable_idx].text = pushbacked_value
				end
				if month == current_month then
					if pushbacked_value == math.tointeger(current_day) then
						obj.canvas[58 * month_index].frame.x = tostring((10 + obj.cellw * (col - 1)) / obj.calw)
						obj.canvas[58 * month_index].frame.y =
							tostring((10 + obj.cellh * (row + 1) + offset * (month_index - 1)) / obj.calh)
					end
				else
					obj.canvas[58 * month_index].fillColor = { red = 0, blue = 0, green = 0, alpha = 0 }
				end
			end
		end
		-- update yearweek
		local yearweek_of_firstday = 0
		if month_diff < 0 then
			yearweek_of_firstday = hs.execute("date -v1d -v" .. tostring(month_diff) .. "m +'%V'")
		elseif month_diff > 0 then
			yearweek_of_firstday = hs.execute("date -v1d -v+" .. tostring(month_diff) .. "m +'%V'")
		else
			yearweek_of_firstday = hs.execute("date -v1d   +'%V'")
		end
		for i = 1, 6 do
			local yearweek_rowvalue = math.tointeger(yearweek_of_firstday) + i - 1
			obj.canvas[51 + i + (month_index - 1) * 58].text = yearweek_rowvalue
			if i > needed_rownum then
				obj.canvas[51 + i + (month_index - 1) * 58].text = ""
			end
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
	local calcolor = { red = 235 / 255, blue = 235 / 255, green = 235 / 255 }
	local cal_header_color = { hex = "#78FF78" }
	local calbgcolor = { red = 0, blue = 0, green = 0, alpha = 0.3 }
	local cal_transparent_bg = { red = 0, blue = 0, green = 0, alpha = 0 }
	local weeknumcolor = { red = 246 / 255, blue = 246 / 255, green = 246 / 255, alpha = 0.5 }
	local weekend_color = { hex = "#FF7878" }
	local cscreen = hs.screen.mainScreen()
	local cres = cscreen:fullFrame()
	local offset = obj.calh / obj.months

	obj.canvas = hs.canvas
		.new({
			x = cres.w - obj.calw - 20,
			y = cres.h - obj.calh - 20,
			w = obj.calw,
			h = obj.calh,
		})
		:show()

	obj.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
	obj.canvas:level(hs.canvas.windowLevels.desktopIcon)

	for month_index = 1, obj.months do
		obj.canvas[1 + (month_index - 1) * 58] = {
			id = "cal_bg",
			type = "rectangle",
			action = "fill",
			fillColor = month_index == 1 and calbgcolor or cal_transparent_bg,
			roundedRectRadii = { xRadius = 10, yRadius = 10 },
		}

		obj.canvas[2 + (month_index - 1) * 58] = {
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
			obj.canvas[2 + i + (month_index - 1) * 58] = {
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
				obj.canvas[9 + 7 * (row - 1) + col + (month_index - 1) * 58] = {
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
			obj.canvas[51 + i + (month_index - 1) * 58] = {
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
		obj.canvas[58 * month_index] = {
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
