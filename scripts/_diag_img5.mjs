// 深入诊断：Ars/Wired 为何抽不出图片
import { JSDOM } from 'jsdom'
globalThis.DOMParser = new JSDOM().window.DOMParser
// 模拟 extract.js 的 parseDocument 需要的环境
import { readFileSync } from 'node:fs'
// 直接读 extract.js 源码，手动复现它的抽取逻辑
const src = readFileSync('d:/OI/Projects/GlobalOverview/src/utils/extract.js', 'utf8')

// 用 jsdom 建一个可用的 document
const dom = new JSDOM('<!DOCTYPE html>')
globalThis.document = dom.window.document
globalThis.DOMParser = dom.window.DOMParser

// 提取 extract.js 里的 absUrl / isContentImage / stripUiNoise
function absUrl(u, base) {
  try { return new URL(u, base).href } catch (e) { return u }
}
function isContentImage(src, tagHtml) {
  if (!src) return false
  if (src.startsWith('data:image/gif;base64,R0lGOD')) return false
  if (/^(#|javascript:)/i.test(src)) return false
  if (/\b(icon|logo|pixel|spacer|tracking|badge|sprite|avatar|favicon|apple-touch-icon)\b/i.test(src)) return false
  if (/\bwidth=["']?\s*(1|2|3|4|5|6|7|8|9|10|1[0-5])\b/i.test(tagHtml || '')) return false
  if (/\.(css|js|html?|json|xml|svg|woff2?|ttf|eot|mp[34]|pdf)(\?|$)/i.test(src)) return false
  return true
}

async function fetchText(url) {
  const r = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' } })
  if (!r.ok) throw new Error('HTTP ' + r.status)
  return r.text()
}

const article = await fetchText('https://arstechnica.com/health/2026/08/us-vaccination-rates-are-at-a-new-low-heres-what-it-takes-to-stop-the-fall/')
console.log('article length:', article.length)

// 分析正文区域的 img 标签
const body = article.match(/<body[^>]*>[\s\S]*<\/body>/i)?.[0] || ''
const imgTags = [...body.matchAll(/<img\b[^>]*>/gi)].slice(0, 15)
console.log('\nimg tags found:', imgTags.length)
for (const it of imgTags.slice(0, 10)) {
  const tag = it[0]
  const hasSrc = /\bsrc\s*=/.test(tag)
  const hasSrcset = /\bsrcset\s*=/.test(tag)
  const hasDataSrc = /\bdata-src\s*=/.test(tag)
  const srcMatch = tag.match(/\bsrc\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i)
  const s = srcMatch ? (srcMatch[2] || srcMatch[3] || srcMatch[4] || '') : ''
  console.log(`  src=${hasSrc} srcset=${hasSrcset} data-src=${hasDataSrc} val="${s.slice(0, 60)}"`)
}
// 是否 picture / source
console.log('\npicture tags:', (body.match(/<picture/gi) || []).length, ' source tags:', (body.match(/<source/gi) || []).length)
