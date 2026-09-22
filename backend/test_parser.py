from cdp.chrome import ChromeCDP
from parser.hanime_parser import HanimeParser


def main():
    chrome = ChromeCDP()

    html = chrome.get_html()

    parser = HanimeParser(html)

    print("页面标题:")
    print(parser.get_title())

    print()

    print("链接数量:")
    print(parser.count_links())

    print()

    print("部分链接:")

    links = parser.get_some_links()

    for item in links:
        print(item)

    print()

    print("图片:")

    images = parser.get_images()

    for img in images:
        print(img)

    print()

    print("视频卡片:")

    cards = parser.get_video_cards()

    print(f"视频卡片数量: {len(cards)}")

    print()

    for index, card in enumerate(cards, start=1):
        print(f"[{index}]")
        print(f"标题: {card.title}")
        print(f"URL: {card.url}")
        print(f"缩略图: {card.thumbnail}")
        print(f"时长: {card.duration}")
        print(f"点赞率: {card.rating}")
        print(f"观看次数: {card.views}")
        print()


if __name__ == "__main__":
    main()