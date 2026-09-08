--[[
    kn_mantle - mid-air ledge grab (mantle) for FiveM
    Copyright (C) 2026 Kanayu_u

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

--[[
===============================================================================
 kn_mantle / Config
-----------------------------------------------------------------------------
 空中での縁掴み (mantle)。

 バニラ GTA V は登攀アニメーションもリーチも持っているが、「空中では登攀を
 開始できない」という制限がある。本リソースはその制限だけを外す。
 掴める高さ・距離を拡張しているわけではない。

 上の「運用者が触る値」だけ見れば足りる。下の「内部値」は実機計測で決めた
 もので、変更すると掴みの成立率が落ちる。
===============================================================================
]]

KnMantleConfig = {

    -- =======================================================================
    -- 運用者が触る値
    -- =======================================================================

    -- ロケール ('ja' / 'en')
    locale = 'ja',

    -- 機能そのものの有効/無効
    enabled = true,

    -- 掴みを発火させる control。22 = ジャンプ (INPUT_JUMP)。
    -- RegisterKeyMapping ではなく control を見るのは、チャット入力中の誤爆を
    -- 避けるため。変更する場合は control ID 一覧を参照すること。
    control = 22,

    -- 掴める縁の高さの上限 (ペドのその瞬間の足元基準 m)。
    --
    -- 実機計測 (v0.4.0): 上限 3.00 で issued:14 climb:14 none:0。
    -- TaskClimb のリーチ側には天井が見つからなかった。判定はペドの現在位置
    -- からの相対なので、実際の上限を決めているのはジャンプの高さである。
    -- 3.00 は「跳んでも届かない壁を撃たない」ための現実的な足切り。
    --
    -- 下げると掴める壁が減る。上げても掴める壁は増えず、届かない壁に対して
    -- TaskClimb を空撃ちする回数が増えるだけ。
    grabMaxHeight = 3.00,

    -- 縁までの水平距離の上限 (m)。
    -- 大きくすると、離れた壁に対しても発行してしまい空振りが増える。
    grabMaxDistance = 1.00,

    -- この速度 (m/s) を超える落下中は掴みを試みない。
    -- 高所から落ちて縁を掴んで無傷、という転用を防ぐための上限。
    -- 通常のジャンプの下降速度は 5〜8 m/s 程度なので、通常のジャンプは妨げない。
    -- 0 に近づけるほど厳しくなる。
    maxFallSpeed = 12.0,

    -- 空中でジャンプキーを押してから、自動で掴みを試み続ける時間 (ms)。
    -- 掴みが成立するフレームは狭く、押した瞬間はまだ壁に届いていないことが多い。
    -- この窓の間はリソース側が機会を探すので、押すタイミングの精度を
    -- プレイヤーに要求しない。短くすると「押したのに掴めない」が増える。
    assistWindowMs = 600,

    -- デバッグ HUD と計測用コマンド。
    -- true にすると HUD が出て、/mantlemax などの調整コマンドが有効になる。
    -- 本番サーバーでは必ず false のままにすること
    -- (プレイヤーが判定の帯を自由に変更できてしまうため)。
    debug = false,

    -- =======================================================================
    -- 内部値 (実機計測で決定。通常は変更しない)
    -- =======================================================================

    -- 上昇中 (IsPedJumping) だけでなく、頂点通過後の落下中も掴みの対象にするか。
    -- 掴みは「跳んで縁に触れる瞬間」= ほぼ頂点〜下降中に起きるため、
    -- false にすると肝心の窓を塞いでしまい、ほぼ掴めなくなる。
    -- 落下ダメージ回避への転用は maxFallSpeed 側で防いでいる。
    allowDuringFall = true,

    -- 空中に出てから掴みを受け付けるまでの最短時間 (ms)。
    -- ジャンプを開始したそのフレームの入力を「空中での再押下」と誤認しない下限。
    minAirborneMs = 120,

    -- ジャンプキーを押しっぱなしにしている間、アシスト窓を延長するか。
    holdRetry = true,

    -- 再試行の最小間隔 (ms)
    retryMs = 50,

    -- 1 回の滞空あたりの最大試行回数。着地するとリセットされる。
    maxAttemptsPerAir = 20,

    -- --- レイキャストによる発行の門番 ------------------------------------
    -- 掴む対象が無いのに TaskClimb を撃つと、空中で登攀動作だけが再生されて
    -- 「二段ジャンプ」に見える。前方に登れる縁が見えているときだけ発行する。
    -- false にするとその挙動に戻る (比較検証用)。
    gateByProbe = true,

    -- 掴める縁の高さの下限 (m)。これ未満はバニラの乗り越えで足りる。
    grabMinHeight = 0.30,

    -- TaskClimb 発行後、実際に登攀状態へ入ったかを監視する時間 (ms)。
    -- 「呼べた」ではなく「効いた」を数えるための計測窓。
    resultWindowMs = 700,

    -- 非空中時のポーリング間隔 (ms)。idle 負荷はこの値で決まる。
    idleWaitMs = 250,

    -- --- レイキャストの形状 ----------------------------------------------
    -- 足元からの高さ (m)。この各高さで前方へ水平に撃ち、壁を探す。
    probeHeights = { 0.6, 1.0, 1.4, 1.8 },

    -- 前方へ撃つ距離 (m)
    probeDistance = 1.2,

    -- 壁の当たり点から更に奥へ進めて、天面を探す水平オフセット (m)
    probeTopForward = 0.35,

    -- 天面を探す上向きの探索範囲 (足元から m)
    probeTopMaxHeight = 3.5,

    -- shapetest のフラグ。1=ワールド 2=車両 16=オブジェクト
    probeFlags = 1 + 2 + 16,

    -- デバッグ HUD の描画位置 (画面比 0.0-1.0)
    hudX = 0.015,
    hudY = 0.42
}
