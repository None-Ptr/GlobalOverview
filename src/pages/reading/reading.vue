<template>
  <view class="page">
    <!-- M3 TopAppBar -->
    <view class="go-appbar floating">
      <text class="go-appbar__title">GlobalOverview</text>
      <view class="go-appbar__actions">
        <view class="go-icon-btn primary" @click="showAdd = true">
          <GoIcon name="plus" :size="'56rpx'" />
        </view>
      </view>
    </view>

    <!-- 首页 Tab：最新5篇 / 源列表 -->
    <view class="home-tabs">
      <view class="go-segmented">
        <view class="go-segmented__item" :class="{ active: tab === 'latest' }" @click="switchTab('latest')">最新 5 篇</view>
        <view class="go-segmented__item" :class="{ active: tab !== 'latest' }" @click="switchTab(activeFeed || (feeds[0] && feeds[0].id))">源列表</view>
      </view>
    </view>

    <!-- 源切换：FilterChip 横向滚动（仅在源列表 Tab 显示） -->
    <scroll-view v-if="tab !== 'latest'" scroll-x class="feed-scroll">
      <view
        v-for="f in displayFeeds"
        :key="f.id"
        class="go-chip"
        :class="{ active: String(f.id) === String(activeFeed) }"
        @click="selectFeed(f.id)"
        @longpress="removeFeed(f)"
      >{{ f.title }}</view>
    </scroll-view>

    <scroll-view
      scroll-y
      class="list go-stagger"
      refresher-enabled
      refresher-default-style="none"
      refresher-background="transparent"
      :refresher-triggered="loading"
      @refresherrefresh="tab === 'latest' ? refreshAll(true) : refreshActive()"
    >
      <view v-if="error" class="state error">
        <text>{{ error }}</text>
        <text class="retry btn-text" @click="tab === 'latest' ? loadLatest() : refreshActive()">重试</text>
      </view>

      <!-- 骨架屏：加载中占位（按当前 tab 独立判断，避免跨 tab 残留数据掩盖状态） -->
      <view v-if="loading && tab === 'latest' && !displayLatest.length" class="skeletons">
        <view v-for="n in 5" :key="n" class="sk-item">
          <view class="go-skeleton sk-line" style="width: 70%; height: 32rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 100%; height: 24rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 90%; height: 24rpx;"></view>
        </view>
      </view>
      <view v-if="loading && tab !== 'latest' && !items.length" class="skeletons">
        <view v-for="n in 5" :key="n" class="sk-item">
          <view class="go-skeleton sk-line" style="width: 70%; height: 32rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 100%; height: 24rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 90%; height: 24rpx;"></view>
        </view>
      </view>

      <!-- 最新 5 篇 -->
      <view
        v-if="tab === 'latest'"
        v-for="(it, idx) in displayLatest"
        :key="'L:'+it.guid"
        class="card go-article-row go-pressable go-enter go-glass go-glass--overlap"
        :style="{ '--i': idx }"
      >
        <view class="go-article-row__avatar">{{ (it.feedTitle || it.title || '?').charAt(0) }}</view>
        <view class="go-article-row__body" @click="openItem(it)">
          <view class="go-article-row__meta">
            <text class="go-article-row__source">{{ it.feedTitle || '未知源' }}</text>
            <text v-if="relTime(it.pubDate)" class="go-article-row__dot">·</text>
            <text v-if="relTime(it.pubDate)" class="go-article-row__date">{{ relTime(it.pubDate) }}</text>
          </view>
          <text class="go-article-row__title">{{ it.title }}</text>
          <text class="go-article-row__preview">{{ it.preview }}</text>
        </view>
        <view
          class="go-plan-btn"
          :class="{ done: planning[it.guid] }"
          @click.stop="addToPlan(it)"
        >
          <GoIcon :name="planning[it.guid] ? 'star' : 'plus'" :size="'26rpx'" class="go-plan-btn__ico" />
          <text>{{ planning[it.guid] ? '已加入' : '加入计划' }}</text>
        </view>
      </view>

      <!-- 源 feed 列表 -->
      <view
        v-if="tab !== 'latest'"
        v-for="(it, idx) in items"
        :key="'F:'+feedKeyFor(it)+':'+it.guid"
        class="card go-article-row go-pressable go-enter go-glass go-glass--overlap"
        :style="{ '--i': idx }"
      >
        <view class="go-article-row__avatar">{{ (it.feedTitle || it.title || '?').charAt(0) }}</view>
        <view class="go-article-row__body" @click="openItem(it)">
          <view class="go-article-row__meta">
            <text class="go-article-row__source">{{ it.feedTitle || '未知源' }}</text>
            <text v-if="relTime(it.pubDate)" class="go-article-row__dot">·</text>
            <text v-if="relTime(it.pubDate)" class="go-article-row__date">{{ relTime(it.pubDate) }}</text>
          </view>
          <text class="go-article-row__title">{{ it.title }}</text>
          <text class="go-article-row__preview">{{ it.preview }}</text>
        </view>
        <view
          class="go-plan-btn"
          :class="{ done: planning[it.guid] }"
          @click.stop="addToPlan(it)"
        >
          <GoIcon :name="planning[it.guid] ? 'star' : 'plus'" :size="'26rpx'" class="go-plan-btn__ico" />
          <text>{{ planning[it.guid] ? '已加入' : '加入计划' }}</text>
        </view>
      </view>

      <view v-if="!loading && !error && tab === 'latest' && !displayLatest.length" class="state">
        <text>还没有文章</text>
        <text class="btn-primary btn-block fetch-btn" @click="refreshAll(true)">立即拉取</text>
      </view>
      <view v-if="!loading && !error && tab !== 'latest' && !items.length" class="state">
        <text>这个源还没有更新</text>
        <text class="btn-primary btn-block fetch-btn" @click="refreshActive()">立即拉取</text>
      </view>
    </scroll-view>

    <!-- 浮动添加按钮：M3 Extended FAB，所有 tab 均可见 -->
    <view v-if="!showAdd" class="go-fab" @click="showAdd = true">
      <GoIcon name="plus" :size="'48rpx'" />
      <text>添加订阅源</text>
    </view>

    <!-- 添加 RSS 弹层（底部 sheet 动画） -->
    <view v-if="showAdd" class="mask" @click="showAdd = false">
      <view class="add-card" @click.stop>
        <text class="add-title">添加 RSS 源</text>
        <input class="go-field" v-model="newUrl" placeholder="https://example.com/rss" placeholder-class="ph" />
        <view class="add-actions">
          <text class="add-cancel btn-text" @click="showAdd = false">取消</text>
          <text class="add-ok btn-primary btn-block" @click="addFeed">添加</text>
        </view>
      </view>
    </view>
    <!-- 自定义多边形加载弹窗（替换 uni.showLoading） -->
    <view v-if="fetching" class="fetch-mask">
      <view class="fetch-card">
        <PolySpinner />
        <text class="fetch-text">抓取正文…</text>
      </view>
    </view>
  </view>
  <BottomNav />
</template>

<script setup>
import { ref, onMounted, nextTick, computed } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import BottomNav from '@/components/BottomNav.vue'
import PolySpinner from '@/components/PolySpinner.vue'
import { listStagger } from '@/utils/anim.js'
import { db, sqlVal, safeGuid, DB_CONFIG } from '@/utils/db.js'
import { BUILTIN_FEEDS } from '@/utils/feeds.js'
import { fetchFeed } from '@/utils/rss.js'
import { extractArticle } from '@/utils/extract.js'
import { fetchText } from '@/utils/http.js'
import { useAppStore } from '@/stores/app.js'
import GoIcon from '@/components/GoIcon.vue'
import { useTransition } from '@/composables/useTransition'

const store = useAppStore()

const transition = useTransition('tab')
onShow(() => { transition.onEnter(); uni.$emit('nav:active', 'reading') })


const feeds = ref([])
const items = ref([])
const activeFeed = ref(null)
const loading = ref(false)
const error = ref('')
const showAdd = ref(false)
const newUrl = ref('')
const fetching = ref(false)

// 首页 Tab：'latest'（最新5篇聚合）/ 源 feed 列表
const tab = ref('latest')
const latest = ref([])
// 过滤掉无标题的残留/无效记录，避免空卡片；空状态与列表都基于它
const displayLatest = computed(() => latest.value.filter((it) => (it.title || '').trim()))
// 过滤掉 title 为空的源，避免源列表出现空白 chip
const displayFeeds = computed(() => feeds.value.filter((f) => (f.title || '').trim()))
const planning = ref({}) // guid -> true 已加入计划

// 抓取并入库文章正文，返回 article id（已存在则直接返回）
async function captureArticle(it) {
  const exists = await db.select(`SELECT id FROM articles WHERE guid = ${safeGuid(it.guid)} LIMIT 1`)
  if (exists.length) return exists[0].id
  const html = await fetchText(it.link, { timeout: 20000 })
  const { html: bodyHtml, plainText, wordCount, blocks } = extractArticle(html, it.link)
  if (!plainText || plainText.length < DB_CONFIG.ARTICLE_MIN_CHARS) {
    throw new Error('正文过短，可能页面结构不受支持')
  }
  const res = await db.execute(
    'INSERT INTO articles (guid, title, sourceUrl, html, plainText, blocks, wordCount, capturedAt) VALUES ('
    + `${safeGuid(it.guid)}, ${sqlVal(it.title)}, ${sqlVal(it.link)}, ${sqlVal(bodyHtml)}, `
    + `${sqlVal(plainText)}, ${sqlVal(JSON.stringify(blocks))}, ${sqlVal(wordCount)}, ${sqlVal(Date.now())})`
  )
  const rows = await db.select('SELECT last_insert_rowid() AS id')
  return rows[0] ? rows[0].id : null
}

// 通过 guid 反查 articles 表主键 id
async function articleIdByGuid(guid) {
  const rows = await db.select(`SELECT id FROM articles WHERE guid = ${sqlVal(guid)}`)
  return rows && rows[0] ? rows[0].id : null
}

// 加载已加入计划的状态（从 plan_items 反查，保证刷新后状态不丢）
async function loadPlanning() {
  try {
    const rows = await db.select(
      'SELECT a.guid FROM plan_items p JOIN articles a ON a.id = p.articleId'
    )
    const map = {}
    ;(rows || []).forEach((r) => { map[r.guid] = true })
    planning.value = map
  } catch (e) {
    planning.value = {}
  }
}

// 加入/取消计划（列表级）：spec §首页/阅读页 每张卡片都要有入口
// 已加入则取消（从 plan_items 移除），未加入则先抓取正文再入库
async function addToPlan(it) {
  const guid = it.guid
  if (planning.value[guid]) {
    // 取消计划：仅移除计划项，不删正文（正文可能已用于做题）
    const articleId = await articleIdByGuid(guid)
    if (articleId) {
      await db.execute(`DELETE FROM plan_items WHERE articleId = ${sqlVal(articleId)}`)
    }
    planning.value = { ...planning.value, [guid]: false }
    uni.showToast({ title: '已取消计划', icon: 'none' })
    return
  }
  fetching.value = true
  try {
    const articleId = await captureArticle(it)
    await db.execute(`INSERT OR IGNORE INTO plan_items (articleId, addedAt) VALUES (${sqlVal(articleId)}, ${sqlVal(Date.now())})`)
    planning.value = { ...planning.value, [guid]: true }
    uni.showToast({ title: '已加入计划', icon: 'none' })
  } catch (e) {
    uni.showModal({
      title: '加入失败',
      content: e.message || '正文抓取失败，可稍后在正文页加入',
      showCancel: false,
    })
  } finally {
    fetching.value = false
  }
}

// 拉取「最新5篇」：跨源聚合所有 feed_items 按 pubDate 倒序取前 5
async function loadLatest() {
  loading.value = true
  error.value = ''
  // 切到「最新 5 篇」时清空源列表旧数据，避免骨架屏/空状态被跨 tab 残留数据干扰
  items.value = []
  try {
    const rows = await db.select(
      'SELECT f.id AS feedId, f.title AS feedTitle, i.guid, i.title, i.preview, i.pubDate, i.link ' +
      'FROM feed_items i LEFT JOIN feeds f ON f.id = i.feedId ' +
      'ORDER BY i.pubDate DESC LIMIT 5'
    )
    latest.value = (rows || []).map((r) => ({ ...r, planned: !!planning.value[r.guid] }))
  } catch (e) {
    error.value = '加载最新失败：' + (e.message || e.errMsg || '')
  } finally {
    loading.value = false
  }
}

// 切换首页 Tab
async function switchTab(t) {
  tab.value = t
  if (t === 'latest') return await loadLatest()
  if (!displayFeeds.value.length) return
  if (activeFeed.value == null) activeFeed.value = displayFeeds.value[0].id
  const feed = displayFeeds.value.find((f) => String(f.id) === String(activeFeed.value))
  if (feed) await loadItems(feed, false)
}

async function ensureFeeds() {
  // 批量插入所有内置源（单条多 VALUES），避免启动时 28 次串行 DB 写
  const rows = [], params = [], now = Date.now()
  for (const f of BUILTIN_FEEDS) { rows.push('(?, ?, ?, ?)'); params.push(f.title, f.url, f.category, now) }
  if (rows.length) {
    await db.execute(`INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES ${rows.join(',')}`, params)
  }
  // 清理因历史 bug 产生的空标题/空 url 脏数据，避免渲染成空白 chip
  await db.execute("DELETE FROM feeds WHERE title IS NULL OR title = '' OR url IS NULL OR url = ''")
  feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
  if (displayFeeds.value.length) activeFeed.value = displayFeeds.value[0].id
}

async function selectFeed(id) {
  // 切换源：先终止上一次未完成的加载，避免旧 fetchFeed 完成后用旧 list 写回 items.value
  loading.value = true
  activeFeed.value = id
  const feed = displayFeeds.value.find((f) => String(f.id) === String(id))
  if (feed) await loadItems(feed, false)
  else loading.value = false
}


// 刷新当前激活的源（源列表 Tab 的「立即拉取」与下拉刷新）
async function refreshActive() {
  if (activeFeed.value == null && displayFeeds.value.length) activeFeed.value = displayFeeds.value[0].id
  const feed = displayFeeds.value.find((f) => String(f.id) === String(activeFeed.value))
  if (!feed) return
  loading.value = true
  error.value = ''
  try {
    await fetchFeedInto(feed, true)
    await loadItems(feed, false)
  } catch (e) {
    error.value = '刷新失败：' + (e.message || e.errMsg || '')
  } finally {
    loading.value = false
  }
}

async function loadItems(feed, replaceCache) {
  loading.value = true
  error.value = ''
  // 先把当前 items 清空，避免上一次源的旧数据视觉残留
  items.value = []
  // 记录本次的目标 feed.url，async 结束前若 feed 被切换则放弃写入
  const urlAtStart = feed.url
  try {
    const { items: list } = await fetchFeed(feed.url)
    // 写入前再确认当前 source 没被切走（用 displayFeeds 避免命中空标题脏数据）
    const feedNow = displayFeeds.value.find((f) => String(f.id) === String(activeFeed.value))
    if (!feedNow || feedNow.url !== urlAtStart) return
    items.value = (list || []).filter((it) => (it.title || '').trim()).map((it) => ({ ...it, feedTitle: feedNow.title }))
    nextTick(() => {
      // 兜底：document 在某些非标准 webview 配置下可能是 undefined；
      // 同时 querySelectorAll 返回值用 || [] 保防后续 length 访问抛错
      const els = (typeof document !== 'undefined' && document.querySelectorAll)
        ? document.querySelectorAll('.list .go-article-row') || []
        : []
      if (els.length) listStagger(els)
    })
    // 复用刚抓到的 list 直接入库（避免重复网络请求）
    await persistItems(feedNow, list || [], replaceCache)
  } catch (e) {
    if (activeFeed.value === feed.id) {
      error.value = '抓取失败：' + (e.message || e.errMsg || '网络错误')
    }
  } finally {
    if (activeFeed.value === feed.id) loading.value = false
  }
}

// 给列表 key 加 feed 维度（不同源的 guid 可能冲突，避免跨源 diff 错位）
function feedKeyFor(it) { return activeFeed.value || 0 }

// 把已经抓到的 list 直接写入 feed_items（不切换 tab / activeFeed，不再二次 fetchFeed）
async function persistItems(feed, list, replaceCache) {
  if (!list || !list.length) return
  // 过滤无标题项，避免数据库和列表出现空卡片
  list = list.filter((it) => (it.title || '').trim())
  if (!list.length) return
  const guids = list.map((it) => it.guid)
  if (replaceCache && guids.length) {
    const delPh = guids.map(() => '?').join(',')
    await db.execute(`DELETE FROM feed_items WHERE feedId = ? AND guid IN (${delPh})`, [feed.id, ...guids])
  }
  // 一次性取出本批已存在的 guid，避免逐条 SELECT
  const placeholders = guids.map(() => '?').join(',')
  const existed = await db.select(`SELECT guid FROM feed_items WHERE guid IN (${placeholders})`, guids)
  const existedSet = new Set(existed.map((r) => r.guid))
  // 组装批量 INSERT（只插不存在的）
  const rows = [], params = []
  for (const it of list) {
    if (existedSet.has(it.guid)) continue
    rows.push('(?, ?, ?, ?, ?, ?, ?)')
    params.push(feed.id, it.guid, it.title || '', it.link || '', it.preview || '', it.pubDate || 0, Date.now())
  }
  if (rows.length) {
    await db.execute(`INSERT OR IGNORE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES ${rows.join(',')}`, params)
  }
}

// 旧 fetchFeedInto 改名 / 删除（前向兼容）
async function fetchFeedInto(feed, replaceCache) {
  // 当前实现已并入 persistItems；保留签名以避免外部引用报错
  try {
    const { items: list } = await fetchFeed(feed.url)
    return await persistItems(feed, list, replaceCache)
  } catch (e) { /* 静默（UI 层已经处理过错误） */ }
}

// 抓取全部源（用于首次自动拉取 / 全部刷新）
async function refreshAll(replaceCache = true) {
  // 清空数据后 feeds 也可能被清空，先确保内置源已就绪再拉取，避免直接 return 拉不到
  if (!displayFeeds.value.length) {
    await ensureFeeds()
    await loadPlanning()
  }
  if (!displayFeeds.value.length) return
  loading.value = true
  error.value = ''
  // 并发拉取，单个源失败不影响其余（用 allSettled 隔离异常）
  const results = await Promise.allSettled(displayFeeds.value.map((f) => fetchFeedInto(f, replaceCache)))
  const ok = results.filter((r) => r.status === 'fulfilled').length
  if (!ok) error.value = '自动抓取失败，请检查网络后下拉重试'
  loading.value = false
  await loadLatest()
}

async function addFeed() {
  const url = newUrl.value.trim()
  if (!url) return
  if (!/^https?:\/\//i.test(url)) {
    uni.showToast({ title: '请填写 http(s) 地址', icon: 'none' })
    return
  }
  await db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES ('
    + `${sqlVal(url)}, ${sqlVal(url)}, 'Custom', ${sqlVal(Date.now())})`)
  feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
  showAdd.value = false
  newUrl.value = ''
  uni.showToast({ title: '已添加', icon: 'none' })
}

async function removeFeed(f) {
  if (f.category !== 'Custom') {
    uni.showToast({ title: '内置源不可删', icon: 'none' })
    return
  }
  uni.showModal({
    title: '删除源',
    content: f.title,
    success: async (r) => {
      if (!r.confirm) return
      await db.execute(`DELETE FROM feeds WHERE id = ${sqlVal(f.id)}`)
      feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
      if (String(activeFeed.value) === String(f.id) && displayFeeds.value.length) await selectFeed(displayFeeds.value[0].id)
    },
  })
}

async function openItem(it) {
  fetching.value = true
  try {
    await captureArticle(it)
    fetching.value = false
    uni.navigateTo({
      url: `/pages/article/article?guid=${encodeURIComponent(it.guid)}&title=${encodeURIComponent(it.title)}`,
    })
  } catch (e) {
    fetching.value = false
    const tooShort = /正文过短/.test(e.message || '')
    if (tooShort) {
      uni.showModal({
        title: '正文抽取失败',
        content: '正文过短，可能页面结构不受支持。',
        confirmText: '浏览器打开',
        cancelText: '重试',
        success: (r) => {
          if (r.confirm) {
            if (typeof plus !== 'undefined' && plus.runtime) plus.runtime.openURL(it.link)
          } else {
            openItem(it)
          }
        },
      })
      return
    }
    uni.showModal({
      title: '抓取失败',
      content: e.message || '网络错误，可能受跨域限制',
      showCancel: false,
    })
  }
}

onMounted(async () => {
  await db.init()
  await ensureFeeds()
  // 首次进入：若 feed_items 中没有有效文章，自动抓取所有源，避免空白提示
  const cached = await db.select(
    "SELECT COUNT(*) AS c FROM feed_items WHERE title IS NOT NULL AND title <> ''"
  )
  const hasCache = cached.length && cached[0].c > 0
  if (!hasCache) {
    await refreshAll(true)
  } else {
    await loadLatest()
  }
  await loadPlanning()
})

// 相对时间格式化（ReadYou 风格：刚刚 / x 分钟前 / x 小时前 / x 天前 / 日期）
function relTime(ts) {
  if (!ts) return ''
  const diff = Date.now() - ts
  const m = 60000, h = 3600000, d = 86400000
  if (diff < m) return '刚刚'
  if (diff < h) return Math.floor(diff / m) + ' 分钟前'
  if (diff < d) return Math.floor(diff / h) + ' 小时前'
  if (diff < 7 * d) return Math.floor(diff / d) + ' 天前'
  const dt = new Date(ts)
  return `${dt.getMonth() + 1}月${dt.getDate()}日`
}
</script>

<style scoped lang="scss">
.page {
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  min-height: 100vh;
  padding-top: var(--go-safe-top);
  background: var(--go-bg);
}
.feed-scroll {
  white-space: nowrap;
  padding: var(--go-sp-3) var(--go-sp-4);
}
.list { flex: 1; padding: var(--go-sp-2) var(--go-sp-4) calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-12) + 96rpx); }

/* 文章行：accent bar + avatar + 内容 + 加入计划 */
.go-article-row {
  position: relative;
  display: flex;
  align-items: stretch;
  gap: var(--go-sp-3);
  padding-left: var(--go-sp-2);
  &::before {
    content: '';
    position: absolute;
    left: 0;
    top: 8rpx;
    bottom: 8rpx;
    width: 6rpx;
    border-radius: var(--go-r-full);
    background: var(--go-accent-bar);
    opacity: 0.85;
  }
}
.go-article-row__avatar {
  flex: none;
  align-self: flex-start;
  width: 76rpx;
  height: 76rpx;
  margin-top: var(--go-sp-1);
  border-radius: var(--go-r-md);
  background: var(--go-primary);
  color: var(--go-on-primary-variant);
  font-size: 32rpx;
  font-weight: var(--go-fw-bold);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--go-shadow-1);
}
.go-article-row__body { flex: 1; min-width: 0; }
.go-article-row__meta {
  display: flex;
  align-items: center;
  gap: var(--go-sp-2);
  margin-bottom: var(--go-sp-2);
}
.go-article-row__dot { color: var(--go-on-surface-disabled); }
.go-article-row__date { color: var(--go-on-surface-3); }
.go-plan-btn {
  align-self: center;
  flex-shrink: 0;
  margin-left: var(--go-sp-2);
  padding: var(--go-sp-2) var(--go-sp-4);
  font-size: var(--go-fs-meta);
  border-radius: var(--go-r-full);
  background: var(--go-primary);
  color: var(--go-on-primary);
  font-weight: var(--go-fw-semibold);
  transition: opacity var(--go-dur-fast) var(--go-ease-standard), background var(--go-dur-fast) var(--go-ease-standard), color var(--go-dur-fast) var(--go-ease-standard);
  display: inline-flex; align-items: center; gap: var(--go-sp-1);
  &:active { opacity: 0.8; }
  &.done {
    background: color-mix(in srgb, var(--go-primary) 14%, var(--go-surface));
    color: var(--go-primary);
    border: 1rpx solid color-mix(in srgb, var(--go-primary) 28%, transparent);
  }
  &__ico { flex: none; transition: transform var(--go-dur-fast) var(--go-ease-standard); }
  &.done &__ico { transform: scale(1.1); }
}

/* 空 / 错状态 */
.state {
  text-align: center;
  color: var(--go-on-surface-3);
  padding: var(--go-sp-16) var(--go-sp-6);
  line-height: 1.6;
  background: var(--go-surface); border-radius: var(--go-r-lg); box-shadow: var(--go-elev-1);
  margin: var(--go-sp-6);
}
/* 空状态内的「立即拉取」按钮 */
.fetch-btn {
  display: inline-block;
  margin-top: var(--go-sp-12);
  padding: var(--go-sp-8) var(--go-sp-20);
}
.state.error {
  color: var(--go-danger);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--go-sp-3);
}
.retry { color: var(--go-primary); font-weight: var(--go-fw-semibold); }

/* 骨架屏 */
.skeletons { padding-top: var(--go-sp-2); }
.sk-item {
  padding: var(--go-sp-5) var(--go-sp-5);
  border-radius: var(--go-r-lg);
  background: var(--go-surface);
  margin-bottom: var(--go-sp-4);
  display: flex;
  flex-direction: column;
  gap: var(--go-sp-3);
  box-shadow: var(--go-shadow-1);
  border: 1rpx solid var(--go-outline);
}
.sk-line { height: 24rpx; }

/* 添加源底部弹层 */
.mask {
  position: fixed;
  inset: 0;
  background: var(--go-scrim);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 100;
  animation: go-fade-in var(--go-dur-med) var(--go-ease-standard) both;
}
.add-card {
  width: 100%;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  padding: var(--go-sp-6) var(--go-sp-6) calc(var(--go-sp-8) + var(--go-safe-bottom));
  box-shadow: var(--go-shadow-3);
  animation: go-sheet-up var(--go-dur-med) var(--go-ease-emphasized) both;
}
.add-title {
  font-size: var(--go-fs-h1);
  font-weight: var(--go-fw-semibold);
  text-align: center;
  display: block;
  margin-bottom: var(--go-sp-6);
  color: var(--go-on-surface);
}
/* RSS 输入框：暖米灰凹陷背景，与弹层米白表面拉开层次 */
.add-card .go-field {
  background: var(--go-surface-2);
  border: 2rpx solid var(--go-outline-strong);
  box-shadow: inset 0 2rpx 6rpx rgba(60, 40, 24, 0.08);
}
.add-actions {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-top: var(--go-sp-6);
  border-top: 1rpx solid var(--go-outline);
  padding-top: var(--go-sp-5);
  gap: var(--go-sp-4);
}
.add-cancel { color: var(--go-on-surface-3); font-weight: var(--go-fw-medium); }
.add-ok { color: var(--go-primary); font-weight: var(--go-fw-semibold); }

/* 抓取加载弹窗 */
.fetch-mask {
  position: fixed;
  inset: 0;
  background: var(--go-scrim);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  animation: go-fade-in 0.2s ease both;
}
.fetch-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--go-sp-4);
  padding: var(--go-sp-8) var(--go-sp-10);
  border-radius: var(--go-r-lg);
  background: var(--go-surface-raised);
  box-shadow: var(--go-shadow-3);
}
.fetch-text {
  font-size: var(--go-fs-body-sm);
  color: var(--go-on-surface-2);
  font-weight: var(--go-fw-medium);
}

@keyframes go-fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}
@keyframes go-sheet-up {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}
</style>

