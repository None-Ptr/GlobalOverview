<template>
  <view class="page">
    <!-- 顶栏：标题随分类变化 + 刷新 -->
    <view class="go-appbar floating">
      <text class="go-appbar__title">{{ pageTitle }}</text>
      <view class="go-appbar__actions">
        <view class="go-icon-btn primary" @click="onRefreshTap">
          <GoIcon name="refresh" :size="'56rpx'" :spin="refreshSpinning" />
        </view>
      </view>
    </view>

    <!-- 分类导航：横向滚动，按分类选择 RSS 源 -->
    <scroll-view scroll-x class="cat-rail go-stagger">
      <view
        v-for="c in catTabs"
        :key="c.key"
        class="cat-chip go-glass"
        :class="{ active: activeCat === c.key }"
        @click="switchCat(c.key)"
      >
        <text class="cat-chip__label">{{ c.label }}</text>
        <text class="cat-chip__count">{{ c.count }}</text>
      </view>
    </scroll-view>

    <!-- 源切换：当前分类下的订阅源 chip（全部 / 单源） -->
    <scroll-view v-if="feedsInCat.length" scroll-x class="feed-rail">
      <view
        class="feed-chip"
        :class="{ active: !activeFeed }"
        @click="activeFeed = null"
      >全部</view>
      <view
        v-for="f in feedsInCat"
        :key="f.url"
        class="feed-chip"
        :class="{ active: activeFeed === f.url }"
        @click="toggleFeed(f)"
      >{{ f.title }}</view>
    </scroll-view>

    <scroll-view
      scroll-y
      class="list go-stagger"
      refresher-enabled
      refresher-default-style="none"
      refresher-background="transparent"
      :refresher-triggered="loading"
      @refresherrefresh="refreshAll(true)"
      @scrolltolower="loadMore"
    >
      <view v-if="error" class="state error">
        <text>{{ error }}</text>
        <text class="retry btn-text" @click="refreshAll(true)">重试</text>
      </view>

      <!-- 骨架屏 -->
      <view v-if="loading && !displayItems.length" class="skeletons">
        <view v-for="n in 5" :key="n" class="sk-item">
          <view class="go-skeleton sk-line" style="width: 70%; height: 32rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 100%; height: 24rpx;"></view>
          <view class="go-skeleton sk-line" style="width: 90%; height: 24rpx;"></view>
        </view>
      </view>

      <!-- 文章列表：按分类 / 源过滤后的聚合 -->
      <view
        v-for="(it, idx) in displayItems"
        :key="it.guid"
        class="card go-article-row go-pressable go-glass go-glass--overlap"
      >
        <view class="go-article-row__avatar">{{ (it.sourceTitle || it.title || '?').charAt(0) }}</view>
        <view class="go-article-row__body" @click="openItem(it)">
          <view class="go-article-row__meta">
            <text class="go-article-row__source">{{ it.sourceTitle || '未知源' }}</text>
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

      <view v-if="hasMore && displayItems.length" class="more" @click="loadMore">加载更多</view>

      <view v-if="!loading && !error && !displayItems.length" class="state">
        <text>{{ feeds.length ? '这个分类下还没有文章' : '还没有订阅任何源' }}</text>

        <view class="go-btn fetch-btn" @click="feeds.length ? refreshAll(true) : (showCatalog = true)">
          {{ feeds.length ? '立即拉取' : '去选择订阅源' }}
        </view>
      </view>
    </scroll-view>

    <!-- 浮动按钮：打开「按分类选择订阅源」面板 -->
    <view v-if="!showCatalog" class="go-fab" @click="showCatalog = true">
      <GoIcon name="plus" :size="'48rpx'" />
      <text>订阅源</text>
    </view>

    <!-- 订阅源浏览面板：按分类选择 RSS 源 -->
    <view v-if="showCatalog" class="sheet-mask" @click="showCatalog = false">
      <view class="sheet" @click.stop>
        <view class="sheet__head">
          <text class="sheet__title">选择订阅源</text>
          <view class="sheet__close" @click="showCatalog = false">
            <GoIcon name="stop" :size="'48rpx'" />
          </view>
        </view>
        <scroll-view scroll-x class="sheet__cats">
          <view
            v-for="c in CATEGORIES"
            :key="c.key"
            class="sheet__cat"
            :class="{ active: catalogCat === c.key }"
            @click="catalogCat = c.key"
          >
            {{ c.label }}<text class="sheet__cat-n">{{ catCount(c.key) }}</text>
          </view>
        </scroll-view>
        <!-- 自定义订阅：手动添加任意 RSS 源 -->
        <view class="sheet__custom">
          <view class="sheet__custom-label">自定义订阅源</view>
          <view class="sheet__custom-row">
            <input
              class="sheet__custom-input"
              v-model="customUrl"
              placeholder="粘贴 RSS 地址（https://…）"
              placeholder-class="sheet__custom-ph"
              confirm-type="done"
              @confirm="addCustomFeed"
            />
            <view class="go-btn sheet__custom-btn" @click="addCustomFeed">添加</view>
          </view>
        </view>
        <scroll-view scroll-y class="sheet__list">
          <view v-for="f in feedsByCat(catalogCat)" :key="f.url" class="pick">
            <view class="pick__main">
              <text class="pick__title">{{ f.title }}</text>
              <text class="pick__url">{{ f.url }}</text>
            </view>
            <view
              class="pick__btn"
              :class="{ on: isSub(f.url) }"
              @click="isSub(f.url) ? unsubscribe(f) : subscribe(f)"
            >{{ isSub(f.url) ? '已订阅' : '订阅' }}</view>
          </view>
          <view v-if="!feedsByCat(catalogCat).length" class="sheet__empty">该分类暂无源</view>
        </scroll-view>
      </view>
    </view>

    <!-- 抓取正文加载弹窗 -->
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
import { ref, computed, onMounted } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import BottomNav from '@/components/BottomNav.vue'
import PolySpinner from '@/components/PolySpinner.vue'
import { db, sqlVal, safeGuid, DB_CONFIG } from '@/utils/db.js'
import { DEFAULT_FEEDS, FEEDS, CATEGORIES } from '@/utils/feeds.js'
import { fetchFeed } from '@/utils/rss.js'
import { extractArticle } from '@/utils/extract.js'
import { fetchText } from '@/utils/http.js'
import GoIcon from '@/components/GoIcon.vue'
import { useTransition } from '@/composables/useTransition'

const transition = useTransition('tab')
onShow(() => { transition.onEnter(); uni.$emit('nav:active', 'reading') })

const feeds = ref([])            // 已订阅源（含 category）
const allItems = ref([])         // 已抓取的 feed_items（按 pubDate 倒序，受 cap 限制）
const activeCat = ref('all')     // 当前分类：'all' 或 CATEGORIES.key
const activeFeed = ref(null)     // 当前单源过滤：feed.url 或 null
const loading = ref(false)
const error = ref('')
const refreshSpinning = ref(false)
const fetching = ref(false)
const showCatalog = ref(false)
const catalogCat = ref('Learner')
const customUrl = ref('')
const planning = ref({})         // guid -> true 已加入计划
const cap = ref(80)
const hasMore = ref(false)
// 连续失败 N 次后自动取消订阅
const FAIL_THRESHOLD = 3
// 并发抓取上限：避免大量源同时请求打满连接数导致批量失败
const CONCURRENCY = 4

// 分类标签
function catLabel(key) {
  const hit = CATEGORIES.find((c) => c.key === key)
  return hit ? hit.label : key
}
const pageTitle = computed(() => (activeCat.value === 'all' ? '阅读' : catLabel(activeCat.value)))

// 顶部分类导航：全部 + 已订阅源实际存在的分类（按 CATEGORIES 顺序）
const catTabs = computed(() => {
  const map = new Map()
  map.set('all', { key: 'all', label: '全部', count: feeds.value.length })
  for (const f of feeds.value) {
    if (!f.category) continue
    if (!map.has(f.category)) map.set(f.category, { key: f.category, label: catLabel(f.category), count: 0 })
    map.get(f.category).count++
  }
  const arr = [map.get('all')]
  for (const c of CATEGORIES) if (map.has(c.key)) arr.push(map.get(c.key))
  return arr
})

// 当前分类下可见的源
const feedsInCat = computed(() =>
  activeCat.value === 'all' ? feeds.value : feeds.value.filter((f) => f.category === activeCat.value)
)

// 文章列表：已加载内容按 分类 + 单源 过滤
const displayItems = computed(() => {
  let list = allItems.value
  if (activeCat.value !== 'all') list = list.filter((it) => it.sourceCat === activeCat.value)
  if (activeFeed.value) list = list.filter((it) => it.sourceUrl === activeFeed.value)
  return list
})

// 订阅面板数据
const feedsByCat = (key) => FEEDS.filter((f) => f.category === key)
const catCount = (key) => FEEDS.filter((f) => f.category === key).length
const isSub = (url) => feeds.value.some((f) => f.url === url)

function dedupe(list) {
  const seen = new Set()
  const out = []
  for (const it of list) {
    if (seen.has(it.guid)) continue
    seen.add(it.guid)
    out.push(it)
  }
  return out
}

// 抓取并入库文章正文，返回 article id（已存在则直接返回）
async function captureArticle(it) {
  // select 在异常路径下可能返回 undefined，直接取 .length 会 TypeError
  const exists = (await db.select(`SELECT id FROM articles WHERE guid = ${safeGuid(it.guid)} LIMIT 1`)) || []
  if (exists.length && exists[0]) return exists[0].id
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

async function articleIdByGuid(guid) {
  const rows = await db.select(`SELECT id FROM articles WHERE guid = ${sqlVal(guid)}`)
  return rows && rows[0] ? rows[0].id : null
}

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

async function addToPlan(it) {
  const guid = it.guid
  if (planning.value[guid]) {
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

// 首次启动：批量写入 DEFAULT_FEEDS（若 feeds 表为空），并清理历史脏数据
async function ensureFeeds() {
  const rows = await db.select('SELECT COUNT(*) AS c FROM feeds')
  const empty = !rows.length || !rows[0].c
  if (empty) {
    const params = []
    const placeholders = DEFAULT_FEEDS.map((f) => {
      params.push(f.title, f.url, f.category, Date.now())
      return '(?, ?, ?, ?)'
    }).join(',')
    if (placeholders) {
      await db.execute(`INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES ${placeholders}`, params)
    }
  }
  await db.execute("DELETE FROM feeds WHERE title IS NULL OR title = '' OR url IS NULL OR url = ''")
  feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
}

// 加载已抓取的 feed_items（聚合全部订阅源，按 pubDate 倒序，受 cap 限制）
async function loadAll(reset = true) {
  if (reset) cap.value = 80
  loading.value = true
  error.value = ''
  try {
    const rows = await db.select(
      `SELECT i.id, i.feedId, i.guid, i.title, i.link, i.preview, i.pubDate, i.fetchedAt,
              f.title AS sourceTitle, f.url AS sourceUrl, f.category AS sourceCat
       FROM feed_items i LEFT JOIN feeds f ON f.id = i.feedId
       ORDER BY i.pubDate DESC LIMIT ? OFFSET ?`,
      [cap.value, reset ? 0 : allItems.value.length]
    )
    const mapped = (rows || []).map((r) => ({
      id: r.id,
      feedId: r.feedId,
      guid: r.guid,
      title: r.title || '(无标题)',
      link: r.link,
      preview: r.preview || '',
      pubDate: r.pubDate || 0,
      sourceTitle: r.sourceTitle || '未知源',
      sourceUrl: r.sourceUrl || '',
      sourceCat: r.sourceCat || '',
    })).filter((it) => (it.title || '').trim())
    allItems.value = reset ? dedupe(mapped) : dedupe(allItems.value.concat(mapped))
    hasMore.value = mapped.length >= cap.value
  } catch (e) {
    error.value = '加载失败：' + (e.message || e.errMsg || '')
  } finally {
    loading.value = false
  }
}

function loadMore() {
  if (loading.value || !hasMore.value) return
  cap.value += 40
  loadAll(false)
}

// 抓取并入库单个源（从 rss.js 拉取后写 feed_items，避免重复网络请求）
// 返回 { ok, error, count, name }。成功时重置 failCount，失败时 failCount+1。
async function fetchFeedInto(feed, replaceCache) {
  try {
    const { items: raw } = await fetchFeed(feed.url)
    if (!raw || !raw.length) { await resetFail(feed); return { ok: true, error: '', count: 0, name: feed.title } }
    const list = raw.filter((it) => (it.title || '').trim())
    if (!list.length) { await resetFail(feed); return { ok: true, error: '', count: 0, name: feed.title } }
    const guids = list.map((it) => it.guid)
    if (replaceCache && guids.length) {
      const delPh = guids.map(() => '?').join(',')
      await db.execute(`DELETE FROM feed_items WHERE feedId = ? AND guid IN (${delPh})`, [feed.id, ...guids])
    }
    const placeholders = guids.map(() => '?').join(',')
    const existed = await db.select(`SELECT guid FROM feed_items WHERE feedId = ? AND guid IN (${placeholders})`, [feed.id, ...guids])
    const existedSet = new Set(existed.map((r) => r.guid))
    const rows = [], params = []
    for (const it of list) {
      if (existedSet.has(it.guid)) continue
      rows.push('(?, ?, ?, ?, ?, ?, ?)')
      params.push(feed.id, it.guid, it.title || '', it.link || '', it.preview || '', it.pubDate || 0, Date.now())
    }
    if (rows.length) {
      await db.execute(`INSERT OR IGNORE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES ${rows.join(',')}`, params)
    }
    await resetFail(feed)
    return { ok: true, error: '', count: rows.length, name: feed.title }
  } catch (e) {
    const newCount = await bumpFail(feed)
    return { ok: false, error: (e && (e.message || e.errMsg)) || '未知错误', count: 0, name: feed.title, failCount: newCount }
  }
}

// 抓取成功：把该源的连续失败计数清零
async function resetFail(feed) {
  try {
    if (feed.id == null) return
    await db.execute('UPDATE feeds SET failCount = 0 WHERE id = ?', [feed.id])
  } catch (e) { /* 非关键，静默 */ }
}
// 抓取失败：连续失败计数 +1，返回新计数
async function bumpFail(feed) {
  try {
    if (feed.id == null) return 0
    const rows = await db.select('SELECT failCount FROM feeds WHERE id = ?', [feed.id])
    const cur = (rows && rows[0] && rows[0].failCount) || 0
    const next = cur + 1
    await db.execute('UPDATE feeds SET failCount = ? WHERE id = ?', [next, feed.id])
    return next
  } catch (e) { return 0 }
}

// 带并发上限的批量执行：避免大量源同时请求打满连接数导致批量失败
async function mapConcurrent(list, limit, fn) {
  const results = new Array(list.length)
  let i = 0
  const workers = Array.from({ length: Math.min(limit, list.length) }, async () => {
    while (i < list.length) {
      const idx = i++
      results[idx] = await fn(list[idx], idx)
    }
  })
  await Promise.all(workers)
  return results
}

async function refreshAll(replaceCache = true) {
  if (!feeds.value.length) await ensureFeeds()
  if (!feeds.value.length) return
  loading.value = true
  error.value = ''
  const results = await mapConcurrent(feeds.value, CONCURRENCY, (f) => fetchFeedInto(f, replaceCache))
  // 连续失败达阈值 → 自动取消订阅
  const autoRemoved = []
  for (let k = results.length - 1; k >= 0; k--) {
    const r = results[k]
    if (r && !r.ok && r.failCount >= FAIL_THRESHOLD) {
      const feed = feeds.value[k]
      await unsubscribe(feed)
      autoRemoved.push(feed.title)
    }
  }
  if (autoRemoved.length) {
    uni.showToast({ title: `已自动取消 ${autoRemoved.length} 个失效源`, icon: 'none' })
  }
  loading.value = false
  await loadAll(true)
}

async function onRefreshTap() {
  if (loading.value) return
  refreshSpinning.value = true
  try {
    await refreshAll(true)
  } finally {
    setTimeout(() => { refreshSpinning.value = false }, 600)
  }
}

// 分类切换：重置单源过滤
function switchCat(key) {
  activeCat.value = key
  activeFeed.value = null
}
// 单源过滤：再次点击同一个源则取消（回到该分类全部）
function toggleFeed(f) {
  activeFeed.value = activeFeed.value === f.url ? null : f.url
}

// 订阅面板：订阅 / 取消订阅
async function subscribe(f) {
  if (isSub(f.url)) return
  await db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (?, ?, ?, ?)', [f.title, f.url, f.category, Date.now()])
  feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
  uni.showToast({ title: '已订阅', icon: 'none' })
  const row = feeds.value.find((x) => x.url === f.url)
  if (row) {
    const res = await fetchFeedInto(row, true)
    if (res && !res.ok) {
      // 首次订阅失败不弹窗打扰，仅 toast（会自动计数，达阈值自动取消）
      uni.showToast({ title: '暂时拉取失败，可稍后重试', icon: 'none' })
    }
    await loadAll(true)
  }
}
async function unsubscribe(f) {
  if (activeFeed.value === f.url) activeFeed.value = null
  const rows = await db.select('SELECT id FROM feeds WHERE url = ?', [f.url])
  const fid = rows && rows[0] ? rows[0].id : null
  if (fid != null) await db.execute('DELETE FROM feed_items WHERE feedId = ?', [fid])
  await db.execute('DELETE FROM feeds WHERE url = ?', [f.url])
  feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
  await loadAll(true)
}

// 自定义订阅源：粘贴 URL → 探测标题 → 入库到「自定义」分类 → 抓取
async function addCustomFeed() {
  const url = (customUrl.value || '').trim().replace(/&amp;/gi, '&')
  if (!url) {
    uni.showToast({ title: '请输入 RSS 地址', icon: 'none' })
    return
  }
  if (!/^https?:\/\/.+/.test(url)) {
    uni.showToast({ title: '地址需以 http(s):// 开头', icon: 'none' })
    return
  }
  if (isSub(url)) {
    uni.showToast({ title: '该源已订阅', icon: 'none' })
    return
  }
  let title = url
  let category = 'Life'
  try {
    const info = await fetchFeed(url)
    if (info && info.title) title = info.title
  } catch (e) { /* 标题探测失败则用 URL 兜底，仍允许订阅 */ }
  try {
    await db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (?, ?, ?, ?)', [title, url, category, Date.now()])
    feeds.value = await db.select('SELECT * FROM feeds ORDER BY id')
    customUrl.value = ''
    uni.showToast({ title: '已添加自定义源', icon: 'none' })
    const row = feeds.value.find((x) => x.url === url)
    if (row) {
      const res = await fetchFeedInto(row, true)
      if (res && !res.ok) uni.showToast({ title: '暂时拉取失败，可稍后重试', icon: 'none' })
      await loadAll(true)
    }
  } catch (e) {
    uni.showToast({ title: '添加失败', icon: 'none' })
  }
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
            if (plus.runtime) plus.runtime.openURL(it.link)
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
  // 必须兜底：db.init() 可能抛「数据库打开超时」。此前无 try/catch，
  // 抛错后 loading 永远不落、页面永久空白，而阅读页还是首屏页 → 整个 App 不可用。
  try {
    await db.init()
    await ensureFeeds()
    const cached = (await db.select(
      "SELECT COUNT(*) AS c FROM feed_items WHERE title IS NOT NULL AND title <> ''"
    )) || []
    const hasCache = cached.length && cached[0].c > 0
    if (!hasCache) {
      await refreshAll(true)
    } else {
      await loadAll(true)
    }
    await loadPlanning()
  } catch (e) {
    loading.value = false
    const msg = (e && e.message) || '初始化失败'
    console.error('[reading] onMounted error:', e)
    uni.showToast({ title: msg, icon: 'none' })
  }
})

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

/* 分类导航：横向滚动 chip 条 */
.cat-rail {
  white-space: nowrap;
  padding: var(--go-sp-3) var(--go-sp-4);
}
.cat-chip {
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-2);
  padding: var(--go-sp-2) var(--go-sp-4);
  margin-right: var(--go-sp-2);
  font-size: var(--go-fs-body-sm);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-surface-2);
  border-radius: var(--go-r-full);
  box-shadow: var(--go-shadow-1);
  transition: color var(--go-dur-fast) var(--go-ease-standard), background var(--go-dur-fast) var(--go-ease-standard), transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(0.96); }
  &.active {
    color: var(--go-on-primary);
    background: var(--go-primary);
    box-shadow: var(--go-shadow-2);
  }
  &__count {
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-bold);
    color: var(--go-on-surface-disabled);
  }
  &.active &__count { color: color-mix(in srgb, var(--go-on-primary) 70%, transparent); }
}

/* 源切换 chip 条 */
.feed-rail {
  white-space: nowrap;
  padding: 0 var(--go-sp-4) var(--go-sp-2);
}
.feed-chip {
  display: inline-block;
  padding: var(--go-sp-1) var(--go-sp-4);
  margin-right: var(--go-sp-2);
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-medium);
  color: var(--go-on-surface-3);
  background: var(--go-surface-2);
  border-radius: var(--go-r-full);
  transition: color var(--go-dur-fast) var(--go-ease-standard), background var(--go-dur-fast) var(--go-ease-standard);
  &:active { opacity: 0.8; }
  &.active {
    color: var(--go-primary);
    background: color-mix(in srgb, var(--go-primary) 14%, var(--go-surface));
    border: 1rpx solid color-mix(in srgb, var(--go-primary) 30%, transparent);
  }
}

.list {
  flex: 1;
  padding: var(--go-sp-2) var(--go-sp-4) calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-12) + 96rpx);
}

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

/* 真实按压反馈（替代原 go-pressable 死类） */
.go-pressable { transition: transform var(--go-dur-fast) var(--go-ease-standard); }
.go-pressable:active { transform: scale(0.985); }

/* 加载更多 */
.more {
  text-align: center;
  color: var(--go-primary);
  font-size: var(--go-fs-body-sm);
  font-weight: var(--go-fw-semibold);
  padding: var(--go-sp-5) 0;
  &:active { opacity: 0.7; }
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
.fetch-btn {
  margin: var(--go-sp-12) auto 0;
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

/* 订阅源浏览面板：底部上滑抽屉 */
.sheet-mask {
  position: fixed;
  inset: 0;
  background: var(--go-scrim);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 100;
  animation: go-fade-in var(--go-dur-med) var(--go-ease-standard) both;
}
.sheet {
  width: 100%;
  /* 关键：必须用 height 而非 max-height，否则 flex 子项拿不到确定高度，
     scroll-view scroll-y 会算成 0 高度而无法滚动。
     max-height 在某些 webview 中也不让 flex:1 在子 scroll-view 上生效。 */
  height: 78vh;
  max-height: 78vh;
  display: flex;
  flex-direction: column;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  box-shadow: var(--go-shadow-3);
  animation: go-sheet-up var(--go-dur-med) var(--go-ease-emphasized) both;
  overflow: hidden;
}
.sheet__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--go-sp-5) var(--go-sp-5) var(--go-sp-3);
  flex-shrink: 0;
}
.sheet__title {
  font-size: var(--go-fs-h1);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-surface);
}
.sheet__close {
  color: var(--go-on-surface-3);
  padding: var(--go-sp-2);
  &:active { opacity: 0.7; }
}
.sheet__cats {
  white-space: nowrap;
  padding: 0 var(--go-sp-5) var(--go-sp-3);
  border-bottom: 1rpx solid var(--go-outline);
  flex-shrink: 0;
}
/* 自定义订阅源输入区 */
.sheet__custom {
  padding: var(--go-sp-4) var(--go-sp-5);
  border-bottom: 1rpx solid var(--go-outline);
  flex-shrink: 0;
}
.sheet__custom-label {
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-surface-3);
  margin-bottom: var(--go-sp-2);
}
.sheet__custom-row {
  display: flex;
  align-items: center;
  gap: var(--go-sp-2);
}
.sheet__custom-input {
  flex: 1;
  min-width: 0;
  height: 68rpx;
  padding: 0 var(--go-sp-3);
  font-size: var(--go-fs-body-sm);
  color: var(--go-on-surface);
  background: var(--go-surface-2);
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-md);
  box-sizing: border-box;
}
.sheet__custom-ph { color: var(--go-on-surface-disabled); }
.sheet__custom-btn {
  flex: none;
  height: 68rpx;
  padding: 0 var(--go-sp-5);
  margin: 0;
  box-sizing: border-box;
}
.sheet__cat {
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-1);
  padding: var(--go-sp-1) var(--go-sp-4);
  margin-right: var(--go-sp-2);
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-medium);
  color: var(--go-on-surface-3);
  background: var(--go-surface-2);
  border-radius: var(--go-r-full);
  &:active { opacity: 0.8; }
  &.active {
    color: var(--go-on-primary);
    background: var(--go-primary);
  }
  &-n {
    font-size: 20rpx;
    font-weight: var(--go-fw-bold);
    opacity: 0.7;
  }
}
.sheet__list {
  /* 关键：flex 子项在 flex 容器内要让 scroll-view 拿到 px 级可用高度，
     min-height: 0 让 flex 子项不被内容撑破，否则 scroll-view 高度为 0。 */
  flex: 1;
  min-height: 0;
  /* padding-bottom 必须额外加上 --go-nav-h，否则最后一项会被页面级 Tab 栏遮挡 */
  padding: var(--go-sp-2) var(--go-sp-5) calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-5));
}
.pick {
  display: flex;
  align-items: center;
  gap: var(--go-sp-4);
  padding: var(--go-sp-4) 0;
  border-bottom: 1rpx solid var(--go-outline);
  &:active { opacity: 0.85; }
  &__main { flex: 1; min-width: 0; }
  &__title {
    display: block;
    font-size: var(--go-fs-body);
    font-weight: var(--go-fw-medium);
    color: var(--go-on-surface);
  }
  &__url {
    display: block;
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    margin-top: 4rpx;
  }
  &__btn {
    flex: none;
    padding: var(--go-sp-2) var(--go-sp-5);
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-semibold);
    border-radius: var(--go-r-full);
    color: var(--go-primary);
    background: color-mix(in srgb, var(--go-primary) 12%, var(--go-surface));
    border: 1rpx solid color-mix(in srgb, var(--go-primary) 30%, transparent);
    &:active { opacity: 0.8; }
    &.on {
      color: var(--go-on-surface-disabled);
      background: var(--go-surface-2);
      border-color: var(--go-outline);
    }
  }
}
.sheet__empty {
  text-align: center;
  color: var(--go-on-surface-3);
  padding: var(--go-sp-12) 0;
  font-size: var(--go-fs-body-sm);
}

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
