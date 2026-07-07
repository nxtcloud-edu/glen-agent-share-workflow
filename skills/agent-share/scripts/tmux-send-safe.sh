#!/bin/sh
# tmux 안전 전송 — 대상 페인이 유휴(프롬프트)일 때만 send-keys (Gotcha 3 기계화).
# TUI 에이전트는 작업 중 입력을 턴 중단(인터럽트)으로 처리한다. capture-pane 으로
# busy 패턴이 사라진 것을 확인한 뒤에만 전송한다.
#
# 사용: tmux-send-safe.sh <session[:window.pane]> <보낼 텍스트>
#         [--enter] [--busy-regex <re>] [--timeout <sec>] [--interval <sec>] [--dry-run]
#   --enter      전송 후 Enter 키까지 (기본: 텍스트만)
#   --busy-regex 이 정규식이 최근 화면에 있으면 busy 로 간주 (기본: 흔한 스피너/상태 문구)
#   --timeout    유휴 대기 최대 초 (기본 120). 초과 시 exit 1 (여전히 busy)
#   --dry-run    전송하지 않고 idle/busy 판정만 출력
set -eu

TARGET=${1:?tmux 대상 (예: coder 또는 coder:0.0)}
TEXT=${2:?보낼 텍스트}
shift 2

ENTER=0
TIMEOUT=120
INTERVAL=2
DRY=0
# 기본은 ASCII 위주 (로케일 이식성 — 멀티바이트 bracket class 는 일부 grep/C 로케일에서 깨진다).
# 특정 TUI 의 스피너 문자를 잡으려면 --busy-regex 로 덮어쓸 것.
BUSY_RE='esc to interrupt|Esc to interrupt|Thinking|Working|Computing|Generating|Running|Compiling|Processing'
while [ $# -gt 0 ]; do
  case "$1" in
    --enter) ENTER=1; shift ;;
    --busy-regex) BUSY_RE=${2:?}; shift 2 ;;
    --timeout) TIMEOUT=${2:?}; shift 2 ;;
    --interval) INTERVAL=${2:?}; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

command -v tmux >/dev/null || { echo "tmux 없음" >&2; exit 2; }
tmux has-session -t "${TARGET%%:*}" 2>/dev/null || { echo "세션 없음: ${TARGET%%:*}" >&2; exit 2; }

is_busy() {
  # 보이는 화면 전체를 검사 — capture-pane 은 스크롤백이 아닌 현재 화면만 반환하고,
  # 하단을 빈 줄로 패딩하므로 tail 로 자르면 스피너를 놓친다.
  tmux capture-pane -t "$TARGET" -p 2>/dev/null | grep -Eq "$BUSY_RE"
}

if [ "$DRY" -eq 1 ]; then
  if is_busy; then echo "busy"; exit 1; else echo "idle"; exit 0; fi
fi

waited=0
while is_busy; do
  if [ "$waited" -ge "$TIMEOUT" ]; then
    echo "타임아웃(${TIMEOUT}s): 여전히 busy — 전송 안 함" >&2
    exit 1
  fi
  sleep "$INTERVAL"
  waited=$((waited + INTERVAL))
done

# 유휴 확인됨 — 텍스트 전송. 텍스트와 Enter 를 분리해 우발적 조기 실행 방지.
tmux send-keys -t "$TARGET" -l "$TEXT"
[ "$ENTER" -eq 1 ] && tmux send-keys -t "$TARGET" Enter
echo "전송 완료(${waited}s 대기): $TARGET"
