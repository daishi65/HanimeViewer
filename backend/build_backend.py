"""把后端打包成一个独立的 exe。

用法（在项目根目录）：

    .venv\\Scripts\\python.exe backend\\build_backend.py

产物：

    backend\\dist\\hanime_backend.exe

注意
----
PyInstaller 不会自动把 uvicorn 的动态导入（`main:app` 那种字符串形式）
和 `websocket-client` 之类一起带上，所以这里用 `--hidden-import` 明确列出，
否则打出来的 exe 一运行就报 ModuleNotFoundError。

另外 `--collect-all` 用于 uvicorn：它内部有按字符串加载模块的逻辑。
"""

import os
import shutil
import subprocess
import sys


BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
DIST_DIR = os.path.join(BACKEND_DIR, "dist")
BUILD_DIR = os.path.join(BACKEND_DIR, "build_pyi")
SPEC_DIR = os.path.join(BACKEND_DIR, "build_pyi")

# 这些是运行时靠字符串导入、或者第三方需要带数据的包
HIDDEN_IMPORTS = [
    "uvicorn",
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "websocket",
    "websocket._abnf",
    "requests",
    "bs4",
    "opencc",
    "main",
    "browser",
    "auth",
    "cache",
]

# 我们自己的包，必须整体收集（PyInstaller 静态分析看不到字符串导入）
COLLECT_SUBMODULES = [
    "cdp",
    "parser",
]


def main():
    try:
        import PyInstaller  # noqa: F401
    except ImportError:
        print("缺少 PyInstaller，先安装：")
        print(f"  {sys.executable} -m pip install pyinstaller")
        return 1

    # 清掉旧产物，避免把过期文件当成结果
    for path in (DIST_DIR, BUILD_DIR):
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)

    args = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        # 单个文件，双击/被 App 拉起都方便
        "--onefile",
        # 不要弹控制台窗口？这里保留控制台，
        # 方便出问题时能看到后端日志。
        "--console",
        "--name",
        "hanime_backend",
        "--distpath",
        DIST_DIR,
        "--workpath",
        BUILD_DIR,
        "--specpath",
        SPEC_DIR,
        # 保证能 import 到 cdp / parser / main
        "--paths",
        BACKEND_DIR,
    ]

    for name in HIDDEN_IMPORTS:
        args += ["--hidden-import", name]

    for package in COLLECT_SUBMODULES:
        args += ["--collect-submodules", package]

    args.append(os.path.join(BACKEND_DIR, "run_backend.py"))

    print("执行：")
    print("  " + " ".join(args))
    print()

    result = subprocess.run(args, cwd=BACKEND_DIR)

    if result.returncode != 0:
        print("\n打包失败。")
        return result.returncode

    exe = os.path.join(DIST_DIR, "hanime_backend.exe")

    if not os.path.isfile(exe):
        print(f"\n打包结束但找不到产物：{exe}")
        return 1

    size_mb = os.path.getsize(exe) / (1024 * 1024)

    print(f"\n打包成功：{exe}")
    print(f"体积：{size_mb:.1f} MB")
    print("\n接下来运行 frontend/scripts/package_windows.ps1 "
          "生成完整的发布目录。")

    return 0


if __name__ == "__main__":
    sys.exit(main())
