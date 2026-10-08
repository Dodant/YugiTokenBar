#!/usr/bin/env python3
"""UI 문구 키를 컴파일러로 뽑아(swiftc -emit-localized-strings → .stringsdata) Resources/{en,ja}.lproj/Localizable.strings 와 맞춘다.
키는 코드의 한국어 문장이고 보간은 컴파일러가 실제 타입으로 바꾼 형식(%lld·%@)이다. Usage/(PokeTokenBar 복사본)는 뺀다.

사용: python3 tools/sync-strings.py                 # 없는 키를 번역 안 된 채(값 = 키) 덧붙인다
      python3 tools/sync-strings.py --check         # 없는 키·번역 안 된 키·안 쓰는 키·키에 없는 한글 리터럴이 있으면 실패
      python3 tools/sync-strings.py --check A.swift  # 그 소스 파일만 (안 쓰는 키 검사는 안 함)
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys

OUT = os.path.abspath(".build/loc")  # 절대 경로: 상대 경로면 컴파일러가 .stringsdata 를 안 쓴다
LANGS = ["en", "ja"]
HANGUL = re.compile(r"[가-힣]")
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
SPEC = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|lf|f)")
INTERP = re.compile(r"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
# 키에 없어도 되는 한글 리터럴 (사용자에게 보이지 않는 것). 줄 내용의 일부 문자열로 적는다
ALLOW = [
    'case .ko: "한국어"',  # 언어 메뉴의 언어 이름은 그 언어로 쓰고 번역하지 않는다 (스펙 6절 설정 화면)
]


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def code_keys():
    """{키: ["파일.swift:줄", …]} — 한글이 든 키만. 여러 파일에서 쓰는 키는 위치를 모두 담는다(파일 인자로 거를 때 빠지지 않게). 매번 처음부터 빌드한다(증분 빌드는 안 바뀐 파일의 .stringsdata 를 다시 안 쓴다)."""
    # ponytail: 매번 전체 빌드(~30초). 느려지면 .stringsdata 를 지우지 않고 증분으로
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(f"{OUT}/strings")  # 폴더가 없으면 조용히 안 쓴다
    subprocess.run(["swift", "build", "--scratch-path", f"{OUT}/build",
                    "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", f"{OUT}/strings"],
                   check=True, stdout=subprocess.DEVNULL)
    keys = {}
    for path in sorted(glob.glob(f"{OUT}/strings/*.stringsdata")):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if "/Usage/" in data["source"]:
            continue
        for e in data["tables"].get("Localizable", []):
            if HANGUL.search(e["key"]):
                keys.setdefault(e["key"], []).append(f'{os.path.basename(data["source"])}:{e["location"]["startingLine"]}')
    return keys


def read_strings(path):
    """{키: 값} (파일 순서)"""
    entries = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if m := ENTRY.match(line.strip()):
                entries[unescape(m.group(1))] = unescape(m.group(2))
    return entries


def append_strings(path, missing):
    with open(path, "a", encoding="utf-8") as f:
        for key, where in missing:
            f.write(f'/* {where} */\n"{escape(key)}" = "{escape(key)}";\n')


def specs(s):
    return sorted(SPEC.findall(s))


def stray_literals(files, keys):
    """소스의 한글 리터럴 중 키에 없는 것 — String 으로 넘겨 Text(변수)로 그리는 곳(컴파일러가 못 봄)을 잡는다."""
    bare = {SPEC.sub("", k) for k in keys}
    out = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                s = line.strip()
                if s.startswith("//") or "AppLog.write" in s or "fatalError" in s or any(a in s for a in ALLOW):
                    continue
                s = s.split(" //")[0]
                for lit in LITERAL.findall(INTERP.sub("", s)):
                    if HANGUL.search(lit) and unescape(lit) not in bare:
                        out.append(f"{os.path.basename(path)}:{n}: {lit}")
    return out


def main():
    args = sys.argv[1:]
    check = "--check" in args
    only = [a for a in args if a.endswith(".swift")]
    keys = code_keys()
    sources = [p for p in glob.glob("Sources/YugiTokenBar/**/*.swift", recursive=True) if "/Usage/" not in p]
    if only:
        keys = {k: w for k, w in keys.items() if any(x.split(":")[0] in only for x in w)}
        sources = [p for p in sources if os.path.basename(p) in only]
    problems = []
    for lang in LANGS:
        path = f"Resources/{lang}.lproj/Localizable.strings"
        table = read_strings(path)
        missing = [(k, w[0]) for k, w in keys.items() if k not in table]
        if check:
            problems += [f"{lang}: 없는 키 {w}: {k}" for k, w in missing]
            problems += [f"{lang}: 번역 안 됨: {k}" for k, v in table.items() if k in keys and HANGUL.search(v)]
            problems += [f"{lang}: 형식 지정자 다름: {k} → {v}" for k, v in table.items() if specs(k) != specs(v)]
            if not only:
                problems += [f"{lang}: 안 쓰는 키: {k}" for k in table if k not in keys and HANGUL.search(k)]
        elif missing:
            append_strings(path, missing)
            print(f"{lang}: 키 {len(missing)}개 덧붙임 (값 = 키, 번역할 것)")
    if check:
        problems += [f"키에 없는 한글 리터럴 {s}" for s in stray_literals(sources, keys)]
        print("\n".join(problems) or "ok")
        sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
