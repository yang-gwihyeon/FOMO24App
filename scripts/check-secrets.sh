#!/usr/bin/env bash
# 스테이징된 변경에서 키·토큰·시크릿 파일 패턴을 찾는다. 커밋 전 훅과 make secrets 에서 사용.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
# 1) 커밋 금지 파일
if git diff --cached --name-only | grep -E '(^|/)GoogleService-Info\.plist$|AuthKey_.*\.p8$|(^|/)\.env(\..*)?$' | grep -v '^CI/'; then
  echo "✗ 시크릿 파일이 스테이징됨 (위 목록). CI/ 의 더미만 허용." >&2; fail=1
fi
# 2) 내용 패턴 (추가된 줄만)
patterns='AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|-----BEGIN (RSA |EC )?PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'
if git diff --cached -U0 | grep -E '^\+' | grep -vE '^\+\+\+' | grep -nE "$patterns"; then
  echo "✗ 키/토큰으로 보이는 문자열이 추가됨 (위 줄)." >&2; fail=1
fi
if [ "$fail" -eq 0 ]; then echo "✓ 시크릿 패턴 없음"; fi
exit $fail
