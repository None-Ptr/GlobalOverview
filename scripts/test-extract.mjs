// 正文抽取器测试：基于 @mozilla/readability，覆盖真实网页形态
// node 环境无原生 DOMParser，用 jsdom 注入全局 DOMParser 供 extract.js 使用
import { JSDOM } from 'jsdom'
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>')
globalThis.DOMParser = dom.window.DOMParser
globalThis.document = dom.window.document
globalThis.Node = dom.window.Node

const { extractArticle } = await import('../src/utils/extract.js')

let pass = 0
let fail = 0
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ' + name) }
  else { fail++; console.log('  FAIL ' + name + (extra !== undefined ? ' => ' + JSON.stringify(extra) : '')) }
}
function noThrow(name, fn) {
  try {
    const r = fn()
    pass++
    console.log('  ok   ' + name)
    return r
  } catch (e) {
    fail++
    console.log('  FAIL ' + name + ' => threw: ' + e.message)
    return null
  }
}

console.log('[1] 基础文章抽取')
{
  const html = `
    <html><body>
      <nav>menu here</nav>
      <article>
        <h1>Title</h1>
        <p>The quick brown fox jumps over the lazy dog. This is a sentence.</p>
        <p>Another paragraph with enough words to score well in the heuristic.</p>
      </article>
      <footer>copyright</footer>
    </body></html>`
  const r = noThrow('不抛异常', () => extractArticle(html))
  check('抽到正文', r && r.plainText.includes('quick brown fox'), r && r.plainText)
  check('剔除 nav', r && !r.plainText.includes('menu here'))
  check('剔除 footer', r && !r.plainText.includes('copyright'))
  check('wordCount > 0', r && r.wordCount > 0, r && r.wordCount)
}

console.log('\n[2] 黑名单标签内含文本（script/style）')
{
  const html = `<div><script>var a=1;</script><style>.x{}</style><p>Real content sentence here.</p></div>`
  const r = noThrow('不抛异常', () => extractArticle(html))
  check('剔除 script', r && !r.plainText.includes('var a=1'))
  check('保留正文', r && r.plainText.includes('Real content'))
}

console.log('\n[3] 畸形 HTML：多余闭合标签（真实网页常见）')
{
  const html = `<div><p>First paragraph text.</p></div></div></section><p>Second paragraph text.</p>`
  const r = noThrow('多余闭合标签不崩', () => extractArticle(html))
  check('仍能抽到内容', r && r.plainText.length > 0, r && r.plainText)
}

console.log('\n[4] 黑名单标签后紧跟文本（DOM 解析健壮性）')
{
  const html = `<div><nav><a>x</a></nav>tail text after nav<p>Body sentence one here.</p></div>`
  const r = noThrow('不崩', () => extractArticle(html))
  check('抽到正文', r && r.plainText.includes('Body sentence'), r && r.plainText)
}

console.log('\n[5] 自闭合/void 标签（br, img, meta）')
{
  const html = `<div><p>Line one.<br>Line two.</p><img src="a.png"><meta charset="utf-8"><p>Line three.</p></div>`
  const r = noThrow('void 标签不崩', () => extractArticle(html))
  check('抽到段落', r && r.plainText.includes('Line one'), r && r.plainText)
}

console.log('\n[6] 空输入与纯文本')
{
  const a = noThrow('空串不崩', () => extractArticle(''))
  check('空串返回空文本', a && a.plainText === '', a && a.plainText)
  const b = noThrow('纯文本不崩', () => extractArticle('just some bare text'))
  check('纯文本 wordCount 合理', b && typeof b.wordCount === 'number')
}

console.log('\n[7] 未闭合标签')
{
  const html = `<div><p>Unclosed paragraph text here<div><p>Nested one.</p>`
  const r = noThrow('未闭合不崩', () => extractArticle(html))
  check('有输出', r && typeof r.plainText === 'string')
}

console.log('\n[8] 属性含广告关键词的容器（Readability 主内容优先）')
{
  const html = `<div><div class="advert">buy now cheap</div><p>Genuine article sentence here.</p></div>`
  const r = noThrow('不抛异常', () => extractArticle(html))
  check('保留主内容', r && r.plainText.includes('Genuine article'), r && r.plainText)
}

console.log('\n[9] 深层嵌套黑名单（Readability 主内容抽取）')
{
  const html = `<article><nav><div><span>navtext</span></div></nav><p>Article body sentence.</p></article>`
  const r = noThrow('不崩', () => extractArticle(html))
  check('抽到正文', r && r.plainText.includes('Article body'), r && r.plainText)
}

console.log('\n[10] 真实结构：header/aside/form 混排')
{
  const html = `
    <body>
      <header><h1>Site</h1></header>
      <aside><p>Related links here</p></aside>
      <form><input></form>
      <main><p>The main article content goes here with several words.</p>
      <p>And a second meaningful paragraph of body text.</p></main>
    </body>`
  const r = noThrow('不抛异常', () => extractArticle(html))
  check('剔除 aside', r && !r.plainText.includes('Related links'), r && r.plainText)
  check('保留 main', r && r.plainText.includes('main article content'))
}

console.log('\n[11] UI caption 控件文本过滤（hide/toggle/show caption）')
{
  const html = `
    <article>
      <h1>Photo story</h1>
      <p>A photographer captured the moment.</p>
      <div>
        <img src="a.jpg">
        <span>hide caption</span>
        <span>toggle caption</span>
        <span>show caption</span>
      </div>
      <p>The end.</p>
    </article>`
  const r = noThrow('不崩', () => extractArticle(html))
  check('剔除 hide caption', r && !r.plainText.includes('hide caption'), r && r.plainText)
  check('剔除 toggle caption', r && !r.plainText.includes('toggle caption'), r && r.plainText)
  check('剔除 show caption', r && !r.plainText.includes('show caption'), r && r.plainText)
  check('保留正文', r && r.plainText.includes('photographer captured'), r && r.plainText)
  check('保留正文结尾', r && r.plainText.includes('The end'), r && r.plainText)
}

console.log(`\n结果：${pass} 通过 / ${fail} 失败`)
if (fail) process.exit(1)
