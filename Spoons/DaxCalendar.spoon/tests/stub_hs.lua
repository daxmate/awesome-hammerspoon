-- Stub of the hs.* API surface DaxCalendar uses, so the spoon can be loaded and
-- driven headlessly (no GUI, no Hammerspoon) from plain `lua`.
--
-- The stub is deliberately strict where the real API is strict:
--   * canvas element writes must be contiguous (index <= elementCount()+1),
--     like hs.canvas' userdata does;
--   * element frames are resolved against the canvas' CURRENT size when they
--     are fractions (0..1), exactly like hs.canvas does -- that scaling is what
--     keeps the calendar's proportions when the canvas is resized.
-- Timers are recorded instead of firing, so tests can trigger them on demand.

local M = {}

local function newScreen(name, id, x, y, w, h)
	return {
		_name = name,
		_id = id,
		_frame = { x = x, y = y, w = w, h = h },
		name = function(self) return self._name end,
		id = function(self) return self._id end,
		fullFrame = function(self)
			local f = self._frame
			return { x = f.x, y = f.y, w = f.w, h = f.h }
		end,
	}
end

M.newScreen = newScreen

--- Build the stub `hs` table.
--- opts.screens : array of screens (defaults to a single built-in screen)
--- returns hs, state  (state carries created canvases + pending timers/watchers)
function M.build(opts)
	opts = opts or {}
	local screens = opts.screens or { newScreen("Built-in Retina Display", "built-in", 0, 0, 1512, 982) }

	local state = { canvases = {}, after_timers = {}, every_timers = {}, watchers = {}, hotkeys = {}, logs = {} }

	local Canvas = {}
	function Canvas:show() self._visible = true end
	function Canvas:hide() self._visible = false end
	function Canvas:delete() self._deleted = true end
	function Canvas:behavior(v) self._behavior = v end
	function Canvas:level(v) self._level = v end
	function Canvas:mouseCallback(fn) self._callback = fn end
	function Canvas:frame() return { x = self._f.x, y = self._f.y, w = self._f.w, h = self._f.h } end
	function Canvas:size(s) self._f.w, self._f.h = s.w, s.h end
	function Canvas:elementCount() return #self._order end
	--- Resolve an element's frame the way hs.canvas does: fractions are relative
	--- to the canvas' current size, plain numbers are points.
	function Canvas:resolvedFrame(i)
		local e = rawget(self, "_store")[i]
		if not e or not e.frame then return nil end
		local f = self._f
		local function ax(v, total) return (type(v) == "string" and tonumber(v) or v) * (type(v) == "string" and total or 1) end
		local x, y, w, h = ax(e.frame.x, f.w), ax(e.frame.y, f.h), ax(e.frame.w, f.w), ax(e.frame.h, f.h)
		return { x = x, y = y, w = w, h = h }
	end

	local function newCanvas(frame)
		local order = {}
		local c = setmetatable({ _f = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }, _order = order, _store = {} }, {
			__index = function(t, k)
				if type(k) == "number" then return rawget(t, "_store")[k] end
				return Canvas[k]
			end,
			__newindex = function(t, k, v)
				if type(k) ~= "number" then rawset(t, k, v) return end
				if k > #order + 1 then
					error(string.format("non-contiguous canvas append: index %d with %d element(s)", k, #order))
				end
				if rawget(t, "_store")[k] == nil then order[#order + 1] = k end
				rawget(t, "_store")[k] = v
			end,
		})
		state.canvases[#state.canvases + 1] = c
		return c
	end

	local hs = {
		configdir = os.getenv("HOME") .. "/.hammerspoon",
		canvas = {
			new = newCanvas,
			windowBehaviors = { canJoinAllSpaces = 1 },
			windowLevels = { desktopIcon = 0 },
		},
		screen = {
			allScreens = function() return screens end,
			mainScreen = function() return screens[1] end,
			watcher = {
				new = function(fn)
					local w = { start = function() return true end, stop = function() end, fire = fn }
					state.watchers[#state.watchers + 1] = w
					return w
				end,
			},
		},
		timer = {
			doAfter = function(sec, fn)
				local t = { _delay = sec, fire = fn, stop = function() end, start = function() return true end }
				state.after_timers[#state.after_timers + 1] = t
				return t
			end,
			doEvery = function(sec, fn)
				local t = { _delay = sec, fire = fn, stop = function() end, start = function() return true end, setNextTrigger = function() end }
				state.every_timers[#state.every_timers + 1] = t
				return t
			end,
			secondsSinceEpoch = function() return os.time() end,
		},
		hotkey = {
			bind = function(mods, key, fn)
				local h = { mods = mods, key = key, fire = fn, delete = function() end }
				state.hotkeys[#state.hotkeys + 1] = h
				return h
			end,
			alertDuration = 0,
		},
		printf = function(msg) state.logs[#state.logs + 1] = msg end,
		http = { asyncGet = function() end, get = function() return 0, "" end },
		json = { decode = function() return nil, "stub" end, encode = function() return "{}", nil end },
		task = { new = function() return { start = function() return true end } end },
		fs = { pathToAbsolute = function(p) return p end, mkdir = function() return true end },
	}

	--- Replace the attached screens and fire the screen watcher.
	function state.setScreens(list)
		for i = #screens, 1, -1 do screens[i] = nil end
		for i, s in ipairs(list) do screens[i] = s end
		for _, w in ipairs(state.watchers) do w.fire() end
	end

	--- Fire every scheduled doAfter timer (the screen-change debounce, the year
	--- prewarm, ...). doEvery timers (the refresh tick) are left alone.
	function state.fireAfterTimers()
		local pending = state.after_timers
		state.after_timers = {}
		for _, t in ipairs(pending) do t.fire() end
	end

	return hs, state
end

return M
