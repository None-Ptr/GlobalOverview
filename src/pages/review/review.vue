<template>
  <view class="page">
    <view class="go-appbar">
      <view class="back" @click="goBack"><GoIcon name="arrow-left" :size="'44rpx'" /></view>
      <text class="go-appbar__title">复习</text>
      <view class="go-appbar__actions"><text class="cnt">{{ cards.length }} 张</text></view>
    </view>

    <view v-if="card" class="rev">
      <view class="rev-card" @click="revealed = !revealed">
        <text class="rev-word">{{ card.head }}</text>
        <view v-if="revealed" class="rev-detail">
          <text v-if="card.zh" class="rev-zh">{{ card.zh }}</text>
          <view v-if="card.sentence" class="rev-sentence">“{{ card.sentence }}”</view>
        </view>
        <view v-else class="rev-hint">点击显示释义</view>
      </view>

      <view class="grades">
        <view class="grade grade--again" @click="answer(1)">忘了</view>
        <view class="grade grade--hard" @click="answer(2)">模糊</view>
        <view class="grade grade--good" @click="answer(3)">记得</view>
        <view class="grade grade--easy" @click="answer(4)">轻松</view>
      </view>
    </view>

    <view v-else class="empty">
      <view class="empty-ico"><GoIcon name="check" :size="'64rpx'" /></view>
      <text class="empty-msg">太棒了，暂时没有待复习的卡片。</text>
      <view class="empty-back" @click="goBack">返回</view>
    </view>
  </view>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { getDueCards, scheduleReview, getOccurrence, syncHeadsFromCache } from '@/utils/vocab.js'
import { loadWordCache } from '@/utils/word.js'
import GoIcon from '@/components/GoIcon.vue'

const cards = ref([])
const idx = ref(0)
const revealed = ref(false)
const card = ref(null)
let wcMap = new Map()

async function load() {
  await syncHeadsFromCache()
  const due = await getDueCards(50)
  cards.value = due || []
  idx.value = 0
  const wc = await loadWordCache(1000)
  wcMap = new Map()
  for (const w of (wc || [])) {
    const k = w.lemma || w.word
    if (!wcMap.has(k)) wcMap.set(k, w)
  }
  await showCurrent()
}

async function showCurrent() {
  revealed.value = false
  const c = cards.value[idx.value]
  if (!c) { card.value = null; return }
  const hit = wcMap.get(c.head)
  let zh = ''
  if (hit && hit.result) {
    if (hit.result.kind === 'dict') {
      zh = (hit.result.senses && hit.result.senses[0] && hit.result.senses[0].definition) || ''
    } else if (hit.result.text) {
      zh = hit.result.text
    }
  }
  const occs = await getOccurrence(c.head)
  const sentence = (occs && occs[0] && occs[0].sentence) || ''
  card.value = { head: c.head, zh, sentence }
}

async function answer(g) {
  const c = cards.value[idx.value]
  if (!c) return
  await scheduleReview(c.head, g)
  idx.value++
  if (idx.value >= cards.value.length) {
    await load()
  } else {
    await showCurrent()
  }
}

function goBack() {
  uni.navigateBack().catch(() => uni.reLaunch({ url: '/pages/home/home' }))
}

onMounted(load)
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  min-height: 100vh;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
  display: flex;
  flex-direction: column;
}
.back {
  width: 56rpx;
  display: flex;
  align-items: center;
  color: var(--go-on-surface);
}
.cnt { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); }

.rev {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: var(--go-sp-6);
}
.rev-card {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--go-sp-6);
  padding: var(--go-sp-10);
  border-radius: var(--go-r-xl);
  background: var(--go-surface);
  box-shadow: var(--go-elev-2);
  &:active { background: var(--go-surface-2); }
}
.rev-word { font-size: 64rpx; font-weight: var(--go-fw-bold); color: var(--go-on-surface); }
.rev-hint { font-size: var(--go-fs-body-sm); color: var(--go-on-surface-3); }
.rev-detail { display: flex; flex-direction: column; align-items: center; gap: var(--go-sp-3); width: 100%; }
.rev-zh { font-size: var(--go-fs-body); color: var(--go-on-surface); text-align: center; }
.rev-sentence {
  font-size: var(--go-fs-body-sm);
  color: var(--go-on-surface-3);
  line-height: 1.6;
  text-align: center;
  font-style: italic;
}

.grades {
  display: flex;
  gap: var(--go-sp-3);
  margin-top: var(--go-sp-6);
}
.grade {
  flex: 1;
  text-align: center;
  padding: var(--go-sp-4) 0;
  border-radius: var(--go-r-lg);
  font-size: var(--go-fs-body);
  font-weight: var(--go-fw-semibold);
  color: #fff;
  &:active { transform: scale(0.97); }
  &--again { background: var(--go-danger); }
  &--hard { background: #E08A2B; }
  &--good { background: var(--go-primary); }
  &--easy { background: #2D9E63; }
}

.empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--go-sp-4);
  color: var(--go-on-surface-3);
  &-msg { font-size: var(--go-fs-body); }
  &-back {
    margin-top: var(--go-sp-4);
    padding: var(--go-sp-2) var(--go-sp-8);
    border-radius: var(--go-r-full);
    border: 1rpx solid var(--go-primary);
    color: var(--go-primary);
    font-size: var(--go-fs-body-sm);
  }
}
</style>
