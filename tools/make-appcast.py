#!/usr/bin/env python3
"""Sparkle appcast(항목 하나)를 표준 출력에 쓴다. 패치노트는 세 언어 CHANGELOG 의 그 버전 항목.
사용: python3 tools/make-appcast.py --version 0.7.0 --build 812 --length 12345 --signature SIG > build/release/appcast.xml"""
import argparse
import os
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOGS = {"ko": "CHANGELOG.md", "en": "CHANGELOG.en.md", "ja": "CHANGELOG.ja.md"}
ET.register_namespace("sparkle", SPARKLE)


def top_notes(text, version):
    """`## <version>` 항목의 본문 (제목 줄 빼고, 다음 `## ` 전까지, 앞뒤 빈 줄 제거)"""
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].split(" ")[0] == version
        elif inside:
            lines.append(line)
    return "\n".join(lines).strip()


def all_notes(version):
    """언어별 패치노트. 한 파일이라도 그 버전 항목이 없으면 멈춘다"""
    notes = {}
    for lang, name in CHANGELOGS.items():
        with open(os.path.join(REPO, name), encoding="utf-8") as f:
            notes[lang] = top_notes(f.read(), version)
        if not notes[lang]:
            raise SystemExit(f"{name}에 {version} 항목이 없음")
    return notes


def appcast(version, build, length, signature, notes):
    url = f"https://github.com/Dodant/YugiTokenBar/releases/download/v{version}/YugiTokenBar-{version}-macOS.zip"
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "YugiTokenBar"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(build)
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = "26.0"
    # Sparkle 은 xml:lang 이 붙은 description 중 앱 언어에 맞는 것을 고른다
    for lang, body in notes.items():
        ET.SubElement(item, "description", {f"{{{SPARKLE}}}format": "markdown", XML_LANG: lang}).text = body
    ET.SubElement(item, "enclosure", {
        "url": url, "length": str(length), "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(rss)
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(rss, encoding="unicode") + "\n"


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True, type=int)
    p.add_argument("--length", required=True, type=int)
    p.add_argument("--signature", required=True)
    a = p.parse_args()
    print(appcast(a.version, a.build, a.length, a.signature, all_notes(a.version)), end="")
