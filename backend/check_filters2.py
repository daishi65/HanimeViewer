import time

from cdp.chrome import ChromeCDP


chrome = ChromeCDP()


def try_filter(label, js_click_script, submit_selector):
    print("=" * 60)
    print(f"测试: {label}")
    print("=" * 60)

    # 每次回到干净状态
    chrome.navigate(
        "https://hanime1.me/search?genre=%E8%A3%8F%E7%95%AA"
    )
    time.sleep(4)

    # 执行点击
    r = chrome.evaluate(js_click_script)
    print("  点击结果:", r.get("value"))
    time.sleep(1)

    # 提交
    r = chrome.evaluate(submit_selector)
    print("  提交结果:", r.get("value"))
    time.sleep(6)

    print("  最终 URL:", chrome.get_url())
    print()


# ========== 测试 1：日期 ==========
try_filter(
    "日期：过去 1 週",
    """
    (() => {
      const btn = document.querySelector('button[data-target="#date-modal"]');
      if (!btn) return 'button not found';
      btn.click();
      return 'opened';
    })()
    """,
    """
    (() => {
      const options = document.querySelectorAll('.hentai-date-options-wrapper');
      for (const o of options) {
        if (o.getAttribute('data-value') === '過去 1 週') {
          const inner = o.querySelector('.hentai-date-options');
          if (inner) inner.click();
          return 'selected: ' + o.getAttribute('data-value');
        }
      }
      return 'option not found';
    })()
    """,
)

# ========== 测试 2：时长 ==========
try_filter(
    "时长：10 分鐘 +",
    """
    (() => {
      const btn = document.querySelector('button[data-target="#duration-modal"]');
      if (!btn) return 'button not found';
      btn.click();
      return 'opened';
    })()
    """,
    """
    (() => {
      const options = document.querySelectorAll('.hentai-duration-options-wrapper');
      for (const o of options) {
        if (o.getAttribute('data-value') === '10 分鐘 +') {
          const inner = o.querySelector('.hentai-duration-options');
          if (inner) inner.click();
          return 'selected';
        }
      }
      return 'option not found';
    })()
    """,
)

# ========== 测试 3：排序方式 ==========
try_filter(
    "排序：本日排行",
    """
    (() => {
      const btn = document.querySelector('button[data-target="#sort-modal"]');
      if (!btn) return 'button not found';
      btn.click();
      return 'opened';
    })()
    """,
    """
    (() => {
      const options = document.querySelectorAll('.hentai-sort-options-wrapper');
      for (const o of options) {
        if (o.getAttribute('data-value') === '本日排行') {
          const inner = o.querySelector('.hentai-sort-options');
          if (inner) inner.click();
          return 'selected';
        }
      }
      return 'option not found';
    })()
    """,
)

# ========== 测试 4：标签 ==========
try_filter(
    "标签：無碼 + 中文字幕",
    """
    (() => {
      const btn = document.querySelector('button[data-target="#tags"]');
      if (!btn) return 'button not found';
      btn.click();
      return 'opened';
    })()
    """,
    """
    (() => {
      const labels = document.querySelectorAll('.hentai-tags-wrapper');
      let clicked = [];
      for (const l of labels) {
        const input = l.querySelector('input[name="tags[]"]');
        if (!input) continue;
        const v = input.getAttribute('value');
        if (v === '無碼' || v === '中文字幕') {
          l.click();
          clicked.push(v);
        }
      }
      return 'clicked: ' + clicked.join(',');
    })()
    """,
)