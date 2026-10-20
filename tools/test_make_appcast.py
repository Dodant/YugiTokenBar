#!/usr/bin/env python3
"""make-appcast.py 자체 검사(네트워크 없음). 사용: python3 tools/test_make_appcast.py"""
import importlib.util
import os
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("ma", os.path.join(os.path.dirname(__file__), "make-appcast.py"))
ma = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ma)
S = "{" + ma.SPARKLE + "}"


def test_top_notes():
    text = "# 패치노트\n\n## 0.7.0 — 2026-10-20\n**✨ 새로운 기능**\n- 업데이트\n\n## 0.6.1 — 2026-10-12\n- 옛 항목\n"
    assert ma.top_notes(text, "0.7.0") == "**✨ 새로운 기능**\n- 업데이트"
    assert ma.top_notes(text, "0.6.1") == "- 옛 항목"
    assert ma.top_notes(text, "9.9.9") == ""


def test_appcast():
    xml = ma.appcast("0.7.0", 812, 12345, "SIG==", {"ko": "- 한", "en": "- en", "ja": "- ja"})
    assert 'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"' in xml
    item = ET.fromstring(xml).find("channel/item")
    assert item.find(S + "version").text == "812"
    assert item.find(S + "shortVersionString").text == "0.7.0"
    assert item.find(S + "minimumSystemVersion").text == "26.0"
    enc = item.find("enclosure")
    assert enc.get("url") == "https://github.com/Dodant/YugiTokenBar/releases/download/v0.7.0/YugiTokenBar-0.7.0-macOS.zip"
    assert enc.get("length") == "12345"
    assert enc.get(S + "edSignature") == "SIG=="
    descs = {d.get(ma.XML_LANG): d for d in item.findall("description")}
    assert set(descs) == {"ko", "en", "ja"}
    assert descs["ko"].text == "- 한"
    assert all(d.get(S + "format") == "markdown" for d in descs.values())


def test_repo_changelogs_have_notes():
    text = open(os.path.join(ma.REPO, "CHANGELOG.md"), encoding="utf-8").read()
    version = next(l[3:].split(" ")[0] for l in text.splitlines() if l.startswith("## ") and l[3:4].isdigit())
    notes = ma.all_notes(version)
    assert set(notes) == {"ko", "en", "ja"} and all(notes.values())


def test_missing_version_fails():
    try:
        ma.all_notes("9.9.9")
    except SystemExit as e:
        assert "9.9.9" in str(e)
    else:
        raise AssertionError("없는 버전인데 실패하지 않음")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
