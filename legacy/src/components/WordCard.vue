<template>
  <view v-if="visible" class="mask go-fade-in" @click="close">
    <view class="card" @click.stop>
      <view class="card-head">
        <text class="word">{{ displayWord }}</text>
        <view class="modes seg">
          <text class="mode seg-item speak" @click="emit('speak', props.word)">朗读</text>
          <template v-if="!isPhrase && !translateDisabled">
            <text class="mode seg-item" :class="{ on: mode === 'en2zh' }" @click="switchMode('en2zh')">中</text>
            <text class="mode seg-item" :class="{ on: mode === 'en2en' }" @click="switchMode('en2en')">英</text>
          </template>
          <text v-else class="phrase-tag">选区解析</text>
        </view>
        <text class="close btn-close" @click="close">×</text>
      </view>

      <scroll-view scroll-y class="body">
          <view v-if="loading" class="loading">
            <PolySpinner />
            <text>查询中…</text>
          </view>
          <view v-else-if="error" class="error">
            <text class="error-msg">{{ error }}</text>
            <text class="retry btn-text" @click="doLookup">重试</text>
          </view>

        <view v-else-if="result && result.kind === 'dict'" class="en">
          <text v-if="result.phonetic" class="phonetic">{{ result.phonetic }}</text>
          <view v-for="(s, i) in result.senses" :key="i" class="entry">
            <text class="pos">{{ s.pos }}</text>
            <text class="def">{{ s.definition }}</text>
            <text v-if="s.example" class="example">e.g. {{ s.example }}</text>
          </view>
        </view>

        <view v-else-if="!translateDisabled && result && result.text && String(result.text).trim()" class="zh">
          <text class="def">{{ result.text }}</text>
        </view>

        <view v-else class="error">
          <text class="error-msg">未获取到释义，轻触外部关闭后重试</text>
        </view>
      </scroll-view>
    </view>
  </view>
</template>

<script setup>
import { ref, computed, watch, nextTick, onErrorCaptured } from 'vue'
import { lookupWord, queryKind } from '@/utils/word.js'
import { wordCardIn, wordCardOut } from '@/utils/anim.js'
import PolySpinner from '@/components/PolySpinner.vue'

// APP 端页面运行于 webview，存在 DOM，可直接驱动动画。
// 但是某些 5+App Runtime / 小程序壳下 document 不存在；
// 若 document 不存在则所有 .querySelector 都会抛 `Cannot read property 'querySelector' of undefined`
// ——这里用 typeof + 可选链兜底，确保点词后链路不中断
function findMask() {
  if (typeof document === 'undefined' || !document || !document.querySelector) return null
  return document.querySelector('.mask')
}

onErrorCaptured((e) => {
  uni.showToast({ title: 'wc ERR ' + (e && e.message ? e.message : '').slice(0, 50), icon: 'none', duration: 6000 })
  return false
})

const props = defineProps({
  visible: Boolean,
  word: String,
  context: { type: String, default: '' },
  translateDisabled: { type: Boolean, default: false },
})
const emit = defineEmits(['close', 'speak'])

const mode = ref(props.translateDisabled ? 'en2en' : 'en2zh')
// 禁用翻译时，强制保持 en2en，避免 prop 变化后 mode 残留 en2zh
watch(() => props.translateDisabled, (d) => {
  if (d) mode.value = 'en2en'
})
const loading = ref(false)
const error = ref('')
const result = ref(null)

const isPhrase = computed(() => queryKind(props.word) === 'phrase')
const displayWord = computed(() => {
  const w = String(props.word || '')
  return w.length > 40 ? w.slice(0, 40) + '…' : w
})

watch(() => props.visible, (v) => {
  if (v && props.word) {
    doLookup()
    nextTick(() => {
      const root = findMask()
      // 用可选链兜底：root.querySelector 即使因元素被替换变 undefined 也不会抛
      const card = root && root.querySelector && root.querySelector('.card')
      if (card && root) wordCardIn(card, root)
    })
  }
})
watch(() => props.word, () => { if (props.visible) doLookup() })

function switchMode(m) {
  if (props.translateDisabled) return
  if (mode.value === m) return
  mode.value = m
  doLookup()
}

async function doLookup() {
  loading.value = true
  error.value = ''
  result.value = null
  // 原文页禁用翻译：单词/短语均不调用任何查询引擎（包括英文词典 en2en），直接提示
  if (props.translateDisabled) {
    loading.value = false
    error.value = '原文页已禁用翻译'
    return
  }
  // 组件级超时兜底：真机 webview 在网络异常时可能既不 success 也不 fail，
  // 导致 lookupWord 永久挂起、蒙层卡死。这里强制在 15s 后给出反馈。
  const timer = setTimeout(() => {
    if (loading.value) error.value = '查询超时，请检查网络后重试'
  }, 15000)
  try {
    const r = await lookupWord(props.word, mode.value, null, props.context)
    // 空结果（LLM / 翻译引擎返回空串）若不当作失败，模板会渲染出空白卡片，
    // 表现为「蒙层变暗但无翻译、看似无法操作」。
    if (!r || (r.kind === 'text' && !String(r.text || '').trim())
        || (r.kind === 'dict' && (!r.senses || !r.senses.length))) {
      error.value = '未获取到释义，请重试'
    } else {
      result.value = r
    }
  } catch (e) {
    error.value = e.message || '查询失败'
  } finally {
    clearTimeout(timer)
    loading.value = false
  }
}

function close() {
  const root = findMask()
  if (!root) { emit('close'); return }
  // 同样用可选链兜底，避免同一时刻元素被替换时 root.querySelector undefined 抛错
  const card = root.querySelector ? root.querySelector('.card') : null
  // 若 card 取不到（极端情况下元素已被替换），直接兜底关闭，避免蒙层卡死无法退出
  if (!card) { emit('close'); return }
  wordCardOut(card, root, () => emit('close'))
}
</script>

<style scoped lang="scss">
.mask {
  position: fixed; inset: 0; background: var(--go-scrim);
  display: flex; align-items: flex-end; z-index: 100;
}
.card {
  width: 100%;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  height: 66vh;          /* 显式给高度，避免 card 没有高度只剩 mask 显示 */
  max-height: 66vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: var(--go-shadow-3);
}
/* scroll-view 是 uni-app 内置组件，其根元素不会继承父 scoped 的 data-v 属性，
   因此原本的 .body { flex: 1 } 无法生效，导致 scroll-view 占 0 高度、card 内容清空。
   这里用 :deep() 显式穿透到子组件根 */
:deep(.body), .body {
  display: block;
  padding: var(--go-sp-4) var(--go-sp-6) var(--go-sp-8);
  flex: 1 1 auto;
  min-height: 0;          /* flex 子项允许收缩，否则高度被内容撑开 */
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}
.card-head {
  display: flex; align-items: center; padding: var(--go-sp-5) var(--go-sp-6) var(--go-sp-3);
  border-bottom: 1rpx solid var(--go-outline);
}
.word { font-size: var(--go-fs-h1); font-weight: var(--go-fw-semibold); flex: 1; line-height: 1.4; color: var(--go-on-surface); }
.phrase-tag {
  font-size: var(--go-fs-meta);
  color: var(--go-on-tertiary-container);
  background: var(--go-tertiary-container);
  padding: var(--go-sp-1) var(--go-sp-4);
  border-radius: var(--go-r-full);
}
.modes { display: flex; align-items: center; gap: var(--go-sp-2); }
.mode { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); padding: var(--go-sp-1) var(--go-sp-3); border-radius: var(--go-r-full); }
.mode.on { color: var(--go-on-primary); background: var(--go-primary); }
.mode.speak { color: var(--go-on-primary); background: var(--go-primary); font-weight: var(--go-fw-medium); }
.body { padding: var(--go-sp-4) var(--go-sp-6) var(--go-sp-8); flex: 1; }
.loading {
  color: var(--go-on-surface-3);
  font-size: var(--go-fs-body-sm);
  padding: var(--go-sp-6) 0;
  display: flex; flex-direction: column; align-items: center; gap: var(--go-sp-3);
}
.error { padding: var(--go-sp-4) 0; display: flex; flex-direction: column; align-items: flex-start; gap: var(--go-sp-3); }
.error-msg { color: var(--go-danger); font-size: var(--go-fs-body-sm); }
.phonetic { display: block; color: var(--go-on-surface-3); font-size: var(--go-fs-body-sm); margin-bottom: var(--go-sp-3); letter-spacing: .3rpx; }
.entry {
  margin-bottom: var(--go-sp-3);
  padding: var(--go-sp-3) var(--go-sp-4);
  background: var(--go-surface-2);
  border-radius: var(--go-r-md);
  border-left: 4rpx solid var(--go-primary);
}
.pos { color: var(--go-primary); font-size: var(--go-fs-meta); margin-right: var(--go-sp-2); font-weight: var(--go-fw-semibold); }
.def { display: block; font-size: var(--go-fs-body-sm); color: var(--go-on-surface); line-height: var(--go-lh-normal); }
.example { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); margin-top: var(--go-sp-1); }
.zh .def { font-size: var(--go-fs-body); line-height: var(--go-lh-relaxed); color: var(--go-on-surface); white-space: pre-wrap; }
</style>
