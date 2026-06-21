#!/usr/bin/env python3
"""
开发工作区布局脚本。
创建一个三面板的开发环境：左侧主编辑器 + 右上终端 + 右下日志。

安装：复制到 ~/Library/Application Support/iTerm2/Scripts/
运行：iTerm2 菜单 > Scripts > dev_workspace
"""
import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    if not window:
        window = await iterm2.Window.async_create(connection)
        if not window:
            return

    tab = await window.async_create_tab()
    main_session = tab.current_session
    await main_session.async_set_name("Editor")

    right_session = await main_session.async_split_pane(vertical=True)
    await right_session.async_set_name("Terminal")

    log_session = await right_session.async_split_pane(vertical=False)
    await log_session.async_set_name("Logs")

    await main_session.async_activate()


iterm2.run_until_complete(main)
