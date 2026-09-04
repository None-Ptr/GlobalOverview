// AI 精选：把正文分句并全局编号，让模型返回「要删除的句子号」，本地按号重建 blocks。
//
// 设计约定（已与需求确认）：
//   - 目标 = 去噪（A 类）：广告/订阅引导/版权/作者 bio/分享引导/导流语句/页脚残留
//   - 图片块(type='img')不参与编号，永远保留
//   - 编号方案 = 全局连续 1..N，内部维护「句子号 -> 段落」映射，模型只回数字
//   - 不设删除上限；空结果/解析失败 = 未发现噪声，保留原文
//   - 输入安全阀 15000 字符：超出部分保留不送去判断（fail-open，内容不丢）

import { chat } from './llm.js'

// 输入安全阀。与出题不同，此处输出只有几十个数字（token 极少），
// 超时风险主要来自输入长度，故可以比 quiz.js 的 6000 宽松得多。
const MAX_CHARS = 15000

// 句末标点：与 article.vue 的 sentenceAround 保持同一套边界，避免两处切分不一致
const SENT_END = /[.!?。！？]/

const SYSTEM = `你是英文文章清洗助手。下面是一篇英文文章的句子，已按顺序编号。
请找出所有应当删除的"噪声"句子，只输出它们的编号。

需要删除的噪声包括：
- 广告、推广、赞助内容
- 订阅/邮件订阅引导（如 "Subscribe to..."、"Sign up for our newsletter"）
- 版权声明、转载声明、版权方信息
- 作者简介、作者联系方式、编辑署名
- 社交分享引导（如 "Share this on Twitter"、"Follow us on..."）
- "Read more"、"Continue reading"、"Click here" 等站内外导流语句
- 导航/菜单/页脚残留、相关阅读推荐列表
- 与正文主题无关的免责声明、Cookie 提示、广告披露

不要删除：正文论述、事实陈述、引语、例子、数据、结论、过渡句、小标题。

严格输出 JSON：{"drop":[1,5,9]}，不要解释、不要 markdown 代码块。
若没有需要删除的句子，输出 {"drop":[]}。`

/* ---------------- 切句 ---------------- */
// 返回 [{ start, end, text }]，text 为 trim 后的句子
export function splitSentences(text) {
  const out = []
  if (!text) return out
  const s = String(text)
  let start = 0
  for (let i = 0; i < s.length; i++) {
    if (!SENT_END.test(s[i])) continue
    // 吃掉连续结束标点（"..."、"?!" 等）
    let e = i + 1
    while (e < s.length && SENT_END.test(s[e])) e++
    const t = s.slice(start, e).trim()
    if (t) out.push({ start, end: e, text: t })
    start = e
    i = e - 1
  }
  if (start < s.length) {
    const tail = s.slice(start).trim()
    if (tail) out.push({ start, end: s.length, text: tail })
  }
  return out
}

/* ---------------- 全局连续编号 ---------------- */
// 仅对 type==='p' 的文本块分句编号；图片块跳过（永远保留）
export function numberBlocks(blocks) {
  const paras = [] // [{ blockIndex, sentences: [{ n, text }] }]
  let n = 0
  ;(blocks || []).forEach((b, blockIndex) => {
    if (!b || b.type !== 'p' || !b.text) return
    const sentences = splitSentences(b.text).map((s) => {
      n += 1
      return { n, text: s.text }
    })
    if (sentences.length) paras.push({ blockIndex, sentences })
  })
  return { paras, total: n }
}

/* ---------------- 构造送模型的编号文本 ---------------- */
// 超过 maxChars 后停止追加，超出部分保留不判断（fail-open）
function buildPromptPayload(paras, maxChars) {
  let used = 0
  let truncated = false
  const lines = []
  for (const g of paras) {
    for (const s of g.sentences) {
      const line = `${s.n}. ${s.text}`
      if (used + line.length + 1 > maxChars) { truncated = true; break }
      lines.push(line)
      used += line.length + 1
    }
    if (truncated) break
  }
  // 边界：首句本身就超过 maxChars 时上面一行都不会收录，导致 prompt 为空。
  // 至少收录第一句（截断到上限），保证模型有可判断的内容。
  if (!lines.length) {
    const first = paras[0].sentences[0]
    lines.push(`${first.n}. ${first.text}`.slice(0, maxChars))
    truncated = true
  }
  return { text: lines.join('\n'), truncated }
}

/* ---------------- 容错解析 ---------------- */
// 容忍 {"drop":[...]} / [1,2] / {"sentences":[...]}，丢弃越界与非数字
function normalizeDrop(res, total) {
  let arr = null
  if (Array.isArray(res)) arr = res
  else if (res && Array.isArray(res.drop)) arr = res.drop
  else if (res && Array.isArray(res.sentences)) arr = res.sentences
  if (!arr) return []
  const set = new Set()
  for (const v of arr) {
    const n = Number(v)
    if (!Number.isFinite(n)) continue
    const i = Math.trunc(n)
    if (i >= 1 && i <= total) set.add(i)
  }
  return Array.from(set).sort((a, b) => a - b)
}

/* ---------------- 按删除号重建 blocks ---------------- */
// 段落内剩余句子用空格重拼；整段被删空则移除该段；图片等非 p 块原位保留
export function applyDrops(blocks, paras, dropArr) {
  const drop = new Set(dropArr)
  const keptByBlock = {}
  for (const g of paras) {
    const kept = g.sentences.filter((s) => !drop.has(s.n)).map((s) => s.text)
    if (kept.length) keptByBlock[g.blockIndex] = kept.join(' ')
  }
  const out = []
  ;(blocks || []).forEach((b, i) => {
    if (b && b.type === 'p') {
      const kept = keptByBlock[i]
      // kept == null 表示该段未登记进 paras，只可能是 text 为空
      // （splitSentences 对非空文本至少返回尾段）。
      // 此前写作 `if (kept)` 会把这类段静默删除；但也不能无条件保留，
      // 否则空文本段落会渲染成一个空行。故：有内容原样保留（如无句末标点的短行），
      // 无内容直接丢弃。
      if (kept == null) {
        if (b.text && String(b.text).trim()) out.push(b)
        return
      }
      if (kept) out.push({ ...b, text: kept })
      return
    }
    out.push(b)
  })
  return out
}

// 由块序列派生纯文本（与 extract.js 的 plainText 形态一致：段落间空行）。
// 出题链路（quiz.js）消费的是 plainText，精选版需先转回纯文本再喂给它。
export function blocksToPlainText(blocks) {
  return (blocks || [])
    .filter((b) => b && b.type === 'p' && b.text)
    .map((b) => String(b.text).trim())
    .filter(Boolean)
    .join('\n\n')
}

// 解析精选块（DB 里是 JSON 串）；无内容返回 null
export function parseCurated(raw) {
  if (!raw) return null
  try {
    const bs = typeof raw === 'string' ? JSON.parse(raw) : raw
    return Array.isArray(bs) && bs.length ? bs : null
  } catch (e) {
    return null
  }
}

/* ---------------- 主流程 ---------------- */
// article: { id, title, blocks(数组或 JSON 串), plainText }
// 返回 { blocks, dropped, total, truncated }；dropped=0 表示未发现噪声
export async function curateArticle(article, profile) {
  if (!article) throw new Error('缺少文章')

  let blocks = article.blocks
  if (typeof blocks === 'string') {
    try { blocks = JSON.parse(blocks) } catch (e) { blocks = null }
  }
  if (!Array.isArray(blocks) || !blocks.length) {
    // 老数据兼容：无 blocks 时用 plainText 拆段
    blocks = String(article.plainText || '')
      .split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean)
      .map((t) => ({ type: 'p', text: t }))
  }
  if (!blocks.length) throw new Error('正文为空，无法精选')

  const { paras, total } = numberBlocks(blocks)
  if (!total) throw new Error('正文无句子，无法精选')

  const { text, truncated } = buildPromptPayload(paras, MAX_CHARS)

  const res = await chat(profile, [
    { role: 'system', content: SYSTEM },
    { role: 'user', content: `文章标题：${article.title || '（无）'}\n\n${text}` },
  ], { json: true, temperature: 0 })

  const drop = normalizeDrop(res, total)
  if (!drop.length) {
    return { blocks: null, dropped: 0, total, truncated }
  }
  return { blocks: applyDrops(blocks, paras, drop), dropped: drop.length, total, truncated }
}
