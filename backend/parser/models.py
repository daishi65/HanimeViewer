from dataclasses import dataclass


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