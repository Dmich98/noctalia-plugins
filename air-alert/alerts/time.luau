--!strict

local daysBeforeMonth = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
-- Gregorian days before 1970-01-01, used to avoid the machine's local time zone.
local daysBefore1970 = 719162

local function validTimestamp(value: any): boolean
    if typeof(value) ~= "string" then
        return false
    end
    local yearText, monthText, dayText, hourText, minuteText, secondText, zone =
        value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if not yearText or not zone then
        return false
    end
    local year = tonumber(yearText) :: number
    local month = tonumber(monthText) :: number
    local day = tonumber(dayText) :: number
    local hour = tonumber(hourText) :: number
    local minute = tonumber(minuteText) :: number
    local second = tonumber(secondText) :: number
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year == 0 or month < 1 or month > 12 or day < 1 or day > days[month] then
        return false
    end
    if hour > 23 or minute > 59 or second > 59 then
        return false
    end
    if zone:sub(1, 1) == "." then
        local fraction = zone:match("^%.%d+")
        if not fraction then
            return false
        end
        zone = zone:sub(#fraction + 1)
    end
    if zone == "Z" then
        return true
    end
    local sign, zoneHourText, zoneMinuteText = zone:match("^([%+%-])(%d%d):(%d%d)$")
    if not sign then
        return false
    end
    local zoneHour = tonumber(zoneHourText) :: number
    local zoneMinute = tonumber(zoneMinuteText) :: number
    return zoneHour <= 14 and zoneMinute <= 59 and (zoneHour < 14 or zoneMinute == 0)
end

local function keepValid(value: any): string?
    return validTimestamp(value) and value or nil
end

local function toUnixSeconds(value: string?): number?
    local timestamp = keepValid(value)
    if not timestamp then
        return nil
    end
    local year = tonumber(timestamp:sub(1, 4)) :: number
    local month = tonumber(timestamp:sub(6, 7)) :: number
    local day = tonumber(timestamp:sub(9, 10)) :: number
    local hour = tonumber(timestamp:sub(12, 13)) :: number
    local minute = tonumber(timestamp:sub(15, 16)) :: number
    local second = tonumber(timestamp:sub(18, 19)) :: number
    local previousYear = year - 1
    local daysBeforeYear = 365 * previousYear
        + math.floor(previousYear / 4)
        - math.floor(previousYear / 100)
        + math.floor(previousYear / 400)
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local leapDay = leap and month > 2 and 1 or 0
    local days = daysBeforeYear + daysBeforeMonth[month] + leapDay + day - 1 - daysBefore1970
    local seconds = days * 86400 + hour * 3600 + minute * 60 + second
    if timestamp:sub(-1) ~= "Z" then
        local sign, zoneHour, zoneMinute = timestamp:match("([%+%-])(%d%d):(%d%d)$")
        local offset = ((tonumber(zoneHour) :: number) * 60 + (tonumber(zoneMinute) :: number)) * 60
        seconds += sign == "+" and -offset or offset
    end
    return seconds
end

return { keepValid = keepValid, toUnixSeconds = toUnixSeconds }
