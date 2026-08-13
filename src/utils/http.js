// 统一 HTTP 层。
// uni.request 在不同平台返回形态不一（部分平台 [err, res] 元组 / Promise 直返），
// 这里统一成 { statusCode, data, header }，调用方无需平台分支。
// App 端 uni.request 直接发起网络请求，无同源/CORS 限制，无需代理。
// 注意：某些小程序/老版本基础库会在 success 回调里传 [err, res] 元组形态，
// 这里做一次归一化，避免上层把元组当成 res（导致 statusCode 为 undefined、HTTP 错误被静默放行）。
function normalize(res) {
  if (Array.isArray(res)) {
    const err = res[0], real = res[1]
    if (err) return { __error: new Error(err && err.errMsg ? err.errMsg : '网络请求失败') }
    return real || {}
  }
  return res || {}
}

// 统一请求：始终 resolve 成 { statusCode, data, header }
export function request(options) {
  return new Promise((resolve, reject) => {
    uni.request({
      ...options,
      timeout: options.timeout || 30000,
      success: (raw) => {
        const res = normalize(raw)
        if (res && res.__error) return reject(res.__error)
        resolve(res)
      },
      fail: (err) => reject(new Error(err && err.errMsg ? err.errMsg : '网络请求失败')),
    })
  })
}

// 拉取文本内容（RSS / HTML），带状态码校验
export async function fetchText(url, options = {}) {
  const res = await request({
    url,
    method: 'GET',
    dataType: 'text',
    responseType: 'text',
    ...options,
  })
  const code = res.statusCode
  if (code && (code < 200 || code >= 300)) throw new Error(`HTTP ${code}`)
  const data = res.data
  if (typeof data === 'string') return data
  if (data == null) return ''
  // 某些平台会把 XML/JSON 自动解析成对象，这里退回字符串形态
  try { return JSON.stringify(data) } catch (e) { return String(data) }
}
