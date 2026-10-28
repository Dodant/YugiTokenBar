import Foundation

enum ImageSource {
    /// passcode → 공식 오버프레임(Yugipedia "Extended art") 이미지. 워터마크(SAMPLE) 없는 실물 스캔·공식 이미지만.
    /// 131팩(정규 부스터·듀얼리스트 팩)에 든 오버프레임 26종 전부(2026-10-28 Yugipedia 목록 기준). 카드별 출처는 docs/sources.md. 같은 카드를 `Balance.overframeCopies` 장 모으면 해금(`Game.unlockOverframe`).
    /// ponytail: 손으로 고른 표. 새 오버프레임이 나오면 Card Gallery 의 `-EA`·LOSP 등 파일을 확인해 한 줄 추가한다(docs/sources.md 표도).
    static let overframe: [Int: String] = [
        35952884: "https://ms.yugipedia.com//e/e7/ShootingQuasarDragon-RA05-EN-UR-1E-EA.png",
        6218704: "https://ms.yugipedia.com//a/ae/OddEyesArcrayDragon-RA05-EN-UR-1E-EA.png",
        21637210: "https://ms.yugipedia.com//7/7c/FirewallDragonSingularity-RA05-EN-UR-1E-EA.png",
        35405755: "https://ms.yugipedia.com//c/c1/KurikaraDivincarnate-RA05-EN-UR-1E-EA.png",
        48130397: "https://ms.yugipedia.com//f/f6/SuperPolymerization-RA05-EN-UR-1E-EA.png",
        97045737: "https://ms.yugipedia.com//7/7e/DominusPurge-RA05-EN-UR-1E-EA.png",
        31801517: "https://ms.yugipedia.com//7/77/Number62GalaxyEyesPrimePhotonDragon-LOSP-JP-PScR.png",
        13331639: "https://ms.yugipedia.com//f/f7/SupremeKingZARC-LOSP-JP-PScR.png",
        22850702: "https://ms.yugipedia.com//f/f2/ChaosAngel-LOSP-JP-PScR.png",
        98127546: "https://ms.yugipedia.com//c/c1/UnderworldGoddessoftheClosedWorld-LOSP-JP-PScR.png",
        25592142: "https://ms.yugipedia.com//5/56/AstellaroftheWhiteForest-CF02-JP-OP.png",
        61980241: "https://ms.yugipedia.com//8/81/ElzetteoftheWhiteForest-CF02-JP-OP.png",
        24203749: "https://ms.yugipedia.com//a/ac/TheGreatGallantBandit-BETB-JP-PScR.png",
        50208444: "https://ms.yugipedia.com//8/80/ElementalSagaDoriado-BETB-JP-PScR.png",
        17242022: "https://ms.yugipedia.com//8/82/RedEyesBlackDragonExceed-BETB-EN-UR-1E-EA.png",
        79791695: "https://ms.yugipedia.com//b/b7/CXyzHopeChaosBarianDragon-BETB-EN-UR-1E-EA.png",
        90960358: "https://ms.yugipedia.com//e/e9/ToonDarkMagicianGirl-RV01-JP-ScR.png",
        // Yugipedia 에 워터마크 판뿐인 카드는 일본 카드숍(카드러시·블루래빗) 상품 스캔
        82344137: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_1.jpg",
        44001993: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_2.jpg",
        70405001: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_3.jpg",
        7894706: "https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_4.jpg",
        40366667: "https://www.cardrush.jp/data/cardrush/product/LOSP2_10.jpg",
        70781052: "https://www.cardrush.jp/data/cardrush/product/S__10100739.jpg",
        53183600: "https://www.rabbit-blue.com/data/nereid/product/RV01/008s.jpg",
        29479265: "https://www.rabbit-blue.com/data/nereid/product/RV01/063s.jpg",
        24269961: "https://www.rabbit-blue.com/data/nereid/product/RV01/064s.jpg",
    ]
}
