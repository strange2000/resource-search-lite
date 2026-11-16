#!/system/bin/sh
# 全搜：一条命令跑完两路 —— 网盘+磁力（find.sh）与 采集接口直链（collect.sh）并发
# 用法：
#   sh scripts/all.sh "关键词"
#   sh scripts/all.sh "关键词" --只直链        # 只跑直链那路（几秒）
#   sh scripts/all.sh "关键词" --只网磁        # 只跑网盘/磁力
#   sh scripts/all.sh "关键词" --条数 10 --网盘条数 5   # 传给 find.sh
#   sh scripts/all.sh "关键词" --宽 --超时=10           # 传给 collect.sh
# 参数分流：--宽/--满/--全部 → collect.sh；--只直链/--只网磁 自己吃掉；其余带值的给 find.sh
set -u
DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || DIR=.

KW=""
A_ARGS=""
C_ARGS=""
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --只直链) ONLY="c" ;;
    --只网磁) ONLY="p" ;;
    --宽|--满|--全部) C_ARGS="$C_ARGS $1" ;;
    --超时=*) C_ARGS="$C_ARGS $1" ;;
    --条数|--类型|--选|--磁链|--夸克条数)
      A_ARGS="$A_ARGS $1 ${2:-}"
      shift ;;
    -h|--help)
      sed -n '2,10p' "$0"; exit 0 ;;
    -*) A_ARGS="$A_ARGS $1" ;;
    *) [ -z "$KW" ] && KW="$1" ;;
  esac
  shift
done

[ -n "$KW" ] || { sed -n '2,10p' "$0"; exit 1; }
[ -f "$DIR/find.sh" ] || { echo "缺少 $DIR/find.sh" >&2; exit 1; }
[ -f "$DIR/collect.sh" ] || { echo "缺少 $DIR/collect.sh" >&2; exit 1; }

TMPD=$(mktemp -d 2>/dev/null) || TMPD="${TMPDIR:-.}/quansou.$$"
mkdir -p "$TMPD" 2>/dev/null || { TMPD="${TMPDIR:-.}/quansou.$$"; mkdir -p "$TMPD"; }
cleanup() { rm -rf "$TMPD" 2>/dev/null; }
trap cleanup EXIT INT TERM

S=$(date +%s)

if [ "$ONLY" != "c" ]; then
  ( sh "$DIR/find.sh" "$KW" $A_ARGS > "$TMPD/pan.txt" 2>&1
    echo $? > "$TMPD/pan.rc"; echo $(( $(date +%s) - S )) > "$TMPD/pan.dur" ) &
fi
if [ "$ONLY" != "p" ]; then
  ( sh "$DIR/collect.sh" "$KW" $C_ARGS > "$TMPD/cj.txt" 2>&1
    echo $? > "$TMPD/cj.rc"; echo $(( $(date +%s) - S )) > "$TMPD/cj.dur" ) &
fi
wait

ALL=$(( $(date +%s) - S ))
PAN_RC=$(cat "$TMPD/pan.rc" 2>/dev/null || echo "-")
CJ_RC=$(cat "$TMPD/cj.rc" 2>/dev/null || echo "-")
PAN_D=$(cat "$TMPD/pan.dur" 2>/dev/null || echo "0")
CJ_D=$(cat "$TMPD/cj.dur" 2>/dev/null || echo "0")

echo "== 「${KW}」全搜 · 总用时 ${ALL}s =="

if [ "$ONLY" != "c" ]; then
  echo
  echo "──────── 网盘 + 磁力（find.sh · ${PAN_D}s · rc=${PAN_RC}）────────"
  if [ -s "$TMPD/pan.txt" ]; then
    cat "$TMPD/pan.txt"
  else
    echo "（没拿到输出：可能 PanSou 实例超时或被风控，单独重跑 sh scripts/find.sh \"$KW\"）"
  fi
fi

if [ "$ONLY" != "p" ]; then
  echo
  echo "──────── 直链（collect.sh · ${CJ_D}s · rc=${CJ_RC}）────────"
  if [ -s "$TMPD/cj.txt" ]; then
    cat "$TMPD/cj.txt"
  else
    echo "（没拿到输出：先跑 sh scripts/collect.sh --探活，看这 14 个接口今天活没活）"
  fi
fi

echo
# 退出码约定：0 有结果 / 3 零结果 / 1 出错 / 2 参数错误
# 单路模式：原样透传那一路的 rc；双路模式：任一路有结果=0，两路都零结果=3，其余=1
if [ "$ONLY" = "c" ]; then
  echo "== 结束：直链那路 rc=$CJ_RC =="
  exit "$CJ_RC"
elif [ "$ONLY" = "p" ]; then
  echo "== 结束：网盘/磁力那路 rc=$PAN_RC =="
  exit "$PAN_RC"
elif [ "$PAN_RC" = "0" ] || [ "$CJ_RC" = "0" ]; then
  echo "== 结束：rc=0（至少一路有结果） =="
  exit 0
elif [ "$PAN_RC" = "3" ] && [ "$CJ_RC" = "3" ]; then
  echo "== 结束：rc=3（两路都连通但没货） =="
  exit 3
fi
echo "== 结束：rc=1（有路没连上：网盘/磁力=$PAN_RC，直链=$CJ_RC） =="
exit 1
