--!strict

local levels: { [string]: { name: string, glyph: string, color: string } } = {
    red = { name = "level.red", glyph = "rocket", color = "#ef4444" },
    yellow = { name = "level.yellow", glyph = "alert-triangle", color = "#facc15" },
}

local reasons = {
    ["Ракетна загроза (червоний рівень)"] = "reason.missile",
    ["Дронова загроза (жовтий рівень)"] = "reason.drone",
}

local safe = { glyph = "brand-flightradar24", color = "#22c55e" }

local function formatAlertLevel(level: string): string
    local info = levels[level]
    return info and noctalia.tr(info.name) or level
end

local function formatAlertReason(reason: string): string
    local key = reasons[reason]
    return key and noctalia.tr(key) or reason
end

local function statusAppearance(active: boolean, level: string?): { glyph: string, color: string }
    return active and (levels[level or ""] or levels.yellow) or safe
end

return {
    formatAlertLevel = formatAlertLevel,
    formatAlertReason = formatAlertReason,
    statusAppearance = statusAppearance,
}
