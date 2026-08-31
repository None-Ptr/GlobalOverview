// 学习习惯 / 连续打卡（"不断电"）本地存储层。
// 与 SQLite 完全解耦：只用 uni.setStorageSync / getStorageSync，
// 数据量极小（日期集合 + 几个计数器 + 设置），无需建表 / 迁移 / 内存引擎兼容。
//
// 设计要点（与产品决策一致）：
// - 原子动作 = "做完 1 次测验"（交卷一次即 +1，含重做）
// - 每日目标可调，默认 1；某天完成次数 >= 目标 → 当天"达标"
// - 连续天数 = 自今天（或昨天，若今天尚未达标）往前连续的达标天数
// - 成就徽章按"最长连续"解锁（周战士/月战士/百炼/年度学者）
// - 清空数据（clearAll）时随 db 一起清掉（G 决策：全部清空）

const DAYS_KEY = 'go_habit_days'      // { 'YYYY-MM-DD': 当日完成次数 }
const TOTAL_KEY = 'go_habit_total'     // 累计交卷次数（含重做）
const CORRECT_KEY = 'go_habit_correct' // 累计已判分正确数
const TOTALQ_KEY = 'go_habit_totalq'   // 累计已判分题数
const GOAL_KEY = 'go_habit_goal'       // 每日目标次数
const MAX_KEY = 'go_habit_maxstreak'   // 历史最长连续
const PERFECT_KEY = 'go_habit_perfect' // 满分测验次数（已判分且全对）
const OVER_KEY = 'go_habit_over'       // 超额完成天数（当日超过目标）
const REACH_KEY = 'go_habit_reach'     // 达标天数（当日达到目标）
const BADGES_KEY = 'go_habit_badges'   // 已解锁徽章 id 数组

export const HABIT_KEYS = [
  DAYS_KEY, TOTAL_KEY, CORRECT_KEY, TOTALQ_KEY, GOAL_KEY, MAX_KEY,
  PERFECT_KEY, OVER_KEY, REACH_KEY, BADGES_KEY,
]

// 成就徽章：五个维度（连续打卡 / 累计测验 / 正确率 / 满分测验 / 超额完成）
// cat: 判定维度；req: 阈值；reqQ: 正确率类需累计题数下限；icon: GoIcon 名；tier: 稀有度
const BADGES = [
  // 连续打卡
  { id: 's3', cat: 'streak', label: '刮目相看', req: 3, icon: 'flame', tier: 'bronze' },
  { id: 's7', cat: 'streak', label: '三之及一', req: 7, icon: 'flame', tier: 'silver' },
  { id: 's30', cat: 'streak', label: '亏盈之变', req: 30, icon: 'flame', tier: 'gold' },
  { id: 's100', cat: 'streak', label: '百日维新', req: 100, icon: 'flame', tier: 'gold' },
  { id: 's365', cat: 'streak', label: '易岁之坚', req: 365, icon: 'flame', tier: 'diamond' },
  // 累计测验
  { id: 'v10', cat: 'total', label: '初试锋芒', req: 10, icon: 'target', tier: 'bronze' },
  { id: 'v50', cat: 'total', label: '渐入佳境', req: 50, icon: 'target', tier: 'silver' },
  { id: 'v200', cat: 'total', label: '滴水聚百', req: 200, icon: 'target', tier: 'gold' },
  { id: 'v500', cat: 'total', label: '万千之间', req: 500, icon: 'target', tier: 'diamond' },
  // 正确率
  { id: 'a90', cat: 'accuracy', label: '九成之握', req: 90, reqQ: 50, icon: 'check', tier: 'silver' },
  { id: 'a98', cat: 'accuracy', label: '出神入化', req: 98, reqQ: 100, icon: 'check', tier: 'gold' },
  // 满分测验
  { id: 'p1', cat: 'perfect', label: '初盈之喜', req: 1, icon: 'trophy', tier: 'silver' },
  { id: 'p10', cat: 'perfect', label: '盈满之诗', req: 10, icon: 'trophy', tier: 'gold' },
  // 超额完成
  { id: 'o1', cat: 'over', label: ' 一五计划', req: 1, icon: 'star', tier: 'bronze' },
  { id: 'o10', cat: 'over', label: '好学之成', req: 10, icon: 'star', tier: 'gold' },
]

export const CAT_META = {
  streak: { label: '连续打卡', icon: 'flame' },
  total: { label: '累计测验', icon: 'target' },
  accuracy: { label: '正确率', icon: 'check' },
  perfect: { label: '满分测验', icon: 'trophy' },
  over: { label: '超额完成', icon: 'star' },
}

function load(key, fallback) {
  try {
    const v = uni.getStorageSync(key)
    return v === '' || v === null || v === undefined ? fallback : v
  } catch (e) {
    return fallback
  }
}
function save(key, val) {
  try { uni.setStorageSync(key, val) } catch (e) {}
}

function ymd(d) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
function addDays(dateStr, n) {
  const [y, m, d] = dateStr.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  dt.setDate(dt.getDate() + n)
  return ymd(dt)
}
function qualifies(daysMap, dateStr, goal) {
  return (daysMap[dateStr] || 0) >= goal
}

export function getGoal() {
  const g = load(GOAL_KEY, 1)
  return Number(g) > 0 ? Number(g) : 1
}

// 连续天数：今天达标从今天起算；今天未达标则从昨天起算（避免还没做今天就被清零）
function computeStreak(daysMap, goal) {
  const today = ymd(new Date())
  let cursor = qualifies(daysMap, today, goal) ? today : addDays(today, -1)
  let streak = 0
  while (qualifies(daysMap, cursor, goal)) {
    streak++
    cursor = addDays(cursor, -1)
  }
  return streak
}

// 交卷一次调用：correct / done 为本次已判分的正确题数 / 总题数（pending 不计入）
export function recordCompletion(correct = 0, done = 0) {
  const days = load(DAYS_KEY, {})
  const today = ymd(new Date())
  const prevCount = days[today] || 0
  const newCount = prevCount + 1
  days[today] = newCount
  save(DAYS_KEY, days)

  const total = load(TOTAL_KEY, 0) + 1
  save(TOTAL_KEY, total)

  const correctSum = load(CORRECT_KEY, 0) + (correct || 0)
  save(CORRECT_KEY, correctSum)

  const totalQ = load(TOTALQ_KEY, 0) + (done || 0)
  save(TOTALQ_KEY, totalQ)

  const goal = getGoal()

  // 达标 / 超额天数增量（仅当日跨过阈值时 +1，避免重复计入）
  let reached = load(REACH_KEY, 0)
  let over = load(OVER_KEY, 0)
  const wasReached = prevCount >= goal
  const wasOver = prevCount > goal
  if (!wasReached && newCount >= goal) reached++
  if (!wasOver && newCount > goal) over++
  save(REACH_KEY, reached)
  save(OVER_KEY, over)

  // 满分测验（已判分且全对）
  let perfect = load(PERFECT_KEY, 0)
  if (done > 0 && correct === done) perfect++
  save(PERFECT_KEY, perfect)

  const streak = computeStreak(days, goal)
  const maxStreak = Math.max(load(MAX_KEY, 0), streak)
  save(MAX_KEY, maxStreak)

  const ctx = buildCtx({ total, maxStreak, correct: correctSum, totalQ, perfect, over })
  const newBadges = evaluateUnlocks(ctx, load(BADGES_KEY, []))

  return { todayCount: newCount, streak, maxStreak, total, newBadges }
}

export function setGoal(n) {
  const v = Number(n)
  save(GOAL_KEY, v > 0 ? v : 1)
}

// 汇总所有判定维度，供徽章评估 / 进度计算
function buildCtx({ total, maxStreak, correct, totalQ, perfect, over }) {
  const accuracy = totalQ > 0 ? Math.round((correct / totalQ) * 100) : null
  return {
    total, maxStreak, correct, totalQ, perfect, over, accuracy,
    goal: getGoal(),
    days: load(DAYS_KEY, {}),
    reached: load(REACH_KEY, 0),
  }
}

function isUnlocked(b, ctx) {
  switch (b.cat) {
    case 'streak': return ctx.maxStreak >= b.req
    case 'total': return ctx.total >= b.req
    case 'accuracy': return ctx.accuracy != null && ctx.accuracy >= b.req && ctx.totalQ >= (b.reqQ || 0)
    case 'perfect': return ctx.perfect >= b.req
    case 'over': return ctx.over >= b.req
    default: return false
  }
}

function badgeProgress(b, ctx) {
  const pct = (cur, req) => Math.min(1, req > 0 ? cur / req : 0)
  switch (b.cat) {
    case 'streak': return { p: pct(ctx.maxStreak, b.req), hint: `${ctx.maxStreak}/${b.req} 天` }
    case 'total': return { p: pct(ctx.total, b.req), hint: `${ctx.total}/${b.req} 次` }
    case 'accuracy': return { p: pct(ctx.accuracy || 0, b.req), hint: `${ctx.accuracy == null ? 0 : ctx.accuracy}% · 需 ${b.req}% / ${b.reqQ} 题` }
    case 'perfect': return { p: pct(ctx.perfect, b.req), hint: `${ctx.perfect}/${b.req} 次满分` }
    case 'over': return { p: pct(ctx.over, b.req), hint: `${ctx.over}/${b.req} 天超额` }
    default: return { p: 0, hint: '' }
  }
}

// 评估并持久化解锁；返回本次新解锁徽章
function evaluateUnlocks(ctx, prevUnlocked) {
  const next = prevUnlocked.slice()
  const fresh = []
  for (const b of BADGES) {
    if (!next.includes(b.id) && isUnlocked(b, ctx)) {
      next.push(b.id)
      fresh.push(b)
    }
  }
  if (fresh.length) save(BADGES_KEY, next)
  return fresh
}

// 读取首页所需的全部展示数据
export function getState() {
  const days = load(DAYS_KEY, {})
  const goal = getGoal()
  const total = load(TOTAL_KEY, 0)
  const correct = load(CORRECT_KEY, 0)
  const totalQ = load(TOTALQ_KEY, 0)
  const maxStreak = load(MAX_KEY, 0)
  const perfect = load(PERFECT_KEY, 0)
  const over = load(OVER_KEY, 0)
  const unlocked = load(BADGES_KEY, [])

  const streak = computeStreak(days, goal)
  const today = ymd(new Date())
  const todayCount = days[today] || 0
  const isTodayDone = todayCount >= goal
  const brokenYesterday =
    !isTodayDone &&
    !qualifies(days, addDays(today, -1), goal) &&
    maxStreak > 0

  const accuracy = totalQ > 0 ? Math.round((correct / totalQ) * 100) : null
  const ctx = buildCtx({ total, maxStreak, correct, totalQ, perfect, over })
  const badges = BADGES.map((b) => {
    const unlockedNow = unlocked.includes(b.id)
    const prog = unlockedNow ? { p: 1, hint: '已解锁' } : badgeProgress(b, ctx)
    return { ...b, unlocked: unlockedNow, progress: prog.p, hint: prog.hint }
  })
  const unlockedCount = badges.filter((b) => b.unlocked).length

  return {
    streak, maxStreak, total, accuracy, todayCount, goal, isTodayDone, brokenYesterday,
    badges, badgeStats: { unlocked: unlockedCount, total: badges.length },
  }
}

export function clearHabit() {
  for (const k of HABIT_KEYS) {
    try { uni.removeStorageSync(k) } catch (e) {}
  }
}
