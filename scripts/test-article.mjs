// APP 端（原生渲染）专属逻辑单测：覆盖 article.vue 中 APP 端才走的分词 / 取词 / 兜底解析。
// 这些函数依赖 uni 运行时（ref/computed），这里用纯 JS 复刻其核心逻辑做行为验证，
// 确保：(1) tokenize 单词可点、空白/标点不可点；(2) ensurePlainText 从 html 兜底；
// (3) onNativeTok 仅单词片段触发 openWord；(4) openWord 归一化后非空才打开。
import assert from 'node:assert'

let pass = 0
let fail = 0
function test(name, fn) {
  try { fn(); pass++; console.log('  ✓', name) }
  catch (e) { fail++; console.error('  ✗', name, '\n    ', e.message) }
}

// ---- 复刻 article.vue 中的纯逻辑（保持同源，改动需同步） ----
function normalizeQuery(s) {
  if (!s) return ''
  return String(s).replace(/\s+/g, ' ').trim()
}
function tokenize(p) {
  if (!p) return []
  const out = []
  const re = /(\s+|[A-Za-z][A-Za-z'’-]*[A-Za-z]|[A-Za-z]|[^A-Za-z\s]+)/g
  let m
  while ((m = re.exec(p)) !== null) {
    let t = m[0]
    if (/^\s+$/.test(t)) {
      // 与 article.vue 同源：空白 token 中空格换为 NBSP，避免原生 webview 折叠
      t = t.replace(/[^\n\t]/g, '\u00A0')
    }
    const word = /^[A-Za-z][A-Za-z'’-]*$/.test(t)
    out.push({ text: t, word })
  }
  return out
}
function ensurePlainText(bodyHtml, plainText) {
  if (plainText && plainText.trim()) return plainText
  if (!bodyHtml) return ''
  const tmp = bodyHtml
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim()
  return tmp
}
function makeOpenWord() {
  const state = { activeWord: '', activeContext: '', wordVisible: false }
  function openWord(text, context) {
    const clean = normalizeQuery(text)
    if (!clean) return false
    state.activeWord = clean
    state.activeContext = context || ''
    state.wordVisible = true
    return true
  }
  function onNativeTok(tk, isLong, ctx) {
    if (!tk || !tk.word) return false // 仅单词片段可触发
    return openWord(tk.text, isLong ? (ctx || '') : '')
  }
  return { state, openWord, onNativeTok }
}

// 复刻 APP 端「点选累积选区」逻辑
function makeSelectable() {
  let selectMode = false
  let selTokens = []
  let h5Selection = { text: '', context: '' }
  const selectedText = () => selTokens.map((t) => t.text).join(' ').trim()
  const isSel = (pi, ti) => selTokens.some((t) => t.pi === pi && t.ti === ti)
  function toggleSelectMode() {
    selectMode = !selectMode
    if (!selectMode) selTokens = []
  }
  function toggleSelToken(tk, pi, ti) {
    if (!tk || !tk.word) return
    const idx = selTokens.findIndex((t) => t.pi === pi && t.ti === ti)
    if (idx >= 0) selTokens.splice(idx, 1)
    else selTokens.push({ pi, ti, text: tk.text })
  }
  function onNativeTok(tk, isLong, ctx, pi, ti) {
    if (!tk || !tk.word) return { acted: false }
    if (selectMode) {
      toggleSelToken(tk, pi, ti)
      return { acted: true, selected: selectedText() }
    }
    return { acted: true, selected: isLong ? ctx : tk.text }
  }
  function lookupSelection() {
    const text = selectedText() || h5Selection.text
    return text || null
  }
  return { get selectMode() { return selectMode }, set selectMode(v) { selectMode = v },
    get selTokens() { return selTokens }, isSel, toggleSelectMode, toggleSelToken,
    selectedText, onNativeTok, lookupSelection,
    setH5(text, ctx) { h5Selection = { text, context: ctx || '' } } }
}

console.log('article (APP 原生端) 逻辑测试：')

test('tokenize: 普通句子切出单词与非词片段', () => {
  const tk = tokenize('Hello, world!')
  const words = tk.filter(t => t.word)
  assert.strictEqual(words.length, 2)
  assert.deepStrictEqual(words.map(w => w.text), ['Hello', 'world'])
  // 逗号、空格、感叹号都标记为不可点
  assert.ok(tk.every(t => (t.text === 'Hello' || t.text === 'world') ? t.word : !t.word))
})

test('tokenize: 连字符/撇号单词被识别为单词', () => {
  const tk = tokenize("don't state-of-the-art")
  const words = tk.filter(t => t.word).map(w => w.text)
  assert.deepStrictEqual(words, ["don't", 'state-of-the-art'])
})

test('tokenize: 纯标点/数字不触发', () => {
  const tk = tokenize('123 !@#')
  assert.ok(tk.length > 0)
  assert.ok(tk.every(t => !t.word))
})

test('tokenize: 空输入返回空数组', () => {
  assert.deepStrictEqual(tokenize(''), [])
  assert.deepStrictEqual(tokenize(null), [])
})

test('tokenize: 空白 token 中的空格被替换为 NBSP（修复单词粘连）', () => {
  const tk = tokenize('Hello world')
  // 'Hello' 与 'world' 之间应有一个 NBSP token
  const spaces = tk.filter((t) => !t.word)
  assert.strictEqual(spaces.length, 1)
  assert.strictEqual(spaces[0].text, '\u00A0')
  // 拼接后的字符序列与原文视觉等价（NBSP 渲染宽度相同）
  const joined = tk.map((t) => t.text).join('')
  assert.strictEqual(joined.length, 'Hello world'.length)
})

test('ensurePlainText: 已有纯文本直接返回(不二次trim)', () => {
  const r = ensurePlainText('<p>x</p>', '  existing text  ')
  assert.strictEqual(r, '  existing text  ')
})

test('ensurePlainText: 从 html 兜底剥离标签/样式/脚本', () => {
  const html = '<style>.a{color:red}</style><script>var a=1</script><p>Hello <b>world</b>&amp; you</p>'
  const r = ensurePlainText(html, '')
  assert.strictEqual(r, 'Hello world & you')
  assert.ok(!r.includes('<'))
  assert.ok(!r.includes('var a'))
})

test('ensurePlainText: 空 html 兜底为空串', () => {
  assert.strictEqual(ensurePlainText('', ''), '')
  assert.strictEqual(ensurePlainText(null, ''), '')
})

test('onNativeTok: 单词片段短按打开词卡(en2zh)', () => {
  const { state, onNativeTok } = makeOpenWord()
  const ok = onNativeTok({ text: 'Hello', word: true }, false, '')
  assert.ok(ok)
  assert.strictEqual(state.activeWord, 'Hello')
  assert.strictEqual(state.activeContext, '') // 短按无上下文
  assert.strictEqual(state.wordVisible, true)
})

test('onNativeTok: 单词片段长按带上下文(短语/句解析)', () => {
  const { state, onNativeTok } = makeOpenWord()
  const ok = onNativeTok({ text: 'world', word: true }, true, 'Hello world!')
  assert.ok(ok)
  assert.strictEqual(state.activeWord, 'world')
  assert.strictEqual(state.activeContext, 'Hello world!')
})

test('onNativeTok: 非单词片段(空格/标点)不触发 —— APP 端修复点', () => {
  const { state, onNativeTok } = makeOpenWord()
  const r1 = onNativeTok({ text: ' ', word: false }, false, '')
  const r2 = onNativeTok({ text: ',', word: false }, true, 'x')
  assert.strictEqual(r1, false)
  assert.strictEqual(r2, false)
  assert.strictEqual(state.wordVisible, false)
})

// ---- 回归：cover 计算属性依赖 article ref 存在 —— 之前 article 未声明导致模板渲染 ReferenceError，整页空白 ----
test('cover 计算属性可访问 article 字段而不抛错', () => {
  // 复刻 cover 的纯计算逻辑（与 article.vue 同源）
  function cover(article, sourceUrl, wordCount, fmtDate) {
    let host = ''
    try { host = sourceUrl ? new URL(sourceUrl).hostname.replace(/^www\./, '') : '' } catch (e) {}
    if (!host) host = (article && (article.feed || article.feedName)) || '收录文章'
    const dt = article && (article.publishedAtText || article.pubDate || article.ts)
    const readMins = wordCount ? Math.max(1, Math.round(wordCount / 220)) : 0
    return { source: host, date: dt ? fmtDate(dt) : '', readMins }
  }
  // 1) article 存在时：feed 回退到 feedName
  const a = { feedName: 'NPR', pubDate: 1730000000000 }
  const c1 = cover(a, '', 600, (t) => '2025-01-01')
  assert.strictEqual(c1.source, 'NPR')
  assert.strictEqual(c1.date, '2025-01-01')
  assert.strictEqual(c1.readMins, 3)
  // 2) article 为 null、sourceUrl 有值：使用域名
  const c2 = cover(null, 'https://example.com/x', 0, () => '')
  assert.strictEqual(c2.source, 'example.com')
  // 3) 全部为空时：使用兜底文案
  const c3 = cover(null, '', 0, () => '')
  assert.strictEqual(c3.source, '收录文章')
})

test('onNativeTok: 空/无效 token 不触发', () => {
  const { state, onNativeTok } = makeOpenWord()
  assert.strictEqual(onNativeTok(null, false, ''), false)
  assert.strictEqual(onNativeTok(undefined, true, ''), false)
  assert.strictEqual(state.wordVisible, false)
})

test('openWord: 归一化空串不打开', () => {
  const { state, openWord } = makeOpenWord()
  assert.strictEqual(openWord('   ', ''), false)
  assert.strictEqual(state.wordVisible, false)
})

test('openWord: 多空格折叠并 trim', () => {
  const { state, openWord } = makeOpenWord()
  openWord('  Hello   world  ', '')
  assert.strictEqual(state.activeWord, 'Hello world')
})

// ---- APP 端「点选累积选区」逻辑（解决"无法选区翻译"） ----
test('选区: 开启选择模式，点选多词累积成选区文本', () => {
  const s = makeSelectable()
  s.toggleSelectMode()
  assert.strictEqual(s.selectMode, true)
  // 段落 0 的第 0/1/2 个词
  const r1 = s.onNativeTok({ text: 'The', word: true }, false, 'The quick brown', 0, 0)
  const r2 = s.onNativeTok({ text: 'quick', word: true }, false, 'The quick brown', 0, 1)
  const r3 = s.onNativeTok({ text: 'brown', word: true }, false, 'The quick brown', 0, 2)
  assert.strictEqual(r1.acted && r2.acted && r3.acted, true)
  assert.strictEqual(s.selectedText(), 'The quick brown')
})

test('选区: 再次点选同一词取消选中', () => {
  const s = makeSelectable()
  s.toggleSelectMode()
  s.onNativeTok({ text: 'Hello', word: true }, false, 'Hello world', 3, 0)
  assert.strictEqual(s.selectedText(), 'Hello')
  assert.strictEqual(s.isSel(3, 0), true)
  s.onNativeTok({ text: 'Hello', word: true }, false, 'Hello world', 3, 0)
  assert.strictEqual(s.selectedText(), '')
  assert.strictEqual(s.isSel(3, 0), false)
})

test('选区: 选择模式下非单词片段(空格/标点)不计入选区', () => {
  const s = makeSelectable()
  s.toggleSelectMode()
  s.onNativeTok({ text: ' ', word: false }, false, '', 0, 5)
  s.onNativeTok({ text: ',', word: false }, false, '', 0, 6)
  assert.strictEqual(s.selectedText(), '')
})

test('选区: 退出选择模式清空选区', () => {
  const s = makeSelectable()
  s.toggleSelectMode()
  s.onNativeTok({ text: 'foo', word: true }, false, 'foo bar', 0, 0)
  assert.strictEqual(s.selectedText(), 'foo')
  s.toggleSelectMode() // 退出
  assert.strictEqual(s.selectMode, false)
  assert.strictEqual(s.selectedText(), '')
})

test('选区: lookupSelection 优先原生多选文本', () => {
  const s = makeSelectable()
  s.toggleSelectMode()
  s.onNativeTok({ text: 'quantum', word: true }, false, 'quantum computing', 1, 0)
  s.onNativeTok({ text: 'computing', word: true }, false, 'quantum computing', 1, 1)
  s.setH5('旧的H5选区', 'ctx')
  assert.strictEqual(s.lookupSelection(), 'quantum computing')
})

console.log(`\n结果：通过 ${pass} / 失败 ${fail}`)
process.exit(fail ? 1 : 0)
