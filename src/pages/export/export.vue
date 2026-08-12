<template>
  <view class="page">
    <view class="go-appbar floating">
      <text class="go-appbar__title">导出</text>
    </view>
    <scroll-view scroll-y class="scroll">
      <view class="sec">
        <text class="sec-title">导出内容</text>
        <view class="src">
          <text class="src-chip" :class="{ on: mode === 'set' }" @click="switchMode('set')">题集</text>
          <text class="src-chip" :class="{ on: mode === 'wrong' }" @click="switchMode('wrong')">错题本</text>
        </view>
        <text v-if="mode === 'wrong'" class="hint">合并当前全部错题为一份练习</text>

        <view v-if="mode === 'set' && setList.length" class="set-pick">
          <text
            v-for="s in setList"
            :key="s.id"
            class="set-chip"
            :class="{ on: String(s.id) === String(setId) }"
            @click="selectSet(s.id)"
          >{{ s.title || ('题集 #' + s.id) }}</text>
        </view>
        <text class="count">共 {{ questions.length }} 题</text>
      </view>

      <view class="sec">
        <text class="sec-title">包含项开关</text>
        <view class="switch-row" v-for="s in switchList" :key="s.key">
          <text class="sw-label">{{ s.label }}</text>
          <switch :checked="switches[s.key]" @change="(e) => (switches[s.key] = e.detail.value)" />
        </view>
        <view class="switch-row" v-if="mode === 'set'">
          <text class="sw-label">含原文</text>
          <switch :checked="switches.article" @change="(e) => (switches.article = e.detail.value)" />
        </view>
      </view>

      <view class="sec">
        <text class="sec-title">模板源码（建议勿动）</text>
        <textarea class="tpl" v-model="tplSource" placeholder="模板源码" placeholder-class="go-field__ph" />
        <view class="tpl-actions">
          <text class="ta" @click="resetTpl">恢复默认</text>
          <text class="ta" @click="saveTpl">保存模板</text>
        </view>
        <text class="hint">
          tips：如果需要自定义的话，请看以下提示：
          可用变量：title、subtitle、date、count；questions 循环内可用
          index、type、prompt、options、answer、analysis、sourceQuote、mine，
          以及 showAnswer / showAnalysis / showMine / showQuote 四个开关
          （由上方开关控制是否渲染）。
        </text>
      </view>
    </scroll-view>

    <view class="actions-bar">
      <text class="preview" @click="doPreview">预览</text>
      <text class="go" @click="doExport">导出 PDF</text>
    </view>
  </view>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import {
  buildHtml, exportPdf, previewHtmlApp, getTemplate, saveTemplate, resetTemplate,
  loadSetQuestions, loadArticleSets, loadWrongQuestions, loadArticleSource, DEFAULT_TEMPLATE,
  _checkShareReady,
} from '@/utils/export.js'
import { useAppStore } from '@/stores/app.js'
import { useTransition } from '@/composables/useTransition'

const store = useAppStore()
const transition = useTransition('secondary')
onShow(() => transition.onEnter())

const mode = ref('set')
const setId = ref(0)
const articleId = ref(0)
const setList = ref([])
const questions = ref([])
const tplSource = ref('')

const switches = ref({ answer: true, analysis: true, mine: false, quote: true, article: true })
const switchList = [
  { key: 'answer', label: '含参考答案' },
  { key: 'analysis', label: '含解析' },
  { key: 'mine', label: '含我的作答' },
  { key: 'quote', label: '含原文引用' },
]
const busy = ref(false)

onLoad((q) => {
  setId.value = Number(q && q.setId) || 0
  articleId.value = Number(q && q.articleId) || 0
  if (q && q.wrong) mode.value = 'wrong'
})

onMounted(async () => {
  try {
    tplSource.value = await getTemplate('default')
  } catch (e) {
    tplSource.value = DEFAULT_TEMPLATE
  }
  if (articleId.value) {
    setList.value = await loadArticleSets(articleId.value)
    if (setList.value.length && !setId.value) setId.value = setList.value[0].id
  }
  await refresh()
})

function switchMode(m) {
  mode.value = m
  refresh()
}

function selectSet(id) {
  setId.value = id
  refresh()
}

async function refresh() {
  try {
    questions.value = mode.value === 'wrong'
      ? await loadWrongQuestions(articleId.value || null)
      : (setId.value ? await loadSetQuestions(setId.value) : [])
  } catch (e) {
    questions.value = []
    uni.showToast({ title: e.message || '读取失败', icon: 'none' })
  }
}

function currentTitle() {
  if (mode.value === 'wrong') return '错题本练习'
  const s = setList.value.find((x) => String(x.id) === String(setId.value))
  return s && s.title ? s.title : `题集 #${setId.value}`
}

function buildOptions() {
  return {
    withAnswer: switches.value.answer,
    withAnalysis: switches.value.analysis,
    withMine: switches.value.mine,
    withQuote: switches.value.quote,
  }
}

async function makeHtml() {
  if (!questions.value.length) throw new Error('没有可导出的题目')
  // 题集模式才挂载原文；错题本合并多篇文章，加原文会割裂/重复，因此不挂载
  let articleTitle = ''
  let articleBody = ''
  if (mode.value === 'set' && articleId.value) {
    try {
      const a = await loadArticleSource(articleId.value)
      articleTitle = a.title || ''
      articleBody = a.body || ''
    } catch (e) { /* 忽略，取不到原文也不阻塞导出 */ }
  }
  return buildHtml({
    title: currentTitle(),
    subtitle: mode.value === 'wrong' ? '错题重练' : '',
    questions: questions.value,
    options: buildOptions(),
    articleTitle,
    articleBody,
    withArticle: mode.value === 'set' && !!switches.value.article,
  })
}

async function doPreview() {
  try {
    const html = await makeHtml()
    if (!previewHtmlApp(html)) {
      uni.showModal({
        title: '预览',
        content: `已渲染 ${questions.value.length} 题，点「导出 PDF」查看完整排版。`,
        showCancel: false,
      })
    }
  } catch (e) {
    uni.showToast({ title: e.message || '预览失败', icon: 'none' })
  }
}

async function doExport() {
  if (busy.value) return
  busy.value = true
  uni.showLoading({ title: '生成中…', mask: true })
  try {
    const html = await makeHtml()
    const r = await exportPdf(html, mode.value === 'wrong' ? 'wrong' : `set_${setId.value}`)
    // export.js 现在永远 resolve（不再 reject 超时）：
    //   r.note 携带平台提示 / r.mode 说明走了哪条路径
    if (r && r.note) {
      // 先弹个短 toast，再给用户一个不阻塞的 ActionSheet 让其选择"复制/分享/忽略"
      try {
        uni.showActionSheet({
          itemList: ['复制全文', '系统分享', '忽略'],
          success: async (res) => {
            const tapIndex = res.tapIndex
            if (tapIndex === 0) {
              // 复制全文（HTML 或 文本）
              const text = extractHtmlText(html)
              uni.setClipboardData({ data: text, success: () => uni.showToast({ title: '已复制', icon: 'none' }) })
            } else if (tapIndex === 1) {
              try {
                const shareReady = _checkShareReady();
                if (shareReady && r.file && typeof plus !== 'undefined' && plus.share) {
                  plus.share.sendWithSystem({ type: 'file', files: [r.file], title: '练习卷导出' }, () => {}, () => {})
                } else { uni.showToast({ title: '未找到可用的分享应用', icon: 'none' }) }
              } catch (e) { uni.showToast({ title: '分享失败', icon: 'none' }) }
            }
          },
        })
      } catch (e) { /* ignore */ }
      uni.showToast({ title: '已打开预览', icon: 'none', duration: 1500 })
    } else {
      uni.showToast({ title: '已调起打印', icon: 'none' })
    }
  } catch (e) {
    uni.showModal({ title: '导出失败', content: e.message || '未知错误', showCancel: false })
  } finally {
    uni.hideLoading()
    busy.value = false
  }
}

// 把导出 HTML 摘要成可读文本，便于"复制全文"
function extractHtmlText(html) {
  if (!html) return ''
  try {
    // 移除所有 html 标签，保留纯文本（给复制到聊天/Word 用）
    return String(html)
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s{2,}/g, ' ')
      .trim()
  } catch (e) {
    return ''
  }
}

async function saveTpl() {
  try {
    await saveTemplate('default', tplSource.value)
    uni.showToast({ title: '模板已保存', icon: 'success' })
  } catch (e) {
    uni.showToast({ title: e.message || '保存失败', icon: 'none' })
  }
}

async function resetTpl() {
  try {
    tplSource.value = await resetTemplate('default')
    uni.showToast({ title: '已恢复默认', icon: 'none' })
  } catch (e) {
    uni.showToast({ title: e.message || '恢复失败', icon: 'none' })
  }
}
</script>

<style scoped lang="scss">
.page {
  box-sizing: border-box;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  padding-top: var(--go-safe-top);
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom));
  background: var(--go-bg);
  color: var(--go-on-surface);
}
.scroll { flex: 1; padding: var(--go-sp-4) var(--go-sp-5) var(--go-sp-6); box-sizing: border-box; }
.sec { margin-bottom: var(--go-sp-6); background: var(--go-surface); border-radius: var(--go-r-lg); overflow: hidden; box-shadow: var(--go-shadow-1); border: 1rpx solid var(--go-outline); }
.sec-title { font-size: var(--go-fs-meta); font-weight: var(--go-fw-semibold); text-transform: uppercase; letter-spacing: 1rpx; color: var(--go-on-surface-3); display: block; margin: var(--go-sp-2) 0 var(--go-sp-1) var(--go-sp-5); }
.src { display: flex; flex-wrap: wrap; gap: var(--go-sp-3); padding: var(--go-sp-2) var(--go-sp-5) var(--go-sp-5); }
.src-chip { padding: var(--go-sp-2) var(--go-sp-6); border-radius: var(--go-r-full); background: var(--go-surface-2); font-size: var(--go-fs-meta); color: var(--go-on-surface-2); transition: background var(--go-dur-fast) var(--go-ease-standard), color var(--go-dur-fast) var(--go-ease-standard); }
.src-chip:active { transform: scale(.95); }
.src-chip.on { background: var(--go-primary); color: var(--go-on-primary); }
.set-pick { display: flex; flex-wrap: wrap; gap: var(--go-sp-3); padding: var(--go-sp-2) var(--go-sp-5) var(--go-sp-5); }
.set-chip { padding: var(--go-sp-2) var(--go-sp-5); border-radius: var(--go-r-full); background: var(--go-surface-2); font-size: var(--go-fs-meta); color: var(--go-on-surface-2); transition: background var(--go-dur-fast) var(--go-ease-standard), color var(--go-dur-fast) var(--go-ease-standard); }
.set-chip:active { transform: scale(.94); }
.set-chip.on { background: var(--go-primary-95); color: var(--go-primary); }
.count { display: block; font-size: var(--go-fs-meta); color: var(--go-on-surface-3); padding: 0 var(--go-sp-5) var(--go-sp-4); }
.hint { font-size: var(--go-fs-meta); color: var(--go-on-surface-3); display: block; margin-top: var(--go-sp-3); line-height: var(--go-lh-normal); }
.switch-row { display: flex; align-items: center; justify-content: space-between; padding: var(--go-sp-4) var(--go-sp-5); border-bottom: 1rpx solid var(--go-outline); }
.switch-row:last-child { border-bottom: none; }
.sw-label { font-size: var(--go-fs-body-sm); color: var(--go-on-surface); }
.tpl { width: 100%; height: 320rpx; border: 1rpx solid var(--go-outline); border-radius: var(--go-r-md); padding: var(--go-sp-3); font-size: var(--go-fs-meta); line-height: 1.5; box-sizing: border-box; background: var(--go-surface-2); color: var(--go-on-surface); caret-color: var(--go-primary); }
.tpl-actions { display: flex; gap: var(--go-sp-6); margin-top: var(--go-sp-3); padding: 0 var(--go-sp-5) var(--go-sp-4); }
.ta { color: var(--go-primary); font-size: var(--go-fs-body-sm); }
.ta:active { opacity: .5; }
.actions-bar { display: flex; gap: var(--go-sp-4); padding: var(--go-sp-4) var(--go-sp-5); border-top: 1rpx solid var(--go-outline); background: color-mix(in srgb, var(--go-surface-raised) 86%, transparent); backdrop-filter: blur(20px); }
.preview { flex: 1; text-align: center; padding: var(--go-sp-4); background: var(--go-surface-2); border-radius: var(--go-r-full); color: var(--go-on-surface); font-size: var(--go-fs-body-sm); transition: transform var(--go-dur-fast) var(--go-ease-standard), opacity var(--go-dur-fast) var(--go-ease-standard); }
.preview:active { transform: scale(.97); opacity: .7; }
.go { flex: 1; text-align: center; padding: var(--go-sp-4); background: var(--go-primary); border-radius: var(--go-r-full); color: var(--go-on-primary); font-size: var(--go-fs-body-sm); font-weight: var(--go-fw-semibold); transition: transform var(--go-dur-fast) var(--go-ease-standard), opacity var(--go-dur-fast) var(--go-ease-standard); }
.go:active { transform: scale(.97); opacity: .9; }
</style>
