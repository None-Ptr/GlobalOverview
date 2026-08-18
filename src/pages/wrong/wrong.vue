<template>
  <view class="page">
    <view class="go-appbar floating">
      <view class="back" @click="goBack">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <view class="bar-actions">
        <text class="title">错题本（{{ list.length }}）</text>
        <view class="bar-ops">
          <text v-if="pendingCount" class="op-link warn" @click="regradeAll">
            重判 {{ pendingCount }}
          </text>
          <text v-if="list.length" class="op-link" @click="redoAll">全部重做</text>
          <text class="op-link" @click="exportWrong">导出</text>
        </view>
      </view>
    </view>

    <view v-if="loading" class="empty">
      <PolySpinner />
      <text class="state-msg">加载中…</text>
    </view>
    <view v-else-if="error" class="empty err">
      <text>{{ error }}</text>
      <text class="retry" @click="load">重试</text>
    </view>

    <scroll-view v-else scroll-y class="list">
      <view v-if="!list.length" class="empty">
        <view class="empty-ico"><GoIcon name="check" :size="'64rpx'" /></view>
        <text class="empty-msg">还没有错题，加油！</text>
      </view>
      <view v-for="(w, idx) in list" :key="w.id" class="item go-pressable go-enter" :style="{ '--i': idx }">
        <view class="item-head">
          <text class="tag">{{ typeLabel(w.type) }}</text>
          <text v-if="w.status === 'pending'" class="tag pend">判分未完成</text>
        </view>
        <text class="q">{{ w.prompt }}</text>
        <text class="ans">你的答案：{{ w.final || '（空）' }}</text>
        <text class="correct">正确：{{ (w.answerList || []).join('；') }}</text>
        <text v-if="w.comment" class="cmt">{{ w.comment }}</text>
        <text v-if="w.analysis" class="ana">{{ w.analysis }}</text>
        <view class="ops">
          <text class="op" @click="redo(w.id)">重做</text>
          <text v-if="w.status === 'pending'" class="op warn" @click="regradeOne(w.id, w.final)">重新判分</text>
          <text class="op ghost" @click="removeOne(w.id)">移出</text>
        </view>
      </view>
    </scroll-view>
  </view>
</template>

<script setup>
import { ref, computed } from 'vue'
import PolySpinner from '@/components/PolySpinner.vue'
import { onShow } from '@dcloudio/uni-app'
import { db } from '@/utils/db.js'
import { gradeBatch } from '@/utils/grade.js'
import { typeLabel } from '@/utils/quiz.js'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'
import GoIcon from '@/components/GoIcon.vue'

const store = useAppStore()
const transition = useTransition('secondary')

const { sqlVal } = db

const list = ref([])
const loading = ref(true)
const error = ref('')

const pendingCount = computed(() => list.value.filter((w) => w.status === 'pending').length)

function safeParse(json, fallback) {
  try { const v = JSON.parse(json); return v == null ? fallback : v } catch (e) { return fallback }
}

function goBack() {
  uni.navigateBack({ delta: 1 })
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    await db.init()
    // 一次性取全部题目与全部作答，内存分组，避免逐题 N+1 查询
    const questions = await db.select('SELECT * FROM questions ORDER BY id ASC')
    const answersAll = await db.select('SELECT * FROM answers ORDER BY gradedAt DESC')
    const latestByQ = new Map()
    for (const a of answersAll || []) {
      if (!latestByQ.has(a.questionId)) latestByQ.set(a.questionId, a) // 已按 gradedAt DESC，首条即最近
    }
    const out = []
    for (const q of questions) {
      const latest = latestByQ.get(q.id)
      if (!latest) continue
      if (Number(latest.wrong) !== 1) continue
      out.push({
        id: q.id,
        type: q.type,
        prompt: q.prompt,
        analysis: q.analysis,
        answerList: safeParse(q.answers, []),
        final: latest.final,
        comment: latest.comment,
        status: latest.status || 'graded',
        gradedAt: latest.gradedAt,
      })
    }
    out.sort((a, b) => (b.gradedAt || 0) - (a.gradedAt || 0))
    list.value = out
  } catch (e) {
    error.value = e.message || '加载失败'
  } finally {
    loading.value = false
  }
}

function redo(qid) {
  uni.navigateTo({ url: `/pages/quiz/quiz?ids=${qid}` })
}

function redoAll() {
  const ids = list.value.map((w) => w.id).join(',')
  if (!ids) return
  uni.navigateTo({ url: `/pages/quiz/quiz?ids=${ids}` })
}

async function regradeOne(qid, final) {
  uni.showLoading({ title: '重新判分…', mask: true })
  try {
    await gradeBatch([{ questionId: qid, final: final || '' }])
    uni.hideLoading()
    await load()
    uni.showToast({ title: '已重判', icon: 'none' })
  } catch (e) {
    uni.hideLoading()
    uni.showToast({ title: e.message || '判分失败', icon: 'none' })
  }
}

async function regradeAll() {
  const items = list.value
    .filter((w) => w.status === 'pending')
    .map((w) => ({ questionId: w.id, final: w.final || '' }))
  if (!items.length) return
  uni.showLoading({ title: `重判 ${items.length} 题…`, mask: true })
  try {
    const res = await gradeBatch(items)
    uni.hideLoading()
    await load()
    uni.showToast({
      title: res.pending ? `仍有 ${res.pending} 题失败` : '全部重判完成',
      icon: 'none',
    })
  } catch (e) {
    uni.hideLoading()
    uni.showToast({ title: e.message || '判分失败', icon: 'none' })
  }
}

function removeOne(qid) {
  uni.showModal({
    title: '移出错题本',
    content: '将清除该题的作答记录，题目本身保留。',
    success: async (r) => {
      if (!r.confirm) return
      await db.execute(`DELETE FROM answers WHERE questionId = ${sqlVal(qid)}`)
      await load()
    },
  })
}

function exportWrong() {
  uni.navigateTo({ url: '/pages/export/export?wrong=1' })
}

onShow(() => {
  load()
  transition.onEnter()
})
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
}
.bar-actions { display: flex; align-items: center; justify-content: space-between; }
.title { font-size: var(--go-fs-h1); font-weight: var(--go-fw-bold); color: var(--go-on-surface); margin-left: var(--go-sp-2); }
.bar-ops { display: flex; gap: var(--go-sp-6); }
.op-link { color: var(--go-primary); font-size: var(--go-fs-body-sm); }
.op-link:active { opacity: .5; }
.op-link.warn { color: var(--go-warning); }
.list { flex: 1; padding: var(--go-sp-4) var(--go-sp-5); }
.empty { text-align: center; color: var(--go-on-surface-3); margin-top: var(--go-sp-16); display: flex; flex-direction: column; align-items: center; gap: var(--go-sp-4); background: var(--go-surface); border-radius: var(--go-r-lg); box-shadow: var(--go-elev-1); padding: var(--go-sp-8) var(--go-sp-6); }
.empty-ico {
  width: 120rpx; height: 120rpx; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 56rpx; background: var(--go-surface-2); box-shadow: var(--go-shadow-1);
  :deep(.go-icon) { font-size: 56rpx; }
}
.empty-msg { max-width: 72%; line-height: 1.6; }
.empty.err { color: var(--go-danger); }
.retry { color: var(--go-primary); font-size: var(--go-fs-body-sm); }
.retry:active { opacity: .5; }
.item {
  border-radius: var(--go-r-lg);
  padding: var(--go-sp-5) var(--go-sp-5);
  margin-bottom: var(--go-sp-4);
  display: flex;
  flex-direction: column;
  background: var(--go-surface);
  box-shadow: var(--go-shadow-1);
  border: 1rpx solid var(--go-outline);
  transition: background var(--go-dur-med) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { background: var(--go-surface-1); transform: scale(.99); }
}
.item-head { display: flex; gap: var(--go-sp-2); margin-bottom: var(--go-sp-3); }
.tag { font-size: var(--go-fs-meta); background: var(--go-surface-2); color: var(--go-on-surface-3); padding: var(--go-sp-1) var(--go-sp-4); border-radius: var(--go-r-full); }
.tag.pend { background: color-mix(in srgb, var(--go-warning) 18%, transparent); color: var(--go-warning); }
.q { font-size: var(--go-fs-body); color: var(--go-on-surface); line-height: var(--go-lh-normal); }
.ans { font-size: var(--go-fs-body-sm); color: var(--go-danger); margin-top: var(--go-sp-3); }
.correct { font-size: var(--go-fs-body-sm); color: var(--go-success); margin-top: var(--go-sp-2); }
.cmt { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-2); }
.ana { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-2); line-height: var(--go-lh-normal); }
.ops { margin-top: var(--go-sp-4); padding-top: var(--go-sp-4); border-top: 1rpx solid var(--go-outline); display: flex; gap: var(--go-sp-3); }
.op {
  color: var(--go-primary);
  font-size: var(--go-fs-meta);
  background: var(--go-primary-95);
  padding: var(--go-sp-2) var(--go-sp-5);
  border-radius: var(--go-r-full);
  transition: transform var(--go-dur-fast) var(--go-ease-standard), opacity var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(.94); opacity: .8; }
}
.op.warn { color: var(--go-warning); background: color-mix(in srgb, var(--go-warning) 16%, transparent); }
.op.ghost { color: var(--go-on-surface-3); background: var(--go-surface-2); }
.state-msg { color: var(--go-on-surface-3); font-size: var(--go-fs-body-sm); }
</style>
