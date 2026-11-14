#!/bin/sh
# 社群首发 —— 从豆瓣条目讨论区的回应里捞网盘与磁力链接（纯 shell：只用 curl/grep/sed/tr/sort）
#
# 为什么需要它：冷门新片在网盘聚合、磁力索引、字幕站里全是 0 条，但首发链接往往
# 就贴在豆瓣条目的讨论帖回应里（《钥匙／鍵 2026》就是这么找到的）。
#
# 用法：
#   sh 社群首发.sh 37817151                    # 扫该条目全部讨论帖
#   sh 社群首发.sh 37817151 --max 200          # 每帖最多取 200 条回应（默认 100）
#   sh 社群首发.sh 37817151 --topic 498744331  # 只扫指定帖
#   sh 社群首发.sh 37817151 --no-expand        # 不展开短链（省流量）
#
# 输出 TSV：帖ID <TAB> 类型 <TAB> 链接     类型 = 夸克/百度/115/磁力/短链/直链
# 依赖：curl、grep -oE、sed、tr、sort（Android toybox 自带，无需 jq/python/awk）
# 注意：变量名一律 ASCII —— bash/mksh 都不认中文变量名（会 bad substitution）。

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
API="https://m.douban.com/rexxar/api/v2"
TAB=$(printf '\t')
MAXC=100
ONLY_TOPIC=""
EXPAND=1
SID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --max)       MAXC="$2"; shift 2 ;;
    --topic)     ONLY_TOPIC="$2"; shift 2 ;;
    --no-expand) EXPAND=0; shift ;;
    -h|--help)   sed -n '2,18p' "$0"; exit 0 ;;
    *)           SID="$1"; shift ;;
  esac
done

if [ -z "$SID" ]; then
  echo "用法：sh 社群首发.sh <豆瓣条目ID> [--max 100] [--topic 帖ID] [--no-expand]"
  echo "例：  sh 社群首发.sh 37817151"
  exit 2
fi

TMP=$(mktemp -d 2>/dev/null || echo "/tmp/db.$$")
mkdir -p "$TMP" 2>/dev/null
trap 'rm -rf "$TMP"' EXIT

REF="https://m.douban.com/movie/subject/$SID/"

dl() {
  curl -s --max-time 30 -A "$UA" -H "accept-language: zh-CN" -H "referer: $REF" "$1"
}

# JSON 压成一行，按 "},{" 切成一条对象一行
flatten() {
  { tr -d '\n\r' < "$1"; echo; } | sed 's/},{/}\n{/g'
}

echo "条目 $SID → 拉讨论帖列表…"
dl "$API/movie/$SID/forum_topics?count=20&start=0" > "$TMP/topics.json"

if [ ! -s "$TMP/topics.json" ]; then
  echo "✗ 讨论区接口没返回内容（条目可能没有讨论区，或被风控）"
  exit 1
fi
if ! printf '%s' "$(cat "$TMP/topics.json")" | grep -q '"total"'; then
  echo "✗ 返回不是预期 JSON：$(head -c 120 "$TMP/topics.json")"
  exit 1
fi
if printf '%s' "$(cat "$TMP/topics.json")" | grep -q '"total": *0'; then
  echo "· 讨论区 0 帖（没人发过帖，去别处找）"
  exit 0
fi

# 主题帖 id：对象里最后一个 "id": "数字" 才是帖 id（前面 author.id 也是这个形态）
flatten "$TMP/topics.json" > "$TMP/topics.blocks"
: > "$TMP/topics.list"
while IFS= read -r blk; do
  tid=$(printf '%s' "$blk" | grep -oE '"id": *"[0-9]+"' | tail -n 1 | grep -oE '[0-9]+')
  tcnt=$(printf '%s' "$blk" | grep -oE '"comments_count": *[0-9]+' | head -n 1 | grep -oE '[0-9]+')
  [ -z "$tid" ] && continue
  if [ -n "$ONLY_TOPIC" ] && [ "$tid" != "$ONLY_TOPIC" ]; then continue; fi
  printf '%s%s%s\n' "$tid" "$TAB" "${tcnt:-0}" >> "$TMP/topics.list"
done < "$TMP/topics.blocks"

echo "· 待扫 $(wc -l < "$TMP/topics.list" | tr -d ' ') 个帖"

: > "$TMP/raw.tsv"

while IFS="$TAB" read -r tid tcnt; do
  echo "  → 帖 $tid（$tcnt 条回应）"
  dl "$API/group/topic/$tid/comments?count=$MAXC&start=0" > "$TMP/c.json"
  if [ ! -s "$TMP/c.json" ]; then
    echo "    ✗ 回应接口没返回（帖被删或需登录）"
    continue
  fi
  flatten "$TMP/c.json" > "$TMP/c.blocks"
  # 豆瓣回应的中文是原文（不是 \uXXXX），可直接匹配
  grep -oE '"text":"[^"]*"' "$TMP/c.blocks" | sed 's/^"text":"//; s/"$//' > "$TMP/texts.txt"
  echo "    · 回应 $(wc -l < "$TMP/texts.txt" | tr -d ' ') 条"

  while IFS= read -r txt; do
    [ -z "$txt" ] && continue
    # 归一：\n 当空格；各种"左斜杠"写法还原成 /
    norm=$(printf '%s' "$txt" | sed 's/\\n/ /g; s/\\r/ /g; s/左斜杠/\//g; s/右斜杠/\//g; s/正斜杠/\//g; s/反斜杠/\//g; s/斜杠/\//g; s/／/\//g')
    # 1) 完整链接
    printf '%s\n' "$norm" | grep -oE 'https?:\/\/[^ "]+' | while IFS= read -r u; do
      printf '%s%s%s\n' "$tid" "$TAB" "$u" >> "$TMP/raw.tsv"
    done
    # 2) 模糊写法：「夸克 左斜杠s左斜杠 38d3d84a625a」→ 还原成 pan.quark.cn/s/38d3d84a625a
    if printf '%s' "$norm" | grep -q '夸克'; then
      printf '%s\n' "$norm" | grep -oE 's/[0-9a-zA-Z]{6,}' | while IFS= read -r p; do
        printf '%s%shttps://pan.quark.cn/%s\n' "$tid" "$TAB" "$p" >> "$TMP/raw.tsv"
      done
    fi
    # 3) 百度 / 115
    printf '%s\n' "$norm" | grep -oE '(pan\.baidu\.com/s/[0-9a-zA-Z_-]+|115\.com/s/[0-9a-zA-Z]+)' | while IFS= read -r p; do
      printf '%s%shttps://%s\n' "$tid" "$TAB" "$p" >> "$TMP/raw.tsv"
    done
    # 4) 磁力
    printf '%s\n' "$norm" | grep -oE 'magnet:\?xt=urn:btih:[0-9a-zA-Z]+' | while IFS= read -r m; do
      printf '%s%s%s\n' "$tid" "$TAB" "$m" >> "$TMP/raw.tsv"
    done
  done < "$TMP/texts.txt"
done < "$TMP/topics.list"

if [ ! -s "$TMP/raw.tsv" ]; then
  echo
  echo "· 回应里没有链接/磁力（这类帖常常只有「我有」「多少米」「20文」这种付费引流）"
  exit 0
fi

# 按链接去重（保留第一次出现），再分类 + 可选展开短链
cut -f2 "$TMP/raw.tsv" | sort -u > "$TMP/urls.txt"
: > "$TMP/hits.tsv"
while IFS= read -r u; do
  tid=$(grep -F "$u" "$TMP/raw.tsv" | head -n 1 | cut -f1)
  kind="直链"
  case "$u" in
    *pan.quark.cn*)  kind="夸克" ;;
    *pan.baidu.com*) kind="百度" ;;
    *115.com*)       kind="115" ;;
    magnet:*)        kind="磁力" ;;
  esac
  out="$u"
  case "$u" in
    *ourl.cn*|*x-zone.cn*|*lexdev.cn*|*t.cn*|*url.cn*|*sourl.cn*|*dwz.cn*|*suo.im*)
      kind="短链"
      if [ "$EXPAND" = "1" ]; then
        fin=$(curl -sIL -o /dev/null --max-time 25 -A "$UA" -w '%{url_effective}' "$u" 2>/dev/null)
        [ -n "$fin" ] && out="$fin"
      fi
      ;;
  esac
  printf '%s%s%s%s%s\n' "$tid" "$TAB" "$kind" "$TAB" "$out" >> "$TMP/hits.tsv"
done < "$TMP/urls.txt"

echo
echo "序号  帖ID        类型   链接"
i=0
while IFS="$TAB" read -r t k l; do
  i=$((i+1))
  printf '%-5s %-11s %-6s %s\n' "$i" "$t" "$k" "$l"
done < "$TMP/hits.tsv"

echo
echo "共 $(wc -l < "$TMP/hits.tsv" | tr -d ' ') 条候选。"
echo "下一步：夸克链接先自行确认有效性；磁力可交给下载工具或 115 离线。"
echo "提醒：这类帖子大量是「我有/多少米/私信」的付费引流，形如 s/xxxxxxx 的才是真链接。"
