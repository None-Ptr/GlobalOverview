import { XMLParser } from 'fast-xml-parser'
import { fetchText } from './http.js'

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  textNodeName: '#text',
})

function asArray(v) {
  if (v == null) return []
  return Array.isArray(v) ? v : [v]
}

function toText(node) {
  if (node == null) return ''
  if (typeof node === 'string') return node
  if (typeof node === 'object') return node['#text'] || ''
  return String(node)
}

function stripTags(html) {
  if (!html) return ''
  return html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim()
}

const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' }
function decodeEntities(s) {
  if (typeof s !== 'string' || !s.includes('&')) return s
  return s.replace(/&([a-z]+|#\d+|#x[0-9a-f]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
      return isNaN(code) ? m : String.fromCodePoint(code)
    }
    return ENT[e.toLowerCase()] != null ? ENT[e.toLowerCase()] : m
  })
}

function getLink(node) {
  if (node == null) return ''
  if (typeof node === 'string') return node
  if (Array.isArray(node)) {
    for (const n of node) {
      const v = getLink(n)
      if (v) return v
    }
    return ''
  }
  if (typeof node === 'object') {
    if (node['@_href']) return node['@_href']
    if (node['#text']) return node['#text']
    return ''
  }
  return String(node)
}

export async function fetchFeed(url) {
  // 防御历史脏数据：数据库里可能存了 HTML 实体转义的 URL（&amp; → &）
  const cleanUrl = String(url || '').replace(/&amp;/gi, '&').trim()
  if (!cleanUrl) throw new Error('订阅源 URL 为空')
  const xml = await fetchText(cleanUrl)
  if (typeof xml !== 'string' || !xml.trim()) throw new Error('订阅源返回空内容')
  const json = parser.parse(xml)
  // RSS 2.0: <rss><channel><item>…；Atom: <feed><entry>…；
  // RSS 1.0/RDF: <rdf:RDF> 下 <channel> 与 <item> 平级（如 Nature）。
  const root = json.rss || json.feed || json['rdf:RDF'] || json
  const channel = root.channel || root
  if (!channel) throw new Error('无法解析订阅源格式')
  const rawItems = asArray(
    channel.item || root.item || channel.entry || root.entry || []
  )
  const items = rawItems.map((it) => {
    const guid = toText(it.guid || it.id) || toText(it.link) || ('__' + toText(it.title)) || ''
    const link = getLink(it.link)
    const encoded = it['content:encoded'] || it.content || it.summary || it.description || ''
    return {
      guid,
      title: decodeEntities(toText(it.title)),
      link,
      preview: decodeEntities(stripTags(toText(encoded))).slice(0, 240),
      pubDate: it.pubDate ? Date.parse(it.pubDate) || 0 : 0,
    }
  })
  return { title: decodeEntities(toText(channel.title)), items }
}
