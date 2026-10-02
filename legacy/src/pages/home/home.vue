<template>
  <view class="go-page">
    <view class="go-appbar floating">
      <view class="go-appbar__title">学习首页</view>
      <view class="go-icon-btn" @tap="goMine">
        <GoIcon name="mine" :size="40" />
      </view>
    </view>

    <view class="go-content go-stagger">
      <!-- 英雄卡：连续天数 -->
      <view class="go-glass hero" data-stagger>
        <view class="hero__greet">{{ greet }}</view>
        <view v-if="brokenYesterday" class="hero__warn">
          <GoIcon name="alert" :size="28" />
          <text>昨日断签，今天续上</text>
        </view>
        <view class="hero__streak">
          <GoIcon name="flame" :size="56" class="hero__flame" />
          <text class="hero__num">{{ streak }}</text>
          <text class="hero__unit">天连续</text>
        </view>
        <text class="hero__sub">保持不断电，知识越积越厚</text>
      </view>

      <!-- 今日目标 -->
      <view class="go-glass card" data-stagger>
        <view class="card__head">
          <text class="card__title">今日目标</text>
          <view class="goal-edit" @tap="goalSheet = true">
            <text class="goal-edit__txt">每天 {{ goal }} 次</text>
            <GoIcon name="settings" :size="30" />
          </view>
        </view>
        <view class="today-num">
          <text class="today-num__cur">{{ todayCount }}</text>
          <text class="today-num__sep">/</text>
          <text class="today-num__goal">{{ goal }}</text>
          <text class="today-num__label">次测验</text>
        </view>
        <view class="go-progress">
          <view class="go-progress__bar" :style="{ width: progressPct + '%' }" />
        </view>
        <text class="today-hint" :class="{ done: isTodayDone }">
          {{ isTodayDone ? '今日已达标，明天见！' : '还差 ' + (goal - todayCount) + ' 次，去测一把' }}
        </text>
      </view>

      <!-- 学习数据 -->
      <view class="go-glass card" data-stagger>
        <view class="card__head">
          <text class="card__title">学习数据</text>
        </view>
        <view class="stats">
          <view class="stat">
            <text class="stat__num">{{ total }}</text>
            <text class="stat__label">累计测验</text>
          </view>
          <view class="stat">
            <text class="stat__num">{{ accuracy === null ? '—' : accuracy + '%' }}</text>
            <text class="stat__label">累计正确率</text>
          </view>
          <view class="stat">
            <text class="stat__num">{{ maxStreak }}</text>
            <text class="stat__label">最长连续</text>
          </view>
          <view class="stat">
            <text class="stat__num">{{ streak }}</text>
            <text class="stat__label">当前连续</text>
          </view>
        </view>
      </view>

      <!-- 成就徽章墙 -->
      <view class="go-glass card" data-stagger>
        <view class="card__head">
          <GoIcon name="trophy" :size="34" />
          <text class="card__title">成就徽章</text>
          <text class="badge-count">{{ badgeStats.unlocked }}/{{ badgeStats.total }}</text>
        </view>
        <view class="badge-group" v-for="g in badgeGroups" :key="g.cat">
          <view class="badge-group__head">
            <GoIcon :name="g.icon" :size="28" />
            <text class="badge-group__label">{{ g.label }}</text>
            <text class="badge-group__count">{{ g.unlocked }}/{{ g.total }}</text>
          </view>
          <view class="badges">
            <view
              v-for="b in g.items"
              :key="b.id"
              class="badge"
              :class="['tier-' + b.tier, { 'badge--locked': !b.unlocked }]"
            >
              <GoIcon :name="b.unlocked ? b.icon : 'lock'" :size="40" class="badge__medal" />
              <text class="badge__name">{{ b.label }}</text>
              <text class="badge__sub">{{ b.hint }}</text>
              <view v-if="!b.unlocked" class="badge__bar">
                <view class="badge__bar-fill" :style="{ width: (b.progress * 100) + '%' }" />
              </view>
            </view>
          </view>
        </view>
      </view>

      <!-- CTA -->
      <button class="go-btn go-btn--block cta" data-stagger @tap="goQuiz">
        去做测验 →
      </button>
    </view>

    <BottomNav />

    <!-- 目标设置底部弹层 -->
    <view class="go-sheet-mask" :class="{ open: goalSheet }" @tap="goalSheet = false" />
    <view class="go-sheet-up" :class="{ open: goalSheet }">
      <view class="go-sheet-handle" />
      <view class="sheet-title">每天做几次测验算达标？</view>
      <view class="goal-options">
        <view
          v-for="n in goalOptions"
          :key="n"
          class="go-chip"
          :class="{ active: goal === n }"
          @tap="pickGoal(n)"
        >
          {{ n }} 次
        </view>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref, computed } from 'vue'
import { onShow, onPullDownRefresh } from '@dcloudio/uni-app'
import GoIcon from '@/components/GoIcon.vue'
import BottomNav from '@/components/BottomNav.vue'
import { getState, setGoal, CAT_META } from '@/utils/habit.js'

const streak = ref(0)
const maxStreak = ref(0)
const total = ref(0)
const accuracy = ref(null)
const todayCount = ref(0)
const goal = ref(1)
const isTodayDone = ref(false)
const brokenYesterday = ref(false)
const badges = ref([])
const badgeStats = ref({ unlocked: 0, total: 0 })

const catOrder = ['streak', 'total', 'accuracy', 'perfect', 'over']
const badgeGroups = computed(() => {
  const map = {}
  for (const b of badges.value) (map[b.cat] = map[b.cat] || []).push(b)
  return catOrder
    .filter((c) => map[c])
    .map((c) => ({
      cat: c,
      label: CAT_META[c].label,
      icon: CAT_META[c].icon,
      items: map[c],
      unlocked: map[c].filter((b) => b.unlocked).length,
      total: map[c].length,
    }))
})

const goalOptions = [1, 2, 3, 5]
const goalSheet = ref(false)

const greet = computed(() => {
  const h = new Date().getHours()
  if (h < 6) return '夜深了'
  if (h < 12) return '早上好'
  if (h < 18) return '下午好'
  return '晚上好'
})
const progressPct = computed(() => {
  if (goal.value <= 0) return 0
  return Math.min(100, Math.round((todayCount.value / goal.value) * 100))
})

function refresh() {
  const s = getState()
  streak.value = s.streak
  maxStreak.value = s.maxStreak
  total.value = s.total
  accuracy.value = s.accuracy
  todayCount.value = s.todayCount
  goal.value = s.goal
  isTodayDone.value = s.isTodayDone
  brokenYesterday.value = s.brokenYesterday
  badges.value = s.badges
  badgeStats.value = s.badgeStats
}

function pickGoal(n) {
  setGoal(n)
  goal.value = n
  goalSheet.value = false
  refresh()
}

function goQuiz() {
  uni.reLaunch({ url: '/pages/reading/reading' })
}
function goMine() {
  uni.reLaunch({ url: '/pages/mine/mine' })
}

onShow(() => refresh())
onPullDownRefresh(() => {
  refresh()
  uni.stopPullDownRefresh()
})
</script>

<style scoped lang="scss">
.hero {
  padding: var(--go-sp-8) var(--go-sp-6);
  text-align: center;
  background:
    linear-gradient(160deg, color-mix(in srgb, var(--go-primary-95) 80%, transparent), var(--go-glass-bg)),
    var(--go-glass-bg);
  &__greet {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
    letter-spacing: 0.05em;
  }
  &__warn {
    display: inline-flex;
    align-items: center;
    gap: var(--go-sp-1);
    margin-top: var(--go-sp-3);
    padding: 6rpx 18rpx;
    border-radius: var(--go-r-full);
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-warning);
    background: color-mix(in srgb, var(--go-warning) 16%, transparent);
  }
  &__streak {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: var(--go-sp-2);
    margin-top: var(--go-sp-4);
  }
  &__flame {
    color: var(--go-tertiary);
    line-height: 1;
    filter: drop-shadow(0 4rpx 10rpx color-mix(in srgb, var(--go-tertiary) 40%, transparent));
  }
  &__num {
    font-size: 88rpx;
    font-weight: var(--go-fw-bold);
    color: var(--go-primary);
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }
  &__unit {
    font-size: var(--go-fs-h2);
    color: var(--go-on-surface-2);
    font-weight: var(--go-fw-medium);
  }
  &__sub {
    display: block;
    margin-top: var(--go-sp-3);
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
  }
}

.card {
  padding: var(--go-sp-5);
  &__head {
    display: flex;
    align-items: center;
    gap: var(--go-sp-2);
    margin-bottom: var(--go-sp-4);
  }
  &__title {
    font-size: var(--go-fs-title);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
  }
}

.goal-edit {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: var(--go-sp-1);
  padding: 6rpx 16rpx;
  border-radius: var(--go-r-full);
  font-size: var(--go-fs-meta);
  color: var(--go-primary);
  background: var(--go-primary-90);
  &:active { transform: scale(0.96); }
  &__txt { font-weight: var(--go-fw-medium); }
}

.today-num {
  display: flex;
  align-items: baseline;
  gap: var(--go-sp-1);
  margin-bottom: var(--go-sp-3);
  &__cur {
    font-size: 56rpx;
    font-weight: var(--go-fw-bold);
    color: var(--go-on-surface);
    font-variant-numeric: tabular-nums;
  }
  &__sep, &__goal {
    font-size: 40rpx;
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface-2);
  }
  &__label {
    margin-left: var(--go-sp-1);
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
  }
}
.today-hint {
  display: block;
  margin-top: var(--go-sp-3);
  font-size: var(--go-fs-meta);
  color: var(--go-on-surface-3);
  &.done { color: var(--go-success); font-weight: var(--go-fw-semibold); }
}

.stats {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: var(--go-sp-3);
}
.stat {
  display: flex;
  flex-direction: column;
  gap: 4rpx;
  padding: var(--go-sp-4);
  border-radius: var(--go-r-md);
  background: var(--go-surface-2);
  &__num {
    font-size: 44rpx;
    font-weight: var(--go-fw-bold);
    color: var(--go-on-surface);
    font-variant-numeric: tabular-nums;
  }
  &__label {
    font-size: var(--go-fs-meta);
    color: var(--go-on-surface-3);
  }
}

.badge-count {
  margin-left: auto;
  font-size: var(--go-fs-meta);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-surface-3);
  font-variant-numeric: tabular-nums;
}
.badge-group {
  margin-top: var(--go-sp-5);
  &:first-of-type { margin-top: 0; }
  &__head {
    display: flex;
    align-items: center;
    gap: var(--go-sp-2);
    margin-bottom: var(--go-sp-3);
  }
  &__label {
    font-size: var(--go-fs-body-sm);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
  }
  &__count {
    margin-left: auto;
    font-size: var(--go-fs-cap);
    color: var(--go-on-surface-3);
    font-variant-numeric: tabular-nums;
  }
}
.badges {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: var(--go-sp-3);
}
.badge {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6rpx;
  padding: var(--go-sp-4) var(--go-sp-2);
  border-radius: var(--go-r-md);
  background: var(--go-primary-95);
  border: 1rpx solid color-mix(in srgb, var(--go-primary) 24%, transparent);
  text-align: center;
  &--locked {
    background: var(--go-surface-2);
    border-color: var(--go-outline);
  }
  &__medal {
    color: var(--go-primary);
    line-height: 1;
  }
  &.tier-silver .badge__medal { color: var(--go-on-surface-3); }
  &.tier-gold .badge__medal { color: var(--go-warning); }
  &.tier-diamond .badge__medal { color: var(--go-tertiary); }
  &__name {
    font-size: var(--go-fs-meta);
    font-weight: var(--go-fw-semibold);
    color: var(--go-on-surface);
  }
  &__sub {
    font-size: var(--go-fs-cap);
    color: var(--go-on-surface-3);
  }
  &__bar {
    width: 100%;
    height: 6rpx;
    margin-top: 4rpx;
    border-radius: var(--go-r-full);
    background: var(--go-outline);
    overflow: hidden;
  }
  &__bar-fill {
    height: 100%;
    border-radius: var(--go-r-full);
    background: var(--go-primary);
  }
}

.cta {
  margin-top: var(--go-sp-4);
  height: 96rpx;
  font-size: var(--go-fs-body);
}

.go-content {
  padding-bottom: calc(var(--go-nav-h) + var(--go-safe-bottom) + var(--go-sp-4));
}

.sheet-title {
  font-size: var(--go-fs-title);
  font-weight: var(--go-fw-semibold);
  color: var(--go-on-surface);
  text-align: center;
  margin-bottom: var(--go-sp-5);
}
.goal-options {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: var(--go-sp-3);
  .go-chip { height: 72rpx; font-size: var(--go-fs-body-sm); padding: 0 var(--go-sp-6); }
}
</style>
