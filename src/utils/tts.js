// TTS 引擎
// 使用 unifiedtts.com 的 Edge TTS 服务（REST API，先拿到音频直链，再下载为 MP3 播放）
// 请求：POST /api/v1/common/tts-sync
//   header: { "X-API-Key": <key>, "Content-Type": "application/json" }
//   body:   { model:"edge-tts", text, voice, speed, pitch, volume, format:"mp3" }
// 响应：{ success:true, data:{ request_id, audio_url, file_size } }
//   audio_url 是 MP3 直链，客户端再下载为 ArrayBuffer 写入缓存并播放。
//
// 缓存策略：合成后的 mp3 按 (cacheKey || 文本) + 音色 的哈希存到本地文件
//   - App 端：plus.io PRIVATE_DOC/tts_cache/<hash>.mp3（重启仍在）

const CFG_KEY = 'go_tts_cfg'

// 默认配置：unifiedtts.com Edge TTS
export const DEFAULT_CFG = {
  apiKey: 'tts_0_6MQXw-VN22wVz_G3f36cIqLF21g78Yh6ty3YzpASo',
  apiUrl: 'https://unifiedtts.com/api/v1/common/tts-sync',
  presetVoice: 'en-US-JennyNeural',
  speed: 1.0,
  pitch: 1.0,
  volume: 1.0,
}

// Edge TTS 常用音色（中文 + 英文等）
export const TTS_VOICES = [
  { id: 'en-US-JennyNeural', name: '英文 · Jenny' },
  { id: 'en-US-GuyNeural', name: '英文 · Guy' },
  { id: 'en-GB-SoniaNeural', name: '英文(英) · Sonia' },
  { id: 'zh-CN-XiaoxiaoNeural', name: '中文 · 晓晓' },
  { id: 'zh-CN-YunxiNeural', name: '中文 · 云希(男)' },
  { id: 'zh-CN-YunyangNeural', name: '中文 · 云扬(男)' },
  { id: 'zh-CN-XiaoyiNeural', name: '中文 · 晓伊' },
  { id: 'ja-JP-NanamiNeural', name: '日文 · Nanami' },
  { id: 'ko-KR-SunHiNeural', name: '韩文 · SunHi' },
  { id: 'fr-FR-DeniseNeural', name: '法文 · Denise' },
  { id: 'de-DE-KatjaNeural', name: '德文 · Katja' },
  { id: 'es-ES-ElviraNeural', name: '西语 · Elvira' },
]

let player = null
let playing = false
let currentId = 0 // 用于让过期回调失效（stop 后旧请求不应再播放）

export function loadTtsConfig() {
  let cfg = null
  try {
    cfg = uni.getStorageSync(CFG_KEY)
  } catch (e) {
    cfg = null
  }
  // 旧配置（不含 apiUrl，即已废弃的 ttsapi）自动重置为 unifiedtts 默认配置
  if (!cfg || typeof cfg !== 'object' || !cfg.apiKey || !cfg.apiUrl) {
    cfg = { ...DEFAULT_CFG }
    try {
      uni.setStorageSync(CFG_KEY, cfg)
    } catch (e) {}
  }
  return { ...DEFAULT_CFG, ...cfg }
}

export function saveTtsConfig(cfg) {
  const merged = { ...DEFAULT_CFG, ...cfg }
  try {
    uni.setStorageSync(CFG_KEY, merged)
  } catch (e) {}
  return merged
}

export function isTtsPlaying() {
  return playing
}

export function stopTts() {
  ++currentId // 丢弃任何进行中的合成/播放请求
  _teardownPlayer()
}

function _teardownPlayer() {
  try {
    if (player) {
      if (typeof player.stop === 'function') player.stop()
      if (typeof player.destroy === 'function') player.destroy()
      if (typeof player.pause === 'function') player.pause()
    }
  } catch (e) {}
  player = null
  playing = false
}

/* ---------------- 缓存（本地文件） ---------------- */
function _hashKey(raw, voice) {
  let h = 2166136261 >>> 0
  const s = (voice || '') + '::' + raw
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619) >>> 0
  }
  return 'tts_' + h.toString(36)
}

function _ensureTtsDir() {
  return new Promise((resolve, reject) => {
    plus.io.requestFileSystem(plus.io.PRIVATE_DOC, (fs) => {
      fs.root.getDirectory('tts_cache', { create: true, exclusive: false }, (d) => resolve(d), (e) => reject(e))
    }, (e) => reject(e))
  })
}

// 返回缓存音频的播放 URL；未命中返回 null
// 关键：plus.audio.createPlayer 必须接收 _doc/ 相对路径（entry.toURL()），
// 不能用 toLocalURL() 返回的 file:// 绝对路径（会让 Android MediaPlayer play 报 -5）。
// 官方 5+ 文档示例即用相对路径：plus.audio.createPlayer("_Doc/Audio/test.mp3")。
function _cacheURL(key) {
  return new Promise((resolve) => {
    _ensureTtsDir()
      .then((dir) => {
        dir.getFile(
          key + '.mp3',
          { create: false },
          (entry) => resolve(entry.toURL()),
          () => resolve(null)
        )
      })
      .catch(() => resolve(null))
  })
}

// 判断 _doc/tts_cache/xxx.mp3 缓存文件是否真实存在且非空；不存在返回 null
function _cacheURLSafe(key, ab) {
  return new Promise((resolve) => {
    _ensureTtsDir()
      .then((dir) => {
        dir.getFile(
          key + '.mp3',
          { create: false },
          (entry) => {
            entry.getMetadata(
              (m) => {
                if (m.size > 128) return resolve(entry.toURL())
                // 缓存文件为空/损坏，有音频数据则删除旧文件后重写
                if (ab && ab.byteLength) {
                  return entry.remove(
                    () => { _writeCache(key, ab, null); resolve(null) },
                    () => { _writeCache(key, ab, null); resolve(null) }
                  )
                }
                return resolve(null)
              },
              () => resolve(null)
            )
          },
          () => resolve(null)
        )
      })
      .catch(() => resolve(null))
  })
}

// 模块顶部：捕获一份稳定的 setTimeout 引用，防止异步回调里自由变量丢失
const _safeSetTimeout = typeof setTimeout === 'function' ? setTimeout : undefined
const _safeClearTimeout = typeof clearTimeout === 'function' ? clearTimeout : undefined
const _safeSetInterval = typeof setInterval === 'function' ? setInterval : undefined
const _safeClearInterval = typeof clearInterval === 'function' ? clearInterval : undefined

// 调试日志（生产环境已关闭）。排查问题时取消下方注释即可恢复输出到 _doc/log.txt 与 console。
// 注：本基座 plus.io.FileWriter.write() 对 ArrayBuffer/Blob 会抛异常，写文件易失败，故不常开。
function _writeLog(...parts) {
  // ;(function () {
  //   try {
  //     if (typeof plus !== 'undefined' && plus.io && plus.io.requestFileSystem) {
  //       const line = '[go] ' + new Date().toISOString() + ' ' + parts.map((p) => {
  //         try { return typeof p === 'object' ? JSON.stringify(p) : String(p) } catch (_) { return String(p) }
  //       }).join(' ') + '\n'
  //       plus.io.requestFileSystem(plus.io.PRIVATE_DOC, (fs) => {
  //         fs.root.getFile('log.txt', { create: true, exclusive: false }, (entry) => {
  //           entry.createWriter((writer) => {
  //             writer.onerror = () => {}
  //             writer.onwriteend = () => {}
  //             try {
  //               writer.seek(writer.length)
  //               writer.write(line)
  //             } catch (_) {
  //               try { writer.write(line) } catch (__) {}
  //             }
  //           }, () => {})
  //         }, () => {})
  //       })
  //     }
  //   } catch (_) {}
  //   try { console.log(...parts) } catch (_) {}
  // })()
}

function _delay(ms) {
  return new Promise((resolve) => {
    if (typeof _safeSetTimeout === 'function') _safeSetTimeout(resolve, ms)
    else if (typeof setTimeout === 'function') setTimeout(resolve, ms)
    else resolve()
  })
}

// 把音频写入缓存（App 写文件），非阻塞
function _writeCache(key, ab, b64) {
  // App 端：直接在 tts_cache 目录下创建/覆盖文件，一次性 write(ArrayBuffer) 后再 truncate，
  // 防止旧文件尺寸大于新内容导致尾部残留垃圾数据，进而播放报 MediaError。
  _ensureTtsDir()
    .then((dir) => {
      dir.getFile(
        key + '.mp3',
        { create: true, exclusive: false },
        (fileEntry) => {
          fileEntry.createWriter(
            (writer) => {
              writer.onerror = () => {}
              writer.onwriteend = () => {
                // 截断到写入长度，丢弃旧文件的尾部残留
                writer.onwriteend = () => {
                  fileEntry.getMetadata(
                    (m) => _writeLog('[writeCache] wrote', key + '.mp3', 'size', m.size, 'expect', ab.byteLength),
                    () => _writeLog('[writeCache] wrote (no metadata)', key + '.mp3')
                  )
                }
                try { writer.truncate(ab.byteLength) } catch (e) {}
              }
              // 该运行时 FileWriter.write(ArrayBuffer) 会抛异常，直接写 Blob 更稳
              try {
                const blob = (typeof Blob !== 'undefined') ? new Blob([ab], { type: 'audio/mpeg' }) : ab
                writer.write(blob)
                _writeLog('[writeCache] Blob write called, bytes', ab.byteLength)
              } catch (e) {
                _writeLog('[writeCache] Blob write failed, try ArrayBuffer', e && e.message)
                try { writer.write(ab) } catch (e2) {}
              }
            },
            () => {}
          )
        },
        () => {}
      )
    })
    .catch(() => {})
}

/* ---------------- 统一朗读入口 ---------------- */
// callbacks:
//   cacheKey  - 缓存键（建议传 articleId / 句子 / 单词 的稳定标识；内部会再哈希成文件名）
//   onReady   - 后端已返回音频数据，可以收起"合成中"遮罩（App 端此时可能还在写临时文件）
//   onStart   - 开始播放（用于标记播放状态）
//   onEnd     - 播放结束
//   onError   - 播放失败
//   onAudio   - 合成成功（拿到 base64，供调用方自行持久化）
export async function speak(text, cfgOverride, callbacks = {}) {
  const cfg = cfgOverride || loadTtsConfig()
  return speakEdge(cfg, text, callbacks)
}

// 直接播放已合成的 base64 mp3（不再请求 API）。callbacks.cacheKey 仍可用于播放级去重。
export async function speakFromBase64(b64, callbacks = {}) {
  _teardownPlayer()
  const myId = ++currentId
  try {
    const ab = _b64ToArrayBuffer(String(b64 || '').replace(/\s+/g, ''))
    if (!ab || (ab.byteLength !== undefined && ab.byteLength === 0)) throw new Error('TTS 缓存音频为空')
    await _play(ab, myId, 'mp3', callbacks)
  } catch (e) {
    if (myId === currentId) playing = false
    throw e
  }
}

// unifiedtts.com Edge TTS
async function speakEdge(cfg, text, callbacks) {
  const input = String(text || '').trim()
  if (!input) throw new Error('没有可朗读的文本')
  if (!cfg.apiKey) throw new Error('未配置 TTS 密钥，请到「我的」配置')
  _teardownPlayer()
  const myId = ++currentId
  const voice = cfg.presetVoice || DEFAULT_CFG.presetVoice
  const key = _hashKey(callbacks.cacheKey != null ? String(callbacks.cacheKey) : input, voice)
  _writeLog('[speakEdge] start', 'voice', voice, 'textLen', input.length)
  try {
    // 先尝试本地缓存
    const url = await _tryCache(key, myId, callbacks)
    if (url) return
    // App 端：FileWriter 在本基座损坏，写文件必失败 → 直接拿网络直链交给原生播放器，不下载整段音频到内存。
    const urlOnly = true
    const { ab, b64, audioUrl } = await fetchUnifiedTts(cfg, input, myId, voice, { urlOnly })
    if (myId !== currentId) return
    // App：用 unifiedtts 返回的网络直链直接播放（5+ 原生播放器原生支持 http/https）
    if (!audioUrl) throw new Error('TTS 未返回音频直链')
    _writeLog('[speakEdge] got audio url (stream, no file write):', audioUrl)
    if (typeof callbacks.onReady === 'function') {
      try { callbacks.onReady() } catch (e) {}
    }
    // App 端不写文件、不下整段音频，b64 为 null，不触发 onAudio（调用方无法用 null 持久化）
    await _play(audioUrl, myId, 'mp3', callbacks)
  } catch (e) {
    if (myId === currentId) playing = false
    throw e
  }
}

// 命中缓存则直接播放并返回 true，否则返回 false
async function _tryCache(key, myId, callbacks, ab = null) {
  const cached = ab ? await _cacheURLSafe(key, ab) : await _cacheURL(key)
  if (!cached || myId !== currentId) return null
  if (typeof callbacks.onReady === 'function') {
    try { callbacks.onReady() } catch (e) {}
  }
  await _play(cached, myId, 'mp3', callbacks) // cached 为文件路径 URL
  return true
}

/* ---------------- unifiedtts.com Edge TTS ---------------- */
function fetchUnifiedTts(cfg, input, myId, voice, opts = {}) {
  const urlOnly = !!opts.urlOnly // App 端：只取音频直链，不下载整段音频
  return new Promise((resolve, reject) => {
    const url = cfg.apiUrl || DEFAULT_CFG.apiUrl
    uni.request({
      url,
      method: 'POST',
      header: {
        'X-API-Key': cfg.apiKey,
        'Content-Type': 'application/json',
      },
      data: {
        model: 'edge-tts',
        text: input,
        voice: voice || cfg.presetVoice || DEFAULT_CFG.presetVoice,
        speed: cfg.speed != null ? cfg.speed : 1.0,
        pitch: cfg.pitch != null ? cfg.pitch : 1.0,
        volume: cfg.volume != null ? cfg.volume : 1.0,
        format: 'mp3',
      },
      timeout: 60000,
      success: (raw) => {
        if (myId !== currentId) return resolve(null)
        const res = Array.isArray(raw) ? raw[1] : raw
        const status = res && res.statusCode
        let body = res && res.data
        if (typeof body === 'string') {
          try {
            body = JSON.parse(body)
          } catch (e) {
            body = null
          }
        }
        if (!body || status >= 400 || !body.success || !body.data || !body.data.audio_url) {
          let msg = 'TTS 服务返回 ' + (status || '?')
          try {
            if (body && (body.message || (body.error && body.error.message))) {
              msg = body.message || body.error.message || msg
            }
          } catch (e) {}
          return reject(new Error(msg))
        }
        const audioUrl = body.data.audio_url
        // 仅取直链模式（App 端）：靠 file_size 做基本校验，不再下载整段音频，
        // 直接把网络直链交给 plus.audio.createPlayer 播放，绕开坏掉的 FileWriter。
        if (urlOnly) {
          const fs = body.data && body.data.file_size
          if (typeof fs === 'number' && fs <= 0) {
            return reject(new Error('TTS 返回空音频(file_size=' + fs + ')'))
          }
          return resolve({ ab: null, b64: null, audioUrl })
        }
        // 第二步：下载 audio_url 得到 MP3 的 ArrayBuffer
        uni.request({
          url: audioUrl,
          method: 'GET',
          responseType: 'arraybuffer',
          timeout: 60000,
          success: (raw2) => {
            if (myId !== currentId) return resolve(null)
            const res2 = Array.isArray(raw2) ? raw2[1] : raw2
            const status2 = res2 && res2.statusCode
            let ab = res2 && res2.data
            if (ab && typeof ab === 'object' && ab.buffer instanceof ArrayBuffer) ab = ab.buffer
            if (!ab || !(ab instanceof ArrayBuffer) || (ab.byteLength !== undefined && ab.byteLength === 0)) {
              let msg = '音频下载失败 ' + (status2 || '?')
              try {
                if (typeof ab === 'string') {
                  const eb = JSON.parse(ab)
                  if (eb && eb.message) msg = eb.message
                }
              } catch (e) {}
              return reject(new Error(msg))
            }
            let b64
            try {
              b64 = uni.arrayBufferToBase64(ab)
            } catch (e) {
              b64 = _arrayBufferToBase64Fallback(ab)
            }
            resolve({ ab, b64, audioUrl })
          },
          fail: (err) => reject(new Error(err && err.errMsg ? err.errMsg : '音频下载失败')),
        })
      },
      fail: (err) => reject(new Error(err && err.errMsg ? err.errMsg : '网络请求失败')),
    })
  })
}

/* ---------------- 播放（App 用 plus.audio.createPlayer） ---------------- */
function _play(abOrUrl, myId, ext = 'mp3', callbacks = {}) {
  _writeLog('[_play] enter', 'argType', typeof abOrUrl, 'isString', typeof abOrUrl === 'string', 'len', abOrUrl && abOrUrl.byteLength != null ? abOrUrl.byteLength : (abOrUrl && abOrUrl.length))
  return new Promise((resolve, reject) => {
    let started = false
    const markStart = () => {
      if (started) return
      started = true
      if (myId === currentId) playing = true
      if (typeof callbacks.onStart === 'function') callbacks.onStart()
    }
    const onEnd = () => {
      if (myId === currentId) playing = false
      player = null
      if (typeof callbacks.onEnd === 'function') callbacks.onEnd()
      resolve()
    }
    const onErr = (e) => {
      if (myId === currentId) playing = false
      player = null
      // 把底层 errMsg 与 error.code 透传出来：MediaError.code 是区分 H1 vs H2 的关键
      // 1=ABORTED, 2=NETWORK, 3=DECODE, 4=SRC_NOT_SUPPORTED
      const msg = (e && (e.errMsg || e.message)) || '未知错误'
      const code = (e && e.code != null) ? e.code : ''
      const err = new Error('音频播放失败' + (code !== '' ? '[' + code + ']' : '') + '：' + msg)
      err.cause = e
      if (typeof callbacks.onError === 'function') callbacks.onError(err)
      reject(err)
    }

    // App 端一律只用原生 plus.audio.createPlayer（此基座 uni.createInnerAudioContext 因 setTimeout 缺失会崩），绝不用 innerAudioContext。
    const begin = (url, retryFile = true) => {
      if (myId !== currentId) return resolve()
      const useNative = !!(plus.audio && plus.audio.createPlayer)
      if (!useNative) {
        return onErr(new Error('原生音频播放器不可用'))
      }
      _writeLog('[tts] plus.audio src:', url, 'retryFile:', retryFile)
      try {
        const ap = plus.audio.createPlayer(url)
        if (!ap) throw new Error('createPlayer 返回 null')
        playing = true
        player = { stop: () => { try { ap.stop() } catch (e) {} ap.close && ap.close() }, _native: ap }
        ap.play(
          () => { if (myId === currentId) playing = false; onEnd() },
          (e) => {
            // 原生播放失败（常因设备/路径差异）：先停掉原生播放器
            try { ap.stop() } catch (_) {}
            try { ap.close && ap.close() } catch (_) {}
            const ec = (e && e.code != null) ? e.code : '?'
            const em = (e && (e.errMsg || e.message)) || 'MediaError'
            _writeLog('[tts] plus.audio play failed:', url, 'code', ec, em)
            // _doc/ 相对路径失败时，再试一次 file:// 绝对路径（部分设备可能相反）
            if (retryFile && typeof url === 'string' && url.startsWith('_doc/')) {
              try {
                const fileUrl = plus.io.convertLocalFileSystemURL(url)
                if (fileUrl && fileUrl !== url) {
                  _writeLog('[tts] retry plus.audio with file://')
                  return begin(fileUrl, false)
                }
              } catch (_) {}
            }
            // 直接上报原生错误（不再退化 innerAudioContext，避免 setTimeout 崩溃）
            onErr(new Error('原生播放失败[' + ec + ']：' + em))
          }
        )
        // 立即认为已开始（兼容性：避免 markStart 依赖 onPlay 触发）
        markStart()
        return
      } catch (e) {
        _writeLog('[tts] plus.audio createPlayer failed:', url, e && e.message)
        // _doc/ 路径失败时，再试一次 file:// 绝对路径
        if (retryFile && typeof url === 'string' && url.startsWith('_doc/')) {
          try {
            const fileUrl = plus.io.convertLocalFileSystemURL(url)
            if (fileUrl && fileUrl !== url) {
              _writeLog('[tts] retry plus.audio with file://')
              return begin(fileUrl, false)
            }
          } catch (_) {}
        }
        onErr(new Error('原生播放器异常：' + (e && e.message ? e.message : 'createPlayer 失败')))
      }
    }
    if (typeof abOrUrl === 'string') {
      begin(abOrUrl)
    } else {
      _writeTemp(abOrUrl, ext, myId)
        .then((url) => { _writeLog('[tts] temp url', url); begin(url) })
        .catch((e) => { _writeLog('[tts] writeTemp err', e); onErr(e) })
    }
  })
}

// 写入 App 本地存储为临时音频文件（文件名带 myId，避免复用同一文件被旧播放器锁住）
// App 端用 plus.io 写临时音频文件。
// write 完成后再 truncate 到实际长度，避免旧文件尾部残留导致播放 MediaError。
// 关键：plus.audio.createPlayer 必须接收 entry.toURL() 返回的 _doc/ 相对路径（如 _doc/go_tts_1.mp3），
// 不能用 file:// 绝对路径（toLocalURL()）—— file:// 会让 Android MediaPlayer 报 -5；
// 也不能用 plus.io.PRIVATE_DOC 字符串拼接（Android 上 PRIVATE_DOC 是 "_documents"，AudioPlayer 不识别）。
function _writeTemp(arrayBuffer, ext, myId) {
  return new Promise((resolve, reject) => {
    const writeOnce = (retryId) => {
      plus.io.resolveLocalFileSystemURL(
        plus.io.PRIVATE_DOC,
        (root) => {
          root.getFile(
            'go_tts_' + retryId + '.' + (ext || 'mp3'),
            { create: true, exclusive: false },
            (entry) => {
              entry.createWriter(
                (writer) => {
                  writer.onerror = (e) => {
                    if (retryId === myId) writeOnce(myId + '_2')
                    else reject(e)
                  }
                  writer.onwriteend = () => {
                    // write 完成后再 truncate，丢弃可能存在的旧文件尾部残留数据
                    writer.onwriteend = () => {
                      // 用 entry.toURL() 返回 _doc/ 相对路径（如 _doc/go_tts_1.mp3）。
                      // 关键：plus.audio.createPlayer 必须接收 _doc/ 相对路径，不能用 toLocalURL() 的 file://
                      // 绝对路径（会让 Android MediaPlayer play 报 -5）。
                      const finalUrl = entry.toURL()
                      entry.getMetadata(
                        (m) => _writeLog('[writeTemp] wrote', finalUrl, 'size', m.size),
                        () => _writeLog('[writeTemp] wrote', finalUrl, '(no metadata)')
                      )
                      resolve(finalUrl)
                    }
                    try { writer.truncate(arrayBuffer.byteLength) } catch (e) { resolve(entry.toURL()) }
                  }
                  try {
                    // 该基座的 FileWriter.write(ArrayBuffer) 会抛异常，直接用 Blob；
                    // 若连 Blob 都不可用则退回 ArrayBuffer 兜底。
                    let wrote = false
                    try {
                      const blob = (typeof Blob !== 'undefined') ? new Blob([arrayBuffer], { type: 'audio/mpeg' }) : null
                      if (blob) {
                        writer.write(blob)
                        wrote = true
                        _writeLog('[writeTemp] Blob write called, bytes', arrayBuffer.byteLength)
                      }
                    } catch (e) {
                      _writeLog('[writeTemp] Blob write failed', e && e.message)
                    }
                    if (!wrote) {
                      try { writer.write(arrayBuffer); wrote = true; _writeLog('[writeTemp] ArrayBuffer fallback write called') } catch (e2) { _writeLog('[writeTemp] ArrayBuffer fallback failed', e2 && e2.message) }
                    }
                    if (!wrote) throw new Error('write failed')
                  } catch (e) {
                    _writeLog('[writeTemp] write catch', e && e.message)
                    if (retryId === myId) writeOnce(myId + '_2')
                    else reject(e)
                  }
                },
                (e) => {
                  if (retryId === myId) writeOnce(myId + '_2')
                  else reject(e)
                }
              )
            },
            (e) => {
              if (retryId === myId) writeOnce(myId + '_2')
              else reject(e)
            }
          )
        },
        (e) => {
          if (retryId === myId) writeOnce(myId + '_2')
          else reject(e)
        }
      )
    }
    writeOnce(myId)
  })
}

function _base64ToArrayBufferFallback(b64) {
  const binary = atob(b64)
  const len = binary.length
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function _b64ToArrayBuffer(b64) {
  if (typeof uni !== 'undefined' && uni.base64ToArrayBuffer) {
    try { return uni.base64ToArrayBuffer(b64) } catch (e) {}
  }
  return _base64ToArrayBufferFallback(b64)
}

function _arrayBufferToBase64Fallback(ab) {
  const bytes = new Uint8Array(ab)
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

// 在应用启动时调用，确保默认配置存在
export function initTtsConfig() {
  loadTtsConfig()
}

// 清理：删除某篇文章的本地 TTS 缓存文件（按文章 id 推算的 key 可能不唯一，这里仅清目录）
export function clearTtsCache() {
  _ensureTtsDir()
    .then((dir) => {
      dir.removeRecursively(() => {}, () => {})
    })
    .catch(() => {})
}
