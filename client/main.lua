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
 kn_mantle / client
-----------------------------------------------------------------------------
 空中で登攀 (mantle) を開始できるようにする。

 バニラ GTA V は登攀アニメーションもリーチも持っているが、空中では登攀を
 「開始」できない。ここで外しているのはその制限だけで、掴める高さや距離を
 拡張しているわけではない (SET_PED_CONFIG_FLAG を含め、リーチを変える手段は
 存在しないことを確認済み)。

 実機検証で分かっていること:
   1. 空中の TaskClimb は機能する (18/18 成立)。
   2. リーチ側に天井は無い。判定はペドのその瞬間の位置からの相対なので、
      実際の上限を決めているのはジャンプの高さ。
   3. 掴む対象が無いのに TaskClimb を撃つと、空中で登攀動作だけが再生されて
      「二段ジャンプ」に見える。→ レイキャストで門番をする。
   4. 掴みが成立するフレームは狭い。押した瞬間はまだ壁に届いていないことが
      多いため、押下からしばらくはこちら側で機会を探す (assistWindowMs)。
   5. 登攀は他プレイヤーの画面にも登攀動作として同期される (本番鯖で確認済み)。
      サーバー中継の同期処理は不要。

 TaskClimb は無言で失敗するため、成功は「呼べた」ではなく IsPedClimbing /
 IsPedVaulting の状態遷移を観測して数えている。
===============================================================================
]]

local Config = KnMantleConfig
local RESOURCE_VERSION = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?'

local State = {
    enabled = Config.enabled,
    allowFall = Config.allowDuringFall,
    debug = Config.debug,

    lastAttemptAt = 0,
    airborneSince = 0,
    wasAirborne = false,
    attemptsThisAir = 0,
    armedUntil = 0,

    pending = nil,

    issues = 0,
    climbs = 0,
    vaults = 0,
    misses = 0,
    blocked = 0,
    noWall = 0,
    noReach = 0,
    lastResult = '-',
    lastRise = 0.0,
    maxRise = 0.0,
    lastReason = '-',

    -- 掴みが成立したときの縁の高さ (足元基準)。判定の帯を決めた実測値。
    lastGrabHeight = 0.0,
    maxGrabHeight = 0.0,

    probe = {
        hits = {},
        topZ = nil,
        topDist = nil,
        ok = false
    },
    probeAtAttempt = '-'
}

-- ----------------------------------------------------------------------------
-- 通知
-- ----------------------------------------------------------------------------

local function notify(message)
    local ok = pcall(function()
        exports.ox_lib:notify({ description = message, type = 'inform' })
    end)

    if ok then
        return
    end

    if GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', { args = { 'kn_mantle', message } })
        return
    end

    print(('[kn_mantle] %s'):format(message))
end

-- ----------------------------------------------------------------------------
-- 高さの基準
-- GetEntityCoords がペドの足元を返すか腰を返すかはモデル依存で当てにならない。
-- モデル境界の最下点から足元 Z を求め、頭の高さを HUD に出して検証可能にする。
-- (人型なら head はおよそ +1.6〜1.7m。大きくずれていれば基準が誤っている)
-- ----------------------------------------------------------------------------

local modelBottomCache = {}

local function footZOf(ped)
    local coords = GetEntityCoords(ped)
    local model = GetEntityModel(ped)
    local bottom = modelBottomCache[model]

    if bottom == nil then
        local minimum = GetModelDimensions(model)
        bottom = minimum and minimum.z or 0.0
        modelBottomCache[model] = bottom
    end

    return coords, coords.z + bottom
end

local function headHeight(ped, footZ)
    -- 0x796E = SKEL_Head
    local head = GetPedBoneCoords(ped, 0x796E, 0.0, 0.0, 0.0)
    return head.z - footZ
end

-- ----------------------------------------------------------------------------
-- レイキャスト (発行の門番を兼ねる)
-- ----------------------------------------------------------------------------

local function probeOnce(ped, origin, target)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        origin.x, origin.y, origin.z,
        target.x, target.y, target.z,
        Config.probeFlags, ped, 4
    )

    local _, hit, endCoords = GetShapeTestResult(handle)

    return (hit == 1 or hit == true), endCoords
end

local function runProbe(ped)
    local probe = State.probe
    local coords, footZ = footZOf(ped)
    local forward = GetEntityForwardVector(ped)

    probe.hits = {}
    probe.topZ = nil
    probe.topDist = nil
    probe.ok = false

    local nearestHitPoint = nil

    for index = 1, #Config.probeHeights do
        local height = Config.probeHeights[index]
        local origin = vector3(coords.x, coords.y, footZ + height)
        local target = origin + (forward * Config.probeDistance)

        local hit, endCoords = probeOnce(ped, origin, target)

        if hit then
            probe.hits[index] = #(vector3(endCoords.x, endCoords.y, endCoords.z) - origin)

            if not nearestHitPoint then
                nearestHitPoint = endCoords
            end
        else
            probe.hits[index] = -1.0
        end
    end

    -- 壁を捉えていれば、その少し奥から下向きに撃って「立てる天面」を探す
    if nearestHitPoint then
        local beyond = vector3(nearestHitPoint.x, nearestHitPoint.y, 0.0)
            + (forward * Config.probeTopForward)

        local origin = vector3(beyond.x, beyond.y, footZ + Config.probeTopMaxHeight)
        local target = vector3(beyond.x, beyond.y, footZ - 0.5)

        local hit, endCoords = probeOnce(ped, origin, target)

        if hit then
            probe.topZ = endCoords.z - footZ
            probe.topDist = #(vector3(endCoords.x, endCoords.y, footZ)
                - vector3(coords.x, coords.y, footZ))
        end
    end

    -- 門番の判定
    if probe.topZ
        and probe.topZ >= Config.grabMinHeight
        and probe.topZ <= Config.grabMaxHeight
        and (probe.topDist or 99.0) <= Config.grabMaxDistance
    then
        probe.ok = true
    end
end

local function probeSummary()
    local probe = State.probe
    local parts = {}

    for index = 1, #Config.probeHeights do
        local distance = probe.hits[index] or -1.0
        local height = Config.probeHeights[index]

        if distance >= 0.0 then
            parts[#parts + 1] = ('h%.1f:%.2f'):format(height, distance)
        else
            parts[#parts + 1] = ('h%.1f:--'):format(height)
        end
    end

    local top = 'top:none'
    if probe.topZ then
        top = ('top:+%.2f d%.2f %s'):format(probe.topZ, probe.topDist or 0.0,
            probe.ok and 'OK' or 'NG')
    end

    return table.concat(parts, ' ') .. '  ' .. top
end

-- ----------------------------------------------------------------------------
-- 状態判定
-- ----------------------------------------------------------------------------

local function blockReason(ped)
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return 'DEAD' end
    if IsPedInAnyVehicle(ped, true) then return 'VEH' end
    if IsPedRagdoll(ped) then return 'RAGDOLL' end
    if IsPedSwimming(ped) then return 'SWIM' end
    if IsPedCuffed(ped) then return 'CUFF' end
    if IsPedClimbing(ped) or IsPedVaulting(ped) then return 'BUSY' end
    if GetPedConfigFlag(ped, 388, true) then return 'LADDER' end
    if GetPedParachuteState(ped) ~= -1 then return 'CHUTE' end

    if GetEntityVelocity(ped).z < -Config.maxFallSpeed then
        return 'TOOFAST'
    end

    return nil
end

local function isAirborne(ped)
    if IsPedJumping(ped) then
        return true
    end

    if not State.allowFall then
        return false
    end

    return IsPedFalling(ped) or IsEntityInAir(ped)
end

-- ----------------------------------------------------------------------------
-- 発行と結果計測
-- 結果待ちは計測のためだけに存在する。次の試行は塞がない。
-- ----------------------------------------------------------------------------

local function issueClimb(ped)
    local coords = GetEntityCoords(ped)

    -- 未解決のまま置き換える場合、前回は空振りとして確定させる
    if State.pending and not State.pending.detected then
        State.misses = State.misses + 1
        State.lastResult = 'NONE'
    end

    TaskClimb(ped, false)

    State.lastAttemptAt = GetGameTimer()
    State.attemptsThisAir = State.attemptsThisAir + 1
    State.issues = State.issues + 1
    State.lastResult = 'WAIT'
    State.probeAtAttempt = probeSummary()

    State.pending = {
        deadline = State.lastAttemptAt + Config.resultWindowMs,
        hardDeadline = State.lastAttemptAt + Config.resultWindowMs + 5000,
        startZ = coords.z,
        topZ = State.probe.topZ,
        detected = false
    }
end

-- TaskClimb は無言で失敗する。状態遷移を観測して初めて成功と数える。
local function resolvePending(ped)
    local pending = State.pending
    if not pending then
        return
    end

    local now = GetGameTimer()

    if not pending.detected then
        if IsPedClimbing(ped) then
            pending.detected = true
            State.climbs = State.climbs + 1
            State.lastResult = 'CLIMB'
        elseif IsPedVaulting(ped) then
            pending.detected = true
            State.vaults = State.vaults + 1
            State.lastResult = 'VAULT'
        elseif now >= pending.deadline then
            State.misses = State.misses + 1
            State.lastResult = 'NONE'
            State.pending = nil
        end

        if pending.detected and pending.topZ then
            State.lastGrabHeight = pending.topZ
            if pending.topZ > State.maxGrabHeight then
                State.maxGrabHeight = pending.topZ
            end
        end

        return
    end

    if (not IsPedClimbing(ped) and not IsPedVaulting(ped)) or now >= pending.hardDeadline then
        local rise = GetEntityCoords(ped).z - pending.startZ

        State.lastRise = rise
        if rise > State.maxRise then
            State.maxRise = rise
        end

        State.pending = nil
    end
end

-- ----------------------------------------------------------------------------
-- メインループ
-- ----------------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = Config.idleWaitMs
        local ped = PlayerPedId()

        if State.pending then
            wait = 0
            resolvePending(ped)
        end

        if State.enabled then
            local airborne = isAirborne(ped)

            if airborne then
                wait = 0

                if not State.wasAirborne then
                    State.airborneSince = GetGameTimer()
                    State.attemptsThisAir = 0
                    State.armedUntil = 0
                end

                local now = GetGameTimer()

                -- 押した瞬間から assistWindowMs の間は、こちらで機会を探し続ける。
                -- 押しっぱなしでも延長する。
                if IsControlJustPressed(0, Config.control) then
                    State.armedUntil = now + Config.assistWindowMs
                elseif Config.holdRetry and IsControlPressed(0, Config.control) then
                    State.armedUntil = math.max(State.armedUntil, now + Config.retryMs)
                end

                local armed = now < State.armedUntil

                -- StartExpensiveSynchronousShapeTestLosProbe は名前の通り高価。
                -- 判定が要る瞬間 (アシスト窓の間) と、HUD を見ている間だけ撃つ。
                if armed or State.debug then
                    runProbe(ped)
                end

                if armed then
                    local reason = blockReason(ped)

                    if (now - State.airborneSince) < Config.minAirborneMs then
                        State.lastReason = 'TOOSOON'
                    elseif State.attemptsThisAir >= Config.maxAttemptsPerAir then
                        State.lastReason = 'BUDGET'
                    elseif IsNuiFocused() or IsPauseMenuActive() then
                        State.lastReason = 'NUI'
                    elseif reason then
                        State.lastReason = reason
                    elseif (now - State.lastAttemptAt) < Config.retryMs then
                        State.lastReason = 'WAITRETRY'
                    elseif Config.gateByProbe and not State.probe.ok then
                        -- 掴む対象が見えていないので撃たない。
                        -- これが「謎の二段ジャンプ」の正体だった。
                        State.blocked = State.blocked + 1

                        if State.probe.topZ then
                            State.lastReason = 'NOREACH'
                            State.noReach = State.noReach + 1
                        else
                            State.lastReason = 'NOWALL'
                            State.noWall = State.noWall + 1
                        end
                    else
                        State.lastReason = 'ISSUE'
                        issueClimb(ped)
                    end
                end
            else
                if State.wasAirborne then
                    State.attemptsThisAir = 0
                    State.armedUntil = 0
                end

                -- 地上でも HUD を見ている間はレイキャストを回す。
                -- 跳ぶ前に「この壁は OK か」を確認できるようにするため。
                -- 非滞空時のループは idleWaitMs (250ms) 間隔なので負荷は小さい。
                if State.debug then
                    runProbe(ped)
                end
            end

            State.wasAirborne = airborne
        else
            State.wasAirborne = false
        end

        Wait(wait)
    end
end)

-- ----------------------------------------------------------------------------
-- デバッグ HUD (DrawText は日本語グリフを持たないため ASCII 固定)
-- ----------------------------------------------------------------------------

local function drawLine(text, y, r, g, b)
    SetTextFont(4)
    SetTextScale(0.0, 0.32)
    SetTextColour(r, g, b, 220)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(Config.hudX, y)
end

local function flag(label, value)
    return value and (label .. ':1') or (label .. ':0')
end

-- Config.debug が false のときは HUD スレッド自体を作らない。
if Config.debug then

    CreateThread(function()
        while true do
            if not State.debug then
                Wait(500)
            else
                local ped = PlayerPedId()
                local _, footZ = footZOf(ped)
                local velocity = GetEntityVelocity(ped)
                local y = Config.hudY

                drawLine(('kn_mantle %s %s fall:%s hold:%s gate:%s')
                    :format(RESOURCE_VERSION,
                        State.enabled and 'ON' or 'OFF',
                        State.allowFall and 'ON' or 'OFF',
                        Config.holdRetry and 'ON' or 'OFF',
                        Config.gateByProbe and 'ON' or 'OFF'), y, 120, 220, 255)
                y = y + 0.021

                -- head は基準の検証用。人型なら +1.6〜1.7 が正しい。
                drawLine(table.concat({
                    flag('AIR', IsEntityInAir(ped)),
                    flag('JUMP', IsPedJumping(ped)),
                    flag('FALL', IsPedFalling(ped)),
                    flag('CLIMB', IsPedClimbing(ped)),
                    ('vz:%.1f'):format(velocity.z),
                    ('head:+%.2f'):format(headHeight(ped, footZ))
                }, ' '), y, 255, 255, 255)
                y = y + 0.021

                drawLine('probe ' .. probeSummary(), y, 180, 255, 180)
                y = y + 0.021

                drawLine(('try:%d/%d issued:%d climb:%d vault:%d none:%d')
                    :format(State.attemptsThisAir, Config.maxAttemptsPerAir,
                        State.issues, State.climbs, State.vaults,
                        State.misses), y, 255, 255, 255)
                y = y + 0.021

                drawLine(('gated:%d (nowall:%d noreach:%d)  band:%.2f-%.2f d<=%.2f')
                    :format(State.blocked, State.noWall, State.noReach,
                        Config.grabMinHeight, Config.grabMaxHeight,
                        Config.grabMaxDistance), y, 255, 180, 180)
                y = y + 0.021

                drawLine(('last:%s why:%s rise:%.2f max:%.2f')
                    :format(State.lastResult, State.lastReason,
                        State.lastRise, State.maxRise), y, 255, 220, 120)
                y = y + 0.021

                -- 掴みが成立したときの縁の高さ = バニラの登攀リーチの実測値
                drawLine(('grab-h last:%.2f max:%.2f | at-try %s')
                    :format(State.lastGrabHeight, State.maxGrabHeight,
                        State.probeAtAttempt), y, 200, 200, 160)

                Wait(0)
            end
        end
    end)

end

-- ----------------------------------------------------------------------------
-- ゲーム内コマンド
-- ----------------------------------------------------------------------------

-- 常時使えるコマンド。プレイヤーが自分の掴みを切るためのもの。
RegisterCommand('mantle', function()
    State.enabled = not State.enabled
    notify(KnMantleL(State.enabled and 'notify.enabled' or 'notify.disabled'))
end, false)

-- ----------------------------------------------------------------------------
-- 以下は検証用。Config.debug が false のときは登録しない。
-- 判定の帯 (grabMaxHeight など) を実行時に変更できてしまうため、
-- 本番サーバーでプレイヤーに開放してはいけない。
-- ----------------------------------------------------------------------------

if Config.debug then

    RegisterCommand('mantlefall', function()
        State.allowFall = not State.allowFall
        notify(KnMantleL(State.allowFall and 'notify.fall.enabled' or 'notify.fall.disabled'))
    end, false)

    RegisterCommand('mantlehold', function()
        Config.holdRetry = not Config.holdRetry
        notify(KnMantleL(Config.holdRetry and 'notify.hold.enabled' or 'notify.hold.disabled'))
    end, false)

    -- 門番を切ると「掴む物が無くても撃つ」挙動に戻る。比較検証用。
    RegisterCommand('mantlegate', function()
        Config.gateByProbe = not Config.gateByProbe
        notify(KnMantleL(Config.gateByProbe and 'notify.gate.enabled' or 'notify.gate.disabled'))
    end, false)

    -- 判定の帯を実機で探すためのコマンド。
    -- ユーザーはリソースを再起動できないため、実行時に動かせるようにしてある。
    local function setNumber(field, raw, label)
        local value = tonumber(raw)

        if not value then
            notify(KnMantleL('notify.number.invalid', label))
            return
        end

        Config[field] = value
        notify(KnMantleL('notify.number.set', label, value))
    end

    RegisterCommand('mantlemax', function(_, args)
        setNumber('grabMaxHeight', args[1], 'grabMaxHeight')
    end, false)

    RegisterCommand('mantlemin', function(_, args)
        setNumber('grabMinHeight', args[1], 'grabMinHeight')
    end, false)

    RegisterCommand('mantledist', function(_, args)
        setNumber('grabMaxDistance', args[1], 'grabMaxDistance')
    end, false)

    RegisterCommand('mantledebug', function()
        State.debug = not State.debug
        notify(KnMantleL(State.debug and 'notify.debug.enabled' or 'notify.debug.disabled'))
    end, false)

    RegisterCommand('mantlereset', function()
        State.issues = 0
        State.climbs = 0
        State.vaults = 0
        State.misses = 0
        State.blocked = 0
        State.noWall = 0
        State.noReach = 0
        State.lastResult = '-'
        State.lastReason = '-'
        State.lastRise = 0.0
        State.maxRise = 0.0
        State.lastGrabHeight = 0.0
        State.maxGrabHeight = 0.0
        State.probeAtAttempt = '-'
        notify(KnMantleL('notify.reset'))
    end, false)

    -- 起動ログ。導入不備の切り分け用なので debug のときだけ出す。
    -- (F8 コンソールは非 ASCII を落とすため英字のみ)
    CreateThread(function()
        print(('[kn_mantle] v%s loaded (debug mode)'):format(RESOURCE_VERSION))
    end)

end
