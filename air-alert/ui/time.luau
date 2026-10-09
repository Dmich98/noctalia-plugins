--!strict

local alertTime = require("../alerts/time.luau")

local function formatKyivTimestamp(value: string?): string?
    local seconds = alertTime.toUnixSeconds(value)
    if not seconds or not noctalia.isValidTimezone("Europe/Kyiv") then
        return nil
    end
    return noctalia.formatTime("%d.%m.%Y %H:%M", seconds, "Europe/Kyiv")
end

local function formatDuration(value: string?): string?
    local since = alertTime.toUnixSeconds(value)
    if not since then
        return nil
    end
    local elapsed = math.floor(noctalia.nowMs() / 1000) - since
    if elapsed < 0 then
        return nil
    end
    local substitutions: { [string]: string | number | boolean } = {
        hours = math.floor(elapsed / 3600),
        minutes = math.floor(elapsed % 3600 / 60),
    }
    return noctalia.tr("time.duration", substitutions)
end

return { formatKyivTimestamp = formatKyivTimestamp, formatDuration = formatDuration }
