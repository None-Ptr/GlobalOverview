// LLM 封装：OpenAI 兼容协议，非流式，多 profile
// key 仅存本地（uni.setStorage），不进 SQLite

const STORE_KEY = 'llm_profiles'

export const PROVIDER_PRESETS = [
  { name: 'OpenAI', baseUrl: 'https://api.openai.com/v1' },
  { name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1' },
  { name: 'Moonshot', baseUrl: 'https://api.moonshot.cn/v1' },
  { name: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1' },
  { name: '智谱', baseUrl: 'https://open.bigmodel.cn/api/paas/v4' },
  { name: '自定义', baseUrl: '' },
]

function loadProfiles() {
  try { return uni.getStorageSync(STORE_KEY) || [] } catch (e) { return [] }
}

export function saveProfiles(list) {
  try { uni.setStorageSync(STORE_KEY, list) } catch (e) {}
}

export function getProfiles() { return loadProfiles() }

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
    return res[1]
  }
  return res
}

function request(options) {
  return new Promise((resolve, reject) => {
    uni.request({
      ...options,
      timeout: options.timeout || 30000,
      success: (raw) => { const res = normalize(raw); if (res && res.__error) return reject(res.__error); resolve(res) },
      fail: (err) => reject(new Error(err && err.errMsg ? err.errMsg : '网络请求失败')),
    })
  })
}

// 从模型回复中提取 JSON：容忍 markdown 代码块与前后噪声文本
function parseJsonLoose(content) {
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
  const body = {
    model: profile.model,
    messages,
    temperature,
    stream: false,
  }
  if (json) body.response_format = { type: 'json_object' }

  const res = await request({
    url: profile.baseUrl.replace(/\/$/, '') + '/chat/completions',
    method: 'POST',
    header: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + profile.apiKey,
    },
    data: body,
  })

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
