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
    release_date: str
    file_size: str
    tags: list[str]
    sources: list = field(default_factory=list)