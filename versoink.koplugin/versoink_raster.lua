local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
local floor, min, max = math.floor, math.min, math.max
local Raster = {}
local folder = debug.getinfo(1, "S").source:sub(2):match("^(.*[/])")
local native
if ffi.os == "Linux" and ffi.arch == "arm" and require("device").model == "KindlePaperWhite3" then
    ffi.cdef([[
        void vi_plate(const uint8_t*,int,int,int,int,int,int,int,uint8_t*,int);
        void vi_add_layer(uint16_t*,const uint8_t*,int,int,int,int);
        void vi_soften(uint16_t*,uint16_t*,int,int);
        void vi_mask(const uint16_t*,int,int,const uint8_t*,int,int,uint8_t*,int,int);
        void vi_apply(uint8_t*,int,const uint8_t*,int,int,int);
    ]])
    local ok, lib = pcall(ffi.load, folder .. "versoink-armel.so")
    if ok then
        native = lib
    end
end
Raster.accelerated = native ~= nil

-- One ink-coverage sample per 2 x 2 pixels, in the orientation of the back
-- of the sheet. Only source page content is sampled, not its running header.
function Raster.plate(page, margins, header)
    local w, h = page:getWidth(), page:getHeight()
    local plate = BB.new(math.ceil(w / 2), math.ceil(h / 2), BB.TYPE_BB8)
    local gray = page
    if page:getType() ~= BB.TYPE_BB8 or page:getRotation() ~= 0 or page:getInverse() ~= 0 then
        gray = BB.new(w, h, BB.TYPE_BB8)
        gray:blitFrom(page)
    end
    local src = ffi.cast("const uint8_t*", gray.data)
    local dst = ffi.cast("uint8_t*", plate.data)
    local ss, ds = tonumber(gray.stride), tonumber(plate.stride)
    local left, right = margins.left or 0, w - (margins.right or 0)
    local top, bottom = (margins.top or 0) + (header or 0), h - (margins.bottom or 0)
    if native then
        native.vi_plate(src, ss, w, h, left, top, right, bottom, dst, ds)
        if gray ~= page then
            gray:free()
        end
        return plate
    end
    for y = max(0, math.ceil(top / 2)), min(plate.h - 1, floor((bottom - 2) / 2)) do
        local row, out = 2 * y * ss, y * ds
        for x = max(0, math.ceil((w - right) / 2)), min(plate.w - 1, floor((w - left - 2) / 2)) do
            local i = row + w - 2 - 2 * x
            dst[out + x] = 255 - floor((src[i] + src[i + 1] + src[i + ss] + src[i + ss + 1] + 2) / 4)
        end
    end
    if gray ~= page then
        gray:free()
    end
    return plate
end

-- Combine all depth layers at half size. plate() already mirrors a page,
-- so every second layer is reflected back to its original orientation.
local weights = { 256, 112, 52, 24 }
local bayer = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local bit = require("bit")
local grain_file = folder .. "paper.grain"
local paper_bytes
local function getPaper()
    if not paper_bytes then
        local file = assert(io.open(grain_file, "rb"))
        paper_bytes = file:read("*a")
        file:close()
        assert(#paper_bytes == 512 * 512, "invalid paper texture")
    end
    return ffi.cast("const uint8_t*", paper_bytes)
end

function Raster.mask(layers, w, h, strength, texture, base)
    local cols, rows = math.ceil(w / 2), math.ceil(h / 2)
    local coverage = ffi.new("uint16_t[?]", cols * rows)
    for depth = 1, #weights do
        local plate = layers[depth]
        if plate then
            local src = ffi.cast("const uint8_t*", plate.data)
            local stride = tonumber(plate.stride)
            if native then
                native.vi_add_layer(coverage, src, stride, cols, rows, depth)
            else
                local reverse = depth % 2 == 0
                for y = 0, rows - 1 do
                    local row, dest = y * stride, y * cols
                    for x = 0, cols - 1 do
                        local ix = reverse and cols - 1 - x or x
                        coverage[dest + x] = coverage[dest + x] + floor(src[row + ix] * weights[depth] / 256)
                    end
                end
            end
        end
    end
    local mask = (base and native) and base:copy() or BB.new(w, h, BB.TYPE_BB8A)
    local dst, ds = ffi.cast("uint8_t*", mask.data), tonumber(mask.stride)
    local paper = texture > 0 and getPaper() or nil
    if next(layers) then
        local tmp = ffi.new("uint16_t[?]", cols * rows)
        if native then
            native.vi_soften(coverage, tmp, cols, rows)
        else
            for y = 0, rows - 1 do
                for x = 0, cols - 1 do
                    local row = y * cols
                    tmp[row + x] = floor(
                        (
                            coverage[row + max(0, x - 1)]
                            + 2 * coverage[row + x]
                            + coverage[row + min(x + 1, cols - 1)]
                            + 2
                        ) / 4
                    )
                end
            end
            for y = 0, rows - 1 do
                for x = 0, cols - 1 do
                    coverage[y * cols + x] = floor(
                        (
                            tmp[max(0, y - 1) * cols + x]
                            + 2 * tmp[y * cols + x]
                            + tmp[min(rows - 1, y + 1) * cols + x]
                            + 2
                        ) / 4
                    )
                end
            end
        end
    end
    if native then
        native.vi_mask(coverage, w, h, paper, texture, strength, dst, ds, base and 1 or 0)
        return mask
    end
    local xmap = ffi.new("uint16_t[?]", w)
    for x = 0, w - 1 do
        local i = bit.band(x, 1023)
        xmap[x] = min(i, 1023 - i)
    end
    local shade = ffi.new("uint8_t[?]", 16 * 128)
    for ph = 0, 15 do
        for i = 0, 127 do
            shade[ph * 128 + i] = 17 * floor(i / 17 + (bayer[ph + 1] + 0.5) / 16)
        end
    end
    for y = 0, h - 1 do
        local iy = floor(y / 2)
        local row, below = iy * cols, min(iy + 1, rows - 1) * cols
        local yf = y % 2
        local phase, out = (y % 4) * 4, y * ds + 1
        local py = bit.band(y, 1023)
        local paperrow = min(py, 1023 - py) * 512
        for x = 0, w - 1, 2 do
            local ix = floor(x / 2)
            local nx = min(ix + 1, cols - 1)
            local a, b = coverage[row + ix], coverage[row + nx]
            if yf == 1 then
                a = (a + coverage[below + ix]) / 2
                b = (b + coverage[below + nx]) / 2
            end
            local v1 = min(255, a) * strength / 255
            if paper then
                v1 = v1 + paper[paperrow + xmap[x]] * texture / 255
            end
            dst[out + 2 * x] = shade[(phase + x % 4) * 128 + floor(v1 + 0.5)]
            if x + 1 < w then
                local v2 = min(255, (a + b) / 2) * strength / 255
                if paper then
                    v2 = v2 + paper[paperrow + xmap[x + 1]] * texture / 255
                end
                dst[out + 2 * x + 2] = shade[(phase + (x + 1) % 4) * 128 + floor(v2 + 0.5)]
            end
        end
    end
    return mask
end
function Raster.apply(mask, target, x, y, w, h)
    if
        native
        and target:getType() == BB.TYPE_BB8
        and target:getRotation() == 0
        and target:getInverse() == 0
        and x % 1 == 0
        and y % 1 == 0
        and x >= 0
        and y >= 0
        and x + w <= target.w
        and y + h <= target.h
    then
        local dst = ffi.cast("uint8_t*", target.data) + y * target.stride + x
        native.vi_apply(dst, target.stride, ffi.cast("const uint8_t*", mask.data), mask.stride, w, h)
    else
        target:alphablitFrom(mask, x, y, 0, 0, w, h)
    end
end
return Raster
