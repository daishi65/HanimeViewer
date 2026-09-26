from bs4 import BeautifulSoup

from parser.models import VideoCard, VideoDetail


class HanimeParser:
    def __init__(self, html):
        self.html = html
        self.soup = BeautifulSoup(html, "html.parser")

    @staticmethod
    def clean_url(value):
        if not value:
            return value

        value = value.strip()

        # 处理 [显示文字](真实地址) 这种 Markdown 格式
        if value.startswith("[") and value.endswith(")"):
            marker = "]("
            marker_pos = value.find(marker)

            if marker_pos != -1:
                return value[marker_pos + 2:-1]

        return value

    def get_title(self):
        if self.soup.title:
            return self.soup.title.text.strip()

        return None

    def count_links(self):
        return len(self.soup.find_all("a"))

    def get_some_links(self, limit=10):
        result = []

        for link in self.soup.find_all("a")[:limit]:
            result.append({
                "text": link.text.strip(),
                "href": self.clean_url(link.get("href"))
            })

        return result

    def get_images(self, limit=10):
        result = []

        for img in self.soup.find_all("img")[:limit]:
            result.append({
                "src": self.clean_url(img.get("src")),
                "alt": img.get("alt")
            })

        return result

    def _parse_video_link(self, card):
        url = self.clean_url(card.get("href"))

        img = card.find("img", class_="main-thumb")

        if not img:
            return None

        thumbnail = self.clean_url(img.get("src"))

        title_box = card.find("div", class_="title")
        title = title_box.get_text(strip=True) if title_box else ""

        duration_box = card.find("div", class_="duration")
        duration = duration_box.get_text(strip=True) if duration_box else ""

        stat_items = card.find_all("div", class_="stat-item")

        rating = ""
        views = ""

        if len(stat_items) >= 1:
            rating_box = stat_items[0]

            icon = rating_box.find("i", class_="material-icons")

            if icon:
                icon.extract()

            rating = rating_box.get_text(strip=True)

        if len(stat_items) >= 2:
            views = stat_items[1].get_text(strip=True)

        return VideoCard(
            title=title,
            url=url,
            thumbnail=thumbnail,
            duration=duration,
            rating=rating,
            views=views
        )

    def get_video_cards(self, limit=None):
        result = []

        cards = self.soup.find_all("a", class_="video-link")

        for card in cards:
            video_card = self._parse_video_link(card)

            if not video_card:
                continue

            result.append(video_card)

            if limit is not None and len(result) >= limit:
                break

        return result
        
    def get_playlists(self, limit=None):
        result = []

        playlist_cards = self.soup.find_all(
            "div",
            class_="video-item-container"
        )

        for card in playlist_cards:
            link = card.find(
                "a",
                class_="video-link",
                href=True
            )

            if not link:
                continue

            href = self.clean_url(
                link.get("href")
            )

            if not href:
                continue

            if not href.startswith(
                "https://hanime1.me/playlist?list="
            ):
                continue

            thumbnail = ""

            img = card.find(
                "img",
                class_="main-thumb"
            )

            if img:
                thumbnail = self.clean_url(
                    img.get("src")
                ) or ""

            name = ""

            title_box = card.find(
                "div",
                class_="title"
            )

            if title_box:
                name = title_box.get_text(
                    " ",
                    strip=True
                )

            if not name:
                continue

            video_count = ""

            stats_container = card.find(
                "div",
                class_="stats-container"
            )

            if stats_container:
                stat_item = stats_container.find(
                    "div",
                    class_="stat-item"
                )

                if stat_item:
                    video_count = stat_item.get_text(
                        " ",
                        strip=True
                    )

            if not video_count:
                continue

            result.append({
                "name": name,
                "video_count": video_count,
                "thumbnail": thumbnail,
                "url": href
            })

            if limit is not None and len(result) >= limit:
                break

        return result

    def get_playlist_videos(self, limit=None):
        result = []
        seen_video_ids = set()

        cards = self.soup.find_all(
            "div",
            class_="playlist-video-card"
        )

        for card in cards:
            link = card.find(
                "a",
                href=True
            )

            if not link:
                continue

            href = self.clean_url(
                link.get("href")
            )

            if not href:
                continue

            if not href.startswith(
                "https://hanime1.me/watch?"
            ):
                continue

            video_id = ""

            query = href.split("?", 1)[1]

            for part in query.split("&"):
                if part.startswith("v="):
                    video_id = part[2:]
                    break

            if not video_id:
                continue

            if video_id in seen_video_ids:
                continue

            thumbnail = ""

            img = card.find(
                "img",
                class_="main-thumb"
            )

            if img:
                thumbnail = self.clean_url(
                    img.get("src")
                ) or ""

            duration = ""

            duration_box = card.find(
                "div",
                class_="duration"
            )

            if duration_box:
                duration = duration_box.get_text(
                    " ",
                    strip=True
                )

            rating = ""
            views = ""

            stat_items = card.find_all(
                "div",
                class_="stat-item"
            )

            if len(stat_items) >= 1:
                rating_box = stat_items[0]

                icon = rating_box.find(
                    "i",
                    class_="material-icons"
                )

                if icon:
                    icon.extract()

                rating = rating_box.get_text(
                    " ",
                    strip=True
                )

            if len(stat_items) >= 2:
                views = stat_items[1].get_text(
                    " ",
                    strip=True
                )

            title = ""

            title_box = card.find(
                "h4",
                class_="video-title"
            )

            if title_box:
                title = title_box.get_text(
                    " ",
                    strip=True
                )

            if not title:
                continue

            seen_video_ids.add(video_id)

            result.append({
                "video_id": video_id,
                "title": title,
                "url": href,
                "thumbnail": thumbnail,
                "duration": duration,
                "rating": rating,
                "views": views
            })

            if limit is not None and len(result) >= limit:
                break

        return result

    def get_video_source(self):
        # 优先寻找：
        # <link rel="preload" as="video" href="...">
        video_preload = self.soup.find(
            "link",
            attrs={
                "rel": "preload",
                "as": "video"
            }
        )

        if video_preload:
            source = video_preload.get("href")

            if source:
                return self.clean_url(source)

        # 如果 preload 没找到，再寻找 <video> / <source>
        video = self.soup.find("video")

        if video:
            source = video.get("src")

            if source:
                return self.clean_url(source)

            source_tag = video.find("source")

            if source_tag:
                source = source_tag.get("src")

                if source:
                    return self.clean_url(source)

        return None

    def get_video_sources(self):
        # 返回页面中所有 <source> 标签对应的画质列表
        # 格式：[{"url": "...", "quality": "1080p"}, ...]
        # 按清晰度从高到低排序
        sources = []

        video = self.soup.find("video")

        if not video:
            return sources

        source_tags = video.find_all("source")

        for source_tag in source_tags:
            src = source_tag.get("src")
            size = source_tag.get("size")

            if not src:
                continue

            if size:
                quality = f"{size}p"
            else:
                import re
                match = re.search(r"-(\d+p)\.mp4", src)
                if match:
                    quality = match.group(1)
                else:
                    quality = "unknown"

            sources.append({
                "url": self.clean_url(src),
                "quality": quality
            })

        def quality_number(item):
            text = item["quality"].rstrip("p")
            if text.isdigit():
                return int(text)
            return 0

        sources.sort(key=quality_number, reverse=True)

        return sources

    def get_thumbnail(self):
        # 优先寻找 Open Graph 图片
        og_image = self.soup.find(
            "meta",
            attrs={
                "property": "og:image"
            }
        )

        if og_image:
            image_url = og_image.get("content")

            if image_url:
                return self.clean_url(image_url)

        # 如果没有 og:image，则尝试页面中的 video poster
        video = self.soup.find("video")

        if video:
            poster = video.get("poster")

            if poster:
                return self.clean_url(poster)

        return None

    def get_description(self):
        meta_description = self.soup.find(
            "meta",
            attrs={
                "name": "description"
            }
        )

        if meta_description:
            return meta_description.get("content")

        return None

    def get_brand(self):
        description = self.get_description()

        if not description:
            return ""

        for line in description.splitlines():
            line = line.strip()

            if line.startswith("Brand / ブランド:"):
                return line.split(":", 1)[1].strip()

        return ""

    def get_release_date(self):
        description = self.get_description()

        if not description:
            return ""

        for line in description.splitlines():
            line = line.strip()

            if line.startswith("Release / 販売日:"):
                return line.split(":", 1)[1].strip()

        return ""

    def get_file_size(self):
        description = self.get_description()

        if not description:
            return ""

        for line in description.splitlines():
            line = line.strip()

            if line.startswith("File size / ファイル容量:"):
                return line.split(":", 1)[1].strip()

        return ""

    def get_tags(self):
        meta_keywords = self.soup.find(
            "meta",
            attrs={
                "name": "keywords"
            }
        )

        if not meta_keywords:
            return []

        content = meta_keywords.get("content")

        if not content:
            return []

        return [
            tag.strip()
            for tag in content.split(",")
            if tag.strip()
        ]

    def get_video_detail(self):
        title = self.get_title()

        video_url = self.soup.find(
            "link",
            attrs={
                "rel": "canonical"
            }
        )

        if video_url:
            video_url = self.clean_url(video_url.get("href"))
        else:
            video_url = ""

        return VideoDetail(
            title=title or "",
            url=video_url,
            video_source=self.get_video_source() or "",
            thumbnail=self.get_thumbnail() or "",
            brand=self.get_brand(),
            release_date=self.get_release_date(),
            file_size=self.get_file_size(),
            tags=self.get_tags(),
            sources=self.get_video_sources()
        )

    def get_tag_groups(self):
        # 从 genre 页面提取所有标签分组
        # 返回格式：[{"name": "人物關係", "tags": ["近親", "姐", ...]}, ...]

        result = []

        modal = self.soup.find("div", id="tags")

        if not modal:
            return result

        modal_body = modal.find("div", class_="modal-body")

        if not modal_body:
            return result

        elements = modal_body.find_all(["h5", "label"])

        current_group = None
        current_tags = []

        def flush():
            if current_group and current_tags:
                result.append({
                    "name": current_group,
                    "tags": list(current_tags)
                })

        for el in elements:
            classes = el.get("class", [])

            if el.name == "h5":
                flush()

                text = el.get_text(strip=True)

                if text == "廣泛配對":
                    current_group = None
                    current_tags = []
                else:
                    current_group = text
                    current_tags = []

            elif el.name == "label":
                if "hentai-tags-wrapper" not in classes:
                    continue

                input_el = el.find(
                    "input",
                    attrs={"name": "tags[]"}
                )

                if not input_el:
                    continue

                value = input_el.get("value", "")

                if value:
                    current_tags.append(value)

        flush()

        return result

    def get_search_total_pages(self):
        from urllib.parse import urlparse, parse_qs

        paginations = self.soup.find_all(
            "div",
            class_="search-pagination"
        )

        print(f"[分页] 找到 {len(paginations)} 个分页区域")

        max_page = 1

        for pagination in paginations:
            for a in pagination.find_all(
                "a",
                class_="page-link",
                href=True
            ):
                href = a.get("href", "")

                if "page=" not in href:
                    continue

                try:
                    parsed = urlparse(href)
                    params = parse_qs(parsed.query)
                    page_num = int(
                        params.get("page", ["0"])[0]
                    )

                    if page_num > max_page:
                        max_page = page_num

                except (ValueError, IndexError):
                    continue

        print(f"[分页] 最大页码 = {max_page}")

        return max_page
    
    def get_search_results(self):
        # 搜索结果页有两种结构：
        # 1. sort 页面（?sort=xxx）和首页栏目结构相同，用 video-link
        # 2. genre 页面（?genre=xxx）用 a > div.video-card-inner 结构
        # 先试 sort 结构，如果找不到视频再试 genre 结构

        result = []

        # 模式 1：video-link（sort 页面、首页栏目）
        cards = self.soup.find_all("a", class_="video-link")

        for card in cards:
            video_card = self._parse_video_link(card)

            if not video_card:
                continue

            if not video_card.url.startswith(
                "https://hanime1.me/watch?"
            ):
                continue

            result.append(video_card)

        if result:
            return result

        # 模式 2：video-card-inner（genre 页面）
        for a in self.soup.find_all("a", href=True):
            href = self.clean_url(a.get("href"))

            if not href:
                continue

            if not href.startswith(
                "https://hanime1.me/watch?"
            ):
                continue

            card = a.find("div", class_="video-card-inner")

            if not card:
                continue

            img = card.find("img")

            if not img:
                continue

            thumbnail = self.clean_url(img.get("src"))

            title_box = card.find(
                "div",
                class_="home-rows-videos-title"
            )

            title = (
                title_box.get_text(strip=True)
                if title_box
                else ""
            )

            if not title:
                continue

            result.append(VideoCard(
                title=title,
                url=href,
                thumbnail=thumbnail,
                duration="",
                rating="",
                views=""
            ))

        return result
    
    def get_home_sections(self):
        # 首页栏目结构：
        # <a class="horizontal-row-title">
        #   <h3>最新上市...查看更多</h3>
        # </a>
        # <div class="home-rows-videos-wrapper ...">
        #   <div class="video-item-container">...</div>
        # </div>
        # ...

        from bs4 import NavigableString

        sections = []

        container = self.soup.find(
            "div",
            class_="home-rows-section-margin-top"
        )

        if not container:
            return sections

        current_name = None
        current_url = None
        current_videos = []

        elements = container.find_all(
            ["a", "div"],
            class_=["horizontal-row-title", "home-rows-videos-wrapper"]
        )

        for el in elements:
            classes = el.get("class", [])

            if "horizontal-row-title" in classes:
                if current_name is not None:
                    sections.append({
                        "name": current_name,
                        "url": current_url,
                        "videos": current_videos
                    })

                current_url = self.clean_url(el.get("href"))

                h3 = el.find("h3")

                current_name = ""

                if h3:
                    for child in h3.children:
                        if isinstance(child, NavigableString):
                            t = child.strip()

                            if t:
                                current_name = t
                                break

                current_videos = []

            elif "home-rows-videos-wrapper" in classes:
                for video_container in el.find_all(
                    "div",
                    class_="video-item-container"
                ):
                    link = video_container.find(
                        "a",
                        class_="video-link"
                    )

                    if not link:
                        continue

                    video_card = self._parse_video_link(link)

                    if video_card:
                        current_videos.append(video_card)

        if current_name is not None:
            sections.append({
                "name": current_name,
                "url": current_url,
                "videos": current_videos
            })

        return sections