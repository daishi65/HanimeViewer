from dataclasses import dataclass, field


@dataclass
class VideoCard:
    title: str
    url: str
    thumbnail: str
    duration: str
    rating: str
    views: str


@dataclass
class VideoDetail:
    title: str
    url: str
    video_source: str
    thumbnail: str
    brand: str
    brand_url: str
    artist_id: str
    artist_url: str
    artist_avatar: str
    uploader: str
    uploader_id: str
    uploader_url: str
    uploader_avatar: str
    like_ratio: str
    like_count: str
    unlike_count: str
    views: str
    release_date: str
    file_size: str
    tags: list[str]
    sources: list = field(default_factory=list)
    related: list = field(default_factory=list)