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

export async function fetchFeed(url) {
  const xml = await fetchText(url)
  if (!xml || !xml.trim()) throw new Error('订阅源返回空内容')
  const json = parser.parse(xml)
  const channel = (json.rss && json.rss.channel) || json.feed || json
  if (!channel) throw new Error('无法解析订阅源格式')
  const rawItems = asArray(channel.item || channel.entry || [])
  const items = rawItems.map((it) => {
    const guid = toText(it.guid || it.id) || toText(it.link)
    const link = typeof it.link === 'string' ? it.link : (it.link?.['@_href'] || toText(it.link))
    const encoded = it['content:encoded'] || it.content || it.summary || it.description || ''
    return {
      guid,
      title: toText(it.title),
      link,
      preview: stripTags(toText(encoded)).slice(0, 240),
      pubDate: it.pubDate ? Date.parse(it.pubDate) || 0 : 0,
    }
  })
  return { title: toText(channel.title), items }
}
