"""打包后的后端入口。

PyInstaller 从这里启动，负责：
1. 解析命令行参数（端口、CDP 端口）
2. 把调试浏览器拉起来（这样用户不用自己去开 Chrome）
3. 启动 uvicorn

打包命令见 backend/build_backend.py。
"""

import argparse
import os
import sys
import threading
import time


def force_utf8_output():
    """把标准输出/错误切到 UTF-8。

    这一步是**必须的**：Windows 控制台的默认编码是 GBK（cp936），
    而 main.py 里有大量 print 会输出中文/日文标题。
    一旦某个标题里出现 GBK 编不了的字符（例如「・」U+30FB），
    print 会直接抛 UnicodeEncodeError，
    整个接口就变成 500 —— 实测 16 次请求里挂了 14 次。
    """
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)

        if stream is None:
            continue

        try:
            stream.reconfigure(
                encoding="utf-8",
                errors="replace",
            )
        except Exception:
            # 某些环境下 reconfigure 不可用（例如被重定向成别的对象），
            # 退化成包一层 wrapper。
            try:
                import io

                setattr(
                    sys,
                    stream_name,
                    io.TextIOWrapper(
                        stream.buffer,
                        encoding="utf-8",
                        errors="replace",
                        line_buffering=True,
                    ),
                )
            except Exception:
                pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="HanimeViewer backend launcher"
    )

    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="后端监听端口（默认 8000）",
    )

    parser.add_argument(
        "--cdp-port",
        type=int,
        default=9222,
        help="调试浏览器端口（默认 9222）",
    )

    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="不要自动启动浏览器",
    )

    return parser.parse_args()


def main():
    # 必须在任何 print / uvicorn 日志之前调用
    force_utf8_output()

    args = parse_args()

    # 这些是 cdp/chrome.py 读取的，必须在 import main 之前设好
    os.environ["HANIME_CDP_PORT"] = str(args.cdp_port)

    # PyInstaller 打包后，工作目录可能不是 exe 所在目录，
    # 而 main / cdp / parser 都是以包的形式打进去的，
    # 所以这里把 _MEIPASS 加进 sys.path。
    if getattr(sys, "frozen", False):
        base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))

        if base not in sys.path:
            sys.path.insert(0, base)

    if not args.no_browser:
        try:
            import browser

            def warm_up():
                # 放到后台线程：浏览器启动可能要几秒，
                # 不要卡住后端对外提供服务（客户端会轮询 /api/status）。
                time.sleep(0.5)

                ok, message, _path = browser.ensure_browser(
                    port=args.cdp_port
                )

                print(f"[browser] {message}", flush=True)

                if not ok:
                    print(
                        "[browser] 浏览器不可用，"
                        "客户端会在启动页提示。",
                        flush=True,
                    )

            threading.Thread(
                target=warm_up,
                daemon=True,
            ).start()
        except Exception as exc:
            print(f"[browser] 启动浏览器失败：{exc}", flush=True)

    import uvicorn

    # /api/shutdown 定义在 main.py 里（这样用 uvicorn main:app 直接跑也有），
    # 这里不再重复注册。
    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=args.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
