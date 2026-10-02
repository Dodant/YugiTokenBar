#!/usr/bin/env python3
"""Konami 한국 DB + YGOPRODeck → Resources/cards.json

한국 정발 정규 부스터 팩 중 『이터니티 코드』(2020-04-14, VRAINS 마지막 팩)까지 75팩을 수집한다.
사용: python3 tools/build-cards.py [출력경로]
"""
import html
import json
import re
import sys
import time
import urllib.request

TIER = {"N": 1, "R": 2, "SR": 3, "UR": 4}  # 그 외(SE 시크릿, UL 얼티미트, HR 홀로그래픽) = 5 — 앱(CardDB.load)이 UR(4)로 합친다
BASE = "https://www.db.yugioh-card.com/yugiohdb/"
CUTOFF = "2020/07/25"  # 『라이즈 오브 더 듀얼리스트』(VRAINS 이후 첫 팩) 직전까지
# --reformat: 받아 오지 않고 기존 파일을 지금 형식으로만 다시 쓴다
REFORMAT = "--reformat" in sys.argv
ARGS = [a for a in sys.argv[1:] if a != "--reformat"]
OUT = ARGS[0] if ARGS else "Resources/cards.json"


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
                if cat == "【정규 부스터 팩】" and d < CUTOFF]
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
    "이름" 은 75팩 카드면 {"cid"}, 아니면 {"name"}, 그 밖("전사족 몬스터")은 {"rule"}, 뒤의 "× N" 은 count.
    NEX 로만 소환하는 2종은 소재 줄이 없다(첫 줄이 '.' 로 끝나는 효과문)."""
    names = {v["name"]: int(k) for k, v in cards.items()}
    nospace = {n.replace(" ", ""): c for n, c in names.items()}

    def material(part):
        m = re.fullmatch(r"(.+?)\s*×\s*(\d+)", part)
        part, count = (m.group(1), int(m.group(2))) if m else (part, None)
        if q := re.fullmatch(r'"(.+)"', part):
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


def write(out):
    """팩 하나·카드 하나가 한 줄 — diff 를 읽을 수 있게. 융합 소재 분리도 여기서 한다."""
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
    if len(packs) != 75 or any(not i["name"] for i in infos.values()) or any(not p["imageURL"] for p in packs):
        sys.exit("검증 실패: 팩 수가 75가 아니거나 이름이 빈 카드·이미지 없는 팩이 있음")


if __name__ == "__main__":
    if REFORMAT:
        with open(OUT, encoding="utf-8") as f:
            write(json.load(f))
    else:
        main()
