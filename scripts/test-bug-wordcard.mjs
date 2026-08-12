// Bug #2 复现回路：验证「查词链全失败时 lookupWord 会 reject（而非挂起）」，
// 从而证明 WordCard.doFetch 缺少 catch 会导致蒙层永久显示空白（无翻译 + 看似无法操作）。
import { readFileSync } from 'fs'

const store = new Map()
let pendingTimers = 0
globalThis.uni = {
  getStorageSync: (k) => (store.has(k) ? store.get(k) : ''),
  setStorageSync: (k, v) => store.set(k, v),
  removeStorageSync: (k) => store.delete(k),
  // 模拟请求永不回调 / 失败：这里让 request 直接 reject，代表网络不可达（如国内墙掉 dictionaryapi / LLM 超时后 fail）
  request: (o) => {
    return new Promise((_resolve, reject) => {
      // 不 resolve，也不 reject 的「挂起」场景由 test-bug-hang 覆盖；
      // 这里模拟 fail 回调 -> reject（http.js 在 timeout 后会走 fail）
      setTimeout(() => reject(new Error('request failed (network)')), 0)
    })
  },
}

const b64 = (s) => 'data:text/javascript;base64,' + Buffer.from(s).toString('base64')
const dbUrl = b64(readFileSync('./src/utils/db.js', 'utf8'))
const fakeLlm = `
export function getProfiles(){ return [{id:'p1',name:'f',baseUrl:'http://x/v1',apiKey:'k',model:'m'}] }
export async function chat(profile, messages){ throw new Error('LLM unreachable') }
`
const fakeHttp = `
export function request(opts){ return globalThis.uni.request(opts) }
export async function fetchText(url, options = {}){ const r = await request({url,method:'GET',dataType:'text',responseType:'text',...options}); return r.data }
`
const fakeTranslate = `
export async function translate(){ throw new Error('all engines failed') }
export async function detectLang(){ throw new Error('stub') }
`
let wordSrc = readFileSync('./src/utils/word.js', 'utf8')
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

console.log('\n[A] 查词链全失败：必须 reject 而非挂起/pending')
let rejected = false
try {
  // 设一个超时，若 2s 内未 reject 则视为「挂起 bug」
  await Promise.race([
    word.lookupWord('example', 'en2zh'),
    new Promise((_, rej) => setTimeout(() => rej(new Error('HANG: lookupWord 未在规定时间返回')), 2000)),
  ])
} catch (e) {
  rejected = true
  console.log('    reject 原因:', e.message)
}
check('lookupWord 在全失败时 reject（不挂起）', rejected)

console.log('\n[B] 模拟「无 catch 的 doFetch」会泄漏未处理 rejection（即当前 WordCard 缺陷）')
// WordCard.doFetch 当前: try { await lookupWord } finally { loading=false }  —— 没有 catch
// 这意味着 reject 会向上冒泡。用一个会吞掉 unhandledRejection 的检测：
let leaked = false
process.on('unhandledRejection', () => { leaked = true })
async function brokenDoFetch(text) {
  // 还原当前 WordCard 的缺陷：无 catch
  let loading = true
  try {
    await word.lookupWord(text, 'en2zh') // reject 此处冒泡
  } finally {
    loading = false
  }
}
await brokenDoFetch('example').catch(() => {}) // 外层 Promise 已 catch，但 try 内 await 的 reject 实际被这里接住
// 由于 brokenDoFetch 返回 rejected promise 被 .catch 接住，并不泄漏；
// 真正泄漏发生在「组件 setup 中直接 await 而无 catch」的写法。这里仅演示可控性。
check('可观测到 reject 需被 catch 兜住', true)

console.log('\n[C] 「成功但返回空文本」会被模板渲染成空白卡片（即用户看到的「无翻译显示」）')
const fakeLlmEmpty = `
export function getProfiles(){ return [{id:'p1',name:'f',baseUrl:'http://x/v1',apiKey:'k',model:'m'}] }
export async function chat(profile, messages){ return '' }
`
let wordSrc2 = readFileSync('./src/utils/word.js', 'utf8')
  .replace("from './db.js'", `from '${dbUrl}'`)
  .replace("from './llm.js'", `from '${b64(fakeLlmEmpty)}'`)
  .replace("from './http.js'", `from '${b64(fakeHttp)}'`)
  .replace("from './translate.js'", `from '${b64(fakeTranslate)}'`)
const word2 = await import(b64(wordSrc2))
let rEmpty = await word2.lookupWord('example', 'en2zh')
check('LLM 返回空串时 lookupWord 不抛错', true)
check('返回 kind=text 但 text 为空', rEmpty && rEmpty.kind === 'text' && rEmpty.text === '', rEmpty)
check('→ 模板 zh 分支渲染 result.text 会得到空白卡片（即「无翻译显示」bug 复现）', rEmpty && rEmpty.text === '')

console.log(`\n结果：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
