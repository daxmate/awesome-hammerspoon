--- === Calendar ===
---
--- A calendar inset into the desktop: Chinese and Japanese holidays, a compact
--- 3-month window and a full-year view, drawn on every attached screen. Click the
--- label in the top-right corner (or press the hotkey) to switch views.
---
--- One module per concern, next to this file:
---   layout.lua      colours, sizes, view shapes, geometry planner
---   monthblock.lua  one month's elements (built once, updated through handles)
---   view.lua        a grid of month blocks + legend strip + view toggle
---   canvas_set.lua  one canvas per attached screen
---   holidays.lua    holiday data: fetch, cache, lookup
---   log.lua         optional diagnostics (/tmp/daxcalendar.log)

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")
	or (hs.configdir .. "/Spoons/DaxCalendar.spoon")
local function load(name) return dofile(DIR .. "/" .. name .. ".lua") end

local Layout = load("layout")
local View = load("view")
local CanvasSet = load("canvas_set")
local Log = load("log")
local holidays = load("holidays"):load()

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Calendar"
obj.version = "1.0"
obj.author = "ashfinal <ashfinal@gmail.com>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- View modes: obj.view_mode holds one of these
local VIEW_3MONTH = "3month"
local VIEW_YEAR   = "year"

-- Both views keep their canvases alive: switching only shows/hides, so no
-- element is ever built twice. A cached view is redrawn when its content is
-- older than this, or when the date (and with it the month window) rolled over.
local STALE_AFTER_S = 600
-- Seconds after init before the year view is built (hidden) in the background,
-- so the first manual switch does not pay the build cost.
local PREWARM_DELAY_S = 3
-- Periodic refresh of the visible view.
local REFRESH_S = 1800

--- The months a view shows: the year view always January..December of the
--- current year, the window view the current month plus its neighbours.
local function monthsFor(view)
	if view == VIEW_YEAR then
		local year = os.date("*t").year
		local months = {}
		for month = 1, 12 do
			months[month] = { year = year, month = month }
		end
		return months
	end
	return Layout.windowMonths()
end

local function contextFor(view)
	return { months = monthsFor(view), today = os.date("*t"), holidays = holidays }
end

--- The cached canvas set of `view`: one entry per screen (nil before the first
--- build). Entries are { screen, id, canvas, view, key }.
local function canvasSetFor(view)
	return obj.canvas_sets and obj.canvas_sets[view]
end

--- Build (hidden) the canvases of `view`, one per screen, and cache the set.
local function buildCanvasSet(view, ctx, plan)
	local set = CanvasSet.build(function(screen)
		local canvas = CanvasSet.newCanvas(screen, plan.w, plan.h, function() obj:toggleView() end)
		return {
			screen = screen,
			id = screen:id(),
			canvas = canvas,
			view = View.build(canvas, view, ctx.months, plan),
			key = Layout.planKey(ctx.months, plan),
		}
	end)
	obj.canvas_sets = obj.canvas_sets or {}
	obj.canvas_sets[view] = set
	return set
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

--- Draw `view` on every screen and return its canvas set plus whether the
--- canvases were rebuilt. A cached canvas is reused while it still shows the
--- right months; when the window rolls over (new months, possibly a different
--- grid height) the set is rebuilt from scratch.
local function renderView(view)
	local t0 = Log.nowMs()
	local ctx = contextFor(view)
	local plan = Layout.plan(view, ctx.months)
	local key = Layout.planKey(ctx.months, plan)
	local set = canvasSetFor(view)
	local rebuilt = false
	if set and set[1].key ~= key then
		CanvasSet.delete(set)
		obj.canvas_sets[view] = nil
		set = nil
	end
	if not set then
		set = buildCanvasSet(view, ctx, plan)
		rebuilt = true
	end
	for _, entry in ipairs(set) do
		View.render(entry.view, ctx)
	end
	obj.rendered_at = obj.rendered_at or {}
	obj.rendered_at[view] = {
		time = os.time(),
		day = ctx.today.day,
		month = ctx.today.month,
		year = ctx.today.year,
	}
	if rebuilt then
		Log.diag(string.format("built %s in %.1f ms, %d canvas(es): %s",
			view, Log.nowMs() - t0, #set, Log.describeSet(set)))
	end
	return set, rebuilt
end

--- Build (and draw) the year view while it stays hidden, so the first manual
--- switch is instant.
local function prewarmYear()
	local t0 = Log.nowMs()
	if canvasSetFor(VIEW_YEAR) then
		Log.diag(string.format("prewarm year: already built, %.1f ms", Log.nowMs() - t0))
		return
	end
	local set = renderView(VIEW_YEAR)
	CanvasSet.hide(set)
	Log.diag(string.format("prewarm year: %.1f ms, %d canvas(es): %s (stays hidden)",
		Log.nowMs() - t0, #set, Log.describeSet(set)))
end

--- Bind the view-toggle hotkey. `_G.daxcalendar_keys` (e.g. { {"alt"}, "," })
--- overrides the default. Any previous handle is deleted first, so repeated
--- rebuilds and spoon reloads never leak hotkeys. The global is the escape hatch
--- the hspoon_list loader leaves us: it calls init() without any configuration.
local function bindToggleHotkey()
	if _G.daxcalendar_hotkey then
		pcall(function() _G.daxcalendar_hotkey:delete() end)
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

--- Drop every canvas and build the visible view again for the screens attached
--- now. Canvas frames are baked at creation, so a display change (plug / unplug,
--- resolution, arrangement) has to recreate them to follow the layout.
local function rebuildCanvases(reason)
	local t0 = Log.nowMs()
	for _, set in pairs(obj.canvas_sets or {}) do
		CanvasSet.delete(set)
	end
	obj.canvas_sets = {}
	obj.rendered_at = {}
	local set = renderView(obj.view_mode)
	CanvasSet.show(set)
	Log.diag(string.format("rebuild (%s): %.1f ms, %d screen(s) now: %s",
		reason, Log.nowMs() - t0, #hs.screen.allScreens(), Log.describeSet(set)))
	-- re-arm the prewarm so the next toggle stays instant
	if hs.timer and hs.timer.doAfter then
		obj.prewarm_timer = hs.timer.doAfter(PREWARM_DELAY_S, prewarmYear)
	end
end

--- Screen changes fire several times per event (and while a resolution
--- switches), so coalesce them into one rebuild.
local function scheduleCanvasRebuild(reason)
	if obj.rebuild_timer then obj.rebuild_timer:stop() end
	obj.rebuild_timer = hs.timer.doAfter(1.0, function()
		obj.rebuild_timer = nil
		rebuildCanvases(reason)
	end)
end

--- Redraw the visible view on every screen (timer tick + first paint).
function obj:render()
	local set, rebuilt = renderView(obj.view_mode)
	if rebuilt then
		CanvasSet.show(set)   -- a rebuild produced fresh (still hidden) canvases
	end
end

--- Show `view`: hide the other view, show this one, and redraw it when its
--- content is stale. A freshly built set is always drawn first (while hidden),
--- so stale content is never shown.
function obj:switchTo(view)
	local t0 = Log.nowMs()
	local previous = canvasSetFor(obj.view_mode)
	local target = canvasSetFor(view)
	if not target or isStale(view) then
		target = renderView(view)
	end
	local t_render = Log.nowMs()
	if previous and previous ~= target then
		CanvasSet.hide(previous)
	end
	CanvasSet.show(target)
	obj.view_mode = view
	bindToggleHotkey()
	Log.diag(string.format("switch to %s: render=%.1f show=%.1f total=%.1f ms, %d canvas(es): %s",
		view, t_render - t0, Log.nowMs() - t_render, Log.nowMs() - t0, #target, Log.describeSet(target)))
	return target
end

--- Switch between the 3-month window and the year view.
function obj:toggleView()
	obj:switchTo(obj.view_mode == VIEW_YEAR and VIEW_3MONTH or VIEW_YEAR)
	return obj.view_mode
end

--- Introspection for the test harness and for diagnostics: the current view and
--- every cached canvas set (one entry per screen, with its view handle). Tests
--- read this instead of poking at internals, so the internals stay free to move.
function obj:debugState()
	local function dump(view)
		local out = {}
		for i, entry in ipairs(canvasSetFor(view) or {}) do
			out[i] = { screen = entry.screen:name(), id = entry.id, canvas = entry.canvas, view = entry.view }
		end
		return out
	end
	return {
		view_mode = obj.view_mode,
		canvas_sets = { [VIEW_3MONTH] = dump(VIEW_3MONTH), [VIEW_YEAR] = dump(VIEW_YEAR) },
	}
end

function obj:init()
	local t0 = Log.nowMs()
	Log.diag("init start")
	obj.view_mode = VIEW_3MONTH
	obj.canvas_sets = {}
	obj.rendered_at = {}

	local set = renderView(VIEW_3MONTH)
	CanvasSet.show(set)
	Log.diag(string.format("init: %d screen(s), %d canvas(es) in %.1f ms: %s",
		#hs.screen.allScreens(), #set, Log.nowMs() - t0, Log.describeSet(set)))

	bindToggleHotkey()

	-- Holiday data. Wrapped: a lookup problem must not abort the rest of init.
	local year = os.date("*t").year
	local ok, err = pcall(function()
		holidays:fetchYear(year - 1)
		holidays:fetchYear(year)
		holidays:fetchYear(year + 1)
		holidays:fetchJapaneseYear(year - 1)
		holidays:fetchJapaneseYear(year)
		holidays:fetchJapaneseYear(year + 1)
	end)
	Log.diag("init: holiday fetch scheduled ok=" .. tostring(ok)
		.. (ok and "" or (" err=" .. tostring(err))) .. string.format(" (%.1f ms)", Log.nowMs() - t0))

	-- Follow display changes: every screen keeps a calendar.
	if hs.screen and hs.screen.watcher then
		obj.screen_watcher = hs.screen.watcher.new(function()
			scheduleCanvasRebuild("screen layout changed")
		end)
		obj.screen_watcher:start()
		Log.diag("init: screen watcher started")
	end

	-- Prewarm the year view a few seconds later (built and drawn while hidden).
	-- Keep the handle: an unreferenced doAfter timer can be collected first.
	if hs.timer and hs.timer.doAfter then
		obj.prewarm_timer = hs.timer.doAfter(PREWARM_DELAY_S, prewarmYear)
		Log.diag(string.format("init: year prewarm scheduled in %ds", PREWARM_DELAY_S))
	end

	-- Periodic refresh of the visible view: a month rollover or a holiday cache
	-- update shows up without a reload.
	if obj.timer == nil then
		obj.timer = hs.timer.doEvery(REFRESH_S, function()
			obj:render()
		end)
		obj.timer:setNextTrigger(0)
	else
		obj.timer:start()
	end
	Log.diag(string.format("init done in %.1f ms", Log.nowMs() - t0))
end

return obj
