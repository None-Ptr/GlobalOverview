import anime from 'animejs'
function safe(fn) {
  if (!anime) return null
  try { return fn() } catch (e) { return null }
}

// 底部 tab 点击：图标弹性缩放 + 标签轻微上移
export function navItemBounce(root) {
  let el = null
  if (root && root.$el) el = root.$el
  else if (typeof root === 'string') {
    // 兜底：document 在某些 5+App Runtime 下可能是 undefined，会触发 `Cannot read property 'querySelector' of undefined`
    if (typeof document !== 'undefined' && document && document.querySelector) el = document.querySelector(root)
  } else el = root
  if (!el) return
  safe(() => {
    const ico = el.querySelector('.nav-ico')
    const label = el.querySelector('.nav-label')
    if (ico) anime({ targets: ico, scale: [1, 1.25, 1], duration: 420, easing: 'easeOutElastic(1, .6)' })
    if (label) anime({ targets: label, translateY: [0, -3, 0], duration: 360, easing: 'easeOutQuad' })
  })
}

// 底部指示器滑动（在 from → to 两个元素间平移）
export function navMarkerSlide(marker, fromX, toX) {
  if (!marker) return
  safe(() => {
    anime({ targets: marker, translateX: [fromX, toX], scaleX: [0.3, 1], opacity: [0, 1], duration: 360, easing: 'cubicBezier(.34,1.56,.64,1)' })
  })
}

// 单词卡弹出：mask 淡入 + 卡片弹性上滑放大
export function wordCardIn(cardEl, maskEl) {
  safe(() => {
    if (maskEl) anime({ targets: maskEl, opacity: [0, 1], duration: 220, easing: 'linear' })
    if (cardEl) {
      anime({ targets: cardEl, translateY: [40, 0], scale: [0.92, 1], opacity: [0, 1], duration: 460, easing: 'easeOutElastic(1, .7)' })
    }
  })
}

// 单词卡关闭：快速淡出下移
export function wordCardOut(cardEl, maskEl, done) {
  if (!anime) { done && done(); return }
  try {
    const tl = anime.timeline({ easing: 'easeInQuad' })
    if (cardEl) tl.add({ targets: cardEl, translateY: [0, 30], scale: [1, 0.96], opacity: [1, 0], duration: 200 })
    if (maskEl) tl.add({ targets: maskEl, opacity: [1, 0], duration: 180 }, 0)
    tl.add({ targets: {}, duration: 1, complete: () => done && done() })
  } catch (e) { done && done() }
}

// 译文卡片展开：高度 + 透明度滑入
export function translationIn(el) {
  if (!el) return
  safe(() => {
    const h = el.offsetHeight
    anime.set(el, { height: 0, opacity: 0, overflow: 'hidden' })
    anime({ targets: el, height: [0, h], opacity: [0, 1], duration: 420, easing: 'easeOutCubic', complete: () => anime.set(el, { height: 'auto', overflow: '' }) })
  })
}

// 列表项错落入场（stagger）
export function listStagger(items) {
  if (!items || !items.length) return
  safe(() => {
    anime({ targets: items, opacity: [0, 1], translateY: [16, 0], delay: anime.stagger(45, { start: 60 }), duration: 480, easing: 'easeOutCubic' })
  })
}

// 通用：元素轻微 pulse（用于提示/高亮）
export function pulse(el) {
  if (!el) return
  safe(() => anime({ targets: el, scale: [1, 1.08, 1], duration: 500, easing: 'easeInOutSine' }))
}

export default { navItemBounce, navMarkerSlide, wordCardIn, wordCardOut, translationIn, listStagger, pulse }
