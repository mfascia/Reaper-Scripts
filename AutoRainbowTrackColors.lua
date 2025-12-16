--[[
    ReaScript Name: Top-level colors from gradient (optional, silent fallback to rainbow) + keywords + darker subtracks + item coloring
    Author: ChatGPT

    Notes:
        - Uses gfx.loadimg + gfx.blit + gfx.getpixel (no gfx.getimgpixel dependency).
        - Avoids gfx.freeimg entirely (some builds don't expose it).
        - Stereo pair detection: matches the previous track at the SAME DEPTH (ignoring children).
]]

------------------------------------------------------------
-- CONFIG: gradient image
------------------------------------------------------------

-- Path to gradient image (thin horizontal strip).
-- Can be:
--   ""                  -> uses "gradient.png" next to script
--   "gradients/foo.png" -> relative to script folder
--   absolute path       -> used as-is
-- If loading fails, script silently falls back to rainbow.
local GRADIENT_IMAGE_PATH = "Gradient Rainbow 2.png"

-- Sample row (0 = first row)
local GRADIENT_SAMPLE_ROW = 0

-- Optional "pastel blend": 0.0 = none, 1.0 = fully white
local PASTEL_BLEND_TO_WHITE = 0.0


------------------------------------------------------------
-- CONFIG: keyword color rules (case-insensitive substring)
------------------------------------------------------------

local COLOR_RULES =
{
    { keyword = "NOTES", r = 255, g = 255, b = 204   },
    -- { keyword = "DRUM", r = 255, g = 180, b = 0   },
    -- { keyword = "BASS", r = 0,   g = 180, b = 255 },
    -- { keyword = "VOC",  r = 220, g = 0,   b = 120 },
}


------------------------------------------------------------
-- CONFIG: distribution + darkening + item/take coloring
------------------------------------------------------------

-- Distribution across top-level tracks that do NOT match a keyword:
--   "adjacent"  -> sequential
--   "opposite"  -> maximally separated order
local DISTRIBUTION = "adjacent"  -- "adjacent" or "opposite"

-- Darkening mode:
--   "by_depth"      = brightness depends on track depth
--   "from_previous" = each track is darker than the one above it
local DARKEN_MODE = "from_previous"   -- "by_depth" or "from_previous"

-- How much to darken (0.0–1.0)
local DARKEN_PER_STEP = 0.15

-- Minimum brightness factor (0.0–1.0)
local MIN_VALUE = 0.2

-- Also apply color to all takes inside items?
local APPLY_ITEM_TAKE_COLORS = true


------------------------------------------------------------
-- CONFIG: stereo L/R pairing (no attenuation between a detected pair)
------------------------------------------------------------

local ENABLE_STEREO_PAIR_NO_ATTENUATION = true

-- Array of suffix pairs. Matching is case-insensitive.
-- Checked against track names AFTER trimming trailing spaces.
-- Order can be L-R or R-L.
local STEREO_SUFFIX_PAIRS =
{
    { " L", " R" },
    { "L",  "R"  },  -- handy for names like "GtrL"/"GtrR"
    { "_L", "_R" },
    { "-L", "-R" },
    { ".L", ".R" },
    -- { " (L)", " (R)" },
}


------------------------------------------------------------
-- Helpers: paths
------------------------------------------------------------

local function get_script_dir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return src:match("^(.*[\\/])") or ""
end

local function is_absolute_path(p)
    if not p or p == "" then return false end
    if p:match("^%a:[\\/]") then return true end -- Windows drive
    if p:sub(1, 1) == "/" then return true end     -- Unix/macOS
    return false
end

local function resolve_gradient_path()
    local base = get_script_dir()

    if not GRADIENT_IMAGE_PATH or GRADIENT_IMAGE_PATH == "" then
        return base .. "gradient.png"
    end

    if is_absolute_path(GRADIENT_IMAGE_PATH) then
        return GRADIENT_IMAGE_PATH
    end

    return base .. GRADIENT_IMAGE_PATH
end


------------------------------------------------------------
-- Helper: clamp / blend / string helpers
------------------------------------------------------------

local function clamp01(x)
    if x < 0.0 then return 0.0 end
    if x > 1.0 then return 1.0 end
    return x
end

local function blend_to_white(r, g, b, amount)
    amount = clamp01(amount)
    r = r + (255 - r) * amount
    g = g + (255 - g) * amount
    b = b + (255 - b) * amount
    return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

local function rstrip_spaces(s)
    return (s or ""):gsub("%s+$", "")
end

local function ends_with(s, suffix)
    if suffix == nil or suffix == "" then return false end
    if s == nil then return false end
    if #suffix > #s then return false end
    return s:sub(-#suffix) == suffix
end

local function is_stereo_pair(prev_name, curr_name)
    if not ENABLE_STEREO_PAIR_NO_ATTENUATION then
        return false
    end

    local a = rstrip_spaces(prev_name):upper()
    local b = rstrip_spaces(curr_name):upper()

    for _, pair in ipairs(STEREO_SUFFIX_PAIRS) do
        local s1 = (pair[1] or ""):upper()
        local s2 = (pair[2] or ""):upper()

        if s1 ~= "" and s2 ~= "" then
            local a1 = ends_with(a, s1)
            local a2 = ends_with(a, s2)
            local b1 = ends_with(b, s1)
            local b2 = ends_with(b, s2)

            if (a1 and b2) or (a2 and b1) then
                return true
            end
        end
    end

    return false
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
    reaper.SetTrackColor(track, native_color)

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
-- Keyword helpers
------------------------------------------------------------

local function find_matching_rule(track_name)
    local upper = (track_name or ""):upper()

    for _, rule in ipairs(COLOR_RULES) do
        local kw = (rule.keyword or ""):upper()
        if kw ~= "" and upper:find(kw, 1, true) then
            return rule
        end
    end

    return nil
end

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
            break
        end

        color_track_and_items(tr, native_color)
    end
end


------------------------------------------------------------
-- Distribution helpers
------------------------------------------------------------

local function gcd(a, b)
    a = math.abs(a)
    b = math.abs(b)

    while b ~= 0 do
        a, b = b, a % b
    end

    return a
end

-- Returns an integer slot in [0, n-1] for the given position (1..n)
local function distribution_slot(pos, n)
    if n <= 1 then
        return 0
    end

    if DISTRIBUTION == "adjacent" then
        return pos - 1
    end

    -- "opposite": max separation order using a step ~ n/2 that is coprime with n
    local step = math.floor(n / 2) + 1

    while gcd(step, n) ~= 1 do
        step = step + 1
        if step >= n then
            step = 1
        end
    end

    return ((pos - 1) * step) % n
end


------------------------------------------------------------
-- Gradient sampling via gfx (no gfx.getimgpixel, no gfx.freeimg)
------------------------------------------------------------

local g_use_gradient = false
local g_img_w = nil
local g_img_h = nil
local g_row_ready = false

local function safe_gfx_quit()
    if gfx and gfx.quit then
        gfx.quit()
    end
end

local function unload_gradient_image()
    safe_gfx_quit()
    g_row_ready = false
    g_use_gradient = false
    g_img_w = nil
    g_img_h = nil
end

local function try_load_gradient_image(path)
    if not gfx or not gfx.init or not gfx.loadimg or not gfx.getimgdim or not gfx.blit or not gfx.getpixel then
        return false
    end

    -- First attempt: read dimensions
    gfx.init("GradientSampler", 1, 1, 0, -10000, -10000)
    if gfx.loadimg(0, path) == -1 then
        safe_gfx_quit()
        return false
    end

    local w, h = gfx.getimgdim(0)
    safe_gfx_quit()

    if not w or not h or w <= 0 or h <= 0 then
        return false
    end

    -- Second attempt: create buffer of exact width so x maps 1:1 to pixels
    gfx.init("GradientSampler", w, 1, 0, -10000, -10000)
    if gfx.loadimg(0, path) == -1 then
        safe_gfx_quit()
        return false
    end

    g_use_gradient = true
    g_img_w = w
    g_img_h = h
    g_row_ready = false
    return true
end

local function ensure_gradient_row_blitted()
    if not g_use_gradient or g_row_ready then
        return
    end

    gfx.set(0, 0, 0, 1)
    gfx.rect(0, 0, g_img_w, 1, 1)

    local y = GRADIENT_SAMPLE_ROW
    if y < 0 then y = 0 end
    if y > (g_img_h - 1) then y = g_img_h - 1 end

    gfx.blit(0, 1, 0,
        0, y, g_img_w, 1,
        0, 0, g_img_w, 1
    )

    g_row_ready = true
end

local function sample_gradient_rgb(t)
    ensure_gradient_row_blitted()

    t = clamp01(t)
    local x = math.floor(t * (g_img_w - 1) + 0.5)

    gfx.x = x
    gfx.y = 0

    local rr, gg, bb = gfx.getpixel()
    local r = math.floor((rr or 0) * 255 + 0.5)
    local g = math.floor((gg or 0) * 255 + 0.5)
    local b = math.floor((bb or 0) * 255 + 0.5)

    if PASTEL_BLEND_TO_WHITE > 0.0 then
        r, g, b = blend_to_white(r, g, b, PASTEL_BLEND_TO_WHITE)
    end

    return r, g, b
end


------------------------------------------------------------
-- Fallback: rainbow sampler (HSV)
------------------------------------------------------------

local function sample_rainbow_rgb(t)
    t = clamp01(t)
    if t >= 1.0 then
        t = 0.999999
    end

    local h = t
    local s = 1.0
    local v = 1.0

    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local tt = v * (1 - (1 - f) * s)

    i = i % 6

    local r, g, b
    if i == 0 then
        r, g, b = v, tt, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, tt
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = tt, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    local R = math.floor(r * 255 + 0.5)
    local G = math.floor(g * 255 + 0.5)
    local B = math.floor(b * 255 + 0.5)

    if PASTEL_BLEND_TO_WHITE > 0.0 then
        R, G, B = blend_to_white(R, G, B, PASTEL_BLEND_TO_WHITE)
    end

    return R, G, B
end


------------------------------------------------------------
-- Main
------------------------------------------------------------

local function main()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then
        return
    end

    -- Try to load gradient image; silently fall back to rainbow
    local gradient_path = resolve_gradient_path()
    local ok = try_load_gradient_image(gradient_path)
    if not ok then
        g_use_gradient = false
    end

    -- Collect top-level tracks and detect keyword matches
    local top_level_indices = {}
    local top_level_has_keyword = {}

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

    if #top_level_indices == 0 then
        if g_use_gradient then unload_gradient_image() end
        return
    end

    -- Build list of top-level tracks that should get sampled colors (NOT matching keyword)
    local sample_top_indices = {}
    for _, idx in ipairs(top_level_indices) do
        if not top_level_has_keyword[idx] then
            table.insert(sample_top_indices, idx)
        end
    end

    -- Assign base RGB to remaining top-level tracks by sampling
    local top_level_base_rgb = {}
    local n = #sample_top_indices

    for pos, track_index in ipairs(sample_top_indices) do
        local slot = distribution_slot(pos, n)

        local t
        if n <= 1 then
            t = 0
        else
            if g_use_gradient then
                t = slot / (n - 1)  -- include endpoints for gradient pixels
            else
                t = slot / n        -- avoid t==1.0 wrap for HSV
            end
        end

        local r, g, b
        if g_use_gradient then
            r, g, b = sample_gradient_rgb(t)
        else
            r, g, b = sample_rainbow_rgb(t)
        end

        top_level_base_rgb[track_index] = { r = r, g = g, b = b }
    end

    --------------------------------------------------------
    -- Pass 1: apply sampled colors + darkening + stereo pair lock
    --
    -- FIX: stereo pairing now compares against the previous track AT THE SAME DEPTH
    -- within the same top-level block, ignoring any intervening child tracks.
    --------------------------------------------------------

    local current_top_index = nil

    -- sequential attenuation memory (original behavior)
    local prev_brightness = nil
    local prev_top_index = nil

    -- depth-aware memory for stereo pairing (and “previous at this depth” lookup)
    local last_at_depth = {}         -- [depth] = { name = "...", brightness = 0.xx }
    local last_depth_seen = 0

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(proj, i)
        local depth = reaper.GetTrackDepth(track)
        local _, name = reaper.GetTrackName(track, "")

        if depth == 0 then
            current_top_index = i
            -- New top block: reset depth tracking
            last_at_depth = {}
            last_depth_seen = 0
            prev_brightness = nil
            prev_top_index = nil
        end

        local base = current_top_index and top_level_base_rgb[current_top_index] or nil
        if base ~= nil then
            -- Clear deeper remembered depths when we move up
            if depth < last_depth_seen then
                for d = depth + 1, last_depth_seen do
                    last_at_depth[d] = nil
                end
            end
            last_depth_seen = depth

            local v

            if depth == 0 then
                v = 1.0
            else
                if DARKEN_MODE == "by_depth" then
                    v = 1.0 - (DARKEN_PER_STEP * depth)
                else
                    -- from_previous (sequential), but stereo can override based on previous at SAME depth
                    local same_block = (prev_top_index == current_top_index)
                    local prev_same_depth = last_at_depth[depth]

                    if prev_same_depth and is_stereo_pair(prev_same_depth.name, name) then
                        -- Stereo-pair lock (ignores intervening children)
                        v = prev_same_depth.brightness
                    else
                        -- Normal sequential attenuation
                        if (not same_block) or (prev_brightness == nil) then
                            v = 1.0 - DARKEN_PER_STEP
                        else
                            v = prev_brightness * (1.0 - DARKEN_PER_STEP)
                        end
                    end
                end
            end

            if v < MIN_VALUE then
                v = MIN_VALUE
            end

            local r = math.floor(base.r * v + 0.5)
            local g = math.floor(base.g * v + 0.5)
            local b = math.floor(base.b * v + 0.5)

            local native_color = rgb_to_native(r, g, b)
            color_track_and_items(track, native_color)

            -- Update sequential memory
            prev_brightness = v
            prev_top_index = current_top_index

            -- Update same-depth memory (used for stereo pairing even if children appear after)
            last_at_depth[depth] = { name = name, brightness = v }
        else
            -- Keyword TL blocks are not in base map; reset sequential memory to avoid leakage
            prev_brightness = nil
            prev_top_index = nil
            last_at_depth = {}
            last_depth_seen = 0
        end
    end

    -- Pass 2: keyword overrides (track + subtracks + items/takes)
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

    if g_use_gradient then
        unload_gradient_image()
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end


reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Track colors: gradient/rainbow + keywords + stereo pair lock (depth-aware)", -1)
