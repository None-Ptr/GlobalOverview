<template>
  <view class="nav">
    <view
      v-for="(t, i) in tabs"
      :key="t.page"
      class="nav-item"
      :class="{ on: active === i }"
      @click="go(t, i)"
    >
      <view class="nav-pill" :class="{ on: active === i }">
        <view class="nav-ico">
          <GoIcon :name="t.key" class="ico" :size="'56rpx'" />
        </view>
        <text class="nav-label" :class="{ on: active === i }">{{ t.text }}</text>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useAppStore } from '@/stores/app.js'
import GoIcon from '@/components/GoIcon.vue'

const store = useAppStore()

const tabs = [
  { key: 'home', text: '首页', page: '/pages/home/home' },
  { key: 'reading', text: '阅读', page: '/pages/reading/reading' },
  { key: 'plan', text: '计划', page: '/pages/plan/plan' },
  { key: 'words', text: '词汇', page: '/pages/vocab/vocab' },
  { key: 'mine', text: '我的', page: '/pages/mine/mine' },
]

const active = ref(0)
function syncActive() {
  const pages = getCurrentPages()
  const cur = pages.length ? pages[pages.length - 1].route : ''
  const idx = tabs.findIndex((t) => cur === t.page.replace(/^\//, ''))
  if (idx >= 0) active.value = idx
}
function onNavActive(key) {
  const idx = tabs.findIndex((t) => t.key === key)
  if (idx >= 0) active.value = idx
}

function go(t, i) {
  if (active.value === i) return
  uni.reLaunch({ url: t.page })
}

onMounted(() => {
  syncActive()
  uni.$on('nav:active', onNavActive)
})
onUnmounted(() => uni.$off('nav:active', onNavActive))
</script>

<style scoped lang="scss">
.nav {
  position: fixed;
  left: 0; right: 0; bottom: 0;
  height: calc(var(--go-nav-h) + var(--go-safe-bottom));
  padding: var(--go-sp-2) var(--go-sp-4) calc(var(--go-sp-2) + var(--go-safe-bottom));
  display: flex;
  align-items: stretch;
  gap: var(--go-sp-2);
  background: color-mix(in srgb, var(--go-surface-raised) 90%, transparent);
  backdrop-filter: saturate(1.5) blur(24rpx);
  -webkit-backdrop-filter: saturate(1.5) blur(24rpx);
  border-top: 1rpx solid var(--go-outline);
  box-shadow: var(--go-nav-shadow);
  z-index: 999;
}
.nav-item {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.nav-pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--go-sp-2);
  height: 64rpx;
  padding: 0 var(--go-sp-5);
  border-radius: var(--go-r-full);
  transition: background var(--go-dur-med) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(0.95); }
}
.nav-item.on .nav-pill {
  background: var(--go-primary-95);
}

.nav-ico {
  width: 44rpx;
  height: 44rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: transform var(--go-dur-med) var(--go-ease-emphasized);
}
.nav-item.on .nav-ico { transform: scale(1.08); }

:deep(.ico) {
  color: var(--go-on-surface-3);
  transition: color var(--go-dur-fast) var(--go-ease-standard),
    transform var(--go-dur-med) var(--go-ease-emphasized);
}
.nav-item.on :deep(.ico) { color: var(--go-primary); }

.nav-label {
  font-size: var(--go-fs-meta);
  line-height: 1.2;
  color: var(--go-on-surface-3);
  font-weight: var(--go-fw-medium);
  transition: color var(--go-dur-fast) var(--go-ease-standard),
    font-weight var(--go-dur-fast) var(--go-ease-standard);
}
.nav-item.on .nav-label {
  color: var(--go-primary);
  font-weight: var(--go-fw-semibold);
}

@media (prefers-reduced-motion: reduce) {
  .nav-pill, .nav-ico, .ico, .nav-label { transition: none !important; }
}
</style>
