<template>
    <view class="go-spinner" :style="boxStyle" role="progressbar" aria-label="加载中">
    <view class="go-spinner__ring go-spinner__ring--cw"></view>
    <view class="go-spinner__ring go-spinner__ring--ccw"></view>
  </view>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  size: { type: Number, default: 56 }, // rpx
})

const boxStyle = computed(() => ({
  width: props.size + 'rpx',
  height: props.size + 'rpx',
}))
</script>

<style scoped lang="scss">
.go-spinner {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.go-spinner__ring {
  position: absolute;
  inset: 0;
  border-radius: 50%;
  border: 4rpx solid transparent;
  box-sizing: border-box;
}
/* 顺时针：用 primary 渐变弧 */
.go-spinner__ring--cw {
  border-top-color: var(--go-primary);
  border-right-color: color-mix(in srgb, var(--go-primary) 32%, transparent);
  animation: go-spin-cw 1.05s cubic-bezier(0.65, 0, 0.35, 1) infinite;
}
/* 逆时针：用 tertiary 渐变弧，形成双环交错 */
.go-spinner__ring--ccw {
  inset: 16%;
  border-bottom-color: var(--go-tertiary);
  border-left-color: color-mix(in srgb, var(--go-tertiary) 32%, transparent);
  animation: go-spin-ccw 0.8s cubic-bezier(0.65, 0, 0.35, 1) infinite;
}
@keyframes go-spin-cw {
  to { transform: rotate(360deg); }
}
@keyframes go-spin-ccw {
  to { transform: rotate(-360deg); }
}
@media (prefers-reduced-motion: reduce) {
  .go-spinner__ring--cw,
  .go-spinner__ring--ccw { animation-duration: 2.4s; }
}
</style>
