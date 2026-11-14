---
name: resource-search-lite
description: 资源检索（零依赖）。按关键词搜网盘分享链接（夸克/百度/阿里云/UC/115/天翼/迅雷/123/PikPak）、直连磁力索引拿磁力链（带做种数、体积），并能查 14 个苹果CMS 采集接口拿 m3u8/mp4 直链，按规则打分排序，输出可直接复制的链接。纯 shell + curl，不需要 Node、alist、网盘登录态，只搜不存。
---

# 找资源（lite）

关键词 → **网盘分享链接** + **磁力链** + **m3u8/mp4 直链**。只搜不存，不碰任何账号。

这是电脑版 `resource-search` 的 lite 分支：原版用 Node 跑 `.cjs`，并调用夸克官方 skill 与 alist 里的 115 做「转存 / 云下载」。这里把「存入」整段摘掉，只负责把链接找出来，所以运行时只剩 shell + curl。

## 什么时候用

- 用户想知道「某部片子 / 某本书 / 某门课」在哪儿能拿到
- 用户想要磁力链，自己丢进下载工具或网盘离线
- 用户想要网盘分享链接，自己去转存

## 命令

Android / Eta 用 `sh`，Linux / macOS / Git Bash 把 `sh` 换成 `bash`：

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

`all.sh` 内部并行跑两条：网盘 + 磁力走 `find.sh`，直链走 `collect.sh`，输出分两段（`──────── 网盘 + 磁力 ────────` / `──────── 直链 ────────`），末尾给两个 rc。参数分流：`--条数/--网盘条数/--类型/--磁力/--只链接/--json` 给前者，`--宽/--满/--超时=N` 给后者。

## 搜索实例

网盘搜索走 PanSou 公开实例，**公共实例会风控**（403、Cloudflare 400、60 秒不响应）。优先让用户自备：

```bash
RS_INSTANCE=https://your-pansou.example.com sh scripts/find.sh "关键词"
RS_INSTANCE=https://a.example.com,https://b.example.com sh scripts/find.sh "关键词"
```

优先级 `RS_INSTANCE` → 脚本内置默认。拉不到结果时先怀疑实例，隔 30–60 秒重跑，别急着改代码。

## 取数规则（两端对齐后的最终结论）

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
- 解析用 mksh 内建字符串操作 + 先 `grep -F` 预筛，同一个「三体」从 4 分钟跑不完降到 13 秒。

## 打分

`scripts/rules.tsv` 每行 `正则<TAB>分数<TAB>标记`，`grep -E`、大小写不敏感，与 `config.json` 的 20 条加分一一对应；再叠加做种（每 2 个 +1，上限 20）、新近（1 天 +20 / 7 天 +12 / 30 天 +5 / 一年以上 −10）、体积 < 150 MB −15。排除词命中直接跳过。

## 已知限制

- 公开实例会风控：403、cloudflare 400、60 秒不响应都见过；同一关键词两次结果可能差很多，隔 30–60 秒重跑。`--测` 报失败时先看是不是这个原因。
- 国际磁力索引不认中日韩文，冷门外语片先用中文译名试。
- mksh 算术是 32 位，超过 2 GB 的字节数做了截位近似，显示误差约 0.1 G。
- 网盘只「搜」，不转存、不写盘。

## 目录说明

```
SKILL.md                 本文件
config.json              规则集中说明（实例、磁力源、加分项），留作对照
scripts/all.sh           三路并发（网盘 + 磁力 + 直链），一条命令跑完
scripts/find.sh          网盘 + 磁力（主入口）
scripts/collect.sh       苹果CMS 站群直链（m3u8 / mp4），只在终端跑
scripts/rules.tsv        打分规则，改这里立即生效
web/index.html           单文件网页版（静态托管或本地打开）
```

同一份逻辑不留两种实现，所以这里没有 `.cjs`。电脑版带转存的 skill 与本次 lite 各自维护、互不覆盖。
