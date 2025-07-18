-- @description Track prefix utility
-- @version 1.4
-- @author Marc Fascia / ChatGPT
-- @noindex

local info = debug.getinfo(1, 'S')
local script_path = info.source:match("@(.*[\\/])")  -- path with trailing slash
dofile(script_path .. "Globals.lua")
dofile("Prefix_AddToSelectredTracks.lua")
dofile("Prefix_RemoveFromAllTracks.lua")
dofile("Prefix_RemoveFromSelectedTracks.lua")
dofile("Prefix_SelectAllTracks.lua")
dofile("Prefix_ToggleOnSelectedTracks.lua")

function show_menu_and_run()
  local menu = "#Choose an action for prefix '" .. PREFIX .. "'|" ..
               "Add prefix to selected tracks|" ..
               "Remove prefix from selected tracks|" ..
               "Toggle prefix on selected tracks|" ..
               "Remove prefix from ALL tracks|" ..
               "Select tracks with prefix"

  local choice = gfx.showmenu(menu)

  if choice == 2 then prefix_add_to_selected_tracks()
  elseif choice == 3 then prefix_remove_from_selected_tracks()
  elseif choice == 4 then prefix_toggle_on_selected_tracks()
  elseif choice == 5 then prefix_removefrom_all_tracks()
  elseif choice == 6 then sprefix_select_all_tracks()
  end
end

-- === MAIN ===
function main()
  reaper.Undo_BeginBlock()
  gfx.init("Track Prefix Menu", 300, 100, 0, 200, 200)
  show_menu_and_run()
  gfx.quit()
  reaper.Undo_EndBlock("Track Prefix Utility Action", -1)
end

main()
