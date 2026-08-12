// PDF 导出模块测试：buildHtml 四开关产出 + 渲染器嵌套 else 边界 + 入参防御
import { readFileSync } from 'fs'

const store = new Map()
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
}

const dbSrc = readFileSync('./src/utils/db.js', 'utf8')
const dbB64 = 'data:text/javascript;base64,' + Buffer.from(dbSrc).toString('base64')
let expSrc = readFileSync('./src/utils/export.js', 'utf8')
expSrc = expSrc.replace("from './db.js'", `from '${dbB64}'`)
const exp = await import('data:text/javascript;base64,' + Buffer.from(expSrc).toString('base64'))

const { render } = exp._internal
let pass = 0, fail = 0
function check(name, actual, expected) {
  if (actual === expected) { pass++; console.log('  ok   ', name) }
  else { fail++; console.log('  FAIL ', name, '\n    实际:', JSON.stringify(actual), '\n    期望:', JSON.stringify(expected)) }
}

console.log('\n[A] buildHtml 四开关产出')
const sample = [
  { type: 'choice', prompt: '选哪个?', options: ['A', 'B'], answer: 'A', analysis: '因为 A', sourceQuote: '原句', mine: 'B' },
  { type: 'fill', prompt: '填空', options: [], answer: '', analysis: '', sourceQuote: '', mine: '' },
]

// 全开：原文引用应出现
const allOn = await exp.buildHtml({
  title: 'T', questions: sample,
  options: { withAnswer: true, withAnalysis: true, withMine: true, withQuote: true },
})
check('含参考答案', allOn.includes('参考答案：A'), true)
check('含解析', allOn.includes('因为 A'), true)
check('含我的作答', allOn.includes('我的作答：B'), true)
check('含原文引用(开关开)', allOn.includes('原句'), true)
check('无残留标签', /\{\{|\}\}/.test(allOn), false)

// 关闭原文引用开关：sourceQuote 存在但不渲染
const quoteOff = await exp.buildHtml({
  title: 'T', questions: sample,
  options: { withAnswer: true, withAnalysis: true, withMine: true, withQuote: false },
})
check('关引用后不渲染原句', quoteOff.includes('原句'), false)
check('关引用不影响答案', quoteOff.includes('参考答案：A'), true)

// 答案开关关闭但 answer 非空：不应渲染空「参考答案：」
const ansOff = await exp.buildHtml({
  title: 'T', questions: sample,
  options: { withAnswer: false, withAnalysis: true, withMine: true, withQuote: true },
})
check('关闭答案后隐藏参考答案', ansOff.includes('参考答案'), false)
check('解析仍显示', ansOff.includes('因为 A'), true)

// 题干2 无 answer：全开时也不应出现空「参考答案：」
check('空答案题不产生空参考答案行', (ansOff.match(/参考答案：/g) || []).length, 0)

console.log('\n[B] buildHtml 入参防御（空 questions 不抛错）')
const empty = await exp.buildHtml({ title: 'T', questions: null, options: {} })
check('null questions 渲染为 0 题', empty.includes('共 0 题'), true)
check('null 不抛 TypeError', /\{\{|\}\}/.test(empty), false)

console.log('\n[C] 嵌套 if 的 else 边界（审查 #13）')
// 外层 if a 为真、内层 if b 为假时，内层走自己的 else(Y)，外层不该误吞
check('嵌套 if+else 正确切分',
  render('{{#if a}}[{{#if b}}B{{else}}Y{{/if}}]{{else}}Z{{/if}}', { a: 1, b: 0 }),
  '[Y]')
check('外层 else 生效',
  render('{{#if a}}[{{#if b}}B{{else}}Y{{/if}}]{{else}}Z{{/if}}', { a: 0, b: 0 }),
  'Z')
check('内层为真取 B',
  render('{{#if a}}[{{#if b}}B{{else}}Y{{/if}}]{{else}}Z{{/if}}', { a: 1, b: 1 }),
  '[B]')

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
