import os
import sys

# 让脚本无论从哪个目录运行，都能 import 到 backend 下的 cdp / parser
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cdp.chrome import ChromeCDP


def main():
    chrome = ChromeCDP()

    print("当前页面:")
    print(chrome.get_url())
    print()

    print("当前标题:")
    print(chrome.get_title())
    print()

    html = chrome.get_html()

    print("========== 页面登录相关信息 ==========")
    print()

    keywords = [
        "715321",
        "你才是奶龙",
        "登出",
        "登出帳戶",
        "Logout",
        "logout",
        "登入",
        "登录",
        "Login",
    ]

    for keyword in keywords:
        print(f"{keyword}: {'找到' if keyword in html else '没有找到'}")

    print()
    print("HTML 长度:")
    print(len(html))

    print()
    print("========== 检查结束 ==========")


if __name__ == "__main__":
    main()