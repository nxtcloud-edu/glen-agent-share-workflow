#!/bin/sh
# 완료 신호 워처 — Coder 워크트리에서 "새 커밋 + TURN_LOG 기록" 복합 조건 감지.
# 주의: 상태 줄(명령서의 '상태:') 단독 감시는 조기 신호가 난다 — 반드시 복합 조건으로 (Gotcha 1).
#
# 사용: watcher.sh <coder-워크트리-경로> <저널 식별자> [--tmux <session>]
#         [--stall-regex <re>] [--journal <상대경로>] [--interval <sec>]
#   예: watcher.sh ../repo-coder "Coder — WO-012" --tmux coder
#
# --tmux 를 주면 capture-pane 으로 정체 패턴(위험 명령 승인 타임아웃 등)도 감시한다.
# 워처는 커밋이 없으면 차단을 못 보므로(Gotcha 6), tmux 화면에서 직접 잡는다.
set -eu

W=${1:?워크트리 경로}
SIG=${2:?저널 식별자 (완료 헤더 안의 문구, 예: "hermes (Coder) — WO-012")}
shift 2

TMUX_SESSION=""
JOURNAL_REL=".agent/TURN_LOG.md"
INTERVAL=30
# ASCII 위주 기본 (로케일 이식성). 'Timeout' 만으로 "⏱ Timeout — denying command" 를 잡는다.
STALL_RE='Timeout|denying command|User denied|awaiting approval|승인 대기'
while [ $# -gt 0 ]; do
  case "$1" in
    --tmux) TMUX_SESSION=${2:?}; shift 2 ;;
    --stall-regex) STALL_RE=${2:?}; shift 2 ;;
    --journal) JOURNAL_REL=${2:?}; shift 2 ;;
    --interval) INTERVAL=${2:?}; shift 2 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

LOG="$W/$JOURNAL_REL"
BASE=$(git -C "$W" log -1 --format=%H 2>/dev/null || echo "")
echo "워처 시작: $W (신호='$SIG'${TMUX_SESSION:+, tmux=$TMUX_SESSION})"

while true; do
  # 완료: 새 커밋 + 저널 기록 (복합 조건)
  # 매치는 2단계 — (1) 완료 헤더 라인(^## …)만 추린 뒤 (2) 식별자를 고정문자열로.
  # 느슨한 매치는 플래너의 발행/핸드오프 문구까지 잡아 조기 완료로 오탐하고(Gotcha 9, WO-008),
  # 식별자에 든 괄호 등 정규식 메타문자는 -F 로 리터럴 처리(예: "hermes (Coder) — WO-012").
  CUR=$(git -C "$W" log -1 --format=%H 2>/dev/null || echo "")
  if [ -n "$CUR" ] && [ "$CUR" != "$BASE" ] \
     && grep '^## ' "$LOG" 2>/dev/null | grep -qF -- "$SIG"; then
    echo "완료 신호: $(git -C "$W" log -1 --oneline)"; exit 0
  fi
  if [ -n "$CUR" ] && [ "$CUR" != "$BASE" ]; then
    echo "커밋 감지(저널 대기): $(git -C "$W" log -1 --oneline)"; BASE="$CUR"
  fi

  # 정체: tmux 화면에서 위험 명령 승인 타임아웃 등 (커밋이 없어 워처가 놓치는 차단)
  if [ -n "$TMUX_SESSION" ] && command -v tmux >/dev/null 2>&1; then
    # 보이는 화면 전체 검사 (capture-pane 은 하단을 빈 줄로 패딩 — tail 은 놓친다)
    if tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | grep -Eq "$STALL_RE"; then
      echo "정체 감지: '$TMUX_SESSION' 화면에 승인 대기/거부 패턴 — 사람 개입 필요 (tmux attach)" >&2
      exit 2
    fi
  fi

  sleep "$INTERVAL"
done
