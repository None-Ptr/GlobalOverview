// 内存 SQL 引擎冒烟测试：模拟 uni 环境后跑一遍完整业务链路
import { readFileSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))

// --- 模拟 uni storage ---
const store = new Map()
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
}

const src = readFileSync(join(__dirname, '../src/utils/db.js'), 'utf8')
const mod = await import('data:text/javascript;base64,' + Buffer.from(src).toString('base64'))
const { db } = mod
const { sqlVal } = db

let pass = 0
let fail = 0
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ', name) }
  else { fail++; console.log('  FAIL ', name, extra === undefined ? '' : JSON.stringify(extra)) }
}

await db.init()

console.log('\n[1] feeds 插入 / UNIQUE 去重 / 转义')
await db.execute(`INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (${sqlVal("O'Reilly's")}, ${sqlVal('http://a.com/rss')}, 'News', 1)`)
await db.execute(`INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES ('dup', ${sqlVal('http://a.com/rss')}, 'News', 2)`)
let feeds = await db.select('SELECT * FROM feeds ORDER BY id')
check('UNIQUE(url) 去重生效', feeds.length === 1, feeds.length)
check('单引号标题正确转义', feeds[0].title === "O'Reilly's", feeds[0].title)

console.log('\n[2] articles + plan_items')
const aid = await db.insertReturnId(`INSERT INTO articles (guid, title, sourceUrl, html, plainText, wordCount, capturedAt) VALUES ('g1', ${sqlVal('Title with "quotes" & \'apos\'')}, 'u', '<p>x</p>', 'hello world', 2, 100)`)
check('insertReturnId 返回自增 id', aid === 1, aid)
await db.execute(`INSERT OR IGNORE INTO plan_items (articleId, addedAt, status) VALUES (${sqlVal(aid)}, 1, 'pending')`)
await db.execute(`INSERT OR IGNORE INTO plan_items (articleId, addedAt, status) VALUES (${sqlVal(aid)}, 2, 'pending')`)
const plan = await db.select('SELECT articleId FROM plan_items')
check('plan_items UNIQUE(articleId)', plan.length === 1, plan.length)

console.log('\n[3] question_sets + questions + JOIN/GROUP BY/COUNT')
const setId = await db.insertReturnId(`INSERT INTO question_sets (articleId, presetId, title, createdAt) VALUES (${sqlVal(aid)}, NULL, 'set A', 10)`)
for (let i = 1; i <= 3; i++) {
  await db.execute(`INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) VALUES (${sqlVal(setId)}, 'choice', 'exact', ${sqlVal('Q' + i)}, ${sqlVal(JSON.stringify(['A', 'B']))}, ${sqlVal(JSON.stringify(['A']))}, 'ana', 'quote', ${i})`)
}
const qs = await db.select(`SELECT * FROM questions WHERE setId = ${sqlVal(setId)} ORDER BY id ASC`)
check('题目写入 3 条', qs.length === 3, qs.length)
check('options JSON 保真', JSON.parse(qs[0].options).length === 2)
const grouped = await db.select('SELECT s.id, s.articleId, COUNT(q.id) AS qcount FROM question_sets s LEFT JOIN questions q ON q.setId = s.id GROUP BY s.id')
check('LEFT JOIN + GROUP BY + COUNT', grouped.length === 1 && Number(grouped[0].qcount) === 3, grouped)
check('JOIN 后保留 articleId', String(grouped[0].articleId) === String(aid), grouped[0])

console.log('\n[4] 空题集 LEFT JOIN 计数为 0')
const emptySet = await db.insertReturnId(`INSERT INTO question_sets (articleId, presetId, title, createdAt) VALUES (${sqlVal(aid)}, NULL, 'empty', 11)`)
const grouped2 = await db.select('SELECT s.id, s.articleId, COUNT(q.id) AS qcount FROM question_sets s LEFT JOIN questions q ON q.setId = s.id GROUP BY s.id')
const emptyRow = grouped2.find((r) => String(r.id) === String(emptySet))
check('空题集 qcount=0', emptyRow && Number(emptyRow.qcount) === 0, grouped2)

console.log('\n[5] drafts upsert')
await db.execute(`INSERT INTO drafts (questionId, content, updatedAt) VALUES (${sqlVal(qs[0].id)}, 'draft1', 1)`)
await db.execute(`UPDATE drafts SET content = ${sqlVal("it's updated")}, updatedAt = 2 WHERE questionId = ${sqlVal(qs[0].id)}`)
const d = await db.select(`SELECT content FROM drafts WHERE questionId = ${sqlVal(qs[0].id)}`)
check('UPDATE + 转义', d[0].content === "it's updated", d[0])

console.log('\n[6] answers gradedAt / ORDER BY DESC / LIMIT')
for (let a = 1; a <= 3; a++) {
  await db.execute(`INSERT INTO answers (questionId, final, correct, wrong, status, comment, gradedAt) VALUES (${sqlVal(qs[0].id)}, ${sqlVal('ans' + a)}, ${a === 3 ? 1 : 0}, ${a === 3 ? 0 : 1}, 'graded', '', ${a})`)
}
const latest = await db.select(`SELECT * FROM answers WHERE questionId = ${sqlVal(qs[0].id)} ORDER BY gradedAt DESC LIMIT 1`)
check('ORDER BY DESC + LIMIT 取最新', latest.length === 1 && Number(latest[0].gradedAt) === 3, latest)
check('最新一次为正确', Number(latest[0].correct) === 1)

console.log('\n[7] IN 列表查询')
const ids = qs.map((q) => q.id)
const inRows = await db.select(`SELECT * FROM questions WHERE id IN (${ids.map(sqlVal).join(',')}) ORDER BY id ASC`)
check('IN 列表命中全部', inRows.length === 3, inRows.length)

console.log('\n[8] pending 状态过滤')
await db.execute(`INSERT INTO answers (questionId, final, correct, wrong, status, comment, gradedAt) VALUES (${sqlVal(qs[1].id)}, 'x', 0, 1, 'pending', 'AI 失败', 5)`)
const pend = await db.select("SELECT questionId, final FROM answers WHERE status = 'pending'")
check("WHERE status='pending'", pend.length === 1 && String(pend[0].questionId) === String(qs[1].id), pend)

console.log('\n[9] templates INSERT OR REPLACE / 长文本')
const tpl = "<html>{{title}}</html>\n{{#each questions}}<b>{{prompt}}</b>{{/each}} 'quoted'"
await db.execute(`INSERT INTO templates (name, source) VALUES ('default', ${sqlVal(tpl)})`)
const t = await db.select("SELECT source FROM templates WHERE name = 'default'")
check('模板长文本保真', t[0].source === tpl)

console.log('\n[10] 持久化：写入 storage（防抖 60ms）')
await new Promise((r) => setTimeout(r, 120))
const dump = store.get('go_mem_db')
check('已落 storage', typeof dump === 'string' && dump.length > 0)
const parsed = dump ? JSON.parse(dump) : {}
check('storage 内含 questions', parsed.questions && parsed.questions.rows.length === 3,
  parsed.questions && parsed.questions.rows.length)

console.log('\n[11] clearCache 只清缓存表')
await db.execute(`INSERT INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES (1, 'fi1', 't', 'l', 'p', 1, 1)`)
await db.execute(`INSERT INTO word_cache (word, mode, result, at) VALUES ('hi', 'en2zh', '{}', 1)`)
await db.clearCache()
const fi = await db.select('SELECT * FROM feed_items')
const wc = await db.select('SELECT * FROM word_cache')
const qAfter = await db.select('SELECT * FROM questions')
check('feed_items 已清空', fi.length === 0)
check('word_cache 已清空', wc.length === 0)
check('questions 保留', qAfter.length === 3, qAfter.length)

console.log('\n[12] word_cache INSERT OR REPLACE 覆盖')
await db.execute(`INSERT OR REPLACE INTO word_cache (word, mode, result, at) VALUES ('run', 'en2zh', '{"v":1}', 1)`)
await db.execute(`INSERT OR REPLACE INTO word_cache (word, mode, result, at) VALUES ('run', 'en2zh', '{"v":2}', 2)`)
await db.execute(`INSERT OR REPLACE INTO word_cache (word, mode, result, at) VALUES ('run', 'phrase', '{"v":3}', 3)`)
const wcAll = await db.select('SELECT * FROM word_cache')
const zh = await db.select(`SELECT result FROM word_cache WHERE word = 'run' AND mode = 'en2zh' LIMIT 1`)
check('同词同模式被覆盖为 1 条', wcAll.length === 2, wcAll.length)
check('覆盖后取到最新值', zh[0].result === '{"v":2}', zh[0])

console.log('\n[13] DELETE WHERE')
await db.execute(`DELETE FROM answers WHERE questionId = ${sqlVal(qs[0].id)}`)
const leftAns = await db.select(`SELECT * FROM answers WHERE questionId = ${sqlVal(qs[0].id)}`)
check('DELETE 生效', leftAns.length === 0)

console.log('\n[14] safeGuid SQL 注入防护与字符串包裹')
const { safeGuid } = db
// 白名单 URL：原样包在单引号内
check(
  'URL 风格 guid 带单引号包裹',
  safeGuid('https://www.npr.org/2026/08/10/abc-123') === `'https://www.npr.org/2026/08/10/abc-123'`,
  safeGuid('https://www.npr.org/2026/08/10/abc-123')
)
// 含单引号：转义为 ''（SQL 标准）
check(
  "含单引号被双写转义",
  safeGuid("o'reilly-tag") === `'o''reilly-tag'`,
  safeGuid("o'reilly-tag")
)
// 含分号/空格（不在白名单）：逐字符 \x 转义阻断注入
const dirty = "abc; DROP TABLE articles-- x"
const sg = safeGuid(dirty)
check('注入串仍带单引号包裹', sg.startsWith("'") && sg.endsWith("'"), sg)
check('分号被 \\x 转义', sg.includes('\\x3b'), sg)
check('空格被 \\x 转义', sg.includes('\\x20'), sg)
check('字母数字原样保留', sg.includes('abc') && sg.includes('DROP'), sg)
// 实际可执行的端到端验证：用含 URL/含注入串的 guid 走真实 SELECT 不应抛错
await db.execute(
  `INSERT OR IGNORE INTO articles (guid, title, sourceUrl, html, plainText, wordCount, capturedAt) VALUES (${safeGuid('https://example.com/a-b/c')}, 't1', 'u', '<p>x</p>', 'hello world', 2, 100)`
)
await db.execute(
  `INSERT OR IGNORE INTO articles (guid, title, sourceUrl, html, plainText, wordCount, capturedAt) VALUES (${safeGuid("o'reilly-x")}, 't2', 'u2', '<p>y</p>', 'hello world again', 2, 101)`
)
const got = await db.select(`SELECT guid FROM articles WHERE guid = ${safeGuid('https://example.com/a-b/c')} LIMIT 1`)
check('URL guid 端到端可查询', got.length === 1 && got[0].guid === 'https://example.com/a-b/c', got)
const got2 = await db.select(`SELECT guid FROM articles WHERE guid = ${safeGuid("o'reilly-x")} LIMIT 1`)
check("含单引号 guid 端到端可查询", got2.length === 1 && got2[0].guid === "o'reilly-x", got2)

console.log('\n[15] 参数化查询 ? 占位符')
{
  // 使用 ? 占位符执行 INSERT / SELECT / DELETE
  await db.execute(
    'INSERT OR IGNORE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [99, 'param-guid', 'Param Title', 'http://p', 'preview', 123, 456]
  )
  const rows = await db.select(
    'SELECT * FROM feed_items WHERE feedId = ? AND guid = ?',
    [99, 'param-guid']
  )
  check('SELECT 命中参数化条件', rows.length === 1 && rows[0].title === 'Param Title', rows)
  await db.execute(
    'DELETE FROM feed_items WHERE feedId = ? AND guid IN (?, ?)',
    [99, 'param-guid', 'none']
  )
  const after = await db.select('SELECT * FROM feed_items WHERE feedId = 99')
  check('DELETE 参数化生效', after.length === 0, after)
  // 字符串内的 ? 不应被替换
  await db.execute(
    "INSERT OR IGNORE INTO feed_items (feedId, guid, title) VALUES (?, ?, ?)",
    [98, 'q-mark', 'What?'] // 标题含问号不应被当作占位符
  )
  const qm = await db.select('SELECT * FROM feed_items WHERE feedId = 98')
  check('字符串内 ? 不被误替换', qm.length === 1 && qm[0].title === 'What?', qm)
  await db.execute('DELETE FROM feed_items WHERE feedId = 98')
}

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
