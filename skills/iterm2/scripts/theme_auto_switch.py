#!/usr/bin/env python3
"""
根据 macOS 系统主题（深色/浅色）自动切换 iTerm2 配色方案。
支持实时监听主题变化，无需手动切换。

安装：复制到 ~/Library/Application Support/iTerm2/Scripts/AutoLaunch/
效果：系统主题切换时，所有 Profile 自动跟随切换配色
"""
import iterm2

DARK_PRESET = "Solarized Dark"
LIGHT_PRESET = "Solarized Light"


async def apply_theme(connection, theme_str):
    parts = theme_str.split(" ")
    preset_name = DARK_PRESET if "dark" in parts else LIGHT_PRESET
    preset = await iterm2.ColorPreset.async_get(connection, preset_name)
    if not preset:
        return
    profiles = await iterm2.PartialProfile.async_query(connection)
    for partial in profiles:
        profile = await partial.async_get_full_profile()
        await profile.async_set_color_preset(preset)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    current = await app.async_get_variable("effectiveTheme")
    if current:
        await apply_theme(connection, current)

    async with iterm2.VariableMonitor(
            connection, iterm2.VariableScopes.APP, "effectiveTheme", None) as mon:
        while True:
            theme = await mon.async_get()
            await apply_theme(connection, theme)


iterm2.run_forever(main)
