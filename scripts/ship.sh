#!/usr/bin/env bash
# TestFlight 빌드 트리거 — 원격(Discord) 파이프라인의 "올려줘" 한 명령.
#   scripts/ship.sh 1.5         # 태그 없이 CI 수동 실행 → TestFlight (테스트 빌드, 반복 가능)
#   scripts/ship.sh 1.5 --tag   # v1.5 태그 생성·푸시 → CI → TestFlight (최종 릴리즈, 되돌리기 어려움)
# 사전 검사: main 브랜치 · 작업 트리 클린 · origin과 동기화 · HEAD의 CI 초록불.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
MODE="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "사용법: scripts/ship.sh <버전 예:1.5> [--tag]"; exit 2; }

branch=$(git branch --show-current)
[[ "$branch" == "main" ]] || { echo "✗ main에서만 실행 (현재: $branch)"; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "✗ 커밋 안 된 변경이 있음"; exit 1; }
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "✗ 로컬 main이 origin/main과 다름 (pull 또는 push 필요)"; exit 1; }

# HEAD 커밋의 CI(필수 체크) 결과
sha=$(git rev-parse HEAD)
ci=$(gh run list --workflow=ci.yml --commit "$sha" --limit 1 --json conclusion --jq '.[0].conclusion // "none"')
[[ "$ci" == "success" ]] || { echo "✗ HEAD($sha)의 CI가 success가 아님: $ci"; exit 1; }

if [[ "$MODE" == "--tag" ]]; then
  tag="v$VERSION"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git ls-remote --tags origin "$tag" | grep -q "$tag"; then
    echo "✗ 태그 $tag 가 이미 있음"; exit 1
  fi
  git tag "$tag" && git push origin "$tag"
  echo "✓ $tag 푸시 → 릴리즈 CI 시작"
else
  gh workflow run release.yml -f version="$VERSION"
  echo "✓ release.yml 수동 실행 (version=$VERSION, 태그 없음)"
fi
sleep 5
gh run list --workflow=release.yml --limit 1 --json databaseId,status,url --jq '"run \(.[0].databaseId) \(.[0].status) \(.[0].url)"'
