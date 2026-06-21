---
name: iterm2
description: 当用户要求"控制 iTerm2"、"创建终端窗口/标签/会话"、"分割终端面板"、"发送命令到终端"、"监控终端输出"、"修改终端配色/字体/样式"、"管理终端 Profile"、"广播输入到多个会话"、"保存/恢复窗口布局"、"监听键盘/焦点/会话事件"时，应使用此技能。此技能提供通过 iTerm2 Python API 编程控制 iTerm2 终端的完整能力。
version: 0.1.0
---

# iTerm2 Python API 控制技能

此技能提供通过 iTerm2 官方 Python API（`iterm2` 包）编程控制 iTerm2 终端的完整能力，涵盖窗口/标签/会话管理、命令执行、屏幕内容读取、配置修改、事件监控等所有核心功能。

---

## 环境准备

### 安装 iterm2 包

iTerm2 提供内置 Python 环境和 `iterm2` 包：

```bash
# 通过 iTerm2 内置 Python 环境安装（推荐）
~/Library/ApplicationSupport/iTerm2/iterm2env/versions/*/bin/pip3 install iterm2

# 或者通过标准 pip 安装
pip3 install iterm2
```

### 启用 Python API

在 iTerm2 中：**Preferences > General > Magic > Enable Python API**（需要打开此开关）。

### 脚本存放位置

- **手动执行脚本**：`~/Library/Application Support/iTerm2/Scripts/`
- **自动启动守护进程**：`~/Library/Application Support/iTerm2/Scripts/AutoLaunch/`

### 运行脚本的方式

```bash
# 方式一：通过 iTerm2 菜单 Scripts > <脚本名>
# 方式二：命令行运行（需确保无 PYTHONPATH 干扰）
~/Library/ApplicationSupport/iTerm2/iterm2env/versions/*/bin/python3 my_script.py

# 方式三：通过 it2run 工具（绕过权限弹窗）
/Applications/iTerm.app/Resources/it2run my_script.py
```

---

## 核心架构模式

### 基础脚本模板

iTerm2 Python API 基于 asyncio 异步架构，所有 API 调用都是 async/await：

```python
#!/usr/bin/env python3
import iterm2

async def main(connection):
    # connection 是与 iTerm2 进程的 WebSocket 连接
    app = await iterm2.async_get_app(connection)
    # 在此执行操作...

# 执行完 main() 后退出
iterm2.run_until_complete(main)
```

### 长期运行的守护进程模板

```python
#!/usr/bin/env python3
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)
    # 注册事件监听器、RPC 函数等...
    # main() 返回后脚本继续运行

# 永不退出，持续监听事件
iterm2.run_forever(main)
```

### async_get_app() 详解

```python
app = await iterm2.async_get_app(connection)
# app 是单例 App 对象，提供对所有窗口/标签/会话的访问
# create_if_needed=True（默认）：若单例不存在则创建
```

---

## 1. App 级别操作

### 获取 App 状态

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 获取当前激活的窗口
    window = app.current_window           # 同 current_terminal_window
    # current_terminal_window 已弃用，用 current_window

    # 获取所有窗口列表
    windows = app.windows                  # 同 terminal_windows（已弃用）

    # 查找特定对象
    session = app.get_session_by_id("session_id", include_buried=True)
    tab = app.get_tab_by_id("tab_id")
    window = app.get_window_by_id("window_id")
    window = app.get_window_for_tab("tab_id")

    # 获取 session 对应的 window 和 tab
    (window, tab) = app.get_window_and_tab_for_session(session)

    # 获取埋藏的会话（buried sessions）
    buried = app.buried_sessions

    # 获取广播域（broadcast domains）
    domains = app.broadcast_domains

    # 打印整个层级结构
    print(app.pretty_str())
```

### 激活 App

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 给 iTerm2 键盘焦点（把所有窗口提前）
    await app.async_activate(raise_all_windows=True, ignoring_other_apps=False)
```

### 获取主题

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 返回 list，可能包含：light, dark, automatic, minimal, highContrast
    theme = await app.async_get_theme()
    # 例如 ["dark", "minimal"]
    if "dark" in theme:
        print("当前是深色主题")
```

### App 全局变量

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 读取全局变量（如 effectiveTheme）
    theme = await app.async_get_variable("effectiveTheme")

    # 设置用户自定义全局变量（必须以 "user." 开头）
    await app.async_set_variable("user.myKey", "myValue")

    # 调用全局 RPC 函数
    result = await iterm2.async_invoke_function(
        connection,
        "my_function(arg: value)",
        timeout=10.0
    )
```

### 从外部启动 iTerm2（需要 PyObjC）

```python
import AppKit
import iterm2

# 启动 iTerm2 应用程序（如果未运行）
AppKit.NSWorkspace.sharedWorkspace().launchApplication_("iTerm2")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    await app.async_activate()
    # ...

iterm2.run_until_complete(main, retry=True)
# retry=True：连接失败时自动重试（适合从外部启动 iTerm2 后立即连接）
```

---

## 2. 窗口管理

### 创建新窗口

```python
async def main(connection):
    # 用默认 Profile 创建新窗口
    window = await iterm2.Window.async_create(connection)

    # 指定 Profile 名称
    window = await iterm2.Window.async_create(connection, profile="My Profile")

    # 指定启动命令
    window = await iterm2.Window.async_create(connection, command="/bin/bash")

    # 使用 Profile 自定义（不修改底层 Profile）
    customizations = iterm2.LocalWriteOnlyProfile()
    customizations.set_background_color(iterm2.Color(0, 0, 0))
    window = await iterm2.Window.async_create(
        connection,
        profile="Default",
        profile_customizations=customizations
    )

    if window is None:
        print("窗口创建后会话立即结束")
```

### 获取当前窗口

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    if window is None:
        print("没有打开的窗口")
        return
    print(f"当前窗口 ID: {window.window_id}")
```

### 窗口属性

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window

    # 获取窗口位置和大小（Frame 原点在主屏右下角）
    frame = await window.async_get_frame()
    # frame.origin.x, frame.origin.y, frame.size.width, frame.size.height

    # 设置窗口位置和大小
    new_frame = iterm2.Frame(
        origin=iterm2.Point(100, 200),
        size=iterm2.Size(800, 600)
    )
    await window.async_set_frame(new_frame)

    # 全屏状态
    is_fullscreen = await window.async_get_fullscreen()
    await window.async_set_fullscreen(True)

    # 激活窗口（给焦点，置于前台；不激活 App 本身）
    await window.async_activate()

    # 关闭窗口
    await window.async_close()            # 有确认提示
    await window.async_close(force=True)  # 跳过确认

    # 当前激活的标签
    current_tab = window.current_tab

    # 所有标签列表
    tabs = window.tabs

    # 格式化输出窗口层级
    print(window.pretty_str())
```

### 窗口变量

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window

    # 设置窗口用户变量（必须以 "user." 开头）
    await window.async_set_variable("user.project", "my-project")

    # 调用 RPC（在窗口上下文中）
    result = await window.async_invoke_function(
        "my_rpc(arg: value)",
        timeout=5.0
    )
```

### 窗口布局（重排标签）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    windows = app.windows

    if len(windows) >= 2:
        w1, w2 = windows[0], windows[1]
        tab_to_move = w1.current_tab

        # 把 tab_to_move 移动到 w2（tabs 列表末尾）
        await w2.async_set_tabs(w2.tabs + [tab_to_move])
        # 注意：Tab 会从原窗口移走
```

---

## 3. 标签管理

### 创建新标签

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window

    # 用默认 Profile 在末尾创建新标签
    tab = await window.async_create_tab()

    # 指定 Profile 和位置
    tab = await window.async_create_tab(
        profile="My Profile",
        command="/bin/zsh",
        index=0  # 0=最前，None=末尾
    )

    # 使用 Profile 自定义
    customizations = iterm2.LocalWriteOnlyProfile()
    customizations.set_foreground_color(iterm2.Color(255, 255, 255))
    tab = await window.async_create_tab(profile_customizations=customizations)

    # Tmux 标签
    # tab = await window.async_create_tmux_tab(tmux_connection)
```

### 标签属性与操作

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    tab = window.current_tab

    # Tab ID
    print(tab.tab_id)

    # 所有会话（不含最小化的会话）
    sessions = tab.sessions

    # 当前激活的会话
    current_session = tab.current_session

    # 分割面板的树形结构根节点
    root_splitter = tab.root  # Splitter 对象

    # 所属窗口
    parent_window = tab.window

    # 激活标签
    await tab.async_activate(order_window_front=True)
    await tab.async_select(order_window_front=True)  # 已弃用，用 async_activate

    # 关闭标签
    await tab.async_close()
    await tab.async_close(force=True)

    # 设置标签标题（插值字符串，空字符串恢复默认）
    await tab.async_set_title("我的标签")

    # 移动标签到新窗口（仅当标签不是所在窗口唯一标签时可用）
    new_window = await tab.async_move_to_window()

    # 激活相邻方向的分割面板
    # direction: NavigationDirection.LEFT/RIGHT/UP/DOWN
    new_session_id = await tab.async_select_pane_in_direction(
        iterm2.NavigationDirection.RIGHT
    )

    # 更新分割面板布局（先修改 session.preferred_size）
    await tab.async_update_layout()

    # 标签变量
    value = await tab.async_get_variable("user.myKey")
    await tab.async_set_variable("user.myKey", "value")

    print(tab.pretty_str())
```

### 遍历所有窗口/标签/会话

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    for window in app.windows:
        print(f"Window {window.window_id}")
        for tab in window.tabs:
            print(f"  Tab {tab.tab_id}")
            for session in tab.sessions:
                print(f"    Session {session.session_id}: {session.name}")
```

---

## 4. 会话管理（Session）

### 分割面板（Split Pane）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 垂直分割（左右），在右侧创建新会话
    right_session = await session.async_split_pane(vertical=True)

    # 垂直分割（左右），在左侧创建新会话
    left_session = await session.async_split_pane(vertical=True, before=True)

    # 水平分割（上下），在下方创建新会话
    bottom_session = await session.async_split_pane(vertical=False)

    # 水平分割（上下），在上方创建新会话
    top_session = await session.async_split_pane(vertical=False, before=True)

    # 分割时指定 Profile
    new_session = await session.async_split_pane(
        vertical=True,
        profile="My Profile"
    )

    # 分割时自定义 Profile 属性
    customizations = iterm2.LocalWriteOnlyProfile()
    customizations.set_background_color(iterm2.Color(30, 30, 30))
    new_session = await session.async_split_pane(
        vertical=True,
        profile_customizations=customizations
    )
```

### 创建典型的四格分割布局

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    # 获取起始会话（左下角）
    bottom_left = app.current_window.current_tab.current_session

    # 向右分割得到右下角
    bottom_right = await bottom_left.async_split_pane(vertical=True)

    # 在左下角上方分割得到左上角
    top_left = await bottom_left.async_split_pane(vertical=False, before=True)

    # 在右下角上方分割得到右上角
    top_right = await bottom_right.async_split_pane(vertical=False, before=True)

    # 激活左下角
    await bottom_left.async_activate()
```

### 发送文本/命令

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 发送文本（模拟用户键入）
    await session.async_send_text("echo hello\n")

    # 发送文本（抑制广播，只发到本会话）
    await session.async_send_text("ls -la\n", suppress_broadcast=True)

    # 注入数据（模拟程序输出，不是用户输入）
    await session.async_inject(b"This appears as terminal output\r\n")

    # 注入 ANSI 控制序列（例如清除滚动缓冲区）
    code = b'\x1b]1337;ClearScrollback\x07'
    await session.async_inject(code)
```

### 会话属性

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 唯一 ID
    print(session.session_id)

    # 会话名称（标题）
    print(session.name)

    # 所属 Tab 和 Window
    tab = session.tab
    window = session.window

    # 网格尺寸（列数×行数）
    size = session.grid_size
    print(f"宽:{size.width} 高:{size.height}")

    # 目标尺寸（用于 tab.async_update_layout）
    session.preferred_size = iterm2.Size(80, 24)

    # 是否被埋藏
    print(session.buried)
```

### 激活会话

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 激活会话（选中其所在 Tab，并把窗口提到前台）
    await session.async_activate(select_tab=True, order_window_front=True)

    # 仅激活会话（不移动窗口到前台）
    await session.async_activate(order_window_front=False)
```

### 关闭与重启

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 关闭（有确认提示）
    await session.async_close()

    # 强制关闭（无确认）
    await session.async_close(force=True)

    # 重启会话
    await session.async_restart()

    # 仅在会话已退出时重启（如果还在运行则抛异常）
    await session.async_restart(only_if_exited=True)
```

### 埋藏会话（Bury/Disinter）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 埋藏会话（从界面隐藏，但保持运行）
    await session.async_set_buried(True)

    # 恢复埋藏的会话
    buried_sessions = app.buried_sessions
    if buried_sessions:
        await buried_sessions[0].async_set_buried(False)
```

### 调整会话大小

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 设置会话网格大小（仅适用于单面板 Tab，不能在全屏窗口使用）
    await session.async_set_grid_size(iterm2.Size(120, 40))
```

### 会话变量

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 读取内置会话变量
    hostname = await session.async_get_variable("hostname")
    username = await session.async_get_variable("username")
    pwd = await session.async_get_variable("path")
    pid = await session.async_get_variable("pid")
    job_name = await session.async_get_variable("jobName")

    # 设置用户自定义变量（必须以 "user." 开头）
    await session.async_set_variable("user.project", "my-project")
    value = await session.async_get_variable("user.project")

    # 在会话上下文中调用 RPC
    result = await session.async_invoke_function(
        "my_function(arg: value)",
        timeout=5.0
    )
```

### 设置会话名称（标题）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 方式一：通过 RPC 设置名称（临时）
    await session.async_set_name("My Custom Session Name")

    # 方式二：通过 Profile 属性设置（永久，且禁止 escape sequence 修改）
    update = iterm2.LocalWriteOnlyProfile()
    update.set_name("Permanent Session Name")
    update.set_allow_title_setting(False)  # 禁止 escape 序列修改标题
    await session.async_set_profile_properties(update)
```

---

## 5. 读取屏幕内容

### 读取当前屏幕内容

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 读取可见屏幕区域
    contents = await session.async_get_screen_contents()
    print(f"光标位置: {contents.cursor_coord}")
    print(f"可见行数: {contents.number_of_lines}")
    print(f"屏幕以上行数: {contents.number_of_lines_above_screen}")

    # 逐行读取
    for i in range(contents.number_of_lines):
        line = contents.line(i)
        print(f"Line {i}: {line.string}")
        print(f"  硬换行: {line.hard_eol}")
        # 读取某列的字符
        char = line.string_at(0)
```

### 读取历史缓冲区内容（需要 Transaction）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # Transaction 确保读取期间终端状态不变
    async with iterm2.Transaction(connection):
        line_info = await session.async_get_line_info()
        # line_info.overflow: 溢出（丢失）的历史行数
        # line_info.scrollback_buffer_height: 历史缓冲区高度
        # line_info.mutable_area_height: 可见屏幕高度
        # line_info.first_visible_line_number: 顶部可见行号

        # 读取历史记录中的 100 行（从溢出点开始）
        lines = await session.async_get_contents(
            first_line=line_info.overflow,
            number_of_lines=100
        )

    for line in lines:
        print(line.string)
```

### 实时监控屏幕变化

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # get_screen_streamer() 返回上下文管理器
    async with session.get_screen_streamer(want_contents=True) as streamer:
        count = 0
        while count < 10:
            # 阻塞直到屏幕内容变化
            contents = await streamer.async_get()
            if contents:
                for i in range(contents.number_of_lines):
                    line = contents.line(i)
                    if line.string.strip():
                        print(f"  {line.string}")
            count += 1
```

### 读取选中文本

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 获取当前选中的文本区域
    selection = await session.async_get_selection()

    # 读取选中区域的文本内容
    text = await session.async_get_selection_text(selection)
    print(f"选中文本: {text}")

    # 设置选中区域
    # 创建坐标范围
    start = iterm2.Point(0, 0)
    end = iterm2.Point(80, 5)
    coord_range = iterm2.CoordRange(start, end)
    windowed_range = iterm2.WindowedCoordRange(coord_range)
    sub = iterm2.SubSelection(
        windowed_range,
        iterm2.SelectionMode.CHARACTER,
        connected=False
    )
    new_selection = iterm2.Selection([sub])
    await session.async_set_selection(new_selection)
```

---

## 6. Profile 管理

### 获取 Profile

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 获取所有 Profile
    profiles = await iterm2.Profile.async_get(connection)
    for p in profiles:
        print(f"Profile: {p.name} (GUID: {p.guid})")

    # 获取默认 Profile
    default_profile = await iterm2.Profile.async_get_default(connection)
    print(f"默认 Profile: {default_profile.name}")

    # 获取指定 Profile（通过 GUID 列表）
    specific_profiles = await iterm2.Profile.async_get(
        connection,
        guids=["profile-guid-here"]
    )

    # 获取当前会话的 Profile（含会话级覆盖）
    session = app.current_window.current_tab.current_session
    session_profile = await session.async_get_profile()
```

### 修改 Profile 颜色

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 获取会话的 Profile
    profile = await session.async_get_profile()

    # 设置背景色（RGBA，0-255）
    await profile.async_set_background_color(iterm2.Color(30, 30, 30, 255))

    # 设置前景色
    await profile.async_set_foreground_color(iterm2.Color(220, 220, 220))

    # 设置光标颜色
    await profile.async_set_cursor_color(iterm2.Color(255, 255, 255))

    # 设置 ANSI 颜色（0-15 对应标准 16 色）
    await profile.async_set_ansi_0_color(iterm2.Color(0, 0, 0))       # 黑
    await profile.async_set_ansi_1_color(iterm2.Color(205, 0, 0))     # 红
    await profile.async_set_ansi_2_color(iterm2.Color(0, 205, 0))     # 绿
    await profile.async_set_ansi_3_color(iterm2.Color(205, 205, 0))   # 黄
    await profile.async_set_ansi_4_color(iterm2.Color(0, 0, 238))     # 蓝
    await profile.async_set_ansi_5_color(iterm2.Color(205, 0, 205))   # 品红
    await profile.async_set_ansi_6_color(iterm2.Color(0, 205, 205))   # 青
    await profile.async_set_ansi_7_color(iterm2.Color(229, 229, 229)) # 白
    # 亮色版本：8-15（ansi_8_color 到 ansi_15_color）

    # 选中文本颜色
    await profile.async_set_selection_color(iterm2.Color(82, 130, 183))
    await profile.async_set_selected_text_color(iterm2.Color(255, 255, 255))

    # 链接颜色
    await profile.async_set_link_color(iterm2.Color(0, 100, 255))

    # 标签颜色
    await profile.async_set_tab_color(iterm2.Color(50, 100, 150))

    # 徽章颜色
    await profile.async_set_badge_color(iterm2.Color(255, 100, 0, 128))
```

### 使用 LocalWriteOnlyProfile 修改会话 Profile（不影响底层 Profile）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # LocalWriteOnlyProfile 只写、不读，批量修改后一次性应用
    change = iterm2.LocalWriteOnlyProfile()

    # 修改背景色
    change.set_background_color(iterm2.Color(20, 20, 30))

    # 修改字体（格式："FontName Size"）
    change.set_normal_font("MesloLGS-NF-Regular 14")

    # 修改透明度（0.0=不透明，1.0=完全透明）
    change.set_transparency(0.1)

    # 开启背景模糊
    change.set_blur(True)
    change.set_blur_radius(5.0)

    # 禁止 escape 序列修改标题
    change.set_allow_title_setting(False)

    # 应用到当前会话（只修改会话的本地副本）
    await session.async_set_profile_properties(change)
```

### 修改字体

```python
import re

async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    profile = await session.async_get_profile()

    # 当前字体（格式："{FontName} {Size}"）
    font = profile.normal_font
    print(f"当前字体: {font}")

    # 增加字号（使用正则解析）
    r = re.compile(r'^(.*) (\d+)(.*)$')
    match = r.search(font)
    if match:
        name, size, rest = match.groups()
        new_font = f"{name} {int(size) + 2}{rest}"
        change = iterm2.LocalWriteOnlyProfile()
        change.set_normal_font(new_font)
        await session.async_set_profile_properties(change)

    # 非 ASCII 字体
    non_ascii_font = profile.non_ascii_font
    change = iterm2.LocalWriteOnlyProfile()
    change.set_non_ascii_font("MesloLGS-NF-Regular 14")
    change.set_use_non_ascii_font(True)
    await session.async_set_profile_properties(change)
```

### 透明度和模糊

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    change = iterm2.LocalWriteOnlyProfile()

    # 透明度（0.0 不透明，1.0 完全透明）
    change.set_transparency(0.15)

    # 背景图片模糊（布尔值）
    change.set_blur(True)
    # 模糊半径（0-30）
    change.set_blur_radius(8.0)

    await session.async_set_profile_properties(change)
```

### 应用 Color Preset

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 获取可用的 Color Preset（返回 ColorPreset 对象，有 .name 属性）
    preset = await iterm2.ColorPreset.async_get(connection, "Solarized Dark")
    if preset:
        profile = await session.async_get_profile()
        await profile.async_set_color_preset(preset)

    # 对所有 Profile 应用 Preset（适合主题切换）
    profiles = await iterm2.PartialProfile.async_query(connection)
    for partial in profiles:
        full_profile = await partial.async_get_full_profile()
        await full_profile.async_set_color_preset(preset)
```

### 列出可用 Color Presets

```python
# ColorPreset.async_get() 只能通过名称获取，无法列出所有预设
# 可用内置预设名称示例：
# "Dark Background", "Light Background", "Solarized Dark", "Solarized Light"
# "Tango Dark", "Tango Light", "Tomorrow Night Eighties" 等
```

### 检测当前 Profile 使用的 Color Preset

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session
    profile = await session.async_get_profile()

    known_presets = [
        "Dark Background", "Light Background",
        "Solarized Dark", "Solarized Light",
        "Tango Dark", "Tango Light",
    ]

    def colors_equal(a, b):
        return (a.red == b.red and a.green == b.green and
                a.blue == b.blue and a.alpha == b.alpha)

    for preset_name in known_presets:
        preset = await iterm2.ColorPreset.async_get(connection, preset_name)
        if preset:
            match = all(
                colors_equal(
                    getattr(profile, f"ansi_{i}_color"),
                    getattr(preset, f"ansi_{i}_color", None) or iterm2.Color()
                )
                for i in range(8)
            )
            if match:
                print(f"当前使用 preset: {preset_name}")
                break
```

### Profile 其他属性

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session
    profile = await session.async_get_profile()

    # 滚动缓冲区
    print(f"滚动行数: {profile.scrollback_lines}")
    await profile.async_set_scrollback_lines(10000)
    await profile.async_set_unlimited_scrollback(True)

    # 光标样式
    await profile.async_set_cursor_type(iterm2.CursorType.BLOCK)  # 方块
    # iterm2.CursorType.VERTICAL_BAR  # 竖线
    # iterm2.CursorType.UNDERLINE      # 下划线

    # 闪烁光标
    await profile.async_set_blinking_cursor(True)

    # 状态栏
    await profile.async_set_status_bar_enabled(True)

    # 铃声
    await profile.async_set_silence_bell(True)
    await profile.async_set_visual_bell(True)

    # 关闭时不确认
    await profile.async_set_prompt_before_closing(False)
    await profile.async_set_close_sessions_on_end(True)

    # 徽章文本
    await profile.async_set_badge_text("Hello")

    # 将此 Profile 设为默认
    await profile.async_make_default()
```

---

## 7. 广播输入（Broadcast）

### 设置广播域

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    tab = window.current_tab

    # 创建广播域（让多个 session 共享输入）
    domain = iterm2.BroadcastDomain()

    # 将会话加入广播域
    for session in tab.sessions:
        domain.add_session(session)

    # 应用广播域配置（替换所有现有广播域）
    await iterm2.async_set_broadcast_domains(connection, [domain])

    # 清除所有广播（传入空列表）
    await iterm2.async_set_broadcast_domains(connection, [])
```

### 手动广播输入到多个会话

```python
import asyncio
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 创建四格布局
    bottom_left = app.current_window.current_tab.current_session
    bottom_right = await bottom_left.async_split_pane(vertical=True)
    top_left = await bottom_left.async_split_pane(vertical=False, before=True)
    top_right = await bottom_right.async_split_pane(vertical=False, before=True)

    await bottom_left.async_activate()
    broadcast_to = [top_left, bottom_left, top_right, bottom_right]

    async def handle_keystroke(keystroke):
        if keystroke.keycode == iterm2.Keycode.ESCAPE:
            return True  # 按 ESC 退出广播
        for session in broadcast_to:
            await session.async_send_text(keystroke.characters)
        return False

    pattern = iterm2.KeystrokePattern()
    pattern.keycodes = list(iterm2.Keycode)
    pattern.forbidden_modifiers = [iterm2.Modifier.COMMAND]

    future = asyncio.Future()

    async def filter_keystrokes():
        async with iterm2.KeystrokeFilter(
                connection, [pattern], bottom_left.session_id) as mon:
            await asyncio.wait([future])

    task = asyncio.create_task(filter_keystrokes())

    async with iterm2.KeystrokeMonitor(
            connection, bottom_left.session_id) as mon:
        done = False
        while not done:
            keystroke = await mon.async_get()
            done = await handle_keystroke(keystroke)
        future.set_result(True)

    await task

iterm2.run_until_complete(main)
```

---

## 8. 键盘监控与过滤

### 监控所有键盘输入

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 监控所有会话的键盘输入（不传 session_id）
    async with iterm2.KeystrokeMonitor(connection) as mon:
        for _ in range(10):
            keystroke = await mon.async_get()
            print(f"键: {keystroke.characters!r}")
            print(f"  忽略修饰键: {keystroke.characters_ignoring_modifiers!r}")
            print(f"  Keycode: {keystroke.keycode}")
            print(f"  修饰键: {keystroke.modifiers}")

iterm2.run_until_complete(main)
```

### 监控特定会话的键盘输入

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 监控特定会话（包含 key-up 和 flags-changed 事件）
    async with iterm2.KeystrokeMonitor(
            connection,
            session.session_id,
            advanced=True) as mon:
        while True:
            keystroke = await mon.async_get()
            if keystroke.keycode == iterm2.Keycode.ANSI_Q:
                break

iterm2.run_until_complete(main)
```

### 使用函数键切换标签

```python
import asyncio
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)
    keycodes = [iterm2.Keycode.F1, iterm2.Keycode.F2, iterm2.Keycode.F3,
                iterm2.Keycode.F4, iterm2.Keycode.F5, iterm2.Keycode.F6,
                iterm2.Keycode.F7, iterm2.Keycode.F8, iterm2.Keycode.F9,
                iterm2.Keycode.F10, iterm2.Keycode.F11, iterm2.Keycode.F12]

    async def keystroke_handler(keystroke):
        if keystroke.modifiers == [iterm2.Modifier.FUNCTION]:
            try:
                idx = keycodes.index(keystroke.keycode)
                tabs = app.current_window.tabs
                if 0 <= idx < len(tabs):
                    await tabs[idx].async_select()
            except ValueError:
                pass

    pattern = iterm2.KeystrokePattern()
    pattern.forbidden_modifiers.extend([
        iterm2.Modifier.CONTROL, iterm2.Modifier.OPTION,
        iterm2.Modifier.COMMAND, iterm2.Modifier.SHIFT, iterm2.Modifier.NUMPAD
    ])
    pattern.required_modifiers.append(iterm2.Modifier.FUNCTION)
    pattern.keycodes.extend(keycodes)

    async def monitor():
        async with iterm2.KeystrokeMonitor(connection) as mon:
            while True:
                keystroke = await mon.async_get()
                await keystroke_handler(keystroke)

    asyncio.create_task(monitor())

    async with iterm2.KeystrokeFilter(connection, [pattern]) as f:
        await iterm2.async_wait_forever()

iterm2.run_forever(main)
```

### 拦截/过滤键盘输入

```python
async def main(connection):
    # KeystrokePattern：定义要拦截的键盘模式
    pattern = iterm2.KeystrokePattern()

    # 拦截所有带 Ctrl 的键
    pattern.required_modifiers = [iterm2.Modifier.CONTROL]

    # 允许的 keycode 列表（拦截所有字母键 + Ctrl）
    pattern.keycodes = [
        iterm2.Keycode.ANSI_A,
        iterm2.Keycode.ANSI_B,
        # ...
    ]

    # 禁止带 Command 键的组合（Command+Ctrl 不拦截）
    pattern.forbidden_modifiers = [iterm2.Modifier.COMMAND]

    # 在特定会话中拦截
    session = (await iterm2.async_get_app(connection)).current_window.current_tab.current_session
    async with iterm2.KeystrokeFilter(
            connection,
            [pattern],
            session.session_id) as filter:
        await iterm2.async_wait_forever()

iterm2.run_forever(main)
```

---

## 9. 焦点与布局变更监控

### 监控焦点变化

```python
async def main(connection):
    async with iterm2.FocusMonitor(connection) as mon:
        while True:
            update = await mon.async_get_next_update()
            # update 的类型：
            # - iterm2.FocusUpdate.ApplicationActive: iTerm2 是否激活
            # - iterm2.FocusUpdate.WindowChanged: 窗口焦点变化
            # - iterm2.FocusUpdate.SelectedTabChanged: 标签切换
            # - iterm2.FocusUpdate.ActiveSessionChanged: 会话切换

            if hasattr(update, 'window_id'):
                print(f"窗口变化: {update.window_id} 原因: {update.reason}")
            elif hasattr(update, 'tab_id'):
                print(f"标签切换: {update.tab_id}")
            elif hasattr(update, 'session_id'):
                print(f"会话切换: {update.session_id}")

iterm2.run_until_complete(main)
```

### 监控布局变化

```python
async def main(connection):
    async with iterm2.LayoutChangeMonitor(connection) as mon:
        while True:
            await mon.async_get()
            # 以下情况触发：会话移动、标签/会话排序变化、
            # 大小调整、会话埋藏/恢复、窗口大小调整
            app = await iterm2.async_get_app(connection)
            print("布局已变更，当前结构：")
            print(app.pretty_str())

iterm2.run_until_complete(main)
```

---

## 10. 会话生命周期监控

### 监控新会话创建

```python
import asyncio
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)

    async with iterm2.NewSessionMonitor(connection) as mon:
        while True:
            session_id = await mon.async_get()
            session = app.get_session_by_id(session_id)
            if session:
                print(f"新会话: {session_id}")
                # 对新会话执行操作，例如设置样式
                change = iterm2.LocalWriteOnlyProfile()
                change.set_background_color(iterm2.Color(20, 20, 20))
                await session.async_set_profile_properties(change)

iterm2.run_forever(main)
```

### 监控会话结束

```python
async def main(connection):
    async with iterm2.SessionTerminationMonitor(connection) as mon:
        while True:
            session_id = await mon.async_get()
            print(f"会话结束: {session_id}")

iterm2.run_forever(main)
```

### 对每个会话（含未来会话）各执行一次

```python
import asyncio
import iterm2

async def setup_session(session_id, app):
    """对每个新会话执行初始化"""
    session = app.get_session_by_id(session_id)
    if session:
        print(f"初始化会话: {session_id}")
        # 在此处理新会话...

async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 方式一：使用 async_foreach_session_create_task（自动管理任务）
    await iterm2.EachSessionOnceMonitor.async_foreach_session_create_task(
        app,
        lambda session_id: setup_session(session_id, app)
    )

    # 方式二：手动使用上下文管理器
    async with iterm2.EachSessionOnceMonitor(connection) as mon:
        while True:
            session_id = await mon.async_get()
            asyncio.create_task(setup_session(session_id, app))

iterm2.run_forever(main)
```

---

## 11. 变量监控

### 监控 Session 变量变化

```python
import asyncio
import iterm2

async def monitor_session(connection, session_id):
    async with iterm2.VariableMonitor(
            connection,
            iterm2.VariableScopes.SESSION,
            "hostname",
            session_id) as mon:
        while True:
            hostname = await mon.async_get()
            print(f"Session {session_id} 的 hostname 变为: {hostname}")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                asyncio.create_task(
                    monitor_session(connection, session.session_id)
                )

iterm2.run_forever(main)
```

### 监控主题变化（App 级变量）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 先处理当前主题
    current_theme = await app.async_get_variable("effectiveTheme")
    print(f"当前主题: {current_theme}")

    # 然后监控变化
    async with iterm2.VariableMonitor(
            connection,
            iterm2.VariableScopes.APP,
            "effectiveTheme",
            None) as mon:
        while True:
            theme = await mon.async_get()
            print(f"主题变为: {theme}")

            # 根据主题切换配色
            parts = theme.split(" ")
            preset_name = "Dark Background" if "dark" in parts else "Light Background"
            preset = await iterm2.ColorPreset.async_get(connection, preset_name)
            if preset:
                profiles = await iterm2.PartialProfile.async_query(connection)
                for partial in profiles:
                    profile = await partial.async_get_full_profile()
                    await profile.async_set_color_preset(preset)

iterm2.run_forever(main)
```

---

## 12. Shell Prompt 监控（需要 Shell Integration）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 获取最近一次 prompt 信息
    prompt = await iterm2.async_get_last_prompt(connection, session.session_id)
    if prompt:
        print(f"命令: {prompt.command_}")
        print(f"工作目录: {prompt.working_directory_}")

    # 监控 Prompt 事件
    async with iterm2.PromptMonitor(
            connection,
            session.session_id,
            modes=[
                iterm2.PromptMonitor.Mode.PROMPT,
                iterm2.PromptMonitor.Mode.COMMAND_START,
                iterm2.PromptMonitor.Mode.COMMAND_END,
            ]) as mon:
        while True:
            mode, info = await mon.async_get()
            if mode == iterm2.PromptMonitor.Mode.PROMPT:
                print("检测到新 prompt")
            elif mode == iterm2.PromptMonitor.Mode.COMMAND_START:
                print("命令开始执行")
            elif mode == iterm2.PromptMonitor.Mode.COMMAND_END:
                print("命令执行结束")

iterm2.run_until_complete(main)
```

---

## 13. 自定义控制序列（Custom Control Sequences）

### 注册监听器（守护进程）

```python
#!/usr/bin/env python3
import iterm2

async def main(connection):
    # 监听发往所有会话的自定义控制序列
    async with iterm2.CustomControlSequenceMonitor(
            connection,
            "my-shared-secret",   # 共享密钥（防止未授权代码调用）
            r'^create-window$'    # 匹配载荷的正则
    ) as mon:
        while True:
            match = await mon.async_get()
            # match 是 re.Match 对象
            await iterm2.Window.async_create(connection)

iterm2.run_forever(main)
```

### 监听特定会话的控制序列

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    async with iterm2.CustomControlSequenceMonitor(
            connection,
            "my-secret",
            r'^set-color:(.+)$',  # 捕获颜色名
            session_id=session.session_id
    ) as mon:
        while True:
            match = await mon.async_get()
            color_name = match.group(1)
            print(f"收到颜色指令: {color_name}")

iterm2.run_forever(main)
```

### 从终端发送自定义控制序列

```bash
# 在终端中发送（格式：\033]1337;Custom=id={secret}:{payload}\a）
printf "\033]1337;Custom=id=my-shared-secret:create-window\a"
printf "\033]1337;Custom=id=my-secret:set-color:blue\a"
```

---

## 14. RPC 注册（Remote Procedure Calls）

### 注册全局 RPC

```python
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)

    @iterm2.RPC
    async def clear_all_sessions():
        """清除所有会话的滚动缓冲区"""
        code = b'\x1b]1337;ClearScrollback\x07'
        for window in app.windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    await session.async_inject(code)

    # 注册（默认超时 5 秒）
    await clear_all_sessions.async_register(connection)

    # 自定义超时
    await clear_all_sessions.async_register(connection, timeout=30.0)

iterm2.run_forever(main)
```

### 带 Session 上下文的 RPC

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)

    @iterm2.RPC
    async def rename_session(
        session_id=iterm2.Reference("id"),          # 必选：当前 session ID
        new_name=iterm2.Reference("user.newName?")  # 可选：用户变量（? 表示可选）
    ):
        session = app.get_session_by_id(session_id)
        if session:
            name = new_name or "Unnamed"
            await session.async_set_name(name)

    await rename_session.async_register(connection)

iterm2.run_forever(main)
```

### RPC 绑定快捷键

在 iTerm2 中：**Preferences > Keys > Key Bindings > + > Action: Invoke Script Function**，填入函数调用字符串，例如：
```
clear_all_sessions()
rename_session(new_name: "MySession")
```

---

## 15. 自定义标题提供者（Title Provider）

```python
import iterm2

async def main(connection):
    @iterm2.TitleProviderRPC
    async def custom_title(
        auto_name=iterm2.Reference("autoName?"),
        job=iterm2.Reference("jobName?"),
        hostname=iterm2.Reference("hostname?")
    ):
        parts = []
        if hostname:
            parts.append(hostname)
        if job:
            parts.append(job)
        if auto_name:
            parts.append(auto_name)
        return " | ".join(parts) if parts else ""

    await custom_title.async_register(
        connection,
        display_name="Host | Job | Auto",           # 在偏好设置中显示的名称
        unique_identifier="com.example.custom-title" # 反向域名格式的唯一 ID
    )

iterm2.run_forever(main)
```

---

## 16. 自定义状态栏组件（Status Bar）

```python
import iterm2
import asyncio

async def main(connection):
    component = iterm2.StatusBarComponent(
        short_description="Git Branch",
        detailed_description="显示当前 Git 分支名称",
        knobs=[
            iterm2.CheckboxKnob("显示图标", True, "show_icon"),
            iterm2.StringKnob("前缀", "branch: ", "", "prefix"),
        ],
        exemplar="branch: main",
        update_cadence=5,  # 每 5 秒刷新，None 表示手动触发
        identifier="com.example.git-branch"
    )

    @iterm2.StatusBarRPC
    async def git_branch_coro(
        knobs,
        path=iterm2.Reference("path?")
    ):
        if not path:
            return ""
        try:
            import subprocess
            result = subprocess.run(
                ["git", "branch", "--show-current"],
                capture_output=True, text=True, cwd=path
            )
            branch = result.stdout.strip()
            prefix = knobs.get("prefix", "branch: ")
            return f"{prefix}{branch}" if branch else ""
        except Exception:
            return ""

    await component.async_register(connection, git_branch_coro)

iterm2.run_forever(main)
```

---

## 17. 自定义右键菜单项（Context Menu）

```python
import iterm2

async def main(connection):
    @iterm2.ContextMenuProviderRPC
    async def open_in_editor():
        """在编辑器中打开当前路径"""
        app = await iterm2.async_get_app(connection)
        session = app.current_window.current_tab.current_session
        path = await session.async_get_variable("path")
        if path:
            import subprocess
            subprocess.Popen(["code", path])

    await open_in_editor.async_register(
        connection,
        "在 VS Code 中打开",             # 菜单项名称
        "com.example.open-in-editor"    # 唯一标识符
    )

iterm2.run_forever(main)
```

---

## 18. 窗口布局（Arrangements）

```python
import iterm2

async def main(connection):
    # 列出所有已保存的布局（需要 iTerm2 3.4.0+）
    names = await iterm2.Arrangement.async_list(connection)
    print(f"已保存的布局: {names}")

    # 保存当前所有窗口为布局
    await iterm2.Arrangement.async_save(connection, "My Layout")

    # 恢复布局（创建新窗口）
    await iterm2.Arrangement.async_restore(connection, "My Layout")

    # 恢复布局（作为标签加入指定窗口）
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    await iterm2.Arrangement.async_restore(
        connection,
        "My Layout",
        window_id=window.window_id
    )

    # 在特定窗口上保存/恢复布局
    await window.async_save_window_as_arrangement("Window Layout")
    await window.async_restore_window_arrangement("Window Layout")

iterm2.run_until_complete(main)
```

---

## 19. 对话框与提示

### Alert 对话框

```python
async def main(connection):
    # 简单 Alert
    alert = iterm2.Alert("标题", "这是一个提示信息")
    alert.add_button("确定")
    alert.add_button("取消")

    # 在特定窗口上显示（模态）
    app = await iterm2.async_get_app(connection)
    window = app.current_window
    alert = iterm2.Alert("确认", "是否继续？", window_id=window.window_id)
    alert.add_button("是")
    alert.add_button("否")

    button = await alert.async_run(connection)
    # 返回值：1000=第一个按钮，1001=第二个按钮，以此类推
    if button == 1000:
        print("用户点击了"是"")
    else:
        print("用户点击了"否"")

iterm2.run_until_complete(main)
```

### 文本输入对话框

```python
async def main(connection):
    alert = iterm2.TextInputAlert(
        title="输入名称",
        subtitle="请输入新的会话名称：",
        placeholder="例如：my-session",
        default_value=""
    )

    result = await alert.async_run(connection)
    if result is not None:
        print(f"用户输入: {result}")
        # 设置会话名称
        app = await iterm2.async_get_app(connection)
        session = app.current_window.current_tab.current_session
        await session.async_set_name(result)
    else:
        print("用户取消了")

iterm2.run_until_complete(main)
```

### 复合对话框（PolyModalAlert）

```python
async def main(connection):
    alert = iterm2.PolyModalAlert("设置", "配置会话选项")
    alert.add_button("应用")
    alert.add_button("取消")
    alert.add_text_field("会话名称", "")
    alert.add_checkbox_item("启用透明度", False)
    alert.add_combobox(["Solarized Dark", "Solarized Light", "Dark Background"], "Solarized Dark")

    result = await alert.async_run(connection)
    # result.button: 被点击的按钮标签
    # result.string_values: 文本框值列表
    # result.checked: 被选中的复选框标签列表
    # result.selected_option: 下拉框选中项

    if result.button == "应用":
        name = result.string_values[0] if result.string_values else ""
        use_transparency = "启用透明度" in result.checked
        preset_name = result.selected_option
        print(f"名称: {name}, 透明度: {use_transparency}, 预设: {preset_name}")

iterm2.run_until_complete(main)
```

---

## 20. 主菜单操作

```python
async def main(connection):
    # 获取菜单项状态
    state = await iterm2.MainMenu.async_get_menu_item_state(
        connection,
        "Edit Current Session..."
    )
    print(f"已选中: {state.checked}, 可用: {state.enabled}")

    # 执行菜单项（通过标识符）
    await iterm2.MainMenu.async_select_menu_item(connection, "Zoom In on Selection")
    await iterm2.MainMenu.async_select_menu_item(connection, "Clear Scrollback Buffer")

    # 常用菜单标识符示例：
    # "New Window"
    # "New Tab"
    # "Split Horizontally with Current Profile"
    # "Split Vertically with Current Profile"
    # "Close"
    # "Select Next Tab"
    # "Select Previous Tab"

iterm2.run_until_complete(main)
```

---

## 21. 偏好设置（Preferences）

```python
async def main(connection):
    # 读取偏好设置
    value = await iterm2.async_get_preference(
        connection,
        iterm2.PreferenceKey.FOCUS_FOLLOWS_MOUSE
    )
    print(f"焦点跟随鼠标: {value}")

    # 修改偏好设置
    await iterm2.async_set_preference(
        connection,
        iterm2.PreferenceKey.FOCUS_FOLLOWS_MOUSE,
        True
    )

    # 常用 PreferenceKey：
    # PreferenceKey.FOCUS_FOLLOWS_MOUSE      - 焦点跟随鼠标
    # PreferenceKey.QUIT_WHEN_ALL_WINDOWS_CLOSED - 关闭所有窗口时退出
    # PreferenceKey.METAL_ENABLED            - 启用 Metal GPU 渲染
    # PreferenceKey.THEME                    - 主题（0=深色,1=浅色,2=自动）

iterm2.run_until_complete(main)
```

---

## 22. Tmux 集成

```python
async def main(connection):
    # 获取所有活跃的 tmux 连接
    tmux_connections = await iterm2.async_get_tmux_connections(connection)

    for conn in tmux_connections:
        print(f"Tmux 连接 ID: {conn.connection_id}")
        print(f"入口会话: {conn.owning_session}")

        # 在 tmux 中创建新窗口（在 iTerm2 中显示为新标签）
        await conn.async_create_window()

        # 发送 tmux 命令
        output = await conn.async_send_command("list-sessions")
        print(f"Tmux 会话: {output}")

        # 控制 tmux 窗口可见性
        await conn.async_set_tmux_window_visible("@1", visible=True)

    # 在 tmux 会话中执行 tmux 命令
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session
    # 仅适用于 tmux integration 会话
    output = await session.async_run_tmux_command("list-windows")

iterm2.run_until_complete(main)
```

---

## 23. Toolbelt Webview 工具

```python
async def main(connection):
    # 注册自定义 Toolbelt 工具（在 Toolbelt 侧边栏中显示 Webview）
    await iterm2.async_register_web_view_tool(
        connection,
        display_name="My Dashboard",
        identifier="com.example.my-dashboard",
        reveal_if_already_registered=True,
        url="http://localhost:8080/dashboard"
    )

iterm2.run_until_complete(main)
```

---

## 24. 协程并发处理多个监控器

```python
import asyncio
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)

    async def monitor_new_sessions():
        async with iterm2.NewSessionMonitor(connection) as mon:
            while True:
                session_id = await mon.async_get()
                print(f"新会话: {session_id}")

    async def monitor_focus():
        async with iterm2.FocusMonitor(connection) as mon:
            while True:
                update = await mon.async_get_next_update()
                print(f"焦点变化: {update}")

    async def monitor_theme():
        async with iterm2.VariableMonitor(
                connection, iterm2.VariableScopes.APP, "effectiveTheme", None) as mon:
            while True:
                theme = await mon.async_get()
                print(f"主题变化: {theme}")

    # 并发运行多个监控器
    asyncio.create_task(monitor_new_sessions())
    asyncio.create_task(monitor_focus())
    asyncio.create_task(monitor_theme())

    # 永久等待
    await iterm2.async_wait_forever()

iterm2.run_forever(main)
```

---

## 25. Transaction（原子操作）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # Transaction 确保期间终端状态不变（适合读取再操作的场景）
    async with iterm2.Transaction(connection):
        line_info = await session.async_get_line_info()
        # 在 Transaction 内读取内容
        lines = await session.async_get_contents(
            line_info.overflow,
            line_info.mutable_area_height
        )

    # Transaction 外处理结果
    for line in lines:
        if "error" in line.string.lower():
            print(f"发现错误行: {line.string}")

    # 注意：某些 API 不能在 Transaction 内使用（会导致死锁）

iterm2.run_until_complete(main)
```

---

## 26. 注解（Annotations）

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 在特定位置添加注解
    start = iterm2.Point(0, 10)
    end = iterm2.Point(40, 10)
    coord_range = iterm2.CoordRange(start, end)

    await session.async_add_annotation(
        coord_range,
        "这一行有问题：内存泄漏"
    )

iterm2.run_until_complete(main)
```

---

## 27. Coprocess

```python
async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    # 获取当前 coprocess
    coprocess = await session.async_get_coprocess()
    print(f"当前 coprocess: {coprocess}")

    # 启动 coprocess（如果没有正在运行的）
    started = await session.async_run_coprocess("my-coprocess-command")
    print(f"启动成功: {started}")

    # 停止 coprocess
    stopped = await session.async_stop_coprocess()
    print(f"停止成功: {stopped}")

iterm2.run_until_complete(main)
```

---

## 常用工具函数速查

```python
# 几何类型
size = iterm2.Size(width=80, height=24)
point = iterm2.Point(x=0, y=0)
frame = iterm2.Frame(origin=point, size=size)
coord_range = iterm2.CoordRange(start=point, end=iterm2.Point(80, 5))
windowed_range = iterm2.WindowedCoordRange(coord_range)  # 或加列范围

# Color
color = iterm2.Color(r=255, g=128, b=0, a=255,
                     color_space=iterm2.ColorSpace.SRGB)

# 修饰键
iterm2.Modifier.CONTROL
iterm2.Modifier.OPTION
iterm2.Modifier.COMMAND
iterm2.Modifier.SHIFT
iterm2.Modifier.FUNCTION
iterm2.Modifier.NUMPAD

# 选择模式
iterm2.SelectionMode.CHARACTER
iterm2.SelectionMode.WORD
iterm2.SelectionMode.LINE
iterm2.SelectionMode.SMART
iterm2.SelectionMode.BOX
iterm2.SelectionMode.WHOLE_LINE

# 变量作用域
iterm2.VariableScopes.APP
iterm2.VariableScopes.SESSION
iterm2.VariableScopes.TAB
iterm2.VariableScopes.WINDOW

# 等待永远（用于 daemon 中等待事件）
await iterm2.async_wait_forever()
```

---

## 常见使用场景

### 场景一：快速为当前会话切换主题

```python
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_window.current_tab.current_session

    preset = await iterm2.ColorPreset.async_get(connection, "Solarized Dark")
    if preset:
        profile = await session.async_get_profile()
        await profile.async_set_color_preset(preset)
    print("主题已切换")

iterm2.run_until_complete(main)
```

### 场景二：创建开发工作区布局

```python
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)

    # 在现有窗口创建新标签
    window = app.current_window
    if not window:
        window = await iterm2.Window.async_create(connection)

    tab = await window.async_create_tab()

    # 获取主会话（编辑器）
    main_session = tab.current_session
    await main_session.async_set_name("Editor")
    await main_session.async_send_text("vim .\n")

    # 右侧分割：终端
    right_session = await main_session.async_split_pane(vertical=True)
    await right_session.async_set_name("Terminal")

    # 右侧再分割：日志
    log_session = await right_session.async_split_pane(vertical=False)
    await log_session.async_set_name("Logs")
    await log_session.async_send_text("tail -f /var/log/system.log\n")

    # 激活编辑器会话
    await main_session.async_activate()

iterm2.run_until_complete(main)
```

### 场景三：根据 hostname 自动切换配色

```python
import asyncio
import iterm2

COLOR_MAP = {
    "production.example.com": "Dark Background",
    "staging.example.com": "Solarized Dark",
    "localhost": "Light Background",
}

async def apply_color_for_host(connection, session):
    hostname = await session.async_get_variable("hostname")
    preset_name = COLOR_MAP.get(hostname)
    if not preset_name:
        return
    preset = await iterm2.ColorPreset.async_get(connection, preset_name)
    if preset:
        profile = await session.async_get_profile()
        await profile.async_set_color_preset(preset)

async def monitor_session(connection, session_id, app):
    session = app.get_session_by_id(session_id)
    if session:
        await apply_color_for_host(connection, session)

    async with iterm2.VariableMonitor(
            connection, iterm2.VariableScopes.SESSION,
            "hostname", session_id) as mon:
        while True:
            await mon.async_get()
            session = app.get_session_by_id(session_id)
            if session:
                await apply_color_for_host(connection, session)

async def main(connection):
    app = await iterm2.async_get_app(connection)

    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                asyncio.create_task(
                    monitor_session(connection, session.session_id, app)
                )

    async with iterm2.NewSessionMonitor(connection) as mon:
        while True:
            session_id = await mon.async_get()
            asyncio.create_task(
                monitor_session(connection, session_id, app)
            )

iterm2.run_forever(main)
```

---

## 内置示例脚本

本技能的 `scripts/` 目录下提供以下开箱即用的脚本，可直接安装到 iTerm2：

| 脚本文件 | 类型 | 说明 |
|---------|------|------|
| `dev_workspace.py` | 手动 | 创建三面板开发工作区（编辑器 + 终端 + 日志） |
| `theme_auto_switch.py` | 守护进程 | 跟随 macOS 主题自动切换 iTerm2 配色 |
| `hostname_colors.py` | 守护进程 | 根据 SSH hostname 自动切换终端配色 |
| `broadcast_input.py` | 手动 | 切换当前标签页的广播输入模式（开/关） |

**安装方式：**

```bash
# 手动执行脚本（按需运行）
cp scripts/<name>.py ~/Library/Application\ Support/iTerm2/Scripts/

# 守护进程（iTerm2 启动时自动运行）
cp scripts/<name>.py ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch/
```

安装后在 iTerm2 菜单 **Scripts** 中选择脚本运行；守护进程脚本会在 iTerm2 启动时自动加载。

---

## 如何使用此技能

当用户描述需要控制 iTerm2 的需求时，根据需求类型给出对应的 Python 脚本代码，并说明如何安装和运行。

**常见场景对应章节：**

| 用户需求 | 参考章节 |
|---------|---------|
| 创建新窗口/标签/分割面板 | 第 2、3、4 章 |
| 发送命令或文本到终端 | 第 4 章「发送文本/命令」 |
| 读取终端输出内容 | 第 5 章 |
| 修改配色/字体/透明度 | 第 6 章 |
| 设置 Color Preset | 第 6 章「应用 Color Preset」 |
| 让多个面板同步输入 | 第 7 章 |
| 监听新建/关闭会话事件 | 第 10 章 |
| 监听焦点/布局变化 | 第 9 章 |
| 注册 RPC/快捷键 | 第 14 章 |
| 自定义标签/状态栏标题 | 第 15、16 章 |
| 保存/恢复窗口布局 | 第 18 章 |

---

## 注意事项

1. **所有 `async_*` 方法必须使用 `await` 调用**，不可遗漏。
2. **`run_until_complete` vs `run_forever`**：执行完 main() 退出用前者；需要持续监听事件用后者。
3. **`LocalWriteOnlyProfile` 只改会话副本**，不修改底层全局 Profile，适合临时自定义。
4. **`Transaction` 内不能调用所有 API**，部分非同步 API 会引发死锁，仅用于读取屏幕内容等只读场景。
5. **用户变量必须以 `user.` 开头**（如 `user.myVar`），内置变量是只读的。
6. **守护进程脚本**放在 `AutoLaunch/` 目录下，随 iTerm2 启动自动运行。
7. **`asyncio.create_task()`** 用于并发运行多个监控器，避免互相阻塞。
8. **共享密钥（shared-secret）** 用于自定义控制序列，防止未经授权的代码触发操作。
9. **Shell Integration** 是 PromptMonitor、hostname 变量等功能的前提条件。
10. **`app.windows`（原 `app.terminal_windows`）** 是最新 API，`terminal_windows` 已弃用。
