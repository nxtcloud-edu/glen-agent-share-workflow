#!/bin/sh
# 턴 상태 파일 스캐폴딩 — 의미 있는 턴 시작 시. 타임스탬프·명명 자동, 절대 덮어쓰지 않음.
#
# 사용: new-turn.sh <share-dir> <agent> <topic> <role> [--phase <phase>] \
#                   [--date <yyyymmdd>] [--time <hhmmss>]
#   role:  initiator | reviewer | follow-up | implementer | verifier | maintainer
#   phase: planning | implementing | verifying | reviewing | follow-up |
#          documenting | handoff | blocked | complete   (기본: planning)
set -eu

DIR=${1:?share-dir (new-share.sh 가 만든 폴더)}
AGENT=${2:?agent}
TOPIC=${3:?topic-slug}
ROLE=${4:?role}
shift 4

PHASE=planning
DATE=$(date +%Y%m%d)
TIME=$(date +%H%M%S)
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE=${2:?}; shift 2 ;;
    --date)  DATE=${2:?}; shift 2 ;;
    --time)  TIME=${2:?}; shift 2 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

[ -d "$DIR" ] || { echo "share-dir 없음: $DIR (먼저 new-share.sh)" >&2; exit 1; }
mkdir -p "$DIR/turns"

STARTED=$(date '+%Y-%m-%d %H:%M:%S %Z')
FILE="$DIR/turns/$AGENT-turn-$TOPIC-$DATE-$TIME.md"
[ -e "$FILE" ] && { echo "이미 존재: $FILE (턴 파일은 덮어쓰지 않음 — --time 으로 재지정)" >&2; exit 1; }

{
  printf '# %s Turn: %s\n\n' "$AGENT" "$TOPIC"
  printf -- '- Agent: %s\n' "$AGENT"
  printf -- '- Turn role: %s\n' "$ROLE"
  printf -- '- Turn phase: %s\n' "$PHASE"
  printf -- '- Started: %s\n' "$STARTED"
  printf -- '- Status: active\n'
  printf -- '- Related artifacts:\n'
  printf -- '  - `<file>`\n\n'
  cat <<'EOF'
## Current Intent

## Context Read

## Planned Writes

## Verification To Run

## Handoff Criteria

## Completion Update
EOF
} > "$FILE"

echo "생성: $FILE"
echo "리마인더: 턴 종료 전 Status 를 complete|waiting-review|waiting-user|blocked 로 갱신 (active 방치 금지)"
