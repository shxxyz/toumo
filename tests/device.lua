io.stdout:setvbuf("line")
require("setupkoenv")
local root = assert(arg[1])
local plugin_dir = root .. "/toumo.koplugin/"
package.path = plugin_dir .. "?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(root .. "/ephemeral.lua")
local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UI = require("ui/uimanager")
local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
local Raster = require("toumo_raster")
local socket = require("socket")
local now = socket.gettime
local w, h = 1072, 1448
local orig_bb = Screen.bb
local screen = BB.new(w, h, BB.TYPE_BB8)
Screen.bb = screen
-- The asymmetric bar detects an inverted even layer or a missing odd-layer mirror.
local unit = BB.new(65, 53, BB.TYPE_BB8)
unit:fill(BB.COLOR_WHITE)
unit:paintRect(8, 10, 15, 30, BB.COLOR_BLACK)
local plate = Raster.plate(unit, {}, 0, 0)
local function mean(mask, x)
    local src = ffi.cast("const uint8_t*", mask.data)
    local total = 0
    for y = 17, 32 do
        for i = x, x + 7 do
            total = total + src[y * mask.stride + 2 * i + 1]
        end
    end
    return total / 128
end
local last = 100
for depth = 1, 4 do
    local mask = Raster.mask({ [depth] = plate }, 65, 53, 36, 0)
    local left, right = mean(mask, 10), mean(mask, 47)
    local ink = (depth % 2 == 1) and right or left
    assert(
        ink > 0 and ink < last and ((depth % 2 == 1 and left == 0) or (depth % 2 == 0 and right == 0)),
        "layer orientation"
    )
    print("DEPTH", depth, left, right)
    last = ink
    mask:free()
end
local texture = Raster.mask({}, 65, 53, 36, 13)
local blank = Raster.mask({}, 65, 53, 36, 0)
assert(mean(texture, 10) > 0 and mean(blank, 10) == 0, "grain independent of ink")
texture:free()
blank:free()
plate:free()
unit:free()
local saved_model = Device.model
Device.model = "VersoQA"
local portable = dofile(plugin_dir .. "toumo_raster.lua")
Device.model = saved_model
assert(not portable.accelerated)
local base1 = BB.new(65, 57, BB.TYPE_BB8)
base1:fill(BB.COLOR_WHITE)
base1:paintRect(4, 4, 43, 26, BB.Color8(33))
local pa = Raster.plate(base1, {}, 0, 0)
local pb = portable.plate(base1, {}, 0, 0)
assert(BB.tostring(pa) == BB.tostring(pb))
local ma = Raster.mask({ pa, pa }, 65, 57, 36, 13)
local mb = portable.mask({ pb, pb }, 65, 57, 36, 13)
assert(BB.tostring(ma) == BB.tostring(mb), "portable and accelerated ink differ")
base1:free()
pa:free()
pb:free()
ma:free()
mb:free()
local cre = require("libs/libkoreader-cre")
cre.initHyphDict("./data/hyph/")
cre.registerFont("fonts/noto/NotoSerif-Regular.ttf")
cre.registerFont("fonts/SourceHanSerifJP-Regular.otf")
local engine = cre.newDocView(w, h, 1)
engine:readDefaults()
engine:setStringProperty("font.face.default", "Source Han Serif JP")
engine:setIntProperty("crengine.render.requested_dom_version", cre.getLatestDomVersion())
engine:setIntProperty("crengine.doc.embedded.styles.enabled", 1)
engine:setStyleSheet("./data/epub.css", "")
engine:setFontSize(44)
engine:setPageMargins(64, 72, 64, 72)
assert(engine:loadDocument(root .. "/test.epub", false))
engine:renderDocument()
print("TEST pages", engine:getPages(), "native", Raster.accelerated)
assert(Raster.accelerated)
local doc = {
    _document = engine,
    file = root .. "/test.epub",
    configurable = { font_gamma = 15 },
    render_color = false,
    been_rendered = true,
}
local CD = require("document/credocument")
setmetatable(doc, { __index = CD })
local view = {
    view_mode = "page",
    document = doc,
    state = { page = 1, offset = { x = 0, y = 0 } },
    visible_area = { w = w, h = h },
    drawPageView = require("apps/reader/modules/readerview").drawPageView,
}
local ui = {
    document = doc,
    view = view,
    rolling = {},
    highlight = {},
    menu = {
        registerToMainMenu = function() end,
    },
}
local P = dofile(plugin_dir .. "main.lua")
local plugin = P:new({ ui = ui, document = doc })
assert(plugin.wrapper and view.drawPageView == plugin.wrapper)
assert(engine:getPages() >= 7)
-- Use KOReader's locale loader just as the UI does. The settings and EPUB
-- in this harness are temporary, so no reader preferences are changed.
local gettext = require("gettext")
local previous_language = gettext.current_lang
local function labels()
    local m = {}
    plugin:addToMainMenu(m)
    local root = m.toumo
    local ordered = { root.text, dofile(plugin_dir .. "_meta.lua").description }
    for _, item in ipairs(root.sub_item_table) do
        ordered[#ordered + 1] = item.text
        for _, choice in ipairs(item.sub_item_table or {}) do
            ordered[#ordered + 1] = choice.text
        end
    end
    assert(dofile(plugin_dir .. "_meta.lua").fullname == root.text)
    return ordered
end
gettext.changeLang("C")
local english = labels()
assert(english[1] == "Toumo" and english[3] == "Enable show-through")
for _, case in ipairs({
    { "zh_CN", "纸背透墨", "启用透墨" },
    { "zh_TW", "紙背透墨", "啟用透墨" },
    { "ja", "紙の裏写り", "裏写りを有効にする" },
}) do
    assert(gettext.changeLang(case[1]))
    local actual = labels()
    assert(actual[1] == case[2] and actual[3] == case[3] and #actual == #english)
    for i = 1, #english do
        assert(actual[i] ~= english[i], case[1] .. " untranslated: " .. english[i])
    end
    print("UI_LOCALE", case[1], actual[1], #actual)
end
assert(gettext.changeLang("fr"))
assert(table.concat(labels(), "|") == table.concat(english, "|"))
gettext.changeLang(previous_language)
local function draw(n)
    view.state.page = n
    local start = now()
    view:drawPageView(screen, 0, 0)
    return (now() - start) * 1000
end
local redraws = 0
UI.setDirty = function()
    redraws = redraws + 1
end
local function runUntil(condition)
    local start = now()
    while not condition() do
        UI:_checkTasks()
        socket.sleep(0.005)
        assert(now() - start < 5, "timed out waiting for prefetch")
    end
    return math.floor(1000 * (now() - start))
end
local raw, plates, ratios = {}, {}, {}
local last = engine:getPages()
for n = 1, last do
    engine:gotoPage(n)
    local bb = BB.new(w, h, BB.TYPE_BB8)
    local _, ratio =
        engine:drawCurrentPage(bb, doc.render_color, false, doc._smooth_scaling, Screen.sw_dithering)
    raw[n] = bb
    ratios[n] = ratio
    print("IMAGE_RATIO", n, ratio)
    plates[n] = Raster.plate(bb, doc:getPageMargins(), doc:getHeaderHeight())
end
local function checkFrame(n)
    local bb = raw[n]:copy()
    if plugin.enabled and not Screen.night_mode then
        local layers = {}
        local step = (plugin.mode == "next" or plugin.mode == "sheet" and n % 2 == 0) and 1 or -1
        for i = 1, plugin.depth do
            layers[i] = plates[n + i * step]
        end
        local mask = Raster.mask(layers, w, h, plugin.strength, plugin.texture)
        Raster.apply(mask, bb, 0, 0, w, h)
        mask:free()
    end
    assert(BB.tostring(screen) == BB.tostring(bb), "wrong pixels for page " .. n)
    assert(engine:getCurrentPage() == n, "foreground reading position moved")
    bb:free()
end
local function ready(page)
    local waited = runUntil(function()
        return plugin.prepared_page == page and plugin.prepared_mask ~= nil
    end)
    assert(redraws == 0, "background worker requested a repaint")
    return waited
end
-- Explicit image regression. These assertions distinguish foreground image
-- effects, full-page artwork as an ink source, and prefetch/cache consistency.
local full, mixed = {}, nil
for n, r in ipairs(ratios) do
    if r > 0.5 then
        full[#full + 1] = n
    elseif r > 0 and r < 0.5 then
        mixed = n
    end
end
assert(#full == 2 and mixed, "fixture must render raster, SVG-wrapped raster and mixed pages")
local function illustrationChanged(n)
    local clean = ffi.cast("const uint8_t*", raw[n].data)
    local painted = ffi.cast("const uint8_t*", screen.data)
    local changed_gray, blacks, darkened = 0, 0, 0
    for i = 0, w * h - 1 do
        assert(painted[i] <= clean[i], "foreground lightened")
        if clean[i] == 0 then
            blacks = blacks + 1
            assert(painted[i] == 0)
        end
        if painted[i] < clean[i] then
            darkened = darkened + 1
            if clean[i] >= 100 and clean[i] < 245 then
                changed_gray = changed_gray + 1
            end
        end
    end
    assert(blacks > 0 and darkened > 0)
    return changed_gray, darkened
end
plugin.depth = 1
plugin.texture = 0
plugin.mode = "previous"
plugin:reset()
for _, front in ipairs(full) do
    draw(front)
    checkFrame(front)
    local gray = illustrationChanged(front)
    assert(gray > 50, "no ghost over the illustration itself")
    local text = front + 1
    assert(ratios[text] == 0)
    plugin:reset()
    draw(text)
    checkFrame(text)
    local _, count = illustrationChanged(text)
    assert(count > 1000, "illustration missing from back of text")
    local cold = BB.tostring(screen)
    plugin:reset()
    plugin.direction = 1
    draw(front)
    ready(text)
    draw(text)
    assert(BB.tostring(screen) == cold, "visited and unvisited illustration ink differ")
    print(
        "ILLUSTRATION",
        front,
        "coverage",
        ratios[front],
        "midtones changed",
        gray,
        "ghost pixels on text",
        count
    )
end
plugin.depth = 0
plugin.texture = 13
plugin:reset()
for _, front in ipairs(full) do
    draw(front)
    checkFrame(front)
    assert(illustrationChanged(front) > 0)
end
plugin.depth = 2
plugin.mode = "sheet"
plugin:reset()
draw(mixed)
checkFrame(mixed)
print("MIXED page", mixed, "coverage", ratios[mixed])
plugin.enabled = false
local base = {}
for i = 1, 5 do
    base[i] = draw(2)
end
table.sort(base)
print("BASELINE", base[3])
plugin.enabled = true
for _, depth in ipairs({ 1, 2, 4 }) do
    plugin.depth = depth
    plugin:reset()
    plugin.direction = 1
    local cold = draw(2)
    checkFrame(2)
    local firstmask = BB.tostring(screen)
    local xp = engine:getXPointer()
    local delay = ready(3)
    assert(engine:getXPointer() == xp)
    assert(BB.tostring(screen) == firstmask, "prefetch changed screen")
    local times = {}
    for n = 3, 6 do
        ready(n)
        times[#times + 1] = draw(n)
        checkFrame(n)
        if depth == 2 and n == 3 then
            screen:writePNG(root .. "/preview.png")
            doc.buffer:writePNG(root .. "/before.png")
        end
    end
    table.sort(times)
    print(
        "BENCH",
        depth,
        "cold single frame ms",
        math.floor(cold),
        "prefetch activity window ms",
        delay,
        "prefetched page turn ms (range)",
        math.floor(times[1]),
        math.floor(times[#times]),
        "redraw requests",
        redraws
    )
end
plugin.depth = 2
plugin:reset()
plugin.direction = 1
draw(2)
runUntil(function()
    return plugin.job ~= nil
end)
local in_flight = draw(3)
checkFrame(3)
print("INFLIGHT", math.floor(in_flight))
runUntil(function()
    return plugin.job ~= nil
end)
local obsolete = plugin.job.pid
draw(6)
checkFrame(6)
assert(ffi.C.waitpid(obsolete, nil, ffi.C.WNOHANG) == -1 and ffi.errno() == 10, "unreaped cancelled job")
draw(5)
checkFrame(5)
ready(4)
local backward = draw(4)
checkFrame(4)
print("BACKWARDS", math.floor(backward))
runUntil(function()
    return plugin.job ~= nil
end)
plugin:onDocumentRerendered()
assert(not plugin.job and not plugin.prepared_mask and not next(plugin.plates))
for _, mode in ipairs({ "previous", "next", "sheet" }) do
    plugin.mode = mode
    plugin:reset()
    draw(1)
    checkFrame(1)
    draw(last)
    checkFrame(last)
end
plugin.depth = 0
plugin:reset()
draw(3)
checkFrame(3)
assert(not plugin.prepare and not plugin.job)
plugin.texture = 0
plugin:reset()
draw(3)
checkFrame(3)
plugin.depth = 2
plugin.texture = 13
plugin:reset()
local night = Screen.night_mode
Screen.night_mode = true
draw(3)
checkFrame(3)
Screen.night_mode = night
plugin.enabled = false
draw(3)
checkFrame(3)
plugin.enabled = true
draw(3)
runUntil(function()
    return plugin.job ~= nil
end)
local closing = plugin.job.pid
plugin:onCloseDocument()
assert(not plugin.job and ffi.C.waitpid(closing, nil, ffi.C.WNOHANG) == -1)
assert(view.drawPageView ~= plugin.wrapper and redraws == 0)
local Job = require("toumo_job")
local job = assert(Job.start(1, 32, 32, function()
    ffi.C.usleep(4000000)
end))
local t = now()
local done, mask = job:collect(true)
assert(done and not mask and now() - t < 3 and ffi.C.waitpid(job.pid, nil, ffi.C.WNOHANG) == -1)
print("TIMEOUT cleanup ok")
Screen.bb = orig_bb
engine:close()
print("QA PASS")
