import json
import time

from bs4 import BeautifulSoup

from cdp.chrome import ChromeCDP


chrome = ChromeCDP()

print("=" * 60)
print("诊断 1：首页栏目里的『查看更多』按钮")
print("=" * 60)

chrome.navigate("https://hanime1.me/")
time.sleep(5)

html = chrome.get_html()
soup = BeautifulSoup(html, "html.parser")

# 找所有 horizontal-row-title（含"查看更多"）
titles = soup.find_all("a", class_="horizontal-row-title")
print(f"horizontal-row-title 总数: {len(titles)}")
print()

for i, t in enumerate(titles[:3]):
    print(f"第 {i+1} 个：")
    print(f"  href = {t.get('href')!r}")
    print(f"  文本 = {t.get_text(' ', strip=True)!r}")
    print()

print("=" * 60)
print("诊断 2：首页顶部的分类导航")
print("=" * 60)

genre_wrapper = soup.find(
    "div",
    class_="home-genre-tabs-wrapper"
)

if genre_wrapper:
    print("找到 home-genre-tabs-wrapper")
    print()

    # 找所有 genre-option
    genre_options = genre_wrapper.find_all(
        class_="genre-option"
    )

    print(f"genre-option 总数: {len(genre_options)}")
    print()

    for i, opt in enumerate(genre_options[:20]):
        tag = opt.name
        cls = " ".join(opt.get("class", []))
        text = opt.get_text(" ", strip=True)
        href = opt.get("href") if tag == "a" else None
        print(
            f"  [{i+1}] <{tag} class='{cls}'> "
            f"text={text!r} href={href!r}"
        )

        # 如果 genre-option 里有子 <a>，也打印
        a_child = opt.find("a")
        if a_child:
            print(
                f"        子 <a>: "
                f"href={a_child.get('href')!r} "
                f"text={a_child.get_text(' ', strip=True)!r}"
            )
else:
    print("没有找到 home-genre-tabs-wrapper")