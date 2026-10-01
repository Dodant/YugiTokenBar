#!/usr/bin/env python3
"""Konami 한국 DB + YGOPRODeck → Resources/cards.json

한국 정발 정규 부스터 팩 중 『듀얼리스트의 태동』(2008-10-07, 첫 싱크로 팩) 이전만 수집한다.
사용: python3 tools/build-cards.py [출력경로]
"""
import html
import json
import re
import sys
import time
import urllib.request

TIER = {"N": 1, "R": 2, "SR": 3, "UR": 4}  # 그 외(SE 시크릿, UL 얼티미트, HR 홀로그래픽) = 5
BASE = "https://www.db.yugioh-card.com/yugiohdb/"
CUTOFF = "2008/10/07"
OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/cards.json"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "YugiTokenBar card builder (personal use)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def clean(s):
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
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
        level = first(r'box_card_level_rank[^>]*>.*?<span>([^<]*)</span>', row)
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
                "def": re.sub(r"[^\d?]", "", dfn) if dfn else None,
                "text": first(r'box_card_text[^"]*">(.*?)</dd>', row, ""),
            },
        })
    return cards


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
        print(f"{p['name']} → {best} ({p['setCode']})")
    missing = []
    for cid, info in infos.items():
        info["imageId"] = by_konami.get(cid)
        if info["imageId"] is None:
            missing.append(f"{cid} {info['name']}")

    out = {"packs": packs, "cards": {str(k): v for k, v in sorted(infos.items())}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"packs={len(packs)} distinct={len(infos)} missingImages={len(missing)}")
    for m in missing:
        print("  no image:", m)
    if len(packs) != 27 or any(not i["name"] for i in infos.values()) or any(not p["setCode"] for p in packs):
        sys.exit("검증 실패: 팩 수가 27이 아니거나 이름이 빈 카드·이미지 없는 팩이 있음")


if __name__ == "__main__":
    main()
