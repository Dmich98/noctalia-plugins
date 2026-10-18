--!strict

export type StartResult = "started" | "missing_dependency" | "launch_failed"
export type LineHandler = (string, number) -> ()

-- Noctalia owns this shell's process group, including websocat and sleep.
-- Ping timeout releases half-open connections so the supervisor can reconnect.
-- Keep messages below runStream's 64 KiB unfinished-line buffer; stderr stays separate.
local command = [[
trap 'exit 0' HUP INT TERM
while :; do
    websocat -t -u -n -S -B 65536 \
        --max-ws-frame-length 61440 --max-ws-message-length 61440 \
        --ping-interval 10 --ping-timeout 30 \
        wss://neptun.in.ua/api/v1/stream - </dev/null
    result=$?
    case "$result" in
        126|127) exit "$result" ;;
    esac
    sleep 5 || exit
done
]]
local result: StartResult? = nil

-- Only the service should require this entry-local singleton. Reload resets failures.
local function start(onLine: LineHandler): StartResult
    if result then
        return result
    end
    if not noctalia.commandExists("websocat") then
        result = "missing_dependency"
        noctalia.log("Air Alert requires websocat; reload the plugin after installing it")
        return "missing_dependency"
    end

    -- Reserve before submission so a reentrant call cannot start a second stream.
    result = "started"
    local accepted = noctalia.runStream(command, function(line: string): ()
        -- Raw activity does not prove valid JSON or synchronized official alerts.
        onLine(line, noctalia.nowMs())
    end)
    if not accepted then
        result = "launch_failed"
        noctalia.log("Could not submit the Air Alert WebSocket stream")
        return "launch_failed"
    end
    return "started"
end

return { start = start }
