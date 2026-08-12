<template>
  <view class="page">
    <!-- M3 TopAppBar -->
    <view class="go-appbar floating">
      <text class="go-appbar__title">出题计划</text>
    </view>

    <!-- M3 预设 / 模型选择（SegmentedButton） -->
    <view class="controls">
      <view class="seg-row">
        <text class="seg-label">预设</text>
        <scroll-view scroll-x class="go-seg">
          <view class="go-segmented">
            <view
              v-for="(p, i) in presets"
              :key="p.id"
              class="go-segmented__item"
              :class="{ active: activePreset && activePreset.id === p.id }"
              @click="activePreset = p; /* 同步 picker 语义 */ onPresetIdx(i)"
            >{{ p.name }}</view>
            <view class="go-segmented__item" @click="openPresetForm">＋</view>
          </view>
        </scroll-view>
      </view>
      <view class="seg-row">
        <text class="seg-label">模型</text>
        <scroll-view scroll-x class="go-seg">
          <view class="go-segmented">
            <view
              v-for="(p, i) in profiles"
              :key="p.id"
              class="go-segmented__item"
              :class="{ active: activeProfile && activeProfile.id === p.id }"
              @click="onProfileIdx(i)"
            >{{ p.name }}</view>
          </view>
        </scroll-view>
      </view>
      <view class="goal-row">
        <text class="seg-label">全局目标</text>
        <picker :range="examKeys" @change="onGoal">
          <view class="goal-val">{{ store.globalGoal }}</view>
        </picker>
        <text class="goal-tip">预设未指定考试时按此难度出题</text>
      </view>
    </view>

    <view v-if="loading" class="state">
      <PolySpinner />
      <text class="state-msg">加载中…</text>
    </view>
    <scroll-view v-else scroll-y class="list">
      <view v-if="!articles.length" class="state">
        <view class="state-ico"><GoIcon name="book" size="72rpx" /></view>
        <text class="state-msg">阅读页点「加入计划」可在此生成题目</text>
      </view>
      <view v-for="(a, idx) in articles" :key="a.id" class="card go-pressable go-enter" :style="{ '--i': idx }">
        <view class="card-top">
          <text class="card-title">{{ a.title }}</text>
          <text class="gen" @click="genSet(a)">生成题集</text>
        </view>
        <text class="card-meta">{{ a.wordCount || 0 }} 词</text>
        <view class="sets">
          <view
            v-for="s in setsByArticle(a.id)"
            :key="s.id"
            class="set-chip"
            @click="openSet(s)"
          >题集 #{{ s.id }} · {{ s.qcount }}题</view>
          <text v-if="!setsByArticle(a.id).length" class="no-set">尚无题集</text>
          <text v-else class="set-export" @click="exportSet(a)">导出</text>
        </view>
        <view class="card-ops">
          <text class="op-remove" @click="removeFromPlan(a.id)">移出计划</text>
        </view>
      </view>
    </scroll-view>

    <view v-if="genning" class="loading-mask"><text>生成中…</text></view>

    <!-- 预设编辑弹层 -->
    <view v-if="showPreset" class="mask" @click="showPreset = false" @touchmove.stop.prevent>
      <view class="preset-card" @click.stop>
        <text class="preset-title">新建出题预设</text>
        <input class="go-field" v-model="presetForm.name" placeholder="预设名称" placeholder-class="go-field__ph" />
        <text class="lbl">对标考试</text>
        <picker :range="examKeys" @change="(e)=>presetForm.exam=examKeys[e.detail.value]">
          <view class="go-field">{{ presetForm.exam }}</view>
        </picker>
        <text class="lbl">题型（逗号分隔）</text>
        <input class="go-field" v-model="presetForm.types" placeholder="choice,fill,shortAnswer" placeholder-class="go-field__ph" />
        <text class="lbl">考察重点</text>
        <input class="go-field" v-model="presetForm.focus" placeholder="词汇、推理" placeholder-class="go-field__ph" />
        <text class="lbl">解析语言</text>
        <picker :range="['zh','en']" @change="(e)=>presetForm.analysisLang=['zh','en'][e.detail.value]">
          <view class="go-field">{{ presetForm.analysisLang === 'en' ? 'English' : '中文' }}</view>
        </picker>
        <text class="lbl">题目数量</text>
        <input class="go-field" v-model="presetForm.count" type="number" placeholder-class="go-field__ph" />
        <view class="preset-actions">
          <text v-if="activePreset" class="pc-del" @click="deletePreset">删除当前</text>
          <text class="pc-cancel" @click="showPreset = false">取消</text>
          <text class="pc-ok" @click="savePreset">保存</text>
        </view>
      </view>
    </view>
  </view>
  <BottomNav />
</template>

<script setup>
import { ref, computed } from 'vue'
import PolySpinner from '@/components/PolySpinner.vue'
import { onShow } from '@dcloudio/uni-app'
import BottomNav from '@/components/BottomNav.vue'
import GoIcon from '@/components/GoIcon.vue'
import { db } from '@/utils/db.js'
import { generateSet, EXAM_MAP } from '@/utils/quiz.js'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'

const { sqlVal } = db
const store = useAppStore()
const transition = useTransition('tab')
onShow(() => { transition.onEnter(); uni.$emit('nav:active', 'plan') })

const articles = ref([])
const sets = ref([])
const presets = ref([])
const activePreset = ref(null)
const genning = ref(false)
const showPreset = ref(false)
const loading = ref(true)

const DEFAULT_FORM = { name: '', exam: 'CET6', types: 'choice,fill', focus: '词汇、句意理解', analysisLang: 'zh', count: 5 }
const presetForm = ref({ ...DEFAULT_FORM })
const examKeys = Object.keys(EXAM_MAP)

const profiles = computed(() => store.llmProfiles)
const activeProfile = computed(() => store.activeProfile)
const presetNames = computed(() => presets.value.map((p) => p.name))
const profileNames = computed(() => profiles.value.map((p) => p.name))

function setsByArticle(id) {
  return sets.value.filter((s) => String(s.articleId) === String(id))
}

async function load() {
  loading.value = true
  try {
    await db.init()
    store.initProfiles()
    store.initGoal()

    presets.value = await db.select('SELECT * FROM presets ORDER BY id ASC')
    if (presets.value.length && !activePreset.value) activePreset.value = presets.value[0]

    const plan = await db.select('SELECT articleId FROM plan_items')
    const ids = plan.map((p) => String(p.articleId))
    const all = await db.select('SELECT id, title, plainText, wordCount FROM articles')
    articles.value = all.filter((a) => ids.includes(String(a.id)))
    await loadSets()
  } catch (e) {
    uni.showToast({ title: e.message || '加载失败', icon: 'none' })
  } finally {
    loading.value = false
  }
}

async function loadSets() {
  sets.value = await db.select(
    'SELECT s.id, s.articleId, COUNT(q.id) AS qcount FROM question_sets s '
    + 'LEFT JOIN questions q ON q.setId = s.id GROUP BY s.id'
  )
}

function onPreset(e) { activePreset.value = presets.value[e.detail.value] }
function onPresetIdx(i) { activePreset.value = presets.value[i] }
function onProfile(e) {
  const p = profiles.value[e.detail.value]
  if (p) store.setActiveProfile(p.id)
}
function onProfileIdx(i) {
  const p = profiles.value[i]
  if (p) store.setActiveProfile(p.id)
}
function onGoal(e) { store.setGoal(examKeys[e.detail.value]) }

function openPresetForm() {
  presetForm.value = { ...DEFAULT_FORM, exam: store.globalGoal }
  showPreset.value = true
}

function cfgOf(p) {
  if (p && p.config) {
    try { return JSON.parse(p.config) } catch (e) { /* 落到下面兜底 */ }
  }
  return { ...DEFAULT_FORM, types: DEFAULT_FORM.types.split(',') }
}

async function genSet(article) {
  // 重新同步模型列表（可能刚在“我的”页新增/编辑）
  store.initProfiles()
  const profile = activeProfile.value || (profiles.value && profiles.value[0])
  if (!profile) {
    uni.showModal({
      title: '未配置模型',
      content: '出题需要大模型 API。请先去「我的 → LLM 模型配置」添加并保存一个模型。',
      confirmText: '去配置',
      cancelText: '取消',
      success: (r) => { if (r.confirm) uni.switchTab({ url: '/pages/mine/mine' }) },
    })
    return
  }
  genning.value = true
  try {
    const cfg = activePreset.value ? cfgOf(activePreset.value) : { ...DEFAULT_FORM, types: ['choice', 'fill'] }
    // 预设未指定 exam 时，用全局目标兜底
    cfg.globalGoal = store.globalGoal
    const res = await generateSet({
      article,
      preset: cfg,
      profile,
      count: Number(cfg.count) || 5,
    })
    await loadSets()
    uni.showToast({
      title: `生成 ${res.ok} 题${res.failed ? '，' + res.failed + ' 题失败' : ''}`,
      icon: 'none',
    })
  } catch (e) {
    uni.showModal({ title: '生成失败', content: e.message || '未知错误', showCancel: false })
  } finally {
    genning.value = false
  }
}

function openSet(s) { uni.navigateTo({ url: `/pages/quiz/quiz?setId=${s.id}` }) }
function exportSet(a) { uni.navigateTo({ url: `/pages/export/export?articleId=${a.id}` }) }

function removeFromPlan(id) {
  uni.showModal({
    title: '移出计划',
    content: '题集与错题记录会保留。',
    success: async (r) => {
      if (!r.confirm) return
      await db.execute(`DELETE FROM plan_items WHERE articleId = ${sqlVal(id)}`)
      await load()
    },
  })
}

async function savePreset() {
  const f = presetForm.value
  if (!f.name.trim()) { uni.showToast({ title: '请填写名称', icon: 'none' }); return }
  const config = JSON.stringify({
    exam: f.exam,
    types: String(f.types).split(',').map((x) => x.trim()).filter(Boolean),
    focus: f.focus,
    analysisLang: f.analysisLang,
    count: Number(f.count) || 5,
  })
  try {
    const id = await db.insertReturnId(
      `INSERT INTO presets (name, config) VALUES (${sqlVal(f.name.trim())}, ${sqlVal(config)})`
    )
    presets.value = await db.select('SELECT * FROM presets ORDER BY id ASC')
    activePreset.value = presets.value.find((p) => String(p.id) === String(id)) || presets.value[0]
    showPreset.value = false
    presetForm.value = { ...DEFAULT_FORM }
  } catch (e) {
    uni.showToast({ title: e.message || '保存失败', icon: 'none' })
  }
}

async function deletePreset() {
  if (!activePreset.value) return
  await db.execute(`DELETE FROM presets WHERE id = ${sqlVal(activePreset.value.id)}`)
  presets.value = await db.select('SELECT * FROM presets ORDER BY id ASC')
  activePreset.value = presets.value.length ? presets.value[0] : null
  showPreset.value = false
}

onShow(load)
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
}
.controls {
  padding: var(--go-sp-4) var(--go-sp-5) var(--go-sp-3);
  display: flex;
  flex-direction: column;
  gap: var(--go-sp-3);
  border-bottom: 1rpx solid var(--go-outline);
  background: var(--go-bg);
}
.seg-row { display: flex; align-items: center; gap: var(--go-sp-4); }
.seg-label { font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); flex: 0 0 auto; width: 84rpx; }
.go-seg { flex: 1; overflow-x: auto; }
.goal-row { display: flex; align-items: center; gap: var(--go-sp-4); padding-top: var(--go-sp-1); }
.goal-val {
  font-size: var(--go-fs-body-sm);
  color: var(--go-primary);
  font-weight: var(--go-fw-semibold);
  background: var(--go-primary-95);
  padding: var(--go-sp-2) var(--go-sp-4);
  border-radius: var(--go-r-full);
}
.goal-tip { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); flex: 1; text-align: right; }
.list { flex: 1; padding: var(--go-sp-4) var(--go-sp-5); }
.state {
  text-align: center; color: var(--go-on-surface-3); margin-top: var(--go-sp-16);
  font-size: var(--go-fs-body-sm); display: flex; flex-direction: column; align-items: center; gap: var(--go-sp-4);
  background: var(--go-surface); border-radius: var(--go-r-lg); box-shadow: var(--go-elev-1);
  padding: var(--go-sp-8) var(--go-sp-6);
}
.state-ico {
  width: 120rpx; height: 120rpx; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  background: var(--go-surface-2); box-shadow: var(--go-shadow-1);
  color: var(--go-on-surface-3);
}
.state-msg { max-width: 70%; line-height: 1.6; }
.card {
  border-radius: var(--go-r-lg);
  padding: var(--go-sp-5) var(--go-sp-5);
  margin-bottom: var(--go-sp-4);
  background: var(--go-surface);
  box-shadow: var(--go-shadow-1);
  border: 1rpx solid var(--go-outline);
  transition: background var(--go-dur-med) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { background: var(--go-surface-1); transform: scale(.99); }
}
.card-top { display: flex; justify-content: space-between; align-items: center; gap: var(--go-sp-4); }
.card-title { font-size: var(--go-fs-body); font-weight: var(--go-fw-semibold); flex: 1; color: var(--go-on-surface); line-height: var(--go-lh-snug); }
.card-meta { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-2); display: block; }
.gen {
  color: var(--go-on-primary);
  font-size: var(--go-fs-meta);
  background: var(--go-primary);
  padding: var(--go-sp-2) var(--go-sp-5);
  border-radius: var(--go-r-full);
  flex: none;
  transition: transform var(--go-dur-fast) var(--go-ease-standard), opacity var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(.94); opacity: .9; }
}
.sets { margin-top: var(--go-sp-4); display: flex; flex-wrap: wrap; gap: var(--go-sp-3); align-items: center; }
.set-chip {
  background: var(--go-surface-2);
  padding: var(--go-sp-2) var(--go-sp-4);
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-2);
  transition: transform var(--go-dur-fast) var(--go-ease-standard), background var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(.94); background: var(--go-sel); }
}
.no-set { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }
.set-export { font-size: var(--go-fs-meta); color: var(--go-primary); }
.set-export:active { opacity: .5; }
.card-ops { margin-top: var(--go-sp-4); padding-top: var(--go-sp-4); border-top: 1rpx solid var(--go-outline); }
.op-remove { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }
.op-remove:active { opacity: .5; }
.loading-mask {
  position: fixed; inset: 0; background: var(--go-scrim);
  display: flex; align-items: center; justify-content: center; color: var(--go-on-primary); z-index: 200;
  animation: go-fade-in var(--go-dur-med) var(--go-ease-standard) both;
}
.mask {
  position: fixed; inset: 0; background: var(--go-scrim);
  display: flex; align-items: flex-end; justify-content: center; z-index: 100;
  animation: go-fade-in var(--go-dur-med) var(--go-ease-standard) both;
}
.preset-card {
  width: 100%;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  padding: var(--go-sp-6) calc(var(--go-sp-6) + env(safe-area-inset-right))
    calc(var(--go-sp-6) + env(safe-area-inset-bottom)) calc(var(--go-sp-6) + env(safe-area-inset-left));
  animation: go-sheet-up var(--go-dur-med) var(--go-ease-emphasized) both;
  box-shadow: var(--go-shadow-3);
  position: relative; z-index: 101;
}
.state-msg { color: var(--go-on-surface-3); font-size: var(--go-fs-body-sm); }
.preset-title { font-size: var(--go-fs-h1); font-weight: var(--go-fw-semibold); text-align: center; display: block; margin-bottom: var(--go-sp-6); color: var(--go-on-surface); }
.lbl { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-3); display: block; }
.go-field {
  font-size: var(--go-fs-body-sm);
  color: var(--go-on-surface);
  padding: var(--go-sp-3);
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-md);
  background: var(--go-surface-2);
  margin-top: var(--go-sp-2);
}
.preset-actions {
  display: flex; justify-content: center; align-items: center; margin-top: var(--go-sp-6);
  border-top: 1rpx solid var(--go-outline); padding-top: var(--go-sp-5); gap: var(--go-sp-6);
}
.pc-del { color: var(--go-danger); font-size: var(--go-fs-body-sm); margin-right: auto; }
.pc-cancel { color: var(--go-on-surface-3); margin-right: var(--go-sp-6); font-size: var(--go-fs-body); }
.pc-ok { color: var(--go-primary); font-size: var(--go-fs-body); font-weight: var(--go-fw-semibold); }

@keyframes go-fade-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes go-sheet-up { from { transform: translateY(100%); } to { transform: translateY(0); } }
</style>
