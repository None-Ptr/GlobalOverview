<template>
  <view class="go-page">
    <view class="go-appbar floating">
      <view class="back" @click="goBack">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <text class="go-appbar__title">语音朗读设置</text>
      <view class="go-appbar__actions">
        <text class="save" @click="save">保存</text>
      </view>
    </view>

    <view class="go-content">
      <view class="go-section">
        <view class="go-section__title">Edge TTS 服务</view>
        <view class="go-card go-card--padded">
          <view class="field">
            <view class="field__labelrow">
              <text class="field__label">API Key</text>
            </view>
            <input class="field__input" :password="!showKey" v-model="form.apiKey" placeholder="tts_..." placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">预设音色</text>
            <view class="method-row">
              <text
                v-for="v in voices"
                :key="v.id"
                class="method-chip"
                :class="{ on: form.presetVoice === v.id }"
                @click="form.presetVoice = v.id"
              >{{ v.name }}</text>
            </view>
          </view>
        </view>
      </view>

      <button class="go-btn go-btn--tonal go-btn--block" @click="testConn">朗读测试</button>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import GoIcon from '@/components/GoIcon.vue'
import { loadTtsConfig, saveTtsConfig, TTS_VOICES, speak, DEFAULT_CFG } from '@/utils/tts.js'

const voices = TTS_VOICES
const showKey = ref(false)

const form = ref({
  apiKey: '',
  presetVoice: DEFAULT_CFG.presetVoice,
})

onLoad(() => {
  const c = loadTtsConfig()
  form.value = {
    apiKey: c.apiKey || '',
    presetVoice: c.presetVoice || DEFAULT_CFG.presetVoice,
  }
})

function goBack() {
  const pages = getCurrentPages()
  if (pages && pages.length > 1) uni.navigateBack()
  // pages.json 未配置 tabBar，switchTab 必然失败；栈深为 1 时用 reLaunch 兜底
  else uni.reLaunch({ url: '/pages/mine/mine' })
}

function save() {
  if (!form.value.apiKey.trim()) {
    uni.showToast({ title: '请填写 API Key', icon: 'none' })
    return
  }
  const prev = loadTtsConfig()
  saveTtsConfig({
    ...prev,
    apiKey: form.value.apiKey.trim(),
    presetVoice: form.value.presetVoice || DEFAULT_CFG.presetVoice,
  })
  uni.showToast({ title: '已保存', icon: 'success' })
  setTimeout(goBack, 400)
}

async function testConn() {
  if (!form.value.apiKey.trim()) {
    uni.showToast({ title: '请先填写密钥', icon: 'none' })
    return
  }
  const cfg = {
    ...loadTtsConfig(),
    apiKey: form.value.apiKey.trim(),
    presetVoice: form.value.presetVoice || DEFAULT_CFG.presetVoice,
  }
  // 朗读测试：合成成功并开始播放即视为通过，不必等整段播完
  uni.showLoading({ title: '朗读中...' })
  let settled = false
  const finish = (err) => {
    if (settled) return
    settled = true
    uni.hideLoading()
    if (err) uni.showToast({ title: err.message || '测试失败', icon: 'none' })
    else uni.showToast({ title: '正在朗读示例', icon: 'none' })
  }
  try {
    speak('Hello, this is a text to speech test.', cfg, {
      onStart: () => finish(),
      onError: (e) => finish(e),
    }).catch((e) => finish(e))
  } catch (e) {
    finish(e)
  }
}
</script>

<style scoped lang="scss">
.save {
  font-size: var(--go-fs-body);
  font-weight: var(--go-fw-semibold);
  color: var(--go-primary);
  padding: var(--go-sp-2);
}
.field {
  display: flex;
  flex-direction: column;
  gap: var(--go-sp-2);
  padding: var(--go-sp-4) var(--go-sp-5);
  border-bottom: 1rpx solid var(--go-outline);
  &:last-child {
    border-bottom: none;
    padding-bottom: var(--go-sp-3);
  }
  &__label {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    font-weight: var(--go-fw-medium);
  }
  &__labelrow {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  &__toggle {
    font-size: var(--go-fs-meta);
    color: var(--go-primary);
    font-weight: var(--go-fw-medium);
    padding: var(--go-sp-1) 0;
  }
  &__input {
    font-size: var(--go-fs-body);
    color: var(--go-on-surface);
    height: 72rpx;
    line-height: 72rpx;
    background: var(--go-surface-2);
    border: 1rpx solid var(--go-outline);
    border-radius: 8rpx;
    padding: 0 var(--go-sp-4);
    box-sizing: border-box;
    transition: border-color var(--go-dur-fast) var(--go-ease-standard),
      box-shadow var(--go-dur-fast) var(--go-ease-standard);
    &:focus {
      border-color: var(--go-primary);
      box-shadow: 0 0 0 3rpx color-mix(in srgb, var(--go-primary) 22%, transparent);
    }
  }
}
.method-row {
  display: flex;
  gap: var(--go-sp-2);
  flex-wrap: wrap;
}
.method-chip {
  padding: var(--go-sp-1) var(--go-sp-4);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-2);
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-full);
  background: var(--go-surface-2);
  &.on {
    color: var(--go-on-primary);
    background: var(--go-primary);
    border-color: var(--go-primary);
  }
}
.ph {
  color: var(--go-on-surface-disabled);
}
.hint {
  display: block;
  font-size: var(--go-fs-cap);
  color: var(--go-on-surface-3);
  padding: var(--go-sp-3) var(--go-sp-3) 0;
  line-height: 1.5;
}
</style>
