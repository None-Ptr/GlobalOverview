// 判分层测试：重点验证审查 #3（AI 判分失败不得伪造 0 分）与 #5/#6（草稿分离、历史保留）
import { readFileSync } from 'fs'

const store = new Map()
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
  request: () => { throw new Error('不应触发真实网络请求') },
}

const b64 = (s) => 'data:text/javascript;base64,' + Buffer.from(s).toString('base64')
const dbUrl = b64(readFileSync('./src/utils/db.js', 'utf8'))

// 用可控的假 llm 模块替换真实网络调用
let llmBehavior = 'ok'
const fakeLlm = `
export function getProfiles(){ return [{id:'p1',name:'fake',baseUrl:'http://x/v1',apiKey:'k',model:'m'}] }
export async function chat(){
  const mode = globalThis.__LLM_MODE
  if (mode === 'fail') throw new Error('网络超时')
  if (mode === 'garbage') return { nonsense: true }
  return { correct: 1, comment: 'AI 认为正确' }
}
`
const llmUrl = b64(fakeLlm)

let gradeSrc = readFileSync('./src/utils/grade.js', 'utf8')
gradeSrc = gradeSrc.replace("from './db.js'", `from '${dbUrl}'`).replace("from './llm.js'", `from '${llmUrl}'`)
const grade = await import(b64(gradeSrc))

const { db } = await import(dbUrl)
const { sqlVal } = db

let pass = 0, fail = 0
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ', name) }
  else { fail++; console.log('  FAIL ', name, extra === undefined ? '' : JSON.stringify(extra)) }
}

await db.init()
const setId = await db.insertReturnId("INSERT INTO question_sets (articleId, presetId, title, createdAt) VALUES (1, NULL, 's', 1)")
async function mkQ(type, gradeMode, answers) {
  return db.insertReturnId(
    `INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) VALUES (`
    + `${sqlVal(setId)}, ${sqlVal(type)}, ${sqlVal(gradeMode)}, 'p', '[]', ${sqlVal(JSON.stringify(answers))}, 'a', 'q', 1)`
  )
}

console.log('\n[1] exact 判分')
const q1 = await mkQ('choice', 'exact', ['Paris'])
let r = await grade.gradeBatch([{ questionId: q1, final: 'Paris' }])
check('完全匹配为正确', r.results[0].correct === 1)
check('状态为 graded', r.results[0].status === 'graded')
r = await grade.gradeBatch([{ questionId: q1, final: ' paris. ' }])
check('大小写/标点归一化后仍正确', r.results[0].correct === 1, r.results[0])
r = await grade.gradeBatch([{ questionId: q1, final: 'London' }])
check('不匹配为错误', r.results[0].correct === 0)
r = await grade.gradeBatch([{ questionId: q1, final: '' }])
check('空作答为错误', r.results[0].correct === 0)
check('空作答提示未作答', r.results[0].comment.includes('未作答'))

console.log('\n[2] contains 判分')
const q2 = await mkQ('shortAnswer', 'contains', ['photosynthesis'])
r = await grade.gradeBatch([{ questionId: q2, final: 'It is about photosynthesis in plants' }])
check('包含关键词为正确', r.results[0].correct === 1)
r = await grade.gradeBatch([{ questionId: q2, final: 'respiration' }])
check('不含关键词为错误', r.results[0].correct === 0)

console.log('\n[3] AI 判分成功')
globalThis.__LLM_MODE = 'ok'
const q3 = await mkQ('shortAnswer', 'ai', ['any'])
r = await grade.gradeBatch([{ questionId: q3, final: '我的回答' }])
check('AI 判为正确', r.results[0].correct === 1)
check('状态 graded', r.results[0].status === 'graded')
check('graded 计数', r.graded === 1 && r.pending === 0, r)

console.log('\n[4] 审查 #3：AI 判分失败必须 pending，不得伪造 0 分')
globalThis.__LLM_MODE = 'fail'
const q4 = await mkQ('shortAnswer', 'ai', ['any'])
r = await grade.gradeBatch([{ questionId: q4, final: '我的回答' }])
check('状态为 pending', r.results[0].status === 'pending', r.results[0])
check('pending 计数为 1', r.pending === 1, r)
check('errors 暴露原因', r.errors.length === 1 && r.errors[0].message.includes('超时'), r.errors)
check('comment 说明未完成', r.results[0].comment.includes('判分未完成'), r.results[0].comment)

console.log('\n[5] AI 返回格式异常也算 pending')
globalThis.__LLM_MODE = 'garbage'
const q5 = await mkQ('shortAnswer', 'ai', ['any'])
r = await grade.gradeBatch([{ questionId: q5, final: 'x' }])
check('格式异常 -> pending', r.results[0].status === 'pending', r.results[0])

console.log('\n[6] regradePending：恢复网络后可重判')
globalThis.__LLM_MODE = 'ok'
const rr = await grade.regradePending()
check('重判了 2 道 pending', rr.graded === 2, rr)
const stillPending = await db.select("SELECT * FROM answers WHERE status = 'pending'")
// 注意：重判是追加新 attempt，旧 pending 行仍在，但最新一次应为 graded
const latest4 = await grade.latestAnswer(q4)
check('q4 最新一次已 graded', latest4.status === 'graded', latest4)
check('q4 最新一次为正确', Number(latest4.correct) === 1, latest4)
void stillPending

console.log('\n[7] 审查 #5：草稿存 answers.draft，判分不互相覆盖')
const q6 = await mkQ('fill', 'exact', ['abc'])
await db.saveDraft(q6, '草稿内容')
let d = await db.loadDrafts([q6])
check('草稿可读回', d[q6] === '草稿内容', d)
const ansRows = await db.select(`SELECT * FROM answers WHERE questionId = ${sqlVal(q6)}`)
check('写草稿产生占位行', ansRows.length === 1 && ansRows[0].draft === '草稿内容', ansRows.length)
await grade.gradeBatch([{ questionId: q6, final: 'abc' }])
d = await db.loadDrafts([q6])
check('判分不清除草稿（由页面显式清）', d[q6] === '草稿内容')
await db.clearDrafts([q6])
d = await db.loadDrafts([q6])
check('clearDrafts 生效', d[q6] === '' || d[q6] === undefined, d)

console.log('\n[8] 审查 #6：重做保留历史，可取上次答案')
await grade.gradeBatch([{ questionId: q6, final: 'wrong-answer' }])
const hist = await db.loadHistory([q6])
check('历史累计 2 次', hist[q6].length === 2, hist[q6] && hist[q6].length)
check('按时间升序', hist[q6][0].gradedAt <= hist[q6][1].gradedAt, hist[q6])
check('第一次为正确(abc)', Number(hist[q6][0].correct) === 1)
check('最后一次为错误', Number(hist[q6][1].correct) === 0)
check('保留上次原文答案', hist[q6][0].final === 'abc', hist[q6][0])

console.log('\n[9] 错题标记 wrong=1')
const wrongRows = await db.select(`SELECT * FROM answers WHERE questionId = ${sqlVal(q6)} ORDER BY gradedAt DESC LIMIT 1`)
check('最近一次 wrong=1', Number(wrongRows[0].wrong) === 1, wrongRows[0])

console.log('\n[10] 题目不存在时报错而非崩溃')
r = await grade.gradeBatch([{ questionId: 99999, final: 'x' }])
check('errors 含题目不存在', r.errors.length === 1 && r.errors[0].message.includes('不存在'), r.errors)

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
