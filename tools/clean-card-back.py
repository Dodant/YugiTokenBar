#!/usr/bin/env python3
"""Resources/card-back.jpg 를 만든다: Yugipedia Back-KR.png 에서 로고 두 개를 지운다.

    curl -A YugiTokenBar -o /tmp/Back-KR.png https://ms.yugipedia.com//7/70/Back-KR.png
    python3 tools/clean-card-back.py /tmp/Back-KR.png Resources/card-back.jpg

로고 자리는 같은 그림의 다른 부분으로 덮는다(경계는 흐리게 섞는다).
KONAMI(왼쪽 위) ← 좌우 반전한 오른쪽 위, 유희왕 로고(오른쪽 아래) ← 180도 돌린 왼쪽 위.
좌표는 923×1351 원본 기준.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageOps


def patch(img, box, src, feather=14):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=feather, fill=255)
    return Image.composite(src, img, mask.filter(ImageFilter.GaussianBlur(feather)))


src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGB")
assert img.size == (923, 1351), img.size
img = patch(img, (40, 30, 300, 115), ImageOps.mirror(img))
img = patch(img, (540, 1095, 905, 1342), img.rotate(180))
img.save(dst, quality=88, optimize=True)
