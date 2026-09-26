import time

import os
import sys

# 让脚本无论从哪个目录运行，都能 import 到 backend 下的 cdp / parser
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cdp.chrome import ChromeCDP
from bs4 import BeautifulSoup
from parser.hanime_parser import HanimeParser


BASE_URL = "https://hanime1.me/user/715321/playlists"


def parse_playlists(html):
    parser = HanimeParser(html)
    return parser.get_playlists()
    soup = BeautifulSoup(html, "html.parser")

    results = []

    for link in soup.find_all("a"):
        href = link.get("href")
        text = link.get_text(" ", strip=True)

        if not href:
            continue

        if not href.startswith("https://hanime1.me/playlist?list="):
            continue

        if "部影片" not in text:
            continue

        # 去掉播放图标文字
        name = text.replace("playlist_play", "", 1).strip()

        count = ""
        if "部影片" in name:
            count, name = name.split("部影片", 1)
            count = count.strip()
            name = name.strip()

        results.append({
            "name": name,
            "video_count": count,
            "url": href
        })

    return results


def get_total_pages(html):
    soup = BeautifulSoup(html, "html.parser")

    pages = []

    for link in soup.find_all("a"):
        href = link.get("href", "")
        text = link.get_text(strip=True)

        if "page=" not in href:
            continue

        try:
            page = int(href.split("page=", 1)[1].split("&", 1)[0])
            pages.append(page)
        except ValueError:
            continue

    if not pages:
        return 1

    return max(pages)


def main():
    chrome = ChromeCDP()

    all_playlists = []

    # 先打开第一页，取得实际总页数
    print("打开第一页:")
    print(BASE_URL)
    print()

    chrome.navigate(BASE_URL)

    print("等待页面加载...")
    time.sleep(5)

    html = chrome.get_html()

    total_pages = get_total_pages(html)

    print("检测到播放清单页数:")
    print(total_pages)
    print()

    # 遍历所有页面
    for page in range(1, total_pages + 1):
        if page == 1:
            url = BASE_URL
        else:
            url = f"{BASE_URL}?page={page}"

        print("=" * 60)
        print(f"正在读取第 {page} / {total_pages} 页")
        print(url)
        print("=" * 60)

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(3)

        html = chrome.get_html()

        playlists = parse_playlists(html)

        print(f"本页播放清单数量: {len(playlists)}")

        all_playlists.extend(playlists)

        print()

    print("=" * 60)
    print("全部播放清单")
    print("=" * 60)

    print(f"总数量: {len(all_playlists)}")
    print()

    for index, playlist in enumerate(all_playlists, start=1):
        print(f"[{index}]")
        print(f"名称: {playlist['name']}")
        print(f"影片数量: {playlist['video_count']}")
        print(f"URL: {playlist['url']}")
        print()


if __name__ == "__main__":
    main()