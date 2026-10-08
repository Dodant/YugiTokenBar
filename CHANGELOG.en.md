# Patch notes

## 0.5.3 — 2026-10-08
**✨ New features**
- You can now swipe left or right on the trackpad over the popover's quick-buy row to move to the previous or next pack in release order. The incoming pack shrinks slightly before settling into place, with a light trackpad tap for each pack.
- Added "Recently obtained" to the collection sidebar. It shows the 50 cards you got most recently (Fusions included) in the order you got them.
- Added 8 materials (Elemental HERO Bubbleman, Black Luster Soldier, Blue-Eyes Ultimate Dragon, and more) for 9 Fusion Monsters that couldn't be made because their materials weren't in any booster (Elemental HERO Tempest, Elemental HERO Mariner, Dragon Master Knight, and more). They're in the same pack as their Fusion Monster.
- Added 25 Fusion Monsters that weren't in any booster but have booster cards among their materials (Gate Guardians Combined, Elemental HERO Neos Kluger, Meteor Black Dragon, and more) to the pack where their latest material was released, along with their remaining materials that weren't in any booster (7 cards, including Meteor Dragon and Fighting Flame Dragon).
- Added "Mask Change" and 10 Masked HEROes to the packs from when they were first released in Korea (EXTREME VICTORY and more). With "Mask Change", you can make a Masked HERO from [Fusion] in the collection, using 1 "HERO" monster of the same Attribute that you have the most copies of. The collection now has 8,223 cards.
- Fusion Monsters whose materials have conditions like Type, Attribute, Level, ATK, monster card type, or an archetype (157 cards, including Fighting Flame Dragon, Elder Entity Norden, Ultimate Ancient Gear Golem, and El Shaddoll Construct) can now be made from [Fusion] in the collection. For each condition, the matching card you have the most copies of is used, and the card details show which cards were picked. 285 cards can now be made by Fusion.

**🎨 Improvements**
- Patch notes now appear in the app language (Korean, English, or Japanese).

## 0.5.2 — 2026-10-08
**🎨 Improvements**
- After opening a free pack, if you have more free packs you can keep going with [Open next free pack]. Before, only [One more pack] (buying the same pack with coins) was available.
- Split the shop pack stamps. Packs you've completed get a green COMPLETE; packs with nothing left to pull but cards still to fill by Fusion get a purple FUSION ONLY.
- On the opening screen, hovering over a card whose name is cut off with … now scrolls the full name sideways, like in the collection.

## 0.5.1 — 2026-10-08
**🎨 Improvements**
- Replaced "(Beta)" on the Partner title in Settings with a small β mark.
- When an update check finds you're up to date, "(latest)" now appears next to the current version.
- Card name tooltips for recently obtained cards in the popover now appear only after a short hover.

**⚡ Performance**
- Card tilt on hover is smoother.

## 0.5.0 — 2026-10-07

Now available in Korean, English, and Japanese.

**✨ New features**
- Added a Language menu (Follow System, 한국어, English, 日本語) in Settings › General. It takes effect after a restart, and unsupported system languages fall back to English. Changing the language keeps your collection and save.
- Card names, effects, attributes, types, and pack names are shown in the chosen language. Pack names switch to the original Japanese or TCG pack names.
- Collection search and name sorting use card names in the chosen language.

**🎨 Improvements**
- Numbers and dates follow the chosen language. Coin and token K/M abbreviations stay the same.
- In the collection, hovering over a card whose name is cut off with … now scrolls the full name sideways.
- Packs in the shop where you've collected every card you can pull now get a slanted CLEAR stamp. Pressing their buy button once changes it to "Buy anyway", and you press again to buy.
- With [Fusion Monsters by Fusion Summon only] on, shop pack progress shows how many cards are left that can only be filled by Fusion ("N left to fuse").
- The Fusion Summonable list on the right of the collection can now be collapsed and expanded by clicking its title. The collapsed state is remembered.
- Clicking during the Fusion animation now skips to the scene where the Fusion card has appeared instead of closing right away. Click again to close.
- The large image in the collection's card info panel is now shown without tilt or reflection, and cards you don't own yet appear in color.

**⚖️ Balance**
- Every pack now contains at least one card you don't have from that pack yet. Once you've completed the pack, there's no guarantee. Free cards are unchanged.

**🐛 Bug fixes**
- Fixed the app crashing when dragging the divider between the card grid and the card info panel in the collection. The card info panel now has a fixed width.

## 0.4.4 — 2026-10-07
**🎨 Improvements**
- Fixed Settings boxes looking pitch black and descriptions being hard to read in dark mode.
- Added a thin light border around cards and packs in dark mode so their outlines show on dark backgrounds.
- Fixed the collection's per-rarity progress bars all turning blue when switching between light and dark; they now keep their rarity colors.
- Brightened the N rarity bar in dark mode so it's easy to see on dark backgrounds.
- Changed the R, UR, and SE rarity labels to white text on a dark background for clearer reading.
- Increased the contrast of the NEW, coin, and count badges, the new version notice, limit warnings, and the "Fusion Summonable" label so they read well in both light and dark.
- Made faint text, such as limit notices and Settings descriptions, slightly darker.

## 0.4.3 — 2026-10-07
**🐛 Bug fixes**
- Fixed the popover's "last bought pack" switching to a pack opened as a free pack, or reverting to the first pack after opening many free cards.
- Fixed two decks with the same name being created when making a new deck after deleting one.
- Fixed the "Couldn't save progress" warning remaining after a successful save import.
- Fixed card details not opening when selecting a range with ⇧ held in the collection.
- Fixed Launch at login not turning off when switched off while waiting for system approval, which made the app launch at login after a later approval even though you'd never turned it on.

## 0.4.2 — 2026-10-07
**🐛 Bug fixes**
- Fixed drag selection going wrong, or hover and image states jumping to other cards, when removing deck or favorite cards or when the list changed in the collection.
- Fixed a new card's image not loading and staying on the card back when clicking different cards in a row in card details.
- Fixed a colored background briefly showing through when a previously seen pack image reappeared.
- Fixed the bars disappearing or being shown twice as "Model", and the 5-hour window reset time being blank, when Claude limits came only in the new format.

## 0.4.1 — 2026-10-07
**🐛 Bug fixes**
- Token usage from periods when the app wasn't running is now credited on the next launch, up to 30 days back.
- Fixed tokens used just before midnight being left out of credit.
- Fixed the card back briefly showing through when a previously seen card image reappeared (scrolling, getting a new card).
- Fixed the next free card countdown showing "0K" when fewer than 1,000 tokens remained; it now shows the actual number of tokens left.

**🎨 Improvements**
- Replaced the card back with a high-resolution image without a logo. It's bundled with the app, so it shows from the start without downloading.
- Coin amounts now roll when they change.
- If saving fails, the menu bar icon changes to a warning, and a notice with [Open folder] appears at the top of the popover.
- Switching to the shop, Settings, or opening screen inside the popover now transitions smoothly.
- Hovering over the usage section now shows that it's clickable, and a progress indicator appears while limits load.
- Polished wording: limits "5h"/"wk" → "5h"/"Weekly", update [OK] → [Check for updates], the sell icon is now a coin (ⓒ), and fixed spacing in the menu bar free card badge.
- In the collection's deck view, selected cards can be removed one copy at a time with the Delete key (toolbar [Remove from Deck]). While typing in the search field, ⌘A and Delete apply to the search text.
- Changed the rarity pill (R, UR, SE) text to black so small text reads well.
- VoiceOver can now read and operate collection cards (name, rarity, copies owned, favorite, remove from deck), opened cards (flip, undo sale), and the Back and New Deck buttons.

**⚡ Performance**
- Reduced unnecessary work in the collection window when usage limits refresh or when switching to the shop or Settings.
- Clicking a card in the collection no longer recalculates the card list and sidebar stats, so it responds faster. Sorting and searching only rerun when their criteria change, and the "Fusion Summonable" list is no longer rebuilt on each card click.

## 0.4.0 — 2026-10-06
Expanded to 100 packs through the Modern era, and added SE rarity, card holograms, and a Fusion animation.

**✨ New features**
- Expanded the card pool through the Modern era (25 packs from RISE OF THE DUELIST to CHAOS ORIGINS), for 100 packs and 8,172 cards. The shop and collection gained a Modern section, and the Settings era range gained "Up to Modern (Support)".
- Added SE (Secret) rarity above UR. Secret, Ultimate, and Holographic Rares appear as SE.
- The 21 cards with official overframe versions are shown with artwork extending past the card frame (Shooting Quasar Dragon, Supreme King Z-ARC, Summoned Skull, and more).
- Added a Fusion animation: material cards are drawn into a galactic whirlpool in space, then burst like a supernova to reveal the Fusion card (click to close).
- If any Fusion Monster you don't own yet can be Fusion Summoned right now, a "Fusion Summonable" list appears at the top of the right panel in the collection.
- Hover over the +ⓒ mark on an auto-sold card and click ✕ to undo the sale.
- Added [Turn off animations] to Settings. Cards are shown right away without tilt, flip, rare, or Fusion effects.

**🎨 Improvements**
- Hovering over a card tilts it toward the cursor like a real card, with a moving light reflection. UR and SE cards get a rainbow hologram (collection details, pack opening, recently obtained).
- SE cards open with two golden light beams and a golden halo for extra flair.
- Rearranged the pack opening screen into 4 cards on top and a large rare slot at the bottom center. [Flip all] flips the rare 0.6 seconds later.
- Getting a free pack or free card while opening no longer makes the panel taller, and it returns to its original height after you open the last free pack.
- Collection: moved the rarity label to the bottom left of the card image and removed the number.
- Collection: the bottom left now shows owned/total cards per rarity and the completion rate.
- Collection: moved the Fusion button to the right, and moved the "Polymerization" card hint into a ? tooltip to the left of the button (click it to jump to "Polymerization").
- Fusion materials with "A" or "B" conditions are now shown as such.
- Coins of 10,000 or more are abbreviated with K/M (including in the menu bar).

**⚖️ Balance**
- 5th card in a pack: SE 2%, UR 10% (was 12%).
- The 4th card in a pack has a 30% chance to be R. The guarantee of monsters in the first 2 cards is unchanged.
- Free card odds: N 70% / R 23% / SR 5% / UR 1.5% / SE 0.5%.
- Sell prices: N ⓒ 20 (was 30), R ⓒ 50 (was 60), SR ⓒ 150, UR ⓒ 400 (was 300), SE ⓒ 1,200. The expected sell value of one pack is about ⓒ 206.
- 98 pack cover monsters now appear as SE (excluding LABYRINTH OF NIGHTMARE and LEGACY OF DARKNESS, whose covers are Spells/Traps). Every pack now has an SE, and in GLADIATOR'S ASSAULT and STARDUST OVERDRIVE, whose only UR was the cover card, the UR slot became SR.
- Reprinted cards with different rarities across packs (such as Yubel) appear at their highest rarity from any pack.
- Fusion consumes materials but leaves your last copy, so they don't disappear from the collection.

**⚡ Performance**
- Card rarities are no longer recalculated at launch.

## 0.3.1 — 2026-10-06
**🎨 Improvements**
- The collection reopens to the last item you chose (All, Favorites, a pack, or a deck). The first open of the day starts at "All".

**⚡ Performance**
- Reduced stutter when clicking, favoriting, or selling cards in the collection (with many cards owned and sorted by name, about 1 s → 0.06 s). The first display is faster too.
- Reduced stutter when scrolling the collection.
- Unchanged Claude logs are no longer reread, greatly cutting the CPU and memory used to tally usage.
- Capped the memory used by card images.

## 0.3.0 — 2026-10-06
**✨ New features**
- Added the partner "Winged Kuriboh" (Beta). It unlocks when you get the card and moves on the menu bar icon and desktop according to your token usage (idle, flapping, flying, and sulking at 80% of a limit). It gets excited when you pull an SR/UR or get a free card, and waves when you have enough coins for a pack.
- Drag the desktop partner to move it, click it to make it tilt its head, and right-click [Hide] to hide it. Turn it on or off and change its size in Settings under "Partner (Beta)".

## 0.2.1 — 2026-10-06
**✨ New features**
- Added Gemini, Grok, Pi, oh-my-pi, and Cursor to token tallying. The usage section shows only today's usage.

## 0.2.0 — 2026-10-02
Expanded to 75 packs through VRAINS, and added card selling, Fusion, deck building, and favorites.

**✨ New features**
- Expanded the card pool through 5D's, ZEXAL, ARC-V, and VRAINS, for 75 packs and 6,160 cards. The shop and collection gained era sections, and Rank, Link, and Pendulum info is shown.
- Added an era range to Settings (from "Up to DM (Ritual)" to "Up to VRAINS (Link)", default "Up to GX (Fusion)"). Shop packs, the total card count, and the free card pool shrink to match the range.
- Added 4 rarities (N/R/SR/UR) with rarity colors.
- Cards can be sold for coins based on rarity. You can turn on auto-selling duplicates in Settings.
- Fusion: with [Fusion Monsters by Fusion Summon only] on in Settings, the 81 Fusion Monsters with known materials no longer appear in packs or free cards. Once you own the "Polymerization" Spell Card, use [Fusion] in the collection to consume material cards ("Polymerization" isn't consumed).
- Collection deck building: add cards to decks in the sidebar's Decks section by drag and drop or right-click. Unowned cards can be added too, up to 3 copies per card. Like packs, decks show owned/deck counts and a progress bar.
- Collection multi-select (⌘/⇧ click, rubber-band from empty space, [Select all] ⌘A) and adding all selected cards to a deck at once.
- Collection favorites (☆ on cards, Favorites in the sidebar), card name search, type (Monster, Spell, Trap, Summon method) and rarity filters, sorting (rarity, name, most owned), and a "Show unowned" checkbox.
- Collection details now show "Fusion Materials". Click a material's name to jump to that card.
- You can rename your collection.
- Added update checking, save export/import (with an automatic backup before importing), version, patch notes, and license info, and Launch at login to Settings.

**🎨 Improvements**
- Packs and free cards are now opened inside the menu bar panel instead of a separate window. You can press [One more pack] or [Open next N] right on the opening screen, and card names appear below the cards.
- SR and UR cards show a special effect when flipped.
- The shop and collection sidebar can be collapsed and expanded by era. The shop remembers its scroll position, and pack tiles show names and a scroll indicator.
- The collection grid shows card names, and owned counts are shown from ×2. Softened the silhouettes of unowned cards.
- The collection always opens with unowned cards shown. If a search finds nothing, [Search all] appears.
- Tidied up collection details into a compact layout: attribute/level/type, ATK/DEF, and owned/sell each on one line, with Fusion material lines separated from the effect text.
- Changed buttons to the Liquid Glass style.
- Esc goes back from the shop, Settings, and opening screens. Added a tooltip to the coin count (10,000 tokens = ⓒ 1) and a new-window icon on the popover's collection row. Increased text contrast on rarity pills you haven't obtained.

**⚖️ Balance**
- Each pack guarantees at least 2 monsters (the first 2 normal slots).
- Buying 10 packs with coins gives 1 free random booster pack (shown like 3/10 in the popover).
- Free cards accumulate and are opened 5 at a time.
- Removed the cap on copies owned.
- When Fusion Monsters can only be obtained by Fusion, selling duplicates and auto-selling keep as many materials as needed.

**🐛 Bug fixes**
- Fixed the collection window closing when narrowing the era range.

## 0.1.0 — 2026-10-01
- First release: earn coins and free cards from token usage, and buy and open 27 booster packs (2,270 cards). Shows today's usage and official limits.
