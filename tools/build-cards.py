#!/usr/bin/env python3
"""Konami 카드 DB + YGOPRODeck → Resources/cards_KO.json · cards_JP.json · cards_EN.json

한국 정발 정규 부스터 팩 중 『카오스 오리진즈』(2026-07-14)까지 100팩을 수집한다(76번째부터 VRAINS 이후 Modern).
같은 분류의 미니 팩(＋1 어시스트·익스팬션 팩, 얼티미트 스페셜 팩: 20장 이하, 노멀 없음)은 뺀다.
사용: python3 tools/build-cards.py [--lang ko|ja|en|all] [--reformat]
"""
import argparse
import html
import json
import os
import re
import sys
import time
import urllib.request

TIER = {"N": 1, "R": 2, "SR": 3, "UR": 4}  # 그 외(SE 시크릿, UL 얼티미트, HR 홀로그래픽 등) = 5 = 앱의 SE
BASE = "https://www.db.yugioh-card.com/yugiohdb/"
CUTOFF = "2026/07/15"  # 『카오스 오리진즈』까지
MINI = re.compile(r"어시스트 팩|익스팬션 팩|얼티미트 스페셜 팩")
LANGS = {"ko": "KO", "ja": "JP", "en": "EN"}
# 세 파일이 같은 카드 필드(KO 기준)와 언어마다 다른 카드 필드
SHARED = ("tier", "imageId", "level", "atk", "def", "scale", "kind", "summons")
TEXT_FIELDS = ("name", "attr", "type", "text", "pendulum")
KINDS = {"마법": "spell", "함정": "trap"}
SUMMONS = {"의식": "ritual", "융합": "fusion", "싱크로": "synchro", "엑시즈": "xyz", "펜듈럼": "pendulum", "링크": "link"}  # 시대 순


def out_path(lang):
    return f"Resources/cards_{LANGS[lang]}.json"


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


def parse_detail(page):
    """카드 상세 페이지(ja·en) → (TEXT_FIELDS 사전, [[수록 팩 이름, 날짜], …]). 그 언어에 없는 카드는 name 이 ""."""
    name = ""
    if h1 := re.search(r'<div id="cardname"[^>]*>\s*<h1>(.*?)</h1>', page, re.S):
        body = re.sub(r'<span class="ruby">.*?</span>', "", h1.group(1), flags=re.S)
        body = re.sub(r"<span>.*?</span>", "", body, flags=re.S)  # ja 의 영문 병기
        name = clean(body)
    start = page.find('<div class="CardText">', max(page.find('<div id="CardSet"'), 0))
    end = page.find("<!-- #CardTextSet -->")
    head = page[start:end] if 0 <= start < end else ""
    rest = page[end:] if end >= 0 else ""
    first_value = first(r'<span class="item_box_value">(.*?)</span>', head)  # 몬스터는 속성, 마법·함정은 아이콘(Normal Spell 등)
    species = first(r'<p class="species">(.*?)</p>', head)
    info = {
        "name": name,
        "attr": first_value or None,
        "type": re.sub(r"\s*／\s*", "/", species) if species else None,
        "text": first(r'<div class="CardText">\s*<div class="item_box_text">.*?<div class="text_linebreak">(.*?)</div>', rest, ""),
        "pendulum": first(r'<div class="frame pen_effect">.*?<div class="text_linebreak">(.*?)</div>', rest) or None,
    }
    packs = []
    if (i := page.find('<div id="update_list"')) >= 0:
        for date, pack in re.findall(r'<div class="time">\s*([\d-]+)\s*</div>.*?<div class="pack_name[^"]*"\s*>(.*?)</div>', page[i:], re.S):
            packs.append([clean(pack), date])
    return info, packs


def cache_path(lang):
    return f"tools/cache/{lang}.jsonl"


def load_cache(path):
    """이어 받기용 캐시(한 줄에 카드 하나). 끊겨서 반쯤 써진 줄은 건너뛴다 → 그 카드는 다시 받는다."""
    recs = {}
    if not os.path.exists(path):
        return recs
    with open(path, encoding="utf-8", errors="replace") as f:  # 끊긴 줄이 글자 중간일 수 있다
        for line in f:
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            recs[r["cid"]] = r
    return recs


def get_card_page(url, retries=4):
    """상세 페이지를 받는다. 네트워크 오류나 카드 페이지가 아닌 응답(점검·오류 페이지)은 쉬었다 다시 받고, 끝내 안 되면 예외."""
    for attempt in range(1, retries + 1):
        try:
            page = get(url)
            if '<div id="cardname"' in page:
                return page
            err = "카드 페이지가 아닌 응답"
        except OSError as e:  # URLError·타임아웃·연결 끊김
            err = repr(e)
        print(f"  재시도 {attempt}/{retries}: {err} {url}", flush=True)
        if attempt == retries:
            raise RuntimeError(f"{url}: {err}")
        time.sleep(30 * attempt)


def fetch_lang(lang, ko):
    """KO 에 있는 cid 만 상세 페이지를 1초 간격으로 받는다. 받은 것은 바로 캐시에 덧붙여, 끊기면 같은 명령으로 이어 받는다."""
    path = cache_path(lang)
    recs = load_cache(path)
    todo = [int(c) for c in ko["cards"] if int(c) not in recs]
    print(f"{lang}: 캐시 {len(recs)}장, 받을 카드 {len(todo)}장 (약 {len(todo) * 1.5 / 3600:.1f}시간)", flush=True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a+", encoding="utf-8") as f:
        f.seek(0, os.SEEK_END)
        if f.tell():  # 끊긴 줄 뒤에 이어 붙이면 새 줄이 깨진다
            f.seek(f.tell() - 1)
            if f.read(1) != "\n":
                f.write("\n")
        for i, cid in enumerate(todo, 1):
            info, packs = parse_detail(get_card_page(BASE + f"card_search.action?ope=2&cid={cid}&request_locale={lang}"))
            recs[cid] = {"cid": cid, "info": info, "packs": packs}
            f.write(json.dumps(recs[cid], ensure_ascii=False) + "\n")
            f.flush()
            if i % 100 == 0 or i == len(todo):
                print(f"{lang} {i}/{len(todo)} {cid} {info['name']}", flush=True)
            time.sleep(1)
    return recs


# 원판 팩명 매핑이 틀렸을 때 고치는 표: {"ja": {KO pid: 이름}, "en": {...}}
PACK_NAME_OVERRIDES = {"ja": {}, "en": {}}
MAT_COUNT = re.compile(r"(.+?)\s*[×xX]\s*([0-9０-９]+)")
QUOTED = re.compile(r'"(.+)"|「(.+)」')


def merge(base, text):
    """KO 카드(base)의 키 순서대로 두되, 언어별 필드는 text 값으로(그 언어에 없는 칸은 뺀다). text 는 늘 둔다."""
    out = {}
    for k, v in base.items():
        if k == "text":
            out[k] = text.get("text") or ""
        elif k in TEXT_FIELDS:
            if text.get(k):
                out[k] = text[k]
        else:
            out[k] = v
    for k in TEXT_FIELDS:
        if k not in out and text.get(k):
            out[k] = text[k]
    return out


def split_lang_materials(text, ko_mats):
    """언어 텍스트 첫 줄(소재 줄)을 떼고 KO 소재와 같은 자리끼리 맞춘다. cid 소재는 KO 그대로,
    name·rule 소재는 그 언어 조각(따옴표는 name 에서 벗기고 끝의 × N 은 count). 조각 수가 다르면 KO 소재 그대로 (ok=False)."""
    first_line, _, rest = text.partition("\n")
    parts = [p.strip() for p in re.split(r"\s+\+\s+|\s*＋\s*", first_line) if p.strip()]
    if len(parts) != len(ko_mats):
        return rest.strip(), ko_mats, False
    out = []
    for part, m in zip(parts, ko_mats):
        if "cid" in m:
            out.append(m)
            continue
        c = MAT_COUNT.fullmatch(part)
        body, count = (c.group(1), int(c.group(2))) if c else (part, None)
        if "name" in m:
            q = QUOTED.fullmatch(body)
            entry = {"name": (q.group(1) or q.group(2)) if q else body}
        else:
            entry = {"rule": body}
        out.append(entry | ({"count": count} if count else {}))
    return rest.strip(), out, True


def localize(ko, recs, fallback=None, fallback_missing=()):
    """KO 를 틀로 언어 파일을 만든다. 그 언어에 없는 카드(이름이 빈 카드)는 언어별 필드 전부를 fallback(이미 만든 JP)
    또는 KO 에서 통째로 가져온다. → (out, 대체된 cid 목록, 소재 줄이 안 맞은 cid 목록)"""
    out = {"packs": [dict(p) for p in ko["packs"]], "cards": {}}
    missing, mismatched = [], []
    for cid, base in ko["cards"].items():
        r = recs.get(int(cid))
        if not r or not r["info"].get("name"):
            out["cards"][cid] = dict((fallback or ko)["cards"][cid])
            missing.append(cid)
            continue
        info = merge(base, r["info"])
        if "materials" in base:
            info["text"], info["materials"], ok = split_lang_materials(info["text"], base["materials"])
            if not ok and any("cid" not in m for m in base["materials"]):
                mismatched.append(cid)
        out["cards"][cid] = info
    return out, missing, mismatched


def pack_names(ko, recs):
    """KO 팩마다 수록 카드들의 그 언어 수록 팩 이름을 세어 가장 많은 것 (동률이면 발매일이 빠른 쪽). → {pid: (이름|None, 겹친 수)}"""
    names = {}
    for p in ko["packs"]:
        count, earliest = {}, {}
        for cid in p["cards"]:
            for name, date in {tuple(x) for x in recs.get(cid, {}).get("packs", [])}:
                count[name] = count.get(name, 0) + 1
                earliest[name] = min(earliest.get(name, date), date)
        best = min(count, key=lambda n: (-count[n], earliest[n]), default=None)
        names[p["pid"]] = (best, count.get(best, 0))
    return names


def verify(files):
    """세 파일이 같은 팩·같은 카드·같은 공유 필드인지, 모든 카드에 이름이 있는지. 문제 문장 목록(비면 통과)."""
    ko, problems = files["ko"], []
    mat_ids = lambda c: [(m.get("cid"), m.get("count")) if "cid" in m else None for m in c.get("materials", [])]
    for lang, f in files.items():
        if [(p["pid"], p["cards"]) for p in f["packs"]] != [(p["pid"], p["cards"]) for p in ko["packs"]]:
            problems.append(f"{lang}: 팩 pid·카드 목록이 KO 와 다름")
        if list(f["cards"]) != list(ko["cards"]):
            problems.append(f"{lang}: 카드 cid 목록·순서가 KO 와 다름")
        for cid, c in f["cards"].items():
            k = ko["cards"].get(cid, {})
            if not c.get("name"):
                problems.append(f"{lang}: {cid} 이름 없음")
            for field in SHARED:
                if c.get(field) != k.get(field):
                    problems.append(f"{lang}: {cid} {field} 가 KO 와 다름")
            if mat_ids(c) != mat_ids(k):
                problems.append(f"{lang}: {cid} 소재가 KO 와 다름")
    return problems


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


def add_codes(cards):
    """언어와 상관없는 코드 필드: 마법·함정은 kind, 몬스터는 type 칸의 소환법을 summons(시대 순)로. 앱 로직은 이것만 본다."""
    for info in cards.values():
        info.pop("kind", None)
        info.pop("summons", None)
        if kind := KINDS.get(info.get("attr")):
            info["kind"] = kind
            continue
        parts = (info.get("type") or "").split("/")
        if summons := [code for name, code in SUMMONS.items() if name in parts]:
            info["summons"] = summons


def normalize_ko(out):
    """KO 전용 후처리: 등급 이식·표지 SE·융합 소재 분리·코드 필드. 이미 한 것은 그대로(--reformat)."""
    move_tiers(out)
    for cid in COVER_SE:
        out["cards"][str(cid)]["tier"] = 5
    split_materials(out["cards"])
    add_codes(out["cards"])


def dump(out, path):
    """팩 하나·카드 하나가 한 줄 — diff 를 읽을 수 있게."""
    line = lambda x: json.dumps(x, ensure_ascii=False, separators=(",", ":"))
    with open(path, "w", encoding="utf-8") as f:
        f.write('{"packs":[\n' + ",\n".join(line(p) for p in out["packs"]) + '\n],"cards":{\n'
                + ",\n".join(f"{line(k)}:{line(v)}" for k, v in out["cards"].items()) + "\n}}\n")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_ko():
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
    normalize_ko(out)
    dump(out, out_path("ko"))
    print(f"packs={len(packs)} distinct={len(infos)} missingImages={len(missing)}")
    for m in missing:
        print("  no image:", m)
    if len(packs) != 100 or any(not i["name"] for i in infos.values()) or any(not p["imageURL"] for p in packs):
        sys.exit("검증 실패: 팩 수가 100이 아니거나 이름이 빈 카드·이미지 없는 팩이 있음")


def build_lang(lang):
    """cards_KO.json 을 틀로 JP·EN 파일을 만든다. EN 은 cards_JP.json 을 대체로 쓴다."""
    ko = load(out_path("ko"))
    recs = fetch_lang(lang, ko)
    fallback, fallback_missing = None, ()
    if lang == "en" and os.path.exists(out_path("ja")):
        fallback = load(out_path("ja"))
        fallback_missing = {cid for cid, c in fallback["cards"].items() if c.get("name") == ko["cards"][cid].get("name")}
    out, missing, mismatched = localize(ko, recs, fallback, fallback_missing)
    for p, (name, n) in zip(out["packs"], pack_names(ko, recs).values()):
        override = PACK_NAME_OVERRIDES[lang].get(p["pid"])
        print(f"  팩 {p['name']} → {override or name} ({n}/{len(p['cards'])}){' [덮어씀]' if override else ''}")
        p["name"] = override or name or p["name"]
    dump(out, out_path(lang))
    label = lambda cid: "KO" if fallback is None or cid in fallback_missing else "JP"
    print(f"{lang}: 대체 {len(missing)}장, 소재 줄 불일치 {len(mismatched)}장")
    for cid in missing:
        print(f"  대체: {cid} {ko['cards'][cid]['name']} (→ {label(cid)})")
    for cid in mismatched:
        print(f"  소재 줄 불일치(KO 소재 유지): {cid} {ko['cards'][cid]['name']}")


def reformat(langs):
    """받아 오지 않고 있는 파일만 지금 형식으로 다시 쓴다. JP·EN 은 KO 와 같은 필드를 KO 에서 다시 맞춘다."""
    ko = load(out_path("ko"))
    normalize_ko(ko)
    if "ko" in langs:
        dump(ko, out_path("ko"))
    for lang in ("ja", "en"):
        if lang in langs and os.path.exists(out_path(lang)):
            out = load(out_path(lang))
            sync_shared(ko, out)
            dump(out, out_path(lang))


def sync_shared(ko, out):
    """언어 파일의 팩(이름 빼고)과 카드 공유 필드를 KO 값으로 맞춘다."""
    for p, k in zip(out["packs"], ko["packs"]):
        p.update({f: v for f, v in k.items() if f != "name"})
    for cid, info in out["cards"].items():
        base = ko["cards"][cid]
        for f in SHARED:
            if f in base:
                info[f] = base[f]
            else:
                info.pop(f, None)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Konami 카드 DB → Resources/cards_XX.json")
    ap.add_argument("--lang", choices=["ko", "ja", "en", "all"], default="all")
    ap.add_argument("--reformat", action="store_true", help="받아 오지 않고 있는 파일을 지금 형식으로만 다시 쓴다")
    args = ap.parse_args()
    langs = ["ko", "ja", "en"] if args.lang == "all" else [args.lang]
    if args.reformat:
        reformat(langs)
    else:
        if "ko" in langs:
            build_ko()
        for lang in ("ja", "en"):
            if lang in langs:
                build_lang(lang)
    files = {lang: load(out_path(lang)) for lang in LANGS if os.path.exists(out_path(lang))}
    if problems := verify(files):
        print("\n".join(problems[:50]))
        sys.exit(f"검증 실패: {len(problems)}건")
    print(f"검증 통과: {', '.join(files)}")
