-- Run from a KOReader directory with its own LuaJIT and shared libraries.
-- arg[1]: plugin directory, arg[2]: copy without accelerators, arg[3]: test EPUB.
require("setupkoenv")
local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
local native = dofile(arg[1] .. "/toumo_raster.lua")
local portable = dofile(arg[2] .. "/toumo_raster.lua")
assert(native.accelerated, "expected a matching native library")
assert(not portable.accelerated, "expected Lua fallback in the second directory")
local have_cbb = BB.has_cblitbuffer
local function equal(a, b, label)
    local x, y = BB.tostring(a), BB.tostring(b)
    if x ~= y then
        for i = 1, #x do
            if x:byte(i) ~= y:byte(i) then
                error(string.format("%s: byte %d, native %d, reference %d", label, i, x:byte(i), y:byte(i)))
            end
        end
        error(label .. ": different dimensions")
    end
end

local checks = 0
local function compare(page, draw, margins)
    local w, h = page:getWidth(), page:getHeight()
    local p = native.plate(page, margins, 1)
    local q = portable.plate(page, margins, 1)
    equal(p, q, "mirrored half-resolution plate")
    -- A non-symmetric plate and different layer parity also exercise the mirror back.
    local configurations =
        { { 0, 0, 0 }, { 0, 36, 13 }, { 1, 22, 0 }, { 2, 36, 13 }, { 3, 52, 26 }, { 4, 52, 26 } }
    local paper = native.mask({}, w, h, 0, 13)
    for _, config in ipairs(configurations) do
        local a, b = {}, {}
        for i = 1, config[1] do
            a[i], b[i] = p, q
        end
        local cached = config[3] == 13 and paper or nil
        local mask = native.mask(a, w, h, config[2], config[3], cached)
        local ref = portable.mask(b, w, h, config[2], config[3])
        equal(mask, ref, "paper/blur/dither mask")
        local target, expected = draw:copy(), draw:copy()
        native.apply(mask, target, 2, 1, w, h)
        portable.apply(ref, expected, 2, 1, w, h)
        equal(target, expected, "composited pixels, padding and border")
        target:free()
        expected:free()
        mask:free()
        ref:free()
        checks = checks + 1
    end
    p:free()
    q:free()
    paper:free()
end

for _, cbb in ipairs(have_cbb and { false, true } or { false }) do
    BB:setUseCBB(cbb)
    for _, dim in ipairs({ { 1, 1 }, { 2, 3 }, { 17, 24 }, { 32, 48 }, { 79, 95 }, { 340, 251 } }) do
        local w, h = dim[1], dim[2]
        local page = BB.new(w, h, BB.TYPE_BB8, nil, w + 7, w + 7)
        local draw = BB.new(w + 4, h + 2, BB.TYPE_BB8, nil, w + 13, w + 13)
        local bytes = ffi.cast("uint8_t*", draw.data)
        for i = 0, tonumber(draw.stride) * draw.h - 1 do
            bytes[i] = (13 * i + math.floor(i / 7)) % 256
        end
        bytes = ffi.cast("uint8_t*", page.data)
        for i = 0, tonumber(page.stride) * page.h - 1 do
            bytes[i] = (23 * i + math.floor(i / 11)) % 256
        end
        compare(page, draw, { left = 1, right = 1, top = 0, bottom = 1 })
        page:free()
        draw:free()
    end
    for _, kind in ipairs({ BB.TYPE_BB8, BB.TYPE_BBRGB32 }) do
        local page = BB.new(25, 31, kind)
        local draw = BB.new(27, 35, kind)
        page:setRotation(1)
        page:setInverse(1)
        draw:setRotation(1)
        draw:setInverse(1)
        for y = 0, page:getHeight() - 1 do
            for x = 0, page:getWidth() - 1 do
                page:setPixel(x, y, BB.ColorRGB32((x * 19) % 256, (y * 31) % 256, (x * y) % 256, 255))
            end
        end
        draw:fill(BB.ColorRGB32(123, 197, 45, 255))
        compare(page, draw, { left = 1, right = 3, top = 2, bottom = 0 })
        page:free()
        draw:free()
    end
end
BB:setUseCBB(have_cbb)
print("ABI", ffi.os, ffi.arch, "hardfp", ffi.abi("hardfp"), "C blitter", have_cbb, "cases", checks)
local cre = require("libs/libkoreader-cre")
cre.initHyphDict("data/hyph/")
cre.registerFont("fonts/noto/NotoSerif-Regular.ttf")
cre.registerFont("fonts/noto/NotoSansCJKsc-Regular.otf")
local w, h = 421, 587
local e = cre.newDocView(w, h, 1)
e:readDefaults()
e:setStringProperty("font.face.default", "Noto Sans CJK SC")
e:setIntProperty("crengine.render.requested_dom_version", cre.getLatestDomVersion())
e:setIntProperty("crengine.doc.embedded.styles.enabled", 1)
e:setStyleSheet("data/epub.css", "")
e:setFontSize(23)
e:setPageMargins(15, 15, 15, 15)
assert(e:loadDocument(arg[3], false))
e:renderDocument()
local total = e:getPages()
local seen_text, seen_picture = 0, 0
for i = 1, math.min(total, 18) do
    e:gotoPage(i)
    local bb = BB.new(w, h, BB.TYPE_BB8)
    local _, ratio = e:drawCurrentPage(bb, false, false, true, false)
    if (ratio > 0.25 and seen_picture == 0) or (ratio == 0 and seen_text == 0) then
        local target = BB.new(w + 4, h + 3, BB.TYPE_BB8)
        target:blitFrom(bb, 2, 1, 0, 0, w, h)
        compare(bb, target, e:getPageMargins())
        print("EPUB", i, "image ratio", ratio, "writing mode", e:getPageWritingMode(i))
        if ratio > 0 then
            seen_picture = seen_picture + 1
        else
            seen_text = seen_text + 1
        end
        target:free()
    end
    bb:free()
    if seen_text > 0 and seen_picture > 0 then
        break
    end
end
-- The plugin prefetches by forking a private CRe instance. Check that a
-- child's stencil survives the shared-memory handoff and the parent stays put.
local Job = dofile(arg[1] .. "/toumo_job.lua")
e:gotoPage(1)
local function mask_for_second_page(raster)
    e:gotoPage(2)
    local bb = BB.new(w, h, BB.TYPE_BB8)
    e:drawCurrentPage(bb, false, false, true, false)
    local plate = raster.plate(bb, e:getPageMargins(), e:getHeaderHeight())
    local mask = raster.mask({ plate }, w, h, 36, 13)
    bb:free()
    plate:free()
    return mask
end
local job = assert(Job.start(2, w, h, function()
    return mask_for_second_page(native)
end))
-- Slow emulation should not turn this numerical test into a timeout test.
local got
for i = 1, 4000 do
    local done, mask = job:collect(false)
    if done then
        got = mask
        break
    end
    ffi.C.usleep(1000)
end
assert(got, "worker did not deliver a stencil")
assert(e:getCurrentPage() == 1, "worker moved the foreground document")
local want = mask_for_second_page(portable)
equal(got, want, "background image stencil")
got:free()
want:free()
print("FORK_FRAME_MATCH")
e:close()
assert(seen_text > 0 and seen_picture > 0, "missing test page")
print("TOUMO_RASTER_PASS", checks)
