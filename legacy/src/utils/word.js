import { db } from './db.js'
import { getProfiles, chat } from './llm.js'
import { lemmaOf } from './vocab.js'
import { request } from './http.js'
import { translate } from './translate.js'

const { sqlVal } = db

const EN2EN_API = 'https://api.dictionaryapi.dev/api/v2/entries/en/'

export function normalizeQuery(text) {
  return String(text || '')
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
}

/** 判断是单词还是短语/句子 */
export function queryKind(text) {
  const t = normalizeQuery(text)
  if (!t) return 'empty'
  const words = t.split(/\s+/).filter(Boolean)
  if (words.length === 1 && /^[A-Za-z][A-Za-z'-]*$/.test(words[0])) return 'word'
  return 'phrase'
}

async function cacheGet(key, mode) {
  await db.init()
  const rows = await db.select(`SELECT result FROM word_cache WHERE word = ${sqlVal(key)} AND mode = ${sqlVal(mode)} LIMIT 1`)
  if (!rows || !rows.length) return null
  try { return JSON.parse(rows[0].result) } catch (e) { return null }
}

async function cachePut(key, mode, result, lemma) {
  await db.init()
  await db.execute(
    'INSERT OR REPLACE INTO word_cache (word, mode, result, at, lemma) VALUES ('
    + `${sqlVal(key)}, ${sqlVal(mode)}, ${sqlVal(JSON.stringify(result))}, ${sqlVal(Date.now())}, ${sqlVal(lemma || null)})`
  )
}

async function fetchEn2En(word) {
  const res = await request({ url: EN2EN_API + encodeURIComponent(word), method: 'GET' })
  if (res.statusCode === 404) throw new Error('词典中未收录该词')
  if (res.statusCode < 200 || res.statusCode >= 300) throw new Error(`词典服务异常（${res.statusCode}）`)
  const data = typeof res.data === 'string' ? JSON.parse(res.data) : res.data
  if (!Array.isArray(data) || !data.length) throw new Error('词典返回为空')
  return normalizeDictResult(data)
}

function normalizeDictResult(data) {
  const first = data[0]
  const phonetic = first.phonetic
    || (first.phonetics || []).map((p) => p.text).filter(Boolean)[0]
    || ''
  const senses = []
  for (const entry of data) {
    for (const m of entry.meanings || []) {
      for (const d of (m.definitions || []).slice(0, 3)) {
        senses.push({
          pos: m.partOfSpeech || '',
          definition: d.definition || '',
          example: d.example || '',
        })
      }
    }
  }
  return { kind: 'dict', word: first.word || '', phonetic, senses: senses.slice(0, 6) }
}

function pickProfile(llmConfig) {
  if (llmConfig) return llmConfig
  const list = getProfiles()
  return list && list.length ? list[0] : null
}

// dictionaryapi.dev 返回英文词性标签，统一映射为词典惯例缩写
const POS_ZH = {
  noun: 'n.', verb: 'v.', adjective: 'adj.', adverb: 'adv.',
  pronoun: 'pron.', preposition: 'prep.', conjunction: 'conj.',
  interjection: 'int.', exclamation: 'int.', determiner: 'det.',
  numeral: 'num.', article: 'art.', particle: 'part.', auxiliary: 'aux.',
}
function posAbbr(pos) {
  return POS_ZH[String(pos || '').toLowerCase()] || pos || ''
}

// 无 LLM 时的富释义路径：词典结构（音标 + 词性 + 多义项）+ 翻译引擎批量译出
// 中文释义，组合成结构化词卡，避免「整词翻译只回一个中文词」的信息损失。
async function fetchEn2ZhByDict(word) {
  const dict = await fetchEn2En(word)
  let zhDefs = []
  try {
    // 全部释义用换行拼成单块一次翻译（百度 QPS=1，逐条翻译会触发频率限制）；
    // translate() 按空行分块，单个换行保持在同一块内，引擎一般按行保留
    const joined = await translate(dict.senses.map((s) => s.definition).join('\n'), { target: 'ZH' })
    zhDefs = String(joined).split(/\n+/).map((s) => s.trim()).filter(Boolean)
  } catch (e) { zhDefs = [] }
  // 行数对不上（引擎合并/拆行）时保留英文释义——音标/词性/多义项结构仍在
  const aligned = zhDefs.length === dict.senses.length
  const senses = dict.senses.map((s, i) => ({
    pos: posAbbr(s.pos),
    definition: aligned ? zhDefs[i] : s.definition,
    example: s.example,
  }))
  return { kind: 'dict', word: dict.word || word, phonetic: dict.phonetic, senses }
}

async function fetchEn2Zh(word, llmConfig) {
  const profile = pickProfile(llmConfig)
  if (profile) {
    try {
      const text = await chat(profile, [{
        role: 'user',
        content: `用简洁中文解释英文单词「${word}」：给出音标（若可知）、词性、1-3 个常用释义、1 个例句。只输出纯文本，不要 markdown。`,
      }], { json: false, temperature: 0.3 })
      return { kind: 'text', word, text: String(text).trim() }
    } catch (e) {}
  }
  try {
    return await fetchEn2ZhByDict(word)
  } catch (e) {
    // 词典未收录/服务异常：退化为整词翻译，保证任何情况下都有结果
    const text = await translate(word, { target: 'ZH' })
    return { kind: 'text', word, text: String(text).trim() }
  }
}

async function fetchPhraseByLLM(phrase, context, llmConfig) {
  const profile = pickProfile(llmConfig)
  if (profile) {
    try {
      const ctx = context && context !== phrase
        ? `\n\n所在句子（仅作理解参考，不要翻译整句）：${String(context).slice(0, 400)}`
        : ''
      const text = await chat(profile, [{
        role: 'user',
        content: `请用中文解析这段英文：「${phrase}」${ctx}\n\n`
          + '按以下顺序输出纯文本，不要 markdown、不要编号以外的修饰：\n'
          + '1. 中文翻译\n2. 关键词汇（最多 3 个，格式：词 — 释义）\n3. 语法/固定搭配要点（一句话，没有就写「无」）',
      }], { json: false, temperature: 0.3 })
      return { kind: 'phrase', word: phrase, text: String(text).trim() }
    } catch (e) {}
  }
  const text = await translate(phrase, { target: 'ZH' })
  return { kind: 'phrase', word: phrase, text: String(text).trim() }
}

/**
 * 统一查询入口。
 * @param text 单词或选区短语
 * @param mode 'en2zh' | 'en2en'
 * @param llmConfig 可选 profile
 * @param context 选区所在句子，用于短语解析
 */
export async function lookupWord(text, mode = 'en2zh', llmConfig = null, context = '') {
  const q = normalizeQuery(text)
  if (!q) throw new Error('没有可查询的内容')

  const kind = queryKind(q)
  const cacheMode = kind === 'phrase' ? 'phrase' : mode
  const cacheKey = kind === 'phrase' ? q.toLowerCase() : q.toLowerCase()

  const cached = await cacheGet(cacheKey, cacheMode)
  if (cached) return cached

  let result
  if (kind === 'phrase') {
    result = await fetchPhraseByLLM(q, context, llmConfig)
  } else if (mode === 'en2en') {
    result = await fetchEn2En(q)
  } else {
    result = await fetchEn2Zh(q, llmConfig)
  }

  const lemma = kind === 'phrase' ? null : lemmaOf(q)
  await cachePut(cacheKey, cacheMode, result, lemma).catch(() => {})
  return result
}

export async function loadWordCache(limit = 200) {
  await db.init()
  const rows = await db.select(`SELECT word, mode, result, at, lemma FROM word_cache ORDER BY at DESC LIMIT ${Number(limit) || 200}`)
  return (rows || []).map((r) => {
    let parsed = null
    try { parsed = JSON.parse(r.result) } catch (e) { parsed = null }
    return { word: r.word, mode: r.mode, at: r.at, lemma: r.lemma, result: parsed }
  })
}

export async function removeWordCache(word, mode) {
  await db.init()
  await db.execute(`DELETE FROM word_cache WHERE word = ${sqlVal(word)} AND mode = ${sqlVal(mode)}`)
}

export async function clearWordCache() {
  await db.init()
  await db.execute('DELETE FROM word_cache')
}
