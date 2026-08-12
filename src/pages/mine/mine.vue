<template>
  <view class="go-page">
    <view class="go-appbar floating">
      <text class="go-appbar__title">我的</text>
    </view>

    <view class="go-content go-stagger">
      <!-- LLM 模型配置 -->
      <view class="go-section" data-stagger>
        <view class="go-section__title">LLM 模型配置</view>
        <view v-if="models.length" class="go-card">
          <view
            v-for="m in models"
            :key="m.id"
            class="go-row"
            @click="editModel(m)"
          >
            <view class="go-row__icon">
              <GoIcon name="robot" class="mi" :size="'48rpx'" />
            </view>
            <view class="go-row__body">
              <view class="go-row__title">{{ m.name }}</view>
              <view class="go-row__sub">{{ m.baseUrl }} · {{ m.model }}</view>
            </view>
            <view class="go-row__trail">
              <view class="go-icon-btn danger" @click.stop="deleteModel(m)">
                <GoIcon name="trash" class="mi" :size="'48rpx'" />
              </view>
              <view class="go-row__chevron mi">›</view>
            </view>
          </view>
        </view>
        <view v-else class="go-empty go-empty--card">
          <text class="go-empty__desc">尚未配置模型，添加后可启用 AI 解析</text>
        </view>
        <button class="go-btn go-btn--tonal go-btn--block add-model" @click="addModel">＋ 新增模型</button>
      </view>

      <!-- 全局备考目标 -->
      <view class="go-section" data-stagger>
        <view class="go-section__title">难度设置</view>
        <view class="go-card go-card--padded goal-card">
          <view class="goal-card__head">
            <view class="goal-card__icon"><GoIcon name="target" class="mi" :size="'48rpx'" /></view>
            <view class="goal-card__title">对标考试难度</view>
          </view>
          <view class="goal-card__desc">未指定考试时按此难度出题</view>
          <view class="goal-card__picks">
            <view
              v-for="lv in levels"
              :key="lv"
              class="goal-pick"
              :class="{ active: targetLevel === lv }"
              @click="setTarget(lv)"
            >{{ lv }}</view>
          </view>
        </view>
      </view>


      <!-- 数据管理 -->
      <view class="go-section" data-stagger>
        <view class="go-section__title">数据管理</view>
        <view class="go-card">
          <view class="go-row" @click="goWrong">
            <view class="go-row__icon"><GoIcon name="book-check" class="mi" :size="'48rpx'" /></view>
            <view class="go-row__body">
              <view class="go-row__title">错题本</view>
              <view class="go-row__sub">查看并改错答错的题目</view>
            </view>
            <view class="go-row__chevron mi">›</view>
          </view>
          <view class="go-row" @click="clearCache">
            <view class="go-row__icon"><GoIcon name="broom" class="mi" :size="'48rpx'" /></view>
            <view class="go-row__body">
              <view class="go-row__title">清除缓存</view>
              <view class="go-row__sub">清空抓取列表与词典缓存，保留题目与错题</view>
            </view>
            <view class="go-row__chevron mi">›</view>
          </view>
          <view class="go-row" @click="clearAll">
            <view class="go-row__icon danger-icon"><GoIcon name="alert" class="mi" :size="'48rpx'" /></view>
            <view class="go-row__body">
              <view class="go-row__title danger-text">清空全部数据</view>
              <view class="go-row__sub">删除文章、题集、错题与计划，保留模型配置</view>
            </view>
            <view class="go-row__chevron mi">›</view>
          </view>
        </view>
      </view>

      <view class="foot-note">GlobalOverview · By ShaDouBuShi & _Null_Ptr</view>
    </view>

    <BottomNav />
  </view>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { useAppStore } from '@/stores/app.js'
import BottomNav from '@/components/BottomNav.vue'
import GoIcon from '@/components/GoIcon.vue'
import { db } from '@/utils/db.js'
import { EXAM_MAP } from '@/utils/quiz.js'

const store = useAppStore()

const models = ref([])
const targetLevel = ref('CET6')
// 考试档位：从 quiz.js 的 EXAM_MAP 动态读取，单一事实来源
const levels = Object.keys(EXAM_MAP)

const MODELS_KEY = 'go_llm_models'

function loadModels() {
  models.value = uni.getStorageSync(MODELS_KEY) || []
}
async function loadGoal() {
  const r = await db.select(`SELECT value FROM kv WHERE key='targetLevel'`)
  if (r.length) {
    let v = r[0].value
    // 兼容旧值：「考研」→ NCEE（quiz.js 重命名后）
    if (v === '考研') v = 'NCEE'
    // 校验合法性：仅接受当前 EXAM_MAP 中存在的档位，避免脏数据静默改写用户目标
    if (!EXAM_MAP[v]) {
      console.warn('[mine] 读取到未知 targetLevel:', v, '保留当前默认值')
    } else {
      targetLevel.value = v
      // 与全局 store 保持一致：避免「全局备考目标」已改但 plan 页/出题等仍读到旧值
      store.setGoal(v)
    }
  }
}

function addModel() {
  uni.navigateTo({ url: '/pages/model-form/model-form' })
}
function editModel(m) {
  uni.navigateTo({ url: '/pages/model-form/model-form?id=' + m.id })
}
async function deleteModel(m) {
  uni.showModal({
    title: '删除模型',
    content: `确认删除「${m.name}」？`,
    success: (res) => {
      if (res.confirm) {
        models.value = models.value.filter((x) => x.id !== m.id)
        uni.setStorageSync(MODELS_KEY, models.value)
      }
    }
  })
}
async function setTarget(lv) {
  targetLevel.value = lv
  await db.execute(`INSERT OR REPLACE INTO kv(key,value) VALUES('targetLevel',${db.sqlVal(lv)})`)
  store.setGoal(lv)
}
function goWrong() {
  uni.navigateTo({ url: '/pages/wrong/wrong' })
}
async function clearCache() {
  uni.showModal({
    title: '清除缓存',
    content: '将清空抓取列表与词典缓存，题目与错题不受影响。',
    success: async (res) => {
      if (res.confirm) {
        await db.execute('DELETE FROM feed_items')
        await db.execute('DELETE FROM dict_cache')
        uni.showToast({ title: '已清除', icon: 'success' })
      }
    }
  })
}
async function clearAll() {
  uni.showModal({
    title: '清空全部数据',
    content: '将删除文章、题集、错题与计划，且不可恢复。模型配置会保留。',
    confirmColor: '#d23f3f',
    success: async (res) => {
      if (res.confirm) {
        // 仅清除真实存在的业务表（schema 无 wrong_items/quiz_sets/plans 等表）
        for (const t of ['articles', 'feed_items', 'question_sets', 'questions', 'plan_items', 'word_cache']) {
          try { await db.execute(`DELETE FROM ${t}`) } catch (e) { /* 表不存在则跳过 */ }
        }
        uni.showToast({ title: '已清空', icon: 'success' })
      }
    }
  })
}

onMounted(async () => {
  await db.init()
  await loadModels()
  await loadGoal()
})
// 从模型配置页返回（tab 页被缓存，onMounted 不会重跑），需在此刷新列表
onShow(async () => {
  loadModels()
  loadGoal()
})
</script>

<style scoped lang="scss">
/* class="mi" 会被 Vue 透传到 GoIcon 根 <svg>，
   但子组件根不带父级的 scoped data-v-xxx，
   所以必须用 :deep() 才能命中。 */
:deep(.mi) {
  font-size: 32rpx;
  line-height: 1;
  color: inherit;
  display: inline-block;
}

.add-model {
  margin-top: var(--go-sp-4);
}

.go-empty--card {
  background: var(--go-surface);
  border: 1rpx solid var(--go-outline);
  border-radius: var(--go-r-lg);
  padding: var(--go-sp-8) var(--go-sp-5);
  margin-bottom: var(--go-sp-4);
  &__desc { max-width: none; }
}

.go-icon-btn {
  width: 64rpx;
  height: 64rpx;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--go-r-full);
  color: var(--go-on-surface-2);
  background: transparent;
  transition: background var(--go-dur-fast) var(--go-ease-standard);
  &:active { background: var(--go-sel); }
  &.danger { color: var(--go-danger); }
}

.goal-card {
  &__head {
    display: flex;
    align-items: center;
    gap: var(--go-sp-3);
  }
  &__icon {
    width: 56rpx;
    height: 56rpx;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--go-r-sm);
    background: var(--go-primary-95);
  }
  &__title {
    font-size: var(--go-fs-body);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
  }
  &__desc {
    margin-top: var(--go-sp-2);
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
  }
  &__picks {
    margin-top: var(--go-sp-4);
    display: flex;
    flex-wrap: wrap;
    gap: var(--go-sp-2);
  }
}
.goal-pick {
  padding: 12rpx 28rpx;
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-medium);
  color: var(--go-on-surface-2);
  background: var(--go-surface-2);
  border: 1rpx solid var(--go-outline);
  transition: all var(--go-dur-fast) var(--go-ease-standard);
  &:active { transform: scale(0.96); }
  &.active {
    color: var(--go-on-primary);
    background: var(--go-primary);
    border-color: var(--go-primary);
  }
}

.danger-icon { background: color-mix(in srgb, var(--go-danger) 14%, transparent); }
.danger-text { color: var(--go-error); }

.foot-note {
  text-align: center;
  font-size: var(--go-fs-cap);
  color: var(--go-on-surface-disabled);
  margin-top: var(--go-sp-8);
  letter-spacing: 0.04em;
}
</style>
