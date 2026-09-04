// LLM 封装：OpenAI 兼容协议，非流式，多 profile
// key 仅存本地（uni.setStorage），不进 SQLite

const STORE_KEY = 'llm_profiles'
// 「我的」页 / 模型表单使用的 UI 列表 key。两处必须双写：
//   llm_profiles  -> chat() 实际调用读取（明文 apiKey）
//   go_llm_models -> 我的页列表 / 编辑删除（混淆 apiKey）
export const MODELS_KEY = 'go_llm_models'
// 内置免费模型一次性播种标记：播种后由用户全权增删，不再重复注入
const SEED_KEY = 'llm_seed_glm_v1'
// 一次性迁移标记：清除历史遗留的限流配置（见 stripRateLimitOnce）
const NORL_KEY = 'llm_norl_v1'

// 内置免费模型：智谱 GLM-4.7-Flash（OpenAI 兼容协议，非流式）
export const BUILTIN_FREE = {
  id: 'builtin_glm_flash',
  name: 'GLM-4.7-Flash',
  baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
  model: 'glm-4.7-flash',
  apiKey: 'ff8f359a4d03404a912514a047283426.ZxCZ03Zc1pqD4hwK',
  builtin: true,
}

export const PROVIDER_PRESETS = [
  { name: 'OpenAI', baseUrl: 'https://api.openai.com/v1' },
  { name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1' },
  { name: 'Moonshot', baseUrl: 'https://api.moonshot.cn/v1' },
  { name: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1' },
  { name: '智谱', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4.7-flash' },
  { name: '自定义', baseUrl: '' },
]

/* ---------------- API Key 混淆（与 model-form 一致） ---------------- */
// 防君子不防小人的混淆，避免明文落盘被直接读取；真正安全需系统级 keychain。
export function obfuscateKey(k) {
  if (!k) return ''
  try { return 'obf:' + btoa(unescape(encodeURIComponent(k))) } catch (_) { return k }
}
export function deobfuscateKey(v) {
  if (!v || !v.startsWith('obf:')) return v
  try { return decodeURIComponent(escape(atob(v.slice(4)))) } catch (_) { return v.slice(4) }
}

/* ---------------- 一次性迁移：清除历史遗留的限流配置 ---------------- */
// 内置模型最初播种时带过 rateLimitMs=60000，该值会随配置落盘到 localStorage。
// 仅改代码不影响已安装应用里已存在的配置，必须在此显式清除（否则用户仍被限流）。
function stripRateLimitOnce() {
  try {
    if (uni.getStorageSync(NORL_KEY)) return
    for (const key of [STORE_KEY, MODELS_KEY]) {
      const list = uni.getStorageSync(key)
      if (!Array.isArray(list) || !list.length) continue
      let changed = false
      const next = list.map((p) => {
        if (!p || p.rateLimitMs === undefined) return p
        const copy = { ...p }
        delete copy.rateLimitMs
        changed = true
        return copy
      })
      if (changed) uni.setStorageSync(key, next)
    }
    // 顺带清掉限流打点记录
    try { uni.removeStorageSync('llm_ratelimit') } catch (e) {}
    uni.setStorageSync(NORL_KEY, 1)
  } catch (e) {}
}

/* ---------------- 首次启动播种内置免费模型 ---------------- */
// 只播一次：之后再清空模型列表不会被重新注入，尊重用户的删除操作。
function ensureSeeded() {
  try {
    if (uni.getStorageSync(SEED_KEY)) return
    const ui = uni.getStorageSync(MODELS_KEY) || []
    if (!ui.length) {
      // UI 列表用混淆 key（与 model-form 保存行为一致）
      uni.setStorageSync(MODELS_KEY, [{ ...BUILTIN_FREE, apiKey: obfuscateKey(BUILTIN_FREE.apiKey) }])
    }
    const core = uni.getStorageSync(STORE_KEY) || []
    if (!core.length) {
      // 调用侧用明文 key
      uni.setStorageSync(STORE_KEY, [{ ...BUILTIN_FREE }])
    }
    uni.setStorageSync(SEED_KEY, 1)
  } catch (e) {}
}

function loadProfiles() {
  try { return uni.getStorageSync(STORE_KEY) || [] } catch (e) { return [] }
}

export function saveProfiles(list) {
  try { uni.setStorageSync(STORE_KEY, list) } catch (e) {}
}

export function getProfiles() {
  ensureSeeded()
  stripRateLimitOnce()
  return loadProfiles()
}

export function upsertProfile(p) {
  const list = loadProfiles()
  if (p.id) {
    const i = list.findIndex((x) => x.id === p.id)
    if (i >= 0) list[i] = { ...list[i], ...p }
  } else {
    p.id = 'p_' + Date.now()
    list.push(p)
  }
  saveProfiles(list)
  return p.id
}

export function deleteProfile(id) {
  const list = loadProfiles().filter((x) => x.id !== id)
  saveProfiles(list)
}

// uni.request 在不同平台返回形态不一（Promise 直返 / [err, res] 元组），统一成 res
// 部分平台会在 success 回调里传 [err, res] 元组，这里归一化，避免上层把元组当成 res
function normalize(res) {
  if (Array.isArray(res)) {
    const err = res[0]
    if (err) return { __error: new Error(err && err.errMsg ? err.errMsg : '网络请求失败') }
    // 必须兜底返回对象：部分平台会传 [null]，直接取 res[1] 会得到 undefined，
    // 上层访问 res.statusCode 即 TypeError。
    return res[1] || {}
  }
  return res || {}
}

function request(options) {
  return new Promise((resolve, reject) => {
    uni.request({
      ...options,
      timeout: options.timeout || 30000,
      success: (raw) => { const res = normalize(raw); if (res && res.__error) return reject(res.__error); resolve(res) },
      fail: (err) => {
        const msg = (err && err.errMsg) || '网络请求失败'
        // 将 uni-app 的 timeout 错误翻译成用户可理解的文案
        if (/timeout|timed out|statusCode:-1/i.test(msg)) {
          reject(new Error('请求超时：模型响应较慢,请稍后重试;如频繁超时,可尝试缩短文章或降低题目数量'))
        } else {
          reject(new Error(msg))
        }
      },
    })
  })
}

// 从模型回复中提取 JSON：容忍 markdown 代码块与前后噪声文本
export function parseJsonLoose(content) {
  let s = String(content).trim()
  const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/i)
  if (fence) s = fence[1].trim()
  try { return JSON.parse(s) } catch (e) { /* 继续尝试截取 */ }
  const start = s.search(/[[{]/)
  if (start >= 0) {
    const open = s[start]
    const close = open === '{' ? '}' : ']'
    const end = s.lastIndexOf(close)
    if (end > start) {
      try { return JSON.parse(s.slice(start, end + 1)) } catch (e) { /* fallthrough */ }
    }
  }
  throw new Error('模型未返回合法 JSON')
}

function validateProfile(profile) {
  if (!profile) throw new Error('未配置 LLM，请先到「我的」页面添加模型配置')
  if (!profile.baseUrl) throw new Error('LLM 配置缺少 Base URL')
  if (!profile.model) throw new Error('LLM 配置缺少模型名')
  if (!profile.apiKey) throw new Error('LLM 配置缺少 API Key')
}

// 单次 chat completion，返回解析后的 JSON（若要求 json）
export async function chat(profile, messages, { json = false, temperature = 0.7 } = {}) {
  validateProfile(profile)

  const send = (useJsonFormat) => {
    const body = {
      model: profile.model,
      messages,
      temperature,
      stream: false,
    }
    if (useJsonFormat) body.response_format = { type: 'json_object' }
    return request({
      url: profile.baseUrl.replace(/\/$/, '') + '/chat/completions',
      method: 'POST',
      header: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + profile.apiKey,
      },
      data: body,
      timeout: 300000, // LLM 生成 JSON 题库较慢,默认 30s 不够;放宽到 5 分钟
    })
  }

  let res = await send(json)
  // 兼容兜底：部分模型（含某些 GLM 版本）不接受 response_format 参数会返回 400，
  // 此时去掉该参数重试一次，改由 prompt 约束 + parseJsonLoose 兜底解析。
  if (json && res && res.statusCode >= 400 && res.statusCode < 500) {
    const errMsg = (res.data && res.data.error && res.data.error.message) || ''
    if (/response_format|json_object|json_schema/i.test(String(errMsg))) {
      res = await send(false)
    }
  }

  if (res.statusCode && (res.statusCode < 200 || res.statusCode >= 300)) {
    const msg = res.data && res.data.error ? res.data.error.message : `HTTP ${res.statusCode}`
    throw new Error(msg)
  }
  const data = typeof res.data === 'string' ? parseJsonLoose(res.data) : res.data
  if (data && data.error) throw new Error(data.error.message || 'API error')
  const content = data && data.choices && data.choices[0]
    && data.choices[0].message && data.choices[0].message.content
  if (!content) throw new Error('模型返回空响应')
  if (!json) return content
  return parseJsonLoose(content)
}

// 测试连接：发一条最小消息
export async function testConnection(profile) {
  await chat(profile, [{ role: 'user', content: 'ping' }], { temperature: 0 })
  return true
}
