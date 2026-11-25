-- KOReader's active interface locale is independent of the open book's language.
local gettext = require("gettext")

-- Columns: Simplified Chinese, Traditional Chinese, Japanese. English is the key.
local messages = {
    ["Toumo"] = { "纸背透墨", "紙背透墨", "紙の裏写り" },
    ["Show faint ink from neighboring pages and paper grain in single-page EPUB view."] = {
        "在日间单页 EPUB 上叠印相邻页的淡墨与纸纹。",
        "在日間單頁 EPUB 上疊印相鄰頁的淡墨與紙紋。",
        "昼間の単ページ表示で、EPUB に隣接ページの薄い裏写りと紙の質感を加えます。",
    },
    ["Enable show-through"] = { "启用透墨", "啟用透墨", "裏写りを有効にする" },
    ["Source pages"] = { "背面取哪一页", "背面取哪一頁", "透かすページ" },
    ["Odd pages look back, even pages look ahead"] = {
        "奇数往前，偶数往后",
        "奇數往前，偶數往後",
        "奇数ページは前、偶数ページは後ろ",
    },
    ["Always look back"] = { "总是往前", "總是往前", "常に前のページ" },
    ["Always look ahead"] = { "总是往后", "總是往後", "常に次のページ" },
    ["Ink layers"] = { "叠加页数", "疊加頁數", "重ねるページ数" },
    ["Paper grain only"] = { "不叠印，只看纸纹", "不疊印，只看紙紋", "紙の質感のみ" },
    ["1 layer"] = { "一层", "一層", "1 枚" },
    ["2 layers"] = { "两层", "兩層", "2 枚" },
    ["3 layers"] = { "三层", "三層", "3 枚" },
    ["4 layers"] = { "四层", "四層", "4 枚" },
    ["Paper grain"] = { "纸张纹理", "紙張紋理", "紙の質感" },
    ["Off"] = { "关闭", "關閉", "オフ" },
    ["Subtle"] = { "细淡", "細淡", "控えめ" },
    ["Pronounced"] = { "明显", "明顯", "はっきり" },
    ["Ink density"] = { "墨迹浓度", "墨跡濃度", "裏写りの濃さ" },
    ["Light"] = { "淡", "淡", "薄め" },
    ["Standard"] = { "标准", "標準", "標準" },
    ["Strong"] = { "较深", "較深", "濃いめ" },
}

return function(message)
    local locale = (gettext.current_lang or "C"):lower():gsub("-", "_")
    local language = locale:match("^([a-z]+)")
    local entry = messages[message]
    if entry and language == "ja" then
        return entry[3]
    elseif entry and language == "zh" then
        if
            locale:find("_hant", 1, true)
            or locale:find("_tw", 1, true)
            or locale:find("_hk", 1, true)
            or locale:find("_mo", 1, true)
        then
            return entry[2]
        end
        return entry[1]
    end
    return message
end
