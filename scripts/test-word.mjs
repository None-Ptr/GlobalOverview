// 查词层测试：验证审查 #4（长按选区短语解析）与缓存分模式隔离
import { readFileSync } from 'fs'

const store = new Map()
let lastChatPrompt = ''
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
  request: (o) => {
    globalThis.__DICT_CALLS = (globalThis.__DICT_CALLS || 0) + 1
    setTimeout(() => o.success({
      statusCode: 200,
      data: [{ word: 'run', phonetic: '/rʌn/', meanings: [{ partOfSpeech: 'verb', definitions: [{ definition: 'to move fast', example: 'He runs.' }] }] }],
    }), 0)
  },
}

const b64 = (s) => 'data:text/javascript;base64,' + Buffer.from(s).toString('base64')
const dbUrl = b64(readFileSync('./src/utils/db.js', 'utf8'))
const fakeLlm = `
export function getProfiles(){ return [{id:'p1',name:'f',baseUrl:'http://x/v1',apiKey:'k',model:'m'}] }
export async function chat(profile, messages){
  globalThis.__LLM_CALLS = (globalThis.__LLM_CALLS||0)+1
  globalThis.__LAST_PROMPT = messages[0].content
  return 'LLM 解析结果'
}
`
let wordSrc = readFileSync('./src/utils/word.js', 'utf8')
// word.js 还相对导入 ./http.js（fetchText），data: URL 下无法解析相对路径，
// 这里也替换成内联 stub（查词测试不触发网络抓取，stub 仅满足模块加载）
const fakeHttp = `
export function request(opts) {
  return new Promise((resolve, reject) => {
    globalThis.uni.request({ ...opts, success: resolve, fail: reject })
  })
}
export async function fetchText(url, options = {}) {
  const res = await request({ url, method: 'GET', dataType: 'text', responseType: 'text', ...options })
  const d = res.data
  if (typeof d === 'string') return d
  if (d == null) return ''
  try { return JSON.stringify(d) } catch (e) { return String(d) }
}
`
const fakeTranslate = `
export async function translate() { throw new Error('stub') }
export async function detectLang() { throw new Error('stub') }
`
wordSrc = wordSrc
  .replace("from './db.js'", `from '${dbUrl}'`)
  .replace("from './llm.js'", `from '${b64(fakeLlm)}'`)
  .replace("from './http.js'", `from '${b64(fakeHttp)}'`)
  .replace("from './translate.js'", `from '${b64(fakeTranslate)}'`)
const word = await import(b64(wordSrc))

let pass = 0, fail = 0
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ', name) }
  else { fail++; console.log('  FAIL ', name, extra === undefined ? '' : JSON.stringify(extra)) }
}

console.log('\n[1] queryKind 判定单词 / 短语')
check('单词', word.queryKind('running') === 'word')
check('带连字符仍是单词', word.queryKind('well-known') === 'word')
check('两个词是短语', word.queryKind('give up') === 'phrase')
check('整句是短语', word.queryKind('He runs fast.') === 'phrase')
check('空白', word.queryKind('   ') === 'empty')
check('前后空白的单词', word.queryKind('  run  ') === 'word')

console.log('\n[2] normalizeQuery')
check('压缩空白', word.normalizeQuery('  give   up \n'), 'give up')
check('压缩空白值', word.normalizeQuery('  give   up \n') === 'give up')

console.log('\n[3] 单词走词典 API（en2en）')
const r1 = await word.lookupWord('run', 'en2en')
check('返回 dict 结构', r1.kind === 'dict', r1)
check('含音标', r1.phonetic === '/rʌn/')
check('含释义', r1.senses[0].definition === 'to move fast')
check('含例句', r1.senses[0].example === 'He runs.')

console.log('\n[4] 缓存命中，不重复请求')
const before = globalThis.__DICT_CALLS
await word.lookupWord('run', 'en2en')
check('第二次走缓存', globalThis.__DICT_CALLS === before, globalThis.__DICT_CALLS)

console.log('\n[5] 同词不同模式互不串味')
const r2 = await word.lookupWord('run', 'en2zh')
check('en2zh 走 LLM', r2.kind === 'text', r2)
check('en2zh 内容独立', r2.text === 'LLM 解析结果')
const r3 = await word.lookupWord('run', 'en2en')
check('en2en 仍是词典结果', r3.kind === 'dict', r3)

console.log('\n[6] 审查 #4：短语/选区走 LLM 并带上下文')
globalThis.__LLM_CALLS = 0
const r4 = await word.lookupWord('give up', 'en2zh', null, 'You should never give up on your dreams.')
check('返回 phrase 结构', r4.kind === 'phrase', r4)
check('调用了 LLM', globalThis.__LLM_CALLS === 1)
check('prompt 含短语', globalThis.__LAST_PROMPT.includes('give up'))
check('prompt 含上下文句', globalThis.__LAST_PROMPT.includes('never give up on your dreams'), globalThis.__LAST_PROMPT)
check('prompt 要求中文翻译', globalThis.__LAST_PROMPT.includes('中文翻译'))

console.log('\n[7] 短语缓存')
globalThis.__LLM_CALLS = 0
await word.lookupWord('give up', 'en2zh', null, 'another context')
check('短语第二次走缓存', globalThis.__LLM_CALLS === 0)

console.log('\n[8] 整句选区')
globalThis.__LLM_CALLS = 0
const r5 = await word.lookupWord('The quick brown fox jumps.', 'en2zh', null, '')
check('整句按 phrase 处理', r5.kind === 'phrase', r5)
check('触发 LLM', globalThis.__LLM_CALLS === 1)

console.log('\n[9] 空输入报错')
let threw = false
try { await word.lookupWord('   ', 'en2zh') } catch (e) { threw = true }
check('空输入抛错', threw)

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
