class Feed {
  final int? id;
  final String? title;
  final String? url;
  final String? category;
  final int? addedAt;
  final int? failCount;
  Feed({this.id, this.title, this.url, this.category, this.addedAt, this.failCount});
  factory Feed.fromMap(Map<String, dynamic> m) => Feed(
        id: m['id'] as int?,
        title: m['title'] as String?,
        url: m['url'] as String?,
        category: m['category'] as String?,
        addedAt: m['addedAt'] as int?,
        failCount: m['failCount'] as int?,
      );
}

class FeedItem {
  final int? id;
  final int? feedId;
  final String? guid;
  final String? title;
  final String? link;
  final String? preview;
  final int? pubDate;
  final int? fetchedAt;
  FeedItem({this.id, this.feedId, this.guid, this.title, this.link, this.preview, this.pubDate, this.fetchedAt});
  factory FeedItem.fromMap(Map<String, dynamic> m) => FeedItem(
        id: m['id'] as int?,
        feedId: m['feedId'] as int?,
        guid: m['guid'] as String?,
        title: m['title'] as String?,
        link: m['link'] as String?,
        preview: m['preview'] as String?,
        pubDate: m['pubDate'] as int?,
        fetchedAt: m['fetchedAt'] as int?,
      );
}

class ArticleBlock {
  final String type;
  final String? text;
  final String? src;
  final String? alt;
  ArticleBlock({required this.type, this.text, this.src, this.alt});
  factory ArticleBlock.fromJson(Map<String, dynamic> j) =>
      ArticleBlock(type: j['type'] as String, text: j['text'] as String?, src: j['src'] as String?, alt: j['alt'] as String?);
  Map<String, dynamic> toJson() => {'type': type, if (text != null) 'text': text, if (src != null) 'src': src, if (alt != null) 'alt': alt};
}
