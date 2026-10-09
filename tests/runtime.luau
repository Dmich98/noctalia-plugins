--!nocheck

return function(sources, translations)
    local function copy(value)
        if type(value) ~= "table" then
            return value
        end
        local result = {}
        for key, item in value do
            result[key] = copy(item)
        end
        return result
    end

    local function runtime(shared)
        shared = shared
            or {
                files = {},
                values = {},
                jsonValues = {},
                watchers = {},
                queue = {},
            }
        if not shared.flush then
            shared.flush = function()
                while #shared.queue > 0 do
                    local event = table.remove(shared.queue, 1)
                    event.callback(event.value)
                end
            end
        end
        local env = setmetatable({
            files = shared.files,
            values = shared.values,
            jsonValues = shared.jsonValues,
            requests = {},
            notifications = {},
            commands = {},
            panels = {},
            config = {},
            shared = shared,
            now = 0,
        }, { __index = getfenv() })
        local watchers, modules = shared.watchers, {}
        env.os = {
            time = function()
                return env.now
            end,
        }
        env.noctalia = {
            getConfig = function(key)
                return env.config[key]
            end,
            tr = function(key, substitutions)
                local text = translations[key] or key
                return (
                    text:gsub("{([^}]+)}", function(name)
                        local value = substitutions and substitutions[name]
                        return value ~= nil and tostring(value) or ("{" .. name .. "}")
                    end)
                )
            end,
            pluginDataDir = function()
                return "/data"
            end,
            fileExists = function(path)
                return env.files[path] ~= nil
            end,
            readFile = function(path)
                return env.files[path], "missing file"
            end,
            writeFile = function(path, raw)
                env.files[path] = raw
                return not env.failWrite, env.failWrite and "write failed" or nil
            end,
            renameFile = function(from, to)
                if env.failRename then
                    return false, "rename failed"
                end
                env.files[to], env.files[from] = env.files[from], nil
                return true
            end,
            removeFile = function(path)
                env.files[path] = nil
                return true
            end,
            log = function() end,
            runAsync = function(command)
                table.insert(env.commands, command)
                if type(command) == "table" and command[3] == "notification-show" then
                    table.insert(env.notifications, copy(env.jsonValues[command[4]]))
                end
                return true
            end,
            nowMs = function()
                return env.now * 1000
            end,
            isValidTimezone = function(zone)
                return zone == "Europe/Kyiv"
            end,
            formatTime = function(pattern, seconds, zone)
                assert(pattern == "%d.%m.%Y %H:%M" and zone == "Europe/Kyiv")
                -- The integration fixtures are in October before Kyiv's DST change.
                return os.date("!" .. pattern, seconds + 3 * 3600)
            end,
            notify = function(title, body)
                table.insert(env.notifications, { title = title, body = body })
            end,
            setUpdateInterval = function(milliseconds)
                env.updateInterval = milliseconds
            end,
            togglePanel = function(id)
                table.insert(env.panels, id)
            end,
            http = function(_, callback)
                if env.rejectRequest then
                    return false
                end
                table.insert(env.requests, callback)
                return true
            end,
            json = {
                decode = function(raw)
                    local value = env.jsonValues[raw]
                    if value == nil then
                        return nil, "invalid JSON"
                    end
                    return copy(value)
                end,
                encode = function(value)
                    if value.summary then
                        local key = "notification-" .. tostring(#env.commands + 1)
                        env.jsonValues[key] = copy(value)
                        return key
                    end
                    env.jsonValues[value.locationKey] = copy(value)
                    return value.locationKey
                end,
            },
            state = {
                get = function(key)
                    return copy(env.values[key])
                end,
                set = function(key, value)
                    env.values[key] = copy(value)
                    for _, listener in watchers[key] or {} do
                        table.insert(
                            shared.queue,
                            { callback = listener.callback, value = copy(value) }
                        )
                    end
                end,
                watch = function(key, callback)
                    watchers[key] = watchers[key] or {}
                    table.insert(watchers[key], { owner = env, callback = callback })
                end,
            },
        }
        env.barWidget = {
            setText = function(text)
                env.text = text
            end,
            setColor = function(color)
                env.color = color
            end,
            setGlyphColor = function(color)
                env.glyphColor = color
            end,
            setGlyph = function(glyph)
                env.glyph = glyph
            end,
            setTooltip = function(tooltip)
                env.tooltip = tooltip
            end,
        }
        env.ui = setmetatable({}, {
            __index = function(_, kind)
                return function(props, children)
                    return { kind = kind, props = props, children = children }
                end
            end,
        })
        env.emit = function(key, value)
            env.noctalia.state.set(key, value)
            shared.flush()
        end
        env.flush = shared.flush
        env.panel = {
            render = function(tree)
                env.tree = tree
            end,
            setWantsSecondTicks = function(wants)
                env.secondTicks = wants
            end,
        }
        env.close = function()
            if env.onExit then
                env.onExit()
            end
            for _, listeners in watchers do
                for index = #listeners, 1, -1 do
                    if listeners[index].owner == env then
                        table.remove(listeners, index)
                    end
                end
            end
            shared.flush()
        end
        env.require = function(path)
            if not modules[path] then
                local chunk = assert(loadstring(assert(sources[path]), path))
                setfenv(chunk, env)
                modules[path] = chunk()
            end
            return modules[path]
        end
        return env
    end

    return runtime
end
