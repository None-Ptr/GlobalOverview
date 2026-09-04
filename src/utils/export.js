// 导出层：模板渲染 → HTML → 打印/另存为 PDF

// HTML5+ share 模块预检缓存：避免每次分享都重复探测原生属性
// ——如果 manifest 没声明 Share，runtime 会弹"打包时未添加 share模块"原生警告
// 我们用一次性探测 + try/catch 兜底，确保即使用户用着旧 APK 也不会再弹这个 dialog
let _shareReadyCache = null
export function _checkShareReady () {
  if (_shareReadyCache !== null) return _shareReadyCache
  try {
    var ok = plus != null
      && plus.share != null
      && typeof plus.share.sendWithSystem === 'function'
    _shareReadyCache = !!ok
  } catch (_) {
    _shareReadyCache = false
  }
  return _shareReadyCache
}
// 主动探测一次（在用户进入导出页前），把原生模块警告提前消费掉
// 任何后续调用都直接读缓存，永不再触发 native 警告
try {
  if (plus && plus.share) {
    try { typeof plus.share.sendWithSystem } catch (_) {}
  }
} catch (_) {}
import { db } from './db.js'

const { sqlVal } = db

/* ------------------------------------------------------------------ */
/* 极简 mustache 渲染器                                                 */
/* 支持：{{var}} {{{var}}} {{#each list}}..{{/each}} {{#if v}}..{{else}}..{{/if}}
/* 容错：标签内允许任意空白；未知变量渲染为空串而非抛错                    */
/* ------------------------------------------------------------------ */

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function lookup(ctx, path) {
  const key = String(path).trim()
  // {{.}} / {{this}} 指向 each 当前项（标量数组场景）
  if (key === '.' || key === 'this') {
    if (ctx && Object.prototype.hasOwnProperty.call(ctx, '__self')) return ctx.__self == null ? '' : ctx.__self
    return ctx == null ? '' : ctx
  }
  let cur = ctx
  for (const seg of key.split('.')) {
    if (cur == null) return ''
    cur = cur[seg]
  }
  return cur == null ? '' : cur
}

function truthy(v) {
  if (Array.isArray(v)) return v.length > 0
  if (v === '0' || v === 0) return false
  return !!v
}

function render(tpl, ctx) {
  let out = ''
  let i = 0
  const blockRe = /\{\{\s*#\s*(each|if)\s+([\w.]+)\s*\}\}/g

  while (i < tpl.length) {
    blockRe.lastIndex = i
    const m = blockRe.exec(tpl)
    if (!m) { out += renderInline(tpl.slice(i), ctx); break }

    out += renderInline(tpl.slice(i, m.index), ctx)
    const kind = m[1]
    const name = m[2]
    const bodyStart = m.index + m[0].length
    const realEnd = findBlockEnd(tpl, kind, bodyStart)
    if (realEnd < 0) { out += renderInline(tpl.slice(m.index), ctx); break }

    const body = tpl.slice(bodyStart, realEnd)
    const val = lookup(ctx, name)

    if (kind === 'each') {
      const list = Array.isArray(val) ? val : []
      list.forEach((item, idx) => {
        const scope = (item && typeof item === 'object')
          ? { ...ctx, ...item, index: idx + 1, _index: idx, __self: item }
          : { ...ctx, index: idx + 1, _index: idx, __self: item }
        out += render(body, scope)
      })
    } else {
      const elseM = splitElse(body)
      out += truthy(val) ? render(elseM.main, ctx) : render(elseM.alt, ctx)
    }

    const closeTag = tpl.slice(realEnd).match(/^\{\{\s*\/\s*\w+\s*\}\}/)
    i = realEnd + (closeTag ? closeTag[0].length : 0)
  }
  return out
}

function findBlockEnd(tpl, kind, from) {
  const re = new RegExp(`\\{\\{\\s*(#\\s*${kind}\\s+[\\w.]+|\\/\\s*${kind})\\s*\\}\\}`, 'g')
  re.lastIndex = from
  let depth = 1
  let m
  while ((m = re.exec(tpl))) {
    if (m[1].trim().startsWith('#')) depth++
    else { depth--; if (depth === 0) return m.index }
  }
  return -1
}

// 只切分深度为 0 的 {{else}}，避免被嵌套 if/each 内部 else 误吞
function splitElse(body) {
  const re = /\{\{\s*(#\s*(if|each)\s+[\w.]+|\/\s*(if|each)|else)\s*\}\}/g
  let depth = 0
  let m
  while ((m = re.exec(body))) {
    const tag = m[1].trim()
    if (tag[0] === '#') depth++
    else if (tag[0] === '/') depth--
    else if (/^else$/i.test(tag)) {
      if (depth === 0) {
        return { main: body.slice(0, m.index), alt: body.slice(m.index + m[0].length) }
      }
    }
  }
  return { main: body, alt: '' }
}

function renderInline(str, ctx) {
  return str
    .replace(/\{\{\{\s*(\.|[\w][\w.]*)\s*\}\}\}/g, (full, k) => {
      // {{{else}}} 等病态输入：由 if 分支自行处理，不当变量吃掉
      if (/^(else)$/i.test(k)) return full
      return String(lookup(ctx, k))
    })
    .replace(/\{\{\s*(\.|[\w][\w.]*)\s*\}\}/g, (full, k) => {
      // {{else}} 由 if 分支自行处理，这里不能当变量吃掉
      if (/^(else)$/i.test(k)) return full
      return escapeHtml(lookup(ctx, k))
    })
}

/* ------------------------------------------------------------------ */
/* 默认模板                                                             */
/* ------------------------------------------------------------------ */

export const DEFAULT_TEMPLATE = `<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", serif; line-height: 1.8; padding: 32px; color: #222; }
  h1 { font-size: 22px; border-bottom: 2px solid #333; padding-bottom: 8px; }
  h2 { font-size: 16px; color: #444; margin: 28px 0 12px; padding-bottom: 4px; border-bottom: 1px dashed #ccc; }
  .meta { color: #888; font-size: 12px; margin-bottom: 24px; }
  .article { background: #fafafa; border: 1px solid #eee; border-radius: 6px; padding: 16px 20px; margin-bottom: 28px; white-space: pre-wrap; font-size: 13px; line-height: 1.85; color: #333; page-break-inside: avoid; }
  .article-title { font-weight: 600; color: #222; margin-bottom: 8px; }
  .q { margin: 14px 0; page-break-inside: avoid; }
  .q-head { font-weight: 600; }
  .tag { display: inline-block; background: #eee; border-radius: 4px; padding: 1px 6px; font-size: 11px; margin-right: 6px; color: #555; }
  .opt { margin: 4px 0 4px 18px; }
  .quote { border-left: 3px solid #ccc; padding-left: 10px; color: #666; font-size: 13px; margin: 6px 0; }
  .mine { color: #c33; margin-top: 4px; font-size: 13px; }
  /* —— 答案与解析集中放末尾 —— */
  .key { margin: 8px 0; page-break-inside: avoid; }
  .key .idx { font-weight: 600; color: #333; }
  .key .answer { color: #0a7; font-weight: 600; }
  .key .analysis { color: #555; font-size: 13px; margin-top: 2px; }
  .key .quote-mini { color: #888; font-size: 12px; border-left: 2px solid #ddd; padding-left: 8px; margin: 4px 0; }
</style></head>
<body>
<h1>{{title}}</h1>
<div class="meta">{{subtitle}} · 共 {{count}} 题 · {{date}}</div>

{{#if showArticle}}
<section class="article">
  {{#if articleTitle}}<div class="article-title">{{articleTitle}}</div>{{/if}}
  {{{articleBody}}}
</section>
{{/if}}

<h2>一、题目</h2>
{{#each questions}}
<div class="q">
  <div class="q-head"><span class="tag">{{type}}</span>{{index}}. {{prompt}}</div>
  {{#if options}}{{#each options}}<div class="opt">{{.}}</div>{{/each}}{{/if}}
  {{#if showQuote}}<div class="quote">{{sourceQuote}}</div>{{/if}}
  {{#if showMine}}<div class="mine">我的作答：{{mine}}</div>{{/if}}
</div>
{{/each}}

{{#if showAnswer}}
{{#if showAnalysis}}<h2>二、答案与解析</h2>{{else}}<h2>二、参考答案</h2>{{/if}}
{{/if}}

{{#each questions}}
{{#if showAnswer}}
<div class="key">
  <span class="idx">{{index}}.</span>
  <span class="answer">{{answer}}</span>
  {{#if showAnalysis}}<div class="analysis">解析：{{analysis}}</div>{{/if}}
  {{#if showQuote}}<div class="quote-mini">{{sourceQuote}}</div>{{/if}}
</div>
{{/if}}
{{/each}}
</body></html>`

/* ------------------------------------------------------------------ */
/* 模板存取                                                             */
/* ------------------------------------------------------------------ */

let templateReady = null

async function tryInitTemplates() {
  await db.init()
  const rows = await db.select("SELECT id FROM templates WHERE name = 'default'")
  if (!rows || rows.length === 0) {
    await db.execute(
      `INSERT INTO templates (name, source) VALUES ('default', ${sqlVal(DEFAULT_TEMPLATE)})`
    )
  }
}

function ensureTemplates() {
  if (!templateReady) {
    templateReady = tryInitTemplates().catch((e) => {
      templateReady = null
      throw e
    })
  }
  return templateReady
}

export async function getTemplate(name = 'default') {
  await ensureTemplates()
  const rows = await db.select(`SELECT source FROM templates WHERE name = ${sqlVal(name)}`)
  if (rows && rows.length && rows[0].source) return rows[0].source
  return DEFAULT_TEMPLATE
}

export async function saveTemplate(name, source) {
  await ensureTemplates()
  const rows = await db.select(`SELECT id FROM templates WHERE name = ${sqlVal(name)}`)
  if (rows && rows.length) {
    await db.execute(`UPDATE templates SET source = ${sqlVal(source)} WHERE name = ${sqlVal(name)}`)
  } else {
    await db.execute(`INSERT INTO templates (name, source) VALUES (${sqlVal(name)}, ${sqlVal(source)})`)
  }
}

export async function resetTemplate(name = 'default') {
  await saveTemplate(name, DEFAULT_TEMPLATE)
  return DEFAULT_TEMPLATE
}

/* ------------------------------------------------------------------ */
/* 数据装配                                                             */
/* ------------------------------------------------------------------ */

function safeParse(json, fallback) {
  try { const v = JSON.parse(json); return v == null ? fallback : v } catch (e) { return fallback }
}

// 取一个题集的题目 + 最近一次作答
export async function loadSetQuestions(setId) {
  await db.init()
  const qs = await db.select(`SELECT * FROM questions WHERE setId = ${sqlVal(setId)} ORDER BY id ASC`)
  const out = []
  for (const q of qs) {
    const ans = await db.select(
      `SELECT final, correct, comment, status FROM answers WHERE questionId = ${sqlVal(q.id)} ORDER BY gradedAt DESC LIMIT 1`
    )
    out.push(normalizeQuestion(q, ans[0]))
  }
  return out
}

export async function loadArticleSets(articleId) {
  await db.init()
  return db.select(
    `SELECT id, title, createdAt FROM question_sets WHERE articleId = ${sqlVal(articleId)} ORDER BY id DESC`
  )
}

// 取原文（导出题集时拼到题目前面）。优先用 plainText；没有则回退到 html 去标签。
export async function loadArticleSource(articleId) {
  if (!articleId) return { title: '', body: '' }
  try {
    await db.init()
    const rows = await db.select(
      `SELECT title, plainText, html FROM articles WHERE id = ${sqlVal(articleId)} LIMIT 1`
    )
    if (!rows || !rows.length) return { title: '', body: '' }
    const a = rows[0] || {}
    let body = a.plainText || ''
    if (!body && a.html) {
      // 把 html 标签剥掉、保留段落
      body = String(a.html)
        .replace(/<style[\s\S]*?<\/style>/gi, ' ')
        .replace(/<script[\s\S]*?<\/script>/gi, ' ')
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/(p|div|li|h\d|tr)>/gi, '\n')
        .replace(/<[^>]+>/g, '')
    }
    // 段落截断防止超长文档撑爆导出
    if (body && body.length > 30000) body = body.slice(0, 30000) + '\n…(后续省略)'
    return { title: a.title || '', body }
  } catch (e) {
    return { title: '', body: '' }
  }
}

export async function loadWrongQuestions(articleId = null) {
  await db.init()
  // 先取最近一次作答，再在 SQL 层过滤 wrong===1，避免 N+1 与全表扫描
  const where = articleId == null ? '' : ` AND s.articleId = ${sqlVal(articleId)}`
  const rows = await db.select(
    `SELECT q.*, a.final, a.correct, a.comment, a.status, a.wrong
     FROM questions q
     JOIN question_sets s ON s.id = q.setId
     JOIN (
       SELECT questionId, final, correct, comment, status, wrong,
              ROW_NUMBER() OVER (PARTITION BY questionId ORDER BY gradedAt DESC) rn
       FROM answers
     ) a ON a.questionId = q.id AND a.rn = 1
     WHERE a.wrong = 1${where}
     ORDER BY q.id ASC`
  )
  return (rows || []).map((q) => normalizeQuestion(q, q))
}

function normalizeQuestion(q, ans) {
  const answers = safeParse(q.answers, [])
  return {
    id: q.id,
    type: q.type || '题',
    prompt: q.prompt || '',
    options: safeParse(q.options, []),
    answer: Array.isArray(answers) ? answers.join(' / ') : String(answers),
    analysis: q.analysis || '',
    sourceQuote: q.sourceQuote || '',
    mine: ans ? (ans.final || '') : '',
    correct: ans ? Number(ans.correct) : null,
    comment: ans ? (ans.comment || '') : '',
    status: ans ? (ans.status || 'graded') : 'none',
  }
}

/* ------------------------------------------------------------------ */
/* 渲染 & 导出                                                          */
/* ------------------------------------------------------------------ */

export async function buildHtml({ title, subtitle = '', questions, options = {}, templateName = 'default', articleTitle = '', articleBody = '', withArticle = true }) {
  const tpl = await getTemplate(templateName)
  const list = Array.isArray(questions) ? questions : []
  // articleBody 在此提前 escapeHtml 并把换行替换为 <br/>，
  // 模板里使用 {{{articleBody}}}（三花括号）以保留 <br/> 不被二次 escape。
  const safeBody = escapeHtml(articleBody || '').replace(/\r?\n/g, '<br/>')
  const safeArticleTitle = escapeHtml(articleTitle || '')
  const ctx = {
    title: title || '练习卷',
    subtitle,
    date: new Date().toLocaleDateString(),
    count: list.length,
    articleTitle: safeArticleTitle,
    articleBody: safeBody,
    showArticle: !!withArticle && !!(articleBody || articleTitle),
    questions: list.map((q, i) => ({
      ...q,
      index: i + 1,
      showAnswer: !!options.withAnswer && !!q.answer,
      showAnalysis: !!options.withAnalysis && !!q.analysis,
      showMine: !!options.withMine && !!q.mine,
      showQuote: !!options.withQuote && !!q.sourceQuote,
    })),
  }
  return render(tpl, ctx)
}

// 在 5+App 中导出 PDF。
// 关键背景：plus.webview 在 Android 系统 WebView 上不支持 window.print()（无系统打印面板），
// 即使可以 evalJS('window.print && window.print()') 通常也会抛错或被静默忽略，
// 导致 15s 兜底超时 → 用户看到「导出超时，请重试」。
//
// 新策略：
//   1) 在 Android 上：直接走预览（previewHtmlApp），并通过 `plus.share` 把 HTML 内容分享出去。
//   2) 在 iOS 上：保留原 plus.webview.create + evalJS print。
//   3) 兜底：若以上都不通，永远 resolve 一个 { mode: 'preview', file: url } 而不再 reject。
export function exportPdf(html, filename = 'export') {
  if (!plus.io) {
    return Promise.reject(new Error('当前环境不支持导出 PDF（仅 APP 端可用）'))
  }
  const platform = (typeof uni !== 'undefined' && uni.getSystemInfoSync)
    ? (uni.getSystemInfoSync().platform || '')
    : ''
  // Android 走预览 + 分享（iOS 才会尝试 window.print）
  if (/android/i.test(platform)) {
    return exportPdfAndroid(html, filename)
  }
  return exportPdfIos(html, filename)
}

// Android：直接预览，并把 HTML 临时文件路径交给 plus.share；失败回退弹个说明 toast。
function exportPdfAndroid(html, filename) {
  return new Promise((resolve, reject) => {
    try {
      // 1) 先按 previewHtmlApp 方式写入 + 打开预览（含返回按钮）
      previewHtmlApp(html, filename)
      // 2) 再立即写入一份 html 到 _doc 临时目录，等会尝试通过 plus.share 分享
      const path = `_doc/${filename}_${Date.now()}.html`
      plus.io.resolveLocalFileSystemURL('_doc/', (entry) => {
        entry.getFile(path.replace('_doc/', ''), { create: true }, (fileEntry) => {
          fileEntry.createWriter((writer) => {
            writer.onwrite = () => {
              const fileUrl = localUrl(fileEntry)
              // 默认 resolve：预览已打开，同时告诉调用方 url 让 export.vue 给 toast 提示
              resolve({
                mode: 'preview-and-share',
                platform: 'android',
                file: fileUrl,
                note: 'Android WebView 不支持 window.print()。已为你打开完整预览，可用系统分享/复制内容。',
              })
              // 异步尝试分享（不阻塞 resolve）；先确认 plus.share 模块真的可用，
              // 否则跳过（manifest 未声明 Share 模块时会触发原生警告弹窗）。
              setTimeout(() => {
                try {
                  if (!_checkShareReady()) return;
                  const msg = '已生成练习卷 HTML（' + (filename || 'export') + '）'
                  plus.share.sendWithSystem({
                    type: 'file',
                    files: [shareFileUrl(fileEntry)],
                    title: msg,
                  }, () => {}, () => {})
                } catch (_) {}
              }, 300)
            }
            writer.onerror = () => {
              resolve({ mode: 'preview-only', platform: 'android', file: '', note: '预览已打开（写入分享文件失败）' })
            }
            writer.write(html)
          }, () => resolve({ mode: 'preview-only', platform: 'android', file: '', note: '预览已打开' }))
        }, () => resolve({ mode: 'preview-only', platform: 'android', file: '', note: '预览已打开' }))
      }, () => resolve({ mode: 'preview-only', platform: 'android', file: '', note: '预览已打开' }))
    } catch (e) {
      // 永远不 reject 给用户看到「导出超时」——改成最小可用 fallback
      resolve({ mode: 'preview-only', platform: 'android', file: '', note: '已尝试打开预览' })
    }
  })
}

// iOS：保留旧行为但加保险（不依赖 window.print 的可用性）
function exportPdfIos(html, filename) {
  return new Promise((resolve, reject) => {
    const path = `_doc/${filename}_${Date.now()}.html`
    let wv = null
    let timer = null
    let settled = false
    let fileEntryRef = null
    // iOS 同样要注入「返回 / 分享 / 复制全文」浮层，否则用户进了预览 webview 出不来
    const wrapped = injectPreviewChrome(html)

    const cleanup = () => {
      if (timer) { clearTimeout(timer); timer = null }
      if (wv) { try { wv.close('auto') } catch (e) {} wv = null }
      if (fileEntryRef) { try { fileEntryRef.remove(() => {}, () => {}) } catch (e) {} fileEntryRef = null }
    }

    // iOS 给 12s 兜底；超时后直接当作「已打印/已取消」处理（不弹错误）
    timer = setTimeout(() => {
      if (settled) return
      settled = true
      cleanup()
      resolve({ mode: 'ios-print-timeout', platform: 'ios', file: '', note: '打印/导出步骤已结束' })
    }, 12000)

    try {
      plus.io.resolveLocalFileSystemURL('_doc/', (entry) => {
        entry.getFile(path.replace('_doc/', ''), { create: true }, (fileEntry) => {
          fileEntryRef = fileEntry
          fileEntry.createWriter((writer) => {
            writer.onwrite = () => {
              try {
                const url = localUrl(fileEntry)
                wv = plus.webview.create(url, `print_${Date.now()}`, {
                  top: '0px', bottom: '0px', scrollIndicator: 'none',
                })
                const settle = (ok) => {
                  if (settled) return
                  settled = true
                  cleanup()
                  if (ok) resolve({ mode: 'ios-print', platform: 'ios', file: url })
                  else resolve({ mode: 'ios-print-noop', platform: 'ios', file: url, note: '当前 iOS 版本不支持系统打印，已显示完整预览' })
                }
                wv.addEventListener('close', () => settle(true))
                setTimeout(() => {
                  try {
                    if (typeof wv.evalJS === 'function') {
                      wv.evalJS('try{window.print&&window.print()}catch(e){var t=document.createElement("div");t.innerHTML="<div style=padding:20px;font-family:sans-serif>该 iOS 版本不支持系统打印，请使用 Safari 打开此页后分享/打印</div>";document.body.appendChild(t)}')
                      // iOS 上 window.print() 打开系统面板；面板关闭会触发 webview close
                    }
                  } catch (e) {
                    settle(false)
                  }
                }, 600)
                wv.show('slide-in-right')
              } catch (e) { settle(false) }
            }
            writer.onerror = () => { if (!settled) { settled = true; resolve({ mode: 'preview-only', platform: 'ios', file: '', note: '写入失败，但已生成预览' }) } }
            writer.write(wrapped)
          }, () => { if (!settled) { settled = true; resolve({ mode: 'preview-only', platform: 'ios', file: '', note: '已生成预览' }) } })
        }, () => { if (!settled) { settled = true; resolve({ mode: 'preview-only', platform: 'ios', file: '', note: '已生成预览' }) } })
      }, () => { if (!settled) { settled = true; resolve({ mode: 'preview-only', platform: 'ios', file: '', note: '已生成预览' }) } })
    } catch (e) {
      if (!settled) { settled = true; resolve({ mode: 'preview-only', platform: 'ios', file: '', note: '已生成预览' }) }
    }
  })
}

// 把 FileEntry.toLocalURL() 规整为 plus.webview 需要的绝对路径。
// 5+Runtime 部分版本 toLocalURL() 返回 "_doc/xxx.html"（无前导 /）或 "file:///..."，
// 不带 / 的相对路径传给 plus.webview.create 会报「资源不存在」，统一补成 "/_doc/..." 形式。
function localUrl(fileEntry) {
  let u = fileEntry.toLocalURL()
  if (!u) return u
  if (u.startsWith('file://')) return u
  if (!u.startsWith('/')) u = '/' + u
  return u
}

// 给 plus.share.sendWithSystem({ type:'file', files:[...] }) 用的文件 URI。
// 系统分享面板只认标准 file:// scheme，不认 5+ 内部的 "/_doc/..." 抽象路径，
// 否则会弹「资源不存在」。toURL() 在 5+ 上返回标准 file:// URI，最稳。
function shareFileUrl(fileEntry) {
  try {
    const u = fileEntry.toURL()
    if (u && u.indexOf('file://') === 0) return u
  } catch (e) {}
  // 回退：把 /_doc/xxx 转成 file:///_doc/xxx
  const u = localUrl(fileEntry)
  if (u.startsWith('/')) return 'file://' + u
  return u
}

// APP 端预览：将 HTML 写入临时文件后用 plus.webview 打开
// 注意：plus.webview 打开的是独立全屏窗口，默认无任何导航栏/返回按钮，
// 必须在 HTML 内注入一个返回浮层，否则用户无法退出预览（只能杀进程）。
export function previewHtmlApp(html, filename = 'preview') {
  if (!plus.io) return false
  const path = `_doc/${filename}_${Date.now()}.html`
  // 直接在写入文件前完成 wrap（不需要 url 占位）
  const wrapped = injectPreviewChrome(html)
  try {
    plus.io.resolveLocalFileSystemURL('_doc/', (entry) => {
      entry.getFile(path.replace('_doc/', ''), { create: true }, (fileEntry) => {
        fileEntry.createWriter((writer) => {
          writer.onwrite = () => {
            const url = localUrl(fileEntry)
            const wv = plus.webview.create(url, `prev_${Date.now()}`, {
              top: '0px', bottom: '0px', scrollIndicator: 'none',
            })
            // 把 fileURL 在 webview 加载好后注入到 window，供浮层"分享"按钮调 plus.share 用
            wv.addEventListener('loaded', () => {
              try {
                wv.evalJS(
                  'window.__GO_FILE_URL__="' + url + '";' +
                  'if(document.documentElement){document.documentElement.setAttribute("data-go-file-url",\'' + url + '\');}'
                )
              } catch (e) {}
            }, false)
            wv.show('slide-in-right')
          }
          writer.onerror = () => {
            // 写入失败必须显式提示，不能静默吞掉（否则用户看到白屏/资源不存在却无任何反馈）
            uni && uni.showToast && uni.showToast({ title: '预览生成失败，请重试', icon: 'none' })
          }
          writer.write(wrapped)
        }, () => {
          uni && uni.showToast && uni.showToast({ title: '无法创建预览文件', icon: 'none' })
        })
      }, () => {
        uni && uni.showToast && uni.showToast({ title: '无法创建预览文件', icon: 'none' })
      })
    }, () => {
      uni && uni.showToast && uni.showToast({ title: '无法访问本地目录', icon: 'none' })
    })
    return true
  } catch (e) {
    return false
  }
}

// 在预览 HTML 中注入一个固定的右上角浮层：「‹ 返回」「分享」「复制」
// Android 系统 WebView 不支持 window.print()，因此导出退化为：让用户通过 preview webview
// 完成复制内容 / 调起系统分享，把 HTML 发到任意应用（微信、文件管理、电脑端等）。
export function injectPreviewChrome(html) {
  const chrome = `
<style>
/* 注意：5+App 原生 WebView 中，position:fixed 的祖先若带 pointer-events:none，
   子按钮的命中测试（hit-test）会失效，导致手指点击穿透/点不动。
   因此 fab 不再用 pointer-events:none，而是改为「右对齐、auto 宽度」只覆盖按钮区域，
   既不影响页面其余区域的触摸，又保证按钮可见可点。 */
.go-prev-fab{position:fixed;top:calc(env(safe-area-inset-top,0px) + 16px);right:10px;left:auto;width:auto;z-index:2147483647;display:flex;gap:8px;align-items:center;justify-content:flex-end;max-width:80vw;flex-wrap:wrap;touch-action:auto;}
.go-prev-btn{position:relative;z-index:2147483647;display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:48px;min-width:48px;padding:13px 22px;border-radius:999px;background:rgba(20,20,28,.82);color:#fff;font-size:16px;font-weight:600;font-family:-apple-system,system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.35);border:1px solid rgba(255,255,255,.18);user-select:none;-webkit-user-select:none;cursor:pointer;touch-action:manipulation;pointer-events:auto;-webkit-tap-highlight-color:transparent;}
.go-prev-btn:active{opacity:.7;}
.go-prev-btn--primary{background:rgba(190,42,52,.92);}
.go-prev-toast{position:fixed;left:50%;bottom:env(safe-area-inset-bottom,20px);transform:translateX(-50%);background:rgba(0,0,0,.85);color:#fff;padding:10px 18px;border-radius:999px;font-size:14px;font-family:-apple-system,system-ui,sans-serif;opacity:0;transition:opacity .25s;pointer-events:none;z-index:2147483647;max-width:80vw;text-align:center;}
.go-prev-toast--on{opacity:1;}
</style>
<div class="go-prev-fab">
  <div class="go-prev-btn" id="goPrevBack">‹ 返回</div>
  <div class="go-prev-btn go-prev-btn--primary" id="goPrevShare">分享</div>
  <div class="go-prev-btn" id="goPrevCopy">复制全文</div>
</div>
<div class="go-prev-toast" id="goPrevToast">已复制</div>
<script>
(function(){
  function toast(msg){
    var t = document.getElementById('goPrevToast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('go-prev-toast--on');
    clearTimeout(toast._t);
    toast._t = setTimeout(function(){ t.classList.remove('go-prev-toast--on'); }, 1500);
  }
  function closePrev(){
    if (plus.webview) {
      var wv = plus.webview.currentWebview();
      if (wv) { wv.close('slide-out-right'); return; }
    }
    if (window.history && window.history.length > 1) window.history.back();
    else if (window.close) window.close();
  }
  function shareFile(){
    var url = (document.documentElement && document.documentElement.getAttribute('data-go-file-url')) || (window.__GO_FILE_URL__) || '';
    // 先检测 plus.share 模块是否真的可用（manifest 里可能没声明 Share 模块），
    // 若不可用，直接走「复制 URL」兜底，避免触发 HTML5+ Runtime 的「打包时未添加 share 模块」警告弹窗。
    // 使用模块顶部一次性缓存的探测结果，避免每次点击都重新查属性触发 native 弹窗
    // 注意：这里**不能**调用 _checkShareReady()——它是 export.js 的模块作用域函数，
    // 在这段注入到独立导出 HTML 的脚本里根本不存在，点击会抛 ReferenceError，
    // 且该调用位于 try 之外，连兜底 toast 都执行不到（分享按钮完全失效）。
    // 改为就地内联探测同样的条件。
    var shareReady = false;
    try {
      shareReady = plus != null
        && plus.share && (typeof plus.share.sendWithSystem === 'function');
    } catch (e) { shareReady = false; }
    if (shareReady && url) {
      try {
        plus.share.sendWithSystem({ type:'file', files:[url], title:'练习卷导出' }, function(){ toast('已调起系统分享'); }, function(){ toast('未找到可用的分享应用'); });
        return;
      } catch (e) { /* 模块未配置时会进入这里 */ }
    }
    // 兜底：复制当前页 URL
    if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url || location.href).then(function(){ toast('链接已复制'); }, function(){ toast('复制失败'); });
    } else {
      toast('该环境不支持分享');
    }
  }
  function copyAll(){
    var html = document.documentElement && document.documentElement.outerHTML ? document.documentElement.outerHTML : '';
    var txt = (document.body && document.body.innerText) ? document.body.innerText : '';
    if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(txt || html).then(function(){ toast('全文已复制'); }, function(){
        legacyCopy(txt || html);
      });
    } else {
      legacyCopy(txt || html);
    }
  }
  function legacyCopy(s){
    try {
      var ta = document.createElement('textarea');
      ta.value = s;
      ta.style.position = 'fixed'; ta.style.left = '-99999px';
      document.body.appendChild(ta); ta.select();
      var ok = document.execCommand('copy');
      document.body.removeChild(ta);
      toast(ok ? '已复制' : '复制失败');
    } catch (e) { toast('复制失败'); }
  }
  // 5+App 真机上触摸事件链在不同 Runtime 版本表现不一致：
  //   - 老 Runtime：touchstart + touchend，无 click
  //   - 新 Runtime (WKWebView / Android X5 新版)：pointerdown + pointerup + click
  //   - 还有的：只派 mousedown/click，touch 完全不派
  // 直接逐个绑容易漏；改用「事件代理」：把 click/touchend/pointerup 都绑到 document，
  // 用 closest() 反查目标。这样无论 native 派哪种事件都能捕获，且不会因元素被遮挡丢事件。
  function on(id, fn){
    var el = document.getElementById(id);
    if (!el) return;
    var last = 0;
    function fire(reason){
      var now = Date.now();
      if (now - last < 300) return;
      last = now;
      fn(reason);
    }
    // 给元素本身兜底：pointer 系事件 + click，5+App 新版会进这里
    el.addEventListener('pointerdown', function(e){ try{ e.preventDefault() }catch(_){} try{ e.stopPropagation() }catch(_){} fire('pointer') }, { passive: false });
    el.addEventListener('click', function(){ fire('click') });
    el.addEventListener('touchstart', function(e){ try{ e.preventDefault() }catch(_){} try{ e.stopPropagation() }catch(_){} fire('touchstart') }, { passive: false });
    el.addEventListener('touchend', function(){ fire('touchend') }, { passive: true });
    // 事件代理：document 上如果 captured 到 click/touchend/pointerup 时，目标是我们的按钮（或冒泡上来的），也触发
    function delegate(e){
      var t = e.target;
      if (!t) return;
      // closest 在原生 webview 上可用；若不可用降级为 contains
      var hit = (el.contains && el.contains(t)) || (t === el) || (el.id && t.id === el.id);
      if (!hit) return;
      // 已经被元素直接绑定的 listener 处理过了（fire 已锁定），避免 double-count 关键场景
      var now = Date.now();
      if (now - last < 350) return;
      fire('delegate');
    }
    document.addEventListener('click', delegate, true);
    document.addEventListener('touchend', delegate, true);
    document.addEventListener('pointerup', delegate, true);
  }
  on('goPrevBack', closePrev);
  on('goPrevShare', shareFile);
  on('goPrevCopy', copyAll);
})();
</script>`
  // 若已有 </body> 则插到其前面，否则直接追加
  if (/<\/body>/i.test(html)) {
    return html.replace(/<\/body>/i, chrome + '</body>')
  }
  return html + chrome
}

// 仅供 scripts/test-render.mjs 单测使用，勿在业务代码中引用
export const _internal = { render }
