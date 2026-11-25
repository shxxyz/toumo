local ok, translate = pcall(require, "toumo_i18n")
local T = ok and translate or function(message)
    return message
end

return {
    name = "toumo",
    fullname = T("Toumo"),
    description = T("Show faint ink from neighboring pages and paper grain in single-page EPUB view."),
    version = "1.3.0-preview.1",
}
