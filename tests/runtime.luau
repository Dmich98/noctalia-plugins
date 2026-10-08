--!nocheck

return function(sources, translations, catalog)
    local early = "2026-10-08T18:00:00Z"
    local late = "2026-10-08T19:00:00.123Z"
    local utcText = {
        [os.time({ year = 2026, month = 10, day = 8, hour = 18, min = 0, sec = 0 })] = early:sub(
            1,
            19
        ),
        [os.time({ year = 2026, month = 10, day = 8, hour = 19, min = 0, sec = 0 })] = late:sub(
            1,
            19
        ),
    }

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
                files = { ["locations/catalog.json"] = "catalog" },
                values = {},
                jsonValues = { catalog = catalog },
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
            panels = {},
            config = {},
            shared = shared,
        }, { __index = getfenv() })
        local watchers, modules = shared.watchers, {}
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
            setUpdateInterval = function() end,
            togglePanel = function(id)
                table.insert(env.panels, id)
            end,
            formatTime = function(pattern, seconds, timezone)
                env.timezone = timezone
                return timezone == "UTC" and (utcText[seconds] or "invalid") or "formatted"
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
            setWantsSecondTicks = function() end,
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
