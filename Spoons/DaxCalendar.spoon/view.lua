--- === View ===
---
--- A view is one canvas' worth of calendar: the background panel, a grid of
--- month blocks, the legend strip and the clickable view toggle.
---
--- The window view and the year view are this same code with a different
--- Layout.views descriptor (cols / rows / uniform), so the two cannot drift
--- apart. Element handles are kept so rendering never needs an index.

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(DIR .. "/layout.lua")
local MonthBlock = dofile(DIR .. "/monthblock.lua")

local M = {}

--- Approximate rendered width of a CJK caption (full-width glyphs).
local function textWidth(str, size)
	local n = utf8 and utf8.len and utf8.len(str)
	return (n or #str) * size
end

local function add(canvas, el)
	canvas[canvas:elementCount() + 1] = el
	return canvas[canvas:elementCount()]
end

--- Legend strip: a coloured disc (with a 休 / 班 glyph) and a caption per item,
--- centred as a group under the grid. All the discs are painted first, then the
--- glyphs on top of them, then the captions. An item with a `color2` gets a
--- two-tone disc (left half `color`, right half `color2`) -- the same shape a
--- Chinese+Japanese holiday day wears on the grid.
local function buildLegend(canvas, plan)
	local items, total = {}, L.legend.gap * (#L.legend.items - 1)
	for i, src in ipairs(L.legend.items) do
		local w = 2 * L.legend.radius + L.legend.disc_gap + textWidth(src.text, L.legend.text_size)
		items[i] = { glyph = src.glyph, color = src.color, color2 = src.color2, text = src.text, w = w }
		total = total + w
	end
	local x = (plan.w - total) / 2
	for _, item in ipairs(items) do
		item.disc_x = x + L.legend.radius
		item.text_x = x + 2 * L.legend.radius + L.legend.disc_gap
		add(canvas, {
			type = "circle",
			action = "fill",
			radius = L.legend.radius,
			center = { x = item.disc_x, y = plan.legend_y },
			fillColor = item.color,
		})
		if item.color2 then
			add(canvas, {
				type = "segments",
				action = "fill",
				closed = true,
				fillColor = item.color2,
				coordinates = L.halfDisc(item.disc_x, plan.legend_y, L.legend.radius, "right"),
			})
		end
		x = x + item.w + L.legend.gap
	end
	for _, item in ipairs(items) do
		if item.glyph then
			add(canvas, {
				type = "text",
				text = item.glyph,
				textFont = "Courier",
				textSize = L.font.label,
				textColor = L.color.badge,
				textAlignment = "center",
				frame = {
					x = item.disc_x - L.badge.box_w / 2,
					y = plan.legend_y - L.badge.box_h / 2 + L.badge.y_adjust,
					w = L.badge.box_w,
					h = L.badge.box_h,
				},
			})
		end
	end
	for _, item in ipairs(items) do
		add(canvas, {
			type = "text",
			text = item.text,
			textFont = "Courier",
			textSize = L.legend.text_size,
			textColor = L.color.day,
			textAlignment = "left",
			frame = {
				x = item.text_x,
				y = plan.legend_y - L.legend.label_box_h / 2 + L.legend.label_y_adjust,
				w = textWidth(item.text, L.legend.text_size) + 6,
				h = L.legend.label_box_h,
			},
		})
	end
end

--- Build every element of `view_id` on `canvas`, which must be empty. `months`
--- only decides the geometry (how tall the grid is); the content is filled in by
--- render(). Returns the view handle.
function M.build(canvas, view_id, months, plan)
	plan = plan or L.plan(view_id, months)

	-- one panel behind everything, sized to the whole canvas: it gives the
	-- calendar its rounded outer corners
	add(canvas, {
		id = "cal_bg",
		type = "rectangle",
		action = "fill",
		fillColor = L.color.panel,
		roundedRectRadii = { xRadius = L.panel_radius, yRadius = L.panel_radius },
		frame = { x = 0, y = 0, w = plan.w, h = plan.h },
	})

	local blocks = {}
	for i, b in ipairs(plan.blocks) do
		blocks[i] = MonthBlock.build(canvas, b.x, b.y, plan.rows[i])
	end

	buildLegend(canvas, plan)

	local toggle = add(canvas, {
		id = L.toggle.id,
		type = "text",
		text = L.views[view_id].toggle_label,
		textFont = "Courier",
		textSize = L.toggle.text_size,
		textColor = L.color.header,
		textAlignment = "right",
		trackMouseDown = true,   -- frame == hit area for text elements
		frame = { x = plan.toggle.x, y = plan.toggle.y, w = L.toggle.w, h = L.toggle.h },
	})

	return { view = view_id, plan = plan, canvas = canvas, blocks = blocks, toggle = toggle }
end

--- Fill the view's content in: block i shows ctx.months[i] (the same list the
--- plan was built from).
function M.render(view, ctx)
	for i, block in ipairs(view.blocks) do
		local month = ctx.months[i]
		MonthBlock.update(block, {
			year = month.year,
			month = month.month,
			today = ctx.today,
			holidays = ctx.holidays,
		})
	end
end

return M
