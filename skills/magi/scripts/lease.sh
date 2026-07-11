#!/usr/bin/env bash
# MAGI 공유 자원 lease (헌장 §7.5 lock registry)
# 저장 위치: $(git rev-parse --git-common-dir)/magi-locks/ — 모든 워크트리가 실제로 보는 비추적 공용 위치.
# 원자성: mkdir은 원자적이므로 동시 acquire 중 하나만 성공한다.
# 자원 이름 예: supabase-local, e2e-port-3111, main-branch
set -euo pipefail

LOCK_ROOT="$(git rev-parse --git-common-dir)/magi-locks"
STALE_HOURS=4

usage() { echo "사용법: lease.sh acquire <자원> <소유자> [WO] | release <자원> <소유자> | status"; exit 1; }

# stale 판정은 시간 기준만 — 에이전트 lease는 acquire한 셸이 종료해도 작업이 계속되므로
# PID 생존 검사를 쓰면 모든 lease가 즉시 stale이 된다 (2026-07-11 실측 버그). PID는 기록용.
is_stale() { # $1=lock dir → stale이면 0
  local ts now age
  ts=$(cut -d'|' -f5 "$1/info" 2>/dev/null) || return 1
  now=$(date +%s); age=$(( (now - ts) / 3600 ))
  [ "$age" -ge "$STALE_HOURS" ]
}

acquire() {
  local res="$1" owner="$2" wo="${3:-}" dir="$LOCK_ROOT/$1"
  mkdir -p "$LOCK_ROOT"
  if [ -d "$dir" ] && is_stale "$dir"; then
    echo "⚠️  stale lease 회수: $(cat "$dir/info")" >&2
    rm -rf "$dir"
  fi
  if mkdir "$dir" 2>/dev/null; then
    echo "$owner|$$|$(git branch --show-current 2>/dev/null || echo '-')|$wo|$(date +%s)|$(date '+%Y-%m-%d %H:%M %Z')" > "$dir/info"
    echo "✅ lease 획득: $res ← $owner"
  else
    echo "❌ 사용 중: $res — $(cat "$dir/info" 2>/dev/null)"; exit 2
  fi
}

release() {
  local res="$1" owner="$2" dir="$LOCK_ROOT/$1"
  [ -d "$dir" ] || { echo "lease 없음: $res"; exit 0; }
  local holder; holder=$(cut -d'|' -f1 "$dir/info" 2>/dev/null || echo '?')
  [ "$holder" = "$owner" ] || { echo "❌ 소유자 불일치: $holder 가 보유 중"; exit 2; }
  rm -rf "$dir" && echo "✅ lease 해제: $res"
}

status() {
  mkdir -p "$LOCK_ROOT"
  local found=0
  for dir in "$LOCK_ROOT"/*/; do
    [ -d "$dir" ] || continue; found=1
    local mark=""; is_stale "$dir" && mark=" [STALE]"
    echo "$(basename "$dir")$mark — $(cat "$dir/info" 2>/dev/null)"
  done
  [ "$found" -eq 1 ] || echo "활성 lease 없음"
}

case "${1:-}" in
  acquire) [ $# -ge 3 ] || usage; acquire "$2" "$3" "${4:-}";;
  release) [ $# -ge 3 ] || usage; release "$2" "$3";;
  status)  status;;
  *) usage;;
esac
