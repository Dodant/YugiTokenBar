# YugiTokenBar

A macOS menu bar app that fills a **Korean-release Yu-Gi-Oh! card collection** (100 regular booster packs, 8,226 cards) with the tokens your coding agents (Claude Code, Codex, etc.) use.
Available in Korean, English, and Japanese.

## How it works

- It reads today's tokens from your local Claude Code and Codex session logs. Usage from before installation is not counted.
- 10,000 tokens = 1 coin. 1,000 coins (= 10M tokens) buy one booster pack (4 Normal + 1 Rare or higher). Buy 10 packs and you get a random pack for free.
- Every 10M tokens you earn a free card, drawn from the whole pool by rarity odds.
- Rarities are N / R / SR / UR / SE. A reprinted card takes its highest rarity.
- In Settings, pick how far the pools reach (DM … Modern, default GX).
- You can collect any number of copies. Extra cards sell for coins.
- Using 50M tokens a day earns 5 free cards + 5 packs. Completing the collection takes about 100B tokens.

## Screens

- **Menu bar**: coins and a badge for unopened free cards
- **Popover**: coins, progress to the next free card, recent cards, quick buy, today's usage and cost, and Claude/Codex limits
- **Shop**: packs grouped by era; hover to buy
- **Pack opening**: flip cards one by one
- **Collection**: per-pack progress, view by rarity, card info, selling

| | Work mode off | Work mode on |
|---|---|---|
| Popover | <img src="docs/image/mainpage.png" width="280"> | <img src="docs/image/mainpage_workmode.png" width="280"> |
| Shop | <img src="docs/image/shop.png" width="280"> | <img src="docs/image/shop_workmode.png" width="280"> |
| Pack opening | <img src="docs/image/packopen.png" width="280"> | <img src="docs/image/packopen_workmode.png" width="280"> |
| Collection | <img src="docs/image/dex.png" width="280"> | <img src="docs/image/dex_workmode.png" width="280"> |

| Usage | Before fusion | After fusion |
|---|---|---|
| <img src="docs/image/usage.png" width="200"> | <img src="docs/image/yugo_pre.png" width="280"> | <img src="docs/image/yugo_post.png" width="280"> |

## Install

Requires macOS 26 or later.
There is no public release yet; once one is published, download `YugiTokenBar-x.y.z.zip` from [Releases](https://github.com/Dodant/YugiTokenBar/releases), unzip it, and move the app to `/Applications`.
To update, quit the app and replace it. Your collection is kept.

## Credits

- Card data: [Konami official card database](https://www.db.yugioh-card.com/yugiohdb/?request_locale=ko)
- Card images: [YGOPRODeck](https://ygoprodeck.com/)
- Pack images: [Yugipedia](https://yugipedia.com/)
- Usage-reading code: [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT, © 2026 chattymin)

> YugiTokenBar is an unofficial, non-commercial fan project.
> It is not affiliated with, endorsed, sponsored, or approved by Konami.
> Yu-Gi-Oh! card names, text, and images are © Konami.
