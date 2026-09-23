import time
from urllib.parse import quote

from bs4 import BeautifulSoup

from cdp.chrome import ChromeCDP


chrome = ChromeCDP()

# 测试用例：每项 (描述, URL)
tests = [
    (
        "排序=本日排行",
        "https://hanime1.me/search?genre=裏番&sort=本日排行",
    ),
    (
        "时长=10 分鐘 +",
        "https://hanime1.me/search?genre=裏番&duration=10 分鐘 +",
    ),
    (
        "日期=過去 1 週",
        "https://hanime1.me/search?genre=裏番&date=過去 1 週",
    ),
    (
        "年月=2024 年 1 月",
        "https://hanime1.me/search?genre=裏番&year=2024&month=1",
    ),
    (
        "标签=無碼",
        "https://hanime1.me/search?genre=裏番&tags[]=無碼",
    ),
    (
        "标签=無碼 + 中文字幕",
        "https://hanime1.me/search?genre=裏番&tags[]=無碼&tags[]=中文字幕",
    ),
    (
        "广泛匹配",
        "https://hanime1.me/search?genre=裏番&tags[]=無碼&tags[]=中文字幕&broad=on",
    ),
]

for i, (label, url) in enumerate(tests):
    print("=" * 60)
    print(f"测试 [{i+1}/{len(tests)}]: {label}")
    print(f"URL: {url}")
    print("=" * 60)

    try:
        # 用 quote 手动编码中文，避免 requests 报错
        encoded_url = quote(url, safe=":/?=&")

        chrome.navigate(encoded_url)
        time.sleep(4)

        html = chrome.get_html()
        soup = BeautifulSoup(html, "html.parser")

        # 提取视频数量
        watch_links = soup.find_all(
            "a",
            href=lambda h: h and "hanime1.me/watch?" in h
        )

        # 提取页面标题
        title = soup.title.get_text(strip=True) if soup.title else ""

        # 提取页面上显示的当前筛选状态
        # 从 URL 的 title 里看不出，看是否有"没有找到"之类的提示
        no_result = "沒有找到" in html or "没有找到" in html

        print(f"  当前 URL: {chrome.get_url()}")
        print(f"  页面标题: {title}")
        print(f"  视频数量: {len(watch_links)}")
        print(f"  无结果提示: {no_result}")
        print()

    except Exception as e:
        print(f"  错误: {e}")
        print()