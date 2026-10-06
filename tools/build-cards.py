#!/usr/bin/env python3
"""Konami 한국 DB + YGOPRODeck → Resources/cards.json

한국 정발 정규 부스터 팩 중 『카오스 오리진즈』(2026-07-14)까지 100팩을 수집한다(76번째부터 VRAINS 이후 Modern).
같은 분류의 미니 팩(＋1 어시스트·익스팬션 팩, 얼티미트 스페셜 팩: 20장 이하, 노멀 없음)은 뺀다.
사용: python3 tools/build-cards.py [출력경로]
"""
import html
import json
import re
import sys
import time
import urllib.request

TIER = {"N": 1, "R": 2, "SR": 3, "UR": 4}  # 그 외(SE 시크릿, UL 얼티미트, HR 홀로그래픽 등) = 5 = 앱의 SE
BASE = "https://www.db.yugioh-card.com/yugiohdb/"
CUTOFF = "2026/07/15"  # 『카오스 오리진즈』까지
MINI = re.compile(r"어시스트 팩|익스팬션 팩|얼티미트 스페셜 팩")
# --reformat: 받아 오지 않고 기존 파일을 지금 형식으로만 다시 쓴다
REFORMAT = "--reformat" in sys.argv
ARGS = [a for a in sys.argv[1:] if a != "--reformat"]
OUT = ARGS[0] if ARGS else "Resources/cards.json"
# 팩 표지 몬스터는 어느 팩에서 나오든 SE (Yugipedia cover_card 기준. 표지가 마법·함정인 악몽의 미궁·어둠의 유산,
# 「영원한 화염」의 마의 덱 파괴 바이러스, 한글판에 없는 「장렬한 전투」 표지 2장은 뺀다)
COVER_SE = [
    4007,  # 푸른 눈의 백룡
    4223,  # 블랙 데몬즈 드래곤
    4737,  # 새크리파이스
    4740,  # 사우전드 아이즈 새크리파이스
    5628,  # 초마도검사 블랙 파라딘
    5489,  # 지옥시인 헬포에머
    5701,  # 엑조디아 네크로스
    5880,  # 혼돈의 흑마술사
    5976,  # 대천사 제라토
    6100,  # 호루스의 흑염룡 LV8
    6176,  # 창세신
    6236,  # 네프티스의 봉황신
    6315,  # 앤틱 기어 골렘
    6397,  # 사이버 엔드 드래곤
    6467,  # 엘리멘틀 히어로 샤이닝 플레어 윙맨
    7171,  # 궁극보옥신 레인보우 드래곤
    6565,  # 환마황제 라비엘
    6765,  # 엘리멘틀 히어로 블랙 네오스
    7275,  # 엘리멘틀 히어로 카오스 네오스
    6656,  # 엘리멘틀 히어로 샤이닝 피닉스 가이
    7085,  # 볼캐닉 데블
    6833,  # 사이버 다크 드래곤
    6989,  # 엘리멘틀 히어로 에어 네오스
    7411,  # 유벨－다스 엑스트레머 트라우리히 드라헨
    7574,  # 어니스트
    7734,  # 스타더스트 드래곤
    7898,  # 블랙 로즈 드래곤
    8007,  # 레드 데몬즈 드래곤 / 버스터
    7733,  # 니트로 워리어
    8090,  # 고대 요정 드래곤
    8475,  # 세이비어 스타 드래곤
    8651,  # 세이비어 데먼 드래곤
    8815,  # 블랙 페더 드래곤
    8969,  # 파동룡기사 드래고에퀴테스
    9117,  # 슈팅 스타 드래곤
    9331,  # 극신성제 오딘
    9508,  # 정크 버서커
    9656,  # No.17 레비아단 드래곤
    9729,  # 갤럭시아이즈 포톤 드래곤
    9914,  # CNo.39 유토피아 레이
    10064,  # 네오 갤럭시아이즈 포톤 드래곤
    10171,  # H－C 엑스칼리버
    10261,  # CNo.32 샤크 드레이크 바이스
    10404,  # No.92 위해신룡 Heart－eartH Dragon
    10525,  # No.107 갤럭시아이즈 타키온 드래곤
    10651,  # CNo.39 유토피아 레이 빅토리
    10777,  # CNo.96 블랙 스톰
    10932,  # CNo.101 사일런트 아너즈 다크 나이트
    11069,  # No.62 갤럭시아이즈 프라임 포톤 드래곤
    11213,  # 오드아이즈 펜듈럼 드래곤
    11385,  # 다크 리벨리온 엑시즈 드래곤
    11565,  # 룬아이즈 펜듈럼 드래곤
    11721,  # 클리어윙 싱크로 드래곤
    11835,  # 패왕흑룡 오드아이즈 리벨리온 드래곤
    11990,  # 레드 데몬즈 드래곤 스카라이트
    12155,  # 엔라이트멘트 파라딘
    12321,  # 크리스탈윙 싱크로 드래곤
    12445,  # 니르바나 하이 파라딘
    12628,  # 스타브 베놈 퓨전 드래곤
    12783,  # 패왕열룡 오드아이즈 레이징 드래곤
    12953,  # 패왕룡 즈아크
    13082,  # 파이어월 드래곤
    13258,  # 바렐로드 드래곤
    13409,  # 엑스코드 토커
    13590,  # 토폴로직 투리스바에나
    13742,  # 사이버스 매지션
    13921,  # 사이버스 클락 드래곤
    14114,  # 바렐로드 새비지 드래곤
    14286,  # 파이어월 X 드래곤
    14487,  # 바렐로드 X 드래곤
    14664,  # 파이어월 드래곤 다크플루이드
    14853,  # 라이트드래곤＠이그니스터
    15032,  # 액세스코드 토커
    15271,  # 용마방 기사 가이아
    15520,  # 아크 리벨리온 엑시즈 드래곤
    15692,  # 암드 드래곤 썬더 LV10
    16000,  # 용장합체 드래고닉 호프레이
    16228,  # 슈팅 세이비어 스타 드래곤
    16536,  # 바렐코드 드래곤
    16841,  # 초마도전사－마스터 오브 카오스
    17145,  # 오드아이즈 펜듈럼그래프 드래곤
    17443,  # 엘리멘틀 히어로 샤이닝 네오스 윙맨
    17797,  # 블랙 페더 어썰트 드래곤
    18188,  # CNo.62 네오 갤럭시아이즈 프라임 포톤 드래곤
    18510,  # 파이어월 드래곤 싱귤래리티
    18824,  # 코즈믹 퀘이사 드래곤
    19172,  # 패왕천룡 오드아이즈 아크레이 드래곤
    19493,  # 유벨－다스 에비히 리베 베히터
    19842,  # 파괴룡 간드라G
    20212,  # 환상의 소환신 엑조디아
    20517,  # CNo.32 샤크 드레이크 리바이스
    20768,  # 이블 히어로 네오스 로드
    21188,  # 어코드 토커＠이그니스터
    21453,  # FNo.0 미래황 호프 제알
    21801,  # DDDD 위차원왕 아크 크라이시스
    22150,  # 바렐슈라우드 드래곤
    22545,  # 더 크림즌 킹
    22976,  # 검은 혼돈의 마술사 블랙 카오스
]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "YugiTokenBar card builder (personal use)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def clean(s):
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = re.sub(r"<br\s*/?>", "\n", s)  # 링크 소재 줄처럼 &lt;br&gt; 로 이스케이프된 줄바꿈
    return "\n".join(" ".join(line.split()) for line in s.split("\n")).strip()


def first(pattern, text, default=None):
    m = re.search(pattern, text, re.S)
    return clean(m.group(1)) if m else default


def parse_products(page):
    rows = re.findall(
        r'<div class="time">\s*(\d{4}/\d\d/\d\d)\s*</div>.*?<span class="ws_nowrap">(【[^】]*】)</span>'
        r'.*?<p>([^<]*)</p>\s*<input type="hidden" class="link_value" value="[^"]*pid=(\d+)',
        page, re.S)
    boosters = [(d, html.unescape(n).strip(), pid) for d, cat, n, pid in rows
                if cat == "【정규 부스터 팩】" and d < CUTOFF and not MINI.search(html.unescape(n))]
    return sorted(boosters)


def parse_pack(page):
    cards = []
    seen = set()
    for row in re.split(r'<div class="t_row ', page)[1:]:
        cid = re.search(r'class="cid" value="(\d+)"', row)
        rid = re.search(r'lr_icon rid rid_(\d+)', row)
        if not cid or not rid:
            continue
        cid = int(cid.group(1))
        if cid in seen:
            continue
        seen.add(cid)
        label = first(r'lr_icon rid rid_\d+[^>]*>\s*<p>([^<]*)</p>', row)
        attr = first(r'box_card_attribute">.*?<span>([^<]*)</span>', row)
        kind = first(r'card_info_species_and_other_item"><span>(.*?)</span>', row)
        if kind:
            kind = kind.strip("[] \n").replace("\n", "").replace("／", "/")
        else:
            kind = first(r'box_card_effect">.*?<span>([^<]*)</span>', row, "일반")
        level = first(r'box_card_(?:level_rank|linkmarker)[^>]*>.*?<span>([^<]*)</span>', row)  # 레벨·랭크·링크 수
        scale = first(r'box_card_pen_scale">.*?P스케일\s*(\d+)', row)
        atk = first(r'class="atk_power">\s*<span>([^<]*)</span>', row)
        dfn = first(r'class="def_power"><span>(.*?)</span>', row)
        cards.append({
            "cid": cid,
            "label": label,
            "tier": TIER.get(label, 5),
            "info": {
                "name": first(r'<span class="card_name">(.*?)</span>', row),
                "attr": attr,
                "level": int(re.sub(r"\D", "", level)) if level else None,
                "type": kind,
                "atk": re.sub(r"[^\d?]", "", atk) if atk else None,
                "def": (re.sub(r"[^\d?]", "", dfn) or None) if dfn else None,  # 링크는 "-" → None
                "text": first(r'box_card_text[^"]*">(.*?)</dd>', row, ""),
                "scale": int(scale) if scale else None,
                "pendulum": first(r'box_card_pen_effect[^"]*">(.*?)</span>', row) or None,  # 펜듈럼 효과 없는 일반 펜듈럼은 ""
            },
        })
    return cards


def korean_pack_image(set_code):
    """Yugipedia 의 한글판 봉투 이미지 `<code>-BoosterKR.*` 를 폭 600px 썸네일로(원본이 더 작으면 원본). 없으면 None."""
    api = "https://yugipedia.com/api.php?format=json&action=query&"
    found = json.loads(get(api + f"list=allimages&aiprefix={set_code}-BoosterKR&ailimit=5"))["query"]["allimages"]
    time.sleep(0.5)
    if not found:
        return None
    pages = json.loads(get(api + f"prop=imageinfo&iiprop=url&iiurlwidth=600&titles={found[0]['title']}"))["query"]["pages"]
    time.sleep(0.5)
    info = next(iter(pages.values()))["imageinfo"][0]
    return info.get("thumburl") or info["url"]


def split_materials(cards):
    """융합 몬스터의 효과 텍스트 첫 줄(소재 줄)을 materials 로 뗀다. 이미 뗀 파일(--reformat)은 그대로.
    "이름" 은 100팩 카드면 {"cid"}, 아니면 {"name"}, 그 밖("전사족 몬스터")은 {"rule"}, 뒤의 "× N" 은 count.
    NEX 로만 소환하는 2종·베어트론은 소재 줄이 없다(첫 줄이 '.' 로 끝나는 효과문)."""
    names = {v["name"]: int(k) for k, v in cards.items()}
    nospace = {n.replace(" ", ""): c for n, c in names.items()}

    def material(part):
        m = re.fullmatch(r"(.+?)\s*×\s*(\d+)", part)
        part, count = (m.group(1), int(m.group(2))) if m else (part, None)
        if q := re.fullmatch(r'"([^"]+)"', part):  # "A"이나 "B" 는 rule
            cid = names.get(q.group(1)) or nospace.get(q.group(1).replace(" ", ""))
            out = {"cid": cid} if cid else {"name": q.group(1)}
        else:
            out = {"rule": part}
        return out | {"count": count} if count else out

    for info in cards.values():
        if "융합" not in info["type"].split("/") or "materials" in info:
            continue
        first, _, rest = info["text"].partition("\n")
        if first.endswith("."):
            continue
        assert "＋" in first or "×" in first or "합계" in first, (info["name"], first)
        info["materials"] = [material(p.strip()) for p in first.split("＋")]
        info["text"] = rest.strip()


def move_tiers(out):
    """팩마다 붙은 등급을 카드로 옮긴다: 재수록 카드는 수록 팩 중 가장 높은 등급. 팩에는 cid 목록만 남는다.
    이미 옮긴 파일(--reformat)은 그대로."""
    for p in out["packs"]:
        for c in p["cards"]:
            if isinstance(c, dict):
                info = out["cards"][str(c["cid"])]
                info["tier"] = max(info.get("tier", 1), c["tier"])
        p["cards"] = [c["cid"] if isinstance(c, dict) else c for c in p["cards"]]


def write(out):
    """팩 하나·카드 하나가 한 줄 — diff 를 읽을 수 있게. 등급 이식·표지 SE·융합 소재 분리도 여기서 한다."""
    move_tiers(out)
    for cid in COVER_SE:
        out["cards"][str(cid)]["tier"] = 5
    split_materials(out["cards"])
    dump = lambda x: json.dumps(x, ensure_ascii=False, separators=(",", ":"))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write('{"packs":[\n' + ",\n".join(dump(p) for p in out["packs"]) + '\n],"cards":{\n'
                + ",\n".join(f"{dump(k)}:{dump(v)}" for k, v in out["cards"].items()) + "\n}}\n")


def main():
    products = parse_products(get(BASE + "card_list.action?request_locale=ko"))
    packs, infos = [], {}
    for date, name, pid in products:
        page = get(BASE + f"card_search.action?ope=1&sess=1&pid={pid}&rp=99999&request_locale=ko")
        cards = parse_pack(page)
        for c in cards:
            infos.setdefault(c["cid"], c["info"])
        packs.append({"pid": pid, "name": name, "date": date.replace("/", "-"),
                      "cards": [{"cid": c["cid"], "tier": c["tier"], "label": c["label"]} for c in cards]})
        dist = {}
        for c in cards:
            dist[c["label"]] = dist.get(c["label"], 0) + 1
        print(f"{date} {name}: {len(cards)} {dist}", flush=True)
        time.sleep(1)

    ygo = json.loads(get("https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes"))["data"]
    by_konami, sets_of = {}, {}
    for c in ygo:
        for m in c.get("misc_info", []):
            if m.get("konami_id"):
                by_konami.setdefault(int(m["konami_id"]), c["card_images"][0]["id"])
                sets_of.setdefault(int(m["konami_id"]), set()).update(s["set_name"] for s in c.get("card_sets", []))

    # 팩 이미지: 카드가 가장 많이 겹치는 TCG 팩(겹친 수 / 두 팩 중 큰 쪽 크기 → 재록 모음집은 밀려남)
    sets = {s["set_name"]: s for s in json.loads(get("https://db.ygoprodeck.com/api/v7/cardsets.php"))}
    for p in packs:
        count = {}
        for c in p["cards"]:
            for s in sets_of.get(c["cid"], ()):
                count[s] = count.get(s, 0) + 1
        best = max((s for s in count if sets.get(s, {}).get("set_image")),
                   key=lambda s: count[s] / max(len(p["cards"]), sets[s]["num_of_cards"]), default=None)
        p["setCode"] = sets[best]["set_code"] if best else None
        p["imageURL"] = korean_pack_image(p["setCode"]) or sets[best]["set_image"] if best else None
        print(f"{p['name']} → {best} ({p['setCode']}) {p['imageURL']}")
    missing = []
    for cid, info in infos.items():
        info["imageId"] = by_konami.get(cid)
        if info["imageId"] is None:
            missing.append(f"{cid} {info['name']}")

    # 빈 칸(None)은 빼서 용량을 줄인다 — 앱은 없는 키를 nil 로 읽는다
    out = {"packs": packs, "cards": {str(k): {f: x for f, x in v.items() if x is not None} for k, v in sorted(infos.items())}}
    write(out)
    print(f"packs={len(packs)} distinct={len(infos)} missingImages={len(missing)}")
    for m in missing:
        print("  no image:", m)
    if len(packs) != 100 or any(not i["name"] for i in infos.values()) or any(not p["imageURL"] for p in packs):
        sys.exit("검증 실패: 팩 수가 100이 아니거나 이름이 빈 카드·이미지 없는 팩이 있음")


if __name__ == "__main__":
    if REFORMAT:
        with open(OUT, encoding="utf-8") as f:
            write(json.load(f))
    else:
        main()
