// 自定义翻译接口配置层（纯存储，不进 SQLite）。
// 每个配置描述一个「通用 HTTP 翻译 REST 接口」，translate.js 据此动态接入回退链与引擎列表。
// 说明：key 仅存本地（uni.setStorageSync），与 llm_profiles 同模式。

const STORE_KEY = 'go_custom_translators'

// 默认目标语言映射：translate() 上层传的是 'ZH'/'EN' 等大写键，
// 自定义接口若未配置 langMap，则用这份默认表把键转成具体语言代码。
export const DEFAULT_LANG_MAP = {
  ZH: 'zh', EN: 'en', JA: 'ja', KO: 'ko', FR: 'fr', DE: 'de', RU: 'ru', ES: 'es',
}

export function loadCustomTranslators() {
  try { return uni.getStorageSync(STORE_KEY) || [] } catch (e) { return [] }
}

export function saveCustomTranslators(list) {
  try { uni.setStorageSync(STORE_KEY, list) } catch (e) {}
}

// 新增（无 id）或更新（有 id）一条自定义翻译接口，返回其 id
export function upsertTranslator(cfg) {
  const list = loadCustomTranslators()
  if (cfg.id) {
    const i = list.findIndex((x) => x.id === cfg.id)
    if (i >= 0) list[i] = { ...list[i], ...cfg }
    else list.push(cfg)
  } else {
    cfg.id = 'ct_' + Date.now()
    list.push(cfg)
  }
  saveCustomTranslators(list)
  return cfg.id
}

export function deleteTranslator(id) {
  saveCustomTranslators(loadCustomTranslators().filter((x) => x.id !== id))
}
