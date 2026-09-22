import time

from cdp.chrome import ChromeCDP
from parser.hanime_parser import HanimeParser


def main():
    chrome = ChromeCDP()

    url = "https://hanime1.me/search?query=nmf"

    print("准备打开:")
    print(url)

    chrome.navigate(url)

    print()
    print("等待页面加载...")

    time.sleep(5)

    print("页面加载完成")
    print()

    print("当前页面 URL:")
    print(chrome.get_url())
    print()

    print("当前页面标题:")
    print(chrome.get_title())
    print()

    html = chrome.get_html()

    print("HTML 长度:")
    print(len(html))
    print()

    parser = HanimeParser(html)

    cards = parser.get_video_cards()

    print("视频卡片数量:")
    print(len(cards))
    print()

    print("========== 搜索结果 ==========")

    for index, card in enumerate(cards, start=1):
        print()
        print(f"[{index}]")
        print(f"标题: {card.title}")
        print(f"URL: {card.url}")
        print(f"缩略图: {card.thumbnail}")
        print(f"时长: {card.duration}")
        print(f"点赞率: {card.rating}")
        print(f"观看次数: {card.views}")

    print()
    print("========== 测试结束 ==========")


if __name__ == "__main__":
    main()