// 第六轮扫描：专攻 纯「每日一词」/ 词汇 / 词源 / ESL 词汇 类源
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
const CANDIDATES = [
  // 词源 / 词汇（中小站，非 Cloudflare）
  { title: 'World Wide Words', url: 'https://www.worldwidewords.org/feed/', category: 'Learner' },
  { title: 'World Wide Words (rss)', url: 'https://www.worldwidewords.org/rss.xml', category: 'Learner' },
  { title: 'Online Etymology Dictionary', url: 'https://www.etymonline.com/feed/rss', category: 'Learner' },
  { title: 'Online Etymology (atom)', url: 'https://www.etymonline.com/feed/atom', category: 'Learner' },
  { title: 'A Word A Day (wordsmith alt)', url: 'https://wordsmith.org/awad/', category: 'Learner' },
  { title: 'Wordnik API WOTD', url: 'https://api.wordnik.com/v4/words.json/wordOfTheDay', category: 'Learner' },
  { title: 'The Free Dictionary WOTD (alt)', url: 'https://www.thefreedictionary.com/_/WoD/rss/wotd-def.xml', category: 'Learner' },

  // ESL 词汇 / 学习站
  { title: 'UsingEnglish', url: 'https://www.usingenglish.com/feed/', category: 'Learner' },
  { title: 'Espresso English', url: 'https://www.espressoenglish.net/feed/', category: 'Learner' },
  { title: 'engVid', url: 'https://www.engvid.com/feed/', category: 'Learner' },
  { title: 'English for Students', url: 'https://www.englishforstudents.com/feed/', category: 'Learner' },
  { title: 'FluentU Blog', url: 'https://www.fluentu.com/blog/english/feed/', category: 'Learner' },
  { title: 'Antimoon', url: 'https://www.antimoon.com/feed/', category: 'Learner' },
  { title: 'Vocabulary.co.il', url: 'https://www.vocabulary.co.il/feed/', category: 'Learner' },
  { title: 'LearnEnglish.de', url: 'https://www.learnenglish.de/feed/', category: 'Learner' },
  { title: 'TalkEnglish', url: 'https://www.talkenglish.com/feed/', category: 'Learner' },
  { title: 'Grammar Monster', url: 'https://www.grammar-monster.com/feed/', category: 'Learner' },
  { title: 'English Leap', url: 'https://www.englishleap.com/feed/', category: 'Learner' },
  { title: 'Daily Grammar', url: 'https://www.dailygrammar.com/feed/', category: 'Learner' },
  { title: 'Cambridge Dictionary (learn)', url: 'https://www.cambridge.org/us/education/feed', category: 'Learner' },
  { title: 'Urban Dictionary', url: 'https://www.urbandictionary.com/feed', category: 'Learner' },
  { title: 'YourDictionary WOTD', url: 'https://www.yourdictionary.com/word-of-the-day.rss', category: 'Learner' },
  { title: 'ThoughtCo Word', url: 'https://www.thoughtco.com/word-of-the-day-4133589.rss', category: 'Learner' },
  { title: 'Oxford Lexico', url: 'https://www.lexico.com/en/feed', category: 'Learner' },
  { title: 'Macquarie Word of the Week', url: 'https://www.macquariedictionary.com.au/rss/feed/word-of-the-week', category: 'Learner' },
  { title: 'A Way with Words', url: 'https://www.awaywithwords.com/feed/', category: 'Learner' },
  { title: 'Sporcle WOTD', url: 'https://www.sporcle.com/rss', category: 'Learner' },
  { title: 'Dictionary.com (feedburner)', url: 'https://feeds.feedburner.com/Dictionarycom', category: 'Learner' },
  { title: 'MW WOTD (feedburner)', url: 'https://feeds.feedburner.com/MerriamWebsterWordOfTheDay', category: 'Learner' },
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
