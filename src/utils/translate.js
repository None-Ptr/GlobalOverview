import { request as http } from './http.js'
import CryptoJS from 'crypto-js'
import { chat as llmChat, getProfiles } from './llm.js'
import { protectText, recoverText, formatText } from './textProtect.js'
import { useAppStore } from '@/stores/app.js'
import { loadCustomTranslators, DEFAULT_LANG_MAP } from './customTranslate.js'
const TARGET_LANG = {
  mymemory: { ZH: 'zh-CN', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
  libre: { ZH: 'zh', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
  baidu: { ZH: 'zh', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
}

// 自定义引擎 id 前缀，用于在回退链 / 引擎列表中区分用户配置的接口
const CUSTOM_PREFIX = 'custom:'

// 响应 JSON 按点路径/下标提取，如 'data.translation' / 'data.choices[0].text'
function getPath(obj, path) {
  if (obj == null || !path) return undefined
  const segs = String(path).replace(/\[(\d+)\]/g, '.$1').split('.').filter(Boolean)
  let cur = obj
  for (const s of segs) {
    if (cur == null) return undefined
    cur = cur[s]
  }
  return cur
}

// 占位符替换（URL 形态）：{text} {target} {lang} 均做 URL 编码
function fillUrl(tpl, text, lang) {
  return String(tpl || '')
    .split('{text}').join(encodeURIComponent(text))
    .split('{target}').join(encodeURIComponent(lang))
    .split('{lang}').join(encodeURIComponent(lang))
}

// 占位符替换（JSON body 形态）：{text} 替换为 JSON 转义但不带外层引号的内容，
// 引号由用户在模板里自行包裹（如 "q": "{text}"），避免与 JSON.stringify 的双引号叠加。
function fillJson(tpl, text, lang) {
  const esc = JSON.stringify(text).slice(1, -1) // 转义内部引号/换行，但去掉首尾引号
  return String(tpl || '')
    .split('{text}').join(esc)
    .split('{target}').join(lang)
    .split('{lang}').join(lang)
}

function tryParse(r) {
  if (typeof r !== 'string') return r
  try { return JSON.parse(r) } catch (e) { return r }
}
// 百度翻译开放平台凭据
let BAIDU_APP_ID = '20210915000944730'
let BAIDU_KEY = 'fp19vk7_V5KW2GSndfd5'
export function setBaiduCreds(appId, key) {
  if (appId) BAIDU_APP_ID = String(appId)
  if (key) BAIDU_KEY = String(key)
}
let LIBRE_URL = 'https://libretranslate.de/translate'
let LIBRE_API_KEY = ''
export function setLibreUrl(url, apiKey = '') {
  if (url) LIBRE_URL = url.replace(/\/+$/, '') + '/translate'
  LIBRE_API_KEY = apiKey || ''
}

export const ENGINE_NAMES = {
  auto: '自动',
  baidu: '百度翻译',
  mymemory: 'MyMemory',
  libre: 'LibreTranslate',
  llm: 'LLM',
}

export const TRANSLATE_SPLIT_LIMIT = 1200

async function baseTranslate(options, processer, checkResponse, retries = 3, retryDelay = 0) {
  let lastErr
  for (let i = 1; i <= retries; i++) {
    try {
      const r = await http(options)
      const data = r && r.data !== undefined ? r.data : r
      const checked = checkResponse(processer(data))
      if (checked.status) return checked.data
      lastErr = new Error(checked.message || '翻译失败')
    } catch (e) { lastErr = e }
  }
  throw lastErr
}

async function translate_baidu(text, target) {
  const q = text
  const from = 'auto'
  const to = TARGET_LANG.baidu[target] || 'zh'
  const salt = Math.floor(Math.random() * (65536 - 32768 + 1)) + 32768
  const signRaw = BAIDU_APP_ID + q + salt + BAIDU_KEY
  const sign = CryptoJS.MD5(signRaw).toString()
  const url =
    'http://api.fanyi.baidu.com/api/trans/vip/translate' +
    `?q=${encodeURIComponent(q)}&from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}` +
    `&appid=${encodeURIComponent(BAIDU_APP_ID)}&salt=${salt}&sign=${encodeURIComponent(sign)}`
  return baseTranslate(
    { url, method: 'GET', dataType: 'text' },
    (r) => (typeof r === 'string' ? JSON.parse(r) : r),
    (out) => {
      if (out && out.error_code) {
        const map = {
          '54003': '百度翻译频率受限，稍后重试',
          '54004': '百度翻译账户余额不足',
          '52001': '百度翻译请求超时',
          '52002': '百度翻译系统错误',
          '52003': '百度翻译 APP ID 无效',
          '54000': '百度翻译签名参数缺失',
          '54001': '百度翻译签名错误',
          '54002': '百度翻译无效的 query',
        }
        const msg = map[out.error_code] || `百度翻译错误 ${out.error_code}: ${out.error_msg || ''}`
        return { status: false, message: msg }
      }
      const trans = out && out.trans_result
      const dst = Array.isArray(trans) && trans.length ? trans[trans.length - 1].dst : ''
      return dst ? { status: true, data: dst } : { status: false, message: '百度翻译返回异常' }
    },
    3,
    1100
  )
}

// ---------- MyMemory（国内直连公共翻译，支持 CORS，兜底） ----------
async function translate_mymemory(text, target) {
  const pair = `en|${TARGET_LANG.mymemory[target] || 'zh-CN'}`
  const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=${encodeURIComponent(pair)}`
  return baseTranslate(
    { url, method: 'GET', dataType: 'text' },
    (r) => (typeof r === 'string' ? JSON.parse(r) : r),
    (out) => {
      const resp = out && out.responseData && out.responseData.translatedText
      return resp ? { status: true, data: resp } : { status: false, message: 'MyMemory 返回异常' }
    }
  )
}

// ---------- LibreTranslate（自建翻译服务，需开启 CORS 或同域） ----------
async function translate_libre(text, target) {
  const body = {
    q: text,
    source: 'en',
    target: TARGET_LANG.libre[target] || 'zh',
    format: 'text',
  }
  if (LIBRE_API_KEY) body.api_key = LIBRE_API_KEY
  return baseTranslate(
    { url: LIBRE_URL, method: 'POST', data: body, header: { 'Content-Type': 'application/json' } },
    (r) => r,
    (out) => {
      const t = out && out.translatedText
      return t ? { status: true, data: t } : { status: false, message: 'LibreTranslate 返回异常' }
    }
  )
}

// ---------- LLM 兜底（由 llm.js 负责，缺配置则抛错） ----------
async function translate_llm(text, target) {
  const profiles = getProfiles()
  if (!profiles || !profiles.length) throw new Error('未配置 LLM，请先到「我的」页面添加模型')
  const profile = profiles[0]
  const prompt = `You are a professional translator. Translate the following English text into ${target === 'ZH' ? 'Simplified Chinese' : target}. Output ONLY the translation, no explanation, no quotes.\n\n${text}`
  const out = await llmChat(profile, [{ role: 'user', content: prompt }], { temperature: 0.3 })
  if (!out) throw new Error('LLM 返回空')
  return out.trim()
}

// ---------- 自定义翻译接口（通用 HTTP 适配器，由用户配置驱动） ----------
// cfg 字段：
//   name, url(必填，占位符 {text} {target} {lang}),
//   method('GET'|'POST', 默认 POST), headers(JSON 对象字符串),
//   body(POST 的 JSON 模板，占位符同上；缺省为 { q, target, source } 契约),
//   resultPath(响应提取路径，默认 'data.translation'),
//   langMap(JSON 目标语言映射，可选)
export async function translate_custom(cfg, text, target) {
  let langMap = null
  try { langMap = JSON.parse(cfg.langMap || 'null') } catch (e) { langMap = null }
  const map = langMap && typeof langMap === 'object' ? langMap : DEFAULT_LANG_MAP
  const lang = map[target] || map.ZH || 'zh'

  const method = String(cfg.method || 'POST').toUpperCase()
  const options = { url: fillUrl(cfg.url, text, lang), method }

  if (method === 'GET') {
    options.dataType = 'text'
  } else {
    options.header = { 'Content-Type': 'application/json' }
    try { Object.assign(options.header, JSON.parse(cfg.headers || '{}')) } catch (e) { /* 忽略非法 header */ }
    if (cfg.body) {
      try { options.data = JSON.parse(fillJson(cfg.body, text, lang)) }
      catch (e) { throw new Error('请求体模板不是合法 JSON') }
    } else {
      // 无自定义 body 时按常见翻译 API 契约发送
      options.data = { q: text, target: lang, source: 'en' }
    }
  }

  return baseTranslate(
    options,
    (r) => tryParse(r),
    (out) => {
      const v = getPath(out, cfg.resultPath || 'data.translation')
      return v != null && String(v).length
        ? { status: true, data: String(v) }
        : { status: false, message: '翻译接口返回异常（resultPath 未命中）' }
    },
    3,
    1000
  )
}

const ENGINE_MAP = {
  baidu: translate_baidu,
  mymemory: translate_mymemory,
  libre: translate_libre,
  llm: translate_llm,
}

// 解析引擎 id 到执行函数：内置引擎直取，custom: 前缀动态查配置
function resolveFn(name) {
  if (name.startsWith(CUSTOM_PREFIX)) {
    const id = name.slice(CUSTOM_PREFIX.length)
    const cfg = loadCustomTranslators().find((t) => t.id === id)
    return cfg ? (text, target) => translate_custom(cfg, text, target) : null
  }
  return ENGINE_MAP[name] || null
}

// 引擎显示名（含自定义），供 UI 动态生成选择列表
export function getEngineNames() {
  const names = { ...ENGINE_NAMES }
  for (const t of loadCustomTranslators()) names[CUSTOM_PREFIX + t.id] = t.name || '自定义'
  return names
}

// 回退顺序：preferred 指定单一引擎（含 custom:x）；auto 时内置优先、自定义殿后
function getEngineOrder(preferred) {
  const base = ['baidu', 'mymemory', 'libre', 'llm']
  const customs = loadCustomTranslators().map((t) => CUSTOM_PREFIX + t.id)
  if (preferred && preferred !== 'auto') return [preferred]
  return [...base, ...customs]
}

// 读取用户当前选中的翻译引擎（store.reader.transEngine），未选则 auto
function defaultEngine() {
  try {
    const store = useAppStore()
    return (store.reader && store.reader.transEngine) || 'auto'
  } catch (e) { return 'auto' }
}

function splitText(text, limit = TRANSLATE_SPLIT_LIMIT) {
  const blocks = String(text || '').split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean)
  const out = []
  for (const b of blocks) {
    if (b.length <= limit) { out.push(b); continue }
    const parts = b.split(/(?<=[.!?。！？])\s+/)
    let cur = ''
    for (const p of parts) {
      if (cur.length + p.length + 1 > limit) {
        if (cur) out.push(cur.trim())
        cur = p
      } else {
        cur = cur ? cur + ' ' + p : p
      }
    }
    if (cur) out.push(cur.trim())
  }
  return out
}

export async function translate(text, opts = {}) {
  const target = opts.target || 'ZH'
  const engine = opts.engine || defaultEngine() || 'auto'
  const raw = String(text || '').trim()
  if (!raw) return ''

  let blocks
  const { text: protectedText, store: pstore } = protectText(raw)
  try {
    blocks = splitText(protectedText)
  } catch (e) {
    blocks = [protectedText]
  }

  const order = getEngineOrder(engine)

  let lastErr
  for (const name of order) {
    const fn = resolveFn(name)
    if (!fn) continue
    try {
      let parts
      if (name === 'baidu') {
        // 百度标准版 QPS=1，必须串行 + 退避，否则并发触发 54003 频率限制
        parts = []
        for (const b of blocks) {
          parts.push(await translate_baidu(b, target))
          if (blocks.length > 1) await new Promise((r) => setTimeout(r, 1100))
        }
      } else {
        parts = await Promise.all(blocks.map((b) => fn(b, target)))
      }
      const joined = parts.join('\n\n')
      return formatText(recoverText(joined, pstore))
    } catch (e) {
      lastErr = e
      // 继续尝试下一个引擎
    }
  }
  throw lastErr || new Error('翻译失败')
}

export default translate
