<p align="center"><img src="docs/image/appicon.png" width="128" alt="YugiTokenBar icon"></p>

<h1 align="center">YugiTokenBar</h1>

<p align="center">A macOS menu bar app that fills a <strong>Yu-Gi-Oh! card collection</strong> with the tokens your coding agents (Claude Code, Codex, etc.) use.<br>
Available in Korean, English, and Japanese.</p>

## How it works

- It reads today's tokens from your local Claude Code, Codex, Gemini, Grok, Pi, oh-my-pi, and Cursor logs.
  On first launch it also credits the last 14 days of usage; anything older is not counted.
- 10,000 tokens = 1 coin.
  1,000 coins (= 10M tokens) buy one booster pack with 5 cards.
  Buy 10 packs and you get a random pack for free.
- Every 10M tokens you earn a free card, drawn from the whole pool by rarity odds.
- Rarities are N / R / SR / UR / SE.
  A reprinted card takes its highest rarity.
- In Settings, pick how far the pools reach (DM … Modern, default GX).
- You can collect any number of copies.
  Extra cards sell for coins.
- 25 cards have official over-frame art, where the illustration breaks out of the card frame.
  Collect 3 copies of one to unlock its over-frame art; it stays unlocked even if you sell them.
  Until then, its copies are never sold as duplicates or used as Fusion Materials, and the Dex shows a ✦ badge with your progress.
- Once you own every card in a pack, cards you still need (locked over-frame cards, and Fusion Materials you are short on) come up 10 times as often as other cards of the same rarity.
  Cards from such a pack also sell for 3 times the price.
- Using 50M tokens a day earns 5 free cards + enough coins for 5 packs.

## Screens

- **Menu bar**: coins and a badge for unopened free cards, or pick in Settings to show today's usage, Claude/Codex limits, Dex progress, or nothing
- **Popover**: coins, progress to the next free card, recent cards, quick buy, today's usage and cost, and Claude/Codex limits
- **Shop**: packs grouped by era; hover to buy
- **Pack**: flip cards one by one
- **Dex**: per-pack progress, view by rarity, card info, selling

Work mode hides card images and the partner character; enable it in Settings.

<table align="center">
<thead><tr><th></th><th>Work mode off</th><th>Work mode on</th></tr></thead>
<tbody>
<tr><th>Menu bar</th><td valign="top" align="center"><img src="docs/image/menuicon.png" height="54"></td><td valign="top" align="center"><img src="docs/image/menuicon_workmode.png" height="54"></td></tr>
<tr><th>Popover</th><td valign="top" align="center"><img src="docs/image/mainpage.png" width="300"></td><td valign="top" align="center"><img src="docs/image/mainpage_workmode.png" width="300"></td></tr>
<tr><th>Shop</th><td valign="top" align="center"><img src="docs/image/shop.png" width="300"></td><td valign="top" align="center"><img src="docs/image/shop_workmode.png" width="300"></td></tr>
<tr><th>Pack</th><td valign="top" align="center"><img src="docs/image/packopen.png" width="300"></td><td valign="top" align="center"><img src="docs/image/packopen_workmode.png" width="300"></td></tr>
<tr><th>Usage</th><td valign="top" align="center"><img src="docs/image/usage.png" width="300"><br>Today's token usage</td><td valign="middle" align="center">Same</td></tr>
<tr><th>Field background</th><td valign="top" align="center"><img src="docs/image/field_background.png" width="300"></td><td valign="middle" align="center">None</td></tr>
</tbody>
</table>

<table align="center">
<tbody>
<tr><th>Dex · Work mode off</th></tr>
<tr><td align="center"><img src="docs/image/dex.png"></td></tr>
<tr><th>Dex · Work mode on</th></tr>
<tr><td align="center"><img src="docs/image/dex_workmode.png"></td></tr>
</tbody>
</table>

<table align="center">
<thead><tr><th>Over-frame locked (1/3)</th><th>Over-frame unlocked</th></tr></thead>
<tbody>
<tr><td align="center"><img src="docs/image/overframe_locked.png" width="216"></td><td align="center"><img src="docs/image/overframe_unlocked.png" width="216"></td></tr>
</tbody>
</table>

Enable fusion-only collection in Settings to obtain eligible Fusion Monsters by combining material cards instead of drawing them.

<p align="center"><a href="docs/video/fusion-demo.mp4"><img src="docs/video/fusion-demo.gif" width="720" alt="Fusion demo"></a></p>

## Remote machines

Usage on a remote machine (SSH, cloud sessions) is logged there, so the app cannot see it.
As a stopgap, copy the logs to this Mac and add the folder in Settings > Extra scan folders:

```bash
# every few minutes (cron/launchd); -a keeps file times
rsync -a gpu1:~/.claude/projects/ ~/remote-logs/gpu1/claude/projects/
rsync -a gpu1:~/.codex/sessions/  ~/remote-logs/gpu1/codex/sessions/
```

Then set Claude to `~/remote-logs/*/claude/projects` and Codex to `~/remote-logs/*/codex/sessions`.
Keep the folder outside Documents, Desktop, and Downloads so macOS does not ask for access.
The same request is counted once even if it shows up in several folders.
Usage synced after midnight is not credited to the previous day.

## Install

Requires macOS 26 or later.
There is no public release yet; once one is published, download `YugiTokenBar-x.y.z.zip` from [Releases](https://github.com/Dodant/YugiTokenBar/releases), unzip it, and move the app to `/Applications`.
The app is not notarized by Apple, so macOS blocks it the first time you open it.
Allow it once in either way:

- **System Settings:** open the app, then go to **Privacy & Security** and click **Open Anyway** next to YugiTokenBar.
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/YugiTokenBar.app`

After an update, macOS may ask again for Keychain access to read Claude limits.
To update, use [Check for updates] in Settings > About & support.
Your collection is kept.

## Credits

- Card data: [Konami official card database](https://www.db.yugioh-card.com/yugiohdb/?request_locale=ko)
- Most card images: [YGOPRODeck](https://ygoprodeck.com/)
- Some over-frame images: [Yugipedia](https://yugipedia.com/) and card shop scans from [CardRush](https://www.cardrush.jp/) and [Blue Rabbit](https://www.rabbit-blue.com/)
- Pack images: [Yugipedia](https://yugipedia.com/)
- Usage-reading code: [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT, © 2026 chattymin)

> YugiTokenBar is an unofficial, non-commercial fan project.
> It is not affiliated with, endorsed, sponsored, or approved by Konami.
> Yu-Gi-Oh! card names, text, and images are © Konami.

## License

The code is under the [MIT License](LICENSE).
Card data, card images, the card back, and the partner sprite are Konami's works or fan art of them, so the MIT License does not cover them.
