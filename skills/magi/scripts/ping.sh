#!/usr/bin/env bash
# MAGI tmux 핑 wrapper (헌장 §7.4·§7.5)
# 원칙: tmux 핑은 "문서를 읽으라"는 wake-up 신호만 — 결정·명령·승인은 Git 문서(SSOT)에 먼저 쓴다.
# 선검사: 세션 존재, 대상 워크트리의 branch·clean 여부를 출력해 잘못된 대상 전송을 막는다.
set -euo pipefail

usage() { echo "사용법: ping.sh <세션 — 코더 노드 또는 오케스트레이터> <메시지>"; exit 1; }
[ $# -ge 2 ] || usage
SESSION="$1"; shift; MSG="$*"

# ▼ 배치 시 프로젝트의 세션→워크트리 매핑을 채운다.
#   오케스트레이터 세션(예: claude)도 등록하면 코더 노드가 턴 완료 시 오케스트레이터를
#   깨우는 **역방향 핑**이 된다 — 오케스트레이터의 폴링을 대체 (goods-bank 실증).
case "$SESSION" in
  # <코더 세션명>)        WT="<워크트리 절대경로>";;
  # <오케스트레이터 세션명>) WT="<main 워크트리 절대경로>";;
  *) echo "❌ 미등록 세션: $SESSION — 스크립트 상단 case문에 매핑을 추가하라"; exit 2;;
esac

# stderr를 삼키면 샌드박스의 소켓 접근 거부가 "세션 없음"으로 오진된다 — 원문을 보존해 출력.
TMUX_ERR=$(tmux has-session -t "$SESSION" 2>&1) || { echo "❌ tmux 세션 접근 실패($SESSION): ${TMUX_ERR:-세션 없음}"; exit 2; }

echo "── 선검사: $SESSION → $WT"
git -C "$WT" status --short --branch | head -3
BASE=$(git -C "$WT" rev-parse --short HEAD)
echo "── base SHA: $BASE"

ENVELOPE="[MAGI ping → $SESSION | base=$BASE | $(date '+%m-%d %H:%M')] $MSG"
tmux send-keys -t "$SESSION" -l "$ENVELOPE"
sleep 1
tmux send-keys -t "$SESSION" C-m
echo "✅ 전송 완료 (${#ENVELOPE}자)"
