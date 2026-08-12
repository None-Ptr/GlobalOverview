import { request as http } from './http.js'
import CryptoJS from 'crypto-js'
import { chat as llmChat, getProfiles } from './llm.js'
import { protectText, recoverText, formatText } from './textProtect.js'
const TARGET_LANG = {
  mymemory: { ZH: 'zh-CN', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
  libre: { ZH: 'zh', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
  baidu: { ZH: 'zh', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es' },
}
// 百度翻译开放平台凭据
let BAIDU_APP_ID = 'abab被吃掉了'
let BAIDU_KEY = 'abab被吃掉了'
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

const ENGINE_ORDER = ['baidu', 'mymemory', 'libre', 'llm']

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

const ENGINE_MAP = {
  baidu: translate_baidu,
  mymemory: translate_mymemory,
  libre: translate_libre,
  llm: translate_llm,
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
  const engine = opts.engine || 'auto'
  const raw = String(text || '').trim()
  if (!raw) return ''

  let blocks
  const { text: protectedText, store: pstore } = protectText(raw)
  try {
    blocks = splitText(protectedText)
  } catch (e) {
    blocks = [protectedText]
  }

  const order = engine === 'auto' ? ENGINE_ORDER : (ENGINE_MAP[engine] ? [engine] : ENGINE_ORDER)

  let lastErr
  for (const name of order) {
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
        parts = await Promise.all(blocks.map((b) => ENGINE_MAP[name](b, target)))
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
