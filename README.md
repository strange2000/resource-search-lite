# 资源搜索 Lite

**零依赖的资源检索：关键词 → 网盘分享链接 / 磁力链 / m3u8 直链。**
不需要 Node，不需要网盘登录态，不挂 alist，不转存、不写盘。

> A dependency-free resource finder: keyword in, pan links / magnets / HLS links out.
> Pure POSIX shell + curl, plus a single-file web UI. No Node, no login, no storage.

这是电脑版 `resource-search` 的**手机适配分支**：原版靠 Node 跑 `.cjs`，并调用夸克网盘官方 skill 与 alist 里的 115 做「转存 / 云下载」。本仓库把「存入」这一整段摘掉，只负责**把链接找出来**，于是运行时只剩 shell 和 curl，手机、路由器、NAS、CI 里都能跑。

## 与电脑版的区别

| | 电脑版 `resource-search` | 本仓库 `resource-search-lite` |
|---|---|---|
| 运行时 | Node ≥ 18（`.cjs`） | POSIX shell + curl |
| 依赖 | alist、115、夸克官方 skill | 无 |
| 收尾动作 | 转存到网盘 / 115 云下载 | **直接给链接**，自己决定怎么用 |
| 磁力 | 多源，按做种数排序 | knaben + apibay，按做种数/体积排序 |
| 直链 | 苹果CMS 采集接口 | 同（14 个接口，可增删） |
| 界面 | CLI | CLI + 单文件网页 |

## 依赖

- `curl`
- 一个能跑的 shell：
  - Android：系统自带 `mksh`（`/system/bin/sh`），脚本就是为它写的
  - Linux / macOS：`bash`（`sh` 若指向 `dash` 会因 `$'...'`、`${v//a/b}` 报错，请显式用 `bash`）
  - Windows：Git Bash 或 WSL
- 可选：`mktemp`、`grep`、`sed`（Android 由 toybox 提供）

## 快速开始

```bash
git clone https://github.com/strange2000/resource-search-lite.git
cd resource-search-lite

# 网盘 + 磁力（主入口）
bash scripts/find.sh "三体"

# 只查磁力，最快（约 6–15 秒）
bash scripts/find.sh "三体" --磁力 --条数 10

# 只查指定网盘
bash scripts/find.sh "三体" --类型 quark,baidu

# 一行一条链接，方便管道
bash scripts/find.sh "三体" --只链接

# 机器可读
bash scripts/find.sh "三体" --json

# 三路并发：网盘 + 磁力 + 直链
bash scripts/all.sh "三体"

# 只要 m3u8 / mp4 直链
bash scripts/collect.sh "三体"

# 自检各源连通性
bash scripts/find.sh --测
```

Android / Eta 里把 `bash` 换成 `sh`，路径改成 skill 目录即可。

## 配置搜索实例（重要）

网盘搜索走 [PanSou](https://github.com/fish2018/pansou) 的公开实例。**公共实例会风控**——403、Cloudflare 400、60 秒不响应都出现过，同一个词隔一分钟结果可能差很多。所以：

```bash
# 推荐：环境变量指向你自己的实例
RS_INSTANCE=https://your-pansou.example.com bash scripts/find.sh "三体"

# 多台实例用逗号分隔（脚本会用第一个，失败再换）
RS_INSTANCE=https://a.example.com,https://b.example.com bash scripts/find.sh "三体"
```

优先级：`RS_INSTANCE` → 脚本内的内置默认。

`config.json` 里的「搜索服务」是同一份配置的**集中说明**（方便你 fork 后统一改），供网页和后来者参照；shell 脚本读的是环境变量与 `scripts/rules.tsv`。

## 网页版

`web/index.html` 是单文件页面，没有任何构建步骤，也没有后端：

- 直接双击打开，或扔到任意静态托管（GitHub Pages / Cloudflare Pages / Nginx）
- 指定实例：`index.html?instance=https://your-pansou.example.com`
- 多实例：`?instance=https://a,https://b`
- 也能写进 `localStorage.rs_instances`，地址栏参数优先级更高
- 亮 / 暗主题、搜索历史、类型筛选、直链播放、失败重试

网页版能直接出磁力，是因为走同一个 PanSou 实例的 `magnet` 通道（该实例开了 CORS）。代价是**只有标题 + 磁力链，没有做种数和体积**；要按做种数排序请用 shell 版。

## 采集接口（苹果CMS）

`scripts/collect.sh` 直连 14 个苹果CMS 采集接口，背后是几千个中文影视站：

```bash
bash scripts/collect.sh "片名"          # 严格：标题含关键词才留
bash scripts/collect.sh "片名" --宽      # 不过滤，先看有没有货
bash scripts/collect.sh "片名" --满      # 每站最多 20 条（默认 8）
bash scripts/collect.sh --探活           # 今天哪几个接口活着
bash scripts/collect.sh "片名" --超时=8   # 单接口超时秒数（默认 15）
```

输出 TSV：`站点 <TAB> 标题 <TAB> 直链`。

**这条只能在终端跑**：这些接口一律没有 `Access-Control-Allow-Origin`，浏览器页面调不到，所以网页版故意不提供。

已知坑：

- 安卓 Chrome 不认 m3u8，点开播不了。丢给 VLC / nPlayer / MX Player，或用 ffmpeg 转 mp4。
- 个别站把中文转成 `\uXXXX`，标题是转义码，但链接能用。
- 接口域名常换，死了不用改代码——往脚本顶部 `EP` 列表里加新的即可。
- 实测（2026-11-14）：`--探活` 活 7 / 死 7；「三体」27 条 / 6 个站 / 13 秒。

## 打分规则

`scripts/rules.tsv` 每行 `正则<TAB>分数<TAB>标记`，`grep -E` 匹配、大小写不敏感，改完立即生效：

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

## 目录结构

```
resource-search-lite/
├── SKILL.md              Agent（Eta 等）调用说明
├── config.json           实例、磁力源、打分规则的集中说明
├── scripts/
│   ├── find.sh           网盘 + 磁力（主入口）
│   ├── collect.sh        苹果CMS 直链（终端专用）
│   ├── all.sh            三路并发
│   └── rules.tsv         打分规则
└── web/
    └── index.html        单文件网页版
```

## 作为 Agent Skill 安装

仓库根目录就是 skill 目录，`SKILL.md` 带 frontmatter。放进 Agent 的 skills 目录即可（Eta：`files/skills/resource-search-lite/`），之后按 `SKILL.md` 里的命令调用。

## 已知限制

- 公开实例不稳定，风控时先隔 30–60 秒重跑，或换自建实例。
- mksh 算术是 32 位，超过 2 GB 的字节数做截位近似，体积显示误差约 0.1 G。
- 国际磁力索引不认中日韩文，冷门外语片先用中文译名试。
- 网盘只「搜」，不转存、不写盘、不碰账号。
- 网盘类型过滤在本地按 `merged_by_type` 的 key 做；请求时不传 `cloud_types`（实测比传满更全，三体：209 条 vs 21 条）。

## 免责声明

本项目只做**公开索引的聚合与排序**，不托管、不存储、不分发任何文件，不提供下载服务，也不绕过任何付费/登录限制。所有链接均来自第三方公开接口，可用性、合法性由来源方负责。请自行确认所在地区的法律与平台条款；权利人若认为某个接口不应被收录，开 issue 说明即可移除。

## License

[MIT](LICENSE)
