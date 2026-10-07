#!/usr/bin/env python3
"""build-cards.py 의 네트워크 없는 함수 자체 검사. 사용: python3 tools/test_build_cards.py"""
import importlib.util
import json
import os
import tempfile

spec = importlib.util.spec_from_file_location("bc", os.path.join(os.path.dirname(__file__), "build-cards.py"))
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)

# 실제 상세 페이지(2026-10-07)의 구조를 줄인 것
JA_MONSTER = """
<div id="cardname" class="pc cardname"><h1>
  <span class="ruby">しょうかんしライズベルト</span>
  召喚師ライズベルト
  <span>Risebell the Summoner</span>
</h1></div>
<div id="CardSet"><div id="CardImgSet"><span class="item_box_value">x</span></div>
<div class="CardText">
  <div class="frame imgset">
    <div class="item_box"><span class="item_box_title"></span><span class="item_box_value"> 光属性 </span></div>
    <div class="item_box"><span class="item_box_title"></span><span class="item_box_value"> レベル 3 </span></div>
  </div>
  <div class="frame"><div class="item_box"><p class="species">
    <span>サイキック族</span> <span>／</span> <span>ペンデュラム／通常</span></p></div></div>
</div><!-- #CardTextSet -->
<div class="CardText pen"><div class="frame pen_effect"><div class="item_box_text">
  <div class="text_linebreak">①：レベルを１つ上げる。</div></div></div></div><!-- CardText -->
<div class="CardText"><div class="item_box_text"><div class="text_title">カードテキスト</div>
  <div class="text_linebreak">心優しき兄&lt;br&gt;二行目</div></div></div><!-- CardText -->
</div>
<div id="update_list" class="list"><div class="t_body">
  <div class="t_row "><div class="inside"><div class="time"> 2016-12-23 </div>
    <div class="flex_1 contents "><div class="card_number">SD31-JP018</div>
    <div class="pack_name flex_1" > ストラクチャーデッキ </div></div></div></div>
  <div class="t_row "><div class="inside"><div class="time"> 2014-04-19 </div>
    <div class="flex_1 contents "><div class="card_number">CROS-JP001</div>
    <div class="pack_name flex_1" > クロスオーバー・ソウルズ </div></div></div></div>
</div></div>
"""
EN_SPELL = """
<div id="cardname" class="pc cardname"><h1>
  Polymerization
</h1></div>
<div id="CardSet"><div class="CardText">
  <div class="frame"><div class="item_box t_center"><span class="item_box_title"> Icon </span>
    <span class="item_box_value"> Normal Spell </span></div></div>
</div><!-- #CardTextSet -->
<div class="CardText"><div class="item_box_text"><div class="text_title">Card Text</div>
  <div class="text_linebreak">Fusion Summon 1 Fusion Monster.</div></div></div></div>
<div id="update_list" class="list"><div class="t_body"></div></div>
"""
EN_MISSING = '<div id="cardname" class="pc cardname"><h1>\n</h1></div><div id="CardSet"></div>'
# 실제 not-found 응답(cid=99999, 2026-10-07)을 줄인 것: 200 이고 cardname 없음
EN_NOT_FOUND = """<nav id="pan_nav"><div><ul><li><a href="/yugiohdb/">HOME</a></li><li>&raquo;</li>
<li>Card information not found.</li></ul></div></nav><div id="main980"><article><div id="article_body">
<div class="no_data" >
  Card information not found.
</div></article></div>"""
JA_NOT_FOUND = EN_NOT_FOUND.replace("HOME", "ホーム").replace("Card information not found.", "カード情報がありません。")


def test_parse_detail_monster():
    info, packs = bc.parse_detail(JA_MONSTER)
    assert info == {"name": "召喚師ライズベルト", "attr": "光属性", "type": "サイキック族/ペンデュラム/通常",
                    "text": "心優しき兄\n二行目", "pendulum": "①：レベルを１つ上げる。"}, info
    assert packs == [["ストラクチャーデッキ", "2016-12-23"], ["クロスオーバー・ソウルズ", "2014-04-19"]], packs


def test_parse_detail_spell_and_missing():
    info, packs = bc.parse_detail(EN_SPELL)
    assert info == {"name": "Polymerization", "attr": "Normal Spell", "type": None,
                    "text": "Fusion Summon 1 Fusion Monster.", "pendulum": None}, info
    assert packs == []
    info, _ = bc.parse_detail(EN_MISSING)
    assert info["name"] == ""


def test_load_cache_skips_partial_line():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "en.jsonl")
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"cid": 1, "info": {"name": "A"}, "packs": []}) + "\n")
            f.write('{"cid": 2, "info": {"na')  # Ctrl-C 로 끊긴 줄
        assert list(bc.load_cache(path)) == [1]
        assert bc.load_cache(os.path.join(d, "none.jsonl")) == {}


def test_load_cache_survives_cut_multibyte():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "ja.jsonl")
        with open(path, "wb") as f:
            f.write((json.dumps({"cid": 1, "info": {"name": "A"}, "packs": []}) + "\n").encode())
            f.write('{"cid": 2, "info": {"name": "召'.encode("utf-8")[:-1])  # 글자 중간에서 끊김
        assert list(bc.load_cache(path)) == [1]


def test_end_line_after_cut_multibyte():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "ja.jsonl")
        with open(path, "wb") as f:
            f.write((json.dumps({"cid": 1, "info": {"name": "A"}, "packs": []}) + "\n").encode())
            f.write('{"cid": 2, "info": {"name": "召'.encode("utf-8")[:-1])
        bc.end_line(path)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"cid": 3, "info": {"name": "C"}, "packs": []}) + "\n")
        assert sorted(bc.load_cache(path)) == [1, 3]
        bc.end_line(path)  # 이미 줄바꿈으로 끝나면 그대로
        bc.end_line(os.path.join(d, "none.jsonl"))  # 없는 파일도 무사
        assert open(path, "rb").read().count(b"\n") == 3


def test_get_card_page_retries():
    calls, sleeps = [], []
    pages = iter([OSError("reset"), "<html>점검 중</html>", EN_SPELL])
    def fake_get(url):
        calls.append(url)
        p = next(pages)
        if isinstance(p, Exception):
            raise p
        return p
    real_get, real_sleep = bc.get, bc.time.sleep
    bc.get, bc.time.sleep = fake_get, sleeps.append
    try:
        assert bc.get_card_page("u") == EN_SPELL and len(calls) == 3 and sleeps == [30, 60]
        for nf in (EN_NOT_FOUND, JA_NOT_FOUND):  # 그 언어에 없는 카드: 재시도 없이 name "" 로
            calls.clear()
            pages = iter([nf])
            assert bc.get_card_page("u") == nf and len(calls) == 1
            assert bc.parse_detail(nf)[0]["name"] == ""
        pages = iter(["x"] * 4)
        try:
            bc.get_card_page("u")
            assert False
        except RuntimeError:
            pass
    finally:
        bc.get, bc.time.sleep = real_get, real_sleep


KO = {
    "packs": [{"pid": "1", "name": "한국팩", "date": "2004-01-01", "cards": [10, 11, 12]}],
    "cards": {
        "10": {"name": "가", "attr": "빛", "level": 4, "type": "전사족/일반", "atk": "1000", "def": "1000", "text": "설명", "imageId": 1, "tier": 1},
        "11": {"name": "나", "attr": "마법", "type": "일반", "text": "효과", "imageId": 2, "tier": 2, "kind": "spell"},
        "12": {"name": "다", "attr": "어둠", "level": 6, "type": "악마족/융합/효과", "atk": "2000", "def": "1000", "text": "효과",
               "imageId": 3, "tier": 3, "summons": ["fusion"],
               "materials": [{"cid": 10}, {"name": "미노타우로스"}, {"rule": "\"검투수\" 몬스터", "count": 2}]},
    },
}


def rec(cid, name, text="", **kw):
    return {"cid": cid, "info": {"name": name, "attr": kw.get("attr"), "type": kw.get("type"), "text": text, "pendulum": None},
            "packs": kw.get("packs", [])}


def test_localize_falls_back_whole_card():
    jp_recs = {10: rec(10, "カ", "説明", attr="光属性"), 11: rec(11, "", "")}
    jp, missing, _ = bc.localize(KO, jp_recs)
    assert jp["cards"]["10"]["name"] == "カ" and jp["cards"]["10"]["attr"] == "光属性"
    assert "type" not in jp["cards"]["10"]  # 그 언어에 없는 칸은 뺀다 (KO 를 섞지 않는다)
    assert jp["cards"]["10"]["atk"] == "1000" and jp["cards"]["10"]["tier"] == 1  # 공유 필드는 KO
    assert jp["cards"]["11"] == KO["cards"]["11"]  # 이름이 빈 카드 → KO 통째로
    assert jp["cards"]["12"]["name"] == "다"  # 캐시에 없는 카드도 KO
    assert missing == ["11", "12"]
    en_recs = {10: rec(10, "Ka", "Desc"), 11: rec(11, "Na", "Eff"), 12: rec(12, "", "")}
    en, missing, _ = bc.localize(KO, en_recs, fallback=jp, fallback_missing=["11", "12"])
    assert en["cards"]["12"]["name"] == "다"  # EN 없음 → JP(이것도 KO 대체)
    assert missing == ["12"]
    assert list(en["cards"]) == list(KO["cards"]) and en["packs"][0]["cards"] == [10, 11, 12]


def test_split_lang_materials():
    mats = KO["cards"]["12"]["materials"]
    text, out, ok = bc.split_lang_materials("「カ」＋「ミノタウルス」＋「剣闘獣」モンスター×２\n①：効果", mats)
    assert ok and text == "①：効果"
    assert out == [{"cid": 10}, {"name": "ミノタウルス"}, {"rule": "「剣闘獣」モンスター", "count": 2}], out
    text, out, ok = bc.split_lang_materials('"Ka" + "Minotaur" + 2 "Gladiator Beast" monsters\nEffect.', mats)
    assert ok and text == "Effect." and out[1] == {"name": "Minotaur"} and out[2] == {"rule": '2 "Gladiator Beast" monsters'}
    text, out, ok = bc.split_lang_materials('"Ka" + "Minotaur"\nEffect.', mats)  # 조각 수가 다르면 KO 그대로
    assert not ok and out == mats and text == "Effect."


def test_pack_names():
    recs = {10: rec(10, "A", packs=[["OCG 팩", "2003-01-01"], ["재록", "2010-01-01"], ["OCG 팩", "2003-01-01"]]),
            11: rec(11, "B", packs=[["OCG 팩", "2003-01-01"]]),
            12: rec(12, "C", packs=[["재록", "2010-01-01"]])}
    assert bc.pack_names(KO, recs) == {"1": ("OCG 팩", 2)}
    tie = {10: rec(10, "A", packs=[["늦은 팩", "2005-01-01"], ["이른 팩", "2002-01-01"]])}
    assert bc.pack_names(KO, tie) == {"1": ("이른 팩", 1)}
    assert bc.pack_names(KO, {}) == {"1": (None, 0)}


def test_verify():
    jp, _, _ = bc.localize(KO, {10: rec(10, "カ")})
    assert bc.verify({"ko": KO, "ja": jp}) == []
    bad = json.loads(json.dumps(jp))
    bad["cards"]["10"]["tier"] = 5
    del bad["cards"]["11"]
    problems = bc.verify({"ko": KO, "ja": bad})
    assert any("cid" in p for p in problems) and any("tier" in p for p in problems), problems


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
