// 数据层：5+App 走 plus.sqlite（init 规定存储选型）。
// 非 5+App 环境（开发期 / 单元测试）走 localStorage 持久化的内存表引擎作为兼容后备，
// 对上层暴露完全一致的 execute/select/insertReturnId 语义。

const DB_NAME = 'global_overview.db'
const IS_APP = typeof plus !== 'undefined' && !!plus.sqlite
const MEM_KEY = 'go_mem_db'

const SCHEMA = `
CREATE TABLE IF NOT EXISTS feeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, url TEXT UNIQUE, category TEXT, addedAt INTEGER
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
  html TEXT, plainText TEXT, blocks TEXT, wordCount INTEGER, capturedAt INTEGER
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
  word TEXT, mode TEXT, result TEXT, at INTEGER, UNIQUE(word, mode)
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

// 旧库升级：answers 表结构对齐（补 draft / status / comment 列）
const MIGRATIONS = [
  'ALTER TABLE answers ADD COLUMN draft TEXT',
  "ALTER TABLE answers ADD COLUMN status TEXT DEFAULT 'graded'",
  'ALTER TABLE answers ADD COLUMN comment TEXT',
  'ALTER TABLE answers ADD COLUMN correct INTEGER',
  'ALTER TABLE answers ADD COLUMN wrong INTEGER DEFAULT 0',
  'ALTER TABLE articles ADD COLUMN blocks TEXT',
]

// 显式检测列是否存在，不存在才 ALTER（避免靠 ALTER 抛错被吞的隐式逻辑）。
// 真机 plus.sqlite 不可用时（非 App 环境）直接跳过，兼容内存引擎。
async function ensureColumn(table, column, def) {
  if (!IS_APP) return
  // 这里必须用 raw 查询/执行，因为 ensureColumn 在 init() 内部被调用，
  // 使用 select()/execute() 会再次 await init() 导致死锁。
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

// RSS guid 白名单校验：返回 SQL 安全的字符串字面量（必带单引号包裹）。
// 用于防御性转义之外再叠加一层，避免 guid 含分号/空格闭合 SQL 语句。
// 约定：调用方直接在 SQL 模板中插入 `${safeGuid(guid)}`，无需再 sqlVal 包裹。
export function safeGuid(guid) {
  const s = String(guid == null ? '' : guid)
  // 1. 内容里单引号 → SQL 标准双写转义（先做，避免被后面 \xNN 转义覆盖）
  const quoted = s.replace(/'/g, "''")
  // 2. 白名单校验：仅字母数字与 URL 安全字符（_-./:@）通过；其余按 \xNN 阻断注入
  //    注意：双写的 '' 只含单引号，需在白名单通不过时跳过再转义
  const sanitized = /^[A-Za-z0-9._:/@'\-]+$/.test(quoted)
    ? quoted
    : quoted.replace(/[^A-Za-z0-9']/g, (c) => '\\x' + c.charCodeAt(0).toString(16))
  // 3. 整体用单引号包裹返回
  return `'${sanitized}'`
}

/* ------------------------------------------------------------------ */
/* 非 5+App 环境内存表引擎：支持项目实际用到的 SQL 子集                  */
/* ------------------------------------------------------------------ */
const mem = {
  tables: {},   // name -> { rows: [], seq: n, idx: { col -> Map<val,row> } }
  loaded: false,
}

const MEM_UNIQUE = {
  feeds: ['url'],
  articles: ['guid'],
  word_cache: ['word', 'mode'],
  plan_items: ['articleId'],
  templates: ['name'],
  kv: ['key'],
}

// 需要为查询加速建立单列索引的列（JOIN / 点查高频列），配合 memSelect 的索引命中
const MEM_INDEX_COLS = {
  feed_items: ['guid', 'feedId'],
  articles: ['guid'],
  feeds: ['url'],
}

function memLoad() {
  if (mem.loaded) return
  mem.loaded = true
  try { const raw = uni.getStorageSync(MEM_KEY); if (raw) mem.tables = typeof raw === 'string' ? JSON.parse(raw) : raw } catch (e) { /* 首次启动 */ }
  for (const t of Object.keys(MEM_UNIQUE)) memEnsure(t)
  for (const t of ['feed_items', 'question_sets', 'questions', 'answers', 'presets']) memEnsure(t)
  // 重建全部索引（载入的数据需要重新建立 Map）
  for (const t of Object.keys(MEM_INDEX_COLS)) memRebuildIndex(t)
}

function memEnsure(name) {
  if (!mem.tables[name]) mem.tables[name] = { rows: [], seq: 0, idx: {} }
  else if (!mem.tables[name].idx) mem.tables[name].idx = {}
  return mem.tables[name]
}

// 惰性构建并缓存某表的某列索引（Map<val, row>）。仅对 MEM_INDEX_COLS 声明的列生效。
function memGetIndex(tableName, col) {
  if (!MEM_INDEX_COLS[tableName] || !MEM_INDEX_COLS[tableName].includes(col)) return null
  const table = memEnsure(tableName)
  if (!table.idx[col]) {
    const m = new Map()
    for (const r of table.rows) m.set(r[col], r)
    table.idx[col] = m
  }
  return table.idx[col]
}

// 全量重建某表所有索引（导入数据后调用）
function memRebuildIndex(tableName) {
  if (!MEM_INDEX_COLS[tableName]) return
  const table = memEnsure(tableName)
  table.idx = {}
  for (const c of MEM_INDEX_COLS[tableName]) {
    const m = new Map()
    for (const r of table.rows) m.set(r[c], r)
    table.idx[c] = m
  }
}

// 增量维护索引：插入/更新/删除一行时同步更新 Map，避免每次查询重建
function memIndexPut(tableName, row) {
  const cols = MEM_INDEX_COLS[tableName]
  if (!cols) return
  const table = memEnsure(tableName)
  for (const c of cols) if (table.idx[c]) table.idx[c].set(row[c], row)
}
function memIndexDelete(tableName, row) {
  const cols = MEM_INDEX_COLS[tableName]
  if (!cols) return
  const table = memEnsure(tableName)
  for (const c of cols) if (table.idx[c]) table.idx[c].delete(row[c])
}

let flushTimer = null
function memFlush() {
  if (flushTimer) return
  flushTimer = setTimeout(() => {
    flushTimer = null
    try { uni.setStorageSync(MEM_KEY, JSON.stringify(mem.tables)) } catch (e) {}
  }, 60)
}

function memClear() {
  mem.tables = {}
  mem.loaded = false
  try { uni.removeStorageSync(MEM_KEY) } catch (e) {}
  memLoad()
}

// --- 极简 SQL 解析（仅覆盖本项目使用的语句形态）---

function stripSql(sql) { return String(sql).trim().replace(/;\s*$/, '') }

// 值列表解析：引号内内容原样保留，引号外空白丢弃。
// 关键点：quoted 段与裸 token 分开累积，否则 `, 'abc'` 会得到 " abc"。
function parseValues(str) {
  const out = []
  let quotedBuf = ''   // 引号内累积
  let bareBuf = ''     // 引号外累积
  let hasQuoted = false
  let inStr = false
  let depth = 0

  const flush = () => {
    if (hasQuoted) out.push(quotedBuf)
    else {
      const t = bareBuf.trim()
      if (/^null$/i.test(t)) out.push(null)
      else if (/^[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?$/.test(t)) out.push(Number(t))
      else out.push(t)
    }
    quotedBuf = ''
    bareBuf = ''
    hasQuoted = false
  }

  for (let i = 0; i < str.length; i++) {
    const c = str[i]
    if (inStr) {
      if (c === "'") {
        if (str[i + 1] === "'") { quotedBuf += "'"; i++ }
        else inStr = false
      } else quotedBuf += c
      continue
    }
    if (c === "'") { inStr = true; hasQuoted = true; continue }
    if (c === '(') { depth++; bareBuf += c; continue }
    if (c === ')') { depth--; bareBuf += c; continue }
    if (c === ',' && depth === 0) { flush(); continue }
    bareBuf += c
  }
  flush()
  return out
}

// WHERE 求值：支持 col=val / col!=val / col IS NULL / col IS NOT NULL /
// col IN (...) / AND 连接 / 简单前缀限定 (a.col)
function buildWhere(whereStr) {
  if (!whereStr || !whereStr.trim()) return () => true
  const parts = whereStr.split(/\s+AND\s+/i).map((s) => s.trim()).filter(Boolean)
  const preds = parts.map((p) => {
    let m = p.match(/^([\w.]+)\s+IS\s+NOT\s+NULL$/i)
    if (m) { const c = col(m[1]); return (r) => r[c] !== null && r[c] !== undefined }
    m = p.match(/^([\w.]+)\s+IS\s+NULL$/i)
    if (m) { const c = col(m[1]); return (r) => r[c] === null || r[c] === undefined }
    m = p.match(/^([\w.]+)\s+IN\s*\(([\s\S]*)\)$/i)
    if (m) {
      const c = col(m[1])
      const inner = m[2].trim()
      if (/^SELECT\s/i.test(inner)) {
        const sub = memSelect(inner).map((row) => Object.values(row)[0])
        return (r) => sub.some((v) => looseEq(r[c], v))
      }
      const set = parseValues(m[2])
      return (r) => set.some((v) => looseEq(r[c], v))
    }
    m = p.match(/^([\w.]+)\s*(!=|<>|>=|<=|=|>|<)\s*([\s\S]+)$/)
    if (m) { const c = col(m[1]); const op = m[2]; const v = parseValues(m[3])[0]; return (r) => cmp(r[c], op, v) }
    m = p.match(/^([\w.]+)\s+LIKE\s+'([\s\S]*)'$/i)
    if (m) {
      const c = col(m[1])
      const pat = m[2].replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*').replace(/_/g, '.')
      const re = new RegExp('^' + pat + '$')
      return (r) => r[c] != null && re.test(String(r[c]))
    }
    return () => true
  })
  return (r) => preds.every((f) => f(r))
}

function col(name) { return name.includes('.') ? name.split('.').pop() : name }
function looseEq(a, b) {
  if (a === null || a === undefined) return b === null || b === undefined
  return String(a) === String(b)
}
function cmp(a, op, b) {
  switch (op) {
    case '=': return looseEq(a, b)
    case '!=': case '<>': return !looseEq(a, b)
    case '>': return Number(a) > Number(b)
    case '<': return Number(a) < Number(b)
    case '>=': return Number(a) >= Number(b)
    case '<=': return Number(a) <= Number(b)
    default: return true
  }
}

function splitParenGroups(s) {
  const out = []
  let depth = 0, buf = '', inStr = false
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (inStr) {
      buf += c
      if (c === "'") { if (s[i + 1] === "'") { buf += "'"; i++ } else inStr = false }
      continue
    }
    if (c === "'") { inStr = true; buf += c; continue }
    if (c === '(' && depth === 0) { depth = 1; buf = ''; continue }
    if (c === '(') { depth++; buf += c; continue }
    if (c === ')') {
      depth--
      if (depth === 0) { out.push(buf); continue }
      buf += c; continue
    }
    if (depth > 0) buf += c
  }
  return out
}

function memExec(sqlRaw) {
  const sql = stripSql(sqlRaw)
  if (!sql) return { rowsAffected: 0 }

  if (/^CREATE\s+TABLE/i.test(sql)) return { rowsAffected: 0 }
  if (/^ALTER\s+TABLE/i.test(sql)) return { rowsAffected: 0 }

  let m = sql.match(/^INSERT\s+(OR\s+(IGNORE|REPLACE)\s+)?INTO\s+(\w+)\s*\(([^)]*)\)\s*VALUES\s+([\s\S]+)$/i)
  if (m) {
    const conflict = (m[2] || '').toUpperCase()
    const table = memEnsure(m[3])
    const cols = m[4].split(',').map((s) => s.trim())
    const groups = splitParenGroups(m[5])
    let insertId = null
    let affected = 0
    for (const g of groups) {
      const vals = parseValues(g)
      const row = {}
      cols.forEach((c, i) => { row[c] = vals[i] === undefined ? null : vals[i] })
      const uniq = MEM_UNIQUE[m[3]]
      if (uniq) {
        const hit = table.rows.find((r) => uniq.every((c) => looseEq(r[c], row[c])))
        if (hit) {
          if (conflict === 'IGNORE') { insertId = hit.id; continue }
          if (conflict === 'REPLACE') {
            const old = { ...hit }
            Object.assign(hit, row)
            memIndexDelete(m[3], old)
            memIndexPut(m[3], hit)
            insertId = hit.id
            affected++
            continue
          }
        }
      }
      row.id = ++table.seq
      table.rows.push(row)
      memIndexPut(m[3], row)
      insertId = row.id
      affected++
    }
    memFlush()
    return { rowsAffected: affected, insertId }
  }

  m = sql.match(/^UPDATE\s+(\w+)\s+SET\s+([\s\S]+)$/i)
  if (m) {
    const table = memEnsure(m[1])
    // WHERE 必须在字符串字面量之外查找，否则值里出现 " WHERE " 会被截断
    const tail = m[2]
    const wIdx = findKeywordOutsideString(tail, /^\s*\bWHERE\s/i)
    const setPart = wIdx < 0 ? tail : tail.slice(0, wIdx)
    const wherePart = wIdx < 0 ? '' : tail.slice(wIdx).replace(/^\s*WHERE\s+/i, '')
    const assigns = splitAssignments(setPart)
    const pred = buildWhere(wherePart)
    let n = 0
    for (const r of table.rows) {
      if (!pred(r)) continue
      memIndexDelete(m[1], r)
      for (const a of assigns) r[a.col] = a.value
      memIndexPut(m[1], r)
      n++
    }
    memFlush()
    return { rowsAffected: n }
  }

  m = sql.match(/^DELETE\s+FROM\s+(\w+)(?:\s+WHERE\s+([\s\S]+))?$/i)
  if (m) {
    const table = memEnsure(m[1])
    const pred = buildWhere(m[2])
    const before = table.rows.length
    table.rows = table.rows.filter((r) => {
      if (pred(r)) { memIndexDelete(m[1], r); return false }
      return true
    })
    memFlush()
    return { rowsAffected: before - table.rows.length }
  }

  return { rowsAffected: 0 }
}

// 在字符串字面量之外查找关键字，返回索引（-1 未找到）
function findKeywordOutsideString(str, re) {
  let inStr = false
  for (let i = 0; i < str.length; i++) {
    const c = str[i]
    if (inStr) {
      if (c === "'") { if (str[i + 1] === "'") i++; else inStr = false }
      continue
    }
    if (c === "'") { inStr = true; continue }
    const m = str.slice(i).match(re)
    if (m && m.index === 0) return i
  }
  return -1
}

function splitAssignments(str) {
  const out = []
  let cur = ''
  let inStr = false
  for (let i = 0; i < str.length; i++) {
    const c = str[i]
    if (inStr) {
      if (c === "'") { if (str[i + 1] === "'") { cur += "''"; i++ } else { inStr = false; cur += c } }
      else cur += c
      continue
    }
    if (c === "'") { inStr = true; cur += c; continue }
    if (c === ',') { out.push(cur); cur = ''; continue }
    cur += c
  }
  if (cur.trim()) out.push(cur)
  return out.map((s) => {
    const i = s.indexOf('=')
    return { col: s.slice(0, i).trim(), value: parseValues(s.slice(i + 1))[0] }
  })
}

function memSelect(sqlRaw) {
  const sql = stripSql(sqlRaw).replace(/\s+/g, ' ')

  if (/last_insert_rowid/i.test(sql)) return [{ id: mem.lastInsertId || null }]

  // SELECT <fields> FROM <t> [alias] [JOIN <t2> alias ON a.x=b.y] [WHERE ..] [GROUP BY ..] [ORDER BY ..] [LIMIT n]
  const m = sql.match(/^SELECT\s+([\s\S]+?)\s+FROM\s+(\w+)(?:\s+(?:AS\s+)?(\w+))?([\s\S]*)$/i)
  if (!m) return []
  const fieldStr = m[1]
  const baseName = m[2]
  const baseAlias = m[3] && !/^(WHERE|JOIN|LEFT|GROUP|ORDER|LIMIT)$/i.test(m[3]) ? m[3] : null
  let rest = (m[3] && /^(WHERE|JOIN|LEFT|GROUP|ORDER|LIMIT)$/i.test(m[3]) ? m[3] + ' ' : '') + (m[4] || '')

  let rows = memEnsure(baseName).rows.map((r) => ({ ...r }))

  // JOIN
  const jm = rest.match(/(LEFT\s+)?JOIN\s+(\w+)(?:\s+(?:AS\s+)?(\w+))?\s+ON\s+([\w.]+)\s*=\s*([\w.]+)/i)
  if (jm) {
    const isLeft = !!jm[1]
    const joinRows = memEnsure(jm[2]).rows
    const joinAlias = jm[3] || jm[2]
    // 判断哪一侧属于 join 表
    const aPrefix = jm[4].split('.')[0]
    const leftIsJoin = aPrefix === joinAlias
    const baseCol = col(leftIsJoin ? jm[5] : jm[4])
    const joinCol = col(leftIsJoin ? jm[4] : jm[5])
    // 若 join 列的索引可用，用 Map 命中替代对全量 joinRows 的线性 filter（O(1) vs O(n)）
    const joinIndex = memGetIndex(jm[2], joinCol)
    const merged = []
    for (const r of rows) {
      let hits
      if (joinIndex) {
        const h = joinIndex.get(r[baseCol])
        hits = h ? [h] : []
      } else {
        hits = joinRows.filter((j) => looseEq(j[joinCol], r[baseCol]))
      }
      if (hits.length) {
        // 基表字段优先级更高，但保留 join 侧字段的带前缀访问路径
        for (const h of hits) {
          const row = { ...h, ...r, __joined: true }
          for (const k of Object.keys(h)) row[`${joinAlias}.${k}`] = h[k]
          merged.push(row)
        }
      } else if (isLeft) {
        merged.push({ ...r, __joined: false })
      }
    }
    rows = merged
    rest = rest.replace(jm[0], ' ')
  }

  const wIdx = findKeywordOutsideString(rest, /^\s*\bWHERE\s/i)
  if (wIdx >= 0) {
    let wStr = rest.slice(wIdx).replace(/^\s*WHERE\s+/i, '')
    const cut = wStr.search(/\s+(GROUP\s+BY|ORDER\s+BY|LIMIT)\b/i)
    if (cut >= 0) wStr = wStr.slice(0, cut)
    rows = rows.filter(buildWhere(wStr))
  }

  // GROUP BY + COUNT
  const gm = rest.match(/GROUP\s+BY\s+([\w.]+)/i)
  const countM = fieldStr.match(/COUNT\(([\w.*]+)\)\s+(?:AS\s+)?(\w+)/i)
  if (gm) {
    const key = col(gm[1])
    const groups = new Map()
    for (const r of rows) {
      const k = r[key]
      if (!groups.has(k)) groups.set(k, [])
      groups.get(k).push(r)
    }
    rows = [...groups.values()].map((g) => {
      const base = { ...g[0] }
      if (countM) {
        const raw = countM[1]
        base[countM[2]] = raw === '*'
          ? g.length
          // COUNT(alias.col)：LEFT JOIN 未命中的行不计数
          : g.filter((r) => {
            if (r.__joined === false) return false
            const v = r[raw] !== undefined ? r[raw] : r[col(raw)]
            return v !== null && v !== undefined
          }).length
      }
      return base
    })
  } else if (countM) {
    // 无 GROUP BY 的 COUNT(*)/COUNT(col)：折叠为单行聚合结果
    const raw = countM[1]
    const val = raw === '*'
      ? rows.length
      : rows.filter((r) => {
        const v = r[raw] !== undefined ? r[raw] : r[col(raw)]
        return v !== null && v !== undefined
      }).length
    rows = [{ [countM[2]]: val }]
  }

  const om = rest.match(/ORDER\s+BY\s+([\w.]+)(\s+DESC|\s+ASC)?/i)
  if (om) {
    const key = col(om[1])
    const desc = /DESC/i.test(om[2] || '')
    rows.sort((a, b) => {
      const x = a[key], y = b[key]
      if (x === y) return 0
      const nx = Number(x), ny = Number(y)
      const rx = x !== '' && x != null && Number.isFinite(nx)
      const ry = y !== '' && y != null && Number.isFinite(ny)
      const r = rx && ry
        ? nx - ny
        : String(x).localeCompare(String(y))
      return desc ? -r : r
    })
  }

  const lm = rest.match(/LIMIT\s+(\d+)/i)
  if (lm) rows = rows.slice(0, Number(lm[1]))

  // 字段投影：处理 `a.id AS aid` 之类别名；`*` / `t.*` 直接透传
  const distinctM = fieldStr.match(/^\s*DISTINCT\s+/i)
  const projStr = distinctM ? fieldStr.slice(distinctM[0].length) : fieldStr
  if (!/^\s*\*\s*$/.test(projStr) && !/^\s*\w+\.\*\s*$/.test(projStr) && !countM) {
    const specs = projStr.split(',').map((s) => s.trim())
    const hasStar = specs.some((s) => s === '*' || /^\w+\.\*$/.test(s))
    rows = rows.map((r) => {
      const o = hasStar ? { ...r } : {}
      for (const s of specs) {
        if (s === '*' || /^\w+\.\*$/.test(s)) continue
        const am = s.match(/^([\w.]+)\s+(?:AS\s+)?(\w+)$/i)
        if (am) {
          const src = am[1]
          o[am[2]] = src.includes('.') && r[src] !== undefined ? r[src] : r[col(src)]
        } else o[col(s)] = r[col(s)]
      }
      return cleanRow(o)
    })
  } else {
    rows = rows.map((r) => cleanRow({ ...r }))
  }
  if (distinctM) {
    const seen = new Set()
    rows = rows.filter((r) => {
      const k = JSON.stringify(r)
      if (seen.has(k)) return false
      seen.add(k)
      return true
    })
  }
  return rows
}

// 去掉内部标记与 join 前缀键，避免泄露到业务层
function cleanRow(o) {
  delete o.__joined
  for (const k of Object.keys(o)) {
    if (k.includes('.')) delete o[k]
  }
  return o
}

/* ------------------------------------------------------------------ */
/* 统一 API                                                             */
/* ------------------------------------------------------------------ */

function openDb() {
  return new Promise((resolve, reject) => {
    if (!IS_APP) return resolve(false)
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
      if (!IS_APP) { memLoad(); inited = true; return }
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
      try { await ensureColumn('answers', 'draft', 'TEXT') } catch (e) {}
      try { await ensureColumn('answers', 'status', "TEXT DEFAULT 'graded'") } catch (e) {}
      try { await ensureColumn('answers', 'comment', 'TEXT') } catch (e) {}
      try { await ensureColumn('answers', 'correct', 'INTEGER') } catch (e) {}
      try { await ensureColumn('answers', 'wrong', 'INTEGER DEFAULT 0') } catch (e) {}
      inited = true
    } catch (e) {
      initPromise = null
      throw e
    }
  })()
  return initPromise
}

// 把 ? 占位符按顺序替换为转义后的字面量；会跳过 SQL 字符串/标识符里的 ?
// 返回值可直接交给真实 SQLite 或内存引擎执行，统一兼容参数化查询。
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
    if (!IS_APP) {
      memLoad()
      const stmts = splitStatements(String(bound))
      let last = { rowsAffected: 0 }
      for (const s of stmts) last = memExec(s)
      if (last.insertId) mem.lastInsertId = last.insertId
      return resolve(last)
    }
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
    if (!IS_APP) { memLoad(); return resolve(memSelect(bound)) }
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
    if (!IS_APP) return mem.lastInsertId || null
    const rows = await select('SELECT last_insert_rowid() AS id')
    return rows[0] ? rows[0].id : null
  })
}

// 清空全部业务数据（保留 LLM 配置与阅读偏好）
async function clearAll() {
  const tables = ['feeds', 'feed_items', 'articles', 'question_sets', 'questions',
    'answers', 'word_cache', 'presets', 'plan_items']
  if (!IS_APP) { memClear(); return }
  for (const t of tables) await execute(`DELETE FROM ${t}`)
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

export const db = { init, execute, select, insertReturnId, clearAll, clearCache,
  loadDraft, loadDrafts, saveDraft, clearDrafts, loadHistory, sqlVal, safeGuid, IS_APP }
