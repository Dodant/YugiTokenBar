<p align="center"><img src="docs/image/appicon.png" width="128" alt="YugiTokenBar アイコン"></p>

<h1 align="center">YugiTokenBar</h1>

<p align="center">コーディングエージェント（Claude Code、Codex など）が使ったトークンで<strong>遊戯王カードのコレクション</strong>を集める macOS メニューバーアプリです。<br>
韓国語・英語・日本語に対応しています。</p>

<p align="center"><a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <strong>日本語</strong></p>

## しくみ

- この Mac にある Claude Code、Codex、Gemini、Grok、Pi、oh-my-pi、Cursor のログから、今日使ったトークンを読み取ります。\
  初回起動時は過去14日分の使用量もまとめて加算し、それより前の分は数えません。
- 10,000トークンで1コインです。\
  1,000コイン（= 1,000万トークン）で、カード5枚入りのブースターパックを1つ買えます。\
  パックを10個買うと、ランダムなパックが1つおまけで付きます。
- コレクションはレギュラーブースター101パックとデュエリストパック30パック（DP表示）で、時代ごとにまとまっています。
- 1,000万トークンごとに無料カードを1枚もらえます。\
  全カードの中からレアリティの確率に応じて選ばれます。
- レアリティは N / R / SR / UR / SE です。\
  再録されたカードは、いちばん高いレアリティになります。
- 設定で、カードが出る時代の範囲を選べます（DM … Modern、初期値は GX）。
- 同じカードを何枚でも集められます。\
  余ったカードはコインに換えて売れます。
- 26枚には、イラストがカードの枠からはみ出す公式のオーバーフレームの絵があります。\
  同じカードを3枚集めるとオーバーフレームの絵が解放され、あとで売っても解放されたままです。\
  解放前はそのカードを重複カードとして売ったり融合素材に使ったりせず、図鑑には ✦ バッジと進み具合が表示されます。
- パックのカードをすべて集めると、まだ必要なカード（未解放のオーバーフレームカード、足りない融合素材）が同じレアリティのほかのカードより10倍出やすくなります。\
  そのパックから出たカードは3倍の値段で売れます。
- 1日に5,000万トークンを使うと、無料カード5枚とパック5つ分のコインがもらえます。

## 画面

- **メニューバー**: コインと、まだ開けていない無料カードのバッジを表示します。\
  設定で、今日の使用量、Claude/Codex の上限、図鑑の進み具合、または何も表示しないように変えられます。
- **ポップオーバー**: コイン、次の無料カードまでの進み具合、最近のカード、クイック購入、今日の使用量とコスト、Claude/Codex の上限
- **Shop**: 時代ごとにまとめたパック、カーソルを合わせて購入
- **パック開封**: カードを1枚ずつめくる
- **Dex**: パックごとの進み具合、レアリティ別の表示、カード情報、売却

仕事モードではカード画像とパートナーキャラクターを隠します。
設定でオンにできます。

<table align="center">
<thead><tr><th></th><th>仕事モード オフ</th><th>仕事モード オン</th></tr></thead>
<tbody>
<tr><th>メニューバー</th><td valign="top" align="center"><img src="docs/image/menuicon.png" height="54"></td><td valign="top" align="center"><img src="docs/image/menuicon_workmode.png" height="54"></td></tr>
<tr><th>ポップオーバー</th><td valign="top" align="center"><img src="docs/image/mainpage.png" width="300"></td><td valign="top" align="center"><img src="docs/image/mainpage_workmode.png" width="300"></td></tr>
<tr><th>Shop</th><td valign="top" align="center"><img src="docs/image/shop.png" width="300"></td><td valign="top" align="center"><img src="docs/image/shop_workmode.png" width="300"></td></tr>
<tr><th>パック開封</th><td valign="top" align="center"><img src="docs/image/packopen.png" width="300"></td><td valign="top" align="center"><img src="docs/image/packopen_workmode.png" width="300"></td></tr>
<tr><th>使用量</th><td valign="top" align="center"><img src="docs/image/usage.png" width="300"><br>今日のトークン使用量</td><td valign="middle" align="center">同じ</td></tr>
<tr><th>フィールド背景</th><td valign="top" align="center"><img src="docs/image/field_background.png" width="300"></td><td valign="middle" align="center">なし</td></tr>
</tbody>
</table>

<table align="center">
<tbody>
<tr><th>Dex · 仕事モード オフ</th></tr>
<tr><td align="center"><img src="docs/image/dex.png"></td></tr>
<tr><th>Dex · 仕事モード オン</th></tr>
<tr><td align="center"><img src="docs/image/dex_workmode.png"></td></tr>
</tbody>
</table>

<table align="center">
<thead><tr><th>オーバーフレーム未解放 (1/3)</th><th>オーバーフレーム解放済み</th></tr></thead>
<tbody>
<tr><td align="center"><img src="docs/image/overframe_locked.png" width="216"></td><td align="center"><img src="docs/image/overframe_unlocked.png" width="216"></td></tr>
</tbody>
</table>

素材カードから作れる融合モンスターは、パックから引くかわりに素材を融合して手に入れます。

<p align="center"><a href="docs/video/fusion-demo.mp4"><img src="docs/video/fusion-demo.gif" width="720" alt="融合のデモ"></a></p>

## リモートマシン

リモートマシン（SSH、クラウドセッション）での使用量はそのマシンにログが残るため、アプリからは見えません。
当面の回避策として、ログをこの Mac にコピーし、そのフォルダを 設定 > 追加スキャンフォルダ に追加してください:

```bash
# 数分ごとに (cron/launchd)。-a でファイルの日時を保つ
rsync -a gpu1:~/.claude/projects/ ~/remote-logs/gpu1/claude/projects/
rsync -a gpu1:~/.codex/sessions/  ~/remote-logs/gpu1/codex/sessions/
```

続けて、Claude には `~/remote-logs/*/claude/projects`、Codex には `~/remote-logs/*/codex/sessions` を指定します。
macOS がアクセス許可を求めないよう、フォルダは書類・デスクトップ・ダウンロードの外に置いてください。
同じリクエストが複数のフォルダにあっても1回だけ数えます。
午前0時を過ぎてから同期された使用量は、前日分には加算されません。

## インストール

macOS 26 以降が必要です。
[最新リリース](https://github.com/Dodant/YugiTokenBar/releases/latest)の **Assets** から `YugiTokenBar-x.y.z-macOS.zip` をダウンロードして展開し、アプリを `/Applications` に移動してください。
GitHub がリリースごとに付ける **Source code** のアーカイブはアプリではなくソースコードです。
0.6.3 のアプリの ZIP は `YugiTokenBar-0.6.3.zip`（約 11 MB）です。
アプリは Apple の公証を受けていないため、初めて開くときに macOS がブロックします。
次のどちらかの方法で一度だけ許可してください:

- **システム設定:** アプリを開いてから **プライバシーとセキュリティ** で YugiTokenBar の横の **このまま開く** をクリックします。
- **ターミナル:** `xattr -dr com.apple.quarantine /Applications/YugiTokenBar.app`

アップデート後、Claude の上限を読むために macOS がキーチェーンへのアクセスをもう一度求めることがあります。
アップデートは 設定 > 情報とサポート の [アップデートを確認] から行います。
集めたコレクションはそのまま残ります。

## クレジット

- カードデータ: [コナミ公式カードデータベース](https://www.db.yugioh-card.com/yugiohdb/?request_locale=ja)
- ほとんどのカード画像: [YGOPRODeck](https://ygoprodeck.com/)
- 一部のオーバーフレーム画像: [Yugipedia](https://yugipedia.com/)、および [カードラッシュ](https://www.cardrush.jp/)・[ブルーラビット](https://www.rabbit-blue.com/) のカードショップのスキャン
- パック画像: [Yugipedia](https://yugipedia.com/)
- 使用量を読むコード: [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)（MIT、© 2026 chattymin）

> YugiTokenBar は非公式・非営利のファンプロジェクトです。
> コナミとは関係がなく、コナミの承認・支援・後援を受けたものではありません。
> 遊戯王のカード名・テキスト・画像の著作権はコナミに帰属します。

## ライセンス

コードは [MIT ライセンス](LICENSE)で公開しています。
カードデータ、カード画像、カードの裏面、パートナーのスプライトはコナミの著作物またはそのファンアートのため、MIT ライセンスの対象外です。
