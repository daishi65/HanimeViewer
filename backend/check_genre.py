import time

from bs4 import BeautifulSoup

from cdp.chrome import ChromeCDP


chrome = ChromeCDP()

url = "https://hanime1.me/search?genre=裏番"

print("准备打开:", url)
chrome.navigate(url)
time.sleep(5)

html = chrome.get_html()
soup = BeautifulSoup(html, "html.parser")

# 找所有 watch 链接
watch_links = soup.find_all(
    "a",
    href=lambda h: h and "hanime1.me/watch?" in h
)

print("=" * 60)
print(f"watch 链接总数: {len(watch_links)}")
print("=" * 60)
print()

# dump 第一个 watch 链接的完整父级结构
if watch_links:
    a = watch_links[0]

    print("=" * 60)
    print("第一个 watch 链接本身的 HTML：")
    print("=" * 60)
    print(a.prettify())
    print()

    print("=" * 60)
    print("第一个 watch 链接的父级链（向上 5 层）：")
    print("=" * 60)

    parent = a.parent
    for i in range(5):
        if parent is None:
            break
        cls = " ".join(parent.get("class", [])) if parent.get("class") else ""
        print(f"  第 {i+1} 层: <{parent.name} class='{cls}'>")
        parent = parent.parent

    print()

    # 找最上层的视频卡片容器，dump 它的完整 HTML
    card = a
    while card.parent and card.parent != soup:
        parent_cls = card.parent.get("class", [])
        # 如果父级有 video-card-inner 或类似容器类名，停下
        if "video-card-inner" in parent_cls:
            card = card.parent
            break
        if "home-rows-videos-div" in parent_cls:
            card = card.parent
            break
        if "search-videos" in parent_cls:
            card = card.parent
            break
        card = card.parent

    print("=" * 60)
    print("最外层视频卡片的完整 HTML：")
    print("=" * 60)
    print(card.prettify())
    print()

    # 再找找 search-videos 是什么
    print("=" * 60)
    print("查找 search-videos：")
    print("=" * 60)

    sv = soup.find_all("div", class_="search-videos")
    print(f"search-videos 总数: {len(sv)}")

    if sv:
        print()
        print("第一个 search-videos 的完整 HTML（前 80 行）：")
        print()

        lines = sv[0].prettify().split("\n")
        for line in lines[:80]:
            print(line)