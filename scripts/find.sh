#!/system/bin/sh
# 资源搜索（精简版）· 无 Node 版 —— curl + shell 内建实现，Android / Linux / macOS 通用
# 用法：sh find.sh "关键词" [选项]
#   --只链接              只输出链接，一行一条
#   --磁力                只查磁力，跳过网盘（快）
#   --json                机器可读
#   --类型 quark,baidu    只查指定网盘（默认全部 9 类）
#   --条数 30             磁力最多列几条（默认 20）
#   --网盘条数 10         每类网盘最多列几条（默认 10）
#   --测                  自检各源连通性
# 说明：纯 shell 实现，Android mksh / Linux bash 均可。

set -u
DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || DIR=.
RULES="$DIR/rules.tsv"
UA="Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
INST="${RS_INSTANCE:-https://so.252035.xyz}"
ALL_TYPES="quark,baidu,aliyun,uc,115,tianyi,xunlei,123,pikpak"
NL=$'\n'
AMP='&'

KW=""; CTYPE=""; MODE="list"; MAG_ONLY=0; TOP=20; PAN_TOP=10; SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --磁力) MAG_ONLY=1 ;;
    --只链接) MODE="links" ;;
    --json) MODE="json" ;;
    --测) SELFTEST=1 ;;
    --类型) shift; CTYPE=$(printf '%s' "${1:-}" | tr -d ' ') ;;
    --条数) shift; TOP="${1:-20}" ;;
    --网盘条数) shift; PAN_TOP="${1:-10}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "未知参数：$1"; exit 2 ;;
    *) KW="$1" ;;
  esac
  shift
done

TMP=$(mktemp -d 2>/dev/null) || TMP=""
[ -n "$TMP" ] && [ -d "$TMP" ] || { TMP="${TMPDIR:-.}/rs.$$"; mkdir -p "$TMP"; }
trap 'rm -rf "$TMP"' EXIT INT TERM

# ── 小工具（尽量用 shell 内建，避免每条记录 fork 一堆 sed）────────
val() { # $1=行 $2=键 → $OUT（字符串字段）
  case "$1" in
    *"\"$2\":\""*) CV=${1#*"\"$2\":\""}; OUT=${CV%%\"*} ;;
    *) OUT="" ;;
  esac
}
nval() { # $1=行 $2=键 → $OUT（数字字段）
  case "$1" in
    *"\"$2\":"*) CV=${1#*"\"$2\":"} ;;
    *) OUT=""; return 0 ;;
  esac
  case "$CV" in
    [0-9]*) CN=${CV%%[!0-9]*}; OUT=${CN:-0} ;;
    *) OUT="" ;;
  esac
}
unesc() { # $1 → $OUT（去掉 JSON 转义）
  OUT=${1//\\u0026/$AMP}
  OUT=${OUT//\\u003d/=}
  OUT=${OUT//\\u002F/\/}
  OUT=$(printf '%s' "$OUT" | tr -d '\134')
}
jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# 相关度：标题要真含关键词（中文按整串，英文按每个词都在）
KWLOW=""
rel_ok() {
  [ -n "$KWLOW" ] || KWLOW=$(printf '%s' "$KW" | tr 'A-Z' 'a-z')
  _t=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$_t" in *"$KWLOW"*) return 0 ;; esac
  _n=0
  for _w in $KWLOW; do
    _n=$((_n + 1))
    case "$_t" in *"$_w"*) : ;; *) return 1 ;; esac
  done
  [ "$_n" -gt 1 ] && return 0
  return 1
}
hsize() {
  b=${1:-0}
  case "$b" in ''|*[!0-9]*) b=0 ;; esac
  n=${#b}
  if [ "$n" -le 9 ]; then
    v=$b
    if [ "$v" -ge 1048576 ]; then
      printf '%s.%sM' $((v / 1048576)) $(( (v % 1048576) * 10 / 1048576 ))
    elif [ "$v" -ge 1024 ]; then
      printf '%s.%sK' $((v / 1024)) $(( (v % 1024) * 10 / 1024 ))
    else
      printf '%sB' "$v"
    fi
  else
    # mksh 的算术是 32 位，超过 2G 的字节数直接算会溢出，这里截前 9 位再除
    v=${b:0:9}
    case $((n - 9)) in
      1) d=10737418 ;; 2) d=1073741 ;; 3) d=107374 ;; *) d=10737 ;;
    esac
    gx=$((v / d))
    printf '%s.%sG' $((gx / 10)) $((gx % 10))
  fi
}
shorten_magnet() {
  case "$1" in
    magnet:*btih:*)
      h=${1#*btih:}; h=${h%%&*}
      printf 'magnet:?xt=urn:btih:%s' "$h" ;;
    *) printf '%s' "$1" ;;
  esac
}
fmt_time() {
  s=${1:-}
  case "$s" in
    ''|0001-01-01*) printf '' ;;
    *[!0-9]*) printf '%s' "${s%%T*}" ;;
    *) date -d "@$s" +%Y-%m-%d 2>/dev/null || printf '' ;;
  esac
}
type_name() {
  case "$1" in
    quark) printf '夸克' ;; baidu) printf '百度' ;; aliyun) printf '阿里云盘' ;;
    uc) printf 'UC' ;; 115) printf '115' ;; tianyi) printf '天翼' ;;
    xunlei) printf '迅雷' ;; 123) printf '123云盘' ;; pikpak) printf 'PikPak' ;;
    magnet) printf "磁力" ;; others) printf "其他" ;; *) printf "%s" "$1" ;;
  esac
}

# ── 网盘：PanSou 实例 ──────────────────────────────────────
# 关键实测（2026-11）：不传 cloud_types 结果最全
#   · 必须带完整浏览器 UA + Referer，否则 403
#   · 不传 cloud_types 结果最多（三体：传 10 类 21 条 vs 不传 209 条），且顺带带回 magnet/ed2k
#   · 请求可能要 40–60 秒，失败时退回「按类型并发」兜底
pan_fetch() {
  if [ -n "${1:-}" ]; then
    curl -sS -m 60 -G "$INST/api/search" \
      --data-urlencode "kw=$KW" \
      --data-urlencode "res=merge" \
      --data-urlencode "cloud_types=$1" \
      -H "User-Agent: $UA" \
      -H "Referer: $INST/" \
      -H "Accept: application/json" \
      -H "Accept-Language: zh-CN,zh;q=0.9" 2>/dev/null
  else
    curl -sS -m 60 -G "$INST/api/search" \
      --data-urlencode "kw=$KW" \
      --data-urlencode "res=merge" \
      -H "User-Agent: $UA" \
      -H "Referer: $INST/" \
      -H "Accept: application/json" \
      -H "Accept-Language: zh-CN,zh;q=0.9" 2>/dev/null
  fi
}

# 合并结果：按 merged_by_type 里出现的类型动态打标记，再逐条抽字段
pan_parse_merge() { # $1=json 文件 → $TMP/pan.tsv
  sed "s/},{/}\n{/g" "$1" > "$TMP/merge.lines"
  for t in $(grep -o '"[a-z0-9][a-z0-9_]*":\[{' "$1" | sed 's/":\[{$//; s/^"//' | sort -u); do
    sed "s/\"$t\":\[/${NL}@$t@/g" "$TMP/merge.lines" > "$TMP/merge.lines2" && mv "$TMP/merge.lines2" "$TMP/merge.lines"
  done
  : > "$TMP/pan.tsv"
  cur=""
  while IFS= read -r ln; do
    case "$ln" in
      @*) tmp=${ln#@}; cur=${tmp%%@*}; ln=${tmp#*@} ;;
    esac
    case "$ln" in \{*) : ;; *) continue ;; esac
    val "$ln" url; [ -n "$OUT" ] || continue; unesc "$OUT"; u=$OUT
    val "$ln" note; unesc "$OUT"; n=$OUT
    val "$ln" datetime; d=$OUT
    val "$ln" source; s=$OUT
    val "$ln" password; p=$OUT
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cur" "$u" "$n" "$d" "$s" "$p" >> "$TMP/pan.tsv"
  done < "$TMP/merge.lines"
}

# 兜底：按类型并发查（结果少，但某一类挂掉不影响别的类）
pan_one() { # $1=类型
  : > "$TMP/pan_$1.tsv"
  pan_fetch "$1" > "$TMP/pan_$1.json"
  grep -q '"code":0' "$TMP/pan_$1.json" 2>/dev/null || return 0
  sed "s/},{/}\n{/g" "$TMP/pan_$1.json" > "$TMP/pan_$1.lines"
  while IFS= read -r ln; do
    case "$ln" in *'"url":"'*) : ;; *) continue ;; esac
    val "$ln" url; [ -n "$OUT" ] || continue; unesc "$OUT"; u=$OUT
    val "$ln" note; unesc "$OUT"; n=$OUT
    val "$ln" datetime; d=$OUT
    val "$ln" source; s=$OUT
    val "$ln" password; p=$OUT
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$u" "$n" "$d" "$s" "$p" >> "$TMP/pan_$1.tsv"
  done < "$TMP/pan_$1.lines"
}

do_pansou() {
  [ -n "$KW" ] || return 0
  # 不传 cloud_types 结果最多；显式 --类型 时才按用户要求过滤
  types_csv=${CTYPE:-}
  PAN_OK=0
  : > "$TMP/pan.tsv"
  pan_fetch "$types_csv" > "$TMP/pan.json"
  if ! grep -q '"code":0' "$TMP/pan.json" 2>/dev/null; then
    sleep 3
    pan_fetch "$types_csv" > "$TMP/pan.json"
  fi
  if grep -q '"code":0' "$TMP/pan.json" 2>/dev/null && grep -q 'merged_by_type' "$TMP/pan.json" 2>/dev/null; then
    PAN_OK=1; pan_parse_merge "$TMP/pan.json"
  else
    # 兜底：按类型并发（20 秒一个，谁先回算谁）
    for t in $(printf '%s' "${CTYPE:-$ALL_TYPES}" | tr ',' ' '); do pan_one "$t" & done
    wait
    for t in $(printf '%s' "${CTYPE:-$ALL_TYPES}" | tr ',' ' '); do
      [ -s "$TMP/pan_$t.tsv" ] && cat "$TMP/pan_$t.tsv" >> "$TMP/pan.tsv"
    done
  fi
  if [ ! -s "$TMP/pan.tsv" ]; then
    echo "（网盘源本轮没返回结果：风控或超时。隔 30–60 秒重跑通常就好）" >&2
  fi
}

# ── 磁力：knaben / apibay ──────────────────────────────────
do_magnets() {
  : > "$TMP/mag.tsv"
  limit=$((TOP * 3)); [ "$limit" -lt 30 ] && limit=30

  body="{\"search_type\":\"100%\",\"search_field\":\"title\",\"query\":\"$(jstr "$KW")\",\"order_by\":\"seeders\",\"order_direction\":\"desc\",\"from\":0,\"size\":$limit,\"hide_unsafe\":true,\"hide_xxx\":true}"
  curl -sS -m 25 -X POST "https://api.knaben.org/v1" \
    -H "Content-Type: application/json" -H "User-Agent: $UA" \
    -d "$body" 2>/dev/null > "$TMP/knaben.json" &
  curl -sS -m 20 -G "https://apibay.org/q.php" \
    --data-urlencode "q=$KW" --data-urlencode "cat=0" \
    -A "$UA" 2>/dev/null > "$TMP/apibay.json" &
  wait

  if [ -s "$TMP/knaben.json" ]; then
    sed "s/},{/}\n{/g" "$TMP/knaben.json" > "$TMP/knaben.lines"
    while IFS= read -r ln; do
      case "$ln" in *'"hash":"'*) : ;; *) continue ;; esac
      val "$ln" title; t=$OUT
      [ -n "$t" ] || { val "$ln" description; t=$OUT; }
      [ -n "$t" ] || continue
      rel_ok "$t" || continue
      val "$ln" magnetUrl; unesc "$OUT"; m=$OUT
      [ -n "$m" ] || { val "$ln" hash; m="magnet:?xt=urn:btih:$OUT"; }
      nval "$ln" bytes; sz=$OUT
      nval "$ln" seeders; sd=$OUT
      val "$ln" date; dt=$OUT
      printf 'knaben\t%s\t%s\t%s\t%s\t%s\n' "$t" "$m" "$sz" "$sd" "$dt" >> "$TMP/mag.tsv"
    done < "$TMP/knaben.lines"
  fi

  if [ -s "$TMP/apibay.json" ]; then
    sed "s/},{/}\n{/g" "$TMP/apibay.json" > "$TMP/apibay.lines"
    while IFS= read -r ln; do
      case "$ln" in *'"info_hash":"'*) : ;; *) continue ;; esac
      val "$ln" name; t=$OUT; val "$ln" info_hash; h=$OUT
      [ -n "$t" ] && [ -n "$h" ] || continue
      case "$t" in "No results returned"*) continue ;; esac
      # 相关性：标题里得真含关键词，否则 apibay 会回一堆不相干的
      rel_ok "$t" || continue
      nval "$ln" size; sz=$OUT
      nval "$ln" seeders; sd=$OUT
      val "$ln" added; dt=$OUT
      printf 'apibay\t%s\t%s\t%s\t%s\t%s\n' "$t" "magnet:?xt=urn:btih:$h" "$sz" "$sd" "$dt" >> "$TMP/mag.tsv"
    done < "$TMP/apibay.lines"
  fi
}

# ── 打分：规则批量匹配标题（每条规则只 fork 一次 grep），再按行号合并
score_all() {
  : > "$TMP/scored"; : > "$TMP/sorted"
  [ -s "$TMP/mag.tsv" ] || return 0
  cut -f2 "$TMP/mag.tsv" > "$TMP/titles"

  : > "$TMP/hits"
  if [ -f "$RULES" ]; then
    while IFS=$'\t' read -r re pts nm; do
      [ -n "${re:-}" ] || continue
      grep -n -E -i -e "$re" "$TMP/titles" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\):.*/\1/p' > "$TMP/nums"
      [ -s "$TMP/nums" ] || continue
      while IFS= read -r no; do printf '%s\t%s\t%s\n' "$no" "$pts" "$nm"; done < "$TMP/nums" >> "$TMP/hits"
    done < "$RULES"
  fi
  sort -n "$TMP/hits" > "$TMP/hits.sorted" 2>/dev/null || : > "$TMP/hits.sorted"

  now=$(date +%s)
  exec 4< "$TMP/hits.sorted"
  hno=""; hpts="0"; hnm=""
  IFS=$'\t' read -r hno hpts hnm <&4 || hno=""
  no=0
  while IFS=$'\t' read -r src ttl mag sz sd dt; do
    no=$((no + 1))
    p=0; lab=""
    while [ -n "$hno" ]; do
      case "$hno" in ''|*[!0-9]*) hno=""; break ;; esac
      if [ "$hno" -eq "$no" ]; then
        p=$((p + hpts)); lab="$lab$hnm/"
        IFS=$'\t' read -r hno hpts hnm <&4 || hno=""
      else
        break
      fi
    done
    skip=0
    for w in 预告 花絮 枪版 抢先 试看 样片 招募 求种 已失效; do
      case "$ttl" in *"$w"*) skip=1; break ;; esac
    done
    if [ "$skip" = "0" ]; then
      case "$sd" in ''|*[!0-9]*) sd=0 ;; esac
      if [ "$sd" -gt 0 ]; then
        if [ "$sd" -ge 40 ]; then p=$((p + 20)); else p=$((p + sd / 2)); fi
      fi
      if [ -n "$dt" ]; then
        case "$dt" in
          *[!0-9]*) ep=$(date -d "$dt" +%s 2>/dev/null) ;;
          *) ep=$dt ;;
        esac
        case "${ep:-}" in ''|*[!0-9]*) ep=0 ;; esac
        if [ "$ep" -gt 0 ]; then
          dd=$(( (now - ep) / 86400 ))
          if [ "$dd" -le 1 ]; then p=$((p + 20))
          elif [ "$dd" -le 7 ]; then p=$((p + 12))
          elif [ "$dd" -le 30 ]; then p=$((p + 5))
          elif [ "$dd" -gt 365 ]; then p=$((p - 10))
          fi
        fi
      fi
      case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
      if [ "$sz" -gt 0 ] && [ "$sz" -lt 157286400 ]; then p=$((p - 15)); fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$src" "$ttl" "$mag" "$sz" "$sd" "${lab%/}" >> "$TMP/scored"
    fi
  done < "$TMP/mag.tsv"
  exec 4<&-
  sort -rn "$TMP/scored" > "$TMP/sorted"
}

# ── 自检 ──────────────────────────────────────────────────
if [ "$SELFTEST" = "1" ]; then
  echo "== 自检 =="
  HAS_KW=0; [ -n "$KW" ] && HAS_KW=1
  echo -n "PanSou $INST … "
  KW=${KW:-三体}
  pan_fetch "" > "$TMP/t.json"   # 自检也走「不传类型」，跟主查询保持一致
  if grep -q '"code":0' "$TMP/t.json" 2>/dev/null; then
    echo "OK $(grep -o '"total":[0-9]*' "$TMP/t.json" | head -1)"
  else
    echo "失败（风控/超时，稍后再试）"
  fi
  echo -n "knaben … "
  curl -sS -m 20 -o /dev/null -w "HTTP %{http_code} %{time_total}s\n" -X POST \
    -H "Content-Type: application/json" -A "$UA" \
    -d '{"search_type":"100%","search_field":"title","query":"matrix","from":0,"size":1}' \
    "https://api.knaben.org/v1" 2>/dev/null || echo "失败"
  echo -n "apibay … "
  curl -sS -m 20 -o /dev/null -w "HTTP %{http_code} %{time_total}s\n" \
    -G "https://apibay.org/q.php" --data-urlencode "q=matrix" --data-urlencode "cat=0" \
    -A "$UA" 2>/dev/null || echo "失败"
  echo
  [ "$HAS_KW" = "1" ] || exit 0
fi

[ -n "$KW" ] || { sed -n '2,12p' "$0"; exit 2; }

# ── 抓取 ──────────────────────────────────────────────────
if [ "$MAG_ONLY" = "0" ]; then do_pansou; else : > "$TMP/pan.tsv"; fi
do_magnets
score_all

# 有哪些类型有结果（从结果里取，magnet/ed2k 不在网盘分组里显示）
: > "$TMP/pan_type.tsv"
if [ -s "$TMP/pan.tsv" ]; then
  cut -f1 "$TMP/pan.tsv" | uniq | while IFS= read -r t; do
    case "$t" in magnet|ed2k) continue ;; esac
    printf '%s\n' "$t"
  done > "$TMP/pan_type.tsv"
fi
count_type() { cut -f1 "$TMP/pan.tsv" 2>/dev/null | grep -c "^$1$"; }

# ── 输出 ──────────────────────────────────────────────────
if [ "$MODE" = "json" ]; then
  printf '{"关键词":"%s","网盘":{' "$(jstr "$KW")"
  first=1
  while IFS= read -r t; do
    [ "$first" = "1" ] || printf ','
    first=0
    printf '"%s":[' "$t"
    i=0
    while IFS=$'\t' read -r tp url note dtm src pw; do
      [ "$tp" = "$t" ] || continue
      i=$((i + 1)); [ "$i" -le "$PAN_TOP" ] || break
      [ "$i" = "1" ] || printf ','
      printf '{"url":"%s","note":"%s","datetime":"%s","source":"%s","password":"%s"}' \
        "$(jstr "$url")" "$(jstr "$note")" "$(jstr "$dtm")" "$(jstr "$src")" "$(jstr "$pw")"
    done < "$TMP/pan.tsv"
    printf ']'
  done < "$TMP/pan_type.tsv"
  printf '},"磁力":['
  i=0
  if [ -s "$TMP/sorted" ]; then
    while IFS=$'\t' read -r sc src ttl mag sz sd lab; do
      i=$((i + 1)); [ "$i" -le "$TOP" ] || break
      [ "$i" = "1" ] || printf ','
      printf '{"分数":%s,"标题":"%s","做种":%s,"大小":%s,"来源":"%s","命中":"%s","链接":"%s"}' \
        "$sc" "$(jstr "$ttl")" "${sd:-0}" "${sz:-0}" "$src" "$(jstr "$lab")" "$(jstr "$mag")"
    done < "$TMP/sorted"
  fi
  printf ']}\n'
  exit 0
fi

if [ "$MODE" = "links" ]; then
  i=0
  while IFS=$'\t' read -r tp url note dtm src pw; do
    i=$((i + 1)); [ "$i" -le "$((PAN_TOP * 9))" ] || break
    if [ -n "$pw" ]; then printf '%s  提取码：%s\n' "$url" "$pw"; else printf '%s\n' "$url"; fi
  done < "$TMP/pan.tsv"
  [ -s "$TMP/sorted" ] && head -n "$TOP" "$TMP/sorted" | while IFS=$'\t' read -r sc src ttl mag sz sd lab; do shorten_magnet "$mag"; echo; done
  exit 0
fi

while IFS= read -r t; do
  cnt=$(count_type "$t")
  [ "$cnt" -gt 0 ] || continue
  printf '【%s】%s 条\n' "$(type_name "$t")" "$cnt"
  i=0
  while IFS=$'\t' read -r tp url note dtm src pw; do
    [ "$tp" = "$t" ] || continue
    i=$((i + 1)); [ "$i" -le "$PAN_TOP" ] || break
    printf '  %2d. %s\n' "$i" "$note"
    printf '      %s · %s\n' "$(fmt_time "$dtm")" "$src"
    if [ -n "$pw" ]; then printf '      %s  提取码：%s\n' "$url" "$pw"; else printf '      %s\n' "$url"; fi
  done < "$TMP/pan.tsv"
  [ "$cnt" -gt "$PAN_TOP" ] && printf '      …… 还有 %s 条没列（--网盘条数 调大）\n' "$((cnt - PAN_TOP))"
  echo
done < "$TMP/pan_type.tsv"

if [ -s "$TMP/sorted" ]; then
  cnt=$(wc -l < "$TMP/sorted" | tr -d ' ')
  [ "$cnt" -gt "$TOP" ] && cnt=$TOP
  printf '【磁力】%s 条\n' "$cnt"
  i=0
  while IFS=$'\t' read -r sc src ttl mag sz sd lab; do
    i=$((i + 1)); [ "$i" -le "$TOP" ] || break
    printf '  %2d. %s分  做种%s  %s  %s  %s\n' "$i" "$sc" "${sd:-0}" "$(hsize "$sz")" "$src" "$ttl"
    [ -n "$lab" ] && printf '      标记：%s\n' "$lab"
    printf '      %s\n' "$(shorten_magnet "$mag")"
  done < "$TMP/sorted"
else
  echo "【磁力】0 条"
fi

if [ -s "$TMP/pan.tsv" ] || [ -s "$TMP/sorted" ]; then
  exit 0                       # 0 = 有结果
fi

echo
echo "什么都没搜到。公开源偶发空结果，隔 30–60 秒重跑一次；中文片名优先；国际索引对中日韩文很弱。"

MAG_OK=0
if [ -s "$TMP/knaben.json" ] || [ -s "$TMP/apibay.json" ]; then MAG_OK=1; fi
if [ "${PAN_OK:-0}" = "1" ] || [ "$MAG_OK" = "1" ]; then
  exit 3                       # 3 = 连得通，但确实没货
fi
exit 1                         # 1 = 两路都没连上（网络/风控）
