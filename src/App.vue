<script setup>
import { onLaunch, onShow, onHide } from '@dcloudio/uni-app'
import { useAppStore } from './stores/app'

const app = useAppStore()

onLaunch(() => {
  app.init()
})
onShow(() => {})
onHide(() => {})
</script>

<style lang="scss">
/* ============ uni-icons 全局注入 ============ */
/* 必须挂在非 scoped <style>：uni-icons 的 @font-face 与 .uniui-* content 映射
   一旦被 scoped 就会被污染，导致图标私有字符 (U+E6xx) 渲染为空白方块。
   同时字体文件通过 vite 静态资源机制被打入 dist/build/app/assets/uniicons.*.ttf */
@import '@dcloudio/uni-ui/lib/uni-icons/uniicons.css';

/* ============ 设计令牌（CSS 变量）============ */
/* 关键：所有 --go-* 变量定义必须且只能在这里。
   之所以不在 uni.scss，是因为 uni-app 会把 uni.scss 注入到
   每个页面的 <style scoped> 中，vue-loader 会给 :root 加上
   page 的 data-v-xxx 属性选择器，变成 :root[data-v-xxx]，
   永远不匹配 <html>，导致页面所有 var(--go-*) 全部落空，
   表现就是图标/文字/按钮全部"消失"。 */

:root {
  /* 主色系（暖陶 Warm Clay · 4 色基调，去亮黄偏奶灰） */
  --go-primary: #b46060;
  --go-primary-95: #fbeee6;
  --go-primary-90: #f3e1d5;
  --go-primary-80: #ebcfbc;
  --go-primary-60: #d99f8f;
  --go-primary-40: #bd7373;
  --go-primary-20: #8a4242;
  --go-on-primary: #fff8f1;
  --go-on-primary-variant: #5a2626;

  --go-secondary: #c98a5e;
  --go-on-secondary: #fff8f1;
  --go-secondary-container: #f5c4a5;
  --go-on-secondary-container: #4d2e1c;

  --go-tertiary: #e08a6a;
  --go-on-tertiary: #fff8f1;
  --go-tertiary-container: #f5d2bb;
  --go-on-tertiary-container: #5a2e1c;

  /* 中性 / 表面 */
  --go-bg: #ece1cf;
  --go-surface: #fcf6ec;
  --go-surface-1: #f6ecdd;
  --go-surface-2: #ecdcc5;
  --go-surface-variant: #e2cfb4;
  --go-surface-raised: #fcf6ec;
  --go-on-surface: #322f2b;
  --go-on-surface-2: #655a50;
  --go-on-surface-3: #958878;
  --go-on-surface-disabled: #bcb0a3;
  --go-outline: #d8c6ad;
  --go-outline-strong: #bca78c;
  --go-on-bg: #322f2b;

  /* 语义色 */
  --go-success: #4f7d4c;
  --go-on-success: #ffffff;
  --go-warning: #a8702f;
  --go-on-warning: #ffffff;
  --go-danger: #a8362a;
  --go-on-danger: #ffffff;
  --go-error: #a8362a;
  --go-info: #b46060;

  --go-bg-glow: radial-gradient(120% 60% at 50% -10%, rgba(180, 96, 96, 0.10), rgba(255, 191, 155, 0.06) 38%, transparent 70%);

  /* 主色加深（AA 对比度 4.5:1+） */
  --go-primary: #a85454;
  --go-on-primary: #ffffff;
  --go-on-primary-variant: #4a201f;
  --go-on-primary-container: #8c3b24;

  --go-sel: rgba(168, 84, 84, 0.16);
  --go-sel-strong: rgba(168, 84, 84, 0.30);
  --go-sel-word: rgba(245, 196, 165, 0.42);
  --go-accent-bar: linear-gradient(180deg, #b46060, #d68a78);

  /* Glassmorphism */
  --go-glass-bg: color-mix(in srgb, var(--go-surface) 58%, rgba(255, 255, 255, 0.32));
  --go-glass-bg-strong: color-mix(in srgb, var(--go-surface) 72%, rgba(255, 255, 255, 0.40));
  --go-glass-border: 1rpx solid rgba(255, 255, 255, 0.20);
  --go-glass-shadow: 0 8rpx 28rpx rgba(80, 50, 30, 0.14), 0 2rpx 8rpx rgba(80, 50, 30, 0.10);
  --go-glass-blur: 24rpx;
  --go-glass-radius: 20rpx;
  --go-glass-glow: radial-gradient(120% 80% at 12% 0%, rgba(255, 255, 255, 0.28), rgba(255, 191, 155, 0.10) 42%, transparent 70%);
  --go-glass-hover: 1.05;

  /* 阴影 */
  --go-elev-1: 0 1rpx 2rpx rgba(60, 40, 24, 0.08), 0 2rpx 6rpx rgba(60, 40, 24, 0.10);
  --go-shadow-1: 0 1rpx 2rpx rgba(60, 40, 24, 0.08), 0 2rpx 6rpx rgba(60, 40, 24, 0.10);
  --go-shadow-2: 0 2rpx 6rpx rgba(60, 40, 24, 0.10), 0 8rpx 20rpx rgba(60, 40, 24, 0.12);
  --go-shadow-3: 0 6rpx 16rpx rgba(60, 40, 24, 0.14), 0 16rpx 36rpx rgba(60, 40, 24, 0.16);
  --go-nav-shadow: 0 -1rpx 0 rgba(60, 40, 24, 0.08), 0 1rpx 8rpx rgba(60, 40, 24, 0.08);

  /* 遮罩 */
  --go-scrim: rgba(60, 45, 30, 0.48);
  --go-overlay: rgba(243, 235, 222, 0.78);
}

:root {
  /* 字体 */
  --go-font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC',
    'Hiragino Sans GB', 'Microsoft YaHei', 'Helvetica Neue', Arial, sans-serif;
  --go-font-read: 'Songti SC', 'STSong', 'SimSun', 'Noto Serif SC', 'Source Han Serif SC',
    'Source Serif 4', Georgia, 'Times New Roman', serif;
  --go-font-mono: 'SF Mono', 'JetBrains Mono', 'Fira Code', Consolas, 'Courier New', monospace;

  /* 字号 */
  --go-fs-display: 40rpx;
  --go-fs-h1: 32rpx;
  --go-fs-h2: 28rpx;
  --go-fs-title: 30rpx;
  --go-fs-body: 30rpx;
  --go-fs-body-sm: 27rpx;
  --go-fs-label: 24rpx;
  --go-fs-meta: 23rpx;
  --go-fs-cap: 21rpx;

  /* 字重 */
  --go-fw-regular: 400;
  --go-fw-medium: 500;
  --go-fw-semibold: 600;
  --go-fw-bold: 700;

  /* 行高 */
  --go-lh-tight: 1.25;
  --go-lh-snug: 1.4;
  --go-lh-normal: 1.6;
  --go-lh-relaxed: 1.75;

  /* 间距 */
  --go-sp-1: 4rpx;
  --go-sp-2: 8rpx;
  --go-sp-3: 12rpx;
  --go-sp-4: 16rpx;
  --go-sp-5: 20rpx;
  --go-sp-6: 24rpx;
  --go-sp-8: 32rpx;
  --go-sp-10: 40rpx;
  --go-sp-12: 48rpx;
  --go-sp-16: 64rpx;

  /* 圆角 */
  --go-r-xs: 8rpx;
  --go-r-sm: 12rpx;
  --go-r-md: 16rpx;
  --go-r-lg: 24rpx;
  --go-r-xl: 32rpx;
  --go-r-full: 999rpx;

  /* 动效 */
  --go-ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --go-ease-emphasized: cubic-bezier(0.2, 0, 0, 1);
  --go-ease-decelerate: cubic-bezier(0, 0, 0, 1);
  --go-dur-fast: 140ms;
  --go-dur-med: 240ms;
  --go-dur-slow: 360ms;

  /* 布局 */
  --go-content-max: 760rpx;
  --go-appbar-h: 104rpx;
  --go-nav-h: 110rpx;
  --go-safe-top: env(safe-area-inset-top, 0rpx);
  --go-safe-bottom: env(safe-area-inset-bottom, 0rpx);
}

/* ============ 全局基础 ============ */
page,
body {
  background: var(--go-bg);
  /* 颗粒磨砂层(最底) + 暖色光晕,营造手作陶质感 */
  background-image:
    url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.04'/%3E%3C/svg%3E"),
    var(--go-bg-glow),
    radial-gradient(60% 40% at 85% 8%, rgba(255, 191, 155, 0.22), transparent 60%),
    radial-gradient(55% 38% at 10% 88%, rgba(180, 96, 96, 0.16), transparent 62%);
  background-repeat: repeat, no-repeat, no-repeat, no-repeat;
  background-size: 160rpx 160rpx, cover, cover, cover;
  background-attachment: fixed, fixed, fixed, fixed;
  color: var(--go-on-surface);
  font-family: var(--go-font-sans);
  font-size: var(--go-fs-body-sm);
  line-height: var(--go-lh-normal);
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

view,
text,
button,
input,
textarea,
scroll-view,
image {
  box-sizing: border-box;
}

/* 通用文字色阶 */
.go-text-1 { color: var(--go-on-surface); }
.go-text-2 { color: var(--go-on-surface-2); }
.go-text-3 { color: var(--go-on-surface-3); }
.go-text-disabled { color: var(--go-on-surface-disabled); }

/* ============ 表单输入 ============ */
.go-field {
  display: block;
  width: 100%;
  font-size: var(--go-fs-body);
  color: var(--go-on-surface);
  caret-color: var(--go-primary);
  padding: var(--go-sp-3) var(--go-sp-4);
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-md);
  background: var(--go-surface-2);
  /* APP 端 <input>/<textarea> 是 native 组件，line-height 若过小或为 0
     会导致 native EditText 内的文本基线异常，文字看起来被遮住 / 飘到上沿 */
  line-height: 1.5;
  min-height: 44rpx;
  transition: border-color var(--go-dur-fast) var(--go-ease-standard),
    box-shadow var(--go-dur-fast) var(--go-ease-standard);
  &:focus {
    border-color: var(--go-primary);
    box-shadow: 0 0 0 3rpx color-mix(in srgb, var(--go-primary) 22%, transparent);
  }
}
/* placeholder 颜色通过 placeholder-class 显式控制（uni-app APP 端 input 默认 placeholder
   颜色有时与 input 文字色冲突，导致「输入文字与 placeholder 同色」看起来像被遮挡） */
.go-field__ph { color: var(--go-on-surface-disabled); }
.go-field .ph { color: var(--go-on-surface-disabled); }
.go-primary { color: var(--go-primary); }

/* ============ 顶栏 AppBar ============ */
.go-appbar {
  position: sticky;
  top: 0;
  z-index: 30;
  display: flex;
  align-items: center;
  gap: var(--go-sp-2);
  min-height: var(--go-appbar-h);
  padding: calc(var(--go-safe-top) + var(--go-sp-2)) var(--go-sp-4) var(--go-sp-2);
  background: var(--go-surface-raised);
  border-bottom: 1rpx solid var(--go-outline);

  &__title {
    flex: 1;
    min-width: 0;
    font-size: var(--go-fs-title);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  &__actions {
    display: flex;
    align-items: center;
    gap: var(--go-sp-1);
  }
  &.tonal {
    background: var(--go-primary-95);
    border-bottom-color: transparent;
  }
  &.transparent {
    background: transparent;
    border-bottom-color: transparent;
    backdrop-filter: blur(20rpx);
  }
  &.floating {
    background: color-mix(in srgb, var(--go-surface-raised) 86%, transparent);
    backdrop-filter: saturate(1.4) blur(24rpx);
    border-bottom-color: transparent;
    box-shadow: var(--go-shadow-1);
  }
}

/* 图标按钮（顶栏/行内通用） */
.go-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 72rpx;
  height: 72rpx;
  border-radius: var(--go-r-full);
  color: var(--go-on-surface-2);
  background: transparent;
  transition: background var(--go-dur-fast) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active {
    background: var(--go-sel);
    transform: scale(0.92);
  }
  /* primary = 玻璃质感的圆 action button（首页 + 之类）
     用半透明主色 + 主色描边 + 微投影做出「浮在顶栏之上」的迷你 FAB 感
     ——比单纯一个描线图标更有「想点」的视觉暗示 */
  &.primary {
    color: var(--go-primary);
    background: color-mix(in srgb, var(--go-primary) 8%, var(--go-on-primary));
    border: 1rpx solid color-mix(in srgb, var(--go-primary) 28%, transparent);
    box-shadow:
      0 6rpx 16rpx color-mix(in srgb, var(--go-primary) 18%, transparent),
      0 1rpx 2rpx rgba(0, 0, 0, 0.04),
      inset 0 1rpx 0 color-mix(in srgb, var(--go-on-primary) 70%, transparent);
    backdrop-filter: blur(16rpx) saturate(140%);
    -webkit-backdrop-filter: blur(16rpx) saturate(140%);
  }
  &.primary:active {
    background: color-mix(in srgb, var(--go-primary) 18%, var(--go-on-primary));
    box-shadow:
      0 3rpx 8rpx color-mix(in srgb, var(--go-primary) 14%, transparent);
    transform: scale(0.94);
  }
}

/* ============ 返回箭（圆形） ============ */
.back {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 72rpx;
  height: 72rpx;
  border-radius: var(--go-r-full);
  background: var(--go-surface-2);
  color: var(--go-on-surface);
  /* 显式提高 z-index + 相对定位 + 可点击：修复 APP 端 sticky bar 下原生层
     偶发吃 click 事件，导致 .back 可见但点不到 */
  position: relative;
  z-index: 31;
  pointer-events: auto;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background var(--go-dur-fast) var(--go-ease-standard),
    transform var(--go-dur-fast) var(--go-ease-standard);
  &:active {
    background: var(--go-sel);
    transform: scale(0.92);
  }
  .back-svg { font-size: 40rpx; line-height: 1; }
}

/* ============ 内容容器 ============ */
.go-page {
  min-height: 100vh;
  background: var(--go-bg);
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-4));
}
.go-content {
  max-width: var(--go-content-max);
  margin: 0 auto;
  padding: var(--go-sp-4);
}
.go-section {
  margin-bottom: var(--go-sp-8);
}
.go-section__title {
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-semibold);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--go-on-surface-3);
  padding: var(--go-sp-2) var(--go-sp-4);
}

/* ============ 卡片 ============ */
/* Glassmorphism 玻璃浮动卡片：圆角/模糊/白边/光晕 + hover 放大 */
.go-card {
  position: relative;
  background: var(--go-glass-bg);
  border-radius: var(--go-glass-radius);
  box-shadow: var(--go-glass-shadow);
  border: var(--go-glass-border);
  backdrop-filter: blur(var(--go-glass-blur)) saturate(140%);
  -webkit-backdrop-filter: blur(var(--go-glass-blur)) saturate(140%);
  overflow: hidden;
  transition: transform 0.28s cubic-bezier(0.2, 0.7, 0.2, 1),
    box-shadow 0.28s ease, background 0.28s ease;
  will-change: transform;
}
.go-card::after {
  content: '';
  position: absolute;
  inset: 0;
  background: var(--go-glass-glow);
  pointer-events: none;
  opacity: 0.9;
}
.go-card:hover {
  transform: scale(var(--go-glass-hover));
  box-shadow: 0 14rpx 40rpx rgba(80, 50, 30, 0.20), 0 4rpx 12rpx rgba(80, 50, 30, 0.14);
  z-index: 5;
}
.go-card--flat {
  box-shadow: none;
  background: var(--go-glass-bg-strong);
}
.go-card--padded {
  padding: var(--go-sp-5);
}
.go-card--clickable {
  transition: transform var(--go-dur-fast) var(--go-ease-standard),
    box-shadow var(--go-dur-fast) var(--go-ease-standard);
  &:active {
    transform: scale(0.985);
    box-shadow: var(--go-shadow-2);
  }
}

/* ============ 列表行（设置项 / 信息等） ============ */
.go-list {
  background: var(--go-surface);
  border-radius: var(--go-r-lg);
  overflow: hidden;
  border: 1rpx solid var(--go-outline);
}
.go-row {
  display: flex;
  align-items: center;
  gap: var(--go-sp-4);
  min-height: 104rpx;
  padding: var(--go-sp-3) var(--go-sp-5);
  background: var(--go-surface);
  transition: background var(--go-dur-fast) var(--go-ease-standard);
  & + & {
    border-top: 1rpx solid var(--go-outline);
  }
  &:active { background: var(--go-sel); }
  &__icon {
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 64rpx;
    height: 64rpx;
    border-radius: var(--go-r-sm);
    background: var(--go-primary-95);
    color: var(--go-primary);
  }
  &__body {
    flex: 1;
    min-width: 0;
  }
  &__title {
    font-size: var(--go-fs-body-sm);
    font-weight: var(--go-fw-medium);
    color: var(--go-on-surface);
  }
  &__sub {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    margin-top: 2rpx;
  }
  &__trail {
    flex: none;
    display: flex;
    align-items: center;
    gap: var(--go-sp-2);
    color: var(--go-on-surface-3);
    font-size: var(--go-fs-meta);
  }
  &__chevron {
    color: var(--go-on-surface-disabled);
  }
}

/* ============ 文章列表行 ============ */
.go-article-row {
  display: block;
  padding: var(--go-sp-5) var(--go-sp-5);
  background: var(--go-surface);
  border-radius: var(--go-r-lg);
  box-shadow: var(--go-shadow-1);
  border: 1rpx solid var(--go-outline);
  transition: transform var(--go-dur-fast) var(--go-ease-standard),
    box-shadow var(--go-dur-fast) var(--go-ease-standard);
  & + & { margin-top: var(--go-sp-4); }
  &:active {
    transform: scale(0.99);
    box-shadow: var(--go-shadow-2);
  }
  &__source {
    display: inline-flex;
    align-items: center;
    gap: var(--go-sp-2);
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-semibold);
    color: var(--go-primary);
    background: var(--go-primary-95);
    padding: 4rpx 14rpx;
    border-radius: var(--go-r-full);
    margin-bottom: var(--go-sp-3);
  }
  &__title {
    font-family: var(--go-font-read);
    font-size: var(--go-fs-h2);
    font-weight: var(--go-fw-semibold);
    line-height: var(--go-lh-snug);
    color: var(--go-on-surface);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  &__preview {
    margin-top: var(--go-sp-2);
    font-size: var(--go-fs-body-sm);
    line-height: var(--go-lh-normal);
    color: var(--go-on-surface-3);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  &__meta {
    margin-top: var(--go-sp-3);
    display: flex;
    align-items: center;
    gap: var(--go-sp-3);
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
  }
  &__dot {
    width: 6rpx;
    height: 6rpx;
    border-radius: var(--go-r-full);
    background: var(--go-on-surface-disabled);
  }
}

/* ============ 芯片 Chip ============ */
.go-chip {
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-1);
  height: 52rpx;
  padding: 0 var(--go-sp-4);
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-medium);
  color: var(--go-on-surface-2);
  background: var(--go-surface-2);
  border: 1rpx solid var(--go-outline);
  transition: all var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(0.96); }
  &.active {
    color: var(--go-on-primary);
    background: var(--go-primary);
    border-color: var(--go-primary);
  }
  &.soft {
    color: var(--go-primary);
    background: var(--go-primary-90);
    border-color: transparent;
    box-shadow: var(--go-shadow-1);
  }
}

/* ============ 按钮 ============ */
.go-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--go-sp-2);
  height: 88rpx;
  padding: 0 var(--go-sp-6);
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-body-sm);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-primary);
  background: var(--go-primary);
  box-shadow: var(--go-shadow-2), inset 0 1rpx 0 rgba(255, 255, 255, 0.25);
  transition: transform var(--go-dur-fast) var(--go-ease-standard),
    box-shadow var(--go-dur-fast) var(--go-ease-standard),
    background var(--go-dur-fast) var(--go-ease-standard);
  &:active {
    transform: scale(0.97);
    box-shadow: var(--go-shadow-3), inset 0 1rpx 0 rgba(255, 255, 255, 0.25);
  }
  &[disabled] {
    background: var(--go-surface);
    color: var(--go-on-surface-disabled);
    box-shadow: none;
  }
  &--block { width: 100%; }
  &--tonal {
    color: var(--go-primary);
    background: var(--go-primary-90);
    box-shadow: var(--go-shadow-1);
  }
  &--outlined {
    color: var(--go-primary);
    background: transparent;
    border: 2rpx solid var(--go-primary);
    box-shadow: none;
  }
  &--text {
    color: var(--go-primary);
    background: transparent;
    box-shadow: none;
    padding: 0 var(--go-sp-4);
  }
}

/* ============ 浮动操作按钮 FAB ============ */
.go-fab {
  position: fixed;
  right: var(--go-sp-6);
  bottom: calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-6));
  z-index: 40;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 112rpx;
  height: 96rpx;
  padding: 0 var(--go-sp-6);
  gap: var(--go-sp-2);
  border-radius: var(--go-r-full);
  background: var(--go-primary);
  color: var(--go-on-primary);
  box-shadow: var(--go-shadow-3);
  font-weight: var(--go-fw-semibold);
  font-size: var(--go-fs-body-sm);
  transition: transform var(--go-dur-fast) var(--go-ease-standard),
    box-shadow var(--go-dur-fast) var(--go-ease-standard);
  &:active {
    transform: scale(0.94);
    box-shadow: var(--go-shadow-2);
  }
}

/* ============ 骨架屏 ============ */
.go-skeleton {
  position: relative;
  overflow: hidden;
  background: var(--go-surface-2);
  border-radius: var(--go-r-md);
  &::after {
    content: '';
    position: absolute;
    inset: 0;
    transform: translateX(-100%);
    background: linear-gradient(
      90deg,
      transparent,
      color-mix(in srgb, var(--go-on-surface) 8%, transparent),
      transparent
    );
    animation: go-shimmer 1.4s infinite;
  }
}
@keyframes go-shimmer {
  100% { transform: translateX(100%); }
}

/* ============ 空状态 ============ */
.go-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--go-sp-16) var(--go-sp-8);
  text-align: center;
  &__icon {
    width: 140rpx;
    height: 140rpx;
    margin-bottom: var(--go-sp-5);
    opacity: 0.7;
    color: var(--go-on-surface-disabled);
  }
  &__title {
    font-size: var(--go-fs-h2);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
  }
  &__desc {
    margin-top: var(--go-sp-2);
    font-size: var(--go-fs-body-sm);
    color: var(--go-on-surface-3);
    max-width: 480rpx;
  }
  &__action { margin-top: var(--go-sp-6); }
}

/* ============ 底部弹层 Sheet ============ */
.go-sheet-up {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 60;
  background: var(--go-surface-raised);
  border-radius: var(--go-r-xl) var(--go-r-xl) 0 0;
  box-shadow: var(--go-shadow-3);
  padding: var(--go-sp-4) var(--go-sp-5) calc(var(--go-sp-6) + var(--go-safe-bottom));
  transform: translateY(100%);
  transition: transform var(--go-dur-med) var(--go-ease-emphasized);
  &.open { transform: translateY(0); }
}
.go-sheet-mask {
  position: fixed;
  inset: 0;
  z-index: 55;
  background: var(--go-scrim);
  opacity: 0;
  pointer-events: none;
  transition: opacity var(--go-dur-med) var(--go-ease-standard);
  &.open { opacity: 1; pointer-events: auto; }
}
.go-sheet-handle {
  width: 64rpx;
  height: 6rpx;
  border-radius: var(--go-r-full);
  background: var(--go-outline-strong);
  margin: var(--go-sp-2) auto var(--go-sp-4);
}

/* ============ 开关 Switch ============ */
.go-switch {
  position: relative;
  width: 92rpx;
  height: 52rpx;
  border-radius: var(--go-r-full);
  background: var(--go-surface-variant);
  transition: background var(--go-dur-med) var(--go-ease-standard);
  flex: none;
  &.on {
    background: var(--go-primary);
  }
  &__thumb {
    position: absolute;
    top: 6rpx;
    left: 6rpx;
    width: 40rpx;
    height: 40rpx;
    border-radius: var(--go-r-full);
    background: var(--go-surface-raised);
    box-shadow: var(--go-shadow-1);
    transition: transform var(--go-dur-med) var(--go-ease-emphasized);
  }
  &.on &__thumb { transform: translateX(40rpx); }
}

/* ============ Segmented 分段控件 ============ */
/* 设计要点：
   - 容器用半透明 surface + 1px 内描边，给页面留出"嵌入"质感而非色块感
   - 滑块用 on-primary 浅色（白/奶白）做出最高对比，而不是实心主色块
     ——主色块在阅读 Tab 上视觉过重，且不易与 chip/按钮拉开层次
   - active 文字加主色，且字重升一档；inactive 用 on-surface-2
   - 加 1px 滑块投影 + 微微 translate 营造物理感 */
.go-segmented {
  display: inline-flex;
  align-items: center;
  padding: 4rpx;
  background: color-mix(in srgb, var(--go-surface-2) 60%, transparent);
  border: 1rpx solid color-mix(in srgb, var(--go-on-surface) 8%, transparent);
  border-radius: var(--go-r-full);
  backdrop-filter: blur(20rpx) saturate(140%);
  -webkit-backdrop-filter: blur(20rpx) saturate(140%);
  box-shadow: inset 0 1rpx 0 color-mix(in srgb, var(--go-on-surface) 6%, transparent);

  &__item {
    position: relative;
    padding: var(--go-sp-2) var(--go-sp-5);
    border-radius: var(--go-r-full);
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-medium);
    color: var(--go-on-surface-3);
    transition: color var(--go-dur-fast) var(--go-ease-standard),
      font-weight var(--go-dur-fast) var(--go-ease-standard);
    z-index: 1;

    &.active {
      color: var(--go-primary);
      font-weight: var(--go-fw-semibold);
      background: var(--go-on-primary);
      box-shadow:
        0 2rpx 8rpx color-mix(in srgb, var(--go-primary) 22%, transparent),
        0 1rpx 2rpx rgba(0, 0, 0, 0.04);
      transform: translateY(-1rpx);
    }
    &:active:not(.active) {
      color: var(--go-on-surface);
      background: color-mix(in srgb, var(--go-on-surface) 6%, transparent);
    }
  }
}

/* ============ 进度条 ============ */
.go-progress {
  height: 12rpx;
  border-radius: var(--go-r-full);
  background: var(--go-surface-variant);
  overflow: hidden;
  &__bar {
    height: 100%;
    border-radius: var(--go-r-full);
    background: var(--go-primary);
    transition: width var(--go-dur-slow) var(--go-ease-emphasized);
  }
}

/* ============ 提示气泡 ============ */
.go-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 36rpx;
  height: 36rpx;
  padding: 0 10rpx;
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-cap);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-primary);
  background: var(--go-primary);
}

/* ============ 过渡动画（页面立体转场，由 useTransition 注入） ============ */
.uni-page-body { transform-style: preserve-3d; background: var(--go-bg); }
.go-push-in {
  animation: go-push-in var(--go-dur-med) var(--go-ease-emphasized) both;
}
.go-push-back {
  animation: go-push-back var(--go-dur-med) var(--go-ease-emphasized) both;
}
.go-pop-front {
  animation: go-pop-front var(--go-dur-med) var(--go-ease-emphasized) both;
}
@keyframes go-push-in {
  from { transform: translate3d(60rpx, 0, -120rpx); opacity: 0.4; }
  to { transform: translate3d(0, 0, 0); opacity: 1; }
}
@keyframes go-push-back {
  from { transform: scale(1); }
  to { transform: scale(0.94); }
}
@keyframes go-pop-front {
  from { transform: scale(1.06); opacity: 0.6; }
  to { transform: scale(1); opacity: 1; }
}

/* ============ 通用工具类 ============ */
.go-mt-2 { margin-top: var(--go-sp-2); }
.go-mt-4 { margin-top: var(--go-sp-4); }
.go-mt-6 { margin-top: var(--go-sp-6); }
.go-mt-8 { margin-top: var(--go-sp-8); }
.go-mb-4 { margin-bottom: var(--go-sp-4); }
.go-center { text-align: center; }
.go-row-flex { display: flex; align-items: center; }
.go-between { display: flex; align-items: center; justify-content: space-between; }
.go-wrap { flex-wrap: wrap; }
.go-gap-2 { gap: var(--go-sp-2); }
.go-gap-3 { gap: var(--go-sp-3); }
.go-gap-4 { gap: var(--go-sp-4); }
/* ============ Glassmorphism 玻璃浮动卡片（全局类，全页面可用） ============ */
.go-glass {
  position: relative;
  background: var(--go-glass-bg);
  border: var(--go-glass-border);
  border-radius: var(--go-glass-radius);
  box-shadow: var(--go-glass-shadow);
  backdrop-filter: blur(var(--go-glass-blur)) saturate(140%);
  -webkit-backdrop-filter: blur(var(--go-glass-blur)) saturate(140%);
  overflow: hidden;
  transition: transform 0.28s cubic-bezier(0.2, 0.7, 0.2, 1),
    box-shadow 0.28s ease, background 0.28s ease;
  will-change: transform;
}
.go-glass::after {
  content: '';
  position: absolute;
  inset: 0;
  background: var(--go-glass-glow);
  pointer-events: none;
  opacity: 0.9;
}
.go-glass:hover {
  transform: scale(var(--go-glass-hover));
  box-shadow: 0 14rpx 40rpx rgba(80, 50, 30, 0.20), 0 4rpx 12rpx rgba(80, 50, 30, 0.14);
  z-index: 5;
}
/* 卡片之间重叠 */
.go-glass--overlap { margin-top: -14rpx; }
.go-glass--overlap:first-of-type { margin-top: 0; }

/* 页面加载时卡片依次浮现（staggered）。
   容器加 .go-stagger，子元素加 .go-glass（或任意带 data-stagger 的节点）。 */
@keyframes go-glass-rise {
  from { opacity: 0; transform: translateY(26rpx) scale(0.98); }
  to   { opacity: 1; transform: translateY(0) scale(1); }
}
.go-stagger > .go-glass,
.go-stagger > [data-stagger] {
  opacity: 0;
  animation: go-glass-rise 0.5s cubic-bezier(0.2, 0.7, 0.2, 1) forwards;
}
.go-stagger > .go-glass:nth-child(1), .go-stagger > [data-stagger]:nth-child(1) { animation-delay: 0.05s; }
.go-stagger > .go-glass:nth-child(2), .go-stagger > [data-stagger]:nth-child(2) { animation-delay: 0.13s; }
.go-stagger > .go-glass:nth-child(3), .go-stagger > [data-stagger]:nth-child(3) { animation-delay: 0.21s; }
.go-stagger > .go-glass:nth-child(4), .go-stagger > [data-stagger]:nth-child(4) { animation-delay: 0.29s; }
.go-stagger > .go-glass:nth-child(5), .go-stagger > [data-stagger]:nth-child(5) { animation-delay: 0.37s; }
.go-stagger > .go-glass:nth-child(6), .go-stagger > [data-stagger]:nth-child(6) { animation-delay: 0.45s; }
.go-stagger > .go-glass:nth-child(7), .go-stagger > [data-stagger]:nth-child(7) { animation-delay: 0.53s; }
.go-stagger > .go-glass:nth-child(8), .go-stagger > [data-stagger]:nth-child(8) { animation-delay: 0.61s; }
.go-stagger > .go-glass:nth-child(n+9), .go-stagger > [data-stagger]:nth-child(n+9) { animation-delay: 0.69s; }

@media (prefers-reduced-motion: reduce) {
  .go-stagger > .go-glass,
  .go-stagger > [data-stagger] { animation: none; opacity: 1; }
}
</style>
