#!/usr/bin/env python3
"""
将当前标签页中所有分割面板设为广播输入模式（输入同步到所有面板）。
再次运行可取消广播。

安装：复制到 ~/Library/Application Support/iTerm2/Scripts/
运行：iTerm2 菜单 > Scripts > broadcast_input（切换广播模式）
"""
import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    if not window:
        return

    tab = window.current_tab
    if not tab:
        return

    current_domains = app.broadcast_domains
    sessions_in_tab = set(s.session_id for s in tab.sessions)

    # 检查当前标签是否已经在广播域中
    already_broadcasting = any(
        sessions_in_tab.issubset(set(d.sessions))
        for d in current_domains
    )

    if already_broadcasting:
        # 取消广播：移除包含本标签会话的域
        new_domains = [
            d for d in current_domains
            if not sessions_in_tab.intersection(set(d.sessions))
        ]
        await iterm2.async_set_broadcast_domains(connection, new_domains)
        await tab.current_session.async_inject(
            b'\r\n\x1b[32m[广播模式已关闭]\x1b[0m\r\n'
        )
    else:
        # 开启广播：为本标签所有会话创建广播域
        domain = iterm2.BroadcastDomain()
        for session in tab.sessions:
            domain.add_session(session)
        await iterm2.async_set_broadcast_domains(connection, current_domains + [domain])
        await tab.current_session.async_inject(
            b'\r\n\x1b[33m[广播模式已开启 - 输入将同步到所有面板]\x1b[0m\r\n'
        )


iterm2.run_until_complete(main)
