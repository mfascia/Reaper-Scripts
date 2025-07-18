-- @description Track prefix utility
-- @version 1.4
-- @author Marc Fascia / ChatGPT
-- @noindex

local info = debug.getinfo(1, 'S')
local script_path = info.source:match("@(.*[\\/])")  -- path with trailing slash
dofile(script_path .. "Globals.lua")


function prefix_select_all_tracks()
  reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name:sub(1, #PREFIX) == PREFIX then
      reaper.SetTrackSelected(track, true)
    end
  end
end

prefix_select_all_tracks()