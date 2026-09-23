import time
from collections import Counter

from bs4 import BeautifulSoup

from cdp.chrome import ChromeCDP


chrome = ChromeCDP()

print("准备打开首页...")
chrome.navigate("https://hanime1.me/")
time.sleep(5)

html = chrome.get_html()
print("HTML 长度:", len(html))
print()

soup = BeautifulSoup(html, "html.parser")

# 找所有 video-link
cards = soup.find_all("a", class_="video-link")
print("video-link 总数:", len(cards))
print()

# 第一个 video-link 的父级链
if cards:
    print("=" * 50)
    print("第一个 video-link 的父级链（向上 8 层）：")
    print("=" * 50)

    parent = cards[0]
    for i in range(8):
        parent = parent.parent
        if parent is None:
            break

        cls = parent.get("class", [])
        cls_str = " ".join(cls) if isinstance(cls, list) else str(cls)

        print(
            f"第 {i + 1} 层: <{parent.name} "
            f"class='{cls_str}'> "
            f"子元素数={len(parent.find_all(recursive=False))}"
        )
print()

# 找"最新上市"这段文字，向上看父级链
print("=" * 50)
print("搜索包含 '最新' 的元素：")
print("=" * 50)

found = False
for el in soup.find_all(string=True):
    text = el.strip()
    if "最新" in text and len(text) < 30:
        print(f"找到文字: {text!r}")
        parent = el.parent
        for i in range(6):
            if parent is None:
                break
            cls = parent.get("class", [])
            cls_str = " ".join(cls) if isinstance(cls, list) else str(cls)
            print(
                f"  上级 {i + 1}: <{parent.name} class='{cls_str}'> "
                f"子元素数={len(parent.find_all(recursive=False))}"
            )
            parent = parent.parent
        print()
        found = True
        break

if not found:
    print("没有找到包含 '最新' 的文字")
print()

# 统计所有 class 名出现次数
print("=" * 50)
print("出现次数 >= 3 的 class 名（降序）：")
print("=" * 50)

all_classes = Counter()
for el in soup.find_all(class_=True):
    classes = el.get("class", [])
    if isinstance(classes, list):
        for c in classes:
            all_classes[c] += 1
    else:
        all_classes[classes] += 1

for cls, count in all_classes.most_common():
    if count >= 3:
        print(f"  {cls}: {count}")