--[[
    ReaScript Name: Rainbow colors (max-separated) for top-level tracks
                   with pastel option, darker subtracks, item coloring,
                   and optional "from previous" darkening
    Author: ChatGPT
    Description:
        - Assigns each top-level track (depth 0) a rainbow hue.
        - Hues are distributed so adjacent top-level tracks are as far apart
          on the color wheel as possible.
        - Subtracks can be darkened either:
              * by depth level, or
              * progressively from the previous track.
        - Global saturation control allows pastel colors.
        - Applies the track color to all items on the track (and optionally their takes).
]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

-- Darkening mode:
--   "by_depth"     = brightness depends on track depth (old behavior)
--   "from_previous"= each track is darker than the one above it
local DARKEN_MODE = "by_depth"   -- "by_depth" or "from_previous"

-- How much to darken (0.0–1.0)
-- - In "by_depth": per depth level (depth 1, 2, 3...)
-- - In "from_previous": per track step down within the same top-level block
local DARKEN_PER_STEP = 0.15

-- Minimum brightness so things don't go fully black (0.0–1.0)
local MIN_VALUE = 0.2

-- Saturation (0 = gray, 1 = vivid rainbow). 0.4–0.7 = pastel-ish.
local PASTEL_SATURATION = 0.6

-- Also apply color to all takes inside items?
local APPLY_ITEM_TAKE_COLORS = true


------------------------------------------------------------
-- Helper: HSV → RGB
------------------------------------------------------------
local function hsv_to_rgb(h, s, v)
    -- h, s, v: 0.0–1.0
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6

    local r, g, b

    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    return math.floor(r * 255 + 0.5),
           math.floor(g * 255 + 0.5),
           math.floor(b * 255 + 0.5)
end

------------------------------------------------------------
-- Helper: RGB → REAPER native color
------------------------------------------------------------
local function rgb_to_native(r, g, b)
    -- Add 0x1000000 so REAPER uses the custom color
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

------------------------------------------------------------
-- Helper: color a track AND all items (and optionally takes) on it
------------------------------------------------------------
local function color_track_and_items(track, native_color)
    -- Track
    reaper.SetTrackColor(track, native_color)

    -- Items
    local item_count = reaper.CountTrackMediaItems(track)

    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)

        if item then
            reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color)

            if APPLY_ITEM_TAKE_COLORS then
                local take_count = reaper.CountTakes(item)

                for t = 0, take_count - 1 do
                    local take = reaper.GetTake(item, t)

                    if take then
                        reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", native_color)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Helper: greatest common divisor (for step selection)
------------------------------------------------------------
local function gcd(a, b)
    a = math.abs(a)
    b = math.abs(b)

    while b ~= 0 do
        a, b = b, a % b
    end

    return a
end

------------------------------------------------------------
-- Main
------------------------------------------------------------
local function main()
    local track_count = reaper.CountTracks(0)

    if track_count == 0 then
        return
    end

    --------------------------------------------------------
    -- Collect indices of all top-level tracks (depth == 0)
    --------------------------------------------------------
    local top_level_indices = {}

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)

        if depth == 0 then
            table.insert(top_level_indices, i)
        end
    end

    local num_top = #top_level_indices

    if num_top == 0 then
        return
    end

    --------------------------------------------------------
    -- Assign each top-level track a hue in a permuted order
    -- so adjacent tracks are far apart on the color wheel.
    --------------------------------------------------------
    local top_level_hues = {}  -- track index -> hue [0.0–1.0]

    if num_top == 1 then
        local only_index = top_level_indices[1]
        top_level_hues[only_index] = 0.0
    else
        -- Choose a step ~ N/2 that is coprime with N
        local step = math.floor(num_top / 2) + 1

        while gcd(step, num_top) ~= 1 do
            step = step + 1

            if step >= num_top then
                step = 1
            end
        end

        for pos, track_index in ipairs(top_level_indices) do
            local slot = ((pos - 1) * step) % num_top
            local h = slot / num_top      -- 0.0 .. <1.0
            top_level_hues[track_index] = h
        end
    end

    --------------------------------------------------------
    -- Walk all tracks and color based on:
    --   - hue from their top-level ancestor
    --   - brightness determined by DARKEN_MODE
    --------------------------------------------------------
    local current_top_index = nil
    local prev_brightness = nil
    local prev_top_index = nil

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)

        -- New top-level anchor
        if depth == 0 then
            current_top_index = i
        end

        if current_top_index ~= nil then
            local h = top_level_hues[current_top_index]

            if h ~= nil then
                local s = PASTEL_SATURATION
                local v

                if depth == 0 then
                    -- Top-level tracks always start at full brightness
                    v = 1.0
                else
                    if DARKEN_MODE == "from_previous" then
                        -- Darken progressively from the track above (within the same top-level block)
                        if prev_top_index ~= current_top_index or prev_brightness == nil then
                            -- First non-top track under this top-level
                            v = 1.0 - DARKEN_PER_STEP
                        else
                            v = prev_brightness * (1.0 - DARKEN_PER_STEP)
                        end
                    else
                        -- "by_depth": brightness is a function of depth only
                        v = 1.0 * (1.0 - DARKEN_PER_STEP * depth)
                    end
                end

                if v < MIN_VALUE then
                    v = MIN_VALUE
                end

                local r, g, b = hsv_to_rgb(h, s, v)
                local native_color = rgb_to_native(r, g, b)

                color_track_and_items(track, native_color)

                -- Remember for next iteration
                prev_brightness = v
                prev_top_index = current_top_index
            end
        end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Rainbow (max-separated) with pastel, darker subtracks, item colors, and darkening mode", -1)

