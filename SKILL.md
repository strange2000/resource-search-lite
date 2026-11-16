---
name: resource-search-lite
description: 资源检索（零依赖）。按关键词搜网盘分享链接（夸克/百度/阿里云/UC/115/天翼/迅雷/123/PikPak）、直连磁力索引拿磁力链（带做种数、体积），并能查 14 个苹果CMS 采集接口拿 m3u8/mp4 直链，按规则打分排序，输出可直接复制的链接。纯 shell + curl，不需要 Node、alist、网盘登录态，只搜不存。 / Zero-dependency resource finder: pan share links, magnets with seeders, HLS direct links. Shell + curl only.
---

# 资源搜索 Lite

关键词 → **网盘分享链接** + **磁力链** + **m3u8/mp4 直链**。只搜不存，不碰任何账号。

只用 `curl` 和一个 POSIX shell，不需要 Node、Python、数据库，也不挂 alist。

## 什么时候用

- 用户想知道「某部片子 / 某本书 / 某门课」在哪儿能拿到
- 用户想要磁力链，自己丢进下载工具或网盘离线
- 用户想要网盘分享链接，自己去转存

## 命令

Android / BusyBox 用 `sh`，Linux / macOS / Git Bash 把 `sh` 换成 `bash`：

```bash
sh scripts/all.sh "关键词"                      # 三路一起跑：网盘 + 磁力 + 直链（并发，约 30–60 秒）
sh scripts/find.sh "关键词"                     # 清单：网盘分组 + 磁力打分排序
sh scripts/find.sh "关键词" --只链接             # 只要链接，一行一条
sh scripts/find.sh "关键词" --磁力 --条数 10     # 只查磁力，最快（约 6–15 秒）
sh scripts/find.sh "关键词" --类型 quark,baidu   # 只查指定网盘（默认不传类型，拿全）
sh scripts/find.sh "关键词" --json               # 机器可读
sh scripts/find.sh "关键词" --网盘条数 20        # 每类网盘最多列几条（默认 10）
sh scripts/find.sh --测                         # 自检各源连通性
sh scripts/collect.sh "片名"                    # 只要直链（m3u8 / mp4）
```

`all.sh` 内部并行跑两条：网盘+磁力走 `find.sh`，直链走 `collect.sh`，两边同时起、谁先回都不影响另一路；
分区打印（每区标题带各自耗时与 rc），末尾给退出码（两路都失败才是 1）。
`--只直链` / `--只网磁` 只跑一路；`--宽/--满/--全部/--超时=N` 给 `collect.sh`，
`--条数/--类型/--选/--磁链/--夸克条数`（带值）与其余开关给 `find.sh`。
某一路空输出时会提示怎么单独重跑。

## 搜索实例

网盘搜索走 PanSou 公开实例，**公共实例会风控**（403、Cloudflare 400、60 秒不响应）。优先让用户自备：

```bash
RS_INSTANCE=https://your-pansou.example.com sh scripts/find.sh "关键词"
RS_INSTANCE=https://a.example.com,https://b.example.com sh scripts/find.sh "关键词"
```

优先级 `RS_INSTANCE` → 脚本内置默认。拉不到结果时先怀疑实例，隔 30–60 秒重跑，别急着改代码。

## 取数规则

- 网盘：发**一次** `res=merge` 请求，**不带 `cloud_types`**。实测不传比传满 9/10 类多 10 倍以上（三体：不传 209 条 / 54s；传 10 类 21 条 / 65s；只传 quark 5 条）。类型过滤在本地按 `merged_by_type` 的 key 做。请求失败才退回「按类型并发」兜底。
- 请求必须带完整浏览器 UA + `Referer`，否则实例直接 403。
- 磁力：`knaben`（POST `/v1`，返回自带 `magnetUrl`）+ `apibay`（`q.php`）并发；只有这两家有真实做种数 / 体积。`nyaa` 国内连不上，没接。
- 标题必须做相关度过滤（中文按整串、英文按每个词都在）。
- 不传类型时结果里常带 `magnet`/`ed2k`，脚本把它们排除在网盘分组外；磁力仍以 knaben/apibay 那两路（有做种数）为准。

## 采集接口（苹果CMS 直链）

另一条独立的路：直连 14 个苹果CMS 采集接口，拿 m3u8/mp4 直链（背后是几千个中文影视站）。
**只能在终端跑** —— 这些接口一律没有 `Access-Control-Allow-Origin`，浏览器页面调不到。

```bash
sh scripts/collect.sh "片名"           # 严格：标题含关键词才留
sh scripts/collect.sh "片名" --满       # 每站最多 20 条（默认 8）
sh scripts/collect.sh "片名" --宽       # 不过滤，先看有没有货
sh scripts/collect.sh --探活            # 今天哪几个接口活着（14 个）
sh scripts/collect.sh "片名" --超时=8    # 单接口超时秒数（默认 15）
```

输出 TSV：`站点 <TAB> 标题 <TAB> 直链`。

实测（2026-11-14）：`--探活` 活 7 / 死 7；「三体」→ 27 条 / 6 个站 / **13 秒**；「钥匙2026」→ 1 条 `play.phimgood.com`；不存在的词 → 0 条并给排查提示。

坑：

- 安卓 Chrome **不认 m3u8**，直接点开播不了。要么丢给 VLC / nPlayer / MX，要么用 ffmpeg 转 mp4。
- 个别站把中文转成 `\uXXXX`，这种条目标题是转义码，但链接能用。
- 接口域名常换，死了不用改代码，往脚本顶部 `EP` 列表里加新的。
- 解析用 shell 内建字符串操作 + 先 `grep -F` 预筛，同一个「三体」从 4 分钟跑不完降到 13 秒。

## 社群首发（豆瓣讨论区捞片源，2026-11-15）

冷门新片在网盘聚合、磁力索引里常常全是 0 条，但首发链接就贴在豆瓣条目讨论区的回应里
（《钥匙／鍵 2026》就是这么找到的）。走的是豆瓣 rexxar 接口，免登录。

```bash
sh scripts/社群首发.sh 37817151                    # 扫该条目全部讨论帖
sh scripts/社群首发.sh 37817151 --topic 498744331  # 只扫指定帖
sh scripts/社群首发.sh 37817151 --max 200          # 每帖最多 200 条回应（默认 100）
sh scripts/社群首发.sh 37817151 --no-expand        # 不展开短链（省流量）
```

输出 TSV：`帖ID <TAB> 类型 <TAB> 链接`，类型 = 夸克/百度/115/磁力/短链/直链。
参数是**豆瓣条目 ID**（不是片名）。实测：条目 37817151 → 1.6 秒，命中 1 条
`https://pan.quark.cn/s/38d3d84a625a`。

注意：这类帖子里大量是「我有／多少米／私信」的付费引流，形如 `s/xxxxxxx` 的才是真链接；
脚本已处理「左斜杠/斜杠」这类躲过滤写法，但**链接真伪还得自己验**。

## m3u8 取流（直链落成本地 .ts，2026-11-15）

```bash
sh scripts/m3u8取流.sh "https://…/index.m3u8" --名 钥匙2026
sh scripts/m3u8取流.sh "https://…/index.m3u8" --片 6          # 只取前 6 片，先验能不能下
sh scripts/m3u8取流.sh "https://…/index.m3u8" --并发 4 --目录 /sdcard/Download
sh scripts/m3u8取流.sh ./local.m3u8 --名 test                # 也吃本地 m3u8
```

自动处理：master 多码率挑 `BANDWIDTH` 最大档、相对路径拼接、`EXT-X-MAP` 初始化段（fMP4）、失败重试 3 次。
**拒绝** `METHOD=AES-128`（手机没有 openssl），退出码 3。

实测（《钥匙》真链，`--片 6`）：13 秒，6 片 4,839,496 字节，首字节 `0x47`（TS 同步字节）。

坑：
- 产物是 `.ts` 不是 mp4（手机没 ffmpeg）；要 mp4 拷到电脑 `ffmpeg -i x.ts -c copy -bsf:a aac_adtstoasc x.mp4`。
- 全片会有上千片、几百 MB 到 1 GB+，别在流量环境跑。
- 脚本结束时清理 `seg_*.ts`；中途 Ctrl-C 退出若有残留，手动删掉即可。

## 字幕（subhd，2026-11-16 新增，搜索入口受站点结构限制）

```bash
sh scripts/字幕.sh --预览 rvMUEC                      # 用 sid 直取（这条最稳）
sh scripts/字幕.sh "真实 2017" --取 1 --页面 1         # 关键词搜索（实验性，见下）
```

把 subhd 的字幕正文拉下来，按规则转成标准 SRT：起始取 `[HH:MM:SS]`，终点 = 下一块起点 − 0.15 s、
上限 +7 s，不足 0.4 s 的补到 1.2 s，最后一条 +3 s；毫秒补零到 3 位。

**实测（sid rvMUEC）**：正文 **494 条**，末条起点 `02:00:05,000`，输出 `.srt` 约 30 KB，块结构/时间轴都对
（与桌面版字幕工具产出的 494 条逐条对得上；末条结束时间按 +3 s 计为 `02:00:08,000`，
对方为 `02:00:07,850`，差 0.15 s（其文件末尾多一个空时间块），不影响播放）。

**已知限制（实际踩到的）：**

- subhd 三个域（`.tv/.me/.one`）国内直连都能 200，但**单请求 9–30 秒**，偶发静默超时；
  脚本对搜索页和 preview 都做了「换域重试」，但仍可能全挂。
- **关键词搜索这条路不稳**：站点当前结构是 `搜索 → /d/<id> 条目页 → /a/<sid>`，
  而搜索结果页里混着大量「推荐位」`/d/` 链接，脚本按片名匹配卡片失败时会直接报错并列出候选，
  **不会乱抓**。要稳妥就用 `--预览 <sid>`（sid 从条目页 `/a/` 链接里拿）。
- 缺 ffprobe：`--视频` 的时间轴对齐做不到，脚本会明说跳过；`--到115` 不做。

## 退出码（2026-11-16 起，三态）

| 码 | 含义 | 出现场景 |
|---|---|---|
| `0` | 有结果 | 网盘/磁力/直链任一路有货 |
| `3` | **连通但没货** | 实例能回、接口能答，但这部片子确实没有 |
| `1` | **没连上** | 网盘实例与磁力源都不通（风控/断网/全超时） |
| `2` | 参数错误 | `find.sh` 未知参数（保持原有语义，不占用 3） |

`all.sh` 的聚合：单路模式原样透传那一路的 rc；双路时**任一路 0 → 0**、**两路都 3 → 3**、其余 → 1。
之所以不让「零结果」返回 0，是因为「网上没有」和「没查成」对调用方是两件事。

## 打分

`scripts/rules.tsv` 每行 `正则<TAB>分数<TAB>标记`，`grep -E`、大小写不敏感，与 `config.json` 的 20 条加分一一对应；再叠加做种（每 2 个 +1，上限 20）、新近（1 天 +20 / 7 天 +12 / 30 天 +5 / 一年以上 −10）、体积 < 150 MB −15。排除词命中直接跳过。

## 网页版

`web/index.html` 是独立的单文件页面，与命令行互不依赖：网盘 + 磁力（同一实例的 magnet 通道），中英双语，右上角切换。采集接口没有 CORS，网页拿不到，只能用 `collect.sh`。

## 已知限制

- 公开实例会风控：403、cloudflare 400、60 秒不响应都见过；同一关键词两次结果可能差很多，隔 30–60 秒重跑。`--测` 报失败时先看是不是这个原因。
- 国际磁力索引不认中日韩文，冷门外语片先用中文译名试。
- mksh 算术是 32 位，超过 2 GB 的字节数做了截位近似，显示误差约 0.1 G。
- 网盘只「搜」，不转存、不写盘。

## 目录说明

```
SKILL.md                 本文件
config.json              规则集中说明（实例、磁力源、加分项）
scripts/all.sh           三路并发（网盘 + 磁力 + 直链），一条命令跑完
scripts/find.sh          网盘 + 磁力（主入口）
scripts/collect.sh       苹果CMS 站群直链（m3u8 / mp4），只在终端跑
scripts/社群首发.sh       豆瓣讨论区捞网盘/磁力（参数是豆瓣条目 ID）
scripts/m3u8取流.sh       m3u8 直链 → 本地 .ts（不支持 AES-128）
scripts/字幕.sh           subhd 字幕 → SRT（--预览 <sid> 最稳）
scripts/rules.tsv        打分规则，改这里立即生效
web/index.html           单文件网页版（静态托管或本地打开）
web/assets/banner.svg    封面图
```
