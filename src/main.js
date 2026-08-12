import { createSSRApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'

// ===== requestAnimationFrame 全局 polyfill =====
;(function installRAF() {
  if (typeof globalThis === 'undefined') return
  const g = globalThis
  if (typeof g.requestAnimationFrame !== 'function') {
    const raf = (cb) => (typeof g.setTimeout === 'function')
      ? g.setTimeout(() => cb(+(new Date())), 16)
      : (() => { try { cb(+(new Date())) } catch (e) {} return 0 })()
    const caf = (id) => { if (typeof g.clearTimeout === 'function' && id) g.clearTimeout(id) }
    try { Object.defineProperty(g, 'requestAnimationFrame', { value: raf, writable: true, configurable: true }) } catch (_) { g.requestAnimationFrame = raf }
    try { Object.defineProperty(g, 'cancelAnimationFrame', { value: caf, writable: true, configurable: true }) } catch (_) { g.cancelAnimationFrame = caf }
  }
})()

export function createApp() {
  const app = createSSRApp(App)
  app.use(createPinia())
  // 诊断回路
  app.config.errorHandler = (err, instance, info) => {
    const msg = (err && (err.stack || err.message)) || String(err)
    console.error('[VUE ERROR]', info, msg)
    try {
      const tag = instance && instance.$options ? (instance.$options.name || instance.$options.__name || 'anon') : 'anon'
      const dump = '[' + info + '/' + tag + '] :: ' + msg.slice(0, 800)
      uni.setStorageSync('__last_err', dump)
      setTimeout(() => {
        const title = 'ERR ' + (err && err.message ? err.message : info).slice(0, 60)
        uni.showToast({ title, icon: 'none', duration: 6000 })
      }, 400)
    } catch (e) { /* ignore */ }
  }
  return { app }
}
