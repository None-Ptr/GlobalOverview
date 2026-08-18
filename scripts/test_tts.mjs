// 测试 unifiedtts Edge TTS 调用链路：POST 拿 audio_url -> GET 下载 MP3 -> 校验文件有效性
import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const API_KEY = 'tts_0_6MQXw-VN22wVz_G3f36cIqLF21g78Yh6ty3YzpASo'
const API_URL = 'https://unifiedtts.com/api/v1/common/tts-sync'
const VOICE = 'en-US-JennyNeural'
const TEXT = 'Hello, this is a test of the Edge TTS pipeline.'
const OUT = join(dirname(fileURLToPath(import.meta.url)), '_tts_test.mp3')

function b64(bytes) {
  let s = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    s += Buffer.from(bytes.subarray(i, i + chunk)).toString('base64')
  }
  return s
}

// 检查 MP3 文件头：ID3 标签 或 MP3 frame sync (0xFF 0xEx / 0xFF 0xFx)
function inspectHead(bytes) {
  const head = bytes.subarray(0, 4)
  const isID3 = head[0] === 0x49 && head[1] === 0x44 && head[2] === 0x33 // "ID3"
  // frame sync: 11 bits set => (b0 & 0xFF)==0xFF && (b1 & 0xE0)==0xE0
  const isFrame = head[0] === 0xff && (head[1] & 0xe0) === 0xe0
  return { firstBytes: [...head].map((b) => '0x' + b.toString(16).padStart(2, '0')), isID3, isFrame }
}

async function main() {
  console.log('[1] POST', API_URL)
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: { 'X-API-Key': API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'edge-tts',
      text: TEXT,
      voice: VOICE,
      speed: 1.0,
      pitch: 1.0,
      volume: 1.0,
      format: 'mp3',
    }),
  })
  console.log('  status:', res.status, res.statusText)
  const json = await res.json()
  console.log('  body:', JSON.stringify(json).slice(0, 300))
  if (!json.success || !json.data || !json.data.audio_url) {
    throw new Error('API 未返回 audio_url')
  }
  const audioUrl = json.data.audio_url
  const apiFileSize = json.data.file_size
  console.log('[2] audio_url:', audioUrl)
  console.log('    api file_size:', apiFileSize)

  console.log('[3] GET audio data')
  const audioRes = await fetch(audioUrl)
  console.log('  status:', audioRes.status, audioRes.statusText)
  const ab = await audioRes.arrayBuffer()
  const bytes = new Uint8Array(ab)
  console.log('  downloaded bytes:', bytes.length)

  console.log('[4] inspect head')
  const head = inspectHead(bytes)
  console.log('  ', JSON.stringify(head))

  const b = b64(bytes)
  console.log('[5] base64 length:', b.length, '(expect ~', Math.round(bytes.length * 1.34), ')')

  writeFileSync(OUT, Buffer.from(bytes))
  console.log('[6] saved ->', OUT)
  console.log('  size on disk:', Buffer.from(bytes).length)

  const ok = bytes.length > 1024 && (head.isID3 || head.isFrame)
  console.log('\nRESULT:', ok ? 'OK 音频文件有效' : 'FAIL 音频文件异常')
  if (!ok) process.exit(1)
}

main().catch((e) => {
  console.error('TEST ERROR:', e)
  process.exit(1)
})
