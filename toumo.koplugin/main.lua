local T = require("toumo_i18n")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Job = require("toumo_job")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local BB = require("ffi/blitbuffer")
local Raster = require("toumo_raster")
local logger = require("logger")

local Plugin = WidgetContainer:extend({ name = "toumo" })
local modes = {
    { "Odd pages look back, even pages look ahead", "sheet" },
    { "Always look back", "previous" },
    { "Always look ahead", "next" },
}
local depths =
    { { "Paper grain only", 0 }, { "1 layer", 1 }, { "2 layers", 2 }, { "3 layers", 3 }, { "4 layers", 4 } }
local textures = { { "Off", 0 }, { "Subtle", 13 }, { "Pronounced", 26 } }
local strengths = { { "Light", 22 }, { "Standard", 36 }, { "Strong", 52 } }

function Plugin:init()
    local doc = self.ui and self.ui.document
    if not doc or not self.ui.rolling or not (doc.file or ""):lower():match("%.epub$") then
        return
    end
    self.enabled = G_reader_settings:nilOrTrue("toumo_enabled")
    self.mode = G_reader_settings:readSetting("toumo_source", "sheet")
    self.depth = G_reader_settings:readSetting("toumo_depth", 2)
    if type(self.depth) ~= "number" or self.depth % 1 ~= 0 or self.depth < 0 or self.depth > 4 then
        self.depth = 2
    end
    self.texture = G_reader_settings:readSetting("toumo_texture", 13)
    if self.texture ~= 0 and self.texture ~= 13 and self.texture ~= 26 then
        self.texture = 13
    end
    self.strength = G_reader_settings:readSetting("toumo_strength", 36)
    if self.strength ~= 22 and self.strength ~= 36 and self.strength ~= 52 then
        self.strength = 36
    end
    self.plates, self.order = {}, {}
    self.direction = 1
    self.poll = function()
        if not self.job then
            return
        end
        local page = self.job.page
        local done, mask = self.job:collect(false)
        if done then
            self.job = nil
            self.prepared_page, self.prepared_mask = page, mask
        else
            UIManager:scheduleIn(0.08, self.poll)
        end
    end
    self.ui.menu:registerToMainMenu(self)
    local view = self.ui.view
    self.original = view.drawPageView
    self.wrapper = function(v, bb, x, y)
        self.original(v, bb, x, y)
        -- Thumbnails, previews and other offscreen clients keep a clean page.
        if self.enabled and not Screen.night_mode and bb == Screen.bb then
            self:overlay(v, bb, x, y)
        end
    end
    view.drawPageView = self.wrapper
end

function Plugin:remember(page, plate)
    if self.plates[page] then
        plate:free()
        return
    end
    if #self.order >= 2 * self.depth + 1 then
        local old = table.remove(self.order, 1)
        self.plates[old]:free()
        self.plates[old] = nil
    end
    self.plates[page] = plate
    table.insert(self.order, page)
end

function Plugin:cancelUpcoming()
    if self.prepare then
        UIManager:unschedule(self.prepare)
        self.prepare = nil
    end
    UIManager:unschedule(self.poll)
    if self.job then
        self.job:cancel()
        self.job = nil
    end
    if self.prepared_mask then
        self.prepared_mask:free()
    end
    self.prepared_page, self.prepared_mask = nil, nil
end

function Plugin:reset()
    if not self.plates then
        return
    end
    self:cancelUpcoming()
    for _, plate in pairs(self.plates) do
        plate:free()
    end
    if self.mask and self.mask ~= self.paper then
        self.mask:free()
    end
    if self.paper then
        self.paper:free()
    end
    self.mask, self.paper, self.page, self.layout = nil, nil, nil, nil
    self.plates, self.order = {}, {}
end
Plugin.onDocumentRerendered = Plugin.reset
Plugin.onDocumentPartiallyRerendered = Plugin.reset
Plugin.onSetDimensions = Plugin.reset

function Plugin:sourcesFor(page, last)
    local forward = self.mode == "next" or (self.mode == "sheet" and page % 2 == 0)
    local step = forward and 1 or -1
    local sources = {}
    for depth = 1, self.depth do
        local source = page + depth * step
        if source < 1 or source > last then
            break
        end
        sources[depth] = source
    end
    return sources
end

function Plugin:knownLayers(sources)
    local layers, missing = {}, false
    for depth, page in ipairs(sources) do
        layers[depth] = self.plates[page]
        if not layers[depth] then
            missing = true
        end
    end
    return layers, missing
end

function Plugin:startJob(page, sources, w, h)
    return Job.start(page, w, h, function()
        local layers = self:knownLayers(sources)
        local doc = self.ui.document
        local buffer
        for depth, source in ipairs(sources) do
            if not layers[depth] then
                buffer = buffer or BB.new(w, h, doc.render_color and BB.TYPE_BBRGB32 or BB.TYPE_BB8)
                doc._document:gotoPage(source)
                doc._document:drawCurrentPage(
                    buffer,
                    doc.render_color,
                    false,
                    doc._smooth_scaling,
                    Screen.sw_dithering
                )
                layers[depth] = Raster.plate(buffer, doc:getPageMargins(), doc:getHeaderHeight())
            end
        end
        if buffer then
            buffer:free()
        end
        return Raster.mask(layers, w, h, self.strength, self.texture, self.paper)
    end)
end

function Plugin:planAhead(page, last, w, h)
    local predicted = page + self.direction
    if self.depth == 0 or predicted < 1 or predicted > last then
        return
    end
    local sources = self:sourcesFor(predicted, last)
    if #sources == 0 then
        return
    end
    -- Let the current page reach the panel first. A fast jump cancels this
    -- timer. The completed prefetch never calls setDirty or paints the screen.
    self.prepare = function()
        self.prepare = nil
        if self.page ~= page or not self.enabled or Screen.night_mode or self.ui.view.view_mode ~= "page" then
            return
        end
        self.job = self:startJob(predicted, sources, w, h)
        if self.job then
            UIManager:scheduleIn(0.08, self.poll)
        end
    end
    UIManager:scheduleIn(0.15, self.prepare)
end

function Plugin:paperOnly(w, h)
    if not self.paper and self.texture > 0 then
        self.paper = Raster.mask({}, w, h, 0, self.texture)
    end
    return self.paper
end

function Plugin:takePrediction(page)
    local mask, attempted
    if self.prepared_page == page then
        mask, attempted = self.prepared_mask, true
        self.prepared_mask = nil
    elseif self.job and self.job.page == page then
        local done
        done, mask = self.job:collect(true)
        attempted = done
        self.job = nil
    end
    self:cancelUpcoming()
    return mask, attempted
end

function Plugin:maskFor(page, last, w, h)
    local mask, attempted = self:takePrediction(page)
    if mask then
        return mask
    end
    local sources = self:sourcesFor(page, last)
    if #sources == 0 then
        return self:paperOnly(w, h)
    end
    local layers, missing = self:knownLayers(sources)
    if missing and not attempted then
        local job = self:startJob(page, sources, w, h)
        if job then
            local done
            done, mask = job:collect(true)
            if done and mask then
                return mask
            end
        end
        logger.warn("Toumo: adjacent-page render unavailable", page)
    end
    if next(layers) then
        return Raster.mask(layers, w, h, self.strength, self.texture, self.paper)
    end
    return self:paperOnly(w, h)
end

function Plugin:overlay(view, target, x, y)
    local doc = view.document
    local front = doc.buffer
    if not front or view.view_mode ~= "page" or doc.no_page_sync or doc:getVisiblePageCount() ~= 1 then
        return
    end
    local w, h = front:getWidth(), front:getHeight()
    local page = view.state.page
    if not page then
        return
    end
    local layout = table.concat({
        w,
        h,
        doc:getDocumentRenderingHash(true),
        doc.configurable.font_gamma or 0,
        doc._smooth_scaling and 1 or 0,
        Screen.sw_dithering and 1 or 0,
        doc.render_color and 1 or 0,
    }, ":")
    if self.layout ~= layout then
        self:reset()
        self.layout = layout
    end
    if
        self.depth > 0
        and not self.plates[page]
        and not (self.ui.highlight and self.ui.highlight.selected_text)
    then
        self:remember(page, Raster.plate(front, doc:getPageMargins(), doc:getHeaderHeight()))
    end
    if self.page ~= page then
        if self.page then
            self.direction = page > self.page and 1 or -1
        end
        if self.mask and self.mask ~= self.paper then
            self.mask:free()
        end
        self.mask = nil
        self.page = page
        local last = doc:getPageCount()
        self.mask = self:maskFor(page, last, w, h)
        self:planAhead(page, last, w, h)
    end
    if self.mask then
        Raster.apply(self.mask, target, x + view.state.offset.x, y + view.state.offset.y, w, h)
    end
end

function Plugin:onSuspend()
    if self.plates then
        self:cancelUpcoming()
    end
end

function Plugin:onResume()
    local doc = self.ui and self.ui.document
    if
        self.enabled
        and self.page
        and doc
        and doc.buffer
        and not Screen.night_mode
        and self.ui.view.view_mode == "page"
        and not self.job
        and not self.prepare
        and not self.prepared_page
    then
        self:planAhead(self.page, doc:getPageCount(), doc.buffer:getWidth(), doc.buffer:getHeight())
    end
end

function Plugin:configure(field, key, value)
    self[field] = value
    G_reader_settings:saveSetting(key, value)
    self:reset()
    UIManager:setDirty(self.ui.dialog or self.ui, "partial")
end

function Plugin:addToMainMenu(items)
    local function choices(list, field, key)
        local menu = {}
        for _, item in ipairs(list) do
            local label, value = item[1], item[2]
            table.insert(menu, {
                text = T(label),
                radio = true,
                checked_func = function()
                    return self[field] == value
                end,
                callback = function()
                    self:configure(field, key, value)
                end,
            })
        end
        return menu
    end
    items.toumo = {
        text = T("Toumo"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = T("Enable show-through"),
                checked_func = function()
                    return self.enabled
                end,
                callback = function()
                    self:configure("enabled", "toumo_enabled", not self.enabled)
                end,
            },
            { text = T("Source pages"), sub_item_table = choices(modes, "mode", "toumo_source") },
            { text = T("Ink layers"), sub_item_table = choices(depths, "depth", "toumo_depth") },
            { text = T("Paper grain"), sub_item_table = choices(textures, "texture", "toumo_texture") },
            { text = T("Ink density"), sub_item_table = choices(strengths, "strength", "toumo_strength") },
        },
    }
end

function Plugin:onCloseDocument()
    if not self.original then
        return
    end
    self.enabled = false
    self:reset()
    if self.ui.view.drawPageView == self.wrapper then
        self.ui.view.drawPageView = self.original
    end
end
return Plugin
