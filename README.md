# GlobalOverview

基于 uni-app 的开源英语学习 App（Android 5+App）。

RSS 阅读器 + LLM 出题（用户自主配置 API）+ 沉浸式阅读（点词查询、加入做题计划）+ 做题计划导出 PDF。零后端、key 仅存本地、MIT 许可证。

## 功能

- **阅读**：21 个内置 RSS 源（中国大陆可达），纯静态抓取 + `@mozilla/readability` 抽取正文；可手动加源。
- **沉浸式阅读器**：字号/行距/主题可调；点词查询（英→中走翻译 API（MyMemory/LibreTranslate）或 LLM，英→英走词典 API，按词+模式缓存）。
- **学习闭环**：
  - 文章「加入计划」→ 计划页选预设（考试对标/题型/考察重点/解析语言/数量）批量生成题集（部分成功）。
  - 答题：一屏一题 + 左右滑动 + 题号导航；草稿自动保存；交卷批量 AI 评分。
  - 错题本：做错自动汇入，可独立重做 / 导出。
- **PDF 导出**：HTML 模板 → WebView → 系统打印（另存为 PDF）。档 1（含答案/解析/原文引用开关）+ 档 3（模板源码编辑），单套题集与错题本合并共用一套渲染管线。

## 技术栈

uni-app 3.0 + Vue3.4 + Vite5.2（5+App）· Pinia（配置/会话态）· `plus.sqlite`（业务数据）· `fast-xml-parser`（RSS）· `@mozilla/readability`（正文抽取）· SCSS。

## 数据模型（SQLite）

`feeds / feed_items / articles / question_sets / questions / answers / word_cache / presets / plan_items / templates`。Schema 见 `src/utils/db.js`。

## 开发

```bash
npm install
npm run dev:app      # 真机/模拟器调试（需 HBuilderX 或 CLI）
npm run build:app    # 打包 APK（Android）
```

> 注：依赖 `esbuild` 安装脚本在某些 npm 环境会被阻断，若 `npm run build:*` 报 esbuild 二进制缺失，手动执行 `node node_modules/esbuild/install.js` 即可。

## 配置 LLM

进入「我的」页，添加 OpenAI 兼容模型（baseUrl / apiKey / model），支持多 profile、测试连接。未配置时出题/判分/英→中提示不可用但不崩溃。

## 许可

MIT。
