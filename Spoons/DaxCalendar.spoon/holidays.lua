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
-- Internal state
-- ============================================================
local data  = {}
local cache = {}

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
-- Public Methods
-- ============================================================

--- Holidays:load()
--- Load embedded data + cached data
function obj:load()
    -- Load embedded
    for yr, days in pairs(EMBEDDED) do
        data[yr] = data[yr] or {}
        for k, v in pairs(days) do
            data[yr][k] = v
        end
    end
    -- Load cached (may override embedded with API-fresh data)
    loadCache()
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
    return { hex = "#FF6B35" }  -- warm orange-red
end

return obj
