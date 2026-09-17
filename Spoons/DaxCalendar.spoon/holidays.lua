--- === Holidays ===
---
--- Chinese holiday data module for DaxCalendar
--- Fetches from timor.tech API (放假 + 调休补班 in one payload), falls back to embedded data

local obj = {}
obj.__index = obj

-- 中国节假日角标统一显示"休"（不区分具体节日）
local HOLIDAY_ABBR = "休"

-- 调休补班 label (weekend that is actually a workday)
local WORKDAY_ABBR = "班"

-- timor.tech rejects requests without a browser-ish User-Agent
local API_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"

-- ============================================================
-- 日本节假日角标同样统一显示"休"（颜色仍用天蓝区分）
local JP_HOLIDAY_ABBR = "休"

-- Embedded fallback data (about 170 lines of pure data) lives in its own
-- file; the API and cache results are merged on top of it.
local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local embedded = dofile(DIR .. "/holidays_data.lua")
local EMBEDDED = embedded.cn
local WORKDAY_EMBEDDED = embedded.workdays
local JP_EMBEDDED = embedded.jp

-- ============================================================
-- Internal state
-- ============================================================
local data  = {}      -- data[year]["MM-DD"]     = { name, abbr }  放假
local cache = {}
local workdays = {}   -- workdays[year]["MM-DD"] = { name, abbr, target }  调休补班
local jp_data  = {}
local jp_cache = {}

-- ============================================================
-- Helpers
-- ============================================================

--- Parse raw API name (e.g. "元旦节（休）" → base name)
local function parseName(raw)
    if not raw then return "" end
    return raw:gsub("%（[^）]*%）", "")
end

--- Key for date lookup
local function dateKey(year, month, day)
    return string.format("%02d-%02d", month, day)
end

--- Year string for data indexing
local function yearKey(year)
    return tostring(year)
end

--- Where the caches and the fetch log live: beside the Spoon, not inside it, so
--- the Spoon directory holds exactly what its repository tracks.
local function dataDir()
    local dir = hs.configdir .. "/DaxCalendar"
    if hs.fs and hs.fs.mkdir then hs.fs.mkdir(dir) end   -- no-op when it exists
    return dir
end

--- Cache file path
local function cachePath()
    return dataDir() .. "/holiday_cache.json"
end

local function tblCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- Report to the console AND to fetch.log, so a silent network failure is still
--- visible later (the console buffer is easy to miss / can be scrolled away).
local function logLine(msg)
    local line = os.date("%Y-%m-%d %H:%M:%S") .. "  [fetch] " .. msg .. "\n"
    local fetch_log = dataDir() .. "/fetch.log"
    local f = io.open(fetch_log, "a")
    if f then
        f:write(line)
        f:close()
    else
        line = line:gsub("\n$", "") .. "\n          (NOTE: " .. fetch_log .. " is NOT writable)\n"
    end
    -- always mirror next to the init/toggle diagnostics in /tmp, so a missing
    -- fetch.log can never hide what the fetch layer did
    local mirror = io.open("/tmp/daxcalendar.log", "a")
    if mirror then
        mirror:write(line)
        mirror:close()
    end
    hs.printf("[DaxCalendar] " .. msg)
end

local function msSince(t0)
    return math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000)
end

--- GET a URL as text. hs.http gets first crack. If it never calls back at all
--- (observed on this machine: no error, no callback, no cache) fall back to the
--- system curl through hs.task, which is known to reach these APIs here.
-- Timers made with hs.timer.doAfter stop firing if nothing references them, so
-- pending watchdogs are parked here until they either fire or are cancelled.
local pending_watchdogs = {}

local function httpGetText(url, callback)
    local answered = false
    local watchdog
    watchdog = hs.timer.doAfter(12, function()
        if answered then return end
        answered = true
        pending_watchdogs[watchdog] = nil
        logLine("watchdog fired: no answer for " .. url .. " within 12s -> trying curl")
        local task = hs.task.new("/usr/bin/curl", function(exitCode, stdout, stderr)
            local body = stdout or ""
            if exitCode == 0 and body ~= "" then
                callback(200, body)
            else
                logLine("curl fallback failed (exit=" .. tostring(exitCode) .. "): " .. tostring(stderr))
                callback(0, "")
            end
        end, { "-s", "--max-time", "20", "-A", API_UA, url })
        task:start()
    end)
    pending_watchdogs[watchdog] = true
    local t_call = hs.timer.secondsSinceEpoch()
    -- hs.http.get() is SYNCHRONOUS and takes no callback (it returns code, body,
    -- headers). The original spoon -- and my first port -- called it with a
    -- callback, so the holiday data was never applied or cached. asyncGet is the
    -- real asynchronous API.
    hs.http.asyncGet(url, { ["User-Agent"] = API_UA }, function(code, body)
        if answered then return end
        answered = true
        pending_watchdogs[watchdog] = nil
        watchdog:stop()
        logLine(string.format("hs.http answered %s in %d ms (http=%s, %d bytes)",
            url:match("([^/]+)$"), msSince(t_call), tostring(code), #(body or "")))
        callback(code, body)
    end)
    logLine(string.format("hs.http.asyncGet(%s) dispatched in %d ms", url:match("([^/]+)$"), msSince(t_call)))
end

-- ============================================================
-- Save / Load local cache
-- ============================================================

--- Merge { year = { "MM-DD" = entry } } into a store, keeping existing entries
local function mergeYears(target, source)
    for yr, days in pairs(source or {}) do
        target[yr] = target[yr] or {}
        for k, v in pairs(days) do
            target[yr][k] = v
        end
    end
end

--- Replace whole years in a store; empty payloads are ignored so
--- embedded fallback data survives an API year with no entries
local function replaceYears(target, source)
    for yr, days in pairs(source or {}) do
        if next(days) ~= nil then
            target[yr] = days
        end
    end
end

local function saveCache()
    local payload = { holidays = data, workdays = workdays }
    local t0 = hs.timer.secondsSinceEpoch()
    local jsonStr, err = hs.json.encode(payload)
    if not jsonStr then
        logLine("cache NOT written: hs.json.encode failed (" .. tostring(err) .. ")")
        return
    end
    local path = cachePath()
    local f, ferr = io.open(path, "w")
    if not f then
        logLine("cache NOT written: cannot open " .. path .. " (" .. tostring(ferr) .. ")")
        return
    end
    f:write(jsonStr)
    f:close()
    logLine("cache written: " .. path .. " (" .. tostring(#jsonStr) .. " bytes, " .. tostring(msSince(t0)) .. " ms)")
end

local function loadCache()
    local f = io.open(cachePath(), "r")
    if not f then return false end
    local raw = f:read("*a")
    f:close()
    local ok, decoded = pcall(hs.json.decode, raw)
    if not ok or type(decoded) ~= "table" then return false end
    if decoded.holidays or decoded.workdays then
        replaceYears(data, decoded.holidays)
        replaceYears(workdays, decoded.workdays)
    else
        -- legacy format: bare { year = { "MM-DD" = ... } } holiday map
        replaceYears(data, decoded)
    end
    return true
end

-- ============================================================
-- Japanese holiday cache save / load (defined before load())
-- ============================================================

local function saveJpCache()
    local path = dataDir() .. "/holiday_jp_cache.json"
    local ok, err = hs.json.encode(jp_data)
    if ok then
        local f = io.open(path, "w")
        if f then
            f:write(ok)
            f:close()
        end
    end
end

local function loadJpCache()
    local path = dataDir() .. "/holiday_jp_cache.json"
    local f = io.open(path, "r")
    if f then
        local raw = f:read("*a")
        f:close()
        local ok, decoded = pcall(hs.json.decode, raw)
        if ok and decoded then
            for yr, days in pairs(decoded) do
                jp_data[yr] = days
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- Public Methods
-- ============================================================

--- Holidays:load()
--- Load embedded data + cached data
function obj:load()
    -- Load embedded Chinese holidays + 调休补班 workdays
    mergeYears(data, EMBEDDED)
    mergeYears(workdays, WORKDAY_EMBEDDED)
    -- Load cached data (may override embedded with API-fresh data)
    loadCache()
    -- Load embedded Japanese holidays
    mergeYears(jp_data, JP_EMBEDDED)
    -- Load cached Japanese holidays
    loadJpCache()
    return self
end

--- Holidays:fetchYear(year, [callback])
--- Fetch holiday data from remote API
function obj:fetchYear(year, callback)
    local yr = yearKey(year)
    -- timor.tech returns both 放假 (holiday=true) and 调休补班 (holiday=false)
    local url = "https://timor.tech/api/holiday/year/" .. yr

    httpGetText(url, function(code, body)
        local ok, result = false, nil
        if code == 200 then
            ok, result = pcall(hs.json.decode, body)
        end
        if ok and result and result.code == 0 and result.holiday then
            local hd, wd = {}, {}
            for dateKeyRaw, info in pairs(result.holiday) do
                if info.holiday then
                    hd[dateKeyRaw] = {
                        name = parseName(info.name),
                        abbr = HOLIDAY_ABBR,
                    }
                else
                    wd[dateKeyRaw] = {
                        name = parseName(info.name),
                        abbr = WORKDAY_ABBR,
                        target = info.target,
                    }
                end
            end
            replaceYears(data, { [yr] = hd })
            replaceYears(workdays, { [yr] = wd })
            saveCache()
            logLine("fetched " .. yr .. ": " .. tostring(tblCount(hd)) .. " holidays, "
                .. tostring(tblCount(wd)) .. " workdays")
            if callback then callback(true) end
            return
        end
        logLine("fetch FAILED for " .. yr .. " (http=" .. tostring(code)
            .. ", bytes=" .. tostring(#(body or "")) .. ")")
        if callback then callback(false) end
    end)
end

--- Holidays:fetchJapaneseYear(year, [callback])
--- Fetch Japanese holiday data from holidays-jp.github.io
function obj:fetchJapaneseYear(year, callback)
    local yr = tostring(year)
    local url = "https://holidays-jp.github.io/api/v1/" .. yr .. "/date.json"

    httpGetText(url, function(code, body)
        if code == 200 then
            local ok, result = pcall(hs.json.decode, body)
            if ok and result then
                jp_data[yr] = jp_data[yr] or {}
                for dateStr, name in pairs(result) do
                    -- dateStr is "YYYY-MM-DD", extract month-day
                    local md = dateStr:sub(6, 10) -- "MM-DD"
                    local baseName = name
                    local abbr = JP_HOLIDAY_ABBR
                    jp_data[yr][md] = { name = baseName, abbr = abbr }
                end
                saveJpCache()
                logLine("fetched JP " .. yr .. ": " .. tostring(tblCount(jp_data[yr])) .. " holidays")
                if callback then callback(true) end
                return
            end
        end
        logLine("JP fetch FAILED for " .. yr .. " (http=" .. tostring(code) .. ")")
        if callback then callback(false) end
    end)
end

--- Holidays:isJapaneseHoliday(year, month, day)
--- Returns (true, {name, abbr, country="JP"}) or (false, nil)
function obj:isJapaneseHoliday(year, month, day)
    local yr = tostring(year)
    local key = dateKey(year, month, day)
    local yd = jp_data[yr]
    if yd and yd[key] then
        local info = yd[key]
        info.country = "JP"
        return true, info
    end
    return false, nil
end

--- Holidays:japanHolidayColor()
--- Returns color table for Japanese holiday text
function obj:japanHolidayColor()
    return { hex = "#4FC3F7" }  -- sky blue
end

--- Holidays:isHoliday(year, month, day)
--- Returns (true, {name, abbr}) or (false, nil)
function obj:isHoliday(year, month, day)
    local yr = yearKey(year)
    local key = dateKey(year, month, day)
    local yd = data[yr]
    if yd and yd[key] then
        return true, yd[key]
    end
    return false, nil
end

--- Get a table of holidays for a specific (year, month)
--- Returns { ["dd"] = {name, abbr}, ... }
function obj:monthHolidays(year, month)
    local yr = yearKey(year)
    local prefix = string.format("%02d-", month)
    local result = {}
    if data[yr] then
        for k, v in pairs(data[yr]) do
            if k:sub(1, 3) == prefix then
                result[k:sub(4, 5)] = v
            end
        end
    end
    return result
end

--- Holidays:isWorkday(year, month, day)
--- 调休补班日（本该休息的周末被调整为工作日）
--- Returns (true, {name, abbr="班", target}) or (false, nil)
function obj:isWorkday(year, month, day)
    local yr = yearKey(year)
    local key = dateKey(year, month, day)
    local yd = workdays[yr]
    if yd and yd[key] then
        return true, yd[key]
    end
    return false, nil
end

--- Holidays:holidayColor()
--- Returns color table for holiday text
function obj:holidayColor()
    return { hex = "#FFB800" }  -- bright amber/gold
end

--- Holidays:workdayColor()
--- Returns color table for 调休补班 labels
function obj:workdayColor()
    return { hex = "#9AA7B8" }  -- slate blue-grey
end

return obj
