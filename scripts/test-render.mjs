// 模板渲染器测试：覆盖审查中 #1（模板初始化）与 #7（{{#if}} 空白容错）
import { readFileSync } from 'fs'

const store = new Map()
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
}

async function load(path) {
  const src = readFileSync(path, 'utf8')
  return import('data:text/javascript;base64,' + Buffer.from(src).toString('base64'))
}

// export.js 依赖 ./db.js，用相对路径无法在 data: URL 里解析，改为直接读源码拼装
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

console.log('\n[1] 基础插值与转义')
check('变量替换', render('Hi {{name}}!', { name: 'Bob' }), 'Hi Bob!')
check('HTML 转义', render('{{v}}', { v: '<b>&"' }), '&lt;b&gt;&amp;&quot;')
check('三花括号不转义', render('{{{v}}}', { v: '<b>' }), '<b>')
check('未知变量为空串', render('[{{nope}}]', {}), '[]')

console.log('\n[2] {{#if}} 空白容错（审查 #7）')
check('无空格', render('{{#if a}}Y{{/if}}', { a: 1 }), 'Y')
check('标签内含空格', render('{{# if  a }}Y{{/ if }}', { a: 1 }), 'Y')
check('假值不渲染', render('{{#if a}}Y{{/if}}', { a: 0 }), '')
check('空数组为假', render('{{#if a}}Y{{/if}}', { a: [] }), '')
check('空字符串为假', render('{{#if a}}Y{{/if}}', { a: '' }), '')
check('else 分支', render('{{#if a}}Y{{else}}N{{/if}}', { a: false }), 'N')

console.log('\n[3] {{#each}}')
check('对象数组', render('{{#each l}}[{{n}}]{{/each}}', { l: [{ n: 1 }, { n: 2 }] }), '[1][2]')
check('标量数组用 .', render('{{#each l}}<{{.}}>{{/each}}', { l: ['a', 'b'] }), '<a><b>')
check('index 从 1 开始', render('{{#each l}}{{index}}.{{/each}}', { l: ['a', 'b', 'c'] }), '1.2.3.')
check('空数组', render('X{{#each l}}Y{{/each}}Z', { l: [] }), 'XZ')
check('缺失列表', render('X{{#each nope}}Y{{/each}}Z', {}), 'XZ')

console.log('\n[4] 嵌套')
check('each 内嵌 if',
  render('{{#each l}}{{#if ok}}+{{else}}-{{/if}}{{/each}}', { l: [{ ok: 1 }, { ok: 0 }, { ok: 1 }] }),
  '+-+')
check('each 内可访问外层变量',
  render('{{#each l}}{{t}}{{n}} {{/each}}', { t: 'Q', l: [{ n: 1 }, { n: 2 }] }),
  'Q1 Q2 ')
check('嵌套 each',
  render('{{#each a}}({{#each b}}{{.}}{{/each}}){{/each}}', { a: [{ b: [1, 2] }, { b: [3] }] }),
  '(12)(3)')

console.log('\n[5] 默认模板端到端')
const html = await exp.buildHtml({
  title: '测试卷',
  subtitle: '子标题',
  questions: [
    { type: 'choice', prompt: '选哪个?', options: ['A', 'B'], answer: 'A', analysis: '因为 A', sourceQuote: '原句', mine: 'B' },
    { type: 'fill', prompt: '填空', options: [], answer: 'x', analysis: '', sourceQuote: '', mine: '' },
  ],
  options: { withAnswer: true, withAnalysis: true, withMine: true },
})
check('渲染出题干1', html.includes('选哪个?'), true)
check('渲染出题干2', html.includes('填空'), true)
check('渲染选项', html.includes('<div class="opt">A</div>'), true)
check('显示参考答案', html.includes('参考答案：A'), true)
check('显示我的作答', html.includes('我的作答：B'), true)
check('显示解析', html.includes('因为 A'), true)
check('无残留标签', /\{\{|\}\}/.test(html), false)
check('题号正确', html.includes('1. 选哪个?') && html.includes('2. 填空'), true)

console.log('\n[6] 关闭开关时不渲染答案')
const html2 = await exp.buildHtml({
  title: 'T',
  questions: [{ type: 'fill', prompt: 'P', options: [], answer: 'SECRET', analysis: 'A', sourceQuote: '', mine: 'M' }],
  options: { withAnswer: false, withAnalysis: false, withMine: false },
})
check('答案已隐藏', html2.includes('SECRET'), false)
check('解析已隐藏', html2.includes('参考答案'), false)
check('我的作答已隐藏', html2.includes('我的作答'), false)
check('题干仍在', html2.includes('P'), true)

console.log('\n[7] 模板持久化（审查 #1：默认模板必须真的写库）')
const t1 = await exp.getTemplate('default')
check('取到默认模板', t1.length > 100, true)
const rows = await (await import(dbB64)).db.select("SELECT source FROM templates WHERE name = 'default'")
check('default 行已写入 templates 表', rows.length === 1, true)
await exp.saveTemplate('default', '<p>{{title}}</p>')
check('保存后读回自定义模板', await exp.getTemplate('default'), '<p>{{title}}</p>')
const rows2 = await (await import(dbB64)).db.select("SELECT source FROM templates WHERE name = 'default'")
check('未产生重复行', rows2.length === 1, true)
const reset = await exp.resetTemplate('default')
check('恢复默认成功', reset === exp.DEFAULT_TEMPLATE, true)

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
