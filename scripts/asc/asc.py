#!/usr/bin/env python3
"""App Store Connect API 최소 클라이언트 — 원격(Discord) 파이프라인의 "심사 준비" 단계.
의존성: 표준 라이브러리 + cryptography (JWT ES256 서명). fastlane 없이 (ADR-0004·0010).

  asc.py auth                                   키·권한 확인 (앱 목록)
  asc.py status                                 최신 빌드·버전·심사 상태
  asc.py builds [--version 1.5]                 업로드된 빌드 (처리 상태)
  asc.py wait-build --version 1.5 [--build 8]   빌드 처리 완료까지 대기 (TestFlight 테스트 가능 시점)
  asc.py prepare --version 1.5 [--build 8] [--notes-ko f] [--notes-en f] [--release manual|auto]
                                                버전 생성/조회 + 빌드 연결 + What's New
  asc.py metadata --version 1.5 --locale ko --field description|keywords|promotionalText --file f
  asc.py screenshots --version 1.5 --locale ko --device iphone67|ipad13 --dir 폴더   (기존 세트 교체)
  asc.py submit --version 1.5                   심사 제출 (되돌리기 어려움 — 항상 사용자 확인 후)

설정: 레포 루트 .env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, ASC_BUNDLE_ID)
"""
import argparse, base64, hashlib, json, os, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parents[2]
DEVICE_TYPES = {"iphone67": "APP_IPHONE_67", "iphone65": "APP_IPHONE_65", "ipad13": "APP_IPAD_PRO_3GEN_129"}
LOCALES = {"ko": "ko", "en": "en-US", "ja": "ja"}


# ── 설정·인증 ──────────────────────────────────────────────
def load_env():
    env = dict(os.environ)
    p = ROOT / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"'))
    missing = [k for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not env.get(k)]
    if missing:
        sys.exit(f"✗ .env에 {', '.join(missing)} 필요 (scripts/asc/env.example 참고)")
    env.setdefault("ASC_BUNDLE_ID", "com.yang.FOMO24")
    return env


_token_cache = {"jwt": None, "exp": 0}


def jwt(env):
    """ES256 JWT, 20분 유효 — 호출마다 재서명하지 않도록 캐시."""
    if _token_cache["jwt"] and time.time() < _token_cache["exp"] - 60:
        return _token_cache["jwt"]
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

    key = serialization.load_pem_private_key(Path(os.path.expanduser(env["ASC_KEY_PATH"])).read_bytes(), password=None)
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": env["ASC_KEY_ID"], "typ": "JWT"}).encode())
    payload = b64(json.dumps({"iss": env["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    der = key.sign(f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    sig = b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    _token_cache.update(jwt=f"{header}.{payload}.{sig}", exp=now + 1200)
    return _token_cache["jwt"]


def call(env, method, path, body=None, params=None, raw_url=None, headers=None, data=None):
    url = raw_url or (API + path + ("?" + urllib.parse.urlencode(params, doseq=True) if params else ""))
    h = {"Authorization": f"Bearer {jwt(env)}"} if not raw_url else {}
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:600]
        sys.exit(f"✗ {method} {path or raw_url} → HTTP {e.code}\n{detail}")


# ── 조회 ──────────────────────────────────────────────────
def app_id(env):
    r = call(env, "GET", "/apps", params={"filter[bundleId]": env["ASC_BUNDLE_ID"], "fields[apps]": "name,bundleId"})
    if not r["data"]:
        sys.exit(f"✗ 번들 {env['ASC_BUNDLE_ID']} 앱 없음")
    return r["data"][0]["id"], r["data"][0]["attributes"]["name"]


def list_builds(env, aid, version=None, limit=10):
    params = {"filter[app]": aid, "sort": "-uploadedDate", "limit": limit,
              "fields[builds]": "version,uploadedDate,processingState,expired,usesNonExemptEncryption",
              "include": "preReleaseVersion", "fields[preReleaseVersions]": "version"}
    if version:
        params["filter[preReleaseVersion.version]"] = version
    r = call(env, "GET", "/builds", params=params)
    pre = {i["id"]: i["attributes"]["version"] for i in r.get("included", []) if i["type"] == "preReleaseVersions"}
    out = []
    for b in r["data"]:
        rel = b["relationships"].get("preReleaseVersion", {}).get("data") or {}
        a = b["attributes"]
        out.append({"id": b["id"], "build": a["version"], "version": pre.get(rel.get("id"), "?"),
                    "state": a["processingState"], "uploaded": (a.get("uploadedDate") or "")[:16], "expired": a.get("expired")})
    return out


def list_versions(env, aid, limit=5):
    r = call(env, "GET", f"/apps/{aid}/appStoreVersions",
             params={"filter[platform]": "IOS", "limit": limit,
                     "fields[appStoreVersions]": "versionString,appVersionState,releaseType,createdDate"})
    return [{"id": v["id"], "version": v["attributes"]["versionString"], "state": v["attributes"].get("appVersionState"),
             "release": v["attributes"].get("releaseType")} for v in r["data"]]


def find_version(env, aid, version):
    return next((v for v in list_versions(env, aid, limit=20) if v["version"] == version), None)


def localizations(env, vid):
    r = call(env, "GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations",
             params={"fields[appStoreVersionLocalizations]": "locale,whatsNew,description,keywords,promotionalText"})
    return {l["attributes"]["locale"]: {"id": l["id"], **l["attributes"]} for l in r["data"]}


# ── 명령 ──────────────────────────────────────────────────
def cmd_auth(env, a):
    aid, name = app_id(env)
    print(f"✓ 인증 OK — 앱 '{name}' (id {aid}), 키 {env['ASC_KEY_ID']}")


def cmd_status(env, a):
    aid, name = app_id(env)
    print(f"앱: {name}")
    for b in list_builds(env, aid, limit=3):
        print(f"  빌드 {b['version']} ({b['build']}) {b['state']} {b['uploaded']}{' 만료' if b['expired'] else ''}")
    for v in list_versions(env, aid, limit=3):
        print(f"  버전 {v['version']}: {v['state']} (release={v['release']})")


def cmd_builds(env, a):
    aid, _ = app_id(env)
    for b in list_builds(env, aid, a.version):
        print(f"{b['version']} ({b['build']})  {b['state']}  {b['uploaded']}  id={b['id']}")


def pick_build(env, aid, version, build=None, require_valid=True):
    builds = [b for b in list_builds(env, aid, version, limit=20) if not b["expired"]]
    if build:
        builds = [b for b in builds if b["build"] == str(build)]
    if not builds:
        sys.exit(f"✗ 버전 {version} 빌드{(' ' + str(build)) if build else ''} 없음")
    b = builds[0]
    if require_valid and b["state"] != "VALID":
        sys.exit(f"✗ 빌드 {b['version']} ({b['build']}) 상태 {b['state']} — 처리 완료(VALID) 아님. wait-build로 대기")
    return b


def cmd_wait_build(env, a):
    aid, _ = app_id(env)
    deadline = time.time() + a.timeout * 60
    while True:
        try:
            b = pick_build(env, aid, a.version, a.build, require_valid=False)
        except SystemExit:
            b = None
        if b and b["state"] == "VALID":
            print(f"✓ 빌드 {b['version']} ({b['build']}) 처리 완료 — TestFlight 테스트 가능")
            return
        if b and b["state"] in ("FAILED", "INVALID"):
            sys.exit(f"✗ 빌드 처리 실패: {b['state']}")
        if time.time() > deadline:
            sys.exit("✗ 대기 시간 초과")
        print(f"  … {b['state'] if b else '아직 업로드 안 됨'} (60초 후 재확인)", flush=True)
        time.sleep(60)


def cmd_prepare(env, a):
    aid, _ = app_id(env)
    v = find_version(env, aid, a.version)
    if v and v["state"] not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
        sys.exit(f"✗ 버전 {a.version} 상태가 {v['state']} — 편집 불가")
    if not v:
        r = call(env, "POST", "/appStoreVersions", body={"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": a.version},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
        v = {"id": r["data"]["id"], "version": a.version, "state": "PREPARE_FOR_SUBMISSION"}
        print(f"✓ 버전 {a.version} 생성")
    else:
        print(f"· 버전 {a.version} 존재 ({v['state']})")
    if a.release:
        call(env, "PATCH", f"/appStoreVersions/{v['id']}", body={"data": {"type": "appStoreVersions", "id": v["id"],
             "attributes": {"releaseType": "MANUAL" if a.release == "manual" else "AFTER_APPROVAL"}}})
        print(f"✓ 출시 방식: {a.release}")
    b = pick_build(env, aid, a.version, a.build)
    call(env, "PATCH", f"/appStoreVersions/{v['id']}/relationships/build", body={"data": {"type": "builds", "id": b["id"]}})
    print(f"✓ 빌드 연결: {b['version']} ({b['build']})")
    locs = localizations(env, v["id"])
    for lang, path in (("ko", a.notes_ko), ("en", a.notes_en)):
        if not path:
            continue
        loc = locs.get(LOCALES[lang])
        text = Path(path).read_text().strip()
        if not loc:
            r = call(env, "POST", "/appStoreVersionLocalizations", body={"data": {
                "type": "appStoreVersionLocalizations", "attributes": {"locale": LOCALES[lang], "whatsNew": text},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
        else:
            call(env, "PATCH", f"/appStoreVersionLocalizations/{loc['id']}", body={"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
        print(f"✓ What's New ({LOCALES[lang]}) {len(text)}자")
    print("→ 다음: asc.py screenshots / metadata (필요 시) → 사용자 확인 → asc.py submit")


def cmd_metadata(env, a):
    aid, _ = app_id(env)
    v = find_version(env, aid, a.version) or sys.exit(f"✗ 버전 {a.version} 없음 (prepare 먼저)")
    loc = localizations(env, v["id"]).get(LOCALES[a.locale]) or sys.exit(f"✗ {a.locale} 로컬라이제이션 없음")
    text = Path(a.file).read_text().strip()
    call(env, "PATCH", f"/appStoreVersionLocalizations/{loc['id']}", body={"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {a.field: text}}})
    print(f"✓ {a.field} ({LOCALES[a.locale]}) {len(text)}자 반영")


def cmd_screenshots(env, a):
    aid, _ = app_id(env)
    v = find_version(env, aid, a.version) or sys.exit(f"✗ 버전 {a.version} 없음 (prepare 먼저)")
    loc = localizations(env, v["id"]).get(LOCALES[a.locale]) or sys.exit(f"✗ {a.locale} 로컬라이제이션 없음")
    dtype = DEVICE_TYPES[a.device]
    files = sorted(p for p in Path(a.dir).iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))
    if not files or len(files) > 10:
        sys.exit(f"✗ 스크린샷 1~10장 필요 (현재 {len(files)}장)")
    sets = call(env, "GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                params={"fields[appScreenshotSets]": "screenshotDisplayType", "include": "appScreenshots"})
    sset = next((s for s in sets["data"] if s["attributes"]["screenshotDisplayType"] == dtype), None)
    if sset:
        for shot in sset["relationships"].get("appScreenshots", {}).get("data", []):
            call(env, "DELETE", f"/appScreenshots/{shot['id']}")
        print(f"· 기존 {dtype} 세트 비움")
        sid = sset["id"]
    else:
        r = call(env, "POST", "/appScreenshotSets", body={"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dtype},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})
        sid = r["data"]["id"]
        print(f"✓ {dtype} 세트 생성")
    for f in files:
        data = f.read_bytes()
        r = call(env, "POST", "/appScreenshots", body={"data": {
            "type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sid}}}}})
        shot = r["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            hdrs = {h["name"]: h["value"] for h in op["requestHeaders"]}
            call(env, op["method"], None, raw_url=op["url"], headers=hdrs, data=chunk)
        call(env, "PATCH", f"/appScreenshots/{shot['id']}", body={"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"✓ 업로드 {f.name} ({len(data)//1024} KB)")
    print(f"→ ASC에서 처리 후 반영 (보통 1~2분). {len(files)}장")


def cmd_submit(env, a):
    aid, _ = app_id(env)
    v = find_version(env, aid, a.version) or sys.exit(f"✗ 버전 {a.version} 없음")
    if v["state"] != "PREPARE_FOR_SUBMISSION":
        sys.exit(f"✗ 버전 상태 {v['state']} — 제출 가능 상태(PREPARE_FOR_SUBMISSION) 아님")
    r = call(env, "POST", "/reviewSubmissions", body={"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
    rs = r["data"]["id"]
    call(env, "POST", "/reviewSubmissionItems", body={"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    call(env, "PATCH", f"/reviewSubmissions/{rs}", body={"data": {"type": "reviewSubmissions", "id": rs, "attributes": {"submitted": True}}})
    print(f"✓ 버전 {a.version} 심사 제출 완료 (reviewSubmission {rs})")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("auth"); sub.add_parser("status")
    s = sub.add_parser("builds"); s.add_argument("--version")
    s = sub.add_parser("wait-build"); s.add_argument("--version", required=True); s.add_argument("--build"); s.add_argument("--timeout", type=int, default=40, help="분")
    s = sub.add_parser("prepare"); s.add_argument("--version", required=True); s.add_argument("--build")
    s.add_argument("--notes-ko"); s.add_argument("--notes-en"); s.add_argument("--release", choices=["manual", "auto"])
    s = sub.add_parser("metadata"); s.add_argument("--version", required=True); s.add_argument("--locale", choices=list(LOCALES), required=True)
    s.add_argument("--field", choices=["description", "keywords", "promotionalText", "whatsNew", "supportUrl", "marketingUrl"], required=True); s.add_argument("--file", required=True)
    s = sub.add_parser("screenshots"); s.add_argument("--version", required=True); s.add_argument("--locale", choices=list(LOCALES), required=True)
    s.add_argument("--device", choices=list(DEVICE_TYPES), required=True); s.add_argument("--dir", required=True)
    s = sub.add_parser("submit"); s.add_argument("--version", required=True)
    a = p.parse_args()
    env = load_env()
    {"auth": cmd_auth, "status": cmd_status, "builds": cmd_builds, "wait-build": cmd_wait_build, "prepare": cmd_prepare,
     "metadata": cmd_metadata, "screenshots": cmd_screenshots, "submit": cmd_submit}[a.cmd](env, a)


if __name__ == "__main__":
    main()
