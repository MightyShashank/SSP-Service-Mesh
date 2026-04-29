-- wrk2 Lua script: compose-post endpoint
-- Faithful port of the official DeathStarBench compose-post.lua
-- Fixed: removed require("socket") — not available in wrk2's stripped LuaJIT
-- Fixed: added required post_type=0 field
-- User IDs: 0-based (0..961) matching init_social_graph.py

math.randomseed(os.time())
math.random(); math.random(); math.random()

local charset = {
  'q','w','e','r','t','y','u','i','o','p','a','s','d','f','g','h','j','k','l','z',
  'x','c','v','b','n','m','Q','W','E','R','T','Y','U','I','O','P','A','S','D','F',
  'G','H','J','K','L','Z','X','C','V','B','N','M','1','2','3','4','5','6','7','8',
  '9','0'
}

local decset = {'1','2','3','4','5','6','7','8','9','0'}

-- socfb-Reed98 has 962 users (indices 0..961)
local max_user_index = tonumber(os.getenv("max_user_index")) or 962

local function stringRandom(length)
  if length > 0 then
    return stringRandom(length - 1) .. charset[math.random(1, #charset)]
  else
    return ""
  end
end

local function decRandom(length)
  if length > 0 then
    return decRandom(length - 1) .. decset[math.random(1, #decset)]
  else
    return ""
  end
end

request = function()
  local user_index = math.random(0, max_user_index - 1)
  local username   = "username_" .. tostring(user_index)
  local user_id    = tostring(user_index)
  local text       = stringRandom(256)

  local num_user_mentions = math.random(0, 5)
  local num_urls          = math.random(0, 5)
  local num_media         = math.random(0, 4)

  local media_ids   = "["
  local media_types = "["

  -- User mentions
  for i = 0, num_user_mentions do
    local uid
    repeat uid = math.random(0, max_user_index - 1) until uid ~= user_index
    text = text .. " @username_" .. tostring(uid)
  end

  -- URLs
  for i = 0, num_urls do
    text = text .. " http://" .. stringRandom(64)
  end

  -- Media
  for i = 0, num_media do
    local media_id = decRandom(18)
    media_ids   = media_ids   .. '"' .. media_id .. '",'
    media_types = media_types .. '"png",'
  end

  media_ids   = media_ids:sub(1, #media_ids - 1)     .. "]"
  media_types = media_types:sub(1, #media_types - 1) .. "]"

  local headers = {}
  headers["Content-Type"] = "application/x-www-form-urlencoded"

  local body = "username=" .. username
    .. "&user_id="     .. user_id
    .. "&text="        .. text
    .. "&media_ids="   .. media_ids
    .. "&media_types=" .. media_types
    .. "&post_type=0"

  headers["Content-Length"] = tostring(#body)

  return wrk.format("POST", "/wrk2-api/post/compose", headers, body)
end
