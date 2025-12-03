--[[
    ReaScript Name: Rainbow colors for top-level tracks with keywords,
                   configurable hue distribution, pastel option,
                   darker subtracks, and item coloring
    Author: ChatGPT
    Description:
        - Step 1: Keyword pass (for logic): determine which tracks match COLOR_RULES.
        - Step 2: Assign rainbow hues to top-level tracks that DO NOT match a keyword.
        - Step 3: Color all tracks/items using rainbow (with depth / previous darkening).
        - Step 4: Apply keyword overrides:
              * If a track name matches a keyword, that track AND its subtracks
                get a specific RGB color from COLOR_RULES (overriding rainbow),
                plus their items/takes.
]]

------------------------------------------------------------
-- CONFIG: keyword color rules
-- Matching is case-insensitive, substring-based.
------------------------------------------------------------

local COLOR_RULES =
{
    { keyword = "NOTES", r = 255, g = 255, b = 204   },
    -- { keyword = "DRUM", r = 255, g = 180, b = 0   },
    -- { keyword = "BASS", r = 0,   g = 180, b = 255 },
    -- { keyword = "GTR",  r = 0,   g = 200, b = 80  },
    -- { keyword = "VOC",  r = 220, g = 0,   b = 120 },
}

------------------------------------------------------------
-- Other CONFIG
------------------------------------------------------------

-- Hue distribution across top-level tracks:
--   "adjacent"  -> neighbors close in hue (smooth rainbow)
--   "opposite"  -> neighbors far apart in hue (max separation)
-- local HUE_DISTRIBUTION = "opposite"
local HUE_DISTRIBUTION = "adjacent"

-- Darkening mode:
--   "by_depth"      = brightness depends on track depth
--   "from_previous" = each track is darker than the one above it
-- local DARKEN_MODE = "from_previous"
local DARKEN_MODE = "by_depth"

-- How much to darken (0.0–1.0)
-- - In "by_depth": per depth level
-- - In "from_previous": per track step down within the same top-level block
local DARKEN_PER_STEP = 0.2

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
-- Keyword matching helpers
------------------------------------------------------------
local function find_matching_rule(track_name)
    local upper = track_name:upper()

    for _, rule in ipairs(COLOR_RULES) do
        local kw = (rule.keyword or ""):upper()
        if kw ~= "" and upper:find(kw, 1, true) then
            return rule
        end
    end

    return nil
end

-- Apply a keyword rule to a track and all its subtracks
local function apply_keyword_rule_to_track_and_children(track_index, rule)
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    local parent = reaper.GetTrack(proj, track_index)
    if not parent then return end

    local parent_depth = reaper.GetTrackDepth(parent)
    local native_color = rgb_to_native(rule.r, rule.g, rule.b)

    for i = track_index, track_count - 1 do
        local tr = reaper.GetTrack(proj, i)
        local depth = reaper.GetTrackDepth(tr)

        if i > track_index and depth <= parent_depth then
            -- we've exited this folder/block
            break
        end

        color_track_and_items(tr, native_color)
    end
end

------------------------------------------------------------
-- Helper: greatest common divisor (for "opposite" step selection)
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
-- Assign hues to NON-keyword top-level tracks based on distribution
------------------------------------------------------------
local function assign_top_level_hues(rainbow_top_indices)
    local num_top = #rainbow_top_indices
    local top_level_hues = {}  -- track index -> hue [0.0–1.0]

    if num_top == 0 then
        return top_level_hues
    end

    if num_top == 1 then
        local only_index = rainbow_top_indices[1]
        top_level_hues[only_index] = 0.0
        return top_level_hues
    end

    if HUE_DISTRIBUTION == "adjacent" then
        -- Simple left-to-right rainbow over remaining tracks
        for pos, track_index in ipairs(rainbow_top_indices) do
            local h = (pos - 1) / num_top     -- 0.0 .. <1.0
            top_level_hues[track_index] = h
        end
    else
        -- "opposite" (max-separated around the wheel) over remaining tracks
        local step = math.floor(num_top / 2) + 1

        -- Ensure gcd(step, num_top) == 1 so we visit all slots
        while gcd(step, num_top) ~= 1 do
            step = step + 1
            if step >= num_top then
                step = 1
            end
        end

        for pos, track_index in ipairs(rainbow_top_indices) do
            local slot = ((pos - 1) * step) % num_top
            local h = slot / num_top         -- 0.0 .. <1.0
            top_level_hues[track_index] = h
        end
    end

    return top_level_hues
end

------------------------------------------------------------
-- Main
------------------------------------------------------------
local function main()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then return end

    --------------------------------------------------------
    -- First: collect top-level tracks and detect keyword matches
    --------------------------------------------------------
    local top_level_indices = {}
    local top_level_has_keyword = {}  -- [track_index] = true if this TL track matches a keyword

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(proj, i)
        local depth = reaper.GetTrackDepth(track)

        if depth == 0 then
            table.insert(top_level_indices, i)

            local _, name = reaper.GetTrackName(track, "")
            local rule = find_matching_rule(name or "")
            if rule then
                top_level_has_keyword[i] = true
            end
        end
    end

    if #top_level_indices == 0 then return end

    --------------------------------------------------------
    -- Build list of top-level tracks that should get rainbow
    -- (i.e. NOT matching a keyword)
    --------------------------------------------------------
    local rainbow_top_indices = {}

    for _, idx in ipairs(top_level_indices) do
        if not top_level_has_keyword[idx] then
            table.insert(rainbow_top_indices, idx)
        end
    end

    --------------------------------------------------------
    -- Assign hues only to rainbow_top_indices
    --------------------------------------------------------
    local top_level_hues = assign_top_level_hues(rainbow_top_indices)

    --------------------------------------------------------
    -- Rainbow / pastel pass: color all tracks & items
    -- Only tracks whose top-level parent has an assigned hue are colored.
    --------------------------------------------------------
    local current_top_index = nil
    local prev_brightness = nil
    local prev_top_index = nil

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(proj, i)
        local depth = reaper.GetTrackDepth(track)

        -- New top-level anchor
        if depth == 0 then
            current_top_index = i
        end

        if current_top_index ~= nil then
            local h = top_level_hues[current_top_index]

            -- If this TL track is in the rainbow set, it has a hue.
            -- Otherwise (keyword TL) h will be nil and we skip rainbow color.
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
            else
                -- For non-rainbow (keyword TL) blocks, do not color here.
                -- They will be colored in the keyword override pass.
            end
        end
    end

    --------------------------------------------------------
    -- Keyword override pass: apply keyword colors
    -- (track + its subtracks + their items/takes)
    -- This now includes:
    --   - keyword top-level tracks (which never got rainbow),
    --   - any non-top tracks that match keywords.
    --------------------------------------------------------
    if #COLOR_RULES > 0 then
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(proj, i)
            local _, name = reaper.GetTrackName(track, "")
            local rule = find_matching_rule(name or "")

            if rule then
                apply_keyword_rule_to_track_and_children(i, rule)
            end
        end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Rainbow + keyword colors, pastel, darker subtracks, item colors (keywords excluded from rainbow split)", -1)
