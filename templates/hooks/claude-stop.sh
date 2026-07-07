#!/bin/sh
# Claude Code Stop 훅 — 턴 종료 시 저널 위생 점검 (Claude 참여자에만 적용).
# active 로 방치된 턴 파일이 있으면 리마인더. "Hook = 필수 작업 자동 실행" 원칙.
#
# 기본은 advisory (stderr 로 안내, stop 허용). AGENT_SHARE_STOP_STRICT=1 이면 stop 을 막고
# 상태 갱신을 유도한다. 무한 루프 방지: stop_hook_active=true 면 무조건 통과.
#
# 등록 (~/.claude/settings.json 또는 프로젝트 .claude/settings.json):
#   { "hooks": { "Stop": [ { "matcher": "",
#       "hooks": [ { "type": "command", "command": "sh templates/hooks/claude-stop.sh" } ] } ] } }
set -eu

payload=$(cat 2>/dev/null || echo "")
# 이미 stop 훅이 한 번 막은 뒤의 재진입이면 통과 (루프 방지)
case "$payload" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac

ROOTS=${AGENT_SHARE_ROOTS:-"agent-share .agent"}
active=""
for f in $(find $ROOTS -path '*/turns/*.md' 2>/dev/null || true); do
  if grep -q '^- Status: active' "$f" 2>/dev/null; then
    active="$active
  - $f"
  fi
done

[ -z "$active" ] && exit 0

msg="저널 위생: active 상태로 남은 턴 파일이 있습니다 (종료 전 complete|waiting-review|waiting-user|blocked 로 갱신):$active"

if [ "${AGENT_SHARE_STOP_STRICT:-0}" = "1" ]; then
  echo "$msg" >&2
  exit 2   # stop 차단 → Claude 가 이어서 상태 갱신
fi
echo "$msg" >&2
exit 0
