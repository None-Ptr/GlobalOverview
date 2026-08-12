// 正文管线：@mozilla/readability 抽取正文（依赖浏览器 DOM）
// 5+App WebView / 浏览器运行时自带 document + DOMParser；
// 非浏览器环境（node 测试 / App 内未暴露 DOMParser 时）用 linkedom（parse5 系）注入 DOMParser。

import { Readability } from '@mozilla/readability'
import { parseHTML } from 'linkedom'

// 解析环境若没有全局 DOMParser，则用 linkedom（基于 parse5）提供标准 DOM 实现
if (typeof DOMParser === 'undefined') {
  globalThis.DOMParser = class {
    parseFromString(html, _mime) {
      const { document } = parseHTML(html)
      return document
    }
  }
}

function parseDocument(html) {
  if (typeof DOMParser === 'undefined') {
    throw new Error('当前环境无 DOMParser，无法运行 Readability（App/浏览器/已注入 linkedom 均可）')
  }
  return new DOMParser().parseFromString(html, 'text/html')
}

// 把相对 URL 解析为绝对地址（基于文章页 baseUrl）
function absUrl(src, base) {
  if (!src || !base) return src || ''
  try { return new URL(src, base).href } catch (e) { return src }
}

// 过滤明显非内容图：占位/icon/像素/跟踪
function isContentImage(src, tagHtml) {
  if (!src) return false
  if (src.startsWith('data:image/gif;base64,R0lGOD')) return false
  if (/\b(icon|logo|pixel|spacer|tracking|badge)\b/i.test(src)) return false
  if (/\bwidth=["']?\s*(1|2|3|4|5|6|7|8|9|10|1[0-5])\b/i.test(tagHtml || '')) return false
  return /\.(jpg|jpeg|png|webp|gif|avif|bmp)(\?|$)/i.test(src)
}

// 过滤 CMS 图片说明控件的 UI 文本（如 hide caption / toggle caption / show caption），
// 这些不是正文内容，会污染阅读器和单词统计。
const UI_CAPTION_RE = /\b(hide|toggle|show)\s+caption\b/gi
function stripUiNoise(text) {
  return text.replace(UI_CAPTION_RE, '').trim()
}

export function extractArticle(html, baseUrl) {
  const doc = parseDocument(String(html == null ? '' : html))
  const article = new Readability(doc).parse()
  if (!article) {
    return { html: '', plainText: '', wordCount: 0, blocks: [] }
  }
  const content = article.content || ''

  // 保留段落结构：遍历块级元素，用双换行分隔各块，块内空白压成单空格。
  // 若直接 textContent.replace(/\s+/g,' ') 会把全篇压成一段，导致阅读器无法分段、
  // 长按选区误选整篇。
  let plainText = ''
  const blocks = []
  if (article.documentElement) {
    const nodes = article.documentElement.querySelectorAll('p, div, h1, h2, h3, h4, h5, h6, li, blockquote')
    nodes.forEach((el) => {
      // 直接子 <img> 单独成块（Readability 有时把图放到 p 里）
      const childImgs = Array.from(el.children || []).filter((c) => c.tagName === 'IMG')
      const t = stripUiNoise((el.textContent || '').replace(/\s+/g, ' ').trim())
      if (t) {
        plainText += t + '\n\n'
        blocks.push({ type: 'p', text: t })
      }
      childImgs.forEach((img) => {
        const src = absUrl(img.getAttribute('src') || img.getAttribute('data-src') || '', baseUrl)
        if (isContentImage(src, img.outerHTML)) {
          const a = img.getAttribute('alt') || ''
          plainText += '\n\n' // 图片不计入纯文本，但保留段间空白
          blocks.push({ type: 'img', src, alt: a })
        }
      })
    })
  }
  if (!plainText.trim()) {
    // 兜底：无块级结构时直接取全文（仍保留段落分隔）
    plainText = stripUiNoise((article.textContent || '').replace(/[ \t]+/g, ' ').replace(/\n{2,}/g, '\n\n').trim())
  }
  plainText = plainText.replace(/\n{3,}/g, '\n\n').trim()

  // 若遍历未产出图片块（结构异常），从 content 中兜底抽取一次
  if (!blocks.some((b) => b.type === 'img')) {
    const imgRe = /<img\b[^>]*>/gi
    let mm
    while ((mm = imgRe.exec(content)) !== null) {
      const tag = mm[0]
      const srcMatch = tag.match(/\bsrc\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i)
      const srcRaw = srcMatch ? (srcMatch[2] || srcMatch[3] || srcMatch[4] || '') : ''
      const altMatch = tag.match(/\balt\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i)
      const altRaw = altMatch ? (altMatch[2] || altMatch[3] || altMatch[4] || '') : ''
      const src = absUrl(srcRaw.trim(), baseUrl)
      if (isContentImage(src, tag)) {
        blocks.push({ type: 'img', src, alt: altRaw.trim() })
      }
    }
  }

  const wordCount = (plainText.match(/[A-Za-z]+/g) || []).length
  return { html: content, plainText, wordCount, blocks }
}
