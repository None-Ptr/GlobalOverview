// 本机网络环境 RSS 源可达性 + 有效性扫描
// 用法: node scripts/scan_rss.mjs
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'

const CANDIDATES = [
  // ===== 现有内置 27 个（复核） =====
  { title: 'NPR News', url: 'https://feeds.npr.org/1001/rss.xml', category: 'News' },
  { title: 'NPR Books', url: 'https://feeds.npr.org/1032/rss.xml', category: 'Books' },
  { title: 'NPR TED', url: 'https://feeds.npr.org/1054/rss.xml', category: 'Ideas' },
  { title: 'France24 English', url: 'https://www.france24.com/en/rss', category: 'News' },
  { title: 'Sky News World', url: 'https://feeds.skynews.com/feeds/rss/world.xml', category: 'News' },
  { title: 'CNBC Top', url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114', category: 'Business' },
  { title: 'Scientific American', url: 'https://www.scientificamerican.com/feed/', category: 'Science' },
  { title: 'Nature', url: 'https://www.nature.com/nature.rss', category: 'Science' },
  { title: 'Quanta', url: 'https://www.quantamagazine.org/feed/', category: 'Science' },
  { title: 'New Scientist', url: 'https://www.newscientist.com/feed/', category: 'Science' },
  { title: 'The Verge', url: 'https://www.theverge.com/rss/index.xml', category: 'Tech' },
  { title: 'Ars Technica', url: 'http://feeds.arstechnica.com/arstechnica/index', category: 'Tech' },
  { title: 'Wired', url: 'https://www.wired.com/feed/rss', category: 'Tech' },
  { title: 'Hacker News', url: 'https://hnrss.org/frontpage', category: 'Tech' },
  { title: 'Engadget', url: 'https://www.engadget.com/rss.xml', category: 'Tech' },
  { title: 'MIT Tech Review', url: 'https://www.technologyreview.com/feed/', category: 'Tech' },
  { title: 'Smashing Magazine', url: 'https://www.smashingmagazine.com/feed/', category: 'Design' },
  { title: 'Literary Hub', url: 'https://lithub.com/feed/', category: 'Books' },
  { title: 'Wait But Why', url: 'https://waitbutwhy.com/feed', category: 'Ideas' },
  { title: 'Lifehacker', url: 'https://lifehacker.com/rss', category: 'Life' },
  { title: 'Aeon', url: 'https://aeon.co/feed', category: 'Ideas' },
  { title: 'Psyche', url: 'https://psyche.co/feed', category: 'Ideas' },
  { title: 'Nautilus', url: 'https://nautil.us/feed/', category: 'Science' },
  { title: 'Longreads', url: 'https://longreads.com/feed/', category: 'Literature' },
  { title: 'Brain Pickings', url: 'https://www.brainpickings.org/feed/', category: 'Books' },
  { title: 'Stratechery', url: 'https://stratechery.com/feed/', category: 'Tech' },

  // ===== 学习者 / 分级英文源 =====
  { title: 'VOA Learning English (feed)', url: 'https://learningenglish.voanews.com/feed/', category: 'Learner' },
  { title: 'VOA LE Let\'s Learn English', url: 'https://learningenglish.voanews.com/podcast/lets-learn-english/feed/', category: 'Learner' },
  { title: 'VOA LE English In A Minute', url: 'https://learningenglish.voanews.com/podcast/english-in-a-minute/feed/', category: 'Learner' },
  { title: 'News in Levels', url: 'https://www.newsinlevels.com/feed/', category: 'Learner' },
  { title: 'English in Levels', url: 'https://www.englishinlevels.com/feed/', category: 'Learner' },
  { title: 'ESL News Stories', url: 'https://eslnewsstories.com/feed/', category: 'Learner' },
  { title: 'Breaking News English', url: 'http://www.breakingnewsenglish.com/index.xml', category: 'Learner' },
  { title: 'TED Blog', url: 'https://blog.ted.com/feed/', category: 'Ideas' },
  { title: 'TED Ideas', url: 'https://ideas.ted.com/feed/', category: 'Ideas' },
  { title: 'British Council Learn English', url: 'https://learnenglish.britishcouncil.org/feed', category: 'Learner' },
  { title: 'ManyThings', url: 'https://www.manythings.org/feed/', category: 'Learner' },

  // ===== 更多优质英文源（综合/深度阅读） =====
  { title: 'The Atlantic', url: 'https://www.theatlantic.com/feed/all/', category: 'News' },
  { title: 'Financial Times', url: 'https://www.ft.com/rss/home', category: 'Business' },
  { title: 'Washington Post National', url: 'https://feeds.washingtonpost.com/rss/national', category: 'News' },
  { title: 'New Yorker News', url: 'https://www.newyorker.com/feed/news', category: 'News' },
  { title: 'Bloomberg Markets', url: 'https://feeds.bloomberg.com/markets/news.rss', category: 'Business' },
  { title: 'Time', url: 'https://time.com/feed/', category: 'News' },
  { title: 'Newsweek', url: 'https://www.newsweek.com/rss', category: 'News' },
  { title: 'USA Today Top', url: 'https://rss.usatoday.com/usatoday-NewsTopStories', category: 'News' },
  { title: 'LA Times', url: 'https://www.latimes.com/rss/topstory', category: 'News' },
  { title: 'Smithsonian', url: 'https://www.smithsonianmag.com/rss/', category: 'Science' },
  { title: 'National Geographic', url: 'https://www.nationalgeographic.com/feed/', category: 'Science' },
  { title: 'Atlas Obscura', url: 'https://www.atlasobscura.com/feed', category: 'Travel' },
  { title: 'History.com', url: 'https://www.history.com/.rss/full/', category: 'History' },
  { title: 'IEEE Spectrum', url: 'https://spectrum.ieee.org/feeds/atom.xml', category: 'Tech' },
  { title: 'Space.com', url: 'https://www.space.com/feeds/all', category: 'Science' },
  { title: 'Live Science', url: 'https://www.livescience.com/feeds/all', category: 'Science' },
  { title: 'Popular Science', url: 'https://www.popsci.com/feed/', category: 'Science' },
  { title: 'Discover', url: 'https://www.discovermagazine.com/feed', category: 'Science' },
  { title: 'Science Daily', url: 'https://www.sciencedaily.com/rss/all.xml', category: 'Science' },
  { title: 'Psychology Today', url: 'https://www.psychologytoday.com/us/blog/rss', category: 'Science' },
  { title: 'Poetry Foundation', url: 'https://www.poetryfoundation.org/feed', category: 'Literature' },
  { title: 'The Conversation US', url: 'https://theconversation.com/us/feed', category: 'Ideas' },
  { title: 'Hakai Magazine', url: 'https://hakaimagazine.com/feed/', category: 'Science' },
  { title: 'The Browser', url: 'https://thebrowser.com/feed/', category: 'Ideas' },
  { title: 'Arts & Letters Daily', url: 'https://aldaily.com/feed/', category: 'Literature' },
  { title: '3 Quarks Daily', url: 'https://3quarksdaily.com/feed/', category: 'Ideas' },
  { title: 'Marginal Revolution', url: 'https://marginalrevolution.com/feed/', category: 'Ideas' },
  { title: 'Farnam Street', url: 'https://fs.blog/feed/', category: 'Ideas' },
  { title: 'Vox', url: 'https://www.vox.com/rss/index.xml', category: 'News' },
  { title: 'Politico', url: 'https://www.politico.com/rss/politics.xml', category: 'News' },
  { title: 'The Hill', url: 'https://thehill.com/feed/', category: 'News' },
  { title: 'Reason', url: 'https://reason.com/feed/', category: 'News' },
  { title: 'Lapham\'s Quarterly', url: 'https://www.laphamsquarterly.org/feed', category: 'Literature' },
  { title: 'The Paris Review', url: 'https://www.theparisreview.org/blog/feed/', category: 'Literature' },
  { title: 'Granta', url: 'https://granta.com/feed/', category: 'Literature' },
  { title: 'Orion Magazine', url: 'https://orionmagazine.org/feed/', category: 'Literature' },
  { title: 'Works in Progress', url: 'https://www.worksinprogress.news/feed', category: 'Ideas' },
  { title: 'Asimov Press', url: 'https://www.asimov.press/feed', category: 'Science' },
  { title: 'Slate', url: 'https://feeds.slate.com/feed/abc', category: 'News' },
  { title: 'TechCrunch', url: 'https://techcrunch.com/feed/', category: 'Tech' },
  { title: 'The New York Review of Books', url: 'https://www.nybooks.com/rss/', category: 'Books' },
  { title: 'Commonweal', url: 'https://www.commonwealmagazine.org/feed', category: 'Ideas' },
]

async function check(c) {
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), 15000)
  try {
    const res = await fetch(c.url, {
      headers: { 'User-Agent': UA, Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*' },
      redirect: 'follow',
      signal: ctrl.signal,
    })
    clearTimeout(t)
    const text = await res.text()
    const ok = res.ok
    const looks = /<rss[\s>]|<feed[\s>]|<rdf:RDF/.test(text)
    const itemCount = (text.match(/<item[\s>]/g) || []).length + (text.match(/<entry[\s>]/g) || []).length
    return { ...c, status: res.status, ok, looks, itemCount, len: text.length, final: res.url }
  } catch (e) {
    clearTimeout(t)
    return { ...c, status: 'ERR', ok: false, looks: false, itemCount: 0, len: 0, err: e.name === 'AbortError' ? 'TIMEOUT' : e.message }
  }
}

const results = []
for (const c of CANDIDATES) {
  const r = await check(c)
  const tag = r.ok && r.looks ? (r.itemCount > 0 ? 'OK ' : 'EMPTY') : 'FAIL'
  console.log(`[${tag}] ${r.title} | ${r.status} | items=${r.itemCount} | len=${r.len} | ${r.url}${r.err ? ' | ' + r.err : ''}`)
  results.push({ ...r, tag })
}
const okList = results.filter((r) => r.tag === 'OK')
console.log('\n=== 可达且有效 (' + okList.length + ') ===')
for (const r of okList) console.log(`${r.category}\t${r.title}\t${r.url}`)
