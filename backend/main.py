import time

from fastapi import FastAPI, HTTPException

from cdp.chrome import ChromeCDP
from parser.hanime_parser import HanimeParser
from opencc import OpenCC


app = FastAPI(
    title="HanimeViewer API",
    version="1.0.0"
)


@app.get("/")
def root():
    return {
        "message": "HanimeViewer API is running"
    }


@app.get("/api/home")
def home_videos():
    url = "https://hanime1.me/"

    try:
        chrome = ChromeCDP()

        print("准备打开首页:")
        print(url)

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(5)

        print("当前页面 URL:")
        print(chrome.get_url())

        print("当前页面标题:")
        print(chrome.get_title())

        html = chrome.get_html()

        print("HTML 长度:")
        print(len(html))

        parser = HanimeParser(html)

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


@app.get("/api/search")
def search_videos(query: str):
    url = f"https://hanime1.me/search?query={query}"

    try:
        chrome = ChromeCDP()

        print("准备打开搜索页面:")
        print(url)

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(5)

        print("当前页面 URL:")
        print(chrome.get_url())

        print("当前页面标题:")
        print(chrome.get_title())

        html = chrome.get_html()

        print("HTML 长度:")
        print(len(html))

        parser = HanimeParser(html)

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
        chrome = ChromeCDP()

        print("准备打开:")
        print(url)

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(5)

        print("当前页面 URL:")
        print(chrome.get_url())

        print("当前页面标题:")
        print(chrome.get_title())

        html = chrome.get_html()

        print("HTML 长度:")
        print(len(html))

        parser = HanimeParser(html)

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
            "release_date": detail.release_date,
            "file_size": detail.file_size,
            "tags": detail.tags,
            "playlist": playlist_videos,
            "sources": detail.sources
        }
    
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )

@app.get("/api/account")
def get_account():
    try:
        chrome = ChromeCDP()

        url = chrome.get_url()
        title = chrome.get_title()
        html = chrome.get_html()

        logged_in = "logout" in html.lower()

        user_id = ""
        username = ""

        if logged_in:
            # 当前用户页面 URL:
            # https://hanime1.me/user/715321/playlists
            parts = url.split("/")

            for index, part in enumerate(parts):
                if part == "user" and index + 1 < len(parts):
                    user_id = parts[index + 1]
                    break

            # 当前页面标题:
            # 你才是奶龙 - 播放清單 - H動漫/裏番/線上看 - Hanime1.me
            if " - " in title:
                username = title.split(" - ", 1)[0].strip()

        return {
            "logged_in": logged_in,
            "user_id": user_id,
            "username": username
        }

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

        chrome = ChromeCDP()

        base_url = (
            "https://hanime1.me/user/715321/playlists"
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

            chrome.navigate(first_url)

            print("等待页面加载...")
            time.sleep(5)

            first_html = chrome.get_html()

            first_parser = HanimeParser(
                first_html
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

                chrome.navigate(url)

                time.sleep(5)

                html = chrome.get_html()

                parser = HanimeParser(html)

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

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(5)

        print("当前页面 URL:")
        print(chrome.get_url())

        print("当前页面标题:")
        print(chrome.get_title())

        html = chrome.get_html()

        if not html:
            print("本页 HTML 获取失败，重新等待...")
            time.sleep(3)

            html = chrome.get_html()

        if not html:
            raise Exception(
                f"第{current_page}页获取 HTML 失败"
            )

        parser = HanimeParser(html)

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

        chrome = ChromeCDP()

        url = (
            "https://hanime1.me/playlist"
            f"?list={list_id}"
        )

        print("准备打开播放清单:")
        print(url)

        chrome.navigate(url)

        print("等待页面加载...")
        time.sleep(5)

        print("当前页面 URL:")
        print(chrome.get_url())

        print("当前页面标题:")
        print(chrome.get_title())

        html = chrome.get_html()

        print("HTML 长度:")
        print(len(html))

        parser = HanimeParser(html)

        videos = parser.get_playlist_videos()

        print("播放清单影片数量:")
        print(len(videos))

        return {
            "list_id": list_id,
            "url": url,
            "title": chrome.get_title(),
            "results": videos
        }

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc)
        )