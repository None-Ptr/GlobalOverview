// 验证多个真实源的图片 URL 可加载性（GET，带 UA），判断是普遍问题还是个别源
import { JSDOM } from 'jsdom'
globalThis.DOMParser = new JSDOM().window.DOMParser
import { extractArticle } from '../src/utils/extract.js'

const UA = 'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36'

async function fetchText(url) {
  const r = await fetch(url, { headers: { 'User-Agent': UA } })
  if (!r.ok) throw new Error('HTTP ' + r.status)
  return r.text()
}

async function getImgs(feedUrl) {
  const html = await fetchText(feedUrl)
  const item = (html.match(/<item>[\s\S]*?<\/item>/) || [])[0]
  if (!item) return null
  const link = (item.match(/<link[^>]*>([^<]+)<\/link>/) || [])[1]
  if (!link) return null
  const articleHtml = await fetchText(link.trim())
  const { blocks } = extractArticle(articleHtml, link.trim())
  return { link: link.trim(), imgs: blocks.filter((b) => b.type === 'img') }
}

async function probeImg(url) {
  try {
    const r = await fetch(url, { method: 'GET', redirect: 'follow', headers: { 'User-Agent': UA, 'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8' } })
    const ct = r.headers.get('content-type') || ''
    const ok = ct.startsWith('image/')
    return { status: r.status, image: ok, ct: ct.slice(0, 25) }
  } catch (e) {
    return { status: 'ERR', image: false, ct: e.message.slice(0, 25) }
  }
}

const feeds = [
  ['NPR', 'https://feeds.npr.org/1001/rss.xml'],
  ['Ars', 'https://feeds.arstechnica.com/arstechnica/index'],
  ['Verge', 'https://www.theverge.com/rss/index.xml'],
  ['Wired', 'https://www.wired.com/feed/rss'],
  ['Nature', 'https://www.nature.com/nature.rss'],
  ['HackerNews', 'https://news.ycombinator.com/rss'],
  ['ScienceDaily', 'https://www.sciencedaily.com/rss/top/science.xml'],
]

for (const [name, url] of feeds) {
  let got = null
  try { got = await getImgs(url) } catch (e) { console.log(`${name}: feed/article fail ${e.message}`); continue }
  if (!got) { console.log(`${name}: no item`); continue }
  console.log(`\n${name} (${got.link.slice(0, 50)}) imgs=${got.imgs.length}`)
  for (const img of got.imgs.slice(0, 3)) {
    const p = await probeImg(img.src)
    console.log(`  [${p.status} ${p.image ? 'IMG' : p.ct}] ${img.src.slice(0, 80)}`)
  }
}
