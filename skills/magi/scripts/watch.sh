#!/usr/bin/env bash
# MAGI 코더 노드 워처 — 글로벌 도구 (~/.magi/scripts/watch.sh)
#
#   watch.sh start|stop|status
#
# 캐스퍼가 유휴여도 코더 노드의 상태 변화를 놓치지 않게 하는 백그라운드 감시자다.
# `magi` 기동 시 자동으로 뜬다 (`magi --no-watch`로 끌 수 있다).
#
# ── 감시 신호 (노드별 독립 — AND 조건 금지, SKILL Gotcha 3) ─────────────────
#   ① 커밋 팁 변화   → 완료 가능성. **주 신호**다 (Gotcha 11: 역핑은 누락된다)
#   ② 세션 소멸      → 노드가 죽었다. 커밋 없이 죽으면 ①로는 영원히 안 잡힌다
#   ③ 승인 대기 감지 → 프롬프트에서 멈춰 있다. 이것도 팁이 안 움직이는 정지 상태다
#
# ②·③이 "커밋 없이 죽는 경우는 폴링으로 안 잡힌다"는 갭을 메운다. 세 신호는 서로
# 독립이며, 하나가 조용해도 나머지는 계속 돈다.
#
# 유휴와 정체를 구분하는 시간 기반 판정은 넣지 않았다 — standby 노드에서 오탐만 낳는다.
# 정지 상태는 ③(입력 대기)으로 잡고, 나머지는 `magi status`로 사람이 실측한다.
set -euo pipefail

MAGI_HOME="$(cd "$(dirname "$0")/.." && pwd)"
. "$MAGI_HOME/scripts/lib.sh"

INTERVAL="${MAGI_WATCH_INTERVAL:-30}"

PROJ_ROOT=$(magi_project_root) || { echo "❌ git 저장소가 아니다"; exit 1; }
PROJ=$(basename "$PROJ_ROOT")
# lease.sh와 같은 자리 — 모든 워크트리가 같은 상태를 본다
STATE_DIR="$(git -C "$PROJ_ROOT" rev-parse --git-common-dir)/magi-watch"
PID_FILE="$STATE_DIR/pid"
LOG_FILE="$STATE_DIR/log"

CASPAR=$(magi_session "$PROJ" claude)

notify() {  # $1=요지
  local msg="[MAGI 워처 | $(date '+%m-%d %H:%M')] $1"
  echo "$msg" >> "$LOG_FILE"
  # 캐스퍼가 살아 있을 때만 깨운다. 핑과 같은 규약 — wake-up 신호일 뿐,
  # 지시가 아니다. 캐스퍼는 깨어나면 저널·팁·pane을 직접 실측한다.
  if tmux has-session -t "$CASPAR" 2>/dev/null; then
    tmux send-keys -t "$CASPAR" -l "$msg — 저널·팁 실측으로 확인하라"
    sleep 1
    tmux send-keys -t "$CASPAR" C-m
  fi
}

loop() {
  local line key wt kor session tip prev pane
  # 시작 시점의 팁을 기준선으로 잡는다 — 과거 커밋을 완료로 오인하지 않기 위해
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=$(magi_field "$line" 1); wt=$(magi_field "$line" 2)
    [ "$key" = "claude" ] && continue
    [ -d "$wt" ] || continue
    git -C "$wt" rev-parse HEAD 2>/dev/null > "$STATE_DIR/$key.tip" || true
    tmux has-session -t "$(magi_session "$PROJ" "$key")" 2>/dev/null \
      && echo alive > "$STATE_DIR/$key.alive" || rm -f "$STATE_DIR/$key.alive"
  done <<EOF
$(magi_nodes "$PROJ_ROOT")
EOF

  while :; do
    sleep "$INTERVAL"
    # 캐스퍼가 사라지면 알릴 대상이 없다 — 워처도 물러난다
    tmux has-session -t "$CASPAR" 2>/dev/null || { echo "[워처] 캐스퍼 세션 소멸 — 종료" >> "$LOG_FILE"; break; }

    while IFS= read -r line; do
      [ -n "$line" ] || continue
      key=$(magi_field "$line" 1); wt=$(magi_field "$line" 2); kor=$(magi_field "$line" 3)
      [ "$key" = "claude" ] && continue
      [ -d "$wt" ] || continue
      session=$(magi_session "$PROJ" "$key")

      # ① 커밋 팁 변화 — 주 신호
      tip=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")
      prev=$(cat "$STATE_DIR/$key.tip" 2>/dev/null || echo "")
      if [ -n "$tip" ] && [ -n "$prev" ] && [ "$tip" != "$prev" ]; then
        echo "$tip" > "$STATE_DIR/$key.tip"
        notify "$kor 커밋 감지 ($(git -C "$wt" rev-parse --abbrev-ref HEAD) → ${tip:0:7})"
        continue
      fi

      # ② 세션 소멸 — 커밋 없이 죽는 경우는 ①로 영원히 안 잡힌다
      if tmux has-session -t "$session" 2>/dev/null; then
        echo alive > "$STATE_DIR/$key.alive"
        # ③ 승인 대기 — 프롬프트에서 멈춘 정지 상태. 스크롤백 금지(Gotcha 12)
        pane=$(tmux capture-pane -p -t "$session" 2>/dev/null || true)
        if echo "$pane" | grep -qiE 'do you trust|allow this|approve\?|\[y/n\]|Press enter to continue'; then
          [ -f "$STATE_DIR/$key.blocked" ] || {
            : > "$STATE_DIR/$key.blocked"
            notify "$kor 입력 대기 중 — 승인 프롬프트에서 정지 (tmux attach -t $session)"
          }
        else
          rm -f "$STATE_DIR/$key.blocked"
        fi
      elif [ -f "$STATE_DIR/$key.alive" ]; then
        rm -f "$STATE_DIR/$key.alive"
        notify "$kor 세션 소멸 — 노드가 죽었다 (magi $key --restart)"
      fi
    done <<EOF
$(magi_nodes "$PROJ_ROOT")
EOF
  done
  rm -f "$PID_FILE"
}

running() { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

case "${1:-status}" in
  start)
    mkdir -p "$STATE_DIR"
    running && { echo "⏭️  워처 이미 실행 중 (pid $(cat "$PID_FILE"))"; exit 0; }
    loop >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo "👁️  워처 시작 — 코더 팁·세션·승인대기 감시 (${INTERVAL}s, pid $!)"
    ;;
  stop)
    running || { echo "워처가 실행 중이 아니다"; exit 0; }
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "🛑 워처 중지"
    ;;
  status)
    if running; then
      echo "👁️  워처 실행 중 (pid $(cat "$PID_FILE"), ${INTERVAL}s 주기)"
    else
      echo "⚪ 워처 정지"
    fi
    [ -f "$LOG_FILE" ] && { echo "── 최근 알림"; tail -5 "$LOG_FILE" | sed 's/^/  /'; }
    ;;
  *) echo "사용법: magi watch start|stop|status"; exit 1;;
esac
