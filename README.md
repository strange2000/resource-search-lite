<div align="center">

![Resource Finder Lite](web/assets/banner.svg)

# 🔍 资源搜索 Lite

**零依赖 · 不登录 · 不转存**

关键词 → 网盘分享链接 / 磁力链 / m3u8 直链

<a href="README.en.md"><img src="https://img.shields.io/badge/English_Switch-2f81f7?style=for-the-badge&logo=googletranslate&logoColor=white" alt="Switch to English" height="28"></a>
<a href="https://strange2000.github.io/"><img src="https://img.shields.io/badge/%F0%9F%8F%A0_Home-8b949e?style=for-the-badge&logo=githubpages&logoColor=white" alt="Home" height="28"></a>

</div>

## ✨ 特点

- 🪶 **零依赖**：只要 `curl` 和一个 POSIX shell；不需要 Node、Python、数据库，也不挂 alist
- 🔒 **不碰账号**：不转存、不写盘、不留登录态，只把链接找出来
- ☁️ **9 类网盘**：夸克、百度、阿里云盘、UC、移动云盘、天翼、115、PikPak、迅雷、123 云盘
- 🧲 **磁力带做种数**：knaben + apibay 两路并发，按做种数、体积、清晰度打分
- 🎬 **直链**：14 个苹果CMS 采集接口，输出 `站点 / 标题 / m3u8 或 mp4`
- 📡 **豆瓣首发**：按豆瓣条目 ID 扫讨论区回应，冷门新片也有机会
- 🎞️ **m3u8 落盘**：直链拉成本地 `.ts`，多码率 / 相对路径 / fMP4 都能处理
- 📝 **字幕**：subhd 字幕转标准 SRT，`--预览 <sid>` 最稳
- 🌐 **单文件网页**：双击即用，中英双语，右上角一键切换
- 🧮 **规则可改**：`scripts/rules.tsv` 一行一条正则，改完立即生效

## 🧩 两件东西 · 互不依赖

| | 🛠️ 命令行 skill | 🌐 单文件网页 |
|---|---|---|
| **路径** | `scripts/` + `SKILL.md` | `web/index.html` |
| **依赖** | `curl` + 一个 POSIX shell | 任意浏览器 |
| **能做** | 网盘 + 磁力 + 苹果CMS 直链，按做种数 / 体积 / 清晰度排序 | 网盘 + 磁力（受 CORS 限制，没有做种数） |
| **适合** | 手机终端、Agent、批处理 | 双击打开、静态托管、手机浏览器 |

两边**互不依赖**：只要网页就下载 `web/index.html` 一个文件；只要命令行就拷走 `scripts/` 一个目录。

## 🚀 快速开始

```bash
git clone https://github.com/strange2000/resource-search-lite.git
cd resource-search-lite

# 网盘 + 磁力（主入口）
bash scripts/find.sh "关键词"

# 只查磁力，最快（约 6–15 秒）
bash scripts/find.sh "关键词" --磁力 --条数 10

# 只查指定网盘
bash scripts/find.sh "关键词" --类型 quark,baidu

# 一行一条链接，方便管道
bash scripts/find.sh "关键词" --只链接

# 机器可读
bash scripts/find.sh "关键词" --json

# 三路并发：网盘 + 磁力 + 直链
bash scripts/all.sh "关键词"

# 只要 m3u8 / mp4 直链
bash scripts/collect.sh "关键词"

# 豆瓣讨论区捞链接（参数是豆瓣条目 ID）
bash scripts/社群首发.sh 37817151

# 把 m3u8 拉成本地 .ts（先取 6 片验证）
bash scripts/m3u8取流.sh "https://…/index.m3u8" --名 片名 --片 6

# 取字幕并转成 SRT（用 sid 最稳）
bash scripts/字幕.sh --预览 rvMUEC

# 自检各源连通性
bash scripts/find.sh --测
```

Android、BusyBox、路由器上把 `bash` 换成 `sh`。

## ⚙️ 配置搜索实例

网盘搜索走 [PanSou](https://github.com/fish2018/pansou) 的公开实例。**公共实例会风控**——403、Cloudflare 400、60 秒不响应都出现过。建议自备：

```bash
# 环境变量（支持逗号分隔多台，失败自动换）
RS_INSTANCE=https://your-pansou.example.com bash scripts/find.sh "关键词"
RS_INSTANCE=https://a.example.com,https://b.example.com bash scripts/find.sh "关键词"
```

优先级：`RS_INSTANCE` → 脚本内置默认。`config.json` 是同一份配置的集中说明，方便 fork 后统一改；shell 脚本实际读环境变量与 `scripts/rules.tsv`。

## 🌐 网页版

`web/index.html` 是单文件页面，没有构建步骤，也没有后端：

- 双击打开，或扔到任意静态托管（GitHub Pages / Cloudflare Pages / Nginx）
- 实例：`index.html?instance=https://your-pansou.example.com`，多台用逗号
- 语言：右上角 `中文 / EN`；也可用 `?lang=zh` / `?lang=en`，选择会记在本地
- 亮 / 暗主题、搜索历史、类型筛选、直链播放、失败重试

网页版能直接出磁力，是因为走同一实例的 `magnet` 通道（该实例开了 CORS）。代价是**只有标题 + 磁力链，没有做种数和体积**；要带做种数的完整清单请用命令行版。

## 🎬 采集接口（苹果CMS）

`scripts/collect.sh` 直连 14 个苹果CMS 采集接口，背后是几千个中文影视站：

```bash
bash scripts/collect.sh "片名"          # 严格：标题含关键词才留
bash scripts/collect.sh "片名" --宽      # 不过滤，先看有没有货
bash scripts/collect.sh "片名" --满      # 每站最多 20 条（默认 8）
bash scripts/collect.sh --探活           # 今天哪几个接口活着
bash scripts/collect.sh "片名" --超时=8   # 单接口超时秒数（默认 15）
```

输出 TSV：`站点 <TAB> 标题 <TAB> 直链`。

这些接口一律不带 `Access-Control-Allow-Origin`，所以**只能在终端跑**，网页版故意不提供。

已知坑：

- 安卓 Chrome 不认 m3u8，点开播不了；丢给 VLC / nPlayer / MX Player，或用 ffmpeg 转 mp4
- 个别站把中文转成 `\uXXXX`，标题是转义码，但链接能用
- 接口域名常换，死了不用改代码——往脚本顶部 `EP` 列表里加新的即可
- 实测（2026-11-14）：`--探活` 活 7 / 死 7；「三体」27 条 / 6 个站 / 13 秒

## 📡 社群首发（豆瓣讨论区）

冷门新片在网盘聚合、磁力索引里常常全是 0 条，但首发链接往往就贴在豆瓣条目讨论区的回应里（《钥匙／鍵 2026》就是这么找到的）。`社群首发.sh` 走豆瓣 rexxar 接口，免登录：

```bash
bash scripts/社群首发.sh 37817151                    # 扫该条目全部讨论帖
bash scripts/社群首发.sh 37817151 --topic 498744331  # 只扫指定帖
bash scripts/社群首发.sh 37817151 --max 200          # 每帖最多 200 条回应（默认 100）
bash scripts/社群首发.sh 37817151 --no-expand        # 不展开短链（省流量）
```

输出 TSV：`帖ID <TAB> 类型 <TAB> 链接`，类型 = 夸克 / 百度 / 115 / 磁力 / 短链 / 直链。

参数是**豆瓣条目 ID**，不是片名。这类帖子里大量是「我有／多少米／私信」的付费引流，形如 `s/xxxxxxx` 的才是真链接；脚本会处理「左斜杠/斜杠」这类躲过滤写法，但**链接真伪仍要自己确认**。

## 🎞️ m3u8 取流（落成本地 .ts）

```bash
bash scripts/m3u8取流.sh "https://…/index.m3u8" --名 片名
bash scripts/m3u8取流.sh "https://…/index.m3u8" --片 6          # 只取前 6 片，先验能不能下
bash scripts/m3u8取流.sh "https://…/index.m3u8" --并发 4 --目录 ./out
bash scripts/m3u8取流.sh ./local.m3u8 --名 test                # 也吃本地 m3u8
```

自动处理：master 多码率挑 `BANDWIDTH` 最大档、相对路径拼接、`EXT-X-MAP` 初始化段（fMP4）、失败重试 3 次。**拒绝** `METHOD=AES-128`（手机端没有 openssl），退出码 3。

产物是 `.ts` 不是 mp4；要 mp4 在电脑上用 `ffmpeg -i x.ts -c copy -bsf:a aac_adtstoasc x.mp4`。全片可能上千片、几百 MB 到 1 GB+，别在流量环境跑。

## 📝 字幕（subhd → SRT）

`scripts/字幕.sh` 从 subhd 取中文字幕，按规则转成标准 SRT：

```bash
bash scripts/字幕.sh --预览 rvMUEC                  # 用 sid 直取（最稳）
bash scripts/字幕.sh "真实 2017" --取 1 --页面 1     # 关键词搜索（实验性）
bash scripts/字幕.sh --预览 rvMUEC --目录 ./subs     # 指定输出目录
```

时间轴：起点取 `[HH:MM:SS]`，终点取下一块起点 − 0.15 s（上限 +7 s），不足 0.4 s 补到 1.2 s，末条 +3 s，毫秒补零到 3 位。实测一条 sid 494 条字幕，输出约 30 KB。

已知限制：

- subhd 三个域国内都能打开，但**单请求 9–30 秒**，偶发静默超时；脚本会换域重试
- **关键词搜索不稳**：站点结构是 `搜索 → /d/<id> → /a/<sid>`，搜索结果页混着大量推荐位链接，脚本按片名匹配失败会报错列候选，不会乱抓；稳妥用 `--预览 <sid>`
- 没有 ffprobe，`--视频` 的时间轴对齐做不到；`--到115` 不支持

## 🧮 打分规则

`scripts/rules.tsv` 每行 `正则<TAB>分数<TAB>标记`，`grep -E` 匹配、大小写不敏感：

```
2160p|4K|UHD	25	4K
1080p|FHD|全高清	20	1080p
中字|中文字幕|简中|繁中	18	中字
枪版|CAM|抢先版	-50	枪版
```

叠加规则：

- 做种数：每 2 个 +1，上限 +20
- 新近：1 天内 +20 / 7 天内 +12 / 30 天内 +5 / 一年以上 −10
- 体积 < 150 MB：−15
- 命中排除词（预告 / 花絮 / 枪版 / 已失效…）直接跳过

## 📁 项目结构

```
resource-search-lite/
├── SKILL.md              Agent / 命令行说明（含 frontmatter）
├── config.json           实例、磁力源、打分规则的集中说明
├── scripts/
│   ├── find.sh           网盘 + 磁力（主入口）
│   ├── collect.sh        苹果CMS 直链（终端专用）
│   ├── all.sh            三路并发
│   ├── 社群首发.sh        豆瓣讨论区捞链接（参数是条目 ID）
│   ├── m3u8取流.sh        m3u8 → 本地 .ts
│   ├── 字幕.sh            subhd 字幕 → SRT（--预览 <sid> 最稳）
│   └── rules.tsv         打分规则
└── web/
    ├── index.html        单文件网页（中英双语）
    └── assets/
        ├── banner.svg    封面图
        └── social-preview.png 社交预览图
```

## 🛡️ 隐私

- 不带任何账号、Cookie、token，也不读取浏览器里其他站点的数据
- 不收集、不上传使用数据
- 网页版的类型选择、语言、搜索历史只存在你自己的 `localStorage`
- 命令行不写盘，临时文件在退出时删除

## ⚠️ 已知限制

- 公开实例不稳定，风控时先隔 30–60 秒重跑，或换自建实例
- mksh 算术是 32 位，超过 2 GB 的字节数做截位近似，体积显示误差约 0.1 G
- 国际磁力索引不认中日韩文，冷门外语片先用中文译名试
- 网盘只「搜」，不转存、不写盘、不碰账号

## ⚖️ 免责声明

本项目只做**公开索引的聚合与排序**，不托管、不存储、不分发任何文件，不提供下载服务，也不绕过任何付费 / 登录限制。所有链接均来自第三方公开接口，可用性与合法性由来源方负责。请自行确认所在地区的法律与平台条款；权利人若认为某个接口不应被收录，开 issue 说明即可移除。

## 📄 License

[MIT](LICENSE)
