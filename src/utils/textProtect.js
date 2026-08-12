// 译文文本保护与后处理。
// 思路借鉴 a.js（OilOJ OJBetter）的 TextBlockReplacer / formatText：
// - 翻译前：用占位符替换可能破坏译文格式的结构（代码块/行内代码/LaTeX），避免被引擎翻坏；
// - 翻译后：把译文里的常见 Markdown 排版问题修复（斜体空格、链接括号、加粗空格等）。
//
// 当前项目是新闻正文（英译中），没有数学公式，故只保护代码块/行内代码，
// 长文拆分逻辑在 translate.js 内按段落处理。

// ---------- 翻译前：保护代码块 ----------
const CODE_BLOCK = /```[\s\S]*?```/g
const CODE_INLINE = /`[^`\n]+`/g

// 占位符形如  ojsb0  …  ojsbN ，翻译引擎通常不会改动纯 ASCII 占位符
function makeHolder(i) {
  return ` ojsb${i} `
}

export function protectText(text) {
  const store = []
  let out = text
  const push = (snippet) => { const i = store.length; store.push(snippet); return makeHolder(i) }
  out = out.replace(CODE_BLOCK, (m) => push(m))
  out = out.replace(CODE_INLINE, (m) => push(m))
  return { text: out, store }
}

export function recoverText(translated, store) {
  let out = translated
  store.forEach((snippet, i) => {
    out = out.split(makeHolder(i)).join(snippet)
  })
  return out
}

// ---------- 翻译后：Markdown 排版修复（对应 a.js formatText 的轻量版） ----------
export function formatText(text) {
  if (!text) return text
  let t = String(text)
  // 中文与 ASCII 之间的多余空格清理：_ 中文 _ -> _中文_
  t = t.replace(/_\s*([一-鿿A-Za-z0-9 ,.;:!?，。；：！？、()（）"“”：'‘’\-]+?)\s*_/g, '_$1_')
  // ] （xxx） -> ](xxx)：链接描述与地址之间的全角空格修复
  t = t.replace(/]\s*[（(]\s*/g, '](')
  t = t.replace(/\s*[）)]\s*/g, ')')
  // ** x ** -> **x**
  t = t.replace(/\*\*\s+/g, '**').replace(/\s+\*\*/g, '**')
  // 合并多余空行
  t = t.replace(/\n{3,}/g, '\n\n')
  return t
}
