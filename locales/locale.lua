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
 kn_mantle / locale runtime
-----------------------------------------------------------------------------
 KnMantleLocales[lang][key] = 文字列 (string.format の書式を含む)
 KnMantleL(key, ...) で取得する。

 注意: デバッグ HUD は GTA の DrawText で描画されるため、ゲーム側フォントに
 グリフが無い日本語は文字化けする。HUD の文言はロケールに置かず、
 コード側で ASCII の技術ラベル (JUMP / CLIMB 等) を直接使っている。
 ここに置くのはチャット通知など NUI 経由の文字列だけ。
===============================================================================
]]

KnMantleLocales = KnMantleLocales or {}

local FALLBACK_LANG = 'en'

function KnMantleL(key, ...)
    local lang = FALLBACK_LANG
    local config = KnMantleConfig

    if type(config) == 'table' and type(config.locale) == 'string' and config.locale ~= '' then
        lang = config.locale
    end

    local template

    local tbl = KnMantleLocales[lang]
    if type(tbl) == 'table' then
        template = tbl[key]
    end

    if template == nil then
        local fallback = KnMantleLocales[FALLBACK_LANG]
        if type(fallback) == 'table' then
            template = fallback[key]
        end
    end

    -- 翻訳が無い場合でも落とさない。キーをそのまま返して所在を分かるようにする。
    if type(template) ~= 'string' then
        return key
    end

    if select('#', ...) == 0 then
        return template
    end

    local ok, formatted = pcall(string.format, template, ...)
    if ok then
        return formatted
    end

    return template
end
