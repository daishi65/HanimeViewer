import os
import sys

# 让脚本无论从哪个目录运行，都能 import 到 backend 下的 cdp / parser
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cdp.chrome import ChromeCDP


def main():

    chrome = ChromeCDP()

    print("标题:")
    print(chrome.get_title())

    print()

    print("网址:")
    print(chrome.get_url())

    print()

    html = chrome.get_html()

    print("HTML长度:")
    print(len(html))


if __name__ == "__main__":
    main()