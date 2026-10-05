#!/usr/bin/env python3
"""앱이 실제로 필요한 유니코드 범위를 pyftsubset --unicodes 형식으로 출력한다 (scripts/subset-fonts.sh가 사용).
- 라틴·기호·통화·화살표·박스
- 한글: KS X 1001 상용 2,350자 + 호환 자모 (전체 11,172자 대신 — 폰트 용량의 대부분)
- 가나 (카탈로그 일본어 종목명)
- 소스 코드 문자열 리터럴에 등장하는 모든 비ASCII 문자 (희귀 한글 포함 — 누락 방지)
"""
import glob, re

ranges = [
    "U+0020-007E", "U+00A0-00FF", "U+0100-017F",          # 라틴·라틴 확장 A
    "U+02C6-02DC", "U+2000-206F", "U+20A0-20BF",           # 구두점·통화 (₩ € £ ¥)
    "U+2100-214F", "U+2190-21FF", "U+2200-22FF",           # 문자 기호·화살표·수학
    "U+2500-25FF", "U+2600-26FF", "U+3000-303F",           # 박스·기호·CJK 구두점
    "U+3041-3096", "U+30A1-30FA", "U+30FC",                # 히라가나·가타카나·장음
    "U+3131-318E", "U+FF01-FF5E",                          # 호환 자모·전각 영숫자
]
chars = set()
# KS X 1001 한글 2,350자 = EUC-KR 0xB0A1–0xC8FE
for hi in range(0xB0, 0xC9):
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode("euc_kr"))
        except UnicodeDecodeError:
            pass
# 소스에 등장하는 비ASCII 문자 (문서 제외 — UI 문자열만)
for path in glob.glob("Sources/**/*.swift", recursive=True) + glob.glob("Modules/**/Sources/*.swift", recursive=True) + glob.glob("Widgets/*.swift"):
    for ch in open(path, encoding="utf-8").read():
        if ord(ch) > 0x7E and not (0x1F000 <= ord(ch) <= 0x1FFFF):   # 이모지는 폰트에 없음
            chars.add(ch)
codes = sorted({ord(c) for c in chars if len(c) == 1})
print(",".join(ranges + [f"U+{c:04X}" for c in codes]))
