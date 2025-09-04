--[[
ReaScript Name: Show Current Recording Take Number + Armed Track Names (Recording Only)
Author: ChatGPT
Description:
  Displays a window showing:
    • While RECORDING: the in-progress take number for the active track (robust first-take fix)
      and the names of all ARMED tracks.
    • While PLAYBACK: the active take number of the item under the play cursor.
  Colors, fonts, and window size are exposed as variables.
]]

local WINDOW_TITLE = "Current Take #"
local FONT_NAME_MAIN = "Arial"
local FONT_NAME_LIST = "Arial"

-- 🔠 FONT SIZES
local FONT_SIZE_MAIN = 60   -- "Take: N"
local FONT_SIZE_LIST = 24   -- track names list

-- 🪟 WINDOW SIZE
local WINDOW_W, WINDOW_H = 160, 200

-- 🎨 COLOR SETTINGS -----------------------
-- {r, g, b} with values 0.0 – 1.0
local REC_FG  = {1.0, 0.7, 0.7}  -- red text while recording
local REC_BG  = {0.2, 0.0, 0.0}  -- background while recording
local PLAY_FG = {0.7,   1, 0.7}  -- white text while playing
local PLAY_BG = {0.0, 0.2, 0.0}
local IDLE_FG = {0.5, 0.5, 0.5}  -- gray text while stopped
local IDLE_BG = {0.1, 0.1, 0.12}
-------------------------------------------

-- ===== Helpers =====
local function get_active_track()
  local tr = reaper.GetSelectedTrack(0, 0)
  if tr then return tr end
  return reaper.GetLastTouchedTrack()
end

local function get_play_state() return reaper.GetPlayState() end
local function get_play_pos() return reaper.GetPlayPosition() end

local function item_spanning_pos_on_track(track, pos)
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e  = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") + 1e-7
    if pos >= s and pos <= e then return it end
  end
  return nil
end

local function rightmost_item_on_track(track)
  local n = reaper.CountTrackMediaItems(track)
  local best, max_start = nil, -math.huge
  for i = 0, n - 1 do
    local cand = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(cand, "D_POSITION")
    if s > max_start then max_start, best = s, cand end
  end
  return best
end

local function find_recording_item_on_track(track)
  -- Prefer item spanning the play position; else rightmost item
  local pos = get_play_pos()
  local it = item_spanning_pos_on_track(track, pos)
  if it then return it end
  return rightmost_item_on_track(track)
end

local function get_active_take_number(item)
  if not item then return nil end
  local idx = reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")
  if idx < 0 then return nil end
  return math.floor(idx + 1)
end

-- FIXED: robust in-progress take number
-- If item is nil at record start, assume first pass = 1.
-- If there are previous items, use rightmost item's CountTakes+1.
local function get_in_progress_take_number(item, track)
  if item then
    local count = reaper.CountTakes(item) or 0
    return math.max(1, count + 1)
  end
  if track then
    local last_item = rightmost_item_on_track(track)
    if last_item then
      local count = reaper.CountTakes(last_item) or 0
      return math.max(1, count + 1)
    end
  end
  return 1 -- no items yet on the track: first take
end

local function get_track_name(track)
  local _, name = reaper.GetTrackName(track, "")
  return name or "Track"
end

-- Names of all ARMED tracks (for recording display)
local function get_all_armed_track_names()
  local names = {}
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr and reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
      names[#names+1] = get_track_name(tr)
    end
  end
  return names
end

-- Drawing helpers
local function draw_centered_text(font_name, font_size, text, y)
  gfx.setfont(1, font_name, font_size)
  local tw, th = gfx.measurestr(text)
  gfx.x = (gfx.w - tw) / 2
  gfx.y = y
  gfx.drawstr(text)
  return th
end

local function draw_list_centered(font_name, font_size, lines, start_y, line_spacing)
  gfx.setfont(1, font_name, font_size)
  local y = start_y
  for _, line in ipairs(lines) do
    local tw, th = gfx.measurestr(line)
    gfx.x = (gfx.w - tw) / 2
    gfx.y = y
    gfx.drawstr(line)
    y = y + th + (line_spacing or 2)
  end
end

-- ===== Main loop =====
local function loop()
  local ch = gfx.getchar()
  if ch < 0 then return end -- window closed

  local state = get_play_state()
  local is_rec  = (state & 4) ~= 0
  local is_play = (state & 1) ~= 0

  -- pick colors
  local fg, bg
  if is_rec then      fg, bg = REC_FG,  REC_BG
  elseif is_play then fg, bg = PLAY_FG, PLAY_BG
  else                fg, bg = IDLE_FG, IDLE_BG
  end

  -- background
  gfx.set(bg[1], bg[2], bg[3], 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local track = get_active_track()
  local text = "–"

  if track then
    if is_rec then
      local item = find_recording_item_on_track(track)
      local n = get_in_progress_take_number(item, track)   -- << fixed logic
      text = tostring(n)
    else
      local item = item_spanning_pos_on_track(track, get_play_pos())
      local n = get_active_take_number(item)
      if n then text = tostring(n) end
    end
  else
    text = "--"
  end

  -- main "Take: N"
  gfx.set(fg[1], fg[2], fg[3], 1) 
  local top_margin = 20
  local th = draw_centered_text(FONT_NAME_MAIN, FONT_SIZE_MAIN, text, top_margin)

  -- In recording mode: list ONLY ARMED tracks
  if is_rec then
    local names = get_all_armed_track_names()
    if #names > 0 then
      local gap = 20
      local header_y = top_margin + th + gap
      local hh = draw_centered_text(FONT_NAME_LIST, FONT_SIZE_LIST, "Armed Tracks:", header_y)
      local list_y = header_y + hh + 4
      draw_list_centered(FONT_NAME_LIST, FONT_SIZE_LIST, names, list_y, 2)
    end
  end

  reaper.defer(loop)
end

-- init
gfx.init(WINDOW_TITLE, WINDOW_W, WINDOW_H, 0, 200, 200)
loop()
