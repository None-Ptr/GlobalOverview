// 第二轮扫描：修复失效源 + 补充可用缺口（Business/Health/Literature/Philosophy/Science 等）
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
const CANDIDATES = [
  // 修复失效内置源
  { title: 'Scientific American (instant)', url: 'https://www.scientificamerican.com/feed/instant-feed/', category: 'Science' },
  { title: 'Scientific American (rss)', url: 'https://www.scientificamerican.com/feed/rss/', category: 'Science' },
  { title: 'New Scientist (topic)', url: 'https://www.newscientist.com/news-and-technology/feed/', category: 'Science' },
  { title: 'New Scientist (all)', url: 'https://www.newscientist.com/feed/', category: 'Science' },

  // 学习者 / 分级
  { title: 'VOA LE via FeedX', url: 'https://feedx.net/voalearningenglish', category: 'Learner' },
  { title: 'ESL Fast', url: 'https://www.eslfast.com/feed/', category: 'Learner' },
  { title: 'Breaking News English (feed)', url: 'http://www.breakingnewsenglish.com/feed/', category: 'Learner' },
  { title: 'Culips ESL Podcast', url: 'https://feeds.megaphone.fm/culips', category: 'Learner' },
  { title: 'News in Levels (确认)', url: 'https://www.newsinlevels.com/feed/', category: 'Learner' },

  // Business（替代被墙的 Bloomberg/FT）
  { title: 'Forbes', url: 'https://www.forbes.com/feed/', category: 'Business' },
  { title: 'Business Insider', url: 'https://www.businessinsider.com/feed', category: 'Business' },
  { title: 'Quartz', url: 'https://qz.com/feed', category: 'Business' },
  { title: 'MarketWatch', url: 'https://www.marketwatch.com/rss', category: 'Business' },
  { title: 'Fortune', url: 'https://fortune.com/feed', category: 'Business' },
  { title: 'Rest of World', url: 'https://restofworld.org/feed/', category: 'Tech' },

  // Health / NPR 补充
  { title: 'NPR Health', url: 'https://feeds.npr.org/1025/rss.xml', category: 'Health' },
  { title: 'NPR Science', url: 'https://feeds.npr.org/1019/rss.xml', category: 'Science' },
  { title: 'NPR Technology', url: 'https://feeds.npr.org/1019/rss.xml', category: 'Tech' },
  { title: 'NPR World', url: 'https://feeds.npr.org/1004/rss.xml', category: 'News' },
  { title: 'The 19th', url: 'https://19thnews.org/feed/', category: 'News' },

  // Literature / 翻译文学（精读好素材）
  { title: 'Electric Literature', url: 'https://electricliterature.com/feed/', category: 'Literature' },
  { title: 'Words Without Borders', url: 'https://wordswithoutborders.org/feed/', category: 'Literature' },
  { title: 'The Millions', url: 'https://www.themillions.com/feed', category: 'Literature' },
  { title: 'Book Riot', url: 'https://bookriot.com/feed/', category: 'Books' },
  { title: 'Asymptote', url: 'https://www.asymptotejournal.com/feed/', category: 'Literature' },

  // Science 补充
  { title: 'Knowable', url: 'https://knowablemagazine.org/feed', category: 'Science' },
  { title: 'Undark', url: 'https://undark.org/feed/', category: 'Science' },
  { title: 'Anthropocene', url: 'https://www.anthropocenemagazine.org/feed/', category: 'Science' },
  { title: 'CACM', url: 'https://cacm.acm.org/feed/', category: 'Tech' },
  { title: 'IEEE Spectrum (rss)', url: 'https://spectrum.ieee.org/feeds/rss/', category: 'Tech' },
  { title: 'Hakai (确认)', url: 'https://hakaimagazine.com/feed/', category: 'Science' },

  // Ideas / Philosophy
  { title: 'Daily Nous', url: 'https://dailynous.com/feed/', category: 'Ideas' },
  { title: 'Big Think', url: 'https://bigthink.com/feed/', category: 'Ideas' },
  { title: 'Freakonomics', url: 'https://freakonomics.com/feed/', category: 'Ideas' },
  { title: 'The History Reader', url: 'https://www.thehistoryreader.com/feed/', category: 'History' },
  { title: 'History Today', url: 'https://www.historytoday.com/feed', category: 'History' },

  // 通用新闻补充（可达）
  { title: 'The Hill (确认)', url: 'https://thehill.com/feed/', category: 'News' },
  { title: 'TechCrunch (确认)', url: 'https://techcrunch.com/feed/', category: 'Tech' },
  { title: 'Works in Progress (确认)', url: 'https://www.worksinprogress.news/feed', category: 'Ideas' },
  { title: 'Asimov Press (确认)', url: 'https://www.asimov.press/feed', category: 'Science' },
  { title: 'Farnam Street (确认)', url: 'https://fs.blog/feed/', category: 'Ideas' },
  { title: '3 Quarks Daily (确认)', url: 'https://3quarksdaily.com/feed/', category: 'Ideas' },
  { title: 'Arts & Letters Daily (确认)', url: 'https://aldaily.com/feed/', category: 'Literature' },
  { title: 'The Paris Review (确认)', url: 'https://www.theparisreview.org/blog/feed/', category: 'Literature' },
]

async function check(c) {
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), 15000)
  try {
    const res = await fetch(c.url, {
      headers: { 'User-Agent': UA, Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*' },
      redirect: 'follow', signal: ctrl.signal,
    })
    clearTimeout(t)
    const text = await res.text()
    const ok = res.ok
    const looks = /<rss[\s>]|<feed[\s>]|<rdf:RDF/.test(text)
    const itemCount = (text.match(/<item[\s>]/g) || []).length + (text.match(/<entry[\s>]/g) || []).length
    return { ...c, status: res.status, ok, looks, itemCount, len: text.length }
  } catch (e) {
    clearTimeout(t)
    return { ...c, status: 'ERR', ok: false, looks: false, itemCount: 0, len: 0, err: e.name === 'AbortError' ? 'TIMEOUT' : e.message }
  }
}

for (const c of CANDIDATES) {
  const r = await check(c)
  const tag = r.ok && r.looks ? (r.itemCount > 0 ? 'OK ' : 'EMPTY') : 'FAIL'
  console.log(`[${tag}] ${r.title} | ${r.status} | items=${r.itemCount} | len=${r.len} | ${r.url}${r.err ? ' | ' + r.err : ''}`)
}
