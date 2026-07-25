#!/usr/bin/env bash
# MAGI 3노드 tmux 기동 wrapper (일반화판 — 배치 시 아래 NODES 표를 채운다)
#
# 카스파·멜기오르·발타자르 세션을 한 번에 띄우고 통합 뷰어 세션에 3개 윈도우로 링크한다
# → 어태치 한 번으로 prefix+1/2/3 전환. 빈 터미널 진입점은 `--attach`.
#
# ⚠️ 세션명은 ping.sh의 send-keys 타겟과 **동일해야 한다** — 바꾸면 노드 간 핑이 조용히 깨진다
#    (SKILL §2). 프로젝트가 여럿이면 접두를 붙여 충돌을 피하라 (예: `<proj>-claude`).
#
# 기동 명령이 죽으면 세션도 사라진다 (remain-on-exit 미사용) — has-session == 노드 생존을
# 유지해 ping.sh 선검사가 "셸만 남은 빈 세션"을 살아있다고 오판하지 않게 한다.
#
# 디렉토리 신뢰 프롬프트는 자동 승인한다. config에 워크트리 경로를 등록하는 방식은 워크트리·
# 프로젝트가 늘 때마다 반복되는 땜질이라 채택하지 않았다. 자동 승인 범위는 "이 디렉토리를
# 신뢰하는가"로 한정 — 명령 실행 승인 프롬프트에는 응답하지 않는다(권한 경계). `--no-trust`로 해제.
set -euo pipefail

# ▼▼ 배치 시 채운다 ▼▼
PROJ_ROOT="<워크트리들이 있는 상위 디렉토리 절대경로>"   # 예: "$HOME/projects"
# ⚠️ 세션명은 전부 프로젝트 접두를 붙인다 — tmux 세션은 머신 전역이라, 여러 프로젝트가
#    `magi` 같은 공용 이름을 쓰면 서로의 세션을 붙잡는다. 아래 NODES의 세션명도 마찬가지.
VIEW_SESSION="<프로젝트접두>-magi"                       # 통합 뷰어 세션명

# key | tmux 세션 | 워크트리 | 윈도우명 | 코드명 | 기동 명령 (마지막 필드, `|` 문자 사용 불가)
#
# - key: CLI 인자로 쓸 짧은 이름 (`magi-up.sh hermes --restart`)
# - 기동 명령: 그 노드의 CLI를 인터랙티브로 띄우는 명령 원문. 샌드박스형 노드는 프로필 플래그까지.
# - 카스파 행의 key는 반드시 `claude`로 둔다 — 아래 "카스파 슬롯 인계" 로직이 이 key를 본다.
#   (오케스트레이터가 Claude Code가 아니면 그 하네스 이름으로 바꾸고 인계 분기의 key도 함께 고친다.)
NODES="
claude|<카스파 세션>|$PROJ_ROOT/<main 워크트리>|caspar|카스파|<오케스트레이터 CLI 기동 명령>
hermes|<멜기오르 세션>|$PROJ_ROOT/<구현 워크트리>|melchior|멜기오르|<주 구현 CLI 기동 명령>
codex|<발타자르 세션>|$PROJ_ROOT/<반증 워크트리>|balthasar|발타자르|<독립 반증 CLI 기동 명령>
"
# ▲▲ 배치 시 채운다 ▲▲

usage() {
  cat <<'EOF'
사용법: magi-up.sh [노드...] [옵션]

  노드      claude | hermes | codex   (생략 시 3노드 전부)
  --restart 이미 떠 있는 세션을 죽이고 다시 띄운다
  --status  기동하지 않고 현재 세션 상태만 출력
  --no-view 통합 뷰어 세션(magi) 링크를 건너뛴다
  --no-trust 디렉토리 신뢰 프롬프트 자동 승인을 끈다 (기본: 자동 승인)
  --attach  기동을 마치면 통합 뷰어 세션에 바로 붙는다 (터미널 진입점용)

예시:
  magi-up.sh                    # 3노드 기동 + magi 뷰어 링크
  magi-up.sh hermes --restart   # 멜기오르만 재기동
  magi-up.sh --status           # 실측만
EOF
  exit 1
}

TARGETS=""
RESTART=0
STATUS_ONLY=0
NO_VIEW=0
NO_TRUST=0
# 기본 0 — 슬래시 명령어(/magi-up)로 부를 때 attach가 실행되면 Claude Code의 Bash가 붙잡힌다.
# 터미널 진입점(alias magi)에서만 켠다.
ATTACH=0

# tmux 안에서 실행됐는지 — 그렇다면 현재 세션을 카스파 슬롯으로 인계한다 (아래 기동 루프 참고)
SELF_SESSION=""
if [ -n "${TMUX:-}" ]; then
  SELF_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
fi

# 디렉토리 신뢰 프롬프트만 자동 승인한다.
# 두 조건을 AND로 요구해 범위를 좁힌다:
#   ① "Do you trust" 질문 문구 — 명령 실행 승인 프롬프트는 이 문구를 쓰지 않는다 (§7.2 권한 경계는 건드리지 않음)
#   ② 선택 커서(›/❯)가 "1. Yes, continue|proceed" 줄에 놓여 있음
# ②가 핵심 안전장치다. 커서가 "2. No, quit"에 있는데 Enter를 보내면 노드를 종료시킨다 —
# 커서 위치를 확인했으므로 Enter 한 번이 곧 승인이고, 숫자 키를 보낼 필요가 없다.
#
# capture-pane에 `-S`(스크롤백)를 주면 안 된다 — 이미 승인돼 지나간 프롬프트 텍스트가
# 히스토리에 남아 "아직 대기 중"으로 오인된다 (실측: 승인 성공했는데 실패로 보고).
# 프롬프트는 언제나 현재 화면에 떠 있으므로 visible screen만 본다.
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
    --no-view)  NO_VIEW=1;;
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
echo "── MAGI 노드 상태 (tmux $(tmux -V 2>/dev/null | cut -d' ' -f2 || echo '미기동'))"
echo "$NODES" | while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); SESSION=$(node_field "$LINE" 2)
  WT=$(node_field "$LINE" 3);  KOR=$(node_field "$LINE" 5)
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    STATE="🟢 실행 중"
  elif [ ! -d "$WT" ]; then
    STATE="⛔ 워크트리 없음"
  else
    STATE="⚪ 정지"
  fi
  # 한글·이모지는 폭≠바이트라 printf 정렬이 밀린다 → 고정폭 필드는 ASCII만, 나머지는 뒤로
  BR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')
  printf '  %-14s %-26s %s\n' "$SESSION" "$BR" "$STATE ($KOR)"
done

if [ "$STATUS_ONLY" = "1" ]; then
  echo
  echo "다음: tmux attach -t $VIEW_SESSION   (뷰어 세션이 있을 때)"
  exit 0
fi

# ── 2. 노드 기동 ────────────────────────────────────────────────
echo
echo "── 기동 대상: $TARGETS"
STARTED=""
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); SESSION=$(node_field "$LINE" 2)
  WT=$(node_field "$LINE" 3);  WIN=$(node_field "$LINE" 4)
  KOR=$(node_field "$LINE" 5); CMD=$(node_field "$LINE" 6)

  wants "$KEY" || continue

  if [ ! -d "$WT" ]; then
    echo "⛔ $KOR: 워크트리 없음 ($WT) — 건너뜀"
    continue
  fi

  # 카스파 슬롯 인계 — 이 스크립트가 tmux 안에서 돌고 있다면(= 사용자가 오케스트레이터 CLI를
  # tmux로 먼저 열고 그 안에서 실행) 그 세션이 곧 카스파다. 새로 띄우면 인스턴스가 중복된다.
  if [ "$KEY" = "claude" ] && [ -n "$SELF_SESSION" ] && [ "$RESTART" != "1" ]; then
    if [ "$SELF_SESSION" = "$SESSION" ]; then
      echo "🏠 $KOR: 현재 세션($SESSION)이 카스파 — 그대로 사용"
      STARTED="$STARTED $KEY"
      continue
    elif tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "⚠️  $KOR: 현재 세션은 '$SELF_SESSION'인데 별도 '$SESSION'가 이미 떠 있다 (Claude 중복)."
      echo "     역핑 타겟은 '$SESSION' 하나뿐이다 — 현재 세션을 카스파로 쓰려면: tmux kill-session -t $SESSION"
      STARTED="$STARTED $KEY"
      continue
    else
      # ping.sh의 send-keys 타겟과 이름을 맞춘다 — 이름이 다르면 역핑이 이 세션에 닿지 않는다
      echo "🏠 $KOR: 현재 세션 '$SELF_SESSION' → '$SESSION'으로 이름 변경 (역핑 타겟 정렬)"
      tmux rename-session -t "$SELF_SESSION" "$SESSION"
      STARTED="$STARTED $KEY"
      continue
    fi
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ "$RESTART" = "1" ]; then
      echo "♻️  $KOR: 기존 세션 종료 후 재기동"
      tmux kill-session -t "$SESSION"
    else
      echo "⏭️  $KOR ($SESSION): 이미 실행 중 — 유지 (재기동은 --restart)"
      STARTED="$STARTED $KEY"
      continue
    fi
  fi

  # 선검사 — 잘못된 워크트리·더티 상태로 노드를 띄우는 사고 방지 (ping.sh와 동일 규율)
  echo "▶️  $KOR ($SESSION) ← $WT"
  git -C "$WT" status --short --branch | head -3 | sed 's/^/     /'

  tmux new-session -d -s "$SESSION" -c "$WT" -n "$WIN" "$CMD"
  tmux set-window-option -t "$SESSION:$WIN" automatic-rename off >/dev/null
  STARTED="$STARTED $KEY"
done <<EOF
$NODES
EOF

# 기동 명령이 즉시 죽었는지 확인할 시간 (TUI 초기화 포함)
sleep 3

# ── 3. 디렉토리 신뢰 프롬프트 자동 승인 ─────────────────────────
if [ "$NO_TRUST" != "1" ]; then
  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    KEY=$(node_field "$LINE" 1); SESSION=$(node_field "$LINE" 2); KOR=$(node_field "$LINE" 5)
    wants "$KEY" || continue
    tmux has-session -t "$SESSION" 2>/dev/null || continue
    auto_trust "$SESSION" "$KOR" || true
  done <<EOF
$NODES
EOF
fi

# ── 4. 통합 뷰어 세션 링크 ──────────────────────────────────────
if [ "$NO_VIEW" != "1" ]; then
  echo
  echo "── 통합 뷰어 세션: $VIEW_SESSION"
  BOOT_ID=""
  if ! tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
    BOOT_ID=$(tmux new-session -d -P -F '#{window_id}' -s "$VIEW_SESSION" -n __bootstrap)
  fi

  IDX=1
  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    SESSION=$(node_field "$LINE" 2); KOR=$(node_field "$LINE" 5)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      # 윈도우 인덱스가 아닌 window_id로 소스를 잡는다 (base-index 설정에 무관)
      SRC=$(tmux list-windows -t "$SESSION" -F '#{window_id}' | head -1)
      CUR=$(tmux display-message -p -t "$VIEW_SESSION:$IDX" '#{window_id}' 2>/dev/null || echo "")
      if [ "$CUR" = "$SRC" ]; then
        # 이미 같은 윈도우가 걸려 있다 — 재링크하면 tmux가 "same index"로 거부한다
        echo "  ✅ $VIEW_SESSION:$IDX ← $SESSION ($KOR) — 링크 유지"
      else
        tmux link-window -d -k -s "$SRC" -t "$VIEW_SESSION:$IDX"
        echo "  🔗 $VIEW_SESSION:$IDX ← $SESSION ($KOR)"
      fi
    else
      echo "  ⚪ $VIEW_SESSION:$IDX — $SESSION 미기동, 링크 생략"
    fi
    IDX=$((IDX + 1))
  done <<EOF
$NODES
EOF

  [ -n "$BOOT_ID" ] && tmux kill-window -t "$BOOT_ID" 2>/dev/null || true
fi

# ── 5. 기동 결과 실측 (pane 내용) ───────────────────────────────
echo
echo "── pane 실측 (마지막 3줄)"
FAILED=""
BLOCKED=""
while IFS= read -r LINE; do
  [ -n "$LINE" ] || continue
  KEY=$(node_field "$LINE" 1); SESSION=$(node_field "$LINE" 2); KOR=$(node_field "$LINE" 5)
  wants "$KEY" || continue
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    # 여기도 스크롤백 금지 — 지나간 프롬프트 잔상을 현재 상태로 오인한다 (auto_trust 주석 참고)
    PANE=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null || true)
    echo "  ✅ $KOR ($SESSION)"
    echo "$PANE" | grep -v '^[[:space:]]*$' | tail -3 | sed 's/^/       /'
    # 자동 승인이 듣지 않은 프롬프트만 남는다 (--no-trust거나 커서가 Yes에 없던 경우).
    if echo "$PANE" | grep -qi 'do you trust'; then
      BLOCKED="$BLOCKED $KEY"
      echo "       ⏸️  승인 프롬프트 대기 중 — tmux attach -t $VIEW_SESSION 후 직접 응답 필요"
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
if [ -n "$SELF_SESSION" ]; then
  # 이미 tmux 안이다 — attach는 nested 경고를 낸다. 클라이언트 전환이 정답.
  echo "다음: tmux switch-client -t $VIEW_SESSION   (지금 tmux '$SELF_SESSION' 안)"
else
  echo "다음: tmux attach -t $VIEW_SESSION"
fi
echo "  prefix+1 카스파 / prefix+2 멜기오르 / prefix+3 발타자르 (prefix 기본 C-b)"
echo "  세션만 개별로: tmux attach -t <세션명>  (세션명은 위 상태표 첫 열)"
echo "  ※ 뷰어에서 detach는 prefix+d — 노드는 계속 살아있다 (종료는 kill-session)"

# ── 6. 뷰어 붙기 (터미널 진입점 모드) ───────────────────────────
if [ "$ATTACH" = "1" ] && [ "$NO_VIEW" != "1" ]; then
  if [ -n "$SELF_SESSION" ]; then
    tmux switch-client -t "$VIEW_SESSION"   # 이미 tmux 안 — attach는 nested 경고
  else
    tmux attach -t "$VIEW_SESSION"
  fi
fi
