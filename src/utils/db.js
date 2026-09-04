// 数据层：仅 5+App 端，统一走 plus.sqlite。上层通过 execute/select/insertReturnId 访问，
// 不再提供非 App 环境的内存兼容引擎（项目仅发布 App）。

import { clearHabit } from './habit.js'

const DB_NAME = 'global_overview.db'

const SCHEMA = `
CREATE TABLE IF NOT EXISTS feeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, url TEXT UNIQUE, category TEXT, addedAt INTEGER,
  failCount INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS feed_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  feedId INTEGER, guid TEXT, title TEXT, link TEXT,
  preview TEXT, pubDate INTEGER, fetchedAt INTEGER,
  UNIQUE(feedId, guid)
);
CREATE TABLE IF NOT EXISTS articles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  guid TEXT UNIQUE, title TEXT, author TEXT, sourceUrl TEXT,
  html TEXT, plainText TEXT, blocks TEXT, wordCount INTEGER, capturedAt INTEGER,
  tts_audio TEXT, tts_voice TEXT
);
CREATE TABLE IF NOT EXISTS question_sets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  articleId INTEGER, presetId INTEGER, title TEXT, createdAt INTEGER
);
CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  setId INTEGER, type TEXT, gradeMode TEXT, prompt TEXT,
  options TEXT, answers TEXT, analysis TEXT, sourceQuote TEXT, createdAt INTEGER
);
CREATE TABLE IF NOT EXISTS answers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  questionId INTEGER NOT NULL,
  draft TEXT,
  final TEXT,
  correct INTEGER,
  wrong INTEGER DEFAULT 0,
  status TEXT DEFAULT 'graded',
  comment TEXT,
  gradedAt INTEGER
);
CREATE TABLE IF NOT EXISTS word_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT, mode TEXT, result TEXT, at INTEGER, lemma TEXT,
  UNIQUE(word, mode)
);
CREATE TABLE IF NOT EXISTS vocab_head (
  head TEXT PRIMARY KEY,
  kind TEXT DEFAULT 'word',
  firstSeen INTEGER, lastSeen INTEGER,
  occCount INTEGER DEFAULT 1,
  family TEXT,
  fsrs_state INTEGER DEFAULT 0,
  fsrs_due INTEGER,
  fsrs_s REAL DEFAULT 0,
  fsrs_d REAL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS vocab_occ (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT, lemma TEXT,
  articleGuid TEXT, articleTitle TEXT, sourceLabel TEXT,
  sentence TEXT, paraIndex INTEGER, tokIndex INTEGER, at INTEGER,
  UNIQUE(word, articleGuid, paraIndex, tokIndex)
);
CREATE TABLE IF NOT EXISTS vocab_sentence (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sentence TEXT UNIQUE,
  articleGuid TEXT, articleTitle TEXT, sourceLabel TEXT,
  paraIndex INTEGER, tokIndex INTEGER, at INTEGER,
  analysis TEXT
);
CREATE TABLE IF NOT EXISTS presets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT, config TEXT
);
CREATE TABLE IF NOT EXISTS plan_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  articleId INTEGER UNIQUE, addedAt INTEGER, status TEXT DEFAULT 'pending'
);
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE, source TEXT
);
`

// 显式检测列是否存在，不存在才 ALTER（避免靠 ALTER 抛错被吞的隐式逻辑）。
// 使用 raw 查询/执行，因为 ensureColumn 在 init() 内部被调用，
// 使用 select()/execute() 会再次 await init() 导致死锁。
async function ensureColumn(table, column, def) {
  const info = await rawSelectOne(`PRAGMA table_info(${table})`)
  const has = (info || []).some((r) => String(r.name).toLowerCase() === String(column).toLowerCase())
  if (!has) await rawExecuteOne(`ALTER TABLE ${table} ADD COLUMN ${column} ${def}`)
}

/* ------------------------------------------------------------------ */
/* SQL 值转义：所有写入统一走 sqlVal / sqlLike，杜绝手工拼引号漏转义      */
/* ------------------------------------------------------------------ */
export function sqlVal(v) {
  if (v === null || v === undefined) return 'NULL'
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'NULL'
  if (typeof v === 'boolean') return v ? '1' : '0'
  // 剥离 NUL 与控制字符，避免破坏 SQL 字面量；再转义单引号（SQL 标准双写）
  const NUL = String.fromCharCode(0)
  const ctrl = new RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', 'g')
  const cleaned = String(v).split(NUL).join('').replace(ctrl, '')
  return `'${cleaned.replace(/'/g, "''")}'`
}

// 业务常量集中管理（避免散落的魔法数字）
export const DB_CONFIG = {
  ARTICLE_MIN_CHARS: 800, // extractArticle 正文最小长度阈值
  WORD_CACHE_TTL_DAYS: 7, // 查词缓存有效期（天）
}

// RSS guid 转义：返回 SQL 安全字符串字面量（必带单引号包裹）。
//
// 历史坑（勿恢复）：此处曾用白名单 + \xNN 转义，而 \xNN 在 SQLite 里是**字面量**而非
// 十六进制转义（SQLite 用 X'...' 语法），导致含 ? = & % , 的 guid（RSS 中极常见）
// 被写成 "...\x3fp\x3d123" 入库。而其余查询走 sqlVal(原始 guid)，两者永不匹配，
// 表现为「文章已抓取但永远打不开」。故统一使用 sqlVal 的标准单引号双写转义，
// 它已能防注入，且写入/读取两侧行为一致。
export function safeGuid(guid) {
  return sqlVal(guid)
}

/* ------------------------------------------------------------------ */
/* 统一 API（5+App：plus.sqlite）                                       */
/* ------------------------------------------------------------------ */

function openDb() {
  return new Promise((resolve, reject) => {
    if (plus.sqlite.isOpenDatabase({ name: DB_NAME, path: `_doc/${DB_NAME}` })) return resolve(true)
    // 真机 plus.sqlite 偶发回调不触发（数据库锁/引擎 bug），加超时避免永久卡死
    const timer = setTimeout(() => reject(new Error('数据库打开超时')), 8000)
    plus.sqlite.openDatabase({
      name: DB_NAME,
      path: `_doc/${DB_NAME}`,
      success: () => { clearTimeout(timer); resolve(true) },
      fail: (e) => { clearTimeout(timer); reject(e) },
    })
  })
}

// 安全的多语句切分：忽略字符串字面量内部的分号
function splitStatements(sql) {
  const out = []
  let cur = ''
  let inStr = false
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i]
    if (inStr) {
      if (c === "'") {
        if (sql[i + 1] === "'") { cur += "''"; i++ }
        else { cur += c; inStr = false }
      } else cur += c
      continue
    }
    if (c === "'") { inStr = true; cur += c; continue }
    if (c === ';') { if (cur.trim()) out.push(cur.trim()); cur = ''; continue }
    cur += c
  }
  if (cur.trim()) out.push(cur.trim())
  return out
}

let inited = false
let initPromise = null

async function init() {
  // 并发锁：多页面（各自独立 webview）可能同时首次调用 init()。
  // 若不做 Promise 复用，异步 openDb 让出后第二调用会重入建表逻辑，
  // 在 5+App 多 webview 下对同库并发 CREATE/execute，导致
  // "database is locked" / "table already exists" 甚至写损坏。
  if (inited) return initPromise || Promise.resolve()
  if (initPromise) return initPromise
  initPromise = (async () => {
    try {
      await openDb()
      // plus.sqlite 单条 executeSql 不接受多语句，逐条建表。
      // 注意：这里必须用 rawExecuteOne，不能用 execute()，因为 execute() 会 await init()，
      // 而 init() 此时正在执行中，会导致递归死锁（页面永久 loading）。
      for (const stmt of splitStatements(SCHEMA)) {
        await rawExecuteOne(stmt)
      }
      // 迁移改为「显式检测列是否存在再 ALTER」，不再依赖 ALTER 抛错被静默吞掉。
      // 真机 plus.sqlite 某些版本对重复 ALTER 的报错并非「列已存在」，会被误吞，
      // 导致 articles.blocks 等列永久缺失，进而让 SELECT 该列的页面整句失败。
      try { await ensureColumn('articles', 'blocks', 'TEXT') } catch (e) {}
      try { await ensureColumn('articles', 'tts_audio', 'TEXT') } catch (e) {}
      try { await ensureColumn('articles', 'tts_voice', 'TEXT') } catch (e) {}
      try { await ensureColumn('articles', 'curated_blocks', 'TEXT') } catch (e) {}
      try { await ensureColumn('answers', 'draft', 'TEXT') } catch (e) {}
      try { await ensureColumn('answers', 'status', "TEXT DEFAULT 'graded'") } catch (e) {}
      try { await ensureColumn('answers', 'comment', 'TEXT') } catch (e) {}
      try { await ensureColumn('answers', 'correct', 'INTEGER') } catch (e) {}
      try { await ensureColumn('answers', 'wrong', 'INTEGER DEFAULT 0') } catch (e) {}
      try { await ensureColumn('feeds', 'failCount', 'INTEGER DEFAULT 0') } catch (e) {}
      try { await ensureColumn('word_cache', 'lemma', 'TEXT') } catch (e) {}
      // 修复历史遗留的 \xNN 损坏 guid（见 repairCorruptedGuids）
      try { await repairCorruptedGuids() } catch (e) {}
      inited = true
    } catch (e) {
      initPromise = null
      throw e
    }
  })()
  return initPromise
}

// 把 ? 占位符按顺序替换为转义后的字面量；会跳过 SQL 字符串/标识符里的 ?
// 返回值可直接交给真实 SQLite 执行，统一兼容参数化查询。
function bindParams(sql, params) {
  if (!params || !params.length) return sql
  let i = 0
  return sql.replace(/('(?:''|[^'])*')|("(?:""|[^"])*")|(`(?:``|[^`])*`)|\?/g, (m, s, d, b) => {
    if (s || d || b) return m
    if (i >= params.length) return 'NULL'
    return sqlVal(params[i++])
  })
}

// 底层执行，不触发 init()，专门供 init() 自身使用，避免递归死锁。
function rawExecuteOne(bound) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('SQL 执行超时')), 8000)
    plus.sqlite.executeSql({
      name: DB_NAME,
      sql: typeof bound === 'string' ? bound : bound.join(';'),
      success: (res) => { clearTimeout(timer); resolve(res) },
      fail: (e) => { clearTimeout(timer); reject(new Error(e.message || 'SQL 执行失败')) },
    })
  })
}

// 底层查询，不触发 init()，专门供 init() 自身使用，避免递归死锁。
function rawSelectOne(bound) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('SQL 查询超时')), 8000)
    plus.sqlite.selectSql({
      name: DB_NAME,
      sql: bound,
      success: (res) => { clearTimeout(timer); resolve(res || []) },
      fail: (e) => { clearTimeout(timer); reject(new Error(e.message || 'SQL 查询失败')) },
    })
  })
}

async function execute(sql, params) {
  await init()
  return rawExecuteOne(bindParams(sql, params))
}

async function select(sql, params) {
  await init()
  return rawSelectOne(bindParams(sql, params))
}

let writeLock = Promise.resolve()
function withWriteLock(fn) {
  const next = writeLock.then(fn, fn)
  writeLock = next.catch(() => {})
  return next
}

async function insertReturnId(sql) {
  await init()
  return withWriteLock(async () => {
    await execute(sql)
    const rows = await select('SELECT last_insert_rowid() AS id')
    return rows[0] ? rows[0].id : null
  })
}

// 清空全部业务数据（保留 LLM 配置与阅读偏好）
async function clearAll() {
  const tables = ['feeds', 'feed_items', 'articles', 'question_sets', 'questions',
    'answers', 'word_cache', 'presets', 'plan_items', 'vocab_head', 'vocab_occ', 'vocab_sentence']
  for (const t of tables) await execute(`DELETE FROM ${t}`)
  // 习惯打卡数据随业务数据一起清空（用户决策：全部清空）
  try { clearHabit() } catch (e) {}
}

// 只清缓存（正文 / 词典 / 抓取列表），保留题目与错题
async function clearCache() {
  for (const t of ['feed_items', 'word_cache']) await execute(`DELETE FROM ${t}`)
}

/* ------------------------------------------------------------------ */
/* 草稿（answers.draft）：init §6 要求静默自动保存，交卷后清空          */
/* ------------------------------------------------------------------ */

// 取某题草稿：优先取未判分占位行（gradedAt=0 且 draft 非空）
async function loadDraft(questionId) {
  await init()
  const rows = await select(
    `SELECT draft FROM answers WHERE questionId = ${sqlVal(questionId)} AND gradedAt = 0 AND draft IS NOT NULL ORDER BY id DESC LIMIT 1`
  )
  if (rows && rows.length) return rows[0].draft
  return ''
}

// 批量取草稿：返回 { questionId: draft }
async function loadDrafts(ids) {
  await init()
  const list = Array.isArray(ids) ? ids : [ids]
  const out = {}
  if (!list.length) return out
  const rows = await select(
    `SELECT id, questionId, draft FROM answers WHERE questionId IN (${list.map(sqlVal).join(',')}) AND gradedAt = 0 AND draft IS NOT NULL`
  )
  const best = {}
  for (const r of (rows || [])) {
    if (!best[r.questionId] || r.id > best[r.questionId].id) best[r.questionId] = r
  }
  for (const qid of list) out[qid] = best[qid] ? best[qid].draft : ''
  return out
}

// 自动保存草稿：复用该题"未判分占位行"（gradedAt=0 且无 final），否则插入新占位行
async function saveDraft(questionId, content) {
  await init()
  return withWriteLock(async () => {
    const rows = await select(
      `SELECT id FROM answers WHERE questionId = ${sqlVal(questionId)} AND gradedAt = 0 AND (final IS NULL OR final = '') ORDER BY id DESC LIMIT 1`
    )
    if (rows && rows.length) {
      await execute(
        `UPDATE answers SET draft = ${sqlVal(content)} WHERE id = ${sqlVal(rows[0].id)}`
      )
    } else {
      await execute(
        `INSERT INTO answers (questionId, draft, gradedAt) VALUES (${sqlVal(questionId)}, ${sqlVal(content)}, 0)`
      )
    }
  })
}

// 交卷后清空草稿（保留 final / 判分结果）：清除未判分草稿占位行的 draft
async function clearDrafts(questionIds) {
  await init()
  const ids = Array.isArray(questionIds) ? questionIds : [questionIds]
  return withWriteLock(async () => {
    for (const qid of ids) {
      const rows = await select(
        `SELECT id FROM answers WHERE questionId = ${sqlVal(qid)} AND gradedAt = 0 AND draft IS NOT NULL ORDER BY id DESC LIMIT 1`
      )
      if (rows && rows.length) {
        await execute(
          `UPDATE answers SET draft = NULL WHERE id = ${sqlVal(rows[0].id)}`
        )
      }
    }
  })
}

// 取某题作答历史（已判分行，按时间升序），供错题/历史展示
// 支持单 id 或 id 数组（数组时返回 { questionId: [...] }）
async function loadHistory(questionId) {
  await init()
  if (Array.isArray(questionId)) {
    const list = questionId
    const out = {}
    if (!list.length) return out
    const rows = await select(
      `SELECT questionId, final, correct, wrong, comment, status, gradedAt
       FROM answers WHERE questionId IN (${list.map(sqlVal).join(',')}) AND gradedAt > 0 ORDER BY gradedAt ASC`
    )
    for (const qid of list) out[qid] = []
    for (const r of (rows || [])) (out[r.questionId] = out[r.questionId] || []).push(r)
    return out
  }
  return select(
    `SELECT final, correct, wrong, comment, status, gradedAt
     FROM answers WHERE questionId = ${sqlVal(questionId)} AND gradedAt > 0 ORDER BY gradedAt ASC`
  ) || []
}

// 读取文章已缓存的 TTS 音频（base64 mp3）与对应音色
async function loadTtsCache(id) {
  try {
    const rows = await select(`SELECT tts_audio, tts_voice FROM articles WHERE id = ${sqlVal(id)} LIMIT 1`)
    const row = rows && rows[0]
    if (row && row.tts_audio) return { audio: row.tts_audio, voice: row.tts_voice || '' }
    return null
  } catch (e) {
    console.error(e)
    return null
  }
}

// 将合成好的 TTS 音频写入文章行，与原文一起缓存
async function saveTtsCache(id, audio, voice) {
  try {
    await execute(`UPDATE articles SET tts_audio = ${sqlVal(audio)}, tts_voice = ${sqlVal(voice)} WHERE id = ${sqlVal(id)}`)
    return true
  } catch (e) {
    console.error(e)
    return false
  }
}

/* ---------------- AI 精选（curated_blocks） ---------------- */
// 与 TTS 缓存同构：原文 blocks 永不改写，精选结果另存一列，
// NULL 表示「未精选」，置回 NULL 即一键还原原文。
async function loadCurated(id) {
  try {
    const rows = await select(`SELECT curated_blocks FROM articles WHERE id = ${sqlVal(id)} LIMIT 1`)
    const raw = rows && rows[0] && rows[0].curated_blocks
    if (!raw) return null
    const bs = JSON.parse(raw)
    return Array.isArray(bs) && bs.length ? bs : null
  } catch (e) {
    // 解析失败视为未精选，不影响主流程
    return null
  }
}

async function saveCurated(id, blocks) {
  try {
    await execute(`UPDATE articles SET curated_blocks = ${sqlVal(JSON.stringify(blocks || []))} WHERE id = ${sqlVal(id)}`)
    return true
  } catch (e) {
    console.error(e)
    return false
  }
}

// 还原原文：把精选结果置空
async function clearCurated(id) {
  try {
    await execute(`UPDATE articles SET curated_blocks = NULL WHERE id = ${sqlVal(id)}`)
    return true
  } catch (e) {
    console.error(e)
    return false
  }
}

/* ---------------- 一次性修复：还原被 \xNN 损坏的 guid ---------------- */
// 旧版 safeGuid 把非白名单字符转义成字面量 "\x3f" 等，导致 articles.guid 与
// feed_items.guid 不匹配（文章入库后永远打不开）。此处把 \xNN 还原成原字符，
// 让两侧重新对齐。
const GUIDFIX_KEY = 'db_guidfix_v1'
// \xNN -> 原字符（NN 为两位十六进制）
function unescapeXNN(s) {
  return String(s).replace(/\\x([0-9a-fA-F]{2})/g, (m, hex) => String.fromCharCode(parseInt(hex, 16)))
}

// 关键：本函数在 init() 内部执行，内部**只能用 rawSelectOne / rawExecuteOne**。
// 若用 select()/execute()，它们会 await init()；而此时 initPromise 已赋值、
// inited 仍为 false，init() 会返回自身 Promise —— 等自己，形成递归死锁，
// 表现为 App 端启动即永久 loading（非 App 分支提前 return，开发期测不出来）。
async function repairCorruptedGuids() {
  try {
    if (uni.getStorageSync(GUIDFIX_KEY)) return 0
    const rows = await rawSelectOne(`SELECT id, guid FROM articles WHERE guid LIKE '%\\x%'`)
    if (!rows || !rows.length) { uni.setStorageSync(GUIDFIX_KEY, 1); return 0 }
    let fixed = 0
    for (const r of rows) {
      const fixedGuid = unescapeXNN(r.guid)
      if (!fixedGuid || fixedGuid === r.guid) continue
      try {
        await rawExecuteOne(`UPDATE articles SET guid = ${sqlVal(fixedGuid)} WHERE id = ${sqlVal(r.id)}`)
        fixed++
      } catch (e) {
        // 与 feed_items.guid UNIQUE 冲突时跳过，保留原值，不影响其它行
      }
    }
    uni.setStorageSync(GUIDFIX_KEY, 1)
    return fixed
  } catch (e) {
    // 修复失败不阻塞启动；标记已跑避免每次启动都重试失败路径
    try { uni.setStorageSync(GUIDFIX_KEY, 1) } catch (e2) {}
    return 0
  }
}

export const db = { init, execute, select, insertReturnId, clearAll, clearCache,
  loadDraft, loadDrafts, saveDraft, clearDrafts, loadHistory,
  loadTtsCache, saveTtsCache, loadCurated, saveCurated, clearCurated,
  repairCorruptedGuids, sqlVal, safeGuid }
