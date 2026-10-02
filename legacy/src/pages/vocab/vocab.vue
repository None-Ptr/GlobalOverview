<template>
  <view class="page">
    <view class="go-appbar">
      <text class="go-appbar__title">词汇</text>
      <view class="go-appbar__actions">
        <view v-if="heads.length" class="ai-btn" @click="onOrganize">
          <GoIcon name="robot" :size="'40rpx'" />
          <text>AI 整理</text>
        </view>
        <text v-if="heads.length" class="clear" @click="clearAll">清空</text>
      </view>
    </view>

    <view class="seg">
      <view class="seg-item" :class="{ on: view === 'vocab' }" @click="view = 'vocab'">词汇</view>
      <view class="seg-item" :class="{ on: view === 'sentence' }" @click="view = 'sentence'">句子</view>
    </view>

    <template v-if="view === 'vocab'">
    <!-- 待复习入口 -->
    <view class="review-card" @click="goReview">
      <view class="review-card__main">
        <text class="review-card__num">{{ dueCount }}</text>
        <text class="review-card__label">张待复习</text>
      </view>
      <text class="review-card__go">去复习 ›</text>
    </view>

    <view class="words-meta">{{ heads.length }} 个词族</view>

    <view class="modes">
      <view class="mode" :class="{ on: mode === 'all' }" @click="mode = 'all'">全部</view>
      <view class="mode" :class="{ on: mode === 'word' }" @click="mode = 'word'">单词</view>
      <view class="mode" :class="{ on: mode === 'phrase' }" @click="mode = 'phrase'">短语</view>
    </view>

    <view v-if="filtered.length" class="list">
      <view
        v-for="(h, idx) in filtered"
        :key="h.head"
        class="card go-enter"
        :style="{ '--i': idx }"
        @click="openOcc(h)"
      >
        <view class="card-main">
          <text class="word">{{ h.head }}</text>
          <view class="badges">
            <text v-if="h.occCount > 1" class="badge">×{{ h.occCount }}</text>
            <text v-if="h.sourceCount > 1" class="badge badge--src">{{ h.sourceCount }} 来源</text>
          </view>
          <text v-if="h.zh" class="zh">{{ h.zh }}</text>
          <text class="preview">{{ previewOf(h) }}</text>
        </view>
        <text class="del" @click.stop="remove(h)">删除</text>
      </view>
    </view>
    <view v-else class="empty">
      <view class="empty-ico"><GoIcon name="book" :size="'64rpx'" /></view>
      <text class="empty-msg">还没有收藏的词汇。在正文里点词即可沉淀到这里。</text>
    </view>
    </template>

    <!-- 句子视图：查询过的句子，支持 LLM 语法/语块拆解 -->
    <template v-else>
      <view class="words-meta">{{ sentences.length }} 个收藏句子</view>
      <view v-if="sentences.length" class="sentence-list">
        <view v-for="(s, i) in sentences" :key="i" class="sentence-card">
          <text class="sentence-text">“{{ s.sentence }}”</text>
          <text class="sentence-src">{{ s.sourceLabel || '来源' }} · {{ s.articleTitle || '' }}</text>
          <view class="sentence-actions">
            <view class="mini-btn" @click="goArticleFromSentence(s)">回到原文</view>
            <view class="mini-btn mini-btn--ai" @click="onAnalyze(s)">
              {{ s._analyzing ? '拆解中…' : (s._analysis ? '重新拆解' : 'LLM 拆解') }}
            </view>
          </view>
          <view v-if="s._analysis" class="analysis">
            <text v-if="s._analysis.translation" class="analysis-tr">{{ s._analysis.translation }}</text>
            <view v-if="s._analysis.chunks && s._analysis.chunks.length" class="analysis-sec">
              <text class="analysis-h">语块</text>
              <view v-for="(c, ci) in s._analysis.chunks" :key="ci" class="analysis-row">
                <text class="analysis-k">{{ c.text }}</text>
                <text class="analysis-v">{{ c.type }} · {{ c.note }}</text>
              </view>
            </view>
            <view v-if="s._analysis.grammar && s._analysis.grammar.length" class="analysis-sec">
              <text class="analysis-h">语法</text>
              <view v-for="(g, gi) in s._analysis.grammar" :key="gi" class="analysis-row">
                <text class="analysis-k">{{ g.point }}</text>
                <text class="analysis-v">{{ g.explain }}</text>
              </view>
            </view>
            <view v-if="s._analysis.keywords && s._analysis.keywords.length" class="analysis-sec">
              <text class="analysis-h">重点词</text>
              <view v-for="(k, ki) in s._analysis.keywords" :key="ki" class="analysis-row">
                <text class="analysis-k">{{ k.word }} <text class="analysis-pos">{{ k.pos }}</text></text>
                <text class="analysis-v">{{ k.zh }}</text>
              </view>
            </view>
          </view>
        </view>
      </view>
      <view v-else class="empty">
        <view class="empty-ico"><GoIcon name="book" :size="'64rpx'" /></view>
        <text class="empty-msg">还没有收藏的句子。在正文里点词，原句会自动沉淀到这里。</text>
      </view>
    </template>

    <!-- 出处面板（语境回溯） -->
    <view v-if="occ" class="mask" @click="occ = null">
      <view class="sheet" @click.stop>
        <text class="sheet-word">{{ occ.head }}</text>
        <text v-if="occ.zh" class="sheet-zh">{{ occ.zh }}</text>
        <view class="sheet-body">
          <view v-for="(o, i) in occ.list" :key="i" class="occ" @click="goArticle(o)">
            <text class="occ-src">{{ o.sourceLabel || '来源' }} · {{ o.articleTitle || '' }}</text>
            <text class="occ-sentence">“{{ o.sentence }}”</text>
            <text class="occ-go">回到原文 ›</text>
          </view>
          <view v-if="!occ.list.length" class="occ-empty">暂无原文出处</view>
        </view>
        <view class="sheet-actions">
          <view class="sheet-btn" @click="occ = null">关闭</view>
        </view>
      </view>
    </view>

    <!-- AI 整理结果 -->
    <view v-if="org" class="mask" @click="org = null">
      <view class="sheet sheet--tall" @click.stop>
        <text class="sheet-word">AI 整理结果</text>
        <view class="sheet-body">
          <view v-for="(g, gi) in org.groups" :key="gi" class="grp">
            <text class="grp-theme">{{ g.theme }}</text>
            <view v-for="(it, ii) in g.items" :key="ii" class="grp-item">
              <text class="grp-word">{{ it.word }} <text class="grp-pos">{{ it.pos }}</text></text>
              <text class="grp-zh">{{ it.zh }}</text>
              <text class="grp-en">{{ it.en }}</text>
              <text class="grp-fam">词族：{{ (it.family || []).join(', ') }}</text>
              <text class="grp-ex">e.g. {{ it.example }}</text>
            </view>
          </view>
        </view>
        <view class="sheet-actions">
          <view class="sheet-btn" @click="org = null">完成</view>
        </view>
      </view>
    </view>

    <PolySpinner v-if="busy" />
  </view>
  <BottomNav />
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'
import {
  getHeads, getOccurrence, getDueCount, llmOrganize, removeHead, clearVocab, syncHeadsFromCache,
  getSentences, llmAnalyzeSentence,
} from '@/utils/vocab.js'
import { loadWordCache } from '@/utils/word.js'
import { db } from '@/utils/db.js'
import GoIcon from '@/components/GoIcon.vue'
import PolySpinner from '@/components/PolySpinner.vue'
import BottomNav from '@/components/BottomNav.vue'

const store = useAppStore()
const transition = useTransition('tab')

const heads = ref([])
const mode = ref('all')
const view = ref('vocab')
const sentences = ref([])
const dueCount = ref(0)
const occ = ref(null)
const org = ref(null)
const busy = ref(false)

const filtered = computed(() => {
  if (mode.value === 'all') return heads.value
  return heads.value.filter((h) => h.kind === mode.value)
})

function previewOf(h) {
  return (h.latestSentence || '').slice(0, 70)
}

function toast(msg, icon) {
  uni.showToast({ title: String(msg).slice(0, 80), icon: icon || 'none', duration: 2500 })
}

async function load() {
  try {
    await db.init()
    await syncHeadsFromCache()
    const list = await getHeads()
    const wc = await loadWordCache(1000)
    const wcMap = new Map()
    for (const w of (wc || [])) {
      const k = w.lemma || w.word
      if (!wcMap.has(k)) wcMap.set(k, w)
    }
    // 一次性取全部出处并按 lemma 分组，避免逐词 N+1 查询
    const allOcc = await db.select(
      `SELECT articleGuid, articleTitle, sourceLabel, sentence, lemma FROM vocab_occ ORDER BY at DESC`
    ) || []
    const occByHead = new Map()
    for (const o of allOcc) {
      if (!occByHead.has(o.lemma)) occByHead.set(o.lemma, [])
      occByHead.get(o.lemma).push(o)
    }
    for (const h of list) {
      const occs = occByHead.get(h.head) || []
      h.sourceCount = new Set(occs.map((o) => o.articleGuid)).size
      h.latestSentence = (occs[0] && occs[0].sentence) || ''
      const hit = wcMap.get(h.head)
      if (hit && hit.result) {
        if (hit.result.kind === 'dict') {
          h.zh = (hit.result.senses && hit.result.senses[0] && hit.result.senses[0].definition) || ''
        } else if (hit.result.text) {
          h.zh = hit.result.text
        }
      }
    }
    heads.value = list
    dueCount.value = await getDueCount()
    const rawSent = await getSentences()
    sentences.value = (rawSent || []).map((s) => {
      let a = null
      try { if (s.analysis) a = JSON.parse(s.analysis) } catch (e) { a = null }
      return { ...s, _analysis: a, _analyzing: false }
    })
  } catch (e) {
    const msg = (e && e.message) || e || '未知错误'
    console.error('[vocab] load error:', e)
    toast('词汇加载失败: ' + msg)
  }
}

async function onOrganize() {
  if (!heads.value.length) { uni.showToast({ title: '暂无生词', icon: 'none' }); return }
  busy.value = true
  try {
    const wc = await loadWordCache(500)
    const res = await llmOrganize(wc)
    org.value = res
    await load()
  } catch (e) {
    const msg = (e && e.message) || '整理失败'
    if (/未配置 LLM|未配置/.test(msg)) {
      uni.showModal({
        title: '未配置 LLM',
        content: 'AI 整理需要模型配置，是否前往「我的」添加？',
        success: (r) => { if (r.confirm) uni.navigateTo({ url: '/pages/model-form/model-form' }) },
      })
    } else {
      uni.showToast({ title: msg.slice(0, 60), icon: 'none' })
    }
  } finally { busy.value = false }
}

async function openOcc(h) {
  const list = await getOccurrence(h.head)
  occ.value = { head: h.head, zh: h.zh || '', list: list || [] }
}

function goArticle(o) {
  if (!o.articleGuid) { uni.showToast({ title: '无原文锚点', icon: 'none' }); return }
  occ.value = null
  uni.navigateTo({
    url: `/pages/article/article?guid=${encodeURIComponent(o.articleGuid)}&focusPara=${o.paraIndex}&focusTok=${o.tokIndex}`,
  })
}

function goArticleFromSentence(s) {
  if (!s.articleGuid) { uni.showToast({ title: '无原文锚点', icon: 'none' }); return }
  uni.navigateTo({
    url: `/pages/article/article?guid=${encodeURIComponent(s.articleGuid)}&focusPara=${s.paraIndex}&focusTok=${s.tokIndex}`,
  })
}

async function onAnalyze(s) {
  if (!s.sentence) return
  s._analyzing = true
  try {
    const data = await llmAnalyzeSentence(s.sentence)
    s._analysis = data
    uni.showToast({ title: '拆解完成', icon: 'success' })
  } catch (e) {
    const msg = (e && e.message) || '拆解失败'
    if (/未配置 LLM/.test(msg)) {
      uni.showModal({
        title: '未配置 LLM',
        content: '语法拆解需要模型配置，是否前往「我的」添加？',
        success: (r) => { if (r.confirm) uni.navigateTo({ url: '/pages/model-form/model-form' }) },
      })
    } else {
      uni.showToast({ title: msg.slice(0, 60), icon: 'none' })
    }
  } finally {
    s._analyzing = false
  }
}

function goReview() {
  uni.navigateTo({ url: '/pages/review/review' })
}

async function remove(h) {
  uni.showModal({
    title: '删除',
    content: `从词汇库移除「${h.head}」？`,
    success: async (r) => {
      if (r.confirm) {
        await removeHead(h.head)
        heads.value = heads.value.filter((x) => x.head !== h.head)
        dueCount.value = await getDueCount()
      }
    },
  })
}

async function clearAll() {
  uni.showModal({
    title: '清空词汇',
    content: '确定删除全部收藏词汇与复习进度？',
    success: async (r) => {
      if (r.confirm) {
        await clearVocab()
        heads.value = []
        dueCount.value = 0
        uni.showToast({ title: '已清空', icon: 'success' })
      }
    },
  })
}

onMounted(() => {
  transition.onEnter()
  uni.$emit('nav:active', 'words')
  load()
})
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  min-height: 100vh;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
}
.ai-btn {
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-1);
  padding: var(--go-sp-1) var(--go-sp-3);
  border-radius: var(--go-r-full);
  color: var(--go-primary);
  border: 1rpx solid var(--go-primary);
  font-size: var(--go-fs-meta);
  &:active { background: var(--go-primary-95); }
}
.clear { margin-left: var(--go-sp-3); color: var(--go-on-surface-3); font-size: var(--go-fs-meta); }

.review-card {
  margin: var(--go-sp-4) var(--go-sp-6);
  padding: var(--go-sp-5) var(--go-sp-6);
  border-radius: var(--go-r-lg);
  background: color-mix(in srgb, var(--go-primary) 12%, var(--go-surface));
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: var(--go-elev-1);
  &:active { transform: scale(0.99); }
  &__num { font-size: 44rpx; font-weight: var(--go-fw-bold); color: var(--go-primary); }
  &__label { font-size: var(--go-fs-body-sm); color: var(--go-on-surface); margin-left: 8rpx; }
  &__go { font-size: var(--go-fs-body-sm); color: var(--go-primary); font-weight: var(--go-fw-semibold); }
}
.words-meta {
  padding: 0 var(--go-sp-6) var(--go-sp-2);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
}
.modes {
  display: flex;
  gap: var(--go-sp-2);
  padding: 0 var(--go-sp-6) var(--go-sp-3);
}
.mode {
  padding: var(--go-sp-1) var(--go-sp-4);
  border-radius: var(--go-r-full);
  border: 1rpx solid var(--go-outline);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  background: transparent;
  &.on { border-color: var(--go-primary); color: var(--go-primary); background: var(--go-primary-95); }
}

.seg {
  display: flex;
  gap: var(--go-sp-2);
  padding: var(--go-sp-3) var(--go-sp-6) var(--go-sp-2);
}
.seg-item {
  flex: 1;
  text-align: center;
  padding: var(--go-sp-2) 0;
  border-radius: var(--go-r-md);
  border: 1rpx solid var(--go-outline);
  font-size: var(--go-fs-body);
  color: var(--go-on-surface-3);
  background: transparent;
  &.on { border-color: var(--go-primary); color: var(--go-primary); background: var(--go-primary-95); }
}

.sentence-list { padding: var(--go-sp-2) var(--go-sp-6) var(--go-sp-8); }
.sentence-card {
  background: var(--go-surface-2);
  border-radius: var(--go-r-lg);
  padding: var(--go-sp-5);
  margin-bottom: var(--go-sp-4);
  border: 1rpx solid var(--go-outline);
}
.sentence-text { font-size: var(--go-fs-body); line-height: 1.6; color: var(--go-on-surface); }
.sentence-src { display: block; margin-top: var(--go-sp-2); font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }
.sentence-actions { display: flex; gap: var(--go-sp-3); margin-top: var(--go-sp-4); }
.mini-btn {
  padding: var(--go-sp-1) var(--go-sp-5);
  border-radius: var(--go-r-full);
  border: 1rpx solid var(--go-outline);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-2);
  background: transparent;
  &.mini-btn--ai { border-color: var(--go-primary); color: var(--go-primary); }
}
.analysis { margin-top: var(--go-sp-4); border-top: 1rpx dashed var(--go-outline); padding-top: var(--go-sp-3); }
.analysis-tr { display: block; font-size: var(--go-fs-body); color: var(--go-on-surface); margin-bottom: var(--go-sp-3); }
.analysis-sec { margin-bottom: var(--go-sp-3); }
.analysis-h { display: block; font-size: var(--go-fs-meta); color: var(--go-primary); font-weight: var(--go-fw-semibold); margin-bottom: var(--go-sp-1); }
.analysis-row { display: flex; flex-direction: column; padding: var(--go-sp-2) 0; border-top: 1rpx solid var(--go-outline); }
.analysis-k { font-size: var(--go-fs-body); color: var(--go-on-surface); }
.analysis-v { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: 2rpx; }
.analysis-pos { color: var(--go-primary); font-size: var(--go-fs-meta); }

.list { padding: 0 var(--go-sp-6); }
.card {
  display: flex;
  align-items: center;
  gap: var(--go-sp-4);
  padding: var(--go-sp-4) var(--go-sp-5);
  margin-bottom: var(--go-sp-3);
  border-radius: var(--go-r-lg);
  background: var(--go-surface);
  box-shadow: var(--go-elev-1);
  &:active { background: var(--go-surface-2); }
}
.card-main { flex: 1; min-width: 0; }
.word { font-size: var(--go-fs-body); font-weight: var(--go-fw-semibold); color: var(--go-on-surface); }
.badges { display: inline-flex; gap: var(--go-sp-2); margin-left: var(--go-sp-3); }
.badge {
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  background: var(--go-surface-2);
  border-radius: var(--go-r-full);
  padding: 2rpx var(--go-sp-2);
  &--src { color: var(--go-primary); background: var(--go-primary-95); }
}
.zh { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface); margin-top: 4rpx; }
.preview {
  display: block;
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  margin-top: 2rpx;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.del { font-size: var(--go-fs-meta); color: var(--go-danger); flex: none; padding: var(--go-sp-2); }

.empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--go-sp-4);
  padding: var(--go-sp-16) var(--go-sp-8);
  color: var(--go-on-surface-3);
  &-msg { font-size: var(--go-fs-body-sm); text-align: center; line-height: 1.6; }
}

.mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  display: flex;
  align-items: flex-end;
  z-index: 200;
}
.sheet {
  width: 100%;
  max-height: 78vh;
  background: var(--go-surface);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  padding: var(--go-sp-6);
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  animation: go-sheet-up var(--go-dur-med) var(--go-ease-emphasized) both;
  &--tall { max-height: 84vh; }
}
.sheet-word { font-size: var(--go-fs-title); font-weight: var(--go-fw-bold); color: var(--go-on-surface); }
.sheet-zh { font-size: var(--go-fs-body); color: var(--go-on-surface-3); margin-top: 2rpx; }
.sheet-body {
  flex: 1;
  overflow-y: auto;
  margin: var(--go-sp-4) 0;
}
.sheet-actions { display: flex; gap: var(--go-sp-3); }
.sheet-btn {
  flex: 1;
  text-align: center;
  padding: var(--go-sp-3);
  border-radius: var(--go-r-full);
  background: var(--go-primary);
  color: #fff;
  font-size: var(--go-fs-body);
  &:active { opacity: 0.9; }
}
.occ {
  padding: var(--go-sp-4) 0;
  border-bottom: 1rpx solid var(--go-outline);
  &:active { background: var(--go-surface-2); }
  &-src { font-size: var(--go-fs-meta); color: var(--go-primary); font-weight: var(--go-fw-semibold); }
  &-sentence { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface); margin-top: 4rpx; line-height: 1.5; }
  &-go { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: 4rpx; }
  &-empty { font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); padding: var(--go-sp-4) 0; }
}
.grp { margin-bottom: var(--go-sp-5); }
.grp-theme {
  display: inline-block;
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-semibold);
  color: var(--go-primary);
  background: var(--go-primary-95);
  border-radius: var(--go-r-full);
  padding: 2rpx var(--go-sp-3);
  margin-bottom: var(--go-sp-2);
}
.grp-item {
  display: block;
  padding: var(--go-sp-3) 0;
  border-bottom: 1rpx solid var(--go-outline);
}
.grp-word { font-size: var(--go-fs-body); font-weight: var(--go-fw-semibold); color: var(--go-on-surface); }
.grp-pos { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); font-weight: var(--go-fw-normal); margin-left: 6rpx; }
.grp-zh { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface); }
.grp-en { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }
.grp-fam { display: block; font-size: var(--go-fs-meta); color: var(--go-primary); margin-top: 2rpx; }
.grp-ex { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); font-style: italic; margin-top: 2rpx; }

@keyframes go-sheet-up {
  from { transform: translateY(100%); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
.go-enter { animation: go-enter var(--go-dur-med) var(--go-ease-standard) both; animation-delay: calc(var(--i) * 18ms); }
@keyframes go-enter {
  from { opacity: 0; transform: translateY(8rpx); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
