import { createSSRApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'

// ===== 全局定时器与 requestAnimationFrame polyfill =====
;(function installGlobals() {
  // 兼容没有 globalThis 的老基座 / 自定义基座：依次取可用的全局对象
  // 注意：模块内是 strict mode，(function(){ return this })() 会返回 undefined，
  // 所以这里用 eval/Function 兜底来获取全局对象。
  const g = (typeof globalThis !== 'undefined') ? globalThis
    : (typeof self !== 'undefined') ? self
    : (typeof window !== 'undefined') ? window
    : (typeof global !== 'undefined') ? global
    : undefined
  if (!g) {
    try { uni.showToast({ title: 'polyfill no global', icon: 'none', duration: 2000 }) } catch (_) {}
    return
  }

  // 先尝试捕获自由变量形式的定时器（某些基座只注入到脚本作用域，未挂到全局对象）
  let freeSetTimeout, freeClearTimeout, freeSetInterval, freeClearInterval
  let freeSetTimeoutForRuntime, freeClearTimeoutForRuntime, freeSetIntervalForRuntime, freeClearIntervalForRuntime
  let freeSetImmediate, freeClearImmediate
  try { freeSetTimeout = setTimeout } catch (_) {}
  try { freeClearTimeout = clearTimeout } catch (_) {}
  try { freeSetInterval = setInterval } catch (_) {}
  try { freeClearInterval = clearInterval } catch (_) {}
  try { freeSetTimeoutForRuntime = setTimeoutForRuntime } catch (_) {}
  try { freeClearTimeoutForRuntime = clearTimeoutForRuntime } catch (_) {}
  try { freeSetIntervalForRuntime = setIntervalForRuntime } catch (_) {}
  try { freeClearIntervalForRuntime = clearIntervalForRuntime } catch (_) {}
  try { freeSetImmediate = setImmediate } catch (_) {}
  try { freeClearImmediate = clearImmediate } catch (_) {}

  const getFn = (freeVar, ...names) => {
    if (typeof freeVar === 'function') return freeVar
    for (const n of names) {
      if (typeof g[n] === 'function') return g[n]
    }
    return undefined
  }

  const install = (name, impl, clearName, clearImpl) => {
    if (typeof g[name] !== 'function') {
      try { Object.defineProperty(g, name, { value: impl, writable: true, configurable: true }) } catch (_) { g[name] = impl }
    }
    if (clearName && typeof g[clearName] !== 'function' && typeof clearImpl === 'function') {
      try { Object.defineProperty(g, clearName, { value: clearImpl, writable: true, configurable: true }) } catch (_) { g[clearName] = clearImpl }
    }
  }

  // 提供一个完全基于 plus.runtime 计时器的兜底实现（避免依赖浏览器 setTimeout）
  const createTimerImpl = () => {
    // 直接用 Date.now() 模拟，精度一般但足够用于短延迟
    let id = 0
    const timers = {}
    const loop = () => {
      const now = Date.now()
      Object.keys(timers).forEach((k) => {
        const t = timers[k]
        if (!t) return
        if (now >= t.when) {
          delete timers[k]
          try { t.fn() } catch (_) {}
          // interval 需要重新排队
          if (t.repeat) {
            t.when = now + t.delay
            timers[k] = t
          }
        }
      })
      requestAnimationFrame && requestAnimationFrame(loop)
    }
    const startLoop = () => {
      if (typeof requestAnimationFrame === 'function') requestAnimationFrame(loop)
      else if (typeof g.setInterval === 'function') g.setInterval(loop, 16)
      // 如果连 setInterval 也没有，只能依赖调用方继续触发（实际不会用到）
    }
    startLoop()
    return {
      setTimeout: (cb, delay, ...args) => {
        const handle = ++id
        timers[handle] = { fn: () => cb(...args), when: Date.now() + (delay || 0), delay, repeat: false }
        return handle
      },
      clearTimeout: (handle) => { delete timers[handle] },
      setInterval: (cb, delay, ...args) => {
        const handle = ++id
        timers[handle] = { fn: () => cb(...args), when: Date.now() + (delay || 0), delay, repeat: true }
        return handle
      },
      clearInterval: (handle) => { delete timers[handle] },
    }
  }

  // 微任务兜底：即使没有原生定时器，也能让 setTimeout 可调
  const createMicrotaskFallback = () => {
    let id = 0
    const timers = {}
    return {
      setTimeout: (cb, delay, ...args) => {
        const handle = ++id
        timers[handle] = () => cb(...args)
        const run = () => { const fn = timers[handle]; if (fn) { delete timers[handle]; try { fn() } catch(_) {} } }
        Promise.resolve().then(run).catch(() => {})
        return handle
      },
      clearTimeout: (handle) => { delete timers[handle] },
    }
  }

  // setTimeout / clearTimeout
  if (typeof g.setTimeout !== 'function') {
    const impl = getFn(freeSetTimeout, 'setTimeout', 'setTimeoutForRuntime', 'setImmediate')
    const clearImpl = getFn(freeClearTimeout, 'clearTimeout', 'clearTimeoutForRuntime', 'clearImmediate')
    if (impl) {
      install('setTimeout', impl, 'clearTimeout', clearImpl)
    } else {
      // 兜底：用 Promise 微任务异步执行，至少避免 "setTimeout is not a function"
      const fallback = createMicrotaskFallback()
      install('setTimeout', fallback.setTimeout, 'clearTimeout', fallback.clearTimeout)
    }
  }
  if (typeof g.clearTimeout !== 'function') {
    const impl = getFn(freeClearTimeout, 'clearTimeout', 'clearTimeoutForRuntime', 'clearImmediate')
    if (impl) install('clearTimeout', impl)
  }

  // setInterval / clearInterval
  if (typeof g.setInterval !== 'function') {
    const impl = getFn(freeSetInterval, 'setInterval', 'setIntervalForRuntime')
    const clearImpl = getFn(freeClearInterval, 'clearInterval', 'clearIntervalForRuntime')
    if (impl) {
      install('setInterval', impl, 'clearInterval', clearImpl)
    } else {
      // 用 setTimeout 模拟 interval，避免 createTimerImpl 依赖 requestAnimationFrame
      install('setInterval', (cb, delay, ...args) => {
        let t
        const loop = () => { cb(...args); t = g.setTimeout(loop, delay) }
        t = g.setTimeout(loop, delay)
        return { __id: t }
      }, 'clearInterval', (handle) => { if (handle && typeof handle.__id !== 'undefined') g.clearTimeout(handle.__id) })
    }
  }
  if (typeof g.clearInterval !== 'function') {
    const impl = getFn(freeClearInterval, 'clearInterval', 'clearIntervalForRuntime')
    if (impl) install('clearInterval', impl)
  }

  // 如果全局对象上已有 setTimeout 但自由变量 setTimeout 仍缺失，显式赋值一次（处理某些作用域异常）
  if (typeof g.setTimeout === 'function' && typeof window !== 'undefined' && typeof window.setTimeout === 'function') {
    try { window.setTimeout = g.setTimeout } catch (_) {}
    try { window.clearTimeout = g.clearTimeout } catch (_) {}
    try { window.setInterval = g.setInterval } catch (_) {}
    try { window.clearInterval = g.clearInterval } catch (_) {}
  }

  if (typeof g.requestAnimationFrame !== 'function') {
    const raf = (cb) => (typeof g.setTimeout === 'function')
      ? g.setTimeout(() => cb(+(new Date())), 16)
      : (() => { try { cb(+(new Date())) } catch (e) {} return 0 })()
    const caf = (id) => { if (typeof g.clearTimeout === 'function' && id) g.clearTimeout(id) }
    try { Object.defineProperty(g, 'requestAnimationFrame', { value: raf, writable: true, configurable: true }) } catch (_) { g.requestAnimationFrame = raf }
    try { Object.defineProperty(g, 'cancelAnimationFrame', { value: caf, writable: true, configurable: true }) } catch (_) { g.cancelAnimationFrame = caf }
  }

  // 全局定时器兜底安装完成（仅在基座缺失时生效）
  try { console.log('[main.js] polyfill setTimeout:', typeof g.setTimeout) } catch (_) {}
})()

export function createApp() {
  const app = createSSRApp(App)
  app.use(createPinia())
  // 诊断回路
  app.config.errorHandler = (err, instance, info) => {
    try {
      const msg = (err && (err.stack || err.message)) || String(err)
      console.error('[VUE ERROR]', info, msg)
      try {
        const tag = instance && instance.$options ? (instance.$options.name || instance.$options.__name || 'anon') : 'anon'
        const dump = '[' + info + '/' + tag + '] :: ' + msg.slice(0, 800)
        uni.setStorageSync('__last_err', dump)
      } catch (_) {}
      try {
        const title = 'ERR ' + (err && err.message ? err.message : info).slice(0, 60)
        uni.showToast({ title, icon: 'none', duration: 6000 })
      } catch (_) {}
    } catch (e) { /* ignore */ }
  }
  return { app }
}
