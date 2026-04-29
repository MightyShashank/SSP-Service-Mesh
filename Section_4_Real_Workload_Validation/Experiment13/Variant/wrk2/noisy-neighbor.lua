-- noisy-neighbor.lua
-- wrk2 Lua script for the svc-noisy synthetic HTTP load generator.
-- Sends simple GET requests to the svc-noisy service's own backend.
-- NO application-level coupling to any DSB service.

local counter = 0

request = function()
  counter = counter + 1
  return wrk.format("GET", "/", {
    ["Connection"] = "keep-alive",
    ["X-Request-ID"] = tostring(counter),
  })
end

response = function(status, headers, body)
  -- silently discard; we only care about RPS and latency impact on DSB
end
