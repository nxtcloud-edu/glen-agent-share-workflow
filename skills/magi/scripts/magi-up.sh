#!/usr/bin/env bash
# MAGI 3노드 tmux 기동 — 글로벌 도구 (~/.magi/scripts/magi-up.sh)
#
# cwd의 저장소를 찾아 그 프로젝트의 카스파·멜기오르·발타자르 세션을 띄운다.
# 세션 간 이동은 tmux 기본 기능(`prefix+s`)으로 — 별도 뷰어 세션을 두지 않는다.
#
# 세션명은 main 워크트리 폴더명에서 자동 생성된다 (<프로젝트>-<노드>). 규칙 정의는 lib.sh —
# ping.sh도 같은 파일을 source하므로 한쪽만 어긋날 수 없다.
#
# 기동 명령이 죽으면 세션도 사라진다 (remain-on-exit 미사용) — has-session == 노드 생존을
# 유지해 ping.sh 선검사가 "셸만 남은 빈 세션"을 살아있다고 오판하지 않게 한다.
#
# 디렉토리 신뢰 프롬프트는 자동 승인한다 — 단 커서가 `1. Yes`일 때만이며(`--no-trust`로 해제),
# 명령 실행 승인 프롬프트에는 응답하지 않는다 (권한 경계).
set -euo pipefail

MAGI_HOME="$(cd "$(dirname "$0")/.." && pwd)"
. "$MAGI_HOME/scripts/lib.sh"

PROJ_ROOT=$(magi_project_root) || { echo "❌ git 저장소가 아니다 — 프로젝트 폴더에서 실행하라"; exit 1; }
PROJ=$(basename "$PROJ_ROOT")
NODES=$(magi_nodes "$PROJ_ROOT")

usage() {
  cat <<EOF
사용법: magi [노드...] [옵션]     (프로젝트: $PROJ)

  노드      claude | hermes | codex   (생략 시 3노드 전부)
  --restart 이미 떠 있는 세션을 죽이고 다시 띄운다
  --status  기동하지 않고 현재 세션 상태만 출력
  --attach  기동을 마치면 카스파 세션에 붙는다 (터미널 진입점 기본값)
  --no-trust 디렉토리 신뢰 프롬프트 자동 승인을 끈다

세션: $(magi_session "$PROJ" claude) / $(magi_session "$PROJ" hermes) / $(magi_session "$PROJ" codex)
이동: prefix+s (세션 목록) · prefix+( ) (이전·다음)
EOF
  exit 1
}

TARGETS=""; RESTART=0; STATUS_ONLY=0; NO_TRUST=0; ATTACH=0

for arg in "$@"; do
  case "$arg" in
    claude|hermes|codex) TARGETS="$TARGETS $arg";;
    --restart)  RESTART=1;;
    --status)   STATUS_ONLY=1;;
    --no-trust) NO_TRUST=1;;
    --attach)   ATTACH=1;;
    -h|--help)  usage;;
    *) echo "❌ 알 수 없는 인자: $arg"; usage;;
  esac
done
[ -n "$TARGETS" ] || TARGETS="claude hermes codex"

wants() { case " $TARGETS " in *" $1 "*) return 0;; *) return 1;; esac; }

# tmux 안에서 실행됐는지 — 그렇다면 현재 세션을 카스파 슬롯으로 인계한다
SELF_SESSION=""
if [ -n "${TMUX:-}" ]; then
  SELF_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
fi

# 디렉토리 신뢰 프롬프트만 자동 승인한다. 두 조건을 AND로 요구해 범위를 좁힌다:
#   ① "Do you trust" 질문 문구 — 명령 실행 승인 프롬프트는 이 문구를 쓰지 않는다
#   ② 선택 커서(›/❯)가 "1. Yes, continue|proceed" 줄에 놓여 있음
# ②가 핵심 안전장치다. 커서가 "2. No, quit"에 있는데 Enter를 보내면 노드를 종료시킨다.
# capture-pane에 `-S`(스크롤백)를 주면 안 된다 — 지나간 프롬프트가 히스토리에 남아 오판된다.
auto_trust() {
  local SESSION="$1" KOR="$2" TRIES=0 PANE
  local YES_CURSOR='(›|❯|>)[[:space:]]*1\.[[:space:]]*Yes,[[:space:]]*(continue|proceed)'
  while [ $TRIES -lt 4 ]; do
    PANE=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null || true)
    if echo "$PANE" | grep -qi 'do you trust' && echo "$PANE" | grep -qiE "$YES_CURSOR"; then
      tmux send-keys -t "$SESSION" C-m
      sleep 2
      PANE=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null || true)
      if echo "$PANE" | grep -qi 'do you trust'; then
        echo "  ⚠️  $KOR: 신뢰 프롬프트 자동 승인 실패 — 어태치해 직접 응답하라"
        return 1
      fi
      echo "  🔓 $KOR: 디렉토리 신뢰 프롬프트 자동 승인"
      return 0
    fi
    TRIES=$((TRIES + 1)); sleep 1
  done
  return 0
}

# ── 1. 상태 실측 ────────────────────────────────────────────────
echo "── MAGI 노드 상태 — $PROJ (tmux $(tmux -V 2>/dev/null | cut -d' ' -f2 || echo '미기동'))"
echo "$NODES" | while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(magi_field "$LINE" 1); WT=$(magi_field "$LINE" 2); KOR=$(magi_field "$LINE" 3)
  SESSION=$(magi_session "$PROJ" "$KEY")
  if tmux has-session -t "$SESSION" 2>/dev/null; then STATE="🟢 실행 중"
  elif [ ! -d "$WT" ]; then STATE="⛔ 워크트리 없음"
  else STATE="⚪ 정지"; fi
  # 한글·이모지는 폭≠바이트라 printf 정렬이 밀린다 → 고정폭 필드는 ASCII만
  BR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')
  printf '  %-28s %-26s %s\n' "$SESSION" "$BR" "$STATE ($KOR)"
done

if [ "$STATUS_ONLY" = "1" ]; then
  echo
  echo "이동: prefix+s (세션 목록) · tmux attach -t $(magi_session "$PROJ" claude)"
  exit 0
fi

# ── 2. 노드 기동 ────────────────────────────────────────────────
echo
echo "── 기동 대상: $TARGETS"
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(magi_field "$LINE" 1); WT=$(magi_field "$LINE" 2)
  KOR=$(magi_field "$LINE" 3); CMD=$(magi_field "$LINE" 4)
  SESSION=$(magi_session "$PROJ" "$KEY")

  wants "$KEY" || continue

  if [ ! -d "$WT" ]; then
    echo "⛔ $KOR: 워크트리 없음 ($WT) — 건너뜀 (`magi init`으로 생성)"
    continue
  fi

  # 카스파 슬롯 인계 — tmux 안에서 돌고 있다면 그 세션이 곧 카스파다 (인스턴스 중복 방지)
  if [ "$KEY" = "claude" ] && [ -n "$SELF_SESSION" ] && [ "$RESTART" != "1" ]; then
    if [ "$SELF_SESSION" = "$SESSION" ]; then
      echo "🏠 $KOR: 현재 세션($SESSION)이 카스파 — 그대로 사용"; continue
    elif tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "⚠️  $KOR: 현재 세션은 '$SELF_SESSION'인데 별도 '$SESSION'가 이미 떠 있다 (중복)."
      echo "     역핑 타겟은 '$SESSION' 하나뿐 — 현재 세션을 쓰려면: tmux kill-session -t $SESSION"
      continue
    else
      echo "🏠 $KOR: 현재 세션 '$SELF_SESSION' → '$SESSION'으로 이름 변경 (역핑 타겟 정렬)"
      tmux rename-session -t "$SELF_SESSION" "$SESSION"; continue
    fi
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ "$RESTART" = "1" ]; then
      echo "♻️  $KOR: 기존 세션 종료 후 재기동"; tmux kill-session -t "$SESSION"
    else
      echo "⏭️  $KOR ($SESSION): 이미 실행 중 — 유지 (재기동은 --restart)"; continue
    fi
  fi

  # 선검사 — 잘못된 워크트리·더티 상태로 노드를 띄우는 사고 방지
  echo "▶️  $KOR ($SESSION) ← $WT"
  git -C "$WT" status --short --branch | head -3 | sed 's/^/     /'
  tmux new-session -d -s "$SESSION" -c "$WT" "$CMD"
done <<EOF
$NODES
EOF

sleep 3   # 기동 명령이 즉시 죽었는지 확인할 시간 (TUI 초기화 포함)

# ── 3. 디렉토리 신뢰 프롬프트 자동 승인 ─────────────────────────
if [ "$NO_TRUST" != "1" ]; then
  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    KEY=$(magi_field "$LINE" 1); KOR=$(magi_field "$LINE" 3)
    SESSION=$(magi_session "$PROJ" "$KEY")
    wants "$KEY" || continue
    tmux has-session -t "$SESSION" 2>/dev/null || continue
    auto_trust "$SESSION" "$KOR" || true
  done <<EOF
$NODES
EOF
fi

# ── 4. 기동 결과 실측 (pane 내용) ───────────────────────────────
echo
echo "── pane 실측 (마지막 3줄)"
FAILED=""; BLOCKED=""
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(magi_field "$LINE" 1); WT=$(magi_field "$LINE" 2); KOR=$(magi_field "$LINE" 3)
  SESSION=$(magi_session "$PROJ" "$KEY")
  wants "$KEY" || continue
  [ -d "$WT" ] || continue
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    PANE=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null || true)
    echo "  ✅ $KOR ($SESSION)"
    echo "$PANE" | grep -v '^[[:space:]]*$' | tail -3 | sed 's/^/       /'
    if echo "$PANE" | grep -qi 'do you trust'; then
      BLOCKED="$BLOCKED $KEY"
      echo "       ⏸️  승인 프롬프트 대기 중 — 어태치해 직접 응답 필요"
    fi
  else
    echo "  ❌ $KOR ($SESSION): 기동 직후 세션 소멸 — 명령 실패 추정"
    FAILED="$FAILED $KEY"
  fi
done <<EOF
$NODES
EOF

echo
[ -n "$FAILED" ] && echo "⚠️  실패 노드:$FAILED — 해당 CLI를 워크트리에서 직접 실행해 원인을 확인하라"
[ -n "$BLOCKED" ] && echo "⏸️  승인 대기:$BLOCKED — 응답 전까지 이 노드는 핑을 처리하지 못한다"
echo "이동: prefix+s (세션 목록) · prefix+( ) (이전·다음) · prefix+d (detach, 노드는 계속 살아있다)"

# ── 5. 카스파 세션에 붙기 ───────────────────────────────────────
if [ "$ATTACH" = "1" ]; then
  CASPAR=$(magi_session "$PROJ" claude)
  if tmux has-session -t "$CASPAR" 2>/dev/null; then
    if [ -n "$SELF_SESSION" ]; then
      tmux switch-client -t "$CASPAR"   # 이미 tmux 안 — attach는 nested 경고
    else
      tmux attach -t "$CASPAR"
    fi
  fi
fi
