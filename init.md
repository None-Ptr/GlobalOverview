# GlobalOverview 方案文档（init.md）

> 基于 uni-app 的开源英语学习 App，仅 Android 5+App（Vue3 + WebView 渲染）。
> RSS 阅读器 + LLM 出题（用户自主配置 API）+ 沉浸式阅读（点词查询、加入做题计划）+ 做题计划导出 PDF。
> 零后端、key 只存本地、MIT 许可证。

---

## 0. 设计哲学

- **Schema 是宪法**：题目输出必须落 JSON Schema；Prompt 与 PDF 模板可自由改，但输出结构不可偏离。
- **X 主干 + Y 高级模式**：默认走 X 简化配置；高级模式允许编辑 Prompt 正文 / PDF 模板源码，但锁死 Schema。
- 已确认的四项代定值：
  1. `ai` 判分保留，交卷批量自动评分；
  2. 重新出题为**新增**题集，非覆盖；
  3. 做错的题自动进入**错题本**，可独立重做、可导出；
  4. 正文 HTML 用 **`@mozilla/readability`** 抽取（依赖 WebView 的 DOM / DOMParser）。

---

## 1. 数据模型（SQLite / `plus.sqlite`）

存储分层（B 方案）：`feed_items` 是缓存（可清空），`articles` 是资产（永不自动删），通过 `guid` 关联。

```sql
-- 订阅源
CREATE TABLE feeds (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  title     TEXT,
  url       TEXT UNIQUE,
  category  TEXT,
  addedAt   INTEGER
);

-- RSS 列表项缓存（可定期清空）
CREATE TABLE feed_items (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  feedId    INTEGER,
  guid      TEXT,
  title     TEXT,
  link      TEXT,
  preview   TEXT,            -- 来自 content:encoded 的纯文本预览，仅列表用
  pubDate   INTEGER,
  fetchedAt INTEGER
);

-- 正文资产（永不自动删）
CREATE TABLE articles (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  guid      TEXT UNIQUE,     -- 关联 feed_items.guid
  title     TEXT,
  author    TEXT,
  sourceUrl TEXT,
  html      TEXT,            -- 清洗后正文 HTML
  plainText TEXT,            -- 行清洗后的纯文本
  wordCount INTEGER,
  capturedAt INTEGER
);

-- 题集（1:N 题目；重新出题为新增题集，非覆盖）
CREATE TABLE question_sets (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  articleId INTEGER,         -- 关联 articles.id
  presetId  INTEGER,         -- 关联出题预设
  title     TEXT,
  createdAt INTEGER
);

CREATE TABLE questions (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  setId     INTEGER,         -- 关联 question_sets.id
  type      TEXT,            -- 管渲染：choice/fill/shortAnswer/general...
  gradeMode TEXT,            -- 管判分：exact/contains/ai/manual
  prompt    TEXT,
  options   TEXT,            -- JSON 数组（选项内容）
  answers   TEXT,            -- JSON 字符串数组（存选项内容，非下标）
  analysis  TEXT,
  sourceQuote TEXT,          -- 永远输出
  createdAt INTEGER
);

-- 作答记录 / 错题本
CREATE TABLE answers (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  questionId INTEGER,
  draft     TEXT,            -- 作答草稿（自动静默保存）
  final     TEXT,            -- 最终提交
  correct   INTEGER,         -- 0/1，ai 判分结果
  wrong     INTEGER DEFAULT 0, -- 1 表示进错题本
  status    TEXT DEFAULT 'graded', -- graded / pending（判分失败，可重判）
  comment   TEXT,            -- AI 点评 / 判分失败原因
  gradedAt  INTEGER
);

-- 点词缓存
CREATE TABLE word_cache (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  word      TEXT,
  mode      TEXT,            -- en2zh / en2en / phrase
  result    TEXT,
  at        INTEGER,
  UNIQUE(word, mode)
);

-- 出题预设
CREATE TABLE presets (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  name      TEXT,
  config    TEXT             -- JSON：题型/数量/难度对标/考察重点/解析语言
);
```

配置（非业务）走 `uni.setStorage`；会话态走 Pinia。

---

## 2. 内容管线（正文抓取，唯一通路，无兜底）

链路（纯静态，无 WebView 深度抓取、无整页降级）：

1. `uni.request` 拉取文章页 HTML。
2. **标签黑名单**：`script / style / nav / footer / aside / form / iframe / noscript / svg / button` 整段删除。
3. **属性关键词剥离**：移除含 `hidden / display:none /广告/ads /sponsor /related /recommend` 等关键词的节点或属性。
4. **`@mozilla/readability`** 解析 DOM 并抽取主内容（`Readability(document).parse()`）。
5. **文本行清洗**：去多余空行、合并连续空白、去尾部乱码行。
6. 清洗后 `< 800 字符` → **失败页**（仅「重试 / 浏览器打开」两个动作），不做降级。

`content:encoded` 仅用于列表预览，不参与正文。

---

## 3. 阅读器（沉浸式）

- 正文全屏渲染，自定义排版（字号/行距/主题）。
- **点词**：
  - 英→中（默认）→ 走 LLM（无免 key 英汉 API）。
  - 英→英 → `dictionaryapi.dev`，降级 `freedictionaryapi.com`。
  - 不内置离线词典；`word_cache` 按「词 + 模式」持久化。
  - 整句 / 长按短语 → 走 LLM 批量解释。
- 「加入做题计划」入口在阅读器内。

---

## 4. LLM 配置（C）

- 单一 OpenAI 兼容协议 + 服务商预设下拉 + 测试连接 + 多 profile。
- 非流式。
- key 仅存本地（`uni.setStorage`）。

---

## 5. 出题（B 路径）

- 唯一入口：**加入计划 → 计划页批量生成**。无快捷出题。
- 批量失败**部分成功**（成功的部分照常落库）。
- 5 维度：题型 / 数量 / 难度对标（8 类考试）/ 考察重点 / 解析语言。
- 难度 = 一组约束（考试 + 词汇量 + 题型偏好），跟随**全局备考目标**。
- 预设方案可存（preset），Schema 锁死；高级模式可改 Prompt 正文。

---

## 6. 答题与判分（B 模式）

- 整套试卷**交卷**后批量 AI 评分（`gradeMode=ai`）。
- 一屏一题 + 左右滑动 + 底部题号导航。
- 草稿**静默自动保存**（answers.draft）。
- 独立全屏「原文查看页」（无点词）。
- **错题本**：做错自动汇入（answers.wrong=1），可独立重做、可导出。

---

## 7. PDF 导出（C）

- HTML/CSS 模板 → WebView → PDF。
- 对象：单套题集 + 错题本（多套合并顺手）。
- 档 1（开关项）+ 档 3（模板源码编辑），共用一套渲染管线。

---

## 8. 信息架构

3 个 tab：**阅读 / 计划 / 我的**。不做已读未读。

---

## 9. 技术栈

- uni-app 3.0 + Vue3.4 + Vite5.2（5+App）。
- Pinia：仅配置 / 会话态。
- `plus.sqlite`：业务数据（feeds / feed_items / articles / question_sets / questions / answers / word_cache）。
- `uni.setStorage`：LLM 配置 / 全局备考目标。
- `fast-xml-parser`：RSS 解析。
- `@mozilla/readability`：HTML 正文抽取（WebView DOM / DOMParser）。
- SCSS。

---

## 10. 内置 RSS 源（21 个，中国大陆实测可达，全默认订阅）

NPR News / NPR Books / NPR TED / France24(en) / Sky News World / CNBC Top /
Scientific American / Nature / Quanta / New Scientist / The Verge / Ars Technica /
Wired / Hacker News / Engadget / MIT Tech Review / Smashing Magazine / CSS-Tricks /
Literary Hub / Wait But Why / Lifehacker。
支持手动加 URL。

---

## 11. 交付顺序（竖切三阶段）

- **阶段一（阅读器）**：脚手架 + 3 tab 框架 + RSS 拉取/解析 + 正文管线 + 沉浸式阅读器 + 点词骨架 + SQLite 落地。
- **阶段二（学习闭环）**：LLM 配置 + 出题 + 答题判分 + 错题本 + 计划页。
- **阶段三（导出 + 工程化）**：PDF 模板管线 + 档 1/档 3 + 工程化收尾 + Release 打包。

---

## 12. 否决项附录（明确不做）

- 不做摘要 / WebView 深度抓取 / 源筛选 UI / 手动编辑正文 / 整页降级兜底。
- 不内置离线词典；不流式输出；不做已读未读；不做 H5 / 小程序。
- 重新出题为新增，不覆盖旧题集。