// 第四轮扫描：补齐缺口（体育/旅行/教育/政策智库/词汇类）+ 原失败源其它路径
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
const CANDIDATES = [
  // ===== 体育 Sports =====
  { title: 'NPR Sports', url: 'https://feeds.npr.org/1042/rss.xml', category: 'Sports' },
  { title: 'Sky Sports', url: 'https://www.skysports.com/rss/12040', category: 'Sports' },
  { title: 'SB Nation', url: 'https://www.sbnation.com/rss/index.xml', category: 'Sports' },
  { title: 'Yahoo Sports', url: 'https://sports.yahoo.com/rss/', category: 'Sports' },
  { title: 'Bleacher Report', url: 'https://bleacherreport.com/rss.xml', category: 'Sports' },
  { title: 'Sports Illustrated', url: 'https://www.si.com/rss/si-top-stories.rss', category: 'Sports' },
  { title: 'Runner\'s World', url: 'https://www.runnersworld.com/feed/', category: 'Sports' },
  { title: 'CyclingTips', url: 'https://www.cyclingtips.com/feed/', category: 'Sports' },
  { title: 'ESPN (retry)', url: 'https://www.espn.com/espn/rss/news', category: 'Sports' },

  // ===== 旅行 Travel =====
  { title: 'AFAR', url: 'https://www.afar.com/feed', category: 'Travel' },
  { title: 'Conde Nast Traveler', url: 'https://www.cntraveler.com/feed', category: 'Travel' },
  { title: 'Travel + Leisure', url: 'https://www.travelandleisure.com/feed', category: 'Travel' },
  { title: 'Skift', url: 'https://skift.com/feed/', category: 'Travel' },
  { title: 'Wanderlust', url: 'https://www.wanderlust.co.uk/feed/', category: 'Travel' },
  { title: 'Fodor\'s', url: 'https://www.fodors.com/features/rss/all.xml', category: 'Travel' },
  { title: 'Thrillist', url: 'https://www.thrillist.com/feed', category: 'Travel' },
  { title: 'Matador Network', url: 'https://matadornetwork.com/feed/', category: 'Travel' },
  { title: 'Atlas Obscura (retry)', url: 'https://www.atlasobscura.com/feed', category: 'Travel' },

  // ===== 教育 Education =====
  { title: 'NPR Education', url: 'https://feeds.npr.org/1012/rss.xml', category: 'Education' },
  { title: 'EdSurge', url: 'https://www.edsurge.com/feed.xml', category: 'Education' },
  { title: 'Inside Higher Ed', url: 'https://www.insidehighered.com/rss.xml', category: 'Education' },
  { title: 'The Hechinger Report', url: 'https://hechingerreport.org/feed/', category: 'Education' },
  { title: 'We Are Teachers', url: 'https://www.weareteachers.com/feed/', category: 'Education' },
  { title: 'eSchool News', url: 'https://www.eschoolnews.com/feed/', category: 'Education' },
  { title: 'Higher Ed Dive', url: 'https://www.highereddive.com/feeds/news/', category: 'Education' },
  { title: 'KQED MindShift', url: 'https://ww2.kqed.org/mindshift/feed/', category: 'Education' },

  // ===== 政策智库 Policy / Think Tank =====
  { title: 'Cato Institute', url: 'https://www.cato.org/feed', category: 'Policy' },
  { title: 'Heritage Foundation', url: 'https://www.heritage.org/feed', category: 'Policy' },
  { title: 'PIIE', url: 'https://www.piie.com/rss.xml', category: 'Policy' },
  { title: 'Hudson Institute', url: 'https://www.hudson.org/rss', category: 'Policy' },
  { title: 'Carnegie', url: 'https://carnegieendowment.org/rss', category: 'Policy' },
  { title: 'CSIS', url: 'https://www.csis.org/rss.xml', category: 'Policy' },
  { title: 'Chatham House', url: 'https://www.chathamhouse.org/rss', category: 'Policy' },
  { title: 'IMF Blog', url: 'https://www.imf.org/en/Blogs/atom.xml', category: 'Policy' },
  { title: 'World Bank', url: 'https://blogs.worldbank.org/rss.xml', category: 'Policy' },
  { title: 'Bruegel', url: 'https://www.bruegel.org/rss.xml', category: 'Policy' },
  { title: 'Wilson Center', url: 'https://www.wilsoncenter.org/rss', category: 'Policy' },
  { title: 'Aspen Institute', url: 'https://www.aspeninstitute.org/feed/', category: 'Policy' },

  // ===== 词汇 / 学习者 Vocabulary / Learner =====
  { title: 'Vocabulary.com', url: 'https://www.vocabulary.com/feed/', category: 'Learner' },
  { title: 'Macmillan BuzzWord', url: 'https://www.macmillandictionary.com/rss/buzzword.xml', category: 'Learner' },
  { title: 'Collins Word of the Day', url: 'https://www.collinsdictionary.com/word-of-the-day/rss', category: 'Learner' },
  { title: 'The Free Dictionary WOTD', url: 'https://www.thefreedictionary.com/_/WoD/rss/wotd.xml', category: 'Learner' },
  { title: 'Daily Writing Tips', url: 'https://www.dailywritingtips.com/feed/', category: 'Learner' },
  { title: 'English Club', url: 'https://www.englishclub.com/feed/', category: 'Learner' },
  { title: 'Oxford English Learning', url: 'https://www.oxfordlearnersdictionaries.com/feed/', category: 'Learner' },
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
