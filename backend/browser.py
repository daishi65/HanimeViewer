"""自己把调试用 Chrome 拉起来。

为什么要这一步
--------------
这个项目的数据全部来自「真实 Chrome + CDP」，因为直接 HTTP 请求
hanime1.me 只会拿到一个 200 但内容为空的 JS 挑战页（实测约 20KB，
没有 .video-link、没有 <video>）。

以前的用法要求用户自己先手动开一个带 --remote-debugging-port 的 Chrome，
再手动起 uvicorn。这个模块负责把 Chrome 这一段自动化掉。

关键点
------
使用**独立的 user-data-dir**：
- 不会干扰用户日常使用的 Chrome
- 即使用户的 Chrome 已经开着，也能可靠占住调试端口
  （共用默认 profile 时，已运行的 Chrome 会直接把新进程合并进去，
   调试端口根本不会开启 —— 这是最常见的失败原因）
- 登录 cookie 保存在这个专用 profile 里，下次启动仍然有效
"""

import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.request


# 常见的 Chrome 安装位置
_CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    os.path.expandvars(
        r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
    ),
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


def find_browser():
    """找一个可用的 Chromium 内核浏览器。找不到返回 None。"""
    # 1. 环境变量优先（方便用户自己指定）
    override = os.environ.get("HANIME_BROWSER", "").strip()

    if override and os.path.isfile(override):
        return override

    # 2. 常见安装路径
    for path in _CHROME_CANDIDATES:
        if path and os.path.isfile(path):
            return path

    # 3. PATH 里找
    for name in ("chrome.exe", "chrome", "msedge.exe", "chromium.exe"):
        found = shutil.which(name)

        if found:
            return found

    return None


def default_profile_dir():
    """专用浏览器配置目录（跟随 app 数据目录）。"""
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")

    return os.path.join(base, "HanimeViewer", "chrome-profile")


def is_cdp_alive(port, timeout=1.5):
    """调试端口是否已经可用。"""
    try:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{port}/json/version",
            timeout=timeout,
        ) as response:
            data = json.loads(response.read().decode("utf-8"))

            return bool(data.get("webSocketDebuggerUrl"))
    except Exception:
        return False


def _iter_browser_pids():
    """当前所有 chrome/msedge 进程的 pid。"""
    try:
        import subprocess as _sp

        # tasklist 比遍历 psutil 更省依赖（项目里没有 psutil）
        output = _sp.run(
            ["tasklist", "/FO", "CSV", "/NH"],
            capture_output=True,
            text=True,
            creationflags=getattr(_sp, "CREATE_NO_WINDOW", 0),
        ).stdout
    except Exception:
        return set()

    pids = set()

    for line in output.splitlines():
        parts = [p.strip('"') for p in line.split('","')]

        if len(parts) < 2:
            continue

        name = parts[0].strip('"').lower()

        if name in ("chrome.exe", "msedge.exe"):
            try:
                pids.add(int(parts[1]))
            except ValueError:
                continue

    return pids


def _hide_windows_of(pids):
    """把这些进程的顶层窗口隐藏掉（不进任务栏、不抢焦点）。

    只做到「窗口移到屏幕外」是不够的：那样任务栏里还是会多出一个图标。
    这里用 Win32 的 ShowWindow(SW_HIDE) 把窗口真正藏起来。

    失败也没关系：调用方已经用 --window-position 把窗口放到屏幕外了，
    最差情况只是任务栏多一个图标，功能不受影响。
    """
    if os.name != "nt":
        return 0

    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32

        SW_HIDE = 0
        GW_OWNER = 4

        EnumWindowsProc = ctypes.WINFUNCTYPE(
            wintypes.BOOL,
            wintypes.HWND,
            wintypes.LPARAM,
        )

        hidden = 0

        def callback(hwnd, _lparam):
            nonlocal hidden

            pid = wintypes.DWORD()
            user32.GetWindowThreadProcessId(
                hwnd, ctypes.byref(pid)
            )

            if pid.value not in pids:
                return True

            # 只处理顶层窗口（有 owner 的通常是工具窗口，跳过）
            if user32.GetWindow(hwnd, GW_OWNER):
                return True

            if not user32.IsWindowVisible(hwnd):
                return True

            user32.ShowWindow(hwnd, SW_HIDE)
            hidden += 1

            return True

        user32.EnumWindows(
            EnumWindowsProc(callback), 0
        )

        return hidden
    except Exception:
        return 0


def hide_all_browser_windows(wait_seconds=6.0, interval=0.5):
    """把所有 chrome/msedge 窗口藏起来。

    可以在任何时候重复调用（幂等）。
    用于两种情况：
    - 启动浏览器时窗口还没创建出来，需要过一会儿再藏
    - 浏览器已经在跑（复用的情况），也要确保它是隐藏的
    """
    if os.name != "nt":
        return 0

    hidden = 0
    deadline = time.monotonic() + wait_seconds

    while time.monotonic() < deadline:
        hidden += _hide_windows_of(_iter_browser_pids())

        time.sleep(interval)

    return hidden


def ensure_browser(
    port=9222,
    profile_dir=None,
    start_url="https://hanime1.me/",
    wait_seconds=25.0,
    hide_window=True,
):
    """确保有一个带调试端口的浏览器在跑。

    返回 (是否就绪, 说明信息, 浏览器路径)。

    已经在跑就直接复用，不会重复启动（但会确保窗口是隐藏的）。
    """
    if is_cdp_alive(port):
        if hide_window:
            # 复用时也要保证窗口不可见：可能是上次启动后
            # 窗口才被创建出来，或者用户手动把窗口显示回来了
            hide_all_browser_windows(wait_seconds=2.0)

        return True, "调试浏览器已在运行，直接复用", ""

    browser = find_browser()

    if not browser:
        return (
            False,
            "找不到 Chrome 或 Edge。请安装 Chrome，"
            "或用环境变量 HANIME_BROWSER 指定浏览器路径。",
            "",
        )

    profile_dir = profile_dir or default_profile_dir()

    os.makedirs(profile_dir, exist_ok=True)

    # 记下启动前的浏览器进程，稍后用来找出我们新起的那个
    pids_before = _iter_browser_pids() if hide_window else set()

    args = [
        browser,
        f"--remote-debugging-port={port}",
        f"--user-data-dir={profile_dir}",
        # 首次启动的引导页会干扰，关掉
        "--no-first-run",
        "--no-default-browser-check",
        # 别让「恢复上次会话」的弹窗挡住页面
        "--disable-features=Translate,InfiniteSessionRestore",
        "--disable-session-crashed-bubble",
        # 把窗口丢到屏幕外，用户完全看不到。
        #
        # 为什么不直接用无头模式（--headless）：
        # 实测 headless Chrome 打开 hanime1.me 会被 Cloudflare 拦成
        # "Attention Required!"，拿不到任何内容 ——
        # 本项目的核心原理就是「用真实的、能过 Cloudflare 的浏览器」，
        # 去掉有头模式等于把这个原理也去掉。
        # 所以这里保留真实浏览器内核，只是让它不出现在屏幕上。
        "--window-position=-32000,-32000",
        "--window-size=1280,900",
        start_url,
    ]

    try:
        subprocess.Popen(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            # 不要跟着后端一起被杀掉：用户可能想继续用这个窗口
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
        )
    except Exception as exc:
        return False, f"启动浏览器失败：{exc}", browser

    # 等调试端口就绪；顺便把新出现的浏览器窗口藏起来
    deadline = time.monotonic() + wait_seconds
    hidden_total = 0

    while time.monotonic() < deadline:
        if hide_window:
            new_pids = _iter_browser_pids() - pids_before

            if new_pids:
                hidden_total += _hide_windows_of(new_pids)

        if is_cdp_alive(port):
            if hide_window:
                # 窗口往往比调试端口晚一步创建，所以这里再多藏一会儿
                hide_all_browser_windows(wait_seconds=3.0)

            return True, "调试浏览器已启动（窗口已隐藏）", browser

        time.sleep(0.4)

    return (
        False,
        f"浏览器已启动，但 {wait_seconds:.0f} 秒内没有开放调试端口 {port}。"
        "可能是该端口被占用，或安全软件拦截了。",
        browser,
    )


def _browser_pids_with_profile():
    """命令行里带我们专用配置目录的 chrome/msedge 进程。"""
    try:
        import subprocess as _sp

        output = _sp.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "Get-CimInstance Win32_Process "
                "-Filter \"Name='chrome.exe' or Name='msedge.exe'\" "
                "| Where-Object { $_.CommandLine -like '*HanimeViewer*' } "
                "| Select-Object -ExpandProperty ProcessId",
            ],
            capture_output=True,
            text=True,
            creationflags=getattr(_sp, "CREATE_NO_WINDOW", 0),
        ).stdout
    except Exception:
        return []

    return [p.strip() for p in output.split() if p.strip().isdigit()]


def stop_browser(port, timeout=15.0):
    """结束我们自己启动的调试浏览器，并**等它真的退干净**。

    这个浏览器是 App 拉起来的、而且窗口是隐藏的，
    用户看不到也就没法自己关，所以 App 退出时要负责收掉它 ——
    否则会留下一堆看不见的 chrome.exe 白占内存。

    为什么要等：taskkill 只是「发出」结束请求，进程要过一会儿才真的消失。
    之前这里发完就返回，调用方紧接着 os._exit(0)，
    结果浏览器还没退完，留下 13 个 chrome 进程（实测）。
    所以这里必须轮询确认进程已经消失。

    只关**使用我们专用配置目录**的实例，不会动用户日常的 Chrome。
    """
    if not is_cdp_alive(port) and not _browser_pids_with_profile():
        return False

    if os.name != "nt":
        return False

    import subprocess as _sp

    killed = False
    deadline = time.monotonic() + timeout

    while time.monotonic() < deadline:
        pids = _browser_pids_with_profile()

        if not pids:
            # 全退干净了
            return killed

        for pid in pids:
            try:
                _sp.run(
                    ["taskkill", "/PID", pid, "/T", "/F"],
                    capture_output=True,
                    creationflags=getattr(_sp, "CREATE_NO_WINDOW", 0),
                )
                killed = True
            except Exception:
                pass

        time.sleep(0.5)

    # 超时也把最后状态说清楚
    return killed
