// 出题引擎：根据文章正文 + 预设，调用 LLM 批量生成题集
// 输出严格落 JSON Schema（Schema 是宪法）

import { db } from './db.js'
import { chat, getProfiles } from './llm.js'

const { sqlVal } = db

export const EXAM_MAP = {
  PTJH: "小升初，禁止题目中出现未翻译的学术用语和高级词汇，主要考察信息检索能力。",
  SHSEE: "中考，题目中仅可少量出现未翻译的高级词汇，不应出现未经翻译的学术用语，并考察较弱的推理能力。",
  NCEE: "高考，需要考察综合应用能力，允许出现极少量（不超过2%）可通过构词法或上下文推导的学术词汇，严禁出现依赖专业背景的裸奔生僻词；重点考察复杂推理、高阶信息检索（区分事实与观点），以及对作者隐含态度和篇章结构的深层理解。",
  CET4: '大学英语四级（词汇量约 4000），侧重同义替换与基本事实定位。',
  CET6: '大学英语六级（词汇量约 5500），侧重长难句解构与抽象概念的具体化转述。',
  TEM4: '英语专业四级（词汇量约 5500~6500），侧重语言学基础知识、文学常识、修辞手法和篇章结构的细粒度理解。',
  TEM8: '英语专业八级（词汇量约 8000~10000，认知词汇量达 13000），考察文学修辞手法赏析、学术文本批判性思维及语言学逻辑。',
  IELTS: '雅思（学术类，7+ 分目标），侧重扫读+精读效率切换，题型复杂（含判断/摘要），要求区分主次信息。',
  TOEFL: '托福（100+ 分目标），侧重学科背景下的短期记忆负荷，重点考察总结题（排除次要细节）和指代关系。',
  GRE: 'GRE（美国研究生入学），阅读文本词汇不偏怪，但逻辑极度复杂（多重嵌套、预设与反驳），重点考察基于文本证据的推理和作者态度微妙变化。',
  GMAT: 'GMAT（管理学研究生），阅读部分侧重论证结构分析和批判性推理（如削弱/加强/假设识别），文本多涉及商业决策、生物科技等跨领域议题。',
  SAT: 'SAT（美国本科入学），侧重历史文献类（建国文献/演说）的复古句式和循证阅读（必须找出上一题答案的原文证据），考察双篇对比关系。',
}

function buildPrompt(article, preset, count) {
  // preset.exam 未指定时回落到全局目标（store.globalGoal 由调用方透传）
  const examKey = preset.exam || preset.globalGoal || 'CET6'
  const exam = EXAM_MAP[examKey] || examKey
  const types = (preset.types && preset.types.length) ? preset.types.join('、') : '选择题(包括判断题)、填空题、简答题'
  const focus = preset.focus || '词汇、句意理解、文中场景实际运用、文中提到内容检索推理'
  const lang = preset.analysisLang === 'en' ? 'English' : '中文'
  return `你是一位英语教学出题专家。请基于下面的英文原文，出 ${count} 道题目。

# 约束
- 对标考试：${exam}
- 题型要求：${types}
- 考察重点：${focus}
- 解析语言：${lang}

# 题目 Schema（必须严格遵循，禁止任何额外字段）
每题是一个对象，包含：
- type: 渲染类型，取值 choice（单选）/ fill（填空）/ shortAnswer（简答）/ general（通用文本）
- gradeMode: 判分方式，取值 exact（精确匹配）/ contains（包含即给分）/ ai（AI 判分）/ manual（人工）
- prompt: 题干（字符串）
- options: 选择题的选项数组（非选择题给空数组 []）
- answers: 标准答案字符串数组（选择题存选项内容，非下标）
- analysis: 解析（${lang}）
- sourceQuote: 原文对应原句（永远输出，字符串）

# 输出格式
严格输出 JSON 对象：{"questions": [ ... ]}，不要任何解释、不要 markdown 代码块。

# 原文
"""
${String(article.plainText || '').slice(0, 6000)}
"""`
}

function normalizeQuestion(q) {
  const type = ['choice', 'fill', 'shortAnswer', 'general'].includes(q.type) ? q.type : 'general'
  let gradeMode = ['exact', 'contains', 'ai', 'manual'].includes(q.gradeMode) ? q.gradeMode : 'ai'
  // 选择题一律精确判分，避免无谓消耗 AI 额度
  if (type === 'choice') gradeMode = 'exact'
  return {
    type,
    gradeMode,
    prompt: String(q.prompt || '').trim(),
    options: Array.isArray(q.options) ? q.options.map(String) : [],
    answers: Array.isArray(q.answers)
      ? q.answers.map(String)
      : (q.answers == null ? [] : [String(q.answers)]),
    analysis: String(q.analysis || ''),
    sourceQuote: String(q.sourceQuote || ''),
  }
}

/**
 * 生成一套题集。
 * @returns { setId, ok, failed, failures }
 * 若一题都没成功，会回滚空题集并抛错，避免留下幽灵题集。
 */
export async function generateSet({ article, preset = {}, profile, count = 5 }) {
  await db.init()

  let useProfile = profile
  if (!useProfile) { const list = getProfiles(); useProfile = list && list.length ? list[0] : null }
  if (!useProfile) throw new Error('未配置 LLM，请先到「我的」页面添加模型配置')
  if (!article || !article.id) throw new Error('文章数据缺失')
  if (!article.plainText || article.plainText.length < 50) throw new Error('正文过短，无法出题')

  const msgs = [{ role: 'user', content: buildPrompt(article, preset, count) }]
  const raw = await chat(useProfile, msgs, { json: true, temperature: 0.7 })
  const list = Array.isArray(raw) ? raw : (raw && raw.questions)
  if (!Array.isArray(list) || !list.length) throw new Error('LLM 未返回题目数组')

  const setTitle = `${article.title || '未命名'} · 第 ${await nextSetIndex(article.id)} 套`
  const setId = await db.insertReturnId(
    'INSERT INTO question_sets (articleId, presetId, title, createdAt) VALUES ('
    + `${sqlVal(article.id)}, ${sqlVal(preset.id == null ? null : preset.id)}, `
    + `${sqlVal(setTitle)}, ${sqlVal(Date.now())})`
  )

  let ok = 0
  const failures = []
  for (const q of list) {
    try {
      const nq = normalizeQuestion(q)
      if (!nq.prompt) { failures.push('题干为空'); continue }
      if (nq.type === 'choice' && nq.options.length < 2) { failures.push('选择题选项不足'); continue }
      await db.execute(
        'INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) VALUES ('
        + `${sqlVal(setId)}, ${sqlVal(nq.type)}, ${sqlVal(nq.gradeMode)}, ${sqlVal(nq.prompt)}, `
        + `${sqlVal(JSON.stringify(nq.options))}, ${sqlVal(JSON.stringify(nq.answers))}, `
        + `${sqlVal(nq.analysis)}, ${sqlVal(nq.sourceQuote)}, ${sqlVal(Date.now())})`
      )
      ok++
    } catch (e) { failures.push(e.message || '写入失败') }
  }

  if (ok === 0) {
    await db.execute(`DELETE FROM question_sets WHERE id = ${sqlVal(setId)}`)
    throw new Error(`出题失败：${failures[0] || '模型返回的题目均不合法'}`)
  }

  return { setId, ok, failed: failures.length, failures }
}

async function nextSetIndex(articleId) {
  const rows = await db.select(`SELECT id FROM question_sets WHERE articleId = ${sqlVal(articleId)}`)
  return (rows ? rows.length : 0) + 1
}

// 重新出题 = 新增题集（非覆盖），复用 generateSet
export async function regenerateSet(params) {
  return generateSet(params)
}

/** 读取题集的题目列表（含解析后的 options/answers） */
export async function loadSet(setId) {
  await db.init()
  const rows = await db.select(`SELECT * FROM questions WHERE setId = ${sqlVal(setId)} ORDER BY id ASC`)
  return rows.map((q) => ({
    ...q,
    options: safeParse(q.options, []),
    answerList: safeParse(q.answers, []),
  }))
}

/** 按 id 列表读题（错题本重做用） */
export async function loadQuestionsByIds(ids) {
  await db.init()
  if (!ids || !ids.length) return []
  const rows = await db.select(
    `SELECT * FROM questions WHERE id IN (${ids.map(sqlVal).join(',')}) ORDER BY id ASC`
  )
  return rows.map((q) => ({
    ...q,
    options: safeParse(q.options, []),
    answerList: safeParse(q.answers, []),
  }))
}

function safeParse(json, fallback) {
  try { const v = JSON.parse(json); return v == null ? fallback : v } catch (e) { return fallback }
}

export function typeLabel(t) {
  return { choice: '选择', fill: '填空', shortAnswer: '简答', general: '问答' }[t] || '问答'
}
