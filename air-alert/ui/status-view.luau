--!strict

local locations = require("../locations/catalog.luau")
local alertState = require("../alerts/state.luau")
local alertTime = require("../alerts/time.luau")
local alertDisplay = require("./alert-display.luau")

local function detailRow(label: string, value: string): UiNode
    return ui.row({ justify = "space_between", gap = 12 }, {
        ui.label({ text = label, color = "on_surface_variant" }),
        ui.label({ text = value, textAlign = "end" }),
    })
end

local function locationSubtitle(location: locations.Location, state: alertState.AlertState?): string
    if location.locationType == "raion" then
        local oblast = location.oblast or (state and state.oblast)
        return oblast and (noctalia.tr("location.raion") .. " · " .. oblast)
            or noctalia.tr("location.raion")
    end
    if
        location.locationKey == "м. київ"
        or location.locationKey == "севастополь"
        or location.locationName:find("область")
    then
        return ""
    end
    return noctalia.tr("location.region")
end

local function renderStatusView(location: locations.Location, state: alertState.AlertState?): UiNode
    local now = os.time()
    local status = noctalia.tr("status.unavailable")
    local glyph = "wifi-off"
    local color = "error"
    if state and state.loading then
        status = noctalia.tr("status.loading")
        glyph, color = "loader", "on_surface_variant"
    elseif state and not state.error and state.active ~= nil then
        status = state.active and noctalia.tr("status.alert") or noctalia.tr("status.safe")
        local appearance = alertDisplay.statusAppearance(state.active, state.level)
        glyph, color = appearance.glyph, appearance.color
    end

    local subtitle = locationSubtitle(location, state)
    local children: { UiNode } = {
        ui.label({
            text = locations.displayName(location),
            fontSize = 20,
            fontWeight = "bold",
            maxLines = 2,
        }),
        ui.label({ text = subtitle, color = "on_surface_variant", visible = subtitle ~= "" }),
        ui.separator({}),
        ui.row({ gap = 10, align = "center", paddingV = 12 }, {
            ui.glyph({ name = glyph, size = 28, color = color }),
            ui.label({ text = status, fontSize = 20, fontWeight = "bold", color = color }),
        }),
    }
    if state and state.loading then
        table.insert(
            children,
            ui.label({
                text = noctalia.tr("status.loading_details"),
                color = "on_surface_variant",
            })
        )
    elseif state and state.error then
        table.insert(
            children,
            ui.label({ text = state.error, color = "on_surface_variant", maxLines = 2 })
        )
    elseif state and state.active then
        local since = alertTime.parseSince(state.since)
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.level"),
                alertDisplay.formatAlertLevel(state.level or noctalia.tr("level.unknown"))
            )
        )
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.since"),
                since and alertTime.formatTime(since) or noctalia.tr("time.unavailable")
            )
        )
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.duration"),
                since and alertTime.formatDuration(since, now) or noctalia.tr("time.unavailable")
            )
        )
        if state.reasons then
            for _, reason in ipairs(state.reasons) do
                table.insert(
                    children,
                    ui.label({
                        text = alertDisplay.formatAlertReason(reason),
                        maxLines = 3,
                        color = "on_surface_variant",
                    })
                )
            end
        end
    end

    table.insert(children, ui.separator({}))
    local lastSuccess = state and state.lastSuccessAt
    table.insert(
        children,
        detailRow(
            state and state.error and noctalia.tr("label.last_success")
                or noctalia.tr("label.updated"),
            lastSuccess and alertTime.formatTime(lastSuccess, "%d.%m.%Y %H:%M:%S")
                or noctalia.tr("time.not_updated")
        )
    )
    local sourceStatus = noctalia.tr("source.waiting")
    if state and state.error then
        sourceStatus = noctalia.tr("source.unavailable")
    elseif lastSuccess then
        local age = now - lastSuccess
        sourceStatus = age < 60 and ""
            or noctalia.tr(
                "time.updated_ago",
                { minutes = math.floor(age / 60) } :: { [string]: string | number | boolean }
            )
    end
    table.insert(
        children,
        ui.label({
            text = sourceStatus,
            color = "on_surface_variant",
            maxLines = 2,
            visible = sourceStatus ~= "",
        })
    )
    return ui.column({ gap = 8 }, children)
end

return { renderStatusView = renderStatusView }
