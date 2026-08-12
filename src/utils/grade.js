// 判分层：本地规则判分 + AI 判分
// 关键约束：AI 判分失败不得静默记 0 分，必须落 status='pending' 并向上层报告，
// 用户可在做题页/错题本对 pending 项发起「重新判分」。
import { db } from './db.js'
import { chat, getProfiles } from './llm.js'

const { sqlVal } = db

function safeParse(json, fallback) {
  try { const v = JSON.parse(json); return v == null ? fallback : v } catch (e) { return fallback }
}

function norm(s) {
  return String(s == null ? '' : s)
    .toLowerCase()
    .replace(/[\s\u3000]+/g, ' ')
    .replace(/[.,;:!?，。；：！？、"'"'()（）]/g, '')
    .trim()
}

function gradeExact(final, answers) {
  const f = norm(final)
  if (!f) return { correct: 0, comment: '未作答' }
  const ok = answers.some((a) => norm(a) === f)
  return { correct: ok ? 1 : 0, comment: ok ? '完全匹配' : `应为：${answers.join(' / ')}` }
}

function gradeContains(final, answers) {
  const f = norm(final)
  if (!f) return { correct: 0, comment: '未作答' }
  const ok = answers.some((a) => { const n = norm(a); return n && (f.includes(n) || n.includes(f)) })
  return { correct: ok ? 1 : 0, comment: ok ? '关键点命中' : `应包含：${answers.join(' / ')}` }
}

async function gradeAi(q, final, profile) {
  const answers = safeParse(q.answers, [])
  const messages = [
    {
      role: 'system',
      content: '你是严谨的外语考试阅卷老师。根据参考答案与原文依据判定学生作答是否正确，'
        + '允许合理的同义表达。只输出 JSON：{"correct":0或1,"comment":"一句话中文点评"}。',
    },
    {
      role: 'user',
      content: [
        `题型：${q.type}`,
        `题干：${q.prompt}`,
        q.sourceQuote ? `原文依据：${q.sourceQuote}` : '',
        `参考答案：${answers.join(' / ')}`,
        `学生作答：${final}`,
      ].filter(Boolean).join('\n'),
    },
  ]
  const raw = await chat(profile, messages, { json: true, temperature: 0 })
  const parsed = safeParse(typeof raw === 'string' ? raw : JSON.stringify(raw), null)
  if (!parsed || (parsed.correct !== 0 && parsed.correct !== 1)) throw new Error('AI 判分返回格式异常')
  return { correct: Number(parsed.correct), comment: String(parsed.comment || '') }
}

// 单题判分。失败时抛错，由 gradeBatch 统一转为 pending。
async function gradeOne(q, final, profile) {
  const answers = safeParse(q.answers, [])
  const mode = q.gradeMode || 'exact'
  if (mode === 'ai') {
    if (!profile) throw new Error('未配置 LLM，无法进行 AI 判分')
    return gradeAi(q, final, profile)
  }
  if (mode === 'contains') return gradeContains(final, answers)
  return gradeExact(final, answers)
}

// 写入判分结果：每次判分 INSERT 新行（保留历史，init §6）。
// gradedAt 单调递增，避免同毫秒内多条判分 ORDER BY 不稳定。
// 草稿占位行（gradedAt=0）不在此删除——由页面交卷后调用 db.clearDrafts 清空。
async function writeResult(questionId, final, result) {
  await db.init()
  const existing = await db.select(
    `SELECT gradedAt FROM answers WHERE questionId = ${sqlVal(questionId)} ORDER BY gradedAt DESC LIMIT 1`
  )
  const maxG = existing && existing.length ? Number(existing[0].gradedAt) || 0 : 0
  const now = Math.max(Date.now(), maxG + 1)
  await db.execute(
    `INSERT INTO answers (questionId, final, correct, wrong, status, comment, gradedAt) VALUES (`
    + `${sqlVal(questionId)}, ${sqlVal(final)}, ${sqlVal(result.correct)}, ${sqlVal(result.correct === 1 ? 0 : 1)}, `
    + `${sqlVal(result.status || 'graded')}, ${sqlVal(result.comment || '')}, ${sqlVal(now)})`
  )
}

/**
 * 批量判分。
 * @param items [{ questionId, final }]
 * @returns { results: [...], pending: n, graded: n, errors: [...] }
 *   单条 result: { questionId, correct, comment, status }
 *   status='pending' 表示 AI 判分失败、结果不可信，需要重判。
 */
export async function gradeBatch(items) {
  await db.init()
  const profiles = getProfiles()
  const profile = profiles && profiles.length ? profiles[0] : null

  const results = []
  const errors = []
  let pending = 0
  let graded = 0

  for (const it of items) {
    const rows = await db.select(`SELECT * FROM questions WHERE id = ${sqlVal(it.questionId)}`)
    if (!rows || !rows.length) {
      errors.push({ questionId: it.questionId, message: '题目不存在' })
      continue
    }
    const q = rows[0]
    let result
    try {
      result = await gradeOne(q, it.final, profile)
      result.status = 'graded'
      graded++
    } catch (e) {
      // 关键：不伪造 0 分，标记 pending 并保留错误原因
      result = {
        correct: 0,
        comment: `判分未完成：${e.message || '未知错误'}`,
        status: 'pending',
      }
      pending++
      errors.push({ questionId: it.questionId, message: e.message || '判分失败' })
    }
    await writeResult(it.questionId, it.final, result)
    results.push({ questionId: it.questionId, ...result })
  }

  return { results, pending, graded, errors }
}

/** 对所有 status='pending' 的作答重新判分（可指定题集） */
export async function regradePending(setId = null) {
  await db.init()
  // 内存引擎不支持子查询，先取题目 id 再用 IN 列表
  let rows
  if (setId == null) {
    rows = await db.select("SELECT questionId, final FROM answers WHERE status = 'pending'")
  } else {
    const qs = await db.select(`SELECT id FROM questions WHERE setId = ${sqlVal(setId)}`)
    const ids = qs.map((q) => q.id)
    if (!ids.length) return { results: [], pending: 0, graded: 0, errors: [] }
    rows = await db.select(
      `SELECT questionId, final FROM answers WHERE status = 'pending' AND questionId IN (${ids.map(sqlVal).join(',')})`
    )
  }
  const uniq = new Map()
  for (const r of rows) uniq.set(r.questionId, r.final)
  const items = [...uniq.entries()].map(([questionId, final]) => ({ questionId, final }))
  if (!items.length) return { results: [], pending: 0, graded: 0, errors: [] }
  return gradeBatch(items)
}

/** 读取某题最近一次判分结果 */
export async function latestAnswer(questionId) {
  await db.init()
  const rows = await db.select(`SELECT * FROM answers WHERE questionId = ${sqlVal(questionId)} ORDER BY gradedAt DESC LIMIT 1`)
  return rows && rows.length ? rows[0] : null
}
