<template>
  <view class="page">
    <view class="go-appbar floating">
      <view class="back" @click="goBack">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <text class="progress">{{ questions.length ? idx + 1 : 0 }} / {{ questions.length }}</text>
      <text class="submit" @click="submit">{{ result ? '重做' : '交卷' }}</text>
    </view>

    <view v-if="loading" class="state">
      <PolySpinner />
      <text class="state-msg">加载中…</text>
    </view>
    <view v-else-if="error" class="state err">
      <text class="state-msg">{{ error }}</text>
      <text class="state-btn" @click="load">重试</text>
    </view>
    <view v-else-if="!questions.length" class="state">
      <text class="state-msg">这里还没有题目</text>
    </view>

    <swiper v-else class="swiper" :current="idx" @change="onSwipe">
      <swiper-item v-for="(q, i) in questions" :key="q.id">
        <scroll-view scroll-y class="q-scroll go-fade-in">
          <view class="q-meta">
            <text class="tag">{{ typeLabel(q.type) }}</text>
            <text class="tag grade">{{ gradeLabel(q.gradeMode) }}</text>
            <text v-if="history[q.id] && history[q.id].length" class="tag hist">
              第 {{ history[q.id].length + 1 }} 次作答
            </text>
          </view>
          <text class="q-prompt">{{ q.prompt }}</text>

          <!-- 回到原文：不在此直接贴出出处，按了另开一页看原文 -->
          <view class="to-src" @click="openSource">
            <GoIcon name="book-open" :size="'34rpx'" />
            <text class="to-src__txt">回到原文</text>
          </view>

          <!-- 重做时展示上一次的作答与点评作为上下文 -->
          <view v-if="lastOf(q.id)" class="last">
            <text class="last-title">上次作答（{{ lastOf(q.id).correct ? '正确' : '错误' }}）</text>
            <text class="last-body">{{ lastOf(q.id).final || '（未作答）' }}</text>
            <text v-if="lastOf(q.id).comment" class="last-cmt">{{ lastOf(q.id).comment }}</text>
          </view>

          <view v-if="q.type === 'choice'" class="options">
            <view
              v-for="(o, oi) in q.options"
              :key="oi"
              class="opt"
              :class="{ sel: draftOf(q.id) === o }"
              @click="pick(q.id, o)"
            >{{ o }}</view>
          </view>

          <input
            v-else-if="q.type === 'fill'"
            class="input"
            :value="draftOf(q.id)"
            placeholder="输入答案"
            :cursor-spacing="20"
            :adjust-position="true"
            :hold-keyboard="true"
            :confirm-type="'done'"
            @input="(e) => setDraft(q.id, e.detail.value)"
            @focus="(e) => onInputFocus(e, q.id)"
          />

          <textarea
            v-else
            class="area"
            :value="draftOf(q.id)"
            placeholder="输入答案"
            :cursor-spacing="20"
            :adjust-position="true"
            :hold-keyboard="true"
            :adjust-keyboard-to="'click'"
            @input="(e) => setDraft(q.id, e.detail.value)"
            @focus="(e) => onInputFocus(e, q.id)"
          />

          <view v-if="result && answered[q.id]" class="result">
            <text :class="['res-tag', resClass(answered[q.id])]">{{ resLabel(answered[q.id]) }}</text>
            <text v-if="answered[q.id].comment" class="res-cmt">{{ answered[q.id].comment }}</text>
            <text
              v-if="answered[q.id].status === 'pending'"
              class="res-retry"
              @click="retryGrade(q.id)"
            >重新判分</text>
            <text class="res-answer">参考答案：{{ (q.answerList || []).join(' / ') }}</text>
            <text v-if="q.analysis" class="res-analysis">{{ q.analysis }}</text>
          </view>
        </scroll-view>
      </swiper-item>
    </swiper>

    <scroll-view v-if="questions.length" scroll-x class="nav">
      <view
        v-for="(q, i) in questions"
        :key="q.id"
        class="nav-dot"
        :class="navClass(q, i)"
        @click="idx = i"
      >{{ i + 1 }}</view>
    </scroll-view>
  </view>
</template>

<script setup>
import { ref, onMounted, onErrorCaptured } from 'vue'
import PolySpinner from '@/components/PolySpinner.vue'
import GoIcon from '@/components/GoIcon.vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import { db, sqlVal } from '@/utils/db.js'
import { loadSet, loadQuestionsByIds, typeLabel } from '@/utils/quiz.js'
import { gradeBatch } from '@/utils/grade.js'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'

const store = useAppStore()

onErrorCaptured((e) => {
  uni.showToast({ title: 'quiz ERR ' + (e && e.message ? e.message : '').slice(0, 50), icon: 'none', duration: 6000 })
  return true
})

const transition = useTransition('secondary')
onShow(() => transition.onEnter())

const setId = ref(0)
const idOnly = ref([])
const questions = ref([])
const idx = ref(0)
const drafts = ref({})     // questionId -> 草稿字符串
const answered = ref({})   // questionId -> { correct, comment, status }
const history = ref({})    // questionId -> 历次作答
const result = ref(false)
const loading = ref(true)
const error = ref('')
const articleGuid = ref('')   // 本题集对应原文文章的 guid，用于「回到原文」

function gradeLabel(g) { return { exact: '精确', contains: '包含', ai: 'AI判', manual: '人工' }[g] || g }

function draftOf(qid) { return drafts.value[qid] || '' }

// 输入聚焦：滚到 input 可见（避免 swiper-item 高度坍缩后点击落空）
function onInputFocus(_e, qid) {
  try {
    const focusIndex = questions.value.findIndex((it) => it && it.id === qid)
    // idx 是顶层 ref（当前 swiper 索引），避免与局部变量同名遮蔽
    if (focusIndex >= 0 && idx.value !== focusIndex) idx.value = focusIndex
  } catch (_) {}
}

// 回到原文：另开一页显示对应文章（不在此贴出处，提高难度）
function openSource() {
  if (!articleGuid.value) {
    uni.showToast({ title: '未关联原文', icon: 'none' })
    return
  }
  uni.navigateTo({ url: '/pages/article/article?guid=' + encodeURIComponent(articleGuid.value) + '&quiz=1' })
}

let saveTimer = null
function setDraft(qid, v) {
  drafts.value[qid] = v
  // 输入防抖，避免每个字符都落库（草稿存 answers.draft）
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(() => { db.saveDraft(qid, v).catch(() => {}) }, 300)
}
function pick(qid, o) {
  drafts.value[qid] = o
  db.saveDraft(qid, o).catch(() => {})
}

function lastOf(qid) {
  const h = history.value[qid]
  if (!h || !h.length) return null
  return h[h.length - 1]
}

function resClass(a) {
  if (a.status === 'pending') return 'pend'
  return a.correct ? 'ok' : 'bad'
}
function resLabel(a) {
  if (a.status === 'pending') return '判分未完成'
  return a.correct ? '正确' : '错误'
}

function navClass(q, i) {
  const a = answered.value[q.id]
  return {
    cur: i === idx.value,
    done: !!drafts.value[q.id],
    ok: result.value && a && a.status === 'graded' && a.correct,
    bad: result.value && a && a.status === 'graded' && !a.correct,
    pend: result.value && a && a.status === 'pending',
  }
}

onLoad((q) => {
  setId.value = Number(q && q.setId) || 0
  idOnly.value = q && q.ids
    ? String(q.ids).split(',').map(Number).filter(Boolean)
    : []
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    await db.init()
    questions.value = idOnly.value.length
      ? await loadQuestionsByIds(idOnly.value)
      : await loadSet(setId.value)

    const ids = questions.value.map((q) => q.id)
    drafts.value = await db.loadDrafts(ids)
    history.value = await db.loadHistory(ids)

    // 关联原文：从题集拿到 articleId，再取 articles.guid 用于「回到原文」
    try {
      const firstSetId = questions.value[0] && questions.value[0].setId
      if (firstSetId) {
        const setRows = await db.select(`SELECT articleId FROM question_sets WHERE id = ${sqlVal(firstSetId)}`)
        const articleId = setRows && setRows[0] && setRows[0].articleId
        if (articleId) {
          const artRows = await db.select(`SELECT guid FROM articles WHERE id = ${sqlVal(articleId)}`)
          if (artRows && artRows[0] && artRows[0].guid) articleGuid.value = artRows[0].guid
        }
      }
    } catch (_) { /* 关联失败不阻断做题 */ }
  } catch (e) {
    error.value = e.message || '加载失败'
    uni.showToast({ title: 'quiz load ERR ' + (e.message || '').slice(0, 50), icon: 'none', duration: 6000 })
  } finally {
    loading.value = false
  }
}

function onSwipe(e) { idx.value = e.detail.current }

async function submit() {
  if (!questions.value.length) return
  if (result.value) { // 再次点击 = 开始新一轮重做
    result.value = false
    answered.value = {}
    drafts.value = {}
    history.value = await db.loadHistory(questions.value.map((q) => q.id))
    idx.value = 0
    return
  }

  const unanswered = questions.value.filter((q) => !draftOf(q.id).trim())
  if (unanswered.length) {
    const go = await confirmModal(`还有 ${unanswered.length} 题未作答，仍要交卷？`)
    if (!go) return
  }

  uni.showLoading({ title: '判分中…', mask: true })
  try {
    const items = questions.value.map((q) => ({ questionId: q.id, final: draftOf(q.id) }))
    const res = await gradeBatch(items)
    for (const r of res.results) {
      answered.value[r.questionId] = { correct: !!r.correct, comment: r.comment, status: r.status }
    }
    await db.clearDrafts(questions.value.map((q) => q.id))
    result.value = true

    const correct = res.results.filter((r) => r.status === 'graded' && r.correct).length
    let content = `正确 ${correct} / ${res.results.length}`
    if (res.pending) content += `，${res.pending} 题判分未完成，可单独重判`
    const wrongCount = res.results.filter((r) => r.status === 'graded' && !r.correct).length
    if (wrongCount) content += '，错题已入错题本'

    uni.hideLoading()
    uni.showModal({
      title: '判分完成',
      content,
      confirmText: wrongCount ? '查看错题' : '好',
      showCancel: !!wrongCount,
      cancelText: '留在本页',
      success: (r) => {
        if (r.confirm && wrongCount) uni.navigateTo({ url: '/pages/wrong/wrong' })
      },
    })
  } catch (e) {
    uni.hideLoading()
    uni.showModal({ title: '判分失败', content: e.message || '未知错误', showCancel: false })
  }
}

async function retryGrade(qid) {
  uni.showLoading({ title: '重新判分…', mask: true })
  try {
    const a = answered.value[qid]
    const res = await gradeBatch([{ questionId: qid, final: a ? draftOf(qid) : '' }])
    const r = res.results[0]
    if (r) answered.value[qid] = { correct: !!r.correct, comment: r.comment, status: r.status }
    uni.hideLoading()
    uni.showToast({ title: r && r.status === 'graded' ? '判分完成' : '仍未成功', icon: 'none' })
  } catch (e) {
    uni.hideLoading()
    uni.showToast({ title: e.message || '判分失败', icon: 'none' })
  }
}

function confirmModal(content) {
  return new Promise((resolve) => {
    uni.showModal({
      title: '提示',
      content,
      success: (r) => resolve(!!r.confirm),
      fail: () => resolve(false),
    })
  })
}

function goBack() { uni.navigateBack() }
onMounted(load)
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  height: 100vh;
  min-height: 100vh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
}
.top-actions { display: flex; align-items: center; }
.back-svg { font-size: 40rpx; line-height: 1; }
.progress { flex: 1; text-align: center; font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); font-weight: var(--go-fw-semibold); }
.submit { color: var(--go-primary); font-size: var(--go-fs-body-sm); font-weight: var(--go-fw-semibold); }
.submit:active { opacity: .5; }
.state { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--go-sp-6); background: var(--go-surface); border-radius: var(--go-r-lg); box-shadow: var(--go-elev-1); margin: var(--go-sp-6); padding: var(--go-sp-8) var(--go-sp-6); }
.state-msg { color: var(--go-on-surface-3); font-size: var(--go-fs-body-sm); }
.state.err .state-msg { color: var(--go-danger); }
.state-btn { color: var(--go-primary); font-size: var(--go-fs-body-sm); }
.state-btn:active { opacity: .6; }
.swiper { flex: 1; min-height: 0; }
.q-scroll { flex: 1; height: 100%; min-height: 480rpx; padding: var(--go-sp-6); box-sizing: border-box; }
.q-meta { display: flex; flex-wrap: wrap; gap: var(--go-sp-2); margin-bottom: var(--go-sp-4); }
.tag { font-size: var(--go-fs-meta); background: var(--go-surface-2); color: var(--go-on-surface-3); padding: var(--go-sp-1) var(--go-sp-4); border-radius: var(--go-r-full); }
.tag.grade { background: var(--go-primary-95); color: var(--go-primary); }
.tag.hist { background: color-mix(in srgb, var(--go-warning) 18%, transparent); color: var(--go-warning); }
.q-prompt { font-size: var(--go-fs-body); line-height: var(--go-lh-normal); color: var(--go-on-surface); display: block; margin-bottom: var(--go-sp-6); }
/* 回到原文按钮：不在此贴出处，按了另开一页看原文（提高难度） */
.to-src {
  display: inline-flex; align-items: center; gap: var(--go-sp-2);
  margin: 0 0 var(--go-sp-6); padding: var(--go-sp-2) var(--go-sp-4);
  background: var(--go-surface-2); color: var(--go-primary);
  border: 1rpx solid var(--go-outline); border-radius: var(--go-r-full);
  font-size: var(--go-fs-meta); line-height: 1; cursor: pointer;
}
.to-src__txt { font-weight: var(--go-fw-semibold); }
.last { background: color-mix(in srgb, var(--go-warning) 8%, transparent); border-left: 6rpx solid var(--go-warning); border-radius: 0 var(--go-r-md) var(--go-r-md) 0; padding: var(--go-sp-3) var(--go-sp-4); margin-bottom: var(--go-sp-5); }
.last-title { display: block; font-size: var(--go-fs-meta); color: var(--go-warning); margin-bottom: var(--go-sp-1); }
.last-body { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); line-height: var(--go-lh-normal); }
.last-cmt { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-1); }
.options { display: flex; flex-direction: column; gap: var(--go-sp-3); }
.opt {
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-md);
  padding: var(--go-sp-5) var(--go-sp-5);
  font-size: var(--go-fs-body-sm);
  color: var(--go-on-surface);
  background: var(--go-surface);
  transition: background var(--go-dur-fast) var(--go-ease-standard),
    border-color var(--go-dur-fast) var(--go-ease-standard),
    color var(--go-dur-fast) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(.99); }
}
/* M3 选中态：primary-container 填充 + 主色左边框，替代整块纯蓝 */
.opt.sel { background: var(--go-primary-95); color: var(--go-on-primary-container); border-color: var(--go-primary); font-weight: var(--go-fw-semibold); border-left-width: 6rpx; }
.input {
  width: 100%; box-sizing: border-box; margin-top: var(--go-sp-2);
  min-height: 72rpx; line-height: 1.5;
  border: 1rpx solid var(--go-outline); border-radius: var(--go-r-md);
  padding: var(--go-sp-3) var(--go-sp-4);
  font-size: var(--go-fs-body); background: var(--go-surface-2); color: var(--go-on-surface);
}
.area {
  width: 100%; height: 240rpx; border: 1rpx solid var(--go-outline); border-radius: var(--go-r-md);
  padding: var(--go-sp-4); font-size: var(--go-fs-body-sm); margin-top: var(--go-sp-2); box-sizing: border-box; background: var(--go-surface-2); color: var(--go-on-surface);
}
.result { margin-top: var(--go-sp-6); padding: var(--go-sp-5); background: var(--go-surface); border-radius: var(--go-r-md); box-shadow: var(--go-shadow-1); border: 1rpx solid var(--go-outline); }
.res-tag { font-size: var(--go-fs-body-sm); font-weight: var(--go-fw-semibold); margin-right: var(--go-sp-2); }
.res-tag.ok { color: var(--go-success); }
.res-tag.bad { color: var(--go-danger); }
.res-tag.pend { color: var(--go-warning); }
.res-cmt { font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); }
.res-retry { display: inline-block; margin-left: var(--go-sp-3); font-size: var(--go-fs-meta); color: var(--go-primary); }
.res-answer { display: block; font-size: var(--go-fs-body-sm); color: var(--go-success); margin-top: var(--go-sp-2); }
.res-analysis { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); line-height: var(--go-lh-normal); margin-top: var(--go-sp-1); }
.nav { white-space: nowrap; padding: var(--go-sp-3) var(--go-sp-5); border-top: 1rpx solid var(--go-outline); background: var(--go-bg); }
.nav-dot {
  display: inline-block; width: 56rpx; height: 56rpx; line-height: 56rpx;
  text-align: center; border-radius: var(--go-r-sm); background: var(--go-surface-2); font-size: var(--go-fs-meta);
  margin-right: var(--go-sp-2); color: var(--go-on-surface-3); transition: all var(--go-dur-fast) var(--go-ease-standard);
}
.nav-dot.ok { background: var(--go-success); color: var(--go-on-success); }
.nav-dot.bad { background: var(--go-danger); color: var(--go-on-danger); }
.nav-dot.pend { background: var(--go-warning); color: var(--go-on-warning); }
.nav-dot.cur { background: var(--go-primary); color: var(--go-on-primary); box-shadow: 0 4rpx 14rpx color-mix(in srgb, var(--go-primary) 32%, transparent); }
</style>
