import time
import os
import threading

from fastapi import FastAPI, HTTPException

from cache import (
    detail_cache,
    home_cache,
    playlist_cache,
    search_cache,
    tags_cache,
    user_cache,
)
from cdp.chrome import (
    ChromeCDP,
    _NAVIGATE_LOCK,
)
import cdp.chrome as cdp
from parser.hanime_parser import HanimeParser
from opencc import OpenCC

import auth


app = FastAPI(
    title="HanimeViewer API",
    version="1.0.0"
)


# ==========================================================
# 统一的「取页面 + 解析」入口
# ==========================================================
#
# 旧的写法在每个接口里重复这一套：
#
#     chrome = ChromeCDP()
#     chrome.navigate(url)
#     time.sleep(5)
#     html = chrome.get_html()
#     parser = HanimeParser(html)
#
# 有两个问题：
#
# 1. 每次固定等 5 秒。实测首页要 5.1 秒才加载完，也就是说固定 5 秒
#    有时候是「提前」取到半成品；而搜索页只要 3.2 秒，又白等了 2 秒。
#    现在改成轮询等待真正的目标元素出现。
#
# 2. 完全没有缓存。同一个页面来回切换就反复重新加载。
#    现在按 URL 缓存解析结果，短时间内的重复请求立即返回。
#
# 另外：整个「导航 -> 等就绪 -> 取 HTML -> 解析」都持有 _NAVIGATE_LOCK。
# 因为所有请求共用同一个 Chrome 标签页，如果解析期间别的请求把页面导航走了，
# 就会解析到错误的页面内容。

# 列表类页面（首页 / 搜索 / 筛选 / 播放清单）都有的元素
LIST_READY_SELECTOR = "a.video-link"

# 视频详情页需要的**全部**元素。
#
# 为什么不是只等一个：#video-artist-name 会比 <video>、简介面板和
# 相关影片区更早出现，只等它就可能在页面画了一半时取走 HTML，
# 结果 sources / related 全是空 —— 这正是之前
# 「有些视频进详情页后底下没有相关影片」的原因。
DETAIL_READY_SELECTORS = [
    "#video-artist-name",
    "video",
    ".video-description-panel",
    "#related-tabcontent",
]

# 兼容旧写法
DETAIL_READY_SELECTOR = DETAIL_READY_SELECTORS[0]


def fetch_html(
    url,
    ready_selector="",
    all_selectors=None,
    cache=None,
    timeout=20.0,
    min_stable=0.5,
):
    """取指定 URL 的 HTML。命中缓存时直接返回，不再访问 Chrome。

    返回 (html, from_cache)。
    """
    if cache is not None:
        cached = cache.get(url)

        if cached is not None:
            return cached, True

    with _NAVIGATE_LOCK:
        chrome = ChromeCDP()

        ready, html = chrome.navigate_and_wait(
            url,
            ready_selector=ready_selector,
            all_selectors=all_selectors,
            timeout=timeout,
            min_stable=min_stable,
        )

        if not ready:
            print(f"[warn] 等待页面就绪超时: {url}")

        if not html:
            raise Exception(f"获取 HTML 失败: {url}")

    if cache is not None:
        cache.set(url, html)

    return html, False


def parse_page(
    url,
    ready_selector="",
    all_selectors=None,
    cache=None,
    timeout=20.0,
    min_stable=0.5,
):
    """取页面并返回 (HanimeParser, from_cache)。"""
    html, from_cache = fetch_html(
        url,
        ready_selector=ready_selector,
        all_selectors=all_selectors,
        cache=cache,
        timeout=timeout,
        min_stable=min_stable,
    )

    return HanimeParser(html), from_cache


@app.get("/")
def root():
    return {
        "message": "HanimeViewer API is running"
    }


@app.post("/api/shutdown")
def shutdown(exit_process: bool = True):
    """App 退出时收尾。

    必须收掉两样东西：
    1. **隐藏的调试浏览器** —— 它的窗口是隐藏的，用户看不到也就没法自己关，
       留着就是一堆白占内存的 chrome.exe（实测会留 13 个）
    2. 后端自己（由调用方决定是否顺带结束）

    这个接口故意放在 main.py 而不是打包入口 run_backend.py：
    放在入口文件里的话，用 `uvicorn main:app` 直接跑后端时就没有这个路由，
    App 的退出清理会静默失败（踩过这个坑）。
    """
    import browser as browser_module

    def _cleanup():
        try:
            # 会轮询等浏览器真的退干净
            browser_module.stop_browser(cdp.CDP_PORT, timeout=15.0)
        except Exception:
            pass

        if exit_process:
            os._exit(0)

    threading.Thread(target=_cleanup, daemon=True).start()

    return {"ok": True}


@app.get("/api/status")
def system_status():
    """给客户端的启动自检用。

    客户端启动时会轮询这个接口，确认「后端 + 调试浏览器」都就绪了
    再进入主界面，避免一开始就报一堆网络错误。
    """
    import browser as browser_module

    browser_path = browser_module.find_browser()
    cdp_alive = browser_module.is_cdp_alive(cdp.CDP_PORT)

    page_count = 0
    current_url = ""

    if cdp_alive:
        try:
            pages = cdp.list_page_targets(timeout=2)

            page_count = len(pages)

            for target in pages:
                url = target.get("url", "")

                if url.startswith("http"):
                    current_url = url
                    break
        except Exception:
            pass

    return {
        "backend": True,
        "cdp_port": cdp.CDP_PORT,
        "cdp_alive": cdp_alive,
        "page_count": page_count,
        "current_url": current_url,
        "browser_found": bool(browser_path),
        "browser_path": browser_path or "",
        "ready": bool(cdp_alive and page_count > 0),
    }


@app.post("/api/browser/start")
def start_browser():
    """手动确保调试浏览器已启动（客户端启动自检失败时可以重试）。"""
    import browser as browser_module

    ok, message, path = browser_module.ensure_browser(
        port=cdp.CDP_PORT
    )

    return {
        "ok": ok,
        "message": message,
        "browser_path": path,
    }


@app.get("/api/cache_stats")
def cache_stats():
    """查看缓存命中情况，方便确认缓存是否真的在起作用。"""
    return {
        "home": home_cache.stats(),
        "search": search_cache.stats(),
        "detail": detail_cache.stats(),
        "tags": tags_cache.stats(),
        "playlist": playlist_cache.stats(),
    }


@app.get("/api/cache_clear")
def cache_clear():
    """手动清空全部缓存（调试用）。"""
    home_cache.clear()
    search_cache.clear()
    detail_cache.clear()
    tags_cache.clear()
    playlist_cache.clear()

    return {"message": "缓存已清空"}


@app.get("/api/home")
def home_videos():
    url = "https://hanime1.me/"

    try:
        print("准备打开首页:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=home_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        cards = parser.get_video_cards()

        # 只保留 Hanime 自己的视频页面，过滤广告
        real_cards = [
            card
            for card in cards
            if card.url.startswith("https://hanime1.me/watch?")
        ]

        print("解析到的视频卡片数量:")
        print(len(cards))

        print("过滤广告后的视频数量:")
        print(len(real_cards))

        results = []

        for card in real_cards:
            results.append({
                "title": card.title,
                "url": card.url,
                "thumbnail": card.thumbnail,
                "duration": card.duration,
                "rating": card.rating,
                "views": card.views
            })

        return {
            "results": results
        }

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/home_sections")
def home_sections():
    url = "https://hanime1.me/"

    try:
        print("准备打开首页（栏目模式）:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=home_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        sections = parser.get_home_sections()

        print("栏目数量:")
        print(len(sections))

        for section in sections:
            print(
                f"  {section['name']}: "
                f"{len(section['videos'])} 个视频"
            )

        result = []

        for section in sections:
            result.append({
                "name": section["name"],
                "url": section.get("url", ""),
                "videos": [
                    {
                        "title": v.title,
                        "url": v.url,
                        "thumbnail": v.thumbnail,
                        "duration": v.duration,
                        "rating": v.rating,
                        "views": v.views
                    }
                    for v in section["videos"]
                ]
            })

        return {"sections": result}

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/tags")
def get_tags():
    url = "https://hanime1.me/search?genre=%E8%A3%8F%E7%95%AA"

    try:
        print("准备打开标签页面:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=tags_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        groups = parser.get_tag_groups()

        print("标签分组数量:")
        print(len(groups))

        for g in groups:
            print(f"  {g['name']}: {len(g['tags'])} 个标签")

        return {"groups": groups}

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/filter")
def filter_videos(
    query: str = "",
    genre: str = "",
    sort: str = "",
    date: str = "",
    duration: str = "",
    page: int = 1,
    tags: str = "",
    broad: str = ""
):
    try:
        if page < 1:
            page = 1

        from urllib.parse import urlencode

        tag_list = [
            t for t in tags.split("|")
            if t.strip()
        ]

        params = [
            ("query", query),
            ("type", ""),
            ("genre", genre),
        ]

        if broad == "on" and tag_list:
            params.append(("broad", "on"))

        for tag in tag_list:
            params.append(("tags[]", tag))

        params.extend([
            ("sort", sort),
            ("date", date),
            ("duration", duration),
        ])

        if page > 1:
            params.append(("page", str(page)))

        query_string = urlencode(params)

        url = f"https://hanime1.me/search?{query_string}"

        print("准备打开筛选页面:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=search_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        cards = parser.get_search_results()

        total_pages = parser.get_search_total_pages()

        # 标签列表就在同一个页面里（<div id="tags"> 模态框），
        # 顺手解析出来一起返回，客户端就不用再单独请求 /api/tags 了。
        # 这省掉了一整次「导航 -> 等就绪 -> 取 HTML」，是标签弹窗变快的关键。
        tag_groups = parser.get_tag_groups()

        print("解析到的视频数量:")
        print(len(cards))

        print("总页数:")
        print(total_pages)

        print("标签分组数量:")
        print(len(tag_groups))

        results = []

        for card in cards:
            results.append({
                "title": card.title,
                "url": card.url,
                "thumbnail": card.thumbnail,
                "duration": card.duration,
                "rating": card.rating,
                "views": card.views
            })

        return {
            "query": query,
            "genre": genre,
            "sort": sort,
            "date": date,
            "duration": duration,
            "tags": tag_list,
            "broad": broad,
            "page": page,
            "total_pages": total_pages,
            "results": results,
            "tag_groups": tag_groups
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/search")
def search_videos(query: str):
    url = f"https://hanime1.me/search?query={query}"

    try:
        print("准备打开搜索页面:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=search_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        cards = parser.get_video_cards()

        # 只保留 Hanime 自己的视频页面，过滤广告
        real_cards = [
            card
            for card in cards
            if card.url.startswith("https://hanime1.me/watch?")
        ]

        print("解析到的视频卡片数量:")
        print(len(cards))

        print("过滤广告后的视频数量:")
        print(len(real_cards))

        results = []

        for card in real_cards:
            results.append({
                "title": card.title,
                "url": card.url,
                "thumbnail": card.thumbnail,
                "duration": card.duration,
                "rating": card.rating,
                "views": card.views
            })

        return {
            "query": query,
            "results": results
        }

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/video/{video_id}")
def get_video(video_id: str):
    url = f"https://hanime1.me/watch?v={video_id}"

    try:
        print("准备打开:")
        print(url)

        # 详情页里的视频直链带 secure 签名，TTL 较短，避免拿到过期地址
        parser, from_cache = parse_page(
            url,
            all_selectors=DETAIL_READY_SELECTORS,
            cache=detail_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        detail = parser.get_video_detail()

        playlist_videos = parser.get_playlist_videos()

        print("视频详情:")
        print(detail)

        print("播放清单影片数量:")
        print(len(playlist_videos))

        return {
            "title": detail.title,
            "url": detail.url,
            "video_source": detail.video_source,
            "thumbnail": detail.thumbnail,
            "brand": detail.brand,
            "brand_url": detail.brand_url,
            # 播放器下方头像所属的「品牌/制作商」主页
            "artist_id": detail.artist_id,
            "artist_url": detail.artist_url,
            "artist_avatar": detail.artist_avatar,
            # 真正的上传者（可能与品牌不是同一个人）
            "uploader": detail.uploader,
            "uploader_id": detail.uploader_id,
            "uploader_url": detail.uploader_url,
            "uploader_avatar": detail.uploader_avatar,
            "like_ratio": detail.like_ratio,
            "like_count": detail.like_count,
            "unlike_count": detail.unlike_count,
            "views": detail.views,
            "release_date": detail.release_date,
            "file_size": detail.file_size,
            "tags": detail.tags,
            "playlist": playlist_videos,
            "sources": detail.sources,
            "related": detail.related,
            # 官方的下載按钮指向这个页面（客户端也可以直接用 video_source）
            "download_url": (
                f"https://hanime1.me/download?v={video_id}"
            )
        }

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/account")
def account_info(force: bool = False):
    """当前登录状态。force=true 时忽略缓存重新检测。"""
    try:
        return auth.get_account(force=force)

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.post("/api/login")
def login(payload: dict):
    """在真实 Chrome 里登录 Hanime。

    请求体：{"email": "...", "password": "..."}

    密码只用于这一次提交，不会写进任何文件。
    """
    email = (payload or {}).get("email", "").strip()
    password = (payload or {}).get("password", "")

    try:
        ok, account, error = auth.login(email, password)

        if not ok:
            raise HTTPException(
                status_code=401,
                detail=error or "登录失败"
            )

        return {
            "ok": True,
            "account": account
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.post("/api/logout")
def logout():
    try:
        auth.logout()

        return {"ok": True}

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/user/{user_id}")
def user_profile(user_id: str, tab: str = "home", page: int = 1):
    """用户/发行商主页。

    tab:
      home      - 个人中心首页（栏目段总览，见 /api/user/{id}/home）
      histories - 觀看紀錄
      saves     - 稍後觀看
      likes     - 讚好的影片
      playlists - 播放清單
      uploaded  - 上傳的影片

    这些页面都是服务端渲染的，直接从同一个浏览器会话里读，
    所以登录之后才能看到的内容也能正常拿到。

    列表类 tab 每页 60 条，用 page 翻页。
    """
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id 不能为空")

    if page < 1:
        page = 1

    base = f"https://hanime1.me/user/{user_id}"

    if tab == "home" or not tab:
        url = base
    else:
        url = f"{base}/{tab}"

        if page > 1:
            url = f"{url}?page={page}"

    try:
        parser, from_cache = parse_page(
            url,
            ready_selector="a.video-link",
            cache=user_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        # tab 页上除了真正的内容，还带着个人中心首页那 4 个栏目段的预览卡片，
        # 所以必须限定在 .specific-tab-view 里解析并去重，
        # 直接全页抓会把预览段和分页重复的卡片一起算进来。
        if tab == "playlists":
            playlists = parser.get_tab_playlists()
            videos = []
        else:
            videos = parser.get_tab_videos()
            playlists = []

        print("影片数量:")
        print(len(videos))

        print("播放清单数量:")
        print(len(playlists))

        # 页面标题形如
        # 「ピンクパイナップル的首頁\xa0-\xa0H動漫/裏番/線上看\xa0-\xa0Hanime1.me」
        # 注意分隔符是 \xa0-（不换行空格），不是普通的 " - "
        title = parser.get_title() or ""
        normalized = title.replace("\xa0", " ")
        name = normalized.split(" - ", 1)[0] if " - " in normalized else normalized

        for suffix in ("的首頁", "的影片", "的播放清單", "的首页"):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break

        avatar = parser.get_user_avatar()

        return {
            "user_id": user_id,
            "tab": tab,
            "page": page,
            "total_pages": parser.get_total_pages(),
            "url": url,
            "name": name.strip(),
            "avatar": avatar,
            # get_tab_videos / get_tab_playlists 返回的就是 dict，
            # 不用再逐字段转换
            "videos": videos,
            "playlists": playlists
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.post("/api/video/{video_id}/action")
def video_action(video_id: str, payload: dict):
    """点赞 / 取消点赞 / 储存。

    请求体：{"action": "like" | "unlike" | "save"}

    实现在真实 Chrome 里触发一次真实点击，然后重新读取页面确认结果。
    成功后详情缓存要清掉，否则前端还会看到旧的点赞数。
    """
    action = (payload or {}).get("action", "").strip()

    if action not in ("like", "unlike", "save"):
        raise HTTPException(
            status_code=400,
            detail="action 必须是 like / unlike / save 之一"
        )

    try:
        ok, message, state = auth.video_action(video_id, action)

        if ok:
            # 页面内容变了，相关缓存作废
            detail_cache.clear()
            user_cache.clear()

        if not ok:
            raise HTTPException(status_code=400, detail=message)

        return {
            "ok": True,
            "message": message,
            "state": state
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/user/{user_id}/home")
def user_center_home(user_id: str):
    """个人中心「主页」的栏目段。

    官网这个页面上有 4 个栏目（觀看紀錄 / 稍後觀看 / 讚好的影片 / 播放清單），
    每个栏目横向排一排卡片，右边有「查看更多」跳到对应页面。

    返回的每个栏目最多 10 个条目（limit_per_row）。
    """
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id 不能为空")

    url = f"https://hanime1.me/user/{user_id}"

    try:
        parser, from_cache = parse_page(
            url,
            ready_selector="a.horizontal-row-title",
            cache=user_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        rows = parser.get_user_home_rows(limit_per_row=10)

        print("栏目数量:")
        print(len(rows))

        for row in rows:
            print(f"  {row['name']}: {len(row['videos'] or row['playlists'])} 个")

        title = parser.get_title() or ""
        normalized = title.replace("\xa0", " ")
        name = (
            normalized.split(" - ", 1)[0]
            if " - " in normalized
            else normalized
        )

        for suffix in ("的首頁", "的影片", "的播放清單", "的首页"):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break

        return {
            "user_id": user_id,
            "url": url,
            "name": name.strip(),
            "avatar": parser.get_user_avatar(),
            "sections": rows,
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/playlists")
def get_playlists(
    page: int = 1,
    search: str = ""
):
    try:
        if page < 1:
            raise HTTPException(
                status_code=400,
                detail="page 必须大于等于 1"
            )

        search = search.strip()

        # 播放清单是账号私有数据，必须用**当前登录的那个账号**。
        # 以前这里写死 715321（早期测试账号），换账号后拿到的还是它的数据。
        account = auth.get_account()

        if not account["logged_in"] or not account["user_id"]:
            raise HTTPException(
                status_code=401,
                detail="播放清单属于账号数据，请先登录",
            )

        base_url = (
            f"https://hanime1.me/user/{account['user_id']}/playlists"
        )

        # =========================
        # 搜索模式
        # =========================
        if search:
            print("准备搜索播放清单:")
            print(search)

            all_playlists = []

            # 先打开第一页，获取总页数
            first_url = base_url

            print("准备打开播放清单第一页:")
            print(first_url)

            first_parser, _ = parse_page(
                first_url,
                ready_selector=LIST_READY_SELECTOR,
                cache=playlist_cache,
            )

            total_pages = 1

            for link in first_parser.soup.find_all(
                "a",
                href=True
            ):
                href = first_parser.clean_url(
                    link.get("href")
                )

                if not href:
                    continue

                if not href.startswith(
                    base_url + "?page="
                ):
                    continue

                try:
                    page_number = int(
                        href.split(
                            "?page=",
                            1
                        )[1]
                    )
                except ValueError:
                    continue

                if page_number > total_pages:
                    total_pages = page_number

            print("检测到播放清单总页数:")
            print(total_pages)

            # 遍历全部播放清单页面
            for current_page in range(
                1,
                total_pages + 1
            ):
                if current_page == 1:
                    url = base_url
                else:
                    url = (
                        f"{base_url}"
                        f"?page={current_page}"
                    )

                print(
                    "搜索播放清单，第"
                    f"{current_page}/{total_pages}页:"
                )
                print(url)

                parser, _ = parse_page(
                    url,
                    ready_selector=LIST_READY_SELECTOR,
                    cache=playlist_cache,
                )

                playlists = parser.get_playlists()

                print(
                    "本页播放清单数量:"
                    f"{len(playlists)}"
                )

                all_playlists.extend(
                    playlists
                )

            print(
                "全部播放清单数量:"
                f"{len(all_playlists)}"
            )

            # 本地搜索播放清单名称
            search_results = []

            cc = OpenCC("s2t")

            search_text = cc.convert(
                search.strip()
            ).casefold()

            for playlist in all_playlists:
                name = (
                    playlist.get("name")
                    or ""
                ).strip()

                searchable_name = cc.convert(
                    name
                ).casefold()

                if search_text in searchable_name:
                    search_results.append(
                        playlist
                    )

            print(
                "搜索匹配数量:"
                f"{len(search_results)}"
            )

            return {
                "page": 1,
                "total_pages": 1,
                "search": search,
                "results": search_results
            }

        # =========================
        # 普通分页模式
        # =========================
        if page == 1:
            url = base_url
        else:
            url = (
                f"{base_url}"
                f"?page={page}"
            )

        print("准备打开播放清单页面:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=playlist_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        playlists = parser.get_playlists()

        print("本页播放清单数量:")
        print(len(playlists))

        total_pages = 1

        for link in parser.soup.find_all(
            "a",
            href=True
        ):
            href = parser.clean_url(
                link.get("href")
            )

            if not href:
                continue

            if not href.startswith(
                base_url + "?page="
            ):
                continue

            try:
                page_number = int(
                    href.split(
                        "?page=",
                        1
                    )[1]
                )
            except ValueError:
                continue

            if page_number > total_pages:
                total_pages = page_number

        print("检测到播放清单页数:")
        print(total_pages)

        return {
            "page": page,
            "total_pages": total_pages,
            "results": playlists
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )


@app.get("/api/playlist")
def get_playlist(list_id: str):
    try:
        if not list_id:
            raise HTTPException(
                status_code=400,
                detail="list_id 不能为空"
            )

        url = (
            "https://hanime1.me/playlist"
            f"?list={list_id}"
        )

        print("准备打开播放清单:")
        print(url)

        parser, from_cache = parse_page(
            url,
            ready_selector=LIST_READY_SELECTOR,
            cache=playlist_cache,
        )

        print("命中缓存:" if from_cache else "已重新加载页面")

        videos = parser.get_playlist_videos()

        print("播放清单影片数量:")
        print(len(videos))

        return {
            "list_id": list_id,
            "url": url,
            "title": parser.get_title(),
            "results": videos
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )
