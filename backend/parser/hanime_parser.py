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

    def get_video_cards(self, limit=144):
        result = []

        cards = self.soup.find_all("a", class_="video-link")

        for card in cards:
            url = self.clean_url(card.get("href"))

            img = card.find("img", class_="main-thumb")

            if not img:
                continue

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

            video_card = VideoCard(
                title=title,
                url=url,
                thumbnail=thumbnail,
                duration=duration,
                rating=rating,
                views=views
            )

            result.append(video_card)

            if len(result) >= limit:
                break

        return result

    def get_home_sections(self):

        print("===== 调试首页结构 =====")


        print(
            self.soup.title
        )


        headings = self.soup.find_all(
            [
                "h1",
                "h2",
                "h3"
            ]
        )


        print(
            "标题数量:",
            len(headings)
        )


        for h in headings[:20]:

            print(
                "标题:",
                h.get_text(strip=True)
            )


        print("=======================")


        print(
            "前5个div:"
        )

        for div in self.soup.find_all("div")[:5]:
            print(div)


        return []
    
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
            tags=self.get_tags()
        )