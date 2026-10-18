--!nocheck

local env = runtime()
local transport = env.require("./alerts/transport.luau")
assert(env.streamAttempts == 0, "require must not launch the stream")
local received = {}
local function onLine(line, receivedAtMs)
    table.insert(received, { line = line, receivedAtMs = receivedAtMs })
end
assert(transport.start(onLine) == "started")
assert(env.commandChecks[1] == "websocat")
for _ = 1, 10 do
    assert(env.require("./alerts/transport.luau").start(function()
        error("repeated start must retain the original callback")
    end) == "started")
end
assert(env.streamAttempts == 1 and #env.streams == 1 and #env.commandChecks == 1)
local stream = env.streams[1]
local heartbeat = '{"type":"heartbeat","ts":"2026-10-17T19:50:57.786Z"}'
env.now = 12
stream.onLine(heartbeat)
env.now = 15
stream.onLine("malformed JSON")
assert(received[1].line == heartbeat and received[1].receivedAtMs == 12000)
assert(received[2].line == "malformed JSON" and received[2].receivedAtMs == 15000)
assert(#env.requests == 0 and #env.commands == 0)
assert(next(env.values) == nil, "transport must not publish official-alert state")
print("PASS single stream, callback ownership and raw activity")

local missing = runtime()
missing.executables.websocat = false
local missingTransport = missing.require("./alerts/transport.luau")
assert(missingTransport.start(onLine) == "missing_dependency")
missing.executables.websocat = true
assert(missingTransport.start(onLine) == "missing_dependency")
assert(missing.streamAttempts == 0 and #missing.commandChecks == 1)

local rejected = runtime()
rejected.rejectStream = true
local rejectedTransport = rejected.require("./alerts/transport.luau")
assert(rejectedTransport.start(onLine) == "launch_failed")
rejected.rejectStream = false
assert(rejectedTransport.start(onLine) == "launch_failed")
assert(rejected.streamAttempts == 1 and #rejected.streams == 0)
print("PASS missing dependency and rejected stream submission without retries")

local reentrant = runtime()
local reentrantTransport = reentrant.require("./alerts/transport.luau")
reentrant.noctalia.runStream = function(_, callback)
    reentrant.streamAttempts += 1
    callback(heartbeat)
    return true
end
assert(reentrantTransport.start(function()
    assert(reentrantTransport.start(onLine) == "started")
end) == "started")
assert(reentrant.streamAttempts == 1)
print("PASS reentrant start cannot duplicate the stream")
