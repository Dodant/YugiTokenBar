#!/usr/bin/env python3
"""UI 문구 키를 컴파일러로 뽑아(swiftc -emit-localized-strings → .stringsdata) Resources/{en,ja}.lproj/Localizable.strings 와 맞춘다.
키는 코드의 한국어 문장이고 보간은 컴파일러가 실제 타입으로 바꾼 형식(%lld·%@)이다. Usage/(PokeTokenBar 복사본)는 뺀다.

사용: python3 tools/sync-strings.py                 # 없는 키를 번역 안 된 채(값 = 키) 덧붙인다
      python3 tools/sync-strings.py --check         # 없는 키·번역 안 된 키·안 쓰는 키·키에 없는 한글 리터럴,
                                                    # en 값의 한글·가나·한자, stringsdict 없는 en 복수 명사("%lld cards")가 있으면 실패
      python3 tools/sync-strings.py --check A.swift  # 그 소스 파일만 (안 쓰는 키 검사는 안 함)
"""
import glob
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import textwrap
from collections import namedtuple

OUT = os.path.abspath(".build/loc")  # 절대 경로: 상대 경로면 컴파일러가 .stringsdata 를 안 쓴다
LANGS = ["en", "ja"]
HANGUL = re.compile(r"[가-힣]")
# en 값에 남으면 안 되는 글자 (한글·자모·가나·한자). 가운뎃점 ・ 은 카드 이름에도 쓰여 뺀다
NOT_EN = re.compile(r"[가-힣ㄱ-ㅎㅏ-ㅣ\u3040-\u30fa\u30fc-\u30ff\u4e00-\u9fff]")
# en 값에서 수 바로 뒤 영어 복수 명사 ("%lld cards") — 1일 때 틀리므로 en.lproj/Localizable.stringsdict 에 복수 규칙이 있어야 한다
PLURAL = re.compile(r"%%|%(?:\d+\$)?lld [A-Za-z]+s\b")
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
# 키에 없어도 되는 한글 리터럴 (사용자에게 보이지 않는 것). 줄 내용의 일부 문자열로 적는다
ALLOW = [
    'case .ko: "한국어"',  # 언어 메뉴의 언어 이름은 그 언어로 쓰고 번역하지 않는다 (스펙 6절 설정 화면)
    '["효과", "Effect", "効果", "일반"',  # 카드 파일의 종류 표기와 맞춰 보는 값 (CardInfo.workLine)
]


def unescape(s):
    """Decode in one pass, so a literal \\n does not become a newline."""
    escapes = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '"': '"', "'": "'", '\\': '\\'}
    def replace(match):
        value = match.group(1)
        if value.startswith("u{"):
            return chr(int(value[2:-1], 16))
        return escapes.get(value, "\\" + value)
    return re.sub(r'\\(u\{[0-9a-fA-F]+\}|.)', replace, s)


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


Token = namedtuple("Token", "kind text offset value interpolated interpolations", defaults=[()])


def swift_tokens(source):
    """Small lexer, not a Swift type checker: comments and string contents stay opaque.

    Interpolation expressions are skipped with balanced delimiters, including their
    own strings/comments, so a quote inside an interpolation cannot end its string.
    Raw/multiline strings are recognized but deliberately not accepted as L keys.
    """
    size = len(source)

    def comment(i):
        if source.startswith("//", i):
            end = source.find("\n", i)
            return size if end < 0 else end
        if source.startswith("/*", i):
            depth, i = 1, i + 2
            while i < size and depth:
                if source.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif source.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            return i
        return None

    def interpolation(i):
        depth = 1
        while i < size and depth:
            end = comment(i)
            if end is not None:
                i = end
            elif string_start(i):
                _, i = string(i)
            else:
                if source[i] == "(":
                    depth += 1
                elif source[i] == ")":
                    depth -= 1
                i += 1
        return i

    def string_start(i):
        return re.match(r'\#*"', source[i:])

    def string(start):
        opening = string_start(start).group()
        hashes = opening[:-1]
        quote = '"""' if source.startswith('"""', start + len(hashes)) else '"'
        closing = quote + hashes
        i = start + len(hashes) + len(quote)
        parts, has_interpolation, expressions = [], False, []
        while i < size:
            if source.startswith(closing, i):
                end = i + len(closing)
                kind = "string" if not hashes and quote == '"' else "unsupported-string"
                value = "".join(parts)
                if quote == '"""' and value.startswith("\n"):
                    # Swift strips the opening newline, closing-line newline and
                    # closing delimiter indentation from multiline strings.
                    indent = source[source.rfind("\n", start, i) + 1:i]
                    if not indent.strip():
                        value = value[1:-(len(indent) + 1)]
                        value = textwrap.dedent(value) if not indent else "\n".join(
                            line[len(indent):] if line.startswith(indent) else line for line in value.split("\n"))
                return Token(kind, source[start:end], start, unescape(value), has_interpolation, expressions), end
            if source.startswith("\\" + hashes, i):
                after = i + 1 + len(hashes)
                if source.startswith("(", after):
                    has_interpolation = True
                    end = interpolation(after + 1)
                    expressions.append((after + 1, end - 1))
                    i = end
                    continue
                if after < size:
                    parts.append(source[i:after + 1])
                    i = after + 1
                    continue
            parts.append(source[i])
            i += 1
        return Token("unterminated-string", source[start:], start, "".join(parts), has_interpolation), size

    i = 0
    while i < size:
        if source[i].isspace():
            i += 1
            continue
        end = comment(i)
        if end is not None:
            i = end
            continue
        if string_start(i):
            token, i = string(i)
            yield token
            continue
        # Extended regex literals used by the shared Localizer are not strings.
        if match := re.match(r'(#+)/', source[i:]):
            end = source.find('/' + match.group(1), i + len(match.group()))
            if end >= 0:
                end += 1 + len(match.group(1))
                yield Token("regex", source[i:end], i, None, False)
                i = end
                continue
        if match := re.match(r'[A-Za-z_][A-Za-z_0-9]*', source[i:]):
            text = match.group()
            yield Token("identifier", text, i, None, False)
            i += len(text)
        else:
            yield Token("punctuation", source[i], i, None, False)
            i += 1


def format_slots(pattern):
    """Yield (argument index, specifier); literal %% consumes no argument."""
    next_index, i = 0, 0
    while i < len(pattern):
        if pattern[i] != "%":
            i += 1
            continue
        if pattern.startswith("%%", i):
            i += 2
            continue
        match = re.match(r'%(?:(\d+)\$)?(lld|@)', pattern[i:])
        if not match:
            raise ValueError("L key supports only %lld, %@, positional specifiers and %%")
        if match.group(1):
            index = int(match.group(1)) - 1
            if index < 0:
                raise ValueError("L argument positions start at 1")
        else:
            index, next_index = next_index, next_index + 1
        yield index, match.group(2)
        i += len(match.group())


def linux_keys(source, path, line_offset=0):
    """Extract explicit static L keys from source, including #if os(Linux) code."""
    tokens = list(swift_tokens(source))
    keys = {}
    for token in tokens:
        for start, end in token.interpolations:
            for key, locations in linux_keys(source[start:end], path, line_offset + source.count("\n", 0, start)).items():
                keys.setdefault(key, []).extend(locations)
    for i, token in enumerate(tokens):
        if token.kind != "identifier" or token.text != "L" or i + 1 >= len(tokens) or tokens[i + 1].text != "(":
            continue
        if i and tokens[i - 1].text in ("func", "."):
            continue
        location = f"{os.path.basename(path)}:{line_offset + source.count(chr(10), 0, token.offset) + 1}"
        try:
            parts, part, stack = [], [], [")"]
            for item in tokens[i + 2:]:
                text = item.text
                if item.kind == "punctuation" and text in ("(", "[", "{"):
                    stack.append({"(": ")", "[": "]", "{": "}"}[text])
                elif item.kind == "punctuation" and text in (")", "]", "}"):
                    if not stack or text != stack.pop():
                        raise ValueError("unbalanced L call")
                    if not stack:
                        parts.append(part)
                        break
                if text == "," and item.kind == "punctuation" and len(stack) == 1:
                    parts.append(part)
                    part = []
                else:
                    part.append(item)
            else:
                raise ValueError("unterminated L call")
            if len(parts[0]) != 1 or parts[0][0].kind != "string" or parts[0][0].interpolated:
                raise ValueError("L key must be one ordinary static string; interpolation, dynamic, raw and multiline keys are unsupported")
            pattern = parts[0][0].value
            arguments = []
            for argument in parts[1:]:
                if (len(argument) < 5 or [t.text for t in argument[:3]] not in
                        ([".", "int", "("], [".", "text", "("]) or argument[-1].text != ")"):
                    raise ValueError("L arguments must be explicit .int(expression) or .text(expression)")
                # The wrapper must cover the whole argument, not .int(x) + .int(y).
                depth = 0
                for n, item in enumerate(argument[2:]):
                    if item.kind == "punctuation" and item.text == "(":
                        depth += 1
                    elif item.kind == "punctuation" and item.text == ")":
                        depth -= 1
                        if depth == 0 and n != len(argument) - 3:
                            raise ValueError("L argument wrapper must cover its entire expression")
                arguments.append("lld" if argument[1].text == "int" else "@")
            used = set()
            for index, specifier in format_slots(pattern):
                if index >= len(arguments) or arguments[index] != specifier:
                    raise ValueError("L key specifier does not match its .int/.text argument")
                used.add(index)
            if used != set(range(len(arguments))):
                raise ValueError("L has unused arguments")
            if HANGUL.search(pattern):
                keys.setdefault(pattern, []).append(location)
        except ValueError as error:
            raise ValueError(f"{location}: {error}") from error
    return keys


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


def stringsdict_keys():
    path = "Resources/en.lproj/Localizable.stringsdict"
    if not os.path.exists(path):
        return set()
    with open(path, "rb") as f:
        return set(plistlib.load(f))


def specs(s):
    # Position, not occurrence count, defines the argument signature: a
    # translation may reorder or repeat an argument. %% is never a placeholder.
    arguments, next_index = set(), 0
    for match in re.finditer(r'%%|%(?:(\d+)\$)?(lld|ld|d|@|lf|f)', s):
        if match.group() == "%%":
            continue
        if match.group(1):
            index = int(match.group(1)) - 1
        else:
            index, next_index = next_index, next_index + 1
        arguments.add((index, match.group(2)))
    return sorted(arguments)


def needs_plural(s):
    return any(match.group() != "%%" for match in PLURAL.finditer(s))


def all_string_tokens(source, offset=0):
    """Visit executable interpolation expressions, never the surrounding text."""
    for token in swift_tokens(source):
        if token.kind in ("string", "unsupported-string"):
            yield token._replace(offset=token.offset + offset)
            for start, end in token.interpolations:
                yield from all_string_tokens(source[start:end], offset + start)


def linux_only_lines(source, path):
    """Identify Linux UI files and explicit platform branches in shared files."""
    if "Linux" in os.path.normpath(path).split(os.sep) or os.path.basename(path).startswith("Linux"):
        return set(range(1, len(source.splitlines()) + 1))
    # Only real directive tokens count; a comment or multiline string can contain
    # text that looks exactly like #if. Tokenization also removes tail comments.
    tokens, directives = list(swift_tokens(source)), {}
    for i, token in enumerate(tokens):
        if token.kind != "punctuation" or token.text != "#":
            continue
        start = source.rfind("\n", 0, token.offset) + 1
        if source[start:token.offset].strip():
            continue
        end = source.find("\n", token.offset)
        end = len(source) if end < 0 else end
        parts = []
        for item in tokens[i + 1:]:
            if item.offset >= end:
                break
            parts.append(item.text)
        if parts:
            directives[source.count("\n", 0, token.offset) + 1] = "#" + parts[0] + " " + "".join(parts[1:])
    def branches(condition):
        # Conditions not decided by the platform (DEBUG, canImport, compiler
        # versions) may be true or false. Check both branches conservatively.
        atoms = re.findall(r'os\s*\(\s*\w+\s*\)|\w+\([^()]*\)|&&|\|\||[!()]|\w+|\S', condition)
        def possible(platform):
            position = 0
            def primary():
                nonlocal position
                if position >= len(atoms):
                    raise ValueError("missing condition")
                atom = atoms[position]
                position += 1
                if atom == "!":
                    return {not value for value in primary()}
                if atom == "(":
                    value = expression()
                    if position >= len(atoms) or atoms[position] != ")":
                        raise ValueError("unbalanced condition")
                    position += 1
                    return value
                if match := re.fullmatch(r'os\s*\(\s*(\w+)\s*\)', atom):
                    return {match.group(1) == platform}
                return {True, False}
            def conjunction():
                nonlocal position
                value = primary()
                while position < len(atoms) and atoms[position] == "&&":
                    position += 1
                    other = primary()
                    value = {a and b for a in value for b in other}
                return value
            def expression():
                nonlocal position
                value = conjunction()
                while position < len(atoms) and atoms[position] == "||":
                    position += 1
                    other = conjunction()
                    value = {a or b for a in value for b in other}
                return value
            try:
                value = expression()
                return value if position == len(atoms) else {True, False}
            except ValueError:
                return {True, False}
        values = {platform: possible(platform) for platform in ("Linux", "macOS")}
        return ({p for p, v in values.items() if True in v}, {p for p, v in values.items() if False in v})

    platforms, stack, lines = {"Linux", "macOS"}, [], set()
    for n, line in enumerate(source.splitlines(), 1):
        stripped = directives.get(n, "").strip()
        if stripped.startswith("#if "):
            selected, remaining = branches(stripped[4:])
            stack.append((platforms, platforms & remaining))
            platforms = platforms & selected
        elif stripped == "#else" and stack:
            _, platforms = stack[-1]
        elif stripped.startswith("#elseif ") and stack:
            previous, remaining = stack[-1]
            selected, otherwise = branches(stripped[8:])
            platforms = remaining & selected
            stack[-1] = (previous, remaining & otherwise)
        elif stripped == "#endif" and stack:
            platforms, _ = stack.pop()
        elif platforms == {"Linux"}:
            lines.add(n)
    return lines


def explicit_key_offsets(source, offset=0):
    tokens = list(swift_tokens(source))
    out = set()
    for i, token in enumerate(tokens):
        if (token.text == "L" and token.kind == "identifier" and i + 2 < len(tokens)
                and tokens[i + 1].text == "(" and tokens[i + 2].kind == "string"
                and (not i or tokens[i - 1].text not in ("func", "."))):
            out.add(offset + tokens[i + 2].offset)
        for start, end in token.interpolations:
            out.update(explicit_key_offsets(source[start:end], offset + start))
    return out


def stray_literals(files, keys):
    """소스의 한글 리터럴 중 키에 없는 것 — String 으로 넘겨 Text(변수)로 그리는 곳(컴파일러가 못 봄)을 잡는다."""
    def normalize(value):
        return re.sub(r'%%|%(?:\d+\$)?(?:lld|ld|d|@|lf|f)',
                      lambda m: "%" if m.group() == "%%" else "", value)
    bare = {normalize(k) for k in keys}
    out = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            source = f.read()
        lines = source.splitlines()
        linux_lines = linux_only_lines(source, path)
        localized = explicit_key_offsets(source)
        for token in all_string_tokens(source):
            n = source.count("\n", 0, token.offset) + 1
            line = lines[n - 1]
            if "AppLog.write" in line or "fatalError" in line or any(a in line for a in ALLOW):
                continue
            if HANGUL.search(token.value) and (
                    (n in linux_lines and token.offset not in localized) or normalize(token.value) not in bare):
                out.append(f"{os.path.basename(path)}:{n}: {token.value}")
    return out


def main():
    args = sys.argv[1:]
    check = "--check" in args
    only = [a for a in args if a.endswith(".swift")]
    sources = [p for p in glob.glob("Sources/YugiTokenBar/**/*.swift", recursive=True) if "/Usage/" not in p]
    explicit = {}
    try:
        for path in sources:
            with open(path, encoding="utf-8") as f:
                for key, locations in linux_keys(f.read(), path).items():
                    explicit.setdefault(key, []).extend(locations)
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    keys = code_keys()
    for key, locations in explicit.items():
        keys.setdefault(key, []).extend(locations)
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
            if lang == "en":
                plurals = stringsdict_keys()
                problems += [f"en: 영어가 아닌 글자: {k} → {v}" for k, v in table.items() if NOT_EN.search(v)]
                problems += [f"en: 복수형 없음(stringsdict 에 추가): {k} → {v}" for k, v in table.items() if needs_plural(v) and k not in plurals]
                problems += [f"en: stringsdict 키가 strings 에 없음: {k}" for k in plurals if k not in table]
        elif missing:
            append_strings(path, missing)
            print(f"{lang}: 키 {len(missing)}개 덧붙임 (값 = 키, 번역할 것)")
    if check:
        problems += [f"키에 없는 한글 리터럴 {s}" for s in stray_literals(sources, keys)]
        print("\n".join(problems) or "ok")
        sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
