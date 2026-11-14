#!/system/bin/sh
# 全搜：一条命令跑完三路 —— 网盘 + 磁力（find.sh）与 采集接口直链（collect.sh）并发
# 用法：
#   sh scripts/all.sh "关键词"
#   sh scripts/all.sh "关键词" --条数 10 --网盘条数 5      # 传给 find.sh
#   sh scripts/all.sh "关键词" --宽 --超时=10              # 传给 collect.sh
#   sh scripts/all.sh "关键词" --只链接                    # find.sh 只打链接
set -u
DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || DIR=.

KW=""
A_ARGS=""
C_ARGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --宽|--满)
      C_ARGS="$C_ARGS $1" ;;
    --超时=*)
      C_ARGS="$C_ARGS $1" ;;
    --磁力|--只链接|--json)
      A_ARGS="$A_ARGS $1" ;;
    --类型|--条数|--网盘条数)
      A_ARGS="$A_ARGS $1 ${2:-}"
      shift ;;
    -h|--help)
      sed -n '2,9p' "$0"; exit 0 ;;
    -*)
      echo "未知参数：$1" >&2 ;;
    *)
      [ -z "$KW" ] && KW="$1" ;;
  esac
  shift
done

[ -n "$KW" ] || { sed -n '2,9p' "$0"; exit 2; }
[ -f "$DIR/find.sh" ] || { echo "缺少 $DIR/find.sh" >&2; exit 1; }
[ -f "$DIR/collect.sh" ] || { echo "缺少 $DIR/collect.sh" >&2; exit 1; }

TMPD=$(mktemp -d 2>/dev/null) || TMPD="${TMPDIR:-.}/quansou.$$"
mkdir -p "$TMPD" 2>/dev/null || { TMPD="${TMPDIR:-.}/quansou.$$"; mkdir -p "$TMPD"; }
cleanup() { rm -rf "$TMPD" 2>/dev/null; }
trap cleanup EXIT INT TERM

T0=$(date +%s)

# 两路并发；各自把 stdout+stderr 都收进文件
( sh "$DIR/find.sh" "$KW" $A_ARGS > "$TMPD/pan.txt" 2>&1; echo $? > "$TMPD/pan.rc" ) &
( sh "$DIR/collect.sh" "$KW" $C_ARGS > "$TMPD/cj.txt" 2>&1; echo $? > "$TMPD/cj.rc" ) &
wait

T1=$(date +%s)
PAN_RC=$(cat "$TMPD/pan.rc" 2>/dev/null || echo "?")
CJ_RC=$(cat "$TMPD/cj.rc" 2>/dev/null || echo "?")

echo "== 「$KW」全搜 · 用时 $((T1 - T0))s =="
echo
echo "──────── 网盘 + 磁力（find.sh）────────"
if [ -s "$TMPD/pan.txt" ]; then cat "$TMPD/pan.txt"; else echo "（无输出，rc=$PAN_RC）"; fi
echo
echo "──────── 直链（collect.sh）────────"
if [ -s "$TMPD/cj.txt" ]; then cat "$TMPD/cj.txt"; else echo "（无输出，rc=$CJ_RC）"; fi
echo
echo "== 结束：网盘/磁力 rc=$PAN_RC，直链 rc=$CJ_RC =="
