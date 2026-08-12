<template>
  <view class="page">
    <view class="go-appbar floating reader-bar">
      <view class="back" @click="goBack" @tap="goBack" hover-class="none" hover-stay-time="0">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <text class="reader-bar__title">{{ title || '文章阅读' }}</text>
      <view class="go-appbar__actions">
        <view class="go-icon-btn" :class="{ on: selectMode }" @click="toggleSelectMode" title="选择">
          <GoIcon name="menu" :size="'52rpx'" />
        </view>
        <view class="go-icon-btn" @click="addToPlan" title="加入计划">
          <GoIcon name="bookmark" :size="'52rpx'" />
        </view>
        <view class="go-icon-btn" @click="showSettings = !showSettings" title="设置">
          <GoIcon name="settings" :size="'52rpx'" />
        </view>
      </view>
    </view>

    <!-- 选择模式提示 -->
    <view v-if="selectMode" class="sel-hint go-fade-in">
      <text>点选多个单词组成选区，点「查询」翻译 · 再次点词取消选中</text>
    </view>

    <!-- 文章封面（ReadYou 风格：衬线大标题 + 来源 + 阅读时长） -->
    <view v-if="!loading && !error && (title || cover.source)" class="cover">
      <text v-if="cover.source" class="cover-source">{{ cover.source }}</text>
      <text class="cover-title">{{ title || '未命名文章' }}</text>
      <view class="cover-meta">
        <text v-if="cover.date" class="cover-date">{{ cover.date }}</text>
        <text v-if="cover.readMins" class="cover-dot">·</text>
        <text v-if="cover.readMins" class="cover-read">{{ cover.readMins }} 分钟阅读</text>
      </view>
    </view>

    <view v-if="showSettings" class="settings go-sheet-down">
      <view class="set-row">
        <text class="set-label">字号</text>
        <view class="stepper">
          <view class="step btn-icon ink" @click="changeFont(-1)">A−</view>
          <text class="set-val">{{ reader.fontSize }}</text>
          <view class="step btn-icon ink" @click="changeFont(1)">A＋</view>
        </view>
      </view>
      <view class="set-row">
        <text class="set-label">行距</text>
        <view class="stepper">
          <view class="step btn-icon ink" @click="changeLine(-0.1)">−</view>
          <text class="set-val">{{ reader.lineHeight.toFixed(1) }}</text>
          <view class="step btn-icon ink" @click="changeLine(0.1)">＋</view>
        </view>
      </view>
      <view class="set-row">
        <text class="set-label">翻译</text>
        <view class="engine-pick">
          <text
            v-for="e in engineList"
            :key="e.id"
            class="eng-chip"
            :class="{ on: reader.transEngine === e.id }"
            @click="setTransEngine(e.id)"
          >{{ e.name }}</text>
        </view>
      </view>
      <view class="set-row">
        <text class="set-tip">单击查词 · 长按整句 · 工具栏「选择」可点选多词翻译</text>
      </view>
    </view>

    <view v-if="loading" class="state">
      <PolySpinner />
      <text>正文加载中…</text>
    </view>
    <view v-else-if="error" class="state err">
      <text>{{ error }}</text>
      <text class="retry btn-text" @click="loadArticle">重试</text>
    </view>

    <scroll-view v-else scroll-y class="reader" :style="readerStyle">
      <!-- 原生渲染：混合块序列（段落逐词查词 + 图片）-->
      <template v-for="(b, bi) in tokenizedBlocks" :key="bi">
        <view
          v-if="b.type === 'p'"
          class="content article-p"
          @longpress="onParaLongPress(paraIndexMap[bi])"
        ><template v-for="(tk, ti) in b.toks" :key="ti"><view
            v-if="tk.word"
            :class="['tok tok--word', { 'tok--sel': isSel(paraIndexMap[bi], ti) }]"
            @click="onNativeTok(tk, false, b.text, paraIndexMap[bi], ti)"
            @longpress="onNativeTok(tk, true, b.text, paraIndexMap[bi], ti)"
          ><text>{{ tk.text }}</text></view><text
            v-else
            class="tok"
          >{{ tk.text }}</text></template></view>
        <view v-else-if="b.type === 'img'" v-show="!b._err" class="article-img" @click="onImgTap(b.src)">
          <image
            class="article-img__el"
            :src="b.src"
            :mode="'widthFix'"
            :lazy-load="true"
            @error="onImgError(bi)"
          />
          <text v-if="b.alt" class="article-img__cap">{{ b.alt }}</text>
        </view>
      </template>
      <view class="tail">— 全文完 —</view>
    </scroll-view>

    <!-- 选区浮动操作条 -->
    <view v-if="selection.text || selectedText" class="sel-bar go-slide-up">
      <text class="sel-text">{{ selectionPreview }}</text>
      <text class="sel-btn" @click="lookupSelection">查询</text>
      <text class="sel-btn ghost" @click="clearSelection">取消</text>
    </view>

    <WordCard
      :visible="wordVisible"
      :word="activeWord"
      :context="activeContext"
      :translate-disabled="isQuiz"
      @close="wordVisible = false"
    />
  </view>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import { db } from '@/utils/db.js'
import { useAppStore } from '@/stores/app.js'
import { normalizeQuery } from '@/utils/word.js'
import WordCard from '@/components/WordCard.vue'
import PolySpinner from '@/components/PolySpinner.vue'
import GoIcon from '@/components/GoIcon.vue'
import { useTransition } from '@/composables/useTransition'
import { fetchText } from '@/utils/http.js'
import { extractArticle } from '@/utils/extract.js'

const transition = useTransition('secondary')
onShow(() => transition.onEnter())

const { sqlVal } = db

const store = useAppStore()
const bodyHtml = ref('')
// 正文块序列（段落 + 图片）：优先来自入库的 blocks，否则由 plainText 退化
const blocks = ref([])
// App 端逐词点击/长按查词：加载纯文本并按段落拆分，逐词渲染为可点击片段。
const plainText = ref('')
// 段落序列直接派生自 blocks 的文本块，保证查词/选区索引与渲染完全一致
const paragraphs = computed(() =>
  blocks.value.filter((b) => b.type === 'p').map((b) => b.text)
)
const title = ref('')
const guid = ref('')
const article = ref(null)
const articleId = ref(0)
const sourceUrl = ref('')
const wordCount = ref(0)

// 封面元信息（ReadYou 风格：来源名 / 日期 / 阅读时长）
const cover = computed(() => {
  const a = article.value
  let host = ''
  try { host = sourceUrl.value ? new URL(sourceUrl.value).hostname.replace(/^www\./, '') : '' } catch (e) {}
  if (!host) host = (a && (a.feed || a.feedName)) || '收录文章'
  const dt = a && (a.publishedAtText || a.pubDate || a.ts)
  const readMins = wordCount.value ? Math.max(1, Math.round(wordCount.value / 60)) : 0
  return { source: host, date: dt ? fmtDate(dt) : '', readMins }
})
const loading = ref(true)
const error = ref('')

const showSettings = ref(false)
const wordVisible = ref(false)
const activeWord = ref('')
const activeContext = ref('')
const selection = ref({ text: '', context: '' })

// 原生端「点选累积选区」：App/小程序无拖选能力，用逐词点选拼出选区
const selectMode = ref(false)
// 是否处于做题模式（从 quiz 页跳转时携带 quiz=1）。做题时禁用翻译以防直接看答案。
const isQuiz = ref(false)
const selTokens = ref([]) // 元素 { pi, ti, text }
function toggleSelectMode() {
  selectMode.value = !selectMode.value
  if (!selectMode.value) selTokens.value = [] // 退出选择模式即清空选区
}
const selectedText = computed(() => selTokens.value.map((t) => t.text).join(' ').trim())
function isSel(pi, ti) {
  return selTokens.value.some((t) => t.pi === pi && t.ti === ti)
}
function toggleSelToken(tk, pi, ti) {
  if (!tk || !tk.word) return
  const idx = selTokens.value.findIndex((t) => t.pi === pi && t.ti === ti)
  if (idx >= 0) selTokens.value.splice(idx, 1)
  else selTokens.value.push({ pi, ti, text: tk.text })
}

const reader = computed(() => store.reader)
const readerStyle = computed(() => ({
  fontSize: reader.value.fontSize + 'px',
  lineHeight: String(reader.value.lineHeight),
}))
const selectionPreview = computed(() => {
  const t = selectedText.value || selection.value.text
  return t.length > 24 ? t.slice(0, 24) + '…' : t
})

onLoad((q) => {
  guid.value = decodeURIComponent((q && q.guid) || '')
  title.value = decodeURIComponent((q && q.title) || '')
  isQuiz.value = !!(q && q.quiz)
})

async function loadArticle() {
  loading.value = true
  error.value = ''
  try {
    await db.init()
    const rows = await db.select(
      `SELECT id, html, plainText, title, sourceUrl, wordCount FROM articles WHERE guid = ${sqlVal(guid.value)} LIMIT 1`
    )
    if (rows && rows.length) {
      article.value = rows[0]
      articleId.value = rows[0].id
      bodyHtml.value = rows[0].html || ''
      plainText.value = rows[0].plainText || ''
      sourceUrl.value = rows[0].sourceUrl || ''
      wordCount.value = rows[0].wordCount || 0
      if (!title.value) title.value = rows[0].title || ''
      // 优先使用入库的 blocks（含图片）；旧数据无 blocks 时用纯文本退化
      let bs = null
      try { bs = rows[0].blocks ? JSON.parse(rows[0].blocks) : null } catch (e) { bs = null }
      if (Array.isArray(bs) && bs.length) {
        blocks.value = bs
      } else {
        // 兼容老库：把 plainText 拆段当作纯文本块
        const ps = (plainText.value || '').split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean)
        blocks.value = ps.map((t) => ({ type: 'p', text: t }))
      }
    } else {
      // 自愈：原文行可能因缓存清理/旧版本入库丢失，但 feed_items 里还有源链接。
      // 按 guid 找回 link → 重新抓取 → 入库 → 再查一遍。
      const linkRows = await db.select(
        `SELECT link, title FROM feed_items WHERE guid = ${sqlVal(guid.value)} LIMIT 1`
      )
      const link = linkRows && linkRows[0] && linkRows[0].link
      if (link) {
        try {
          const rawHtml = await fetchText(link, { timeout: 20000 })
          const ext = extractArticle(rawHtml, link)
          const bodyHtmlLocal = ext.html
          const extPlain = ext.plainText
          const extWordCount = ext.wordCount
          const extBlocks = ext.blocks
          if (!extPlain || extPlain.length < 200) throw new Error('正文过短，可能页面结构不受支持')
          await db.execute(
            'INSERT INTO articles (guid, title, sourceUrl, html, plainText, blocks, wordCount, capturedAt) VALUES ('
            + `${sqlVal(guid.value)}, ${sqlVal(title.value || (linkRows[0].title || ''))}, ${sqlVal(link)}, `
            + `${sqlVal(bodyHtmlLocal)}, ${sqlVal(extPlain)}, ${sqlVal(JSON.stringify(extBlocks))}, `
            + `${sqlVal(extWordCount)}, ${sqlVal(Date.now())})`
          )
          const rows2 = await db.select(
            `SELECT id, html, plainText, title, sourceUrl, wordCount FROM articles WHERE guid = ${sqlVal(guid.value)} LIMIT 1`
          )
          if (rows2 && rows2.length) {
            article.value = rows2[0]
            articleId.value = rows2[0].id
            bodyHtml.value = rows2[0].html || ''
            plainText.value = rows2[0].plainText || ''
            sourceUrl.value = rows2[0].sourceUrl || ''
            wordCount.value = rows2[0].wordCount || 0
            if (!title.value) title.value = rows2[0].title || ''
            // 与上方「旧数据兼容」分支保持一致的防御：blocks 字段损坏不得冒泡到外层 catch
            let bs = null
            try { bs = rows2[0].blocks ? JSON.parse(rows2[0].blocks) : null } catch (e) { bs = null }
            blocks.value = Array.isArray(bs) && bs.length
              ? bs
              : (plainText.value || '').split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean).map((t) => ({ type: 'p', text: t }))
            error.value = ''
          } else {
            error.value = '未找到正文，请返回列表重新抓取'
          }
        } catch (e2) {
          error.value = '原文未缓存且自动重新抓取失败：' + (e2.message || '')
        }
      } else {
        error.value = '未找到正文，请返回列表重新抓取'
      }
    }
    // 原生端（无 DOM）依赖 plainText 渲染逐词查词；若为空（旧数据/未落库）则从 html 兜底派生
    ensurePlainText()
  } catch (e) {
    error.value = e.message || '加载失败'
  } finally {
    loading.value = false
  }
}

/* ---------------- 取词 / 选区 ---------------- */

// 原生端长按段落：直接选中整段文本（不依赖 DOM innerText，用段落数据索引取值）
function onParaLongPress(pi) {
  const para = (paragraphs.value && paragraphs.value[pi]) || ''
  if (!para || !para.trim()) return
  selection.value = { text: para.trim().slice(0, 400), context: para.trim() }
}

// 点击正文图片：调用系统预览大图（长按可保存）
function onImgTap(src) {
  if (!src) return
  const urls = blocks.value.filter((b) => b.type === 'img' && b.src).map((b) => b.src)
  if (!urls.length) return
  try {
    uni.previewImage({ current: src, urls })
  } catch (e) {
    // 极少数 webview 不支持预览时静默忽略
  }
}

// 预计算每个 block 的段落序号（仅对 type==='p' 计数），返回 bi -> paraIndex 映射，
// 避免渲染时在模板里反复调用 O(n^2) 的遍历。paraIndexMap 依赖 blocks 自动重算。
const paraIndexMap = computed(() => {
  const arr = []
  let n = 0
  for (let i = 0; i < blocks.value.length; i++) {
    if (blocks.value[i].type === 'p') { arr.push(n); n++ } else arr.push(-1)
  }
  return arr
})

// 预计算 tokenize 结果并写入每个文本块的 toks 字段，避免每次渲染对全文重新切词。
// 模板直接消费 b.toks，配合 paraIndexMap 彻底消除重渲染时的重复计算。
const tokenizedBlocks = computed(() => blocks.value.map((b) =>
  b.type === 'p' ? { ...b, toks: tokenize(b.text) } : b
))

// 图片加载失败：隐藏该图块（避免裂图占位占版面）
function onImgError(bi) {
  if (blocks.value[bi]) blocks.value[bi]._err = true
}

// 取词长按：选中该词所在完整句子（句子边界按 .!? 切分），弹选区条供查询
function sentenceAround(p, ti) {
  const toks = tokenize(p)
  if (!toks.length) return p.trim()
  // 累加长度定位第 ti 个 token 的字符起点
  let start = 0
  for (let i = 0; i < ti && i < toks.length; i++) start += toks[i].text.length
  const off = Math.min(start, p.length)
  const sentenceEnd = /[.!?。！？]/g
  // 向前找句首
  let s = off
  while (s > 0) {
    const ch = p[s - 1]
    if (/[.!?。！？]/.test(ch)) break
    s--
  }
  // 向后找句尾
  let e = off
  sentenceEnd.lastIndex = 0
  const rest = p.slice(off)
  const m = rest.match(/^[A-Za-z'\u2019-]*\s*/) // 跳过当前词
  const from = off + (m ? m[0].length : 0)
  const tail = p.slice(from)
  const mm = tail.match(/^[^.!?。！？]*/)
  e = from + (mm ? mm[0].length : 0)
  // 向后扩展到句尾标点
  const tail2 = p.slice(e)
  const dot = tail2.match(/^[.!?。！？]+/)
  if (dot) e += dot[0].length
  const sentence = p.slice(s, e).trim()
  return sentence || p.trim()
}

// 原生端逐词查词：把段落切成「词 + 空白/标点」片段，词可点击。
// 关键：空白 token 改用 NBSP(\u00A0)，避免原生 webview 把 inline <view>/<text>
// 内首尾空白裁掉导致单词粘连。NBSP 渲染宽度等同普通空格，视觉无差。
function tokenize(p) {
  if (!p) return []
  const out = []
  const re = /(\s+|[A-Za-z][A-Za-z'’-]*[A-Za-z]|[A-Za-z]|[^A-Za-z\s]+)/g
  let m
  while ((m = re.exec(p)) !== null) {
    let t = m[0]
    if (/^\s+$/.test(t)) {
      // 保留 \n / \t；单空格与连续空格统一换为 NBSP，避免被原生布局器折叠裁切
      t = t.replace(/[^\n\t]/g, '\u00A0')
    }
    const word = /^[A-Za-z][A-Za-z'’-]*$/.test(t)
    out.push({ text: t, word })
  }
  return out
}

// 原生端点词：选择模式下点击/长按=累积/取消选区；否则短按=查单词，长按=选中整句
function onNativeTok(tk, isLong, ctx, pi, ti) {
  if (!tk || !tk.word) return // 仅单词片段可触发，空白/标点不响应
  if (selectMode.value) {
    toggleSelToken(tk, pi, ti)
    return
  }
  if (isLong) {
    // 长按 = 选中该词所在完整句子，弹选区条供整句查询
    const sentence = sentenceAround(ctx, ti)
    if (sentence) {
      selection.value = { text: sentence.slice(0, 400), context: sentence }
      return
    }
  }
  openWord(tk.text, isLong ? (ctx || '') : '')
}

// 统一打开词卡：点击 / 选中 最终都走这里，避免中间态失败
function openWord(text, context) {
  const clean = normalizeQuery(text)
  if (!clean) return
  activeWord.value = clean
  activeContext.value = context || ''
  wordVisible.value = true
}

function ensurePlainText() {
  if (plainText.value && plainText.value.trim()) return
  if (!bodyHtml.value) return
  // 兜底：从 html 去标签提取纯文本
  const tmp = bodyHtml.value
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim()
  plainText.value = tmp
}

function lookupSelection() {
  // 原生逐词多选优先；否则取平台选区兜底
  const text = selectedText.value || selection.value.text
  const context = selection.value.context
  if (!text) return
  openWord(text, context)
  clearSelection()
}

function clearSelection() {
  selection.value = { text: '', context: '' }
  selTokens.value = []
  selectMode.value = false
}

/* ---------------- 阅读设置 ---------------- */

function changeFont(d) {
  const v = Math.min(28, Math.max(14, reader.value.fontSize + d))
  store.setReader({ fontSize: v })
}
function changeLine(d) {
  const v = Math.min(2.4, Math.max(1.2, Math.round((reader.value.lineHeight + d) * 10) / 10))
  store.setReader({ lineHeight: v })
}

// 翻译引擎选项（与 translate.js 的 ENGINE_NAMES / ENGINE_ORDER 对齐）
const engineList = [
  { id: 'auto', name: '自动' },
  { id: 'baidu', name: '百度翻译' },
  { id: 'mymemory', name: 'MyMemory' },
  { id: 'libre', name: 'LibreTranslate' },
  { id: 'llm', name: 'LLM' },
]
function setTransEngine(id) {
  store.setReader({ transEngine: id || 'auto' })
}

function goBack() {
  // 多重兜底：APP 端 sticky bar 下，单次 navigateBack 偶发丢失
  // 1) 先正常 navigateBack
  // 2) 200ms 后若没回退成功且还在 article 页，直接 reLaunch reading
  const before = getCurrentPages().length
  try { uni.navigateBack({ delta: 1 }) } catch (e) {}
  setTimeout(() => {
    const cur = getCurrentPages()
    if (cur.length >= before) {
      try { uni.reLaunch({ url: '/pages/reading/reading' }) } catch (e) {}
    }
  }, 220)
}

async function addToPlan() {
  try {
    await db.init()
    let aid = articleId.value
    if (!aid) {
      const a = await db.select(`SELECT id FROM articles WHERE guid = ${sqlVal(guid.value)} LIMIT 1`)
      if (!a || !a.length) { uni.showToast({ title: '文章未入库', icon: 'none' }); return }
      aid = a[0].id
    }
    await db.execute(
      'INSERT OR IGNORE INTO plan_items (articleId, addedAt, status) VALUES ('
      + `${sqlVal(aid)}, ${sqlVal(Date.now())}, 'pending')`
    )
    uni.showToast({ title: '已加入计划', icon: 'success' })
  } catch (e) {
    uni.showToast({ title: e.message || '加入失败', icon: 'none' })
  }
}

onMounted(() => {
  store.initReader()
  loadArticle()
})
</script>

<style scoped lang="scss">
@keyframes go-slide-up {
  from { transform: translateY(120%); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
@keyframes go-sheet-down {
  from { transform: translateY(-100%); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
.page {
  box-sizing: border-box;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
  transition: background var(--go-dur-med) var(--go-ease-standard),
    color var(--go-dur-med) var(--go-ease-standard);
}
.reader-bar {
  background: color-mix(in srgb, var(--go-bg) 80%, transparent);
  display: flex; align-items: center; gap: var(--go-sp-3);
}
.reader-bar__title {
  flex: 1; min-width: 0;
  font-size: var(--go-fs-body-sm);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-bg);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}

.settings {
  padding: var(--go-sp-2) 0;
  border-bottom: 1rpx solid var(--go-outline);
  background: var(--go-surface-raised);
}
.go-sheet-down { animation: go-sheet-down var(--go-dur-med) var(--go-ease-emphasized) both; }
.set-row {
  display: flex;
  align-items: center;
  margin: 0 var(--go-sp-6);
  padding: var(--go-sp-4) 0;
  border-bottom: 1rpx solid var(--go-outline);
}
.set-row:last-child { border-bottom: none; }
.set-label { width: 96rpx; font-size: var(--go-fs-body-sm); color: var(--go-on-surface); }
.set-tip { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }
.stepper { display: flex; align-items: center; margin-left: auto; gap: var(--go-sp-2); }
.step {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 64rpx;
  height: 64rpx;
  border-radius: var(--go-r-full);
  background: var(--go-surface-2);
  color: var(--go-on-surface);
  font-size: var(--go-fs-body-sm);
  &:active { background: var(--go-sel); }
}
.set-val { font-size: var(--go-fs-body-sm); min-width: 80rpx; text-align: center; color: var(--go-on-surface-3); }

.engine-pick { display: flex; gap: var(--go-sp-2); margin-left: auto; flex-wrap: wrap; justify-content: flex-end; }
.eng-chip {
  padding: var(--go-sp-1) var(--go-sp-4);
  font-size: var(--go-fs-meta);
  border-radius: var(--go-r-full);
  border: 1rpx solid var(--go-outline);
  color: var(--go-on-surface-3);
  background: transparent;
  transition: all var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(.9); }
  &.on {
    border-color: var(--go-primary);
    color: var(--go-primary);
    background: var(--go-primary-95);
  }
}

.state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--go-sp-6);
  color: var(--go-on-surface-3);
  font-size: var(--go-fs-body-sm);
  /* 加载容器：明确的不透明卡片，避免与正文重叠时透出底层文字 */
  background: var(--go-surface);
  border-radius: var(--go-r-lg);
  box-shadow: var(--go-elev-1);
  padding: var(--go-sp-8) var(--go-sp-6);
  margin: var(--go-sp-6);
}
.state.err {
  color: var(--go-danger);
  background: color-mix(in srgb, var(--go-danger) 8%, var(--go-surface));
}

.reader { flex: 1; padding: var(--go-sp-6) var(--go-sp-6) 0; background: inherit; }
.content {
  color: inherit;
  /* App 端用「逐词点选」做选区，禁用原生文本选择以免与点击冲突 */
  user-select: none;
  -webkit-user-select: none;
  -webkit-touch-callout: none;
  letter-spacing: .2rpx;
  font-family: var(--go-font-read);
  background: transparent;
  max-width: 720rpx;
  margin: 0 auto;
}
.tok { line-height: inherit; white-space: pre; }
.tok--word {
  display: inline-block;
  padding: 0 1rpx;
  transition: background var(--go-dur-fast) var(--go-ease-standard);
  border-radius: 6rpx;
  white-space: pre;
}
.tok--word:active { background: var(--go-sel-strong); }
.tok--sel {
  background: var(--go-sel-word);
  box-shadow: inset 0 0 0 2rpx var(--go-primary);
  border-radius: 6rpx;
  font-weight: var(--go-fw-semibold);
}

/* 文章封面（ReadYou 风格：衬线大标题 + 来源 + 阅读时长） */
.cover {
  padding: var(--go-sp-6) var(--go-sp-6) var(--go-sp-5);
  max-width: 720rpx;
  margin: 0 auto;
  width: 100%;
  box-sizing: border-box;
}
.cover-source {
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-2);
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-semibold);
  letter-spacing: .04em;
  text-transform: uppercase;
  color: var(--go-primary);
  margin-bottom: var(--go-sp-4);
  &::before {
    content: '';
    width: 28rpx;
    height: 4rpx;
    border-radius: var(--go-r-full);
    background: var(--go-accent-bar);
  }
}
.cover-title {
  display: block;
  font-family: var(--go-font-read);
  font-weight: var(--go-fw-bold);
  font-size: var(--go-fs-display);
  line-height: var(--go-lh-tight);
  letter-spacing: -.01em;
  color: var(--go-on-surface);
  margin-bottom: var(--go-sp-3);
}
.cover-meta {
  display: flex;
  align-items: center;
  gap: var(--go-sp-2);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
}

/* 选择模式提示条 */
.sel-hint {
  position: fixed;
  left: 50%;
  transform: translateX(-50%);
  bottom: calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-8));
  max-width: 86%;
  background: color-mix(in srgb, var(--go-on-surface) 88%, transparent);
  color: var(--go-bg);
  font-size: var(--go-fs-meta);
  line-height: var(--go-lh-snug);
  padding: var(--go-sp-3) var(--go-sp-5);
  border-radius: var(--go-r-md);
  z-index: 60;
  text-align: center;
  box-shadow: var(--go-shadow-2);
}

/* 选区浮动操作条 */
.sel-bar {
  position: fixed;
  left: var(--go-sp-4);
  right: var(--go-sp-4);
  bottom: calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-4));
  // 用纯实色深底，避免依赖 color-mix()（部分 5+App webview 不支持该函数会导致规则失效、文字变透明）
  background: #322f2b;
  backdrop-filter: blur(20rpx);
  border-radius: var(--go-r-lg);
  padding: var(--go-sp-3) var(--go-sp-4);
  display: flex;
  align-items: center;
  gap: var(--go-sp-3);
  z-index: 90;
  box-shadow: var(--go-shadow-3);
}
.go-slide-up { animation: go-slide-up var(--go-dur-med) var(--go-ease-emphasized) both; }
.sel-text {
  flex: 1;
  // 实色白字，对深底保证对比度；不再用 --go-bg（米色与深底对比度不足）
  color: #ffffff;
  font-size: var(--go-fs-body-sm);
}
.sel-btn {
  color: #ffffff;
  font-size: var(--go-fs-body-sm);
  padding: var(--go-sp-2) var(--go-sp-5);
  background: rgba(255, 255, 255, 0.18);
  border-radius: var(--go-r-full);
  transition: background var(--go-dur-fast) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { background: rgba(255, 255, 255, 0.28); transform: scale(.95); }
}
.sel-btn.ghost {
  // 取消按钮：用半透明白（rgba 在所有 webview 都受支持），仍是可见文字而非"透明"
  color: rgba(255, 255, 255, 0.75);
}

.tail {
  text-align: center;
  color: var(--go-on-surface-3);
  font-size: var(--go-fs-meta);
  padding: var(--go-sp-12) 0 calc(var(--go-sp-12) + 40rpx);
  letter-spacing: 2rpx;
}

/* 正文图片块：宽度撑满正文区，按原比例高度自适应 */
.article-img {
  margin: var(--go-sp-5) 0;
  border-radius: var(--go-r-md);
  overflow: hidden;
  background: var(--go-surface-2);
  box-shadow: 0 1rpx 6rpx rgba(60, 45, 30, 0.08);
  cursor: pointer;
}
.article-img__el {
  width: 100%;
  display: block;
  /* mode=widthFix 由组件控制高度；这里仅兜底避免 0 高度 */
  min-height: 120rpx;
}
.article-img__cap {
  display: block;
  padding: var(--go-sp-2) var(--go-sp-3) var(--go-sp-3);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  line-height: 1.4;
}
</style>
