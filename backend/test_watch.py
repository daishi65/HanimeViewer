import time

from cdp.chrome import ChromeCDP
from parser.hanime_parser import HanimeParser


def main():
    chrome = ChromeCDP()

    url = "https://hanime1.me/watch?v=408328"

    print("准备打开:")
    print(url)

    chrome.navigate(url)

    print()
    print("等待页面加载...")

    time.sleep(5)

    print("页面加载完成")
    print()

    html = chrome.get_html()

    parser = HanimeParser(html)

    detail = parser.get_video_detail()

    print("========== 视频详情 ==========")
    print()

    print("标题:")
    print(detail.title)
    print()

    print("视频页面 URL:")
    print(detail.url)
    print()

    print("视频地址:")
    print(detail.video_source)
    print()

    print("缩略图:")
    print(detail.thumbnail)
    print()

    print("品牌:")
    print(detail.brand)
    print()

    print("发行日期:")
    print(detail.release_date)
    print()

    print("文件大小:")
    print(detail.file_size)
    print()

    print("标签:")
    print(detail.tags)
    print()

    print("========== 测试结束 ==========")


if __name__ == "__main__":
    main()