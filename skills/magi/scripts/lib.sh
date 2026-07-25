#!/usr/bin/env bash
# MAGI 공통 로직 — 프로젝트 식별과 세션명 규칙.
#
# 이 파일이 세션명의 **단일 정의처**다. magi-up.sh(기동)와 ping.sh(핑)가 둘 다 여기를
# source하므로, 규칙을 바꿔도 두 스크립트가 어긋나지 않는다.
# (과거 각자 하드코딩하던 시절, 한쪽만 고쳐 역핑이 조용히 끊긴 사고가 있었다.)

# cwd가 속한 저장소의 **main 워크트리** 절대경로를 찾는다.
# 코더 워크트리(../<proj>-hermes 등)에서 실행해도 공용 .git을 통해 main을 역산한다.
magi_project_root() {
  local wt common
  wt=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  common=$(cd "$wt" && git rev-parse --git-common-dir)
  case "$common" in /*) ;; *) common="$wt/$common";; esac
  dirname "$(cd "$(dirname "$common")" && pwd)/$(basename "$common")"
}

# 세션명 = <프로젝트 폴더명>-<노드 key>
# tmux 세션 공간은 머신 전역이라, 경로에서 뽑은 접두가 프로젝트 간 충돌을 구조적으로 막는다.
magi_session() { echo "$1-$2"; }

# 프로젝트의 노드 정의를 stdout으로 낸다.
#   형식: key|워크트리|코드명|기동 명령
# `.magi/nodes.conf`가 있으면 그것을, 없으면 기본 관례를 쓴다.
# nodes.conf는 프로젝트마다 다른 값(예: codex 프로필명)을 담는 유일한 자리다.
magi_nodes() {
  local root="$1" proj parent conf
  proj=$(basename "$root"); parent=$(dirname "$root")
  conf="$root/.magi/nodes.conf"
  if [ -f "$conf" ]; then
    # ${PROJ_ROOT}·${WT_PARENT}·${PROJ} 치환만 허용 — 임의 코드 실행은 하지 않는다
    sed -e "s|\${PROJ_ROOT}|$root|g" -e "s|\${WT_PARENT}|$parent|g" -e "s|\${PROJ}|$proj|g" \
        -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$conf"
  else
    cat <<EOF
claude|$root|카스파|claude
hermes|$parent/$proj-hermes|멜기오르|hermes chat
codex|$parent/$proj-codex-cli|발타자르|codex -a never -s workspace-write
EOF
  fi
}

magi_field() { echo "$1" | cut -d'|' -f"$2"; }
