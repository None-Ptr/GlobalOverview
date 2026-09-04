<template>
  <view class="go-page">
    <view class="go-appbar floating">
      <view class="back" @click="goBack">
        <GoIcon name="arrow-left" class="back-svg" :size="'52rpx'" />
      </view>
      <text class="go-appbar__title">{{ isEdit ? '编辑翻译接口' : '新增翻译接口' }}</text>
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
            <input class="field__input" v-model="form.name" placeholder="如：腾讯云 / 有道" placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">请求地址</text>
            <input class="field__input" v-model="form.url" placeholder="https://.../translate" placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">请求方法</text>
            <view class="method-row">
              <text
                v-for="m in ['POST', 'GET']"
                :key="m"
                class="method-chip"
                :class="{ on: form.method === m }"
                @click="form.method = m"
              >{{ m }}</text>
            </view>
          </view>
        </view>
      </view>

      <view class="go-section">
        <view class="go-section__title">请求与响应</view>
        <view class="go-card go-card--padded">
          <view class="field">
            <text class="field__label">结果提取路径（JSON）</text>
            <input class="field__input" v-model="form.resultPath" placeholder="如 data.translation / data.choices[0].text" placeholder-class="ph" />
          </view>
          <view class="field">
            <text class="field__label">请求头（JSON，可选）</text>
            <textarea class="field__input field__area" v-model="form.headers" placeholder='如 {"Authorization": "Bearer xxx"}' placeholder-class="ph" auto-height />
          </view>
          <view class="field">
            <text class="field__label">请求体模板（JSON，可选）</text>
            <textarea
              class="field__input field__area"
              v-model="form.body"
              placeholder='占位符 {text} {target} {lang}，如 {"q": "{text}", "target": "{lang}", "source": "en"}'
              placeholder-class="ph"
              auto-height
            />
          </view>
          <view class="field">
            <text class="field__label">目标语言映射（JSON，可选）</text>
            <textarea class="field__input field__area" v-model="form.langMap" placeholder='如 {"ZH":"zh","EN":"en"}' placeholder-class="ph" auto-height />
          </view>
        </view>
        <text class="hint">URL 支持 {text} {target} {lang} 占位符；不填请求体时按 {"q":文字, "target":语言, "source":"en"} 发送。</text>
      </view>

      <button class="go-btn go-btn--tonal go-btn--block" @click="testConn">测试</button>
      <button v-if="isEdit" class="go-btn go-btn--error go-btn--block" @click="remove">删除接口</button>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import GoIcon from '@/components/GoIcon.vue'
import { loadCustomTranslators, upsertTranslator, deleteTranslator } from '@/utils/customTranslate.js'
import { translate_custom } from '@/utils/translate.js'

const isEdit = ref(false)
const editId = ref(null)
const form = ref({
  name: '',
  url: '',
  method: 'POST',
  headers: '',
  body: '',
  resultPath: 'data.translation',
  langMap: '',
})

onLoad((opt) => {
  if (opt && opt.id) {
    isEdit.value = true
    editId.value = String(opt.id)
    const cfg = loadCustomTranslators().find((x) => x.id === editId.value)
    if (cfg) {
      form.value = {
        name: cfg.name || '',
        url: cfg.url || '',
        method: cfg.method || 'POST',
        headers: cfg.headers || '',
        body: cfg.body || '',
        resultPath: cfg.resultPath || 'data.translation',
        langMap: cfg.langMap || '',
      }
    }
  }
})

function goBack() {
  const pages = getCurrentPages()
  if (pages && pages.length > 1) uni.navigateBack()
  // pages.json 未配置 tabBar，switchTab 必然失败；栈深为 1 时用 reLaunch 兜底
  else uni.reLaunch({ url: '/pages/mine/mine' })
}

function save() {
  if (!form.value.name.trim()) {
    uni.showToast({ title: '请填写名称', icon: 'none' })
    return
  }
  if (!form.value.url.trim()) {
    uni.showToast({ title: '请填写请求地址', icon: 'none' })
    return
  }
  if (form.value.headers.trim()) {
    try { JSON.parse(form.value.headers) } catch (e) {
      uni.showToast({ title: '请求头不是合法 JSON', icon: 'none' }); return
    }
  }
  if (form.value.body.trim()) {
    try { JSON.parse(form.value.body) } catch (e) {
      uni.showToast({ title: '请求体不是合法 JSON', icon: 'none' }); return
    }
  }
  if (form.value.langMap.trim()) {
    try { JSON.parse(form.value.langMap) } catch (e) {
      uni.showToast({ title: '语言映射不是合法 JSON', icon: 'none' }); return
    }
  }
  upsertTranslator({
    id: editId.value || undefined,
    name: form.value.name.trim(),
    url: form.value.url.trim(),
    method: form.value.method,
    headers: form.value.headers.trim(),
    body: form.value.body.trim(),
    resultPath: form.value.resultPath.trim() || 'data.translation',
    langMap: form.value.langMap.trim(),
  })
  uni.showToast({ title: '已保存', icon: 'success' })
  setTimeout(goBack, 400)
}

function remove() {
  uni.showModal({
    title: '删除接口',
    content: '删除后将从翻译引擎列表移除，确定？',
    success: (r) => {
      if (r.confirm) {
        deleteTranslator(editId.value)
        uni.showToast({ title: '已删除', icon: 'success' })
        setTimeout(goBack, 300)
      }
    },
  })
}

async function testConn() {
  if (!form.value.url.trim()) {
    uni.showToast({ title: '先填写请求地址', icon: 'none' })
    return
  }
  uni.showLoading({ title: '测试中...' })
  try {
    // 用当前表单内容临时构造一个配置，直接调用通用适配器验证连通性与响应解析
    const cfg = {
      url: form.value.url.trim(),
      method: form.value.method,
      headers: form.value.headers.trim(),
      body: form.value.body.trim(),
      resultPath: form.value.resultPath.trim() || 'data.translation',
      langMap: form.value.langMap.trim(),
    }
    const out = await translate_custom(cfg, 'Hello world', 'ZH')
    uni.hideLoading()
    uni.showModal({
      title: '测试成功',
      content: `返回译文：${String(out).slice(0, 120) || '（空）'}`,
      showCancel: false,
    })
  } catch (e) {
    uni.hideLoading()
    uni.showToast({ title: e.message || '测试失败', icon: 'none' })
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
  &:last-child { border-bottom: none; }
  &__label {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    font-weight: var(--go-fw-medium);
  }
  &__input {
    // 单行 input：固定高度 + 圆角矩形，避免 rpx min-height 在 app 端解析成胶囊
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
  &__area {
    // 多行 textarea：min-height 走像素兜底，圆角保持，禁用 auto-height 的胶囊化
    font-size: var(--go-fs-body);
    color: var(--go-on-surface);
    min-height: 120px;
    line-height: 1.5;
    background: var(--go-surface-2);
    border: 1rpx solid var(--go-outline);
    border-radius: 8rpx;
    padding: var(--go-sp-3) var(--go-sp-4);
    box-sizing: border-box;
    width: 100%;
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
.ph { color: var(--go-on-surface-disabled); }
.hint {
  display: block;
  font-size: var(--go-fs-cap);
  color: var(--go-on-surface-3);
  padding: var(--go-sp-3) var(--go-sp-3) 0;
  line-height: 1.5;
}
.go-btn--error {
  color: var(--go-error, #b3261e);
  margin-top: var(--go-sp-4);
}
</style>
