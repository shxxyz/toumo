# toumo · 纸背透墨

一个 KOReader 插件。翻开 EPUB 时，相邻页的文字和插画会像印在薄纸背面一样，在当前页隐约透出来。墨影取自这本书的实际排版，横排、日文竖排和图文混排都可以用。

[下载安装包](https://github.com/shxxyz/toumo/releases/latest)

## 实机渲染对照

下面两张均已开启透墨。两组样张来自 Kindle Paperwhite 3 上的 KOReader Tategumi v2026.10.1 和 toumo 1.1.1，使用两层墨影、标准浓度和细淡纸纹。点击图片可以查看原尺寸。

### 横排 · 余华《活着》

汇文明朝体。看正文留白处，纸纤维上还有一层淡淡的镜像字。

![开启透墨的《活着》横排局部，汇文明朝体](docs/images/huozhe-huiwen-mincho-03-on.png)

### 竖排 · 雨森たきび《負けヒロインが多すぎる！》

思源宋体日文版（Source Han Serif JP）。背面的字也跟随原书竖排。

![开启透墨的《負けヒロインが多すぎる！》竖排局部，思源宋体日文版](docs/images/makeine-source-han-serif-jp-03-on.png)

<details>
<summary>展开同页对照：关闭与开启</summary>

| 书籍 | 关闭 | 开启 |
| --- | --- | --- |
| 《活着》 | ![汇文明朝体横排原页](docs/images/huozhe-huiwen-mincho-03-off.png) | ![同一位置开启透墨](docs/images/huozhe-huiwen-mincho-03-on.png) |
| 《負けヒロインが多すぎる！》 | ![思源宋体日文版竖排原页](docs/images/makeine-source-han-serif-jp-03-off.png) | ![同一位置开启透墨](docs/images/makeine-source-han-serif-jp-03-on.png) |

</details>

<details>
<summary>查看 1072 × 1448 的完整竖排参考图</summary>

下面是开发插件时在 PW3 上生成的原创测试页，正文使用思源宋体日文版。整页可以看到留白、页边距和背面字影如何一起呈现。

![纸背透墨的 PW3 完整竖排参考页：午後の古書店](docs/images/pw3-vertical-reference.png)

</details>

## 安装与设置

1. 从 [Releases](https://github.com/shxxyz/toumo/releases) 下载 `toumo-v版本号.zip`。
2. 解压，把整个 `versoink.koplugin` 文件夹放进 KOReader 的 `plugins/`。Kindle 上的完整路径是 `/mnt/us/koreader/plugins/versoink.koplugin/`。
3. 重启 KOReader，打开一本分页显示的 EPUB。在 **工具 → 更多工具 → 纸背透墨** 中调整效果。

默认按排版后的页号配对。**奇数页向前取，偶数页向后取**。比如读第 5 页时，第 4 页左右镜像，第 3 页正向，两层一起透出来。想避开尚未读到的内容，可以选择「总是往前」。

| 选项 | 效果 |
| --- | --- |
| 背面取哪一页 | 按奇偶页决定方向，或固定向前、向后取页 |
| 叠加页数 | 0–4 层；相对墨量依次约为 100%、44%、20%、9%。设为 0 可只看纸纹 |
| 墨迹浓度 | 淡、标准、较深 |
| 纸张纹理 | 关闭、细淡、明显 |

页首和页尾只使用存在的相邻页。显示范围为日间、单页、分页 EPUB；夜间模式、连续滚动和双页模式沿用阅读器原本的页面。

## 兼容性与实现

已在 **Kindle Paperwhite 3 · KOReader Tategumi v2026.10.1** 验证。插件复用当前 EPUB 的排版，后台预取下一个可能需要的墨影，再与正文一次合成。跳页或预取未完成时，首次显示前会等待渲染；背页渲染失败或等待超时，则使用可用的缓存层。图片页和文字页采用相同的翻页流程。

插件入口为 Lua。包内附有从 `versoink.c` 编译的 ARMEL 加速库，仅在 Paperwhite 3 上加载。其他设备走 Lua 实现，实际速度和兼容性有待设备验证。

## 构建与测试

用 Python 3 运行 `python3 tools/package.py` 即可在 `dist/` 生成安装包。需要重编 PW3 加速库时，先运行 `tools/build-armel.sh`。构建使用 Zig 0.13.0，环境变量 `ZIG` 可指定编译器路径。

在已配置 SSH 的 PW3 上，运行 `tools/test-pw3.sh <SSH 主机别名>` 可复测镜像方向、墨量、图片页、预取与取消。测试用本仓库自带的原创 EPUB 测试页和独立的临时设置，在内存中绘制。测试环境使用 Source Han Serif JP，字体文件位于 `koreader/fonts/SourceHanSerifJP-Regular.otf`。

## 许可

插件以 [MIT 许可证](LICENSE) 发布。预览中的两部小说及其文字版权归各自权利人；仓库只展示用于对比渲染的局部截图。
