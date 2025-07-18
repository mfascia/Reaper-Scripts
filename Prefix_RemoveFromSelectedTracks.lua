-- @description Track prefix utility
-- @version 1.4
-- @author Marc Fascia / ChatGPT
-- @noindex

local info = debug.getinfo(1, 'S')
local script_path = info.source:match("@(.*[\\/])")  -- path with trailing slash
dofile(script_path .. "Globals.lua")


function prefix_remove_from_selected_tracks()
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name:sub(1, #PREFIX) == PREFIX then
      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name:sub(#PREFIX + 1), true)
    end
  end
end

prefix_remove_from_selected_tracks()