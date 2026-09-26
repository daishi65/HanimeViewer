"""简单的内存 TTL 缓存。

HanimeViewer 的每次数据请求都要经过「真实 Chrome → CDP → 解析 HTML」，
一次大约 3~5 秒。同一个页面在短时间内被反复请求时（启动、切页面、来回导航），
没必要每次都重新走一遍。这里用一个进程内字典缓存结果。

注意：
- 只是内存缓存，后端重启就清空，这是刻意设计（避免留下过期数据）。
- 线程安全（uvicorn 的同步接口跑在线程池里）。
- 缓存的是**解析后的结果**，不是 HTML，省掉重复解析。
"""

import threading
import time


class TTLCache:
    def __init__(self, ttl=300, maxsize=200):
        self.ttl = ttl
        self.maxsize = maxsize
        self._store = {}
        self._lock = threading.Lock()
        self.hits = 0
        self.misses = 0

    def get(self, key):
        now = time.monotonic()

        with self._lock:
            entry = self._store.get(key)

            if entry is None:
                self.misses += 1
                return None

            expire_at, value = entry

            if now >= expire_at:
                # 过期了，顺手清掉
                self._store.pop(key, None)
                self.misses += 1
                return None

            self.hits += 1
            return value

    def set(self, key, value):
        with self._lock:
            # 超出上限就丢掉最早过期的那些，避免无限增长
            if len(self._store) >= self.maxsize:
                self._prune_locked()

            self._store[key] = (time.monotonic() + self.ttl, value)

    def _prune_locked(self):
        if not self._store:
            return

        # 先删已过期的
        now = time.monotonic()
        expired = [
            key
            for key, (expire_at, _) in self._store.items()
            if now >= expire_at
        ]

        for key in expired:
            self._store.pop(key, None)

        if len(self._store) < self.maxsize:
            return

        # 还是太满，就按过期时间排序，删掉最旧的 1/4
        ordered = sorted(
            self._store.items(),
            key=lambda item: item[1][0]
        )

        for key, _ in ordered[: max(1, len(ordered) // 4)]:
            self._store.pop(key, None)

    def clear(self):
        with self._lock:
            self._store.clear()

    def stats(self):
        with self._lock:
            return {
                "entries": len(self._store),
                "hits": self.hits,
                "misses": self.misses,
                "ttl": self.ttl,
            }


# 首页栏目：变化不频繁，缓存久一点
home_cache = TTLCache(ttl=600)

# 搜索/筛选结果：翻页内容相对稳定，中等 TTL
search_cache = TTLCache(ttl=300)

# 视频详情（含播放地址）：
# 注意里面的视频直链带 secure 签名和过期时间，TTL 不能太长，
# 否则用户点播放会拿到失效的地址。
detail_cache = TTLCache(ttl=180)

# 标签分组：基本不变，缓存最久
tags_cache = TTLCache(ttl=1800)

# 播放清单列表：中等
playlist_cache = TTLCache(ttl=300)

# 用户/发行商主页：中等
user_cache = TTLCache(ttl=300)
