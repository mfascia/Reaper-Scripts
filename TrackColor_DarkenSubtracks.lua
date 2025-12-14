--[[
    ReaScript Name: Inherit parent track color (darker) for tracks and items + LR pair exception
    Author: ChatGPT
    Description:
        - For every non top-level track:
            * Set its track color to its parent track's color, darkened by DARKEN_AMOUNT.
            * Set all items on that track to the same color.
        - Exception:
            * If two adjacent tracks at the same depth end with "L" and "R" respectively
              (in either order), they BOTH get the exact same color as their parent
              (no darkening), and their items match.
        - Top-level tracks (depth 0) are left unchanged.
]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

-- How much darker than the parent (0.0–1.0)
-- Effective factor = (1 - DARKEN_AMOUNT)
local DARKEN_AMOUNT = 0.1

-- Also color all takes in items? (optional)
local APPLY_ITEM_TAKE_COLORS = false


------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function rgb_to_native(r, g, b)
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function darken_native_color(native_color, darken_amount)
    if native_color == 0 then
        return native_color
    end

    local r, g, b = reaper.ColorFromNative(native_color)

    local factor = 1.0 - darken_amount
    if factor < 0.0 then factor = 0.0 end

    local dr = math.floor(r * factor + 0.5)
    local dg = math.floor(g * factor + 0.5)
    local db = math.floor(b * factor + 0.5)

    return rgb_to_native(dr, dg, db)
end

local function color_items_on_track(track, native_color)
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

local function get_track_name(track)
    local _, name = reaper.GetTrackName(track, "")
    return name or ""
end

local function last_non_space_char_upper(s)
    -- Trim trailing whitespace and return last char uppercased (or nil)
    s = tostring(s or "")
    s = s:gsub("%s+$", "")
    if #s == 0 then
        return nil
    end
    return s:sub(-1):upper()
end

local function is_lr_pair_suffix(a_last, b_last)
    return (a_last == "L" and b_last == "R") or (a_last == "R" and b_last == "L")
end


------------------------------------------------------------
-- Main
------------------------------------------------------------

local function main()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then return end

    -- parent_for_depth[d] holds the most recent track encountered at depth d
    local parent_for_depth = {}

    local i = 0
    while i < track_count do
        local track = reaper.GetTrack(proj, i)
        local depth = reaper.GetTrackDepth(track)

        local parent_track = nil
        if depth > 0 then
            parent_track = parent_for_depth[depth - 1]
        end

        -- Check L/R adjacent pair at same depth (only makes sense if we have a parent)
        if parent_track and (i + 1) < track_count then
            local next_track = reaper.GetTrack(proj, i + 1)
            local next_depth = reaper.GetTrackDepth(next_track)

            if next_depth == depth then
                local a_last = last_non_space_char_upper(get_track_name(track))
                local b_last = last_non_space_char_upper(get_track_name(next_track))

                if a_last and b_last and is_lr_pair_suffix(a_last, b_last) then
                    local parent_color = reaper.GetTrackColor(parent_track)
                    if parent_color ~= 0 then
                        -- No attenuation: both get parent's exact color
                        local same_color = parent_color

                        reaper.SetTrackColor(track, same_color)
                        color_items_on_track(track, same_color)

                        reaper.SetTrackColor(next_track, same_color)
                        color_items_on_track(next_track, same_color)
                    end

                    -- Update parent tracking for this depth (the later sibling is the last seen)
                    parent_for_depth[depth] = next_track

                    -- Skip the next track since we handled the pair
                    i = i + 2
                    goto continue
                end
            end
        end

        -- Normal behavior: inherit parent's color with darkening
        if parent_track then
            local parent_color = reaper.GetTrackColor(parent_track)
            if parent_color ~= 0 then
                local child_color = darken_native_color(parent_color, DARKEN_AMOUNT)
                reaper.SetTrackColor(track, child_color)
                color_items_on_track(track, child_color)
            end
        end

        -- This track becomes the "current" parent for its depth
        parent_for_depth[depth] = track

        i = i + 1
        ::continue::
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Inherit parent track color (darker) + LR pair exception", -1)
