#!/bin/sh
# m3u8取流 —— 把 m3u8 拉成本地文件（纯 shell：只需 curl/grep/sed/tr/sort）
#
# 手机端没有 ffmpeg，所以这里只拼成 .ts（绝大多数播放器/VLC/nPlayer 能直接播）。
# 想封成 mp4，把 .ts 拷到电脑上用 ffmpeg：ffmpeg -i x.ts -c copy -bsf:a aac_adtstoasc x.mp4
#
# 用法：
#   sh m3u8取流.sh "https://…/index.m3u8" --名 钥匙2026
#   sh m3u8取流.sh "https://…/index.m3u8" --片 8          # 只取前 8 片（先验能不能下、画质如何）
#   sh m3u8取流.sh "https://…/index.m3u8" --并发 4 --目录 /sdcard/Download
#   sh m3u8取流.sh ./local.m3u8 --名 test               # 也支持本地 m3u8
#
# 会自动处理：master 多码率（挑 BANDWIDTH 最大的一档）、相对路径、EXT-X-MAP 初始化段。
# 拒绝处理：AES-128 加密（手机端没有 openssl，解不了，直接报错退出）。
# 注意：变量名一律 ASCII —— bash/mksh 都不认中文变量名。

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
URL=""
NAME=""
LIMIT=0
CONC=4
DIR=""
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --名|--name)   NAME="$2"; shift 2 ;;
    --片|--limit)  LIMIT="$2"; shift 2 ;;
    --并发|--conc) CONC="$2"; shift 2 ;;
    --目录|--dir)  DIR="$2"; shift 2 ;;
    --留片|--keep) KEEP=1; shift ;;
    -h|--help)     sed -n '2,17p' "$0"; exit 0 ;;
    *)             URL="$1"; shift ;;
  esac
done

if [ -z "$URL" ]; then
  echo "用法：sh m3u8取流.sh <m3u8地址或本地文件> [--名 名字] [--片 N] [--并发 4] [--目录 目录] [--留片]"
  exit 2
fi

TMP=$(mktemp -d 2>/dev/null || echo "/tmp/m3u8.$$")
mkdir -p "$TMP" 2>/dev/null
trap '[ "$KEEP" = "1" ] || rm -rf "$TMP"' EXIT

fetch() {
  case "$1" in
    http*) curl -s --max-time 40 -A "$UA" -H "referer: $2" "$1" ;;
    *)     cat "$1" ;;
  esac
}

# 拼相对地址：$1=基地址(带目录)，$2=相对路径
joinurl() {
  _b="$1"; _r="$2"
  case "$_r" in
    http*) printf '%s' "$_r"; return ;;
    /*)    _host=$(printf '%s' "$_b" | sed 's#^\(https\?://[^/]*\).*#\1#'); printf '%s%s' "$_host" "$_r"; return ;;
  esac
  printf '%s%s' "$_b" "$_r"
}

echo "→ 取播放列表：$URL"
fetch "$URL" "$URL" > "$TMP/index.m3u8"
if [ ! -s "$TMP/index.m3u8" ]; then
  echo "✗ 播放列表取不到（地址失效 / 需要 referer / 网络不通）"
  exit 1
fi

# --- master 多码率：挑 BANDWIDTH 最大的一档 ---
if grep -q 'EXT-X-STREAM-INF' "$TMP/index.m3u8"; then
  echo "· 这是 master（多码率），挑最高码率那一档"
  : > "$TMP/variants.txt"
  ln=0
  while IFS= read -r line; do
    ln=$((ln+1))
    case "$line" in
      *BANDWIDTH=*)
        bw=$(printf '%s' "$line" | sed 's/.*BANDWIDTH=\([0-9]*\).*/\1/')
        res=$(printf '%s' "$line" | sed -n 's/.*RESOLUTION=\([0-9x]*\).*/\1/p')
        n=$((ln+1))
        uri=""
        while : ; do
          cand=$(sed -n "${n}p" "$TMP/index.m3u8")
          [ -z "$cand" ] && break
          case "$cand" in \#*) n=$((n+1)); continue ;; esac
          uri="$cand"; break
        done
        [ -n "$uri" ] && printf '%s%s%s\n' "$bw" "$(printf '\t')" "$uri" >> "$TMP/variants.txt"
        ;;
    esac
  done < "$TMP/index.m3u8"
  if [ -s "$TMP/variants.txt" ]; then
    best=$(sort -k1,1 -n -r "$TMP/variants.txt" | head -n 1)
    bw=$(printf '%s' "$best" | cut -f1)
    uri=$(printf '%s' "$best" | cut -f2)
    base=$(printf '%s' "$URL" | sed 's#/[^/]*$#/#')
    SUB=$(joinurl "$base" "$uri")
    echo "· 选中 BANDWIDTH=$bw → $SUB"
    URL="$SUB"
    fetch "$URL" "$URL" > "$TMP/media.m3u8"
  else
    echo "✗ master 里没解析出子列表"
    exit 1
  fi
else
  cp "$TMP/index.m3u8" "$TMP/media.m3u8"
fi

# --- 加密检查 ---
if grep -q 'EXT-X-KEY' "$TMP/media.m3u8"; then
  if grep -q 'METHOD=AES-128' "$TMP/media.m3u8"; then
    echo "✗ 这个流是 AES-128 加密的，手机端没有 openssl，解不了。换未加密的直链，或在电脑上处理。"
    exit 3
  fi
fi

BASE=$(printf '%s' "$URL" | sed 's#/[^/]*$#/#')
TOTAL=$(grep -vc '^#' "$TMP/media.m3u8" 2>/dev/null | tr -d ' ')
grep -q 'EXT-X-ENDLIST' "$TMP/media.m3u8" && ENDLIST="有" || ENDLIST="无（直播/未完结）"

if [ -z "$NAME" ]; then
  NAME=$(printf '%s' "$URL" | sed 's#.*/\([^/]*\)/.*#\1#')
  [ -z "$NAME" ] && NAME="m3u8_$(date +%s)"
fi
[ -n "$DIR" ] && mkdir -p "$DIR" && WORK="$DIR" || WORK="$TMP"
# 只处理 Windows 盘符写法（D:\x → /d/x）；Android 的 /sdcard/... 原样保留
case "$WORK" in
  [A-Za-z]:*) WORK=$(printf '%s' "$WORK" | sed 's#\\#/#g' | sed 's#^\([A-Za-z]\):#/\1#') ;;
  *)          WORK=$(printf '%s' "$WORK" | sed 's#\\#/#g') ;;
esac

echo "· 分片总数 $TOTAL · ENDLIST=$ENDLIST · 工作目录 $WORK"

# --- EXT-X-MAP 初始化段（fMP4）---
INIT=""
mapuri=$(sed -n 's/.*EXT-X-MAP:URI="\([^"]*\)".*/\1/p' "$TMP/media.m3u8" | head -n 1)
if [ -n "$mapuri" ]; then
  mfull=$(joinurl "$BASE" "$mapuri")
  echo "· 有初始化段（fMP4），先下它"
  curl -s --max-time 60 -A "$UA" -H "referer: $BASE" -o "$WORK/seg_00000.init" "$mfull" || true
  INIT="$WORK/seg_00000.init"
fi

# --- 下载分片（分批并发）---
: > "$TMP/segs.txt"
n=0
while IFS= read -r line; do
  case "$line" in \#*|"") continue ;; esac
  n=$((n+1))
  [ "$LIMIT" -gt 0 ] && [ "$n" -gt "$LIMIT" ] && break
  full=$(joinurl "$BASE" "$line")
  printf '%s%s%s\n' "$n" "$(printf '\t')" "$full" >> "$TMP/segs.txt"
done < "$TMP/media.m3u8"

CNT=$(wc -l < "$TMP/segs.txt" | tr -d ' ')
echo "· 准备下载 $CNT 片（并发 $CONC）"

done_n=0
while IFS="$(printf '\t')" read -r idx full; do
  done_n=$((done_n+1))
  out=$(printf '%s/seg_%05d.ts' "$WORK" "$idx")
  (
    ok=0
    try=1
    while [ "$try" -le 3 ]; do
      curl -s --max-time 90 -A "$UA" -H "referer: $BASE" -o "$out" "$full" && [ -s "$out" ] && ok=1 && break
      try=$((try+1))
      sleep 1
    done
    [ "$ok" = "0" ] && printf '%s\n' "$idx" >> "$TMP/failed.txt"
  ) &
  if [ $((done_n % CONC)) -eq 0 ]; then wait; fi
  if [ $((done_n % 50)) -eq 0 ]; then echo "  · 已提交 $done_n/$CNT"; fi
done < "$TMP/segs.txt"
wait

if [ -s "$TMP/failed.txt" ]; then
  echo "⚠ 有 $(wc -l < "$TMP/failed.txt" | tr -d ' ') 片重试 3 次仍失败（编号见下），拼出来的文件可能有跳帧："
  head -n 10 "$TMP/failed.txt" | tr '\n' ' '; echo
fi

# --- 拼接（按分片编号顺序，不依赖 ls 通配）---
OUT="$WORK/$NAME.ts"
: > "$OUT"
[ -n "$INIT" ] && [ -s "$INIT" ] && cat "$INIT" >> "$OUT"
got=0
while IFS="$(printf '\t')" read -r idx full; do
  f=$(printf '%s/seg_%05d.ts' "$WORK" "$idx")
  if [ -s "$f" ]; then cat "$f" >> "$OUT"; got=$((got+1)); fi
done < "$TMP/segs.txt"

SZ=$(wc -c < "$OUT" | tr -d ' ')
MB=$((SZ / 1024 / 1024))
echo
echo "✓ 完成：$OUT"
echo "  分片 $got 个 · 合计 ${SZ} 字节（约 ${MB} MB）"
if [ "$LIMIT" -gt 0 ]; then
  echo "  注意：这是 --片 $LIMIT 的试取，不是全片。去掉 --片 重跑才是完整版。"
fi
echo "  手机自带播放器认 .ts；要 mp4 就拷到电脑：ffmpeg -i \"$NAME.ts\" -c copy -bsf:a aac_adtstoasc \"$NAME.mp4\""
if [ "$KEEP" != "1" ]; then
  rm -f "$WORK"/seg_*.ts 2>/dev/null
  echo "  （临时分片已清理；加 --留片 可保留）"
fi
