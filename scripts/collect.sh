#!/system/bin/sh
# 采集接口（苹果CMS 站群）搜索 —— 纯 shell 版（Android mksh / Linux bash 均可）
# 用法：
#   sh scripts/collect.sh "片名"              严格相关（标题含关键词才留）
#   sh scripts/collect.sh "片名" --宽          不过滤，全列（噪声多）
#   sh scripts/collect.sh --探活               看今天哪些接口活着
#   sh scripts/collect.sh "片名" --满           每个接口最多 20 条（默认 8）
#   sh scripts/collect.sh "片名" --超时=8       单接口超时秒数（默认 15）
# 输出：每行  站点 <TAB> 标题 <TAB> 直链（m3u8 优先；没有 m3u8 就给第一个 http 地址）
#
# 实现说明：解析用 shell 内建字符串操作，不再每条记录 fork 四趟 sed/grep。
# 实测「三体」从 4 分钟还没跑完 → 十几秒。
set -u

EP="
https://caiji.dyttzyapi.com/api.php/provide/vod/
https://cj.lziapi.com/api.php/provide/vod/
https://cj.ffzyapi.com/api.php/provide/vod/
https://api.ffzyapi.com/api.php/provide/vod/
https://api.apibdzy.com/api.php/provide/vod/
https://cj.rycjapi.com/api.php/provide/vod/
https://api.wujinapi.com/api.php/provide/vod/
https://api.zuidapi.com/api.php/provide/vod/
https://api.ukuapi88.com/api.php/provide/vod/
https://api.hongniuzy2.com/api.php/provide/vod/
https://api.tiankongapi.com/api.php/provide/vod/
https://collect.wolongzyw.com/api.php/provide/vod/
https://json.heimuer.xyz/api.php/provide/vod/
https://api.1080zyku.com/inc/api.php
"

EP_TIMEOUT="${EP_TIMEOUT:-15}"
LIMIT=8
WIDE=0
PROBE=0
KW=""

for a in "$@"; do
  case "$a" in
    --宽) WIDE=1 ;;
    --满) LIMIT=20 ;;
    --探活) PROBE=1 ;;
    --超时=*) EP_TIMEOUT=${a#--超时=} ;;
    -*) : ;;
    *) [ -z "$KW" ] && KW="$a" ;;
  esac
done

TMPD=$(mktemp -d 2>/dev/null) || TMPD="${TMPDIR:-.}/caiji.$$"
mkdir -p "$TMPD" 2>/dev/null || { TMPD="${TMPDIR:-.}/caiji.$$"; mkdir -p "$TMPD"; }
cleanup() { rm -rf "$TMPD" 2>/dev/null; }
trap cleanup EXIT INT TERM

site_of() { printf '%s' "$1" | sed 's#https://##;s#/api.*##;s#/inc.*##'; }

fetch_one() {
  _ep="$1"; _out="$2"
  curl -sS --max-time "$EP_TIMEOUT" --compressed \
       -A "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36" \
       -G --data "ac=detail" --data-urlencode "wd=$KW" "$_ep" 2>/dev/null > "$_out"
}

# ---------- 探活 ----------
if [ "$PROBE" = "1" ]; then
  KW="三体"
  i=0
  for ep in $EP; do i=$((i+1)); ( fetch_one "$ep" "$TMPD/$i.json" ) & done
  wait
  i=0; ALIVE=0; DEAD=0
  for ep in $EP; do
    i=$((i+1))
    SIZE=$(wc -c < "$TMPD/$i.json" 2>/dev/null | tr -d ' ')
    [ -z "$SIZE" ] && SIZE=0
    if [ "$SIZE" -gt 200 ] && grep -q '"list"' "$TMPD/$i.json" 2>/dev/null; then
      printf '活  %-40s %s B\n' "$(site_of "$ep")" "$SIZE"; ALIVE=$((ALIVE+1))
    else
      printf '死  %-40s %s B\n' "$(site_of "$ep")" "$SIZE"; DEAD=$((DEAD+1))
    fi
  done
  echo "—— 接口池 $((ALIVE+DEAD)) 个，活 $ALIVE / 死 ${DEAD}（死的不代表永久废，域名常换）"
  exit 0
fi

[ -z "$KW" ] && { echo '用法：sh scripts/collect.sh "片名" [--宽] [--满] [--探活] [--超时=N]'; exit 1; }

# ---------- 搜索 ----------
i=0
for ep in $EP; do i=$((i+1)); ( fetch_one "$ep" "$TMPD/$i.json" ) & done
wait

: > "$TMPD/out.tsv"
i=0
for ep in $EP; do
  i=$((i+1))
  f="$TMPD/$i.json"
  [ -s "$f" ] || continue
  SITE=$(site_of "$ep")
  # 一次 sed 搞定：切条目 + 还原 JSON 的 \/ 转义（放在这里就不用在循环里逐条 fork）
  { tr -d '\n\r' < "$f"; echo; } | sed 's#\\/#/#g; s/},{/}\n{/g' > "$TMPD/$i.lines"

  if [ "$WIDE" = "0" ]; then
    grep -F -e "$KW" "$TMPD/$i.lines" > "$TMPD/$i.hit" 2>/dev/null
  else
    cp "$TMPD/$i.lines" "$TMPD/$i.hit"
  fi
  n=0
  while IFS= read -r line; do
    [ "$n" -ge "$LIMIT" ] && break
    # 抽 vod_name（纯内建，不 fork）
    case "$line" in
      *'"vod_name":"'*) : ;;
      *) continue ;;
    esac
    _t=${line#*'"vod_name":"'}
    NAME=${_t%%\"*}
    [ -n "$NAME" ] || continue
    if [ "$WIDE" = "0" ]; then
      case "$NAME" in *"$KW"*) : ;; *) continue ;; esac
    fi
    # 抠第一个 .m3u8 地址（含其后的 query），没有再退回第一个 http 地址
    LINK=""
    case "$line" in
      *http*'.m3u8'*)
        _h=${line%%'.m3u8'*}          # 第一个 .m3u8 之前
        _u=${_h##*http}               # 取最后一个 http 之后的部分
        _r=${line#*'.m3u8'}           # .m3u8 之后
        case "$_r" in *'"'*) _r=${_r%%\"*} ;; esac
        case "$_r" in *'#'*) _r=${_r%%#*} ;; esac
        case "$_r" in *'\'*) _r=${_r%%\\*} ;; esac
        LINK="http${_u}.m3u8${_r}"
        ;;
      *http*)
        _t=${line#*http}
        _t=${_t%%\"*}
        case "$_t" in *'#'*) _t=${_t%%#*} ;; esac
        LINK="http${_t}"
        ;;
    esac
    [ -n "$LINK" ] || continue
    printf '%s\t%s\t%s\n' "$SITE" "$NAME" "$LINK" >> "$TMPD/out.tsv"
    n=$((n+1))
  done < "$TMPD/$i.hit"
done

if [ -s "$TMPD/out.tsv" ]; then
  sort -u "$TMPD/out.tsv" > "$TMPD/out2.tsv" 2>/dev/null || cp "$TMPD/out.tsv" "$TMPD/out2.tsv"
  ROWS=$(wc -l < "$TMPD/out2.tsv" | tr -d ' ')
  SITES=$(cut -f1 "$TMPD/out2.tsv" | sort -u | wc -l | tr -d ' ')
  echo "== 「${KW}」采集接口命中 $ROWS 条（来自 $SITES 个站，每站最多 $LIMIT 条）=="
  cat "$TMPD/out2.tsv"
  echo
  echo "—— 下一步：把直链粘进「找资源」页的「播放 / 下载直链」直接看；"
  echo "   要下载成 mp4 用 ffmpeg，或直接丢给 VLC / nPlayer / MX 播放。"
else
  echo "== 「${KW}」采集接口 0 条 =="
  echo "先确认接口今天活着：sh scripts/collect.sh --探活"
  echo "活着但还是 0 条，说明这几个站没有该片；换正式片名再试，或加 --宽 看未过滤结果。"
fi

# 退出码：0 有结果 / 3 零结果（接口通但没货）/ 1 全挂（14 个接口都没返回数据）
if [ -s "$TMPD/out.tsv" ]; then exit 0; fi
if grep -q '"list"' "$TMPD"/*.json 2>/dev/null; then exit 3; fi
exit 1
