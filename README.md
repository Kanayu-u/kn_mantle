# kn_mantle

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
[![Framework](https://img.shields.io/badge/framework-Standalone-green.svg)](#要件)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey.svg)](LICENSE)

空中での縁掴み (mantle) を可能にする FiveM リソース。

ジャンプしながら壁に向かってジャンプキーを押すと、縁を掴んでよじ登る。
バニラでは掴めずに落ちる高さの壁に、そのまま登れるようになる。

## 由来

[NoPixel V の mantle](https://x.com/gta_np/status/2095907273118007544) を参考に、
同じ挙動を再現したもの。**着想元はそちらで、実装は全て自前**（第三者のコードは含まない）。

## 仕組み

バニラ GTA V は登攀アニメーションもリーチも既に持っている。持っていないのは
**空中から登攀を開始する**手段だけで、本リソースが外しているのはその制限のみ。

- 掴める高さ・水平距離を拡張してはいない（バニラのまま）
- 独自アニメーション・独自リーチ・独自の当たり判定は無い
- 他プレイヤーの画面にも通常の登攀動作として同期される（本番サーバーで確認済み）

## 要件

- クライアント専用・フレームワーク非依存（QBCore / ESX / スタンドアロンいずれでも動く）
- ストリーミング資産なし（バニラのアニメーションのみ）
- 依存なし。`ox_lib` があれば通知に使うが、無ければチャットへフォールバックする

## 導入

1. `kn_mantle` を `resources/` に配置する
2. `server.cfg` に追記する

```cfg
ensure kn_mantle
```

3. 設定を変えた場合は `refresh` → `ensure kn_mantle`
   （`restart` は fxmanifest とファイル一覧を読み直さない）

## 操作

**ジャンプ中に、壁の方を向いてジャンプキーを押す**（押しっぱなしでもよい）。

掴めるフレームは狭いため、押した瞬間に条件が揃っていなくても、
そこから 0.6 秒間はリソース側が機会を探し続ける。
タイミングを正確に合わせる必要はない。

| コマンド | 動作 |
|---|---|
| `/mantle` | 自分の掴みの ON/OFF |

## 設定

`config/config.lua` の上段だけ見れば足りる。

| キー | 既定 | 意味 |
|---|---|---|
| `locale` | `'ja'` | 通知の言語（`ja` / `en`） |
| `enabled` | `true` | 機能の有効/無効 |
| `control` | `22` | 発火させる control（22 = ジャンプ） |
| `grabMaxHeight` | `3.00` | 掴める縁の高さの上限（足元基準 m） |
| `grabMaxDistance` | `1.00` | 縁までの水平距離の上限（m） |
| `maxFallSpeed` | `12.0` | この落下速度（m/s）を超えると掴まない |
| `assistWindowMs` | `600` | 押下後にリソース側が機会を探し続ける時間（ms） |
| `debug` | `false` | デバッグ HUD と調整コマンド。**本番では false のまま** |

下段の「内部値」は実機計測で決めた値で、変更すると掴みの成立率が落ちる。

### `grabMaxHeight` について

**上げても掴める壁は増えない。**
判定はペドのその瞬間の位置からの相対で行われるため、到達高度を決めているのは
TaskClimb のリーチではなく**ジャンプの高さ**である。実機計測では上限 3.00 で
14 回中 14 回成立し、リーチ側に天井は見つからなかった。

3.00 は「跳んでも届かない壁に対して無駄撃ちしない」ための足切りとして置いている。
上げると、届かない壁に対して空撃ちする回数が増えるだけになる。

### `maxFallSpeed` について

高所から落下して縁を掴み、落下ダメージを消す、という転用を防ぐための上限。
通常のジャンプの下降速度は 5〜8 m/s 程度なので、通常のジャンプは妨げない。
厳しくしたい場合は値を下げる。

## 掴めない条件

以下では発火しない。

- 死亡 / 瀕死・車内・ラグドール・水泳・拘束中
- 既に登攀・乗り越え中・はしご使用中・パラシュート展開中
- `maxFallSpeed` を超える落下中
- チャット / NUI にフォーカスがある、ポーズメニュー中
- 前方に「登れる縁」が見えていないとき

最後の 1 つが重要で、**掴む対象が無いときは TaskClimb を発行しない**。
発行してしまうと空中で登攀動作だけが再生され、二段ジャンプのように見える。
そのため事前にレイキャストで前方の壁と天面を探し、
`grabMinHeight` 〜 `grabMaxHeight` の帯に収まる天面がある場合のみ発行する。

## 負荷

- 地上 / 通常の滞空中: 250ms 間隔のポーリングのみ
- レイキャスト（5 本 / フレーム）は**ジャンプキーを押した後のアシスト窓の間だけ**実行する
- `debug = true` のときは常時レイキャストと HUD 描画を行うため、本番では false にすること

## 既知の制限

- 到達できる高さはキャラクターのジャンプ性能で決まる。リソース側では上げられない
- 掴む対象の判定は前方への直線レイキャストなので、
  細い柵や複雑な形状の縁では検出できないことがある
- 純粋な落下中（ジャンプを伴わない落下）の掴みは動作するが、単独では検証していない

## ライセンス (License)

**GNU General Public License v3.0 (GPL-3.0)**

Copyright (C) 2026 Kanayu_u

無償で公開しています。商用・非商用を問わず、サーバーでの利用・改変が可能です。
Free and open source. You may use and modify it on your server, commercially or not.

再配布・改変版の配布を行う場合は、GPL-3.0 の条件に従ってください。
If you redistribute it, or distribute a modified version, you must comply with GPL-3.0:

- **ソースコードを公開すること** / Disclose the source code
- **同じ GPL-3.0 で配布すること** / License the derivative work under GPL-3.0 as well
- **著作権表示とライセンス文を残すこと** / Retain the copyright notice and license text
- **変更点を明示すること** / State the changes you made

つまり、**このコードを暗号化して有料アセットとして再販することはできません。**
In other words, you may not repackage this as an encrypted paid asset.

全文は同梱の `LICENSE` ファイルを参照してください。
See the bundled `LICENSE` file for the full text.

本ソフトウェアは無保証で提供されます。
This program is distributed WITHOUT ANY WARRANTY; see the license for details.
