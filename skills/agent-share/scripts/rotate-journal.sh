#!/bin/sh
# TURN_LOG 로테이션 — 임계치 초과 시 오래된 턴을 월별 아카이브로 이관, 최근 N턴만 유지.
#
# 왜 스크립트인가: 이 규칙은 전부 기계적이고, 전제조건(merge=union 부활 방지)을
# 사람/LLM 판단에 맡기면 사고가 난다. 스크립트가 게이트를 강제한다.
#
# 안전 게이트: main 에 머지되지 않은 wo/* 브랜치가 있으면 중단.
#   union 머지는 truncate 를 되살리므로(SKILL Gotcha 6), 모든 WO 가 머지된 정지 시점에만.
#
# 사용: rotate-journal.sh [journal-dir] [--threshold 500] [--keep 10]
#                         [--check] [--no-commit] [--force]
#   --check      판정만 (파일 변경 없음)
#   --no-commit  파일만 갱신, 커밋 안 함 (수동 커밋 시 git commit --no-verify 필요)
#   --force      임계치 미만이어도 실행 (머지 게이트는 --force 로도 우회 불가)
set -eu

JOURNAL_DIR=.agent
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then JOURNAL_DIR=$1; shift; fi

THRESHOLD=500
KEEP=10
CHECK=0
NO_COMMIT=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD=${2:?}; shift 2 ;;
    --keep) KEEP=${2:?}; shift 2 ;;
    --check) CHECK=1; shift ;;
    --no-commit) NO_COMMIT=1; shift ;;
    --force) FORCE=1; shift ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

LOG="$JOURNAL_DIR/TURN_LOG.md"
[ -f "$LOG" ] || { echo "TURN_LOG.md 없음: $LOG" >&2; exit 1; }

lines=$(wc -l < "$LOG" | tr -d ' ')
if [ "$lines" -le "$THRESHOLD" ] && [ "$FORCE" -eq 0 ]; then
  echo "로테이션 불필요: ${lines}줄 (임계치 ${THRESHOLD})"
  exit 0
fi

turns=$(grep -c '^## ' "$LOG" || true); turns=${turns:-0}
if [ "$turns" -le "$KEEP" ]; then
  echo "아카이브할 턴 없음: 총 ${turns}턴 (유지 ${KEEP})"
  exit 0
fi

# --- 안전 게이트: 미머지 wo/* 브랜치 (merge=union 부활 방지) ---
unmerged=$(git -C "$JOURNAL_DIR" branch --no-merged main 2>/dev/null | grep -E 'wo/' || true)
if [ -n "$unmerged" ]; then
  echo "중단: main 에 머지되지 않은 WO 브랜치가 있어 로테이션할 수 없습니다." >&2
  echo "      (union 머지가 잘라낸 내용을 되살립니다 — SKILL Gotcha 6)" >&2
  echo "$unmerged" | sed 's/^/        /' >&2
  echo "      모든 wo/* 를 main 에 머지한 뒤 다시 실행하세요." >&2
  exit 3
fi

archive_n=$((turns - KEEP))
if [ "$CHECK" -eq 1 ]; then
  echo "로테이션 가능: ${lines}줄, ${turns}턴 → 최근 ${KEEP}턴 유지, ${archive_n}턴 아카이브"
  echo "(게이트 통과: 미머지 WO 브랜치 없음)"
  exit 0
fi

YM=$(date +%Y%m)
ARCHIVE="$JOURNAL_DIR/TURN_LOG-archive-${YM}.md"
first=$(grep -n '^## ' "$LOG" | head -1 | cut -d: -f1)
keepstart=$(grep -n '^## ' "$LOG" | sed -n "$((turns - KEEP + 1))p" | cut -d: -f1)

tmp_pre=$(mktemp); tmp_arc=$(mktemp); tmp_kep=$(mktemp); tmp_log=$(mktemp)
trap 'rm -f "$tmp_pre" "$tmp_arc" "$tmp_kep" "$tmp_log"' EXIT

awk -v first="$first" -v keepstart="$keepstart" \
    -v pre="$tmp_pre" -v arc="$tmp_arc" -v kep="$tmp_kep" '
  NR <  first     { print > pre; next }
  NR <  keepstart { print > arc; next }
                  { print > kep }
' "$LOG"

if [ ! -f "$ARCHIVE" ]; then
  printf '# Turn Log Archive — %s\n\n로테이션으로 이관된 과거 턴. append-only. 현재 저널은 TURN_LOG.md.\n\n' "$YM" > "$ARCHIVE"
fi
cat "$tmp_arc" >> "$ARCHIVE"

cat "$tmp_pre" "$tmp_kep" > "$tmp_log"
mv "$tmp_log" "$LOG"

new_lines=$(wc -l < "$LOG" | tr -d ' ')
echo "로테이션 완료: ${archive_n}턴 → $(basename "$ARCHIVE"), TURN_LOG ${lines}→${new_lines}줄 (최근 ${KEEP}턴)"

if [ "$NO_COMMIT" -eq 1 ]; then
  echo "커밋 생략(--no-commit). 수동 커밋 시 append-only 훅 때문에 --no-verify 필요."
  exit 0
fi

git -C "$JOURNAL_DIR" add "$(basename "$LOG")" "$(basename "$ARCHIVE")"
git -C "$JOURNAL_DIR" commit --no-verify \
  -m "chore: TURN_LOG 로테이션 (${archive_n}턴 → ${YM} 아카이브)" >/dev/null
echo "커밋: $(git -C "$JOURNAL_DIR" log -1 --oneline)"
