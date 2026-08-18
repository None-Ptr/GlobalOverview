<template>
  <uni-icons
    class="go-icon"
    :class="{ 'go-icon--spin': spin }"
    :type="type"
    :size="iconSize"
    :color="color"
    :aria-label="name"
  />
</template>

<script setup>
// 统一图标组件（基于 uni-icons 图标库）：把项目内自有的 name 映射到 uni-icons 的 type。
// 通过 size(color 默认为 currentColor，跟随父级 CSS color) 控制大小与上色，
// 规避 webview 对自绘 SVG 的渲染问题。class 透传、:size、spin 行为保持一致。
import uniIcons from '@dcloudio/uni-ui/lib/uni-icons/uni-icons.vue'

const props = defineProps({
  name: { type: String, required: true },
  size: { type: [String, Number], default: 24 },         // 默认 24px
  color: { type: String, default: 'currentColor' },       // 跟随父级 color
  strokeWidth: { type: [String, Number], default: 1.8 }, // 兼容旧调用，uni-icons 不使用
  spin: { type: Boolean, default: false },
})

// size 接收 string(如 '56rpx'/'40px') 或 number(默认按 px)
// uni-icons 的 size 为数字(单位 px)，此处把 rpx/px 统一换算为 px 数字
const iconSize = (() => {
  const s = String(props.size)
  if (s.endsWith('rpx')) return Math.round(parseFloat(s) / 2) // rpx → px (750 设计宽)
  if (s.endsWith('px')) return parseFloat(s)
  return parseFloat(s) || 24
})()

// name → uni-icons type 映射（已与 uniicons_file.ts 的 fontData 逐项校验）
// 字体内不存在 → 替换为已存在的（否则渲染为空白方块）：
//   book          → compose   （笔记/书本感）
//   bookmark      → star      （收藏/书签）
//   arrowleft     → arrow-left（注意是字符 - 而非驼峰）
const map = {
  reading: 'list',           // 阅读：列表感
  plan: 'calendar',
  words: 'list',
  mine: 'person',
  'arrow-left': 'arrow-left',
  plus: 'plus',
  menu: 'bars',
  bookmark: 'star',
  settings: 'gear',
  robot: 'chatbubble',
  trash: 'trash',
  target: 'location',
  search: 'search',
  'book-check': 'checkbox-filled',
  broom: 'clear',
  alert: 'info',
  book: 'compose',
  refresh: 'refresh',
  copy: 'paperclip',
  check: 'checkmarkempty',
  export: 'upload',
  star: 'star',
  brain: 'color',
  translate: 'compose', // 翻译/语言接口
  tts: 'sound',          // 朗读/语音
  stop: 'closeempty',    // 停止
}

const type = map[props.name] || 'help'
</script>

<style scoped lang="scss">
.go-icon {
  display: inline-block;
  vertical-align: middle;
  line-height: 1;
}
.go-icon--spin {
  animation: go-icon-spin 0.9s linear infinite;
}
@keyframes go-icon-spin {
  to { transform: rotate(360deg); }
}
@media (prefers-reduced-motion: reduce) {
  .go-icon--spin { animation: none; }
}
</style>
