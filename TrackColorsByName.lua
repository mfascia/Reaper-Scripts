--[[
    ReaScript Name: Color tracks by name keywords (including subtracks)
    Author: ChatGPT
    Description:
        Scans all tracks, and if a track name contains a given keyword,
        assigns a defined color to that track and all of its child tracks
        (if it’s a folder).

    HOW TO USE:
        1. Edit the COLOR_RULES table below.
        2. Put your desired keywords and RGB values.
        3. Save this as a .lua script in REAPER and run it.
]]

------------------------------------------------------------
-- CONFIG: keyword → RGB color table
-- Add / remove entries as needed.
-- Matching is case-insensitive and uses "contains" (substring) logic.
------------------------------------------------------------

local COLOR_RULES =
{
    -- Example rules:
    { keyword = "DRUM",   r = 255, g = 180, b = 0   },
    { keyword = "BASS",   r = 0,   g = 180, b = 255 },
    { keyword = "KEYS",   r = 220, g = 0,   b = 120 },
    { keyword = "GTR",    r = 0,   g = 200, b = 80  },
    { keyword = "VOX",    r = 220, g = 0,   b = 120 },
    -- Add your own:
    -- { keyword = "KEYS",  r = 160, g = 100, b = 255 },
}

------------------------------------------------------------
-- Helper functions
------------------------------------------------------------

local function rgb_to_native(r, g, b)
    -- REAPER expects a packed integer color.
    -- The 0x1000000 flag is needed so REAPER uses the custom color.
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function find_matching_rule(track_name)
    local upper_name = track_name:upper()

    for _, rule in ipairs(COLOR_RULES) do
        local upper_keyword = rule.keyword:upper()
        -- plain = true for literal substring match (no patterns)
        if upper_name:find(upper_keyword, 1, true) then
            return rule
        end
    end

    return nil
end

local function color_track(track, rule)
    local color = rgb_to_native(rule.r, rule.g, rule.b)
    reaper.SetTrackColor(track, color)
end

-- Color all children of a folder track with the same color.
-- This uses track depth to determine where the folder ends.
local function color_folder_children(parent_track_index, rule)
    local track_count = reaper.CountTracks(0)
    local parent_track = reaper.GetTrack(0, parent_track_index)
    if not parent_track then
        return
    end

    local parent_depth = reaper.GetTrackDepth(parent_track)
    local color = rgb_to_native(rule.r, rule.g, rule.b)

    for i = parent_track_index + 1, track_count - 1 do
        local child_track = reaper.GetTrack(0, i)
        local child_depth = reaper.GetTrackDepth(child_track)

        -- When depth <= parent_depth, we've exited the folder
        if child_depth <= parent_depth then
            break
        end

        reaper.SetTrackColor(child_track, color)
    end
end

------------------------------------------------------------
-- Main
------------------------------------------------------------

local function main()
    local track_count = reaper.CountTracks(0)

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track, "")

        local rule = find_matching_rule(name)
        if rule then
            -- Color the track itself
            color_track(track, rule)

            -- If this track is a folder, also color its children
            local folder_depth_flag = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if folder_depth_flag == 1 then
                color_folder_children(i, rule)
            end
        end
    end

    -- Refresh track panel
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Color tracks by name keywords (including subtracks)", -1)

