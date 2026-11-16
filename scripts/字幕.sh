#!/system/bin/sh
# 字幕 —— 从 subhd 取中文字幕并转成标准 SRT（纯 shell：curl/sed/grep/tr/sort，无 jq/python）
# 用法：
#   sh scripts/字幕.sh "真实 2017"              # 搜索，列出条目页里的字幕候选（带 sid）
#   sh scripts/字幕.sh "真实 2017" --取 1       # 取第 1 条的正文，落一份 .srt
#   sh scripts/字幕.sh --预览 rvMUEC            # 直接用 sid 取
#   sh scripts/字幕.sh "真实 2017" --目录 /sdcard/Download --取 2
# 说明：
#   · 站点结构 2026-11 实测为「搜索 → /d/<id> 条目页 → /a/<sid> 字幕页 → preview 接口」
#     （旧文档写的是搜索页直接出 /a/<sid>，与当前结构不符，这里按实际结构走两跳）
#   · subhd 从国内直连偏慢（单请求 9–15 秒），偶发静默超时；脚本对每个请求设超时并明确报错
#   · 缺 ffprobe：--视频 <文件> 的时间轴对齐做不到，会明说跳过
#   · --到115 不做（手机侧没有 115 通道）
set -u

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
DOMAINS="subhd.tv subhd.me subhd.one"
KW=""
PICK=""
SID=""
DIR="."
MAXPAGE=3
TM=30

while [ $# -gt 0 ]; do
  case "$1" in
    --取) shift; PICK="${1:-1}" ;;
    --预览) shift; SID="${1:-}" ;;
    --目录) shift; DIR="${1:-.}" ;;
    --页面) shift; MAXPAGE="${1:-3}" ;;
    --超时=*) TM=${1#--超时=} ;;
    --到115) echo "· 手机侧没有 115 通道，--到115 已忽略" >&2 ;;
    --视频) shift; echo "· 缺 ffprobe，跳过时间轴对齐（--视频 ${1:-}）" >&2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    -*) : ;;
    *) [ -z "$KW" ] && KW="$1" ;;
  esac
  shift
done

[ -n "$SID" ] || [ -n "$KW" ] || { sed -n '2,16p' "$0"; exit 1; }

TMP=$(mktemp -d 2>/dev/null) || TMP="${TMPDIR:-.}/sub.$$"
mkdir -p "$TMP" 2>/dev/null || { TMP="${TMPDIR:-.}/sub.$$"; mkdir -p "$TMP"; }
cleanup() { rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT INT TERM
TAB=$(printf '\t')

# ---- 百分号编码（关键字要进 path，curl 不会替我们编码路径）----
urlenc() {
  _s="$1"; _o=""
  for _h in $(printf '%s' "$_s" | od -An -v -tx1); do
    case "$_h" in
      3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]|2d|2e|5f|7e) _o="$_o$(printf "\\x$_h")" ;;
      *) _o="$_o%$_h" ;;
    esac
  done
  printf '%s' "$_o"
}

# ---- 选一个能通的域名 ----
BASE=""
for d in $DOMAINS; do
  code=$(curl -sS -m "$TM" -o /dev/null -A "$UA" -H "accept-language: zh-CN,zh;q=0.9" \
         -w '%{http_code}' "https://$d/" 2>/dev/null)
  case "$code" in 2*) BASE="https://$d"; break ;; esac
done
[ -n "$BASE" ] || { echo "✗ subhd 三个域名都不通（可能要代理）"; exit 2; }
echo "· 用 $BASE"
BASE_HOST=${BASE#https://}
HOSTS="$BASE_HOST"
for d in $DOMAINS; do [ "$d" = "$BASE_HOST" ] || HOSTS="$HOSTS $d"; done

# ---- 搜索 → 条目页 → 字幕 sid ----
if [ -z "$SID" ]; then
  enc=$(urlenc "$KW")
  for h in $HOSTS; do
    curl -sS -m "$TM" --compressed -A "$UA" -H "accept-language: zh-CN,zh;q=0.9" \
         -H "referer: https://$h/" "https://$h/search/$enc" -o "$TMP/s.html" 2>/dev/null || true
    [ -s "$TMP/s.html" ] && break
    echo "· https://$h 搜索页超时，换下一个域…"
  done
  if [ ! -s "$TMP/s.html" ]; then echo "✗ 三个域的搜索页都没拿到（subhd 直连不稳，稍后重试或挂代理）"; exit 3; fi

  # 结果卡片：每个 <a href="/d/ID"> 前面通常带 img alt="片名"，按卡片切，避免抓到推荐位
  ONE=$(tr -d '\n\r' < "$TMP/s.html")
  A="${ONE#*的搜索结果}"
  : > "$TMP/cards2.txt"
  printf '%s' "$A" | sed 's#href="/d/#\
href="/d/#g' | grep 'href="/d/' | head -n 10 > "$TMP/cards.txt"
  : > "$TMP/d.txt"
  KW2=$(printf '%s' "$KW" | sed 's/[ 0-9]*$//')
  while IFS= read -r c; do
    id=$(printf '%s' "$c" | grep -oE '/d/[0-9]+' | head -1)
    alt=$(printf '%s' "$c" | grep -oE 'alt="[^"]*"' | head -1 | sed 's/alt="//;s/"$//')
    [ -n "$id" ] || continue
    printf '%s\t%s\n' "$id" "$alt" >> "$TMP/cards2.txt"
    case "$alt" in
      *"$KW"*)  printf '%s\n' "$id" >> "$TMP/d.txt" ;;
      *"$KW2"*) [ -n "$KW2" ] && printf '%s\n' "$id" >> "$TMP/d.txt" ;;
    esac
  done < "$TMP/cards.txt"
  if [ ! -s "$TMP/d.txt" ]; then
    echo "✗ 搜索结果里没有片名含「${KW}」的条目。抓到的候选："
    cut -f1,2 "$TMP/cards2.txt" | head -n 8 | sed 's/^/  /'
    echo "  → 换个片名重试，或用 --预览 <sid> 直取（sid 在条目页 /a/ 链接里）"
    exit 4
  fi
  head -n "$MAXPAGE" "$TMP/d.txt" > "$TMP/d2.txt" && mv "$TMP/d2.txt" "$TMP/d.txt"
  if [ ! -s "$TMP/d.txt" ]; then
    echo "✗ 搜索页里没有条目链接（可能关键词没结果，或被风控）"
    exit 4
  fi

  : > "$TMP/items.tsv"
  while IFS= read -r dpath; do
    [ -n "$dpath" ] || continue
    sleep 1
    curl -sS -m "$TM" --compressed -A "$UA" -H "accept-language: zh-CN,zh;q=0.9" \
         -H "referer: $BASE/search/$enc" "$BASE$dpath" -o "$TMP/d.html" 2>/dev/null || true
    [ -s "$TMP/d.html" ] || continue
    grep -oE 'href="/a/[0-9A-Za-z]{4,12}"[^>]*>[^<]{1,80}' "$TMP/d.html" \
      | sed 's#href="/a/##; s/"[^>]*>/\t/' >> "$TMP/items.tsv"
  done < "$TMP/d.txt"

  if [ ! -s "$TMP/items.tsv" ]; then
    echo "✗ 条目页里没找到 /a/<sid> 字幕项（页面结构可能又变了）"
    exit 5
  fi

  echo "序号  sid              标题"
  n=0
  while IFS="$TAB" read -r sid title; do
    n=$((n+1))
    printf '%-5s %-16s %s\n' "$n" "$sid" "$title"
  done < "$TMP/items.tsv"
  echo
  echo "共 $n 条候选。用 --取 N 下载其中一条，或 --预览 <sid> 直取。"
  [ -n "$PICK" ] || exit 0
  SID=$(sed -n "${PICK}p" "$TMP/items.tsv" | cut -f1)
  [ -n "$SID" ] || { echo "✗ --取 $PICK 超出范围"; exit 6; }
fi

# ---- 取正文（哪个域先成功就用哪个）----
BASE_HOST=${BASE#https://}
HOSTS="$BASE_HOST"
for d in $DOMAINS; do [ "$d" = "$BASE_HOST" ] || HOSTS="$HOSTS $d"; done

GOT=""
for h in $HOSTS; do
  echo "· 取 https://$h/a/$SID 的正文…"
  curl -sS -m "$TM" --compressed -A "$UA" -H "accept-language: zh-CN,zh;q=0.9" \
       -H "referer: https://$h/a/$SID" "https://$h/api/sub/preview/$SID" -o "$TMP/p.json" 2>/dev/null || true
  if [ -s "$TMP/p.json" ] && grep -q '"success":true' "$TMP/p.json"; then GOT=$h; break; fi
done
if [ -z "$GOT" ]; then
  echo "✗ preview 三个域都没拿到（subhd 直连偏慢，可稍后重试或挂代理）"
  exit 7
fi
case "$(head -c 1 "$TMP/p.json")" in
  '{') : ;;
  *) echo "✗ preview 返回异常（前 80 字节）：$(head -c 80 "$TMP/p.json")"; exit 8 ;;
esac
if ! grep -q '"success":true' "$TMP/p.json"; then
  echo "✗ 返回 success!=true，通常是被拦/要登录：$(head -c 120 "$TMP/p.json")"
  exit 9
fi

# 正文可能在 file.content / data.file.content / data.content，逐个兜
sed -n 's/.*"content":"//p' "$TMP/p.json" > "$TMP/raw.txt"
if [ ! -s "$TMP/raw.txt" ]; then echo "✗ 找不到 content 字段"; exit 10; fi
# 去掉结尾的 "}} 或 "} 等收尾引号，再还原转义
sed 's/"}\{1,2\}$//' "$TMP/raw.txt" | sed 's/\\n/\
/g; s/\\"/"/g; s/\\t/	/g; s/\\r//g' > "$TMP/content.txt"

# ---- 转 SRT ----
NAME=$(sed -n 's/.*"filename":"\([^"]*\)".*/\1/p' "$TMP/p.json" | head -1)
[ -n "$NAME" ] || NAME="$SID.srt"
case "$NAME" in *.srt) : ;; *) NAME="$NAME.srt" ;; esac
mkdir -p "$DIR" 2>/dev/null
OUT="$DIR/$(printf '%s' "$NAME" | sed "s#[/#]#_#g")"

# 已经是 SRT？
head -1 "$TMP/content.txt" | grep -qE '^[0-9]+$' && grep -q -- '-->' "$TMP/content.txt" && {
  cp "$TMP/content.txt" "$OUT"
  CNT=$(grep -c -- '-->' "$OUT")
  LAST=$(grep -- '-->' "$OUT" | tail -1 | cut -d'>' -f2 | sed 's/^ *//;s/ .*//')
  echo "✓ 原样保存（本来就是 SRT）：$OUT"
  echo "  条数 $CNT · 末条 $LAST"
  exit 0
}

t2ms() {
  _t="${1#\[}"; _t="${_t%\]}"
  case "$_t" in
    *.*) _ms="${_t#*.}"; _t="${_t%%.*}" ;;
    *,*) _ms="${_t#*,}"; _t="${_t%%,*}" ;;
    *) _ms=0 ;;
  esac
  case "${#_ms}" in 1) _ms="${_ms}00" ;; 2) _ms="${_ms}0" ;; esac
  _h="${_t%%:*}"; _r="${_t#*:}"; _m="${_r%%:*}"; _s="${_r#*:}"
  [ "$_r" = "$_t" ] && { _h=0; _m="$_t"; _s=0; }
  echo $(( 10#${_h:-0} * 3600000 + 10#${_m:-0} * 60000 + 10#${_s:-0} * 1000 + 10#${_ms:-0} ))
}

fmt_ms() {
  _v="$1"
  _h=$(( _v / 3600000 )); _v=$(( _v % 3600000 ))
  _m=$(( _v / 60000 ));   _v=$(( _v % 60000 ))
  _s=$(( _v / 1000 ));    _ms=$(( _v % 1000 ))
  printf '%02d:%02d:%02d,%03d' "$_h" "$_m" "$_s" "$_ms"
}

# 把正文切成「起始毫秒 + 台词」的块，逐块按规则算终点
IDX=0
P_START=""; P_TEXT=""
C_START=""; C_TEXT=""; IN=0
LAST_START=0; LAST_END=0

emit() { # $1=start $2=end $3=text
  [ -n "$3" ] || return 0            # 没有台词的块（比如片尾空的 [时间] 行）不输出
  IDX=$((IDX+1))
  printf '%d\n%s --> %s\n%s\n\n' "$IDX" "$(fmt_ms "$1")" "$(fmt_ms "$2")" "$3" >> "$OUT"
  LAST_START=$1; LAST_END=$2
}

flush_block() { # 用当前块（C_*）的起点去关上一块（P_*）
  [ -n "$P_START" ] || return 0
  e=$(( C_START - 150 ))
  [ "$e" -gt $(( P_START + 7000 )) ] && e=$(( P_START + 7000 ))
  [ "$e" -le $(( P_START + 400 )) ] && e=$(( P_START + 1200 ))
  emit "$P_START" "$e" "$P_TEXT"
}

: > "$OUT"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    \[*\]*)
      # 收掉上一块
      if [ "$IN" = "1" ]; then flush_block; P_START="$C_START"; P_TEXT="$C_TEXT"; fi
      C_START=$(t2ms "$line"); C_TEXT=""; IN=1 ;;
    '')
      if [ "$IN" = "1" ] && [ -n "$C_TEXT" ]; then
        flush_block; P_START="$C_START"; P_TEXT="$C_TEXT"; C_START=""; C_TEXT=""; IN=0
      fi ;;
    *)
      [ "$IN" = "1" ] || continue
      if [ -z "$C_TEXT" ]; then C_TEXT="$line"; else C_TEXT="$C_TEXT
$line"; fi ;;
  esac
done < "$TMP/content.txt"

if [ "$IN" = "1" ] && [ -n "$C_START" ]; then
  flush_block; P_START="$C_START"; P_TEXT="$C_TEXT"
fi
# 最后一块：起点 +3 秒
[ -n "$P_START" ] && emit "$P_START" $(( P_START + 3000 )) "$P_TEXT"

CNT=$IDX
echo
echo "✓ 完成：$OUT"
echo "  条数 $CNT · 末条 $(fmt_ms "$LAST_END")"
[ -n "$KW" ] && echo "  关键词「${KW}」· sid $SID"
