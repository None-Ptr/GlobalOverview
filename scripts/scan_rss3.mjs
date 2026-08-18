// 第三轮扫描：补齐缺失类别（编程/环境/食物/艺术/智库/历史/医学/语言写作/数学/媒体/数据/体育/教育/旅行/哲学）
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
const CANDIDATES = [
  // 编程 / 开发
  { title: 'Dev.to', url: 'https://dev.to/feed', category: 'Tech' },
  { title: 'freeCodeCamp', url: 'https://www.freecodecamp.org/news/rss/', category: 'Tech' },
  { title: 'HackerNoon', url: 'https://hackernoon.com/feed', category: 'Tech' },
  { title: 'CSS-Tricks', url: 'https://css-tricks.com/feed/', category: 'Design' },
  { title: 'InfoQ', url: 'https://feed.infoq.com/', category: 'Tech' },
  { title: 'The Practical Dev', url: 'https://dev.to/feed', category: 'Tech' },

  // 环境 / 气候
  { title: 'Inside Climate News', url: 'https://insideclimatenews.org/feed/', category: 'Environment' },
  { title: 'Yale Environment 360', url: 'https://e360.yale.edu/feed', category: 'Environment' },
  { title: 'Grist', url: 'https://grist.org/feed/', category: 'Environment' },
  { title: 'Mongabay', url: 'https://news.mongabay.com/feed/', category: 'Environment' },
  { title: 'Carbon Brief', url: 'https://www.carbonbrief.org/feed/', category: 'Environment' },

  // 食物 / 烹饪
  { title: 'Serious Eats', url: 'https://www.seriouseats.com/feeds/human.xml', category: 'Food' },
  { title: 'Eater', url: 'https://www.eater.com/rss/index.xml', category: 'Food' },
  { title: 'Bon Appétit', url: 'https://www.bonappetit.com/feed/rss', category: 'Food' },

  // 艺术 / 设计
  { title: 'Hyperallergic', url: 'https://hyperallergic.com/feed/', category: 'Art' },
  { title: 'The Art Newspaper', url: 'https://www.theartnewspaper.com/rss', category: 'Art' },
  { title: 'Colossal', url: 'https://www.thisiscolossal.com/feed/', category: 'Art' },
  { title: 'Design Milk', url: 'https://design-milk.com/feed/', category: 'Design' },

  // 智库 / 经济 / 政策
  { title: 'Brookings', url: 'https://www.brookings.edu/feed/', category: 'Policy' },
  { title: 'RAND', url: 'https://www.rand.org/feed', category: 'Policy' },
  { title: 'Council on Foreign Relations', url: 'https://www.cfr.org/rss/index.xml', category: 'Policy' },

  // 历史
  { title: 'JSTOR Daily', url: 'https://daily.jstor.org/feed/', category: 'History' },
  { title: 'HistoryExtra', url: 'https://www.historyextra.com/feed/', category: 'History' },

  // 医学 / 健康
  { title: 'STAT', url: 'https://www.statnews.com/feed/', category: 'Health' },
  { title: 'Medical News Today', url: 'https://www.medicalnewstoday.com/rss', category: 'Health' },

  // 语言 / 写作（英语阅读训练强相关）
  { title: 'Merriam-Webster Word of the Day', url: 'https://www.merriam-webster.com/wotd/feed/rss', category: 'Learner' },
  { title: 'Grammarly Blog', url: 'https://www.grammarly.com/blog/feed/', category: 'Learner' },
  { title: 'Dictionary.com Word of the Day', url: 'https://www.dictionary.com/wordoftheday/feed/', category: 'Learner' },
  { title: 'The Write Practice', url: 'https://thewritepractice.com/feed/', category: 'Learner' },
  { title: 'Open Culture', url: 'https://www.openculture.com/feed', category: 'Learner' },

  // 数学 / 科普
  { title: 'Plus Magazine', url: 'https://plus.maths.org/feed', category: 'Science' },
  { title: 'Quanta (确认)', url: 'https://www.quantamagazine.org/feed/', category: 'Science' },

  // 媒体 / 新闻业
  { title: 'Columbia Journalism Review', url: 'https://www.cjr.org/feed', category: 'Media' },
  { title: 'Nieman Lab', url: 'https://www.niemanlab.org/feed/', category: 'Media' },

  // 数据
  { title: 'Our World in Data', url: 'https://ourworldindata.org/feed', category: 'Data' },

  // 体育
  { title: 'The Ringer', url: 'https://www.theringer.com/feed', category: 'Sports' },
  { title: 'FiveThirtyEight', url: 'https://fivethirtyeight.com/feeds/podcast/', category: 'Sports' },

  // 教育
  { title: 'Edutopia', url: 'https://www.edutopia.org/rss.xml', category: 'Education' },
  { title: 'Khan Academy', url: 'https://www.khanacademy.org/api/v1/talks/rss', category: 'Education' },

  // 旅行
  { title: 'Lonely Planet', url: 'https://www.lonelyplanet.com/feed/', category: 'Travel' },

  // 哲学 / 文化补充
  { title: 'Noema', url: 'https://www.noemamag.com/feed/', category: 'Ideas' },
  { title: 'The Point', url: 'https://thepointmag.com/feed/', category: 'Ideas' },
  { title: 'Cabinet', url: 'https://www.cabinetmagazine.org/feed/', category: 'Ideas' },
  { title: 'Inverse', url: 'https://www.inverse.com/feed', category: 'Science' },
  { title: 'Popular Mechanics', url: 'https://www.popularmechanics.com/feed/', category: 'Science' },
  { title: 'Mental Floss', url: 'https://www.mentalfloss.com/feed', category: 'Ideas' },
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
