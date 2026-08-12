import { defineStore } from 'pinia'
import { getProfiles, saveProfiles } from '@/utils/llm.js'

const GOAL_KEY = 'global_goal'
const ACTIVE_KEY = 'active_profile_id'

// 仅存配置 / 会话态；业务数据走 SQLite
export const useAppStore = defineStore('app', {
  state: () => ({
    llmProfiles: [],
    activeProfileId: null,
    globalGoal: 'CET6', // 全局备考目标，预设未指定考试时由它兜底
    reader: { fontSize: 18, lineHeight: 1.8, transEngine: 'auto' },
  }),
  getters: {
    activeProfile(state) {
      if (!state.llmProfiles.length) return null
      const hit = state.llmProfiles.find((p) => p.id === state.activeProfileId)
      return hit || state.llmProfiles[0]
    },
  },
  actions: {
    init() {
      this.initReader()
      this.initProfiles()
      this.initGoal()
    },
    initReader() {
      try { const saved = uni.getStorageSync('reader_cfg'); if (saved) this.reader = { ...this.reader, ...saved } } catch (e) {}
    },
    setReader(cfg) {
      this.reader = { ...this.reader, ...cfg }
      try { uni.setStorageSync('reader_cfg', this.reader) } catch (e) {}
    },
    initProfiles() {
      this.llmProfiles = getProfiles() || []
      try { const id = uni.getStorageSync(ACTIVE_KEY); if (id) this.activeProfileId = id } catch (e) {}
      if (!this.activeProfileId && this.llmProfiles.length) this.activeProfileId = this.llmProfiles[0].id
    },
    setProfiles(list) {
      this.llmProfiles = list || []
      saveProfiles(this.llmProfiles)
      if (!this.llmProfiles.find((p) => p.id === this.activeProfileId)) {
        this.setActiveProfile(this.llmProfiles.length ? this.llmProfiles[0].id : null)
      }
    },
    setActiveProfile(id) {
      this.activeProfileId = id
      try { uni.setStorageSync(ACTIVE_KEY, id) } catch (e) {}
    },
    initGoal() {
      try { const g = uni.getStorageSync(GOAL_KEY); if (g) this.globalGoal = g } catch (e) {}
    },
    setGoal(g) {
      this.globalGoal = g
      try { uni.setStorageSync(GOAL_KEY, g) } catch (e) {}
    },
    // 兼容旧调用：设置出题难度（全局目标）
    setTarget(g) { this.setGoal(g) },
  },
})
