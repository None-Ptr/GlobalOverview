// 正文管线：@mozilla/readability 抽取正文（依赖浏览器 DOM）

import { Readability } from '@mozilla/readability'
import { parseHTML } from 'linkedom'

// 部分旧 webview（尤其 Android 低版本）缺少 Array.prototype.at，
// 而 Readability / linkedom 内部会用到它，导致抓取时报 .at is not a function。
if (!Array.prototype.at) {
  Array.prototype.at = function (n) {
    const len = this.length
    let i = Number.isNaN(n) ? 0 : Math.trunc(n) || 0
    if (i < 0) i += len
    return i >= 0 && i < len ? this[i] : undefined
  }
}

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

function absUrl(src, base) {
  if (!src || !base) return src || ''
  try { return new URL(src, base).href } catch (e) { return src }
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

const UI_CAPTION_RE = /\b(hide|toggle|show)\s+caption\b/gi
function stripUiNoise(text) {
  return text.replace(UI_CAPTION_RE, '').trim()
}

// 后处理：把 Readability 输出的粘连文本修复为可阅读的正文。
// 1) 在「小写|大写」与「数字|大写」边界插入空格（"PROSubscribe" -> "PRO Subscribe"），
//    缓解 CMS footer/nav 把链接列表拼成连续文本丢失词边界的现象。
// 2) 过滤明显的 footer/nav 段落：包含版权/sitemap/条款/广告等强信号的行。
function postProcess(text) {
  if (!text) return text
  let out = text.replace(/([a-z])([A-Z])/g, '$1 $2')
  out = out.replace(/(\d)([A-Z][a-z])/g, '$1 $2')
  const outLines = []
  for (const line of out.split(/\n/)) {
    if (looksLikeFooterLine(line)) continue
    outLines.push(line)
  }
  return outLines.join('\n').replace(/\n{3,}/g, '\n\n').trim()
}

function looksLikeFooterLine(line) {
  const t = line.trim()
  if (!t) return false
  // 行长守卫：真正的页脚/版权/订阅行都很短。当整篇正文因 fallback 被压成单行时，
  // 正文中间出现的 "newsletter"/"subscribe" 等词会命中关键字——若不限长，整行正文会被
  // 误当页脚整段删除，导致"篇幅太短"。长行一律视为正文，不做页脚过滤。
  if (t.length > 120) return false
  if (/\b(copyright|©|all rights reserved|privacy policy|terms of service|cookie|sitemap|newsletter|advertise|subscriptions?)\b/i.test(t)) return true
  if (/^(all rights|your privacy|data is|market data|terms of|about|contact|careers|help|advertise with)/i.test(t)) return true
  return false
}

export function extractArticle(html, baseUrl) {
  const rawHtml = String(html == null ? '' : html)
  const doc = parseDocument(rawHtml)

  // Readability 在解析某些极简/异常 HTML（如 Hacker News）时会访问到 null 节点，
  // 直接抛出 "Cannot read property 'tagName' of null"。外层捕获后降级为原始 HTML 抽取。
  let parsed = null
  try {
    parsed = new Readability(doc).parse()
  } catch (e) {
    // eslint-disable-next-line no-console
    console.warn('[extractArticle] Readability failed:', e && e.message)
  }

  let article
  if (parsed) {
    article = parsed
    // @mozilla/readability 的 parse() 返回值不含 documentElement（它只是构造参数）。
    // 若缺 documentElement，后续逐段 block 抽取会被整体跳过、退化为单行 textContent。
    // 这里用 Readability 产出的 content HTML 重建文档片段，恢复真实段落结构。
    if (!article.documentElement && article.content) {
      try {
        const contentDoc = parseDocument(article.content)
        article.documentElement = contentDoc.body || contentDoc.documentElement || null
      } catch (e) {
        article.documentElement = null
      }
    }
  } else {
    const root = doc.documentElement
    article = {
      content: rawHtml,
      documentElement: root,
      textContent: ((doc.body && doc.body.textContent) || (root && root.textContent) || '').trim(),
      title: doc.title || '',
    }
  }
  const content = article.content || ''

  let plainText = ''
  const blocks = []
  if (article.documentElement) {
    const nodes = article.documentElement.querySelectorAll('p, div, h1, h2, h3, h4, h5, h6, li, blockquote, picture, figure')
    nodes.forEach((el) => {
      if (!el || !el.tagName) return

      const collectImg = (img) => {
        if (!img || !img.tagName || img.tagName !== 'IMG') return null
        const srcset = img.getAttribute('srcset') || img.getAttribute('data-srcset') || ''
        let best = ''
        if (srcset) {
          const parts = srcset.split(',').map((s) => s.trim()).filter(Boolean)
          for (const p of parts) { const u = p.split(/\s+/)[0]; if (u) best = u }
        }
        const raw = best || img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('src') || ''
        return { src: absUrl(raw, baseUrl), alt: img.getAttribute('alt') || '' }
      }

      const childImgs = Array.from(el.children || []).filter((c) => c && c.tagName === 'IMG')
      const t = stripUiNoise((el.textContent || '').replace(/\s+/g, ' ').trim())
      if (t) {
        plainText += t + '\n\n'
        blocks.push({ type: 'p', text: t })
      }
      childImgs.forEach((img) => {
        const got = collectImg(img)
        if (got && isContentImage(got.src, img.outerHTML)) {
          plainText += '\n\n'
          blocks.push({ type: 'img', src: got.src, alt: got.alt })
        }
      })

      if (el.tagName === 'PICTURE') {
        const sources = Array.from(el.querySelectorAll('source[srcset]'))
        for (const s of sources) {
          if (!s || !s.tagName || s.tagName !== 'SOURCE') continue
          const ss = s.getAttribute('srcset') || ''
          let best = ''
          if (ss) {
            const parts = ss.split(',').map((x) => x.trim()).filter(Boolean)
            for (const p of parts) { const u = p.split(/\s+/)[0]; if (u) best = u }
          }
          if (best) {
            const src = absUrl(best, baseUrl)
            if (isContentImage(src, s.outerHTML)) {
              plainText += '\n\n'
              blocks.push({ type: 'img', src, alt: '' })
              break
            }
          }
        }
      }
    })
  }
  if (!plainText.trim()) {
    plainText = stripUiNoise((article.textContent || '').replace(/[ \t]+/g, ' ').replace(/\n{2,}/g, '\n\n').trim())
  }
  plainText = postProcess(plainText.replace(/\n{3,}/g, '\n\n').trim())

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
