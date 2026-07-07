#!/bin/sh
# 공유 폴더 스캐폴딩 (initiator) — 폴더/turns/plan/progress 를 명명 규칙대로 생성.
# 날짜·hyphen-case 는 스크립트가 고정 → LLM 의 명명 불일치 원천 차단.
#
# 사용: new-share.sh <agent> <topic-slug> [--root <dir>] [--date <yyyymmdd>]
#   예: new-share.sh claude auth-refactor
#       new-share.sh codex review-remediation --root agent-share --date 20260707
set -eu

AGENT=${1:?agent (예: claude|codex|gemini|human)}
TOPIC=${2:?topic-slug (소문자 hyphen-case)}
shift 2

ROOT=agent-share
DATE=$(date +%Y%m%d)
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT=${2:?}; shift 2 ;;
    --date) DATE=${2:?}; shift 2 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

case "$TOPIC" in *[!a-z0-9-]*) echo "topic-slug 는 소문자·숫자·하이픈만: $TOPIC" >&2; exit 2 ;; esac
case "$DATE" in ????????) : ;; *) echo "date 는 yyyymmdd: $DATE" >&2; exit 2 ;; esac

DATE_H=$(echo "$DATE" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DIR="$ROOT/$AGENT-$TOPIC-$DATE"
PLAN="$DIR/$AGENT-plan-$TOPIC-$DATE.md"
PROGRESS="$DIR/$AGENT-progress-$TOPIC-$DATE.md"

[ -e "$DIR" ] && { echo "이미 존재: $DIR (덮어쓰지 않음)" >&2; exit 1; }
mkdir -p "$DIR/turns"

{
  printf '# %s Plan: %s\n\n' "$AGENT" "$TOPIC"
  printf -- '- Initiator: %s\n' "$AGENT"
  printf -- '- Created: %s\n' "$DATE_H"
  printf -- '- Status: planning\n'
  printf -- '- Project: %s\n' "$PROJECT"
  printf -- '- Purpose: <why this artifact exists>\n\n'
  cat <<'EOF'
## Context

## Decisions So Far

## Proposed Plan

## Verification Plan

## Risks

## Reviewer Questions

## Follow-up Expectations
EOF
} > "$PLAN"

{
  printf '# %s Progress: %s\n\n' "$AGENT" "$TOPIC"
  printf -- '- Author: %s\n' "$AGENT"
  printf -- '- Created: %s\n' "$DATE_H"
  printf -- '- Related plan: `%s`\n' "$(basename "$PLAN")"
  printf -- '- Status: not-started\n\n'
  cat <<'EOF'
## Timeline

## Work Completed

## Verification

## Files Created Or Changed

## Open Questions

## Next Agent Instructions
EOF
} > "$PROGRESS"

echo "생성: $DIR"
echo "  - $PLAN"
echo "  - $PROGRESS"
echo "  - $DIR/turns/"
echo "다음: new-turn.sh \"$DIR\" $AGENT $TOPIC initiator --phase planning"
