<template>
  <view class="page">
    <view class="go-appbar">
      <text class="go-appbar__title">生词本</text>
      <view class="go-appbar__actions">
        <text v-if="words.length" class="clear" @click="clearAll">清空</text>
      </view>
    </view>
    <view class="words-meta">{{ words.length }} 词</view>

    <view class="modes">
      <view class="mode" :class="{ on: mode === 'all' }" @click="mode = 'all'">全部</view>
      <view class="mode" :class="{ on: mode === 'word' }" @click="mode = 'word'">单词</view>
      <view class="mode" :class="{ on: mode === 'phrase' }" @click="mode = 'phrase'">短语</view>
    </view>

    <view v-if="filtered.length" class="list">
      <view
        v-for="(w, idx) in filtered"
        :key="w.word + '|' + w.mode"
        class="card go-enter"
        :style="{ '--i': idx }"
        @click="review(w)"
      >
        <view class="card-main">
          <text class="word">{{ w.word }}</text>
          <text class="tag" :class="'tag--' + w.mode">{{ w.mode === 'phrase' ? '短语' : (w.mode === 'en2en' ? '英英' : '中英') }}</text>
          <text class="preview">{{ previewOf(w.result) }}</text>
        </view>
        <text class="del" @click.stop="remove(w)">删除</text>
      </view>
    </view>

    <view v-else class="empty">
      <view class="empty-ico"><GoIcon name="book" :size="'64rpx'" /></view>
      <text class="empty-msg">还没有生词。在正文里点词或长按选区即可收藏。</text>
    </view>

    <!-- 复习浮层 -->
    <view v-if="active" class="mask" @click="active = null">
      <view class="sheet" @click.stop>
        <text class="sheet-word">{{ active.word }}</text>
        <view class="sheet-body">
          <text class="sheet-text">{{ detailOf(active.result) }}</text>
        </view>
        <view class="sheet-actions">
          <view class="sheet-btn" @click="active = null">关闭</view>
        </view>
      </view>
    </view>
  </view>
  <BottomNav />
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'
import { loadWordCache, removeWordCache, clearWordCache } from '@/utils/word.js'
import GoIcon from '@/components/GoIcon.vue'
import BottomNav from '@/components/BottomNav.vue'

const store = useAppStore()
const transition = useTransition('tab')
onMounted(() => { transition.onEnter(); uni.$emit('nav:active', 'words') })

const words = ref([])
const mode = ref('all')
const active = ref(null)

const filtered = computed(() => {
  if (mode.value === 'all') return words.value
  if (mode.value === 'word') {
    // word_cache 的 mode 取值为 en2zh / en2en / phrase，单词类即非 phrase
    return words.value.filter((w) => w.mode !== 'phrase')
  }
  return words.value.filter((w) => w.mode === mode.value)
})

function previewOf(r) {
  if (!r) return ''
  if (r.kind === 'dict') return (r.phonetic ? r.phonetic + '  ' : '') + (r.senses[0] ? r.senses[0].definition : '')
  return String(r.text || '').slice(0, 60)
}
function detailOf(r) {
  if (!r) return ''
  if (r.kind === 'dict') {
    return (r.phonetic ? '音标：' + r.phonetic + '\n\n' : '') +
      (r.senses || []).map((s) => `${s.pos ? '【' + s.pos + '】' : ''}${s.definition}${s.example ? '\n例句：' + s.example : ''}`).join('\n\n')
  }
  return String(r.text || '')
}

function review(w) { active.value = w }

// 返回：可返回上一页则 navigateBack，否则回到底部导航首页（阅读）
function goBack() {
  const pages = getCurrentPages()
  if (pages && pages.length > 1) {
    uni.navigateBack()
  } else {
    uni.switchTab({ url: '/pages/reading/reading' })
  }
}

async function remove(w) {
  await removeWordCache(w.word, w.mode)
  words.value = words.value.filter((x) => !(x.word === w.word && x.mode === w.mode))
}

async function clearAll() {
  uni.showModal({
    title: '清空生词本',
    content: '确定删除全部已收藏的查询记录？',
    success: async (r) => {
      if (r.confirm) {
        await clearWordCache()
        words.value = []
      }
    },
  })
}

onMounted(async () => {
  words.value = await loadWordCache(300)
})
</script>

<style scoped lang="scss">
.page {
  min-height: 100vh;
  background: var(--go-bg);
  padding: calc(var(--go-safe-top) + var(--go-sp-4)) var(--go-sp-4) calc(var(--go-nav-h) + var(--go-safe-bottom));
}
.topbar {
  display: flex;
  align-items: center;
  gap: var(--go-sp-3);
  padding: calc(var(--go-safe-top) + var(--go-sp-2)) 0 var(--go-sp-3);
}
.back-svg { font-size: 40rpx; line-height: 1; }
.words-meta { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); padding: 0 var(--go-sp-2) var(--go-sp-2); }
.clear { font-size: var(--go-fs-body-sm); color: var(--go-danger); font-weight: var(--go-fw-semibold); }
.modes { display: flex; gap: var(--go-sp-3); margin-bottom: var(--go-sp-4); }
.mode {
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  padding: var(--go-sp-2) var(--go-sp-6);
  border-radius: var(--go-r-full);
  background: var(--go-surface-2);
  transition: background var(--go-dur-fast) var(--go-ease-standard);
}
.mode.on { background: var(--go-primary-95); color: var(--go-primary); font-weight: var(--go-fw-semibold); }
.list { display: flex; flex-direction: column; gap: var(--go-sp-3); }
.card {
  display: flex; align-items: center; gap: var(--go-sp-3);
  padding: var(--go-sp-4) var(--go-sp-5);
  background: var(--go-surface);
  border-radius: var(--go-r-lg);
  box-shadow: var(--go-shadow-1);
  border: 1rpx solid var(--go-outline);
}
.card-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--go-sp-1); }
.word { font-size: var(--go-fs-body); font-weight: var(--go-fw-semibold); color: var(--go-on-surface); }
.tag { align-self: flex-start; font-size: var(--go-fs-cap); padding: 2rpx 12rpx; border-radius: var(--go-r-full); background: var(--go-secondary-container); color: var(--go-on-secondary-container); }
.tag--phrase { background: var(--go-tertiary-container); color: var(--go-on-tertiary-container); }
.tag--en2en { background: var(--go-primary-95); color: var(--go-primary); }
.preview { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.del { font-size: var(--go-fs-meta); color: var(--go-danger); padding: var(--go-sp-2) var(--go-sp-4); flex-shrink: 0; }
.empty { padding: var(--go-sp-16) var(--go-sp-6); text-align: center; color: var(--go-on-surface-3); font-size: var(--go-fs-body-sm); line-height: var(--go-lh-normal); display: flex; flex-direction: column; align-items: center; gap: var(--go-sp-4); background: var(--go-surface); border-radius: var(--go-r-lg); box-shadow: var(--go-elev-1); }
.empty-ico {
  width: 120rpx; height: 120rpx; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 56rpx; background: var(--go-surface-2); box-shadow: var(--go-shadow-1);
  :deep(.go-icon) { font-size: 56rpx; }
}
.empty-msg { max-width: 72%; line-height: 1.6; }
.mask { position: fixed; inset: 0; background: var(--go-scrim); display: flex; align-items: flex-end; z-index: 50; animation: go-fade-in var(--go-dur-med) var(--go-ease-standard) both; }
.sheet {
  width: 100%;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  padding: var(--go-sp-6) var(--go-sp-6) calc(var(--go-sp-8) + var(--go-safe-bottom));
  animation: go-sheet-up var(--go-dur-med) var(--go-ease-emphasized) both;
  box-shadow: var(--go-shadow-3);
}
.sheet-word { font-size: var(--go-fs-h1); font-weight: var(--go-fw-bold); color: var(--go-on-surface); }
.sheet-body { margin: var(--go-sp-4) 0; max-height: 50vh; overflow-y: auto; }
.sheet-text { font-size: var(--go-fs-body-sm); color: var(--go-on-surface); line-height: var(--go-lh-relaxed); white-space: pre-wrap; }
.sheet-actions { display: flex; }
.sheet-btn {
  flex: 1; text-align: center; padding: var(--go-sp-4); border-radius: var(--go-r-md);
  background: var(--go-primary); color: var(--go-on-primary); font-weight: var(--go-fw-semibold); font-size: var(--go-fs-body-sm);
  &:active { opacity: .9; }
}

@keyframes go-fade-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes go-sheet-up { from { transform: translateY(100%); } to { transform: translateY(0); } }
</style>
