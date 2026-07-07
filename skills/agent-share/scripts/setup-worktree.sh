#!/bin/sh
# 코더 워크트리 + 브랜치 게이트 셋업 (full 모드 1회 준비).
# 미검증 코드가 main 에 못 들어오게 하는 물리적 격리를 스크립트로 고정한다.
#
# 하는 일:
#   1) ../<repo>-<agent> 워크트리 + <agent>/idle 브랜치 (없으면 생성)
#   2) 코더 가드 마커(.agent-coder-guard) 를 워크트리에 배치 → 훅이 이 워크트리에서만
#      main 직접 커밋·push 를 차단 (마커 없는 planner 워크트리는 영향 없음)
#   3) --hooks-src 주면 pre-commit·pre-push 를 .githooks/ 에 설치하고 core.hooksPath 설정
#   4) --wo NNN 주면 wo/NNN 브랜치 생성, --install 주면 워크트리에서 설치 명령 실행
#
# 사용: setup-worktree.sh <main-repo> <agent> [--base main] [--wo NNN]
#         [--hooks-src <dir>] [--install "<cmd>"]
set -eu

REPO=${1:?main repo 경로}
AGENT=${2:?coder agent 이름 (예: coder)}
shift 2

BASE=main
WO=""
HOOKS_SRC=""
INSTALL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=${2:?}; shift 2 ;;
    --wo) WO=${2:?}; shift 2 ;;
    --hooks-src) HOOKS_SRC=${2:?}; shift 2 ;;
    --install) INSTALL=${2:?}; shift 2 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "git 저장소 아님: $REPO" >&2; exit 1; }
REPO_ABS=$(cd "$REPO" && pwd)
NAME=$(basename "$REPO_ABS")
WT="$REPO_ABS/../$NAME-$AGENT"

# 1) 워크트리
if git -C "$REPO" worktree list --porcelain | grep -qx "worktree $(cd "$WT" 2>/dev/null && pwd || echo __none__)"; then
  echo "워크트리 존재: $WT"
else
  git -C "$REPO" worktree add "$WT" -b "$AGENT/idle" "$BASE"
  echo "워크트리 생성: $WT ($AGENT/idle)"
fi
WT_ABS=$(cd "$WT" && pwd)

# 2) 코더 가드 마커 + .gitignore
touch "$WT_ABS/.agent-coder-guard"
GI="$REPO_ABS/.gitignore"
if [ ! -f "$GI" ] || ! grep -qx '.agent-coder-guard' "$GI" 2>/dev/null; then
  printf '.agent-coder-guard\n' >> "$GI"
  echo ".gitignore 에 .agent-coder-guard 추가"
fi
echo "코더 가드 마커 배치: $WT_ABS/.agent-coder-guard"

# 3) 훅 설치 (선택)
if [ -n "$HOOKS_SRC" ]; then
  mkdir -p "$REPO_ABS/.githooks"
  for h in pre-commit pre-push; do
    if [ -f "$HOOKS_SRC/$h" ]; then
      cp "$HOOKS_SRC/$h" "$REPO_ABS/.githooks/$h"
      chmod +x "$REPO_ABS/.githooks/$h"
      echo "훅 설치: .githooks/$h"
    fi
  done
  # 절대경로 필수 — 상대경로는 각 워크트리가 자기 루트 기준으로 해석해 훅이 조용히 사라진다 (Gotcha 8)
  git -C "$REPO" config core.hooksPath "$REPO_ABS/.githooks"
  echo "core.hooksPath = $REPO_ABS/.githooks (절대경로 — 모든 워크트리 공유)"
fi

# 4) WO 브랜치 (선택)
if [ -n "$WO" ]; then
  if git -C "$WT" show-ref --verify --quiet "refs/heads/wo/$WO"; then
    echo "브랜치 존재: wo/$WO"
  else
    git -C "$WT" switch -c "wo/$WO" "$BASE"
    echo "브랜치 생성·체크아웃: wo/$WO (워크트리 $WT_ABS)"
  fi
fi

# 5) 설치 명령 (선택)
if [ -n "$INSTALL" ]; then
  echo "설치 명령 실행 ($WT_ABS): $INSTALL"
  ( cd "$WT_ABS" && sh -c "$INSTALL" )
fi

echo "완료. 코더는 이 워크트리의 wo/NNN 에서만 작업 — main 직접 커밋·push 는 훅이 차단."
