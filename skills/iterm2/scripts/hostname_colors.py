#!/usr/bin/env python3
"""
根据 SSH 连接的 hostname 自动切换终端配色，直观区分环境。
编辑 COLOR_MAP 配置你自己的主机与配色对应关系。

安装：复制到 ~/Library/Application Support/iTerm2/Scripts/AutoLaunch/
前提：需要安装 iTerm2 Shell Integration（it2-profile 等命令）
"""
import asyncio
import iterm2

# 自定义 hostname -> Color Preset 映射
COLOR_MAP = {
    "production": "Dark Background",
    "staging": "Solarized Dark",
    "localhost": "Light Background",
    "127.0.0.1": "Light Background",
}

DEFAULT_PRESET = "Light Background"


async def apply_color_for_session(connection, session):
    hostname = await session.async_get_variable("hostname") or ""
    host_key = next((k for k in COLOR_MAP if k in hostname), None)
    preset_name = COLOR_MAP[host_key] if host_key else DEFAULT_PRESET
    preset = await iterm2.ColorPreset.async_get(connection, preset_name)
    if preset:
        profile = await session.async_get_profile()
        await profile.async_set_color_preset(preset)


async def watch_session(connection, session_id, app):
    session = app.get_session_by_id(session_id)
    if session:
        await apply_color_for_session(connection, session)
    async with iterm2.VariableMonitor(
            connection, iterm2.VariableScopes.SESSION,
            "hostname", session_id) as mon:
        while True:
            await mon.async_get()
            s = app.get_session_by_id(session_id)
            if s:
                await apply_color_for_session(connection, s)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                asyncio.create_task(watch_session(connection, session.session_id, app))

    async with iterm2.NewSessionMonitor(connection) as mon:
        while True:
            sid = await mon.async_get()
            asyncio.create_task(watch_session(connection, sid, app))


iterm2.run_forever(main)
