// 第五轮扫描：专攻 词汇/语法 缺口 + 补充 旅行/教育/政策
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
const CANDIDATES = [
  // 词汇 / 语法（英语训练核心缺口）
  { title: 'Wordsmith A Word A Day', url: 'https://wordsmith.org/awad/rss.xml', category: 'Learner' },
  { title: 'Wordnik', url: 'https://www.wordnik.com/rss.xml', category: 'Learner' },
  { title: 'Grammar Girl', url: 'https://www.quickanddirtytips.com/grammar-girl/feed', category: 'Learner' },
  { title: 'The Word Detective', url: 'http://www.word-detective.com/feed/', category: 'Learner' },
  { title: 'Writing Excuses', url: 'https://writingexcuses.com/feed/', category: 'Learner' },
  { title: 'OUP Blog (Oxford)', url: 'https://blog.oup.com/feed/', category: 'Learner' },
  { title: 'Vocabulary.com WOTD', url: 'https://www.vocabulary.com/rss.xml', category: 'Learner' },
  { title: 'Macmillan Dictionary blog', url: 'https://www.macmillandictionary.com/rss/', category: 'Learner' },

  // 旅行补充
  { title: 'Rough Guides', url: 'https://www.roughguides.com/feed/', category: 'Travel' },
  { title: 'Lonely Planet alt', url: 'https://www.lonelyplanet.com/feed', category: 'Travel' },

  // 教育补充（K-12）
  { title: 'TeachThought', url: 'https://www.teachthought.com/feed/', category: 'Education' },
  { title: 'Cult of Pedagogy', url: 'https://www.cultofpedagogy.com/feed/', category: 'Education' },

  // 政策补充
  { title: 'Project Syndicate', url: 'https://www.project-syndicate.org/rss', category: 'Policy' },
  { title: 'AEI', url: 'https://www.aei.org/feed/', category: 'Policy' },
  { title: 'Hoover Institution', url: 'https://www.hoover.org/feed', category: 'Policy' },
  { title: 'Lowy Institute', url: 'https://www.lowyinstitute.org/feed', category: 'Policy' },
  { title: 'Center for Strategic and Budgetary', url: 'https://csbaonline.org/feed', category: 'Policy' },
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
