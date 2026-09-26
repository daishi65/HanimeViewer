import time

import os
import sys

# 让脚本无论从哪个目录运行，都能 import 到 backend 下的 cdp / parser
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cdp.chrome import ChromeCDP


chrome = ChromeCDP()


def test_tags(label, tags, broad):
    print("=" * 60)
    print(f"测试: {label}")
    print("=" * 60)

    chrome.navigate(
        "https://hanime1.me/search?genre=%E8%A3%8F%E7%95%AA"
    )
    time.sleep(4)

    # 打开标签弹窗
    r = chrome.evaluate("""
    (() => {
      const btn = document.querySelector('button[data-target="#tags"]');
      if (!btn) return 'tags button not found';
      btn.click();
      return 'opened';
    })()
    """)
    print("  打开标签弹窗:", r.get("value"))
    time.sleep(1)

    # 点击指定的标签
    tags_json = str(tags).replace("'", '"')

    r = chrome.evaluate(f"""
    (() => {{
      const targets = {tags_json};
      const labels = document.querySelectorAll('.hentai-tags-wrapper');
      let clicked = [];
      for (const l of labels) {{
        const input = l.querySelector('input[name="tags[]"]');
        if (!input) continue;
        const v = input.getAttribute('value');
        if (targets.includes(v)) {{
          l.click();
          clicked.push(v);
        }}
      }}
      return 'clicked: ' + clicked.join(',');
    }})()
    """)
    print("  点击标签:", r.get("value"))

    # 广泛匹配
    if broad:
        r = chrome.evaluate("""
        (() => {
          const input = document.getElementById('broad');
          if (!input) return 'broad input not found';
          if (!input.checked) input.click();
          return 'broad checked: ' + input.checked;
        })()
        """)
        print("  广泛匹配:", r.get("value"))

    time.sleep(1)

    # 点击标签弹窗的提交按钮
    r = chrome.evaluate("""
    (() => {
      const modal = document.getElementById('tags');
      if (!modal) return 'tags modal not found';
      const btn = modal.querySelector('button[type="submit"]');
      if (!btn) return 'submit not found';
      btn.click();
      return 'submitted';
    })()
    """)
    print("  提交:", r.get("value"))

    time.sleep(6)

    print("  最终 URL:", chrome.get_url())
    print()


# 测试 1：单标签
test_tags("单标签：無碼", ["無碼"], False)

# 测试 2：两个标签
test_tags("两个标签：無碼 + 中文字幕", ["無碼", "中文字幕"], False)

# 测试 3：两个标签 + 广泛匹配
test_tags("两个标签 + 广泛匹配", ["無碼", "中文字幕"], True)