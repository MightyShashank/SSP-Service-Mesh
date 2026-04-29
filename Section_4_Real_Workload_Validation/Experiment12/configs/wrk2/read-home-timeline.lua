-- wrk2 Lua script: read-home-timeline endpoint
-- Generates GET /wrk2-api/home-timeline/read requests
-- Exercises fan-out read through social-graph → post-storage → home-timeline

math.randomseed(os.time())

-- User pool from socfb-Reed98 (963 users, IDs 1–963)
local function random_user_id()
  return math.random(1, 963)
end

request = function()
  local user_id = random_user_id()
  -- start=0, stop=10: fetch 10 timeline entries (standard DSB benchmark pattern)
  local path = string.format(
    "/wrk2-api/home-timeline/read?user_id=%d&start=0&stop=10",
    user_id
  )
  return wrk.format("GET", path)
end
