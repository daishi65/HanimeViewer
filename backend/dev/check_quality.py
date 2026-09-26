import json

import os
import sys

# 让脚本无论从哪个目录运行，都能 import 到 backend 下的 cdp / parser
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cdp.chrome import ChromeCDP


chrome = ChromeCDP()

print("当前页面 URL:")
print(chrome.get_url())
print()

script = """
(() => {
  const result = {
    video_src: null,
    video_currentSrc: null,
    sources: [],
    mp4_links: [],
    quality_texts: []
  };

  const video = document.querySelector('video');

  if (video) {
    result.video_src = video.src || null;
    result.video_currentSrc = video.currentSrc || null;

    video.querySelectorAll('source').forEach(s => {
      result.sources.push({
        src: s.src,
        type: s.type,
        label: s.getAttribute('label'),
        size: s.getAttribute('size'),
        res: s.getAttribute('res')
      });
    });
  }

  document.querySelectorAll('a[href*=".mp4"]').forEach(el => {
    result.mp4_links.push(el.href);
  });

  const seen = new Set();
  document.querySelectorAll('*').forEach(el => {
    if (el.children.length === 0) {
      const t = (el.innerText || '').trim();
      if (t.length > 0 && t.length < 30 && /\\d{3,4}p/i.test(t)) {
        seen.add(t);
      }
    }
  });
  result.quality_texts = Array.from(seen);

  return result;
})()
"""

result = chrome.evaluate(script)

print(json.dumps(result.get("value"), ensure_ascii=False, indent=2))