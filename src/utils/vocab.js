// 个人语料库 / 词族归并 / 语境回溯 / FSRS 间隔复习 的单一数据源。
// 设计原则：纯本地、离线可用；查询缓存(word_cache) ≠ 个人语料库(vocab_*)，二者解耦。

import { db } from './db.js'
import { getProfiles, chat, parseJsonLoose } from './llm.js'

const { sqlVal } = db

// 新词首次复习间隔：查词后不「即时到期」（避免读文章当下就被淹没），
// 但也不拖到次日——改为 10~60 分钟内错峰到期，保证「复习」页当天就有内容可刷。
const FSRS_NEW_FIRST_MIN = 10 * 60 * 1000      // 最短 10 分钟（明显晚于查词当下）
const FSRS_NEW_FIRST_SPREAD = 50 * 60 * 1000   // 在最短基础上再错峰 0~50 分钟
// 旧生词分 30 天错峰到期（按原始查词时间取模），避免首开词汇中心即出现海量待复习。
const FSRS_LEGACY_SPREAD_DAYS = 30

// 新词首复习到期时间：以 head 做稳定哈希，在 [MIN, MIN+SPREAD] 内错峰，避免全部同时到期。
function firstDueFor(head, now) {
  let h = 0
  const s = String(head || '')
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0
  const jitter = ((h % 100) / 100) * FSRS_NEW_FIRST_SPREAD
  return now + FSRS_NEW_FIRST_MIN + jitter
}

// ───────────────────────── 词族离线归并（规则档） ─────────────────────────

const IRREGULAR = {
  // be
  was: 'be', were: 'be', is: 'be', am: 'be', are: 'be', been: 'be', being: 'be',
  // go
  went: 'go', goes: 'go', gone: 'go', going: 'go',
  // do
  did: 'do', does: 'do', done: 'do', doing: 'do',
  // have
  had: 'have', has: 'have', having: 'have',
  // eat
  ate: 'eat', eaten: 'eat', eats: 'eat', eating: 'eat',
  // see
  saw: 'see', seen: 'see', sees: 'see', seeing: 'see',
  // take
  took: 'take', taken: 'take', takes: 'take', taking: 'take',
  // give
  gave: 'give', given: 'give', gives: 'give', giving: 'give',
  // get
  got: 'get', gotten: 'get', gets: 'get', getting: 'get',
  // make
  made: 'make', makes: 'make', making: 'make',
  // come
  came: 'come', comes: 'come', coming: 'come',
  // think
  thought: 'think', thinks: 'think', thinking: 'think',
  // say
  said: 'say', says: 'say', saying: 'say',
  // know
  knew: 'know', known: 'know', knows: 'know', knowing: 'know',
  // fall
  fell: 'fall', fallen: 'fall', falls: 'fall', falling: 'fall',
  // feel
  felt: 'feel', feels: 'feel', feeling: 'feel',
  // leave
  left: 'leave', leaves: 'leave', leaving: 'leave',
  // mean
  meant: 'mean', means: 'mean', meaning: 'mean',
  // meet
  met: 'meet', meets: 'meet', meeting: 'meet',
  // pay
  paid: 'pay', pays: 'pay', paying: 'pay',
  // sell
  sold: 'sell', sells: 'sell', selling: 'sell',
  // tell
  told: 'tell', tells: 'tell', telling: 'tell',
  // win
  won: 'win', wins: 'win', winning: 'win',
  // write
  wrote: 'write', written: 'write', writes: 'write', writing: 'write',
  // drive
  drove: 'drive', driven: 'drive', drives: 'drive', driving: 'drive',
  // ride
  rode: 'ride', ridden: 'ride', rides: 'ride', riding: 'ride',
  // speak
  spoke: 'speak', spoken: 'speak', speaks: 'speak', speaking: 'speak',
  // break
  broke: 'break', broken: 'break', breaks: 'break', breaking: 'break',
  // choose
  chose: 'choose', chosen: 'choose', chooses: 'choose', choosing: 'choose',
  // freeze
  froze: 'freeze', frozen: 'freeze', freezes: 'freeze', freezing: 'freeze',
  // forget
  forgot: 'forget', forgotten: 'forget', forgets: 'forget', forgetting: 'forget',
}

// 后缀剥离（顺序敏感：ies/ves 须在 s 之前）
const SUFFIX = [
  [/(?:ies)$/, 'y'],   // countries → country
  [/(?:ves)$/, 'f'],   // leaves → leaf
  [/(?:es)$/, ''],     // watches → watch
  [/(?:ed)$/, ''],
  [/(?:ing)$/, ''],
  [/(?:ly)$/, ''],
  [/(?:ness)$/, ''],
  [/(?:ful)$/, ''],
  [/(?:ous)$/, ''],
  [/(?:ive)$/, ''],
  [/(?:s)$/, ''],
]

export function lemmaOf(t) {
  const w = String(t || '')
    .toLowerCase()
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
  if (!w) return w
  if (IRREGULAR[w]) return IRREGULAR[w]
  for (const [re, rep] of SUFFIX) {
    if (re.test(w)) {
      const m = w.replace(re, rep)
      if (m.length >= 3) return m
    }
  }
  return w
}

// ───────────────────────── 写入：查词锚点 + 词族 head ─────────────────────────

// 阅读器查词成功时调用（isQuiz 下不调用）。把当前出处写入 vocab_occ，并聚合 vocab_head。
export async function saveOccurrence({ word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex }) {
  const head = lemma || lemmaOf(word)
  const now = Date.now()
  await db.init()
  // 仅当本次是「新的真实出处」时才让 occCount +1，避免首次落库即 +1、重复点同一词被错误累加
  const headRows = await db.select(`SELECT 1 AS e FROM vocab_head WHERE head = ${sqlVal(head)} LIMIT 1`)
  const headRowsExisting = !!(headRows && headRows.length)
  const occRows = await db.select(
    `SELECT 1 AS e FROM vocab_occ
     WHERE word = ${sqlVal(word)} AND articleGuid = ${sqlVal(articleGuid)}
       AND paraIndex = ${sqlVal(paraIndex)} AND tokIndex = ${sqlVal(tokIndex)} LIMIT 1`
  )
  const occExisting = !!(occRows && occRows.length)
  if (!headRowsExisting) {
    await db.execute(
      `INSERT INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due)
       VALUES (${sqlVal(head)}, 'word', ${sqlVal(now)}, ${sqlVal(now)}, 1, 0, ${sqlVal(firstDueFor(head, now))})`
    )
  } else if (!occExisting) {
    await db.execute(
      `UPDATE vocab_head SET occCount = occCount + 1, lastSeen = ${sqlVal(now)} WHERE head = ${sqlVal(head)}`
    )
  } else {
    await db.execute(
      `UPDATE vocab_head SET lastSeen = ${sqlVal(now)} WHERE head = ${sqlVal(head)}`
    )
  }
  await db.execute(
    `INSERT OR IGNORE INTO vocab_occ (word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at)
     VALUES (${sqlVal(word)}, ${sqlVal(head)}, ${sqlVal(articleGuid)}, ${sqlVal(articleTitle)}, ${sqlVal(sourceLabel)},
       ${sqlVal(sentence)}, ${sqlVal(paraIndex)}, ${sqlVal(tokIndex)}, ${sqlVal(now)})`
  )
  // 查询过的句子即「收藏」：去重沉淀到 vocab_sentence，供 LLM 语法/语块拆解
  if (sentence) {
    await db.execute(
      `INSERT OR IGNORE INTO vocab_sentence (sentence, articleGuid, articleTitle, sourceLabel, paraIndex, tokIndex, at)
       VALUES (${sqlVal(sentence)}, ${sqlVal(articleGuid)}, ${sqlVal(articleTitle)}, ${sqlVal(sourceLabel)},
         ${sqlVal(paraIndex)}, ${sqlVal(tokIndex)}, ${sqlVal(now)})`
    )
  }
}

// ───────────────────────── 读取 ─────────────────────────

// 取某词的全部出处（语境回溯用）。word 可能是任意形态，自动归并到 lemma。
export async function getOccurrence(word) {
  const head = lemmaOf(word)
  await db.init()
  return await db.select(
    `SELECT articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at
     FROM vocab_occ WHERE lemma = ${sqlVal(head)} ORDER BY at DESC`
  )
}

// 把历史 word_cache 词同步进 vocab_head（幂等），避免旧生词丢失。
// 旧数据无 vocab_occ 锚点，回溯时走详情浮层（符合"旧生词不补全锚点"）。
// 关键：旧生词按原始查词时间分 30 天错峰到期，避免首开词汇中心即淹没"待复习"。
export async function syncHeadsFromCache() {
  await db.init()
  const now = Date.now()
  // 清理脏数据：之前把整句/整段（选区查询、长文本翻译）也错误地同步成 head
  await db.execute(
    `DELETE FROM vocab_head WHERE length(head) > 80 OR length(head) - length(replace(head, ' ', '')) > 5`
  )
  // 只把真正的单词/短词同步成 head：排除 phrase（整句/选区翻译）和明显过长的文本
  const rows = await db.select(
    `SELECT word, lemma, at, mode FROM word_cache
     WHERE word IS NOT NULL AND mode IN ('en2zh', 'en2en')
       AND length(word) <= 80
       AND length(word) - length(replace(word, ' ', '')) <= 5`
  ) || []
  if (rows.length) {
    const existing = await db.select(`SELECT head FROM vocab_head`) || []
    const have = new Set(existing.map((e) => e.head))
    for (const r of rows) {
      const head = (r.lemma && String(r.lemma)) || String(r.word).toLowerCase()
      if (!head || have.has(head)) continue
      have.add(head)
      const days = Math.abs(Math.floor(Number(r.at) / 86400000)) % FSRS_LEGACY_SPREAD_DAYS
      const due = now + days * 86400000
      await db.execute(
        `INSERT OR IGNORE INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due)
         VALUES (${sqlVal(head)}, 'word', ${sqlVal(now)}, ${sqlVal(now)}, 1, 0, ${sqlVal(due)})`
      )
    }
  }
  // 回正：此前新词被推迟 24h 到期，导致「复习」页长期为空。
  // 把所有「从未复习(state=0)且到期远超近期窗口」的 head 重新错峰到 10~60 分钟内，
  // 让存量数据立刻有内容；已复习过(state>0)的合法远到期卡片不动。
  const horizon = now + FSRS_NEW_FIRST_MIN + FSRS_NEW_FIRST_SPREAD
  const dead = await db.select(
    `SELECT head FROM vocab_head WHERE fsrs_state = 0 AND fsrs_due > ${sqlVal(horizon)}`
  ) || []
  for (const r of dead) {
    await db.execute(
      `UPDATE vocab_head SET fsrs_due = ${sqlVal(firstDueFor(r.head, now))} WHERE head = ${sqlVal(r.head)}`
    )
  }
}

// 词族 head 列表（词汇中心主列表源）
export async function getHeads() {
  await db.init()
  return await db.select(
    `SELECT head, kind, firstSeen, lastSeen, occCount, family, fsrs_state, fsrs_due
     FROM vocab_head ORDER BY lastSeen DESC`
  )
}

// 待复习卡片数（首页/词汇中心展示用）
export async function getDueCount() {
  await db.init()
  const now = Date.now()
  const rows = await db.select(`SELECT COUNT(*) AS n FROM vocab_head WHERE fsrs_due <= ${sqlVal(now)}`)
  return (rows && rows[0] && rows[0].n) || 0
}

// 待复习卡片（FSRS 调度）
export async function getDueCards(limit = 50) {
  await db.init()
  const now = Date.now()
  return await db.select(
    `SELECT head, fsrs_state, fsrs_due, fsrs_s, fsrs_d
     FROM vocab_head WHERE fsrs_due <= ${sqlVal(now)} ORDER BY fsrs_due ASC LIMIT ${sqlVal(limit)}`
  )
}

// 收藏的句子（= 查询过的句子，去重沉淀于 vocab_sentence）
export async function getSentences() {
  await db.init()
  return await db.select(
    `SELECT sentence, articleTitle, sourceLabel, paraIndex, tokIndex, at, analysis
     FROM vocab_sentence ORDER BY at DESC`
  ) || []
}

export async function setSentenceAnalysis(sentence, analysis) {
  await db.init()
  await db.execute(
    `UPDATE vocab_sentence SET analysis = ${sqlVal(analysis)} WHERE sentence = ${sqlVal(sentence)}`
  )
}

// 对收藏句子调用用户已配置 LLM 做语法/语块拆解（锁定 JSON Schema，默认开启）
export async function llmAnalyzeSentence(sentence) {
  const { getProfiles, chat } = await import('./llm.js')
  const profiles = getProfiles()
  if (!profiles || !profiles.length) throw new Error('未配置 LLM')
  const sys = `你是英语语法与语块分析助手。只输出对象，不要解释、不要 markdown。结构：
{
  "translation": "整句自然中文翻译",
  "chunks": [ {"text":"语块原文","type":"phrase|clause|idiom|fixed","note":"这个语块的意思/作用"} ],
  "grammar": [ {"point":"语法点(时态/语态/从句/非谓语等)","explain":"一句话说明"} ],
  "keywords": [ {"word":"重点词","pos":"词性","zh":"中文释义"} ]
}`
  const user = `请拆解并分析这句话：\n${sentence}`
  const res = await chat(profiles[0], [
    { role: 'system', content: sys },
    { role: 'user', content: user },
  ], { json: true, temperature: 0.3 })
  if (!res) throw new Error('LLM 无返回')
  const parsed = parseJsonLoose(res)
  if (!parsed || typeof parsed !== 'object') throw new Error('拆解结果解析失败')
  const data = {
    translation: parsed.translation || '',
    chunks: Array.isArray(parsed.chunks) ? parsed.chunks : [],
    grammar: Array.isArray(parsed.grammar) ? parsed.grammar : [],
    keywords: Array.isArray(parsed.keywords) ? parsed.keywords : [],
  }
  await setSentenceAnalysis(sentence, JSON.stringify(data))
  return data
}

// ───────────────────────── FSRS 间隔重复（简化内核） ─────────────────────────
// 以稳定性 S(天) + 难度 D(1..10) 驱动间隔。冷启动用官方推荐初值 S=1天 D=5。
// grade: 1=忘了 2=模糊 3=记得 4=轻松
const DAY = 86400000
function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)) }

export function fsrsNext(state, s, d, grade, now) {
  const D = d && d > 0 ? d : 5
  const S = s && s > 0 ? s : DAY
  const newD = clamp(D + (grade - 3) * 0.8, 1, 10)
  let newState, newS
  if (grade >= 3) {
    // 成功
    if (state === 0 || !s) {
      newS = (grade === 4 ? 3.0 : 1.5) * DAY
    } else {
      const g = grade === 4 ? 2.6 : 1.8
      newS = S * (1 + g * (1 + (10 - D) / 10))
      newS = Math.max(newS, S * g)
    }
    newState = newS >= 21 * DAY ? 2 : 1
  } else {
    // 失败（忘了/模糊）-> 重新学习
    newState = 3
    newS = Math.max(S * (grade === 2 ? 0.5 : 0.2), 0.2 * DAY)
  }
  return {
    state: newState,
    due: Math.round(now + newS),
    s: Math.round(newS),
    d: Math.round(newD * 100) / 100,
  }
}

// 评分一次，更新 vocab_head 的 FSRS 状态
export async function scheduleReview(head, grade) {
  await db.init()
  const rows = await db.select(
    `SELECT fsrs_state, fsrs_s, fsrs_d FROM vocab_head WHERE head = ${sqlVal(head)} LIMIT 1`
  )
  const cur = rows && rows[0] ? rows[0] : { fsrs_state: 0, fsrs_s: 0, fsrs_d: 5 }
  const next = fsrsNext(cur.fsrs_state, cur.fsrs_s, cur.fsrs_d, grade, Date.now())
  await db.execute(
    `UPDATE vocab_head
     SET fsrs_state = ${sqlVal(next.state)}, fsrs_due = ${sqlVal(next.due)},
         fsrs_s = ${sqlVal(next.s)}, fsrs_d = ${sqlVal(next.d)}, lastSeen = ${sqlVal(Date.now())}
     WHERE head = ${sqlVal(head)}`
  )
  return next
}

// ───────────────────────── AI 整理（默认开启，词族自动归集） ─────────────────────────

// words: [{ word, mode, result }]，来自 loadWordCache。
// 返回锁定 Schema：{ groups: [{ theme, items: [{ word, lemma, pos, zh, en, family, example }] }] }
export async function llmOrganize(words) {
  const profiles = getProfiles()
  if (!profiles || !profiles.length) {
    throw new Error('未配置 LLM，请先到「我的」页面添加模型配置')
  }
  const list = (words || []).map((w) => {
    let hint = ''
    const r = w.result
    if (r) {
      if (r.kind === 'dict') hint = (r.phonetic || '') + ' ' + (r.senses || []).map((s) => s.definition).join('; ')
      else if (r.text) hint = String(r.text).slice(0, 140)
    }
    return { word: w.word, mode: w.mode, hint }
  })
  const prompt = `你是一个英语词汇整理助手。下面是一批用户在阅读中查询过的生词（JSON 数组，含 word / mode / hint，hint 是该词已有的释义片段，可能为空）。
请按主题将生词聚类分组，并为每个词补全：lemma（词族原形小写）、pos（词性缩写，如 n./v./adj.）、zh（中文释义）、en（英文释义）、family（常见形态数组，含自身，如 ["emit","emits","emitted","emitting","emission"]）、example（一个地道英文例句）。
只输出如下 JSON，不要任何 markdown 或解释：
{"groups":[{"theme":"...","items":[{"word":"...","lemma":"...","pos":"...","zh":"...","en":"...","family":[...],"example":"..."}]}]}
生词列表：
${JSON.stringify(list)}`

  const parsed = await chat(profiles[0], [{ role: 'user', content: prompt }], { json: true, temperature: 0.3 })
  if (!parsed || !Array.isArray(parsed.groups)) throw new Error('模型返回结构异常')
  for (const g of parsed.groups) {
    for (const it of (g.items || [])) {
      try { await saveFamily(it) } catch (e) { /* 单条词族回写失败不影响整体归集 */ }
    }
  }
  return parsed
}

// 词族回写：family 各形态写入 word_cache（已存在补 lemma，不存在新增），并记 vocab_head.family
async function saveFamily(item) {
  const head = lemmaOf(item.lemma || item.word)
  const now = Date.now()
  const family = Array.isArray(item.family) && item.family.length ? item.family : [item.word]
  await db.init()
  await db.execute(
    `INSERT OR IGNORE INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due)
     VALUES (${sqlVal(head)}, 'word', ${sqlVal(now)}, ${sqlVal(now)}, 1, 0, ${sqlVal(now)})`
  )
  await db.execute(
    `UPDATE vocab_head SET family = ${sqlVal(JSON.stringify(family))} WHERE head = ${sqlVal(head)}`
  )
  const zh = item.zh || ''
  const result = JSON.stringify({ kind: 'text', word: head, text: zh })
  for (const f of family) {
    const fword = String(f).toLowerCase()
    const rows = await db.select(`SELECT id FROM word_cache WHERE word = ${sqlVal(fword)} AND mode = 'en2zh' LIMIT 1`)
    if (rows && rows.length) {
      await db.execute(`UPDATE word_cache SET lemma = ${sqlVal(head)} WHERE id = ${sqlVal(rows[0].id)}`)
    } else {
      await db.execute(
        `INSERT OR IGNORE INTO word_cache (word, mode, result, at, lemma)
         VALUES (${sqlVal(fword)}, 'en2zh', ${sqlVal(result)}, ${sqlVal(now)}, ${sqlVal(head)})`
      )
    }
  }
}

// ───────────────────────── 删除 / 清空 ─────────────────────────

export async function removeHead(head) {
  await db.init()
  await db.execute(`DELETE FROM vocab_head WHERE head = ${sqlVal(head)}`)
  await db.execute(`DELETE FROM vocab_occ WHERE lemma = ${sqlVal(head)}`)
}

// 清空词汇中心（含生词历史）。与 db.clearAll 不同，仅清词汇相关表。
export async function clearVocab() {
  await db.init()
  await db.execute('DELETE FROM vocab_head')
  await db.execute('DELETE FROM vocab_occ')
  await db.execute('DELETE FROM word_cache')
}
