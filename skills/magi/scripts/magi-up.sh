#!/usr/bin/env bash
# MAGI 3노드 tmux 기동 wrapper (일반화판 — 배치 시 아래 NODES 표를 채운다)
#
# 카스파·멜기오르·발타자르 세션 3개를 띄운다. 세션 간 이동은 tmux 기본 기능으로 한다
# (`prefix+s` 세션 목록 / `prefix+(`·`prefix+)` 이전·다음) — 별도 뷰어 세션을 두지 않는다.
#
# ⚠️ 세션명은 **main 워크트리 폴더명에서 자동 생성**한다: <프로젝트>-<노드>
#      예: myproj-claude / myproj-hermes / myproj-codex
#    tmux 세션 공간은 머신 전역이라, 프로젝트명을 접두로 쓰면 충돌이 구조적으로 사라진다.
#    손으로 접두를 정하지 마라 — 프로젝트가 늘 때마다 같은 실수를 반복하게 된다.
#    `ping.sh`가 **같은 규칙**으로 세션명을 계산한다 — 규칙을 바꾸면 양쪽을 함께 고쳐라.
#
# 배치: 이 파일을 프로젝트의 `.magi/scripts/`에 두고 NODES의 워크트리·기동 명령을 채운다.
# 진입점은 alias가 아니라 cwd 기반 셸 함수로 건다 (SKILL §6).
#
# 기동 명령이 죽으면 세션도 사라진다 (remain-on-exit 미사용) — has-session == 노드 생존을
# 유지해 ping.sh 선검사가 "셸만 남은 빈 세션"을 살아있다고 오판하지 않게 한다.
#
# 디렉토리 신뢰 프롬프트는 자동 승인한다. config에 워크트리 경로를 등록하는 방식은 워크트리·
# 프로젝트가 늘 때마다 반복되는 땜질이라 채택하지 않았다. 자동 승인 범위는 "이 디렉토리를
# 신뢰하는가"로 한정 — 명령 실행 승인 프롬프트에는 응답하지 않는다(§7.2 권한 경계). `--no-trust`로 해제.
set -euo pipefail

# ── 프로젝트 식별 (세션명 접두) ─────────────────────────────────
# 이 스크립트는 main 워크트리에 있다 → 두 단계 위가 프로젝트 루트.
PROJ_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROJ=$(basename "$PROJ_ROOT")
WT_PARENT=$(dirname "$PROJ_ROOT")

# ▼▼ 배치 시 채운다 — key | 워크트리 | 코드명 | 기동 명령 (마지막 필드, `|` 사용 불가) ▼▼
#
# - key: CLI 인자로 쓸 짧은 이름 (`magi-up.sh hermes --restart`). 세션명은 "$PROJ-<key>" 자동 생성.
# - 카스파 행의 key는 `claude`로 둔다 — 아래 "카스파 슬롯 인계" 분기가 이 key를 본다
#   (오케스트레이터가 다른 하네스면 key와 그 분기를 함께 고친다).
# - 워크트리 경로는 관례($PROJ-<노드>)를 쓰되, 다르면 절대경로로 직접 적는다.
# - 기동 명령: 그 노드의 CLI를 인터랙티브로 띄우는 명령 원문. 샌드박스형은 프로필 플래그까지.
NODES="
claude|$PROJ_ROOT|카스파|<오케스트레이터 CLI 기동 명령>
hermes|$WT_PARENT/$PROJ-hermes|멜기오르|<주 구현 CLI 기동 명령>
codex|$WT_PARENT/$PROJ-codex-cli|발타자르|<독립 반증 CLI 기동 명령>
"
# ▲▲ 배치 시 채운다 ▲▲

session_of() { echo "$PROJ-$1"; }

usage() {
  cat <<EOF
사용법: magi-up.sh [노드...] [옵션]     (프로젝트: $PROJ)

  노드      claude | hermes | codex   (생략 시 3노드 전부)
  --restart 이미 떠 있는 세션을 죽이고 다시 띄운다
  --status  기동하지 않고 현재 세션 상태만 출력
  --attach  기동을 마치면 카스파 세션에 붙는다 (터미널 진입점용)
  --no-trust 디렉토리 신뢰 프롬프트 자동 승인을 끈다 (기본: 자동 승인)

세션: $(session_of claude) / $(session_of hermes) / $(session_of codex)
이동: prefix+s (세션 목록) · prefix+( ) (이전·다음)
EOF
  exit 1
}

TARGETS=""
RESTART=0
STATUS_ONLY=0
NO_TRUST=0
# 기본 0 — 슬래시 명령어(/magi-up)로 부를 때 attach가 실행되면 Claude Code의 Bash가 붙잡힌다.
# 터미널 진입점(셸 함수 magi)에서만 켠다.
ATTACH=0

# tmux 안에서 실행됐는지 — 그렇다면 현재 세션을 카스파 슬롯으로 인계한다 (아래 기동 루프 참고)
SELF_SESSION=""
if [ -n "${TMUX:-}" ]; then
  SELF_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
fi

# 디렉토리 신뢰 프롬프트만 자동 승인한다.
# 두 조건을 AND로 요구해 범위를 좁힌다:
#   ① "Do you trust" 질문 문구 — 명령 실행 승인 프롬프트는 이 문구를 쓰지 않는다
#   ② 선택 커서(›/❯)가 "1. Yes, continue|proceed" 줄에 놓여 있음
# ②가 핵심 안전장치다. 커서가 "2. No, quit"에 있는데 Enter를 보내면 노드를 종료시킨다.
#
# capture-pane에 `-S`(스크롤백)를 주면 안 된다 — 이미 승인돼 지나간 프롬프트 텍스트가
# 히스토리에 남아 "아직 대기 중"으로 오인된다 (SKILL Gotcha 14).
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
    TRIES=$((TRIES + 1))
    sleep 1
  done
  return 0
}

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

node_field() { echo "$1" | cut -d'|' -f"$2"; }

wants() {
  case " $TARGETS " in *" $1 "*) return 0;; *) return 1;; esac
}

# ── 1. 상태 실측 ────────────────────────────────────────────────
echo "── MAGI 노드 상태 — $PROJ (tmux $(tmux -V 2>/dev/null | cut -d' ' -f2 || echo '미기동'))"
echo "$NODES" | while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); WT=$(node_field "$LINE" 2); KOR=$(node_field "$LINE" 3)
  SESSION=$(session_of "$KEY")
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    STATE="🟢 실행 중"
  elif [ ! -d "$WT" ]; then
    STATE="⛔ 워크트리 없음"
  else
    STATE="⚪ 정지"
  fi
  # 한글·이모지는 폭≠바이트라 printf 정렬이 밀린다 → 고정폭 필드는 ASCII만, 나머지는 뒤로
  BR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')
  printf '  %-26s %-26s %s\n' "$SESSION" "$BR" "$STATE ($KOR)"
done

if [ "$STATUS_ONLY" = "1" ]; then
  echo
  echo "이동: prefix+s (세션 목록) · tmux attach -t $(session_of claude)"
  exit 0
fi

# ── 2. 노드 기동 ────────────────────────────────────────────────
echo
echo "── 기동 대상: $TARGETS"
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); WT=$(node_field "$LINE" 2)
  KOR=$(node_field "$LINE" 3); CMD=$(node_field "$LINE" 4)
  SESSION=$(session_of "$KEY")

  wants "$KEY" || continue

  if [ ! -d "$WT" ]; then
    echo "⛔ $KOR: 워크트리 없음 ($WT) — 건너뜀"
    continue
  fi

  # 카스파 슬롯 인계 — 이 스크립트가 tmux 안에서 돌고 있다면(= 오케스트레이터 CLI를 tmux로
  # 먼저 열고 그 안에서 실행) 그 세션이 곧 카스파다. 새로 띄우면 인스턴스가 중복된다.
  if [ "$KEY" = "claude" ] && [ -n "$SELF_SESSION" ] && [ "$RESTART" != "1" ]; then
    if [ "$SELF_SESSION" = "$SESSION" ]; then
      echo "🏠 $KOR: 현재 세션($SESSION)이 카스파 — 그대로 사용"
      continue
    elif tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "⚠️  $KOR: 현재 세션은 '$SELF_SESSION'인데 별도 '$SESSION'가 이미 떠 있다 (중복)."
      echo "     역핑 타겟은 '$SESSION' 하나뿐이다 — 현재 세션을 카스파로 쓰려면: tmux kill-session -t $SESSION"
      continue
    else
      # ping.sh의 send-keys 타겟과 이름을 맞춘다 — 이름이 다르면 역핑이 이 세션에 닿지 않는다
      echo "🏠 $KOR: 현재 세션 '$SELF_SESSION' → '$SESSION'으로 이름 변경 (역핑 타겟 정렬)"
      tmux rename-session -t "$SELF_SESSION" "$SESSION"
      continue
    fi
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ "$RESTART" = "1" ]; then
      echo "♻️  $KOR: 기존 세션 종료 후 재기동"
      tmux kill-session -t "$SESSION"
    else
      echo "⏭️  $KOR ($SESSION): 이미 실행 중 — 유지 (재기동은 --restart)"
      continue
    fi
  fi

  # 선검사 — 잘못된 워크트리·더티 상태로 노드를 띄우는 사고 방지 (ping.sh와 동일 규율)
  echo "▶️  $KOR ($SESSION) ← $WT"
  git -C "$WT" status --short --branch | head -3 | sed 's/^/     /'

  tmux new-session -d -s "$SESSION" -c "$WT" "$CMD"
done <<EOF
$NODES
EOF

# 기동 명령이 즉시 죽었는지 확인할 시간 (TUI 초기화 포함)
sleep 3

# ── 3. 디렉토리 신뢰 프롬프트 자동 승인 ─────────────────────────
if [ "$NO_TRUST" != "1" ]; then
  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    KEY=$(node_field "$LINE" 1); KOR=$(node_field "$LINE" 3)
    SESSION=$(session_of "$KEY")
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
FAILED=""
BLOCKED=""
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); KOR=$(node_field "$LINE" 3)
  SESSION=$(session_of "$KEY")
  wants "$KEY" || continue
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    # 스크롤백 금지 — 지나간 프롬프트 잔상을 현재 상태로 오인한다 (auto_trust 주석 참고)
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
if [ -n "$FAILED" ]; then
  echo "⚠️  실패 노드:$FAILED — 해당 CLI를 워크트리에서 직접 실행해 원인을 확인하라"
fi
if [ -n "$BLOCKED" ]; then
  echo "⏸️  승인 대기:$BLOCKED — 어태치해서 응답하기 전까지 이 노드는 핑을 처리하지 못한다"
fi
echo "세션: $(session_of claude) · $(session_of hermes) · $(session_of codex)"
echo "  이동: prefix+s (세션 목록) · prefix+( ) (이전·다음) · prefix+d (detach, 노드는 계속 살아있다)"

# ── 5. 카스파 세션에 붙기 (터미널 진입점 모드) ──────────────────
if [ "$ATTACH" = "1" ]; then
  CASPAR=$(session_of claude)
  if tmux has-session -t "$CASPAR" 2>/dev/null; then
    if [ -n "$SELF_SESSION" ]; then
      tmux switch-client -t "$CASPAR"   # 이미 tmux 안 — attach는 nested 경고
    else
      tmux attach -t "$CASPAR"
    fi
  fi
fi
