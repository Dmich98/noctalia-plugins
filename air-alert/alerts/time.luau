--!strict

local function parseSince(timestamp: string?): number?
    if typeof(timestamp) ~= "string" then
        return nil
    end
    local year, month, day, hour, minute, second =
        timestamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if
        not year
        or not month
        or not day
        or not hour
        or not minute
        or not second
        or (timestamp:sub(20) ~= "Z" and not timestamp:sub(20):match("^%.%d+Z$"))
    then
        return nil
    end
    local ok, seconds = pcall(os.time, {
        year = tonumber(year) :: number,
        month = tonumber(month) :: number,
        day = tonumber(day) :: number,
        hour = tonumber(hour) :: number,
        min = tonumber(minute) :: number,
        sec = tonumber(second) :: number,
    })
    if not ok then
        return nil
    end
    -- Reject invalid dates that os.time might normalize (e.g. February 31).
    if noctalia.formatTime("%Y-%m-%dT%H:%M:%S", seconds, "UTC") ~= timestamp:sub(1, 19) then
        return nil
    end
    return seconds
end

local function formatTime(seconds: number, pattern: string?): string
    return noctalia.formatTime(pattern or "%d.%m.%Y %H:%M", seconds, "Europe/Kyiv")
end

local function formatDuration(since: number, now: number): string
    if since > now then
        return noctalia.tr("time.invalid")
    end
    local minutes = math.floor((now - since) / 60)
    if minutes == 0 then
        return noctalia.tr("time.less_than_minute")
    end
    if minutes < 60 then
        return noctalia.tr(
            "time.minutes",
            { minutes = minutes } :: { [string]: string | number | boolean }
        )
    end
    return noctalia.tr(
        "time.hours_minutes",
        { hours = math.floor(minutes / 60), minutes = minutes % 60 } :: { [string]: string | number | boolean }
    )
end

return { parseSince = parseSince, formatTime = formatTime, formatDuration = formatDuration }
