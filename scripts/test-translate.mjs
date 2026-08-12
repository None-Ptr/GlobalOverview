// 翻译引擎测试：验证各引擎在 Node 环境直连可用性
import CryptoJS from 'crypto-js'

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0 Safari/537.36'

async function t(name, fn) {
  console.log(`\n=== ${name} ===`)
  try {
    const r = await fn()
    console.log('  OK:', r)
  } catch (e) {
    console.log('  FAIL:', e.message)
  }
}

const TEXT = 'Hello world, this is a test.'

await t('MyMemory (国内直连)', async () => {
  const pair = `en|zh-CN`
  const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(TEXT)}&langpair=${pair}`
  const r = await fetch(url, { headers: { 'User-Agent': UA } })
  const j = await r.json()
  const out = j?.responseData?.translatedText
  if (!out) throw new Error('返回异常 ' + JSON.stringify(j).slice(0, 100))
  return out
})

await t('LibreTranslate', async () => {
  const r = await fetch('https://libretranslate.de/translate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ q: TEXT, source: 'en', target: 'zh', format: 'text' }),
  })
  if (!r.ok) throw new Error('HTTP ' + r.status)
  const j = await r.json()
  const out = j?.translatedText
  if (!out) throw new Error('返回异常 ' + JSON.stringify(j).slice(0, 100))
  return out
})

console.log('\n=== 测试完成 ===')
