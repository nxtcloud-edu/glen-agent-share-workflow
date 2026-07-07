#!/bin/sh
# 저널 ↔ 실제 상태 대조 (검증자 1단계 기계화, AGENTS.md 규칙 1).
# 자기 보고를 곧이곧대로 믿지 않기 위한 실측 대조 — 전부 휴리스틱이므로 불일치는 "확인 필요" 신호.
#
# 검사:
#   [1] CURRENT_STATE.md 에 적힌 SHA ↔ 실제 git HEAD
#   [2] active 상태로 방치된 턴 파일
#   [3] WO 상태(진행 중/검증 대기 등) ↔ wo/NNN 브랜치 존재 여부
#
# 사용: check-journal.sh [journal-dir] [--turns-root <dir>] [--wo-dir <dir>]
#                        [--branch-prefix wo/] [--strict]
#   --strict  불일치 발견 시 exit 1 (게이트용). 기본은 리포트만 하고 exit 0.
set -eu

JOURNAL_DIR=.agent
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then JOURNAL_DIR=$1; shift; fi

TURNS_ROOT=agent-share
WO_DIR=""
PREFIX=wo/
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --turns-root) TURNS_ROOT=${2:?}; shift 2 ;;
    --wo-dir) WO_DIR=${2:?}; shift 2 ;;
    --branch-prefix) PREFIX=${2:?}; shift 2 ;;
    --strict) STRICT=1; shift ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done
[ -n "$WO_DIR" ] || WO_DIR="$JOURNAL_DIR/work-orders"

issues=0
note() { echo "  - $1"; }

echo "저널 대조: $JOURNAL_DIR"

# [1] CURRENT_STATE HEAD ↔ 실제 HEAD
echo "[1] CURRENT_STATE HEAD ↔ git HEAD"
CS="$JOURNAL_DIR/CURRENT_STATE.md"
if [ -f "$CS" ]; then
  head_full=$(git -C "$JOURNAL_DIR" rev-parse HEAD 2>/dev/null || echo "")
  toks=$(grep -oE '[0-9a-f]{7,40}' "$CS" | sort -u || true)
  if [ -z "$toks" ]; then
    note "SHA 미기재 — 대조 불가"
  elif [ -z "$head_full" ]; then
    note "git HEAD 확인 불가"
  else
    match=0
    for t in $toks; do
      case "$head_full" in "$t"*) match=1 ;; esac
    done
    if [ "$match" -eq 1 ]; then
      note "일치: $head_full"
    else
      note "불일치: 기재 [$(echo $toks | tr '\n' ' ')] ≠ HEAD $head_full (오래된 상태일 수 있음)"
      issues=$((issues + 1))
    fi
  fi
else
  note "CURRENT_STATE.md 없음: $CS"
fi

# [2] active 방치 턴 파일
echo "[2] active 방치 턴 파일"
found_active=0
if [ -d "$TURNS_ROOT" ] || [ -d "$JOURNAL_DIR" ]; then
  for f in $(find "$TURNS_ROOT" "$JOURNAL_DIR" -path '*/turns/*.md' 2>/dev/null || true); do
    if grep -q '^- Status: active' "$f" 2>/dev/null; then
      note "active: $f"
      found_active=1
      issues=$((issues + 1))
    fi
  done
fi
[ "$found_active" -eq 0 ] && note "없음 (모든 턴 종료됨)"

# [3] WO 상태 ↔ 브랜치
echo "[3] WO 상태 ↔ ${PREFIX}NNN 브랜치"
if [ -d "$WO_DIR" ]; then
  any=0
  for wo in "$WO_DIR"/WO-*.md; do
    [ -e "$wo" ] || continue
    any=1
    num=$(basename "$wo" | sed -n 's/^WO-\([0-9][0-9]*\).*/\1/p')
    [ -n "$num" ] || continue
    status=$(grep -m1 '^상태:' "$wo" 2>/dev/null | sed 's/^상태:[[:space:]]*//' || true)
    br="${PREFIX}${num}"
    has=$(git -C "$JOURNAL_DIR" branch --list "$br" 2>/dev/null | tr -d ' *' || true)
    case "$status" in
      *"진행 중"*|*"검증 대기"*)
        if [ -z "$has" ]; then note "WO-$num '$status' 인데 브랜치 $br 없음"; issues=$((issues + 1)); fi ;;
      *완료*|*반려*|*대기*)
        if [ -n "$has" ]; then note "WO-$num '$status' 인데 브랜치 $br 잔존 (정리 후보)"; fi ;;
      *) note "WO-$num 상태 파싱 불가: '$status'" ;;
    esac
  done
  [ "$any" -eq 0 ] && note "WO 파일 없음"
else
  note "WO 디렉토리 없음: $WO_DIR"
fi

echo
if [ "$issues" -gt 0 ]; then
  echo "불일치/주의 ${issues}건 — 검증자 실측으로 확정할 것 (자기 보고는 미확인)"
  [ "$STRICT" -eq 1 ] && exit 1
else
  echo "대조 통과: 불일치 없음"
fi
exit 0
