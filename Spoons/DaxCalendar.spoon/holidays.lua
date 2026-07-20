--- === Holidays ===
---
--- Chinese holiday data module for DaxCalendar
--- Fetches from holiday.ailcc.com API, falls back to embedded data

local obj = {}
obj.__index = obj

-- ============================================================
-- Holiday name → abbreviation mapping
-- ============================================================
local HOLIDAY_ABBR = {
    ["元旦节"] = "元",
    ["元旦"]    = "元",
    ["春节"]    = "春",
    ["清明节"]  = "清",
    ["清明"]    = "清",
    ["劳动节"]  = "劳",
    ["端午节"]  = "端",
    ["端午"]    = "端",
    ["中秋节"]  = "中",
    ["中秋"]    = "中",
    ["国庆节"]  = "国",
    ["国庆"]    = "国",
    ["除夕"]    = "除",
}

-- ============================================================
-- Japanese holiday abbreviation mapping
-- ============================================================
local JP_ABBR = {
    ["元日"]         = "元",
    ["成人の日"]     = "成",
    ["建国記念の日"] = "建",
    ["天皇誕生日"]   = "天",
    ["春分の日"]     = "春",
    ["昭和の日"]     = "昭",
    ["憲法記念日"]   = "憲",
    ["みどりの日"]   = "緑",
    ["こどもの日"]   = "子",
    ["海の日"]       = "海",
    ["山の日"]       = "山",
    ["敬老の日"]     = "敬",
    ["秋分の日"]     = "秋",
    ["スポーツの日"] = "ス",
    ["文化の日"]     = "文",
    ["勤労感謝の日"] = "勤",
    ["振替休日"]     = "振",
    ["国民の休日"]   = "休",
}

-- ============================================================
-- Embedded fallback data (will be augmented by API fetch)
-- ============================================================
local EMBEDDED = {
    ["2025"] = {
        ["01-01"] = { name = "元旦",      abbr = "元" },
        ["01-28"] = { name = "春节",      abbr = "春" },
        ["01-29"] = { name = "春节",      abbr = "春" },
        ["01-30"] = { name = "春节",      abbr = "春" },
        ["01-31"] = { name = "春节",      abbr = "春" },
        ["02-01"] = { name = "春节",      abbr = "春" },
        ["02-02"] = { name = "春节",      abbr = "春" },
        ["02-03"] = { name = "春节",      abbr = "春" },
        ["02-04"] = { name = "春节",      abbr = "春" },
        ["04-04"] = { name = "清明节",    abbr = "清" },
        ["04-05"] = { name = "清明节",    abbr = "清" },
        ["04-06"] = { name = "清明节",    abbr = "清" },
        ["05-01"] = { name = "劳动节",    abbr = "劳" },
        ["05-02"] = { name = "劳动节",    abbr = "劳" },
        ["05-03"] = { name = "劳动节",    abbr = "劳" },
        ["05-04"] = { name = "劳动节",    abbr = "劳" },
        ["05-05"] = { name = "劳动节",    abbr = "劳" },
        ["05-31"] = { name = "端午节",    abbr = "端" },
        ["06-01"] = { name = "端午节",    abbr = "端" },
        ["06-02"] = { name = "端午节",    abbr = "端" },
        ["10-01"] = { name = "国庆节",    abbr = "国" },
        ["10-02"] = { name = "国庆节",    abbr = "国" },
        ["10-03"] = { name = "国庆节",    abbr = "国" },
        ["10-04"] = { name = "国庆节",    abbr = "国" },
        ["10-05"] = { name = "国庆节",    abbr = "国" },
        ["10-06"] = { name = "国庆节",    abbr = "国" },
        ["10-07"] = { name = "国庆节",    abbr = "国" },
        ["10-08"] = { name = "国庆节",    abbr = "国" },
    },
    ["2026"] = {
        ["01-01"] = { name = "元旦",      abbr = "元" },
        ["01-02"] = { name = "元旦",      abbr = "元" },
        ["01-03"] = { name = "元旦",      abbr = "元" },
        ["02-15"] = { name = "春节",      abbr = "春" },
        ["02-16"] = { name = "春节",      abbr = "春" },
        ["02-17"] = { name = "春节",      abbr = "春" },
        ["02-18"] = { name = "春节",      abbr = "春" },
        ["02-19"] = { name = "春节",      abbr = "春" },
        ["02-20"] = { name = "春节",      abbr = "春" },
        ["02-21"] = { name = "春节",      abbr = "春" },
        ["02-22"] = { name = "春节",      abbr = "春" },
        ["02-23"] = { name = "春节",      abbr = "春" },
        ["04-04"] = { name = "清明",      abbr = "清" },
        ["04-05"] = { name = "清明",      abbr = "清" },
        ["04-06"] = { name = "清明",      abbr = "清" },
        ["05-01"] = { name = "劳动节",    abbr = "劳" },
        ["05-02"] = { name = "劳动节",    abbr = "劳" },
        ["05-03"] = { name = "劳动节",    abbr = "劳" },
        ["05-04"] = { name = "劳动节",    abbr = "劳" },
        ["05-05"] = { name = "劳动节",    abbr = "劳" },
        ["06-19"] = { name = "端午节",    abbr = "端" },
        ["06-20"] = { name = "端午节",    abbr = "端" },
        ["06-21"] = { name = "端午节",    abbr = "端" },
        ["09-25"] = { name = "中秋节",    abbr = "中" },
        ["09-26"] = { name = "中秋节",    abbr = "中" },
        ["09-27"] = { name = "中秋节",    abbr = "中" },
        ["10-01"] = { name = "国庆节",    abbr = "国" },
        ["10-02"] = { name = "国庆节",    abbr = "国" },
        ["10-03"] = { name = "国庆节",    abbr = "国" },
        ["10-04"] = { name = "国庆节",    abbr = "国" },
        ["10-05"] = { name = "国庆节",    abbr = "国" },
        ["10-06"] = { name = "国庆节",    abbr = "国" },
        ["10-07"] = { name = "国庆节",    abbr = "国" },
    },
    ["2027"] = {
        -- Will be populated by API fetch; fallback placeholder
    },
}

-- ============================================================
-- Embedded Japanese holiday data (fallback)
-- ============================================================
local JP_EMBEDDED = {
    ["2025"] = {
        ["01-01"] = { name = "元日",         abbr = "元" },
        ["01-13"] = { name = "成人の日",     abbr = "成" },
        ["02-11"] = { name = "建国記念の日", abbr = "建" },
        ["02-23"] = { name = "天皇誕生日",   abbr = "天" },
        ["02-24"] = { name = "振替休日",     abbr = "振" },
        ["03-20"] = { name = "春分の日",     abbr = "春" },
        ["04-29"] = { name = "昭和の日",     abbr = "昭" },
        ["05-03"] = { name = "憲法記念日",   abbr = "憲" },
        ["05-04"] = { name = "みどりの日",   abbr = "緑" },
        ["05-05"] = { name = "こどもの日",   abbr = "子" },
        ["05-06"] = { name = "振替休日",     abbr = "振" },
        ["07-21"] = { name = "海の日",       abbr = "海" },
        ["08-11"] = { name = "山の日",       abbr = "山" },
        ["09-15"] = { name = "敬老の日",     abbr = "敬" },
        ["09-23"] = { name = "秋分の日",     abbr = "秋" },
        ["10-13"] = { name = "スポーツの日", abbr = "ス" },
        ["11-03"] = { name = "文化の日",     abbr = "文" },
        ["11-23"] = { name = "勤労感謝の日", abbr = "勤" },
        ["11-24"] = { name = "振替休日",     abbr = "振" },
    },
    ["2026"] = {
        ["01-01"] = { name = "元日",         abbr = "元" },
        ["01-12"] = { name = "成人の日",     abbr = "成" },
        ["02-11"] = { name = "建国記念の日", abbr = "建" },
        ["02-23"] = { name = "天皇誕生日",   abbr = "天" },
        ["03-20"] = { name = "春分の日",     abbr = "春" },
        ["04-29"] = { name = "昭和の日",     abbr = "昭" },
        ["05-03"] = { name = "憲法記念日",   abbr = "憲" },
        ["05-04"] = { name = "みどりの日",   abbr = "緑" },
        ["05-05"] = { name = "こどもの日",   abbr = "子" },
        ["05-06"] = { name = "振替休日",     abbr = "振" },
        ["07-20"] = { name = "海の日",       abbr = "海" },
        ["08-11"] = { name = "山の日",       abbr = "山" },
        ["09-21"] = { name = "敬老の日",     abbr = "敬" },
        ["09-22"] = { name = "国民の休日",   abbr = "休" },
        ["09-23"] = { name = "秋分の日",     abbr = "秋" },
        ["10-12"] = { name = "スポーツの日", abbr = "ス" },
        ["11-03"] = { name = "文化の日",     abbr = "文" },
        ["11-23"] = { name = "勤労感謝の日", abbr = "勤" },
    },
    ["2027"] = {
        ["01-01"] = { name = "元日",         abbr = "元" },
        ["01-11"] = { name = "成人の日",     abbr = "成" },
        ["02-11"] = { name = "建国記念の日", abbr = "建" },
        ["02-23"] = { name = "天皇誕生日",   abbr = "天" },
        ["03-21"] = { name = "春分の日",     abbr = "春" },
        ["03-22"] = { name = "振替休日",     abbr = "振" },
        ["04-29"] = { name = "昭和の日",     abbr = "昭" },
        ["05-03"] = { name = "憲法記念日",   abbr = "憲" },
        ["05-04"] = { name = "みどりの日",   abbr = "緑" },
        ["05-05"] = { name = "こどもの日",   abbr = "子" },
        ["07-19"] = { name = "海の日",       abbr = "海" },
        ["08-11"] = { name = "山の日",       abbr = "山" },
        ["09-20"] = { name = "敬老の日",     abbr = "敬" },
        ["09-23"] = { name = "秋分の日",     abbr = "秋" },
        ["10-11"] = { name = "スポーツの日", abbr = "ス" },
        ["11-03"] = { name = "文化の日",     abbr = "文" },
        ["11-23"] = { name = "勤労感謝の日", abbr = "勤" },
    },
}

-- ============================================================
-- Internal state
-- ============================================================
local data  = {}
local cache = {}
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

--- Derive abbreviation from holiday name
local function abbrFor(name)
    local base = parseName(name)
    return HOLIDAY_ABBR[base] or base:sub(1, 1)
end

--- Key for date lookup
local function dateKey(year, month, day)
    return string.format("%02d-%02d", month, day)
end

--- Year string for data indexing
local function yearKey(year)
    return tostring(year)
end

--- Cache file path
local function cachePath()
    return hs.configdir .. "/Spoons/DaxCalendar.spoon/holiday_cache.json"
end

-- ============================================================
-- Save / Load local cache
-- ============================================================

local function saveCache()
    local path = cachePath()
    local ok, err = hs.json.encode(data)
    if ok then
        local f = io.open(path, "w")
        if f then
            f:write(ok)
            f:close()
        end
    end
end

local function loadCache()
    local path = cachePath()
    local f = io.open(path, "r")
    if f then
        local raw = f:read("*a")
        f:close()
        local ok, decoded = pcall(hs.json.decode, raw)
        if ok and decoded then
            for yr, days in pairs(decoded) do
                data[yr] = days
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- Japanese holiday cache save / load (defined before load())
-- ============================================================

local function saveJpCache()
    local path = hs.configdir .. "/Spoons/DaxCalendar.spoon/holiday_jp_cache.json"
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
    local path = hs.configdir .. "/Spoons/DaxCalendar.spoon/holiday_jp_cache.json"
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
    -- Load embedded Chinese holidays
    for yr, days in pairs(EMBEDDED) do
        data[yr] = data[yr] or {}
        for k, v in pairs(days) do
            data[yr][k] = v
        end
    end
    -- Load cached Chinese holidays (may override embedded with API-fresh data)
    loadCache()
    -- Load embedded Japanese holidays
    for yr, days in pairs(JP_EMBEDDED) do
        jp_data[yr] = jp_data[yr] or {}
        for k, v in pairs(days) do
            jp_data[yr][k] = v
        end
    end
    -- Load cached Japanese holidays
    loadJpCache()
    return self
end

--- Holidays:fetchYear(year, [callback])
--- Fetch holiday data from remote API
function obj:fetchYear(year, callback)
    local yr = yearKey(year)
    local url = "https://holiday.ailcc.com/api/holiday/year/" .. yr

    hs.http.get(url, nil, function(code, body)
        if code == 200 then
            local ok, result = pcall(hs.json.decode, body)
            if ok and result and result.code == 0 and result.holiday then
                data[yr] = data[yr] or {}
                for dateKeyRaw, info in pairs(result.holiday) do
                    if info.holiday then
                        data[yr][dateKeyRaw] = {
                            name = parseName(info.name),
                            abbr = abbrFor(info.name),
                        }
                    end
                end
                saveCache()
                if callback then callback(true) end
                return
            end
        end
        hs.printf("[DaxCalendar] Failed to fetch holidays for " .. yr)
        if callback then callback(false) end
    end)
end

--- Holidays:fetchJapaneseYear(year, [callback])
--- Fetch Japanese holiday data from holidays-jp.github.io
function obj:fetchJapaneseYear(year, callback)
    local yr = tostring(year)
    local url = "https://holidays-jp.github.io/api/v1/" .. yr .. "/date.json"

    hs.http.get(url, nil, function(code, body)
        if code == 200 then
            local ok, result = pcall(hs.json.decode, body)
            if ok and result then
                jp_data[yr] = jp_data[yr] or {}
                for dateStr, name in pairs(result) do
                    -- dateStr is "YYYY-MM-DD", extract month-day
                    local md = dateStr:sub(6, 10) -- "MM-DD"
                    local baseName = name
                    local abbr = JP_ABBR[baseName] or baseName:sub(1, 1)
                    jp_data[yr][md] = { name = baseName, abbr = abbr }
                end
                saveJpCache()
                if callback then callback(true) end
                return
            end
        end
        hs.printf("[DaxCalendar] Failed to fetch Japanese holidays for " .. yr)
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

--- Holidays:holidayColor()
--- Returns color table for holiday text
function obj:holidayColor()
    return { hex = "#FFB800" }  -- bright amber/gold
end

return obj
