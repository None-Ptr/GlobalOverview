<template>
  <view class="go-page">
    <view class="go-appbar floating">
      <view class="back" @click="goBack">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <text class="go-appbar__title">{{ isEdit ? '编辑模型' : '新增模型' }}</text>
      <view class="go-appbar__actions">
        <text class="save" @click="save">保存</text>
      </view>
    </view>

    <view class="go-content">
      <view class="go-section">
        <view class="go-section__title">基本信息</view>
        <view class="go-card go-card--padded">
          <view class="field">
            <text class="field__label">名称</text>
            <input class="field__input" v-model="form.name" placeholder="如：我的 GPT" placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">API 地址</text>
            <input class="field__input" v-model="form.baseUrl" placeholder="https://api.openai.com/v1" placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">模型</text>
            <input class="field__input" v-model="form.model" placeholder="gpt-4o / claude-3-5-sonnet" placeholder-class="ph" />
          </view>
        </view>
      </view>

      <view class="go-section">
        <view class="go-section__title">密钥</view>
        <view class="go-card go-card--padded">
          <view class="field">
            <text class="field__label">API Key</text>
            <input class="field__input" v-model="form.apiKey" :password="!showKey" placeholder="sk-..." placeholder-class="ph" />
          </view>
          <view class="field field--row" @click="showKey = !showKey">
            <text class="field__label">显示密钥</text>
            <view class="go-switch" :class="{ on: showKey }"><view class="go-switch__thumb"></view></view>
          </view>
        </view>
        <text class="hint">密钥仅保存在本机，不会上传到任何服务器。</text>
      </view>

      <button class="go-btn go-btn--tonal go-btn--block" @click="testConn">测试连接</button>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import GoIcon from '@/components/GoIcon.vue'
import { useAppStore } from '@/stores/app.js'

const store = useAppStore()

const MODELS_KEY = 'go_llm_models'
const isEdit = ref(false)
const editId = ref(null)
const showKey = ref(false)

const form = ref({ name: '', baseUrl: '', model: '', apiKey: '' })

// API Key 轻度混淆后落盘：避免以明文存于 localStorage / 应用沙箱被直接读取。
// 注意：这是"防君子不防小人"的混淆（非加密），真正安全需系统级 keychain。
function obfuscateKey(k) {
  if (!k) return ''
  try { return 'obf:' + btoa(unescape(encodeURIComponent(k))) } catch (_) { return k }
}
function deobfuscateKey(v) {
  if (!v || !v.startsWith('obf:')) return v
  try { return decodeURIComponent(escape(atob(v.slice(4)))) } catch (_) { return v.slice(4) }
}

onLoad((opt) => {
  if (opt && opt.id) {
    isEdit.value = true
    editId.value = Number(opt.id)
    const list = uni.getStorageSync(MODELS_KEY) || []
    const m = list.find((x) => x.id === editId.value)
    if (m) {
      form.value = { ...m }
      // 读取时还原明文到表单（用户编辑可见）
      form.value.apiKey = deobfuscateKey(m.apiKey)
    }
  }
})

function goBack() {
  const pages = getCurrentPages()
  if (pages && pages.length > 1) uni.navigateBack()
  else uni.switchTab({ url: '/pages/mine/mine' })
}

function save() {
  if (!form.value.name.trim()) {
    uni.showToast({ title: '请填写名称', icon: 'none' })
    return
  }
  const list = uni.getStorageSync(MODELS_KEY) || []
  // 落盘前混淆 apiKey，避免明文存储
  const record = { ...form.value, id: isEdit.value ? editId.value : Date.now() }
  record.apiKey = obfuscateKey(form.value.apiKey)
  if (isEdit.value) {
    const i = list.findIndex((x) => x.id === editId.value)
    if (i >= 0) list[i] = record
  } else {
    list.push(record)
  }
  uni.setStorageSync(MODELS_KEY, list)
  // 同步到 store，确保“我的”页与出题页即时拿到最新模型（store 内存中也用混淆值，调用方需 deobfuscate）
  store.setProfiles(list.map((p) => ({ ...p, apiKey: deobfuscateKey(p.apiKey) })))
  // 若尚未指定默认模型，自动设为当前新增/编辑的模型
  const savedId = record.id
  if (!store.activeProfileId) store.setActiveProfile(savedId)
  uni.showToast({ title: '已保存', icon: 'success' })
  setTimeout(goBack, 400)
}

function testConn() {
  if (!form.value.baseUrl || !form.value.apiKey) {
    uni.showToast({ title: '先填写地址与密钥', icon: 'none' })
    return
  }
  uni.showLoading({ title: '测试中...' })
  uni.request({
    url: form.value.baseUrl.replace(/\/$/, '') + '/models',
    method: 'GET',
    header: { Authorization: 'Bearer ' + form.value.apiKey },
    timeout: 12000,
    success: (res) => {
      uni.hideLoading()
      if (res.statusCode >= 200 && res.statusCode < 300) {
        uni.showToast({ title: '连接成功', icon: 'success' })
      } else {
        uni.showToast({ title: '连接失败 ' + res.statusCode, icon: 'none' })
      }
    },
    fail: () => {
      uni.hideLoading()
      uni.showToast({ title: '连接失败：网络错误', icon: 'none' })
    }
  })
}
</script>

<style scoped lang="scss">
.save {
  font-size: var(--go-fs-body);
  font-weight: var(--go-fw-semibold);
  color: var(--go-primary);
  padding: var(--go-sp-2) var(--go-sp-2);
}
.field {
  display: flex;
  flex-direction: column;
  gap: var(--go-sp-2);
  padding: var(--go-sp-4) var(--go-sp-5);
  border-bottom: 1rpx solid var(--go-outline);
  &:last-child { border-bottom: none; }
  &--row {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
  }
  &__label {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    font-weight: var(--go-fw-medium);
  }
  &__input {
    font-size: var(--go-fs-body);
    color: var(--go-on-surface);
    min-height: 44rpx;
    background: var(--go-surface-2);
    border: 1rpx solid var(--go-outline);
    border-radius: var(--go-r-md);
    padding: var(--go-sp-3) var(--go-sp-4);
    box-sizing: border-box;
    transition: border-color var(--go-dur-fast) var(--go-ease-standard),
      box-shadow var(--go-dur-fast) var(--go-ease-standard);
    &:focus {
      border-color: var(--go-primary);
      box-shadow: 0 0 0 3rpx color-mix(in srgb, var(--go-primary) 22%, transparent);
    }
  }
}
.ph { color: var(--go-on-surface-disabled); }
.hint {
  display: block;
  font-size: var(--go-fs-cap);
  color: var(--go-on-surface-3);
  padding: var(--go-sp-3) var(--go-sp-3) 0;
  line-height: 1.5;
}
.go-switch {
  width: 84rpx;
  height: 48rpx;
  border-radius: var(--go-r-full);
  background: var(--go-surface-2);
  border: 1rpx solid var(--go-outline);
  position: relative;
  transition: background var(--go-dur-fast) var(--go-ease-standard);
  &__thumb {
    position: absolute;
    top: 4rpx;
    left: 4rpx;
    width: 40rpx;
    height: 40rpx;
    border-radius: var(--go-r-full);
    background: var(--go-surface-raised);
    box-shadow: var(--go-shadow-1);
    transition: transform var(--go-dur-med) var(--go-ease-emphasized);
  }
  &.on { background: var(--go-primary); border-color: var(--go-primary); }
  &.on &__thumb { transform: translateX(36rpx); }
}
</style>
