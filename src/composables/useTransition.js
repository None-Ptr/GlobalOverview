// 立体转场 composable（面向 APP，页面运行于 webview 含 DOM）
// 通过给页面根节点（.uni-page-body）注入动画类，
// 实现 iOS 式 3D 景深 push/pop 转场。
//
// 兼容：uni-app 某些构建目标（特别是 APP 端非 webview 场景下）
// 不会自动注入 window.requestAnimationFrame，这里做局部自包含兜底，
// 无需依赖宿主环境全局对象即可执行。

const g = typeof globalThis !== 'undefined' ? globalThis
  : (typeof window !== 'undefined' ? window
  : (typeof global !== 'undefined' ? global : null))

function rafSafe(cb) {
  if (g && typeof g.requestAnimationFrame === 'function') return g.requestAnimationFrame(cb)
  if (g && typeof g.setTimeout === 'function') return g.setTimeout(() => cb(+(new Date())), 16)
  // 极端兜底（无 setTimeout 时）：同步执行，避免抛 ReferenceError 中断 setup
  try { cb(+(new Date())) } catch (e) { /* swallow */ }
  return 0
}

function rootOf(pageInstance) {
  if (!pageInstance || !pageInstance.$el) return null
  const el = pageInstance.$el
  // Vue3 setup 页面：$el 即根节点；可能内部含 .uni-page-body
  const body = el.querySelector && el.querySelector('.uni-page-body')
  return (body && body.classList) ? body : (el.classList ? el : null)
}

// 给页面栈中第 index 个页面（默认最后一个）挂动画类
function animateAt(index, className, clearOthers = []) {
  rafSafe(() => {
    const pages = getCurrentPages()
    const inst = pages[index]
    const root = rootOf(inst) ||
      (typeof document !== 'undefined' && document.querySelectorAll
        ? document.querySelectorAll('.uni-page-body')[index]
        : null)
    if (!root || !root.classList) return
    clearOthers.forEach((c) => root.classList.remove(c))
    void root.offsetWidth // 触发重排以重启动画
    root.classList.add(className)
    root.addEventListener('animationend', () => root.classList.remove(className), { once: true })
  })
}

/**
 * 在页面脚本中调用：
 *   const transition = useTransition('secondary' | 'tab')
 *   onShow(() => transition.onEnter())
 */
export function useTransition(type) {
  const isTab = type === 'tab'
  const isSecondary = type === 'secondary'

  function onEnter() {
    const pages = getCurrentPages()
    const last = pages.length - 1
    if (isTab) {
      // tabBar 页显示：放大归位景深（返回 / tab 切换都自然）
      animateAt(last, 'go-pop-front', ['go-tab-in', 'go-push-in'])
    } else if (isSecondary) {
      // 二级页进入：3D 从右推入，同时让来源页后退缩小形成景深
      animateAt(last, 'go-push-in', ['go-pop-front'])
      if (last > 0) animateAt(last - 1, 'go-push-back')
    }
  }

  return { onEnter }
}
