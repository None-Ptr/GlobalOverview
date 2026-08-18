// 复现 addFeed 的 INSERT，验证是否报错
import { JSDOM } from 'jsdom'
globalThis.DOMParser = new JSDOM().window.DOMParser
globalThis.uni = { getStorageSync: () => '', setStorageSync: () => {}, showToast: () => {} }

const { db } = await import('../src/utils/db.js')

await db.init()
console.log('init ok')

// 复现 addFeed 的语句
const sqlVal = (v) => "'" + String(v).replace(/'/g, "''") + "'"
const url = 'https://example.com/test-rss'
const stmt = 'INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES ('
  + `${sqlVal(url)}, ${sqlVal(url)}, 'Custom', ${sqlVal(Date.now())})`
console.log('stmt:', stmt)

try {
  const res = await db.execute(stmt)
  console.log('execute ok:', JSON.stringify(res))
} catch (e) {
  console.log('EXECUTE FAIL:', e.message)
}

const rows = await db.select('SELECT * FROM feeds')
console.log('feeds:', JSON.stringify(rows))
