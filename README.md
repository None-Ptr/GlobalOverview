<div align="center">
<p align="center">
<img src="src/static/logo.png" alt="GlobalOverview" width="160"/>
</p>

# GlobalOverview
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Stars](https://img.shields.io/github/stars/None-Ptr/GlobalOverview)
![Release](https://img.shields.io/github/release/None-Ptr/GlobalOverview.svg)
![Platform](https://img.shields.io/badge/Android-3DDC84?style=flat&logo=android&logoColor=white)
![Github](https://img.shields.io/badge/Github-181717?style=flat&logo=github&logoColor=white)
</div>


## 说在前面

又到了假期，不知为何每次放假后，紧绷的弦突然松开时，我都会感到空虚，上学时如果明明要我说去玩什么的话我能说出一大串来，但放了假后明明有时间玩了，而我却什么连想玩什么都不知道了。

既然不知道玩什么，那就写点题吧，指尖划过屏幕，在 pdd 上敲下“英语时文阅读”几个字。随之出现在眼前的，不是软件图标，而是一堆数字。

我愣了一下，想起了那些发黄的纸币。或许，在我身后柜子里还有几张，十几张那样的纸币。可是，那又够我在求学路上支撑多久呢？

突然有一天我的朋友找到我问我这个暑假还写项目吗，此时，我看到了一束光。那束光，是家中台式电脑电源按钮的微光，我好似看到了希望。

我想起了我的项目，想起了我在上上个寒假开发 `OJ` 的日日夜夜，想起了我与朋友一同开发的日子。我觉得忏悔，为什么面对忙碌而又空虚的假期，我没有早点想起我还能继续开发，可能是因为我已经上课上麻木了吧。

受 [ReadYou](https://github.com/ReadYouApp/ReadYou) 等 `RSS` 阅读器的启发，一个大胆的念头出现在我的脑海之中，我要自己手搓一个英语时文阅读器。于是我连忙拉上了一位英语更不好的英语课代表一起，准备这项伟大的工程。

完全的免费，完全的自由，完全的希望！不，是取之不尽的，用之不竭的！

这次，我的手指在触感真实而又熟悉的黑色键盘上，回味着往事。在经过漫长的开发和调试之后，在我几乎想要放弃之际，终于我看到了方向。 

那里，有一座望远镜，和一个地球。

紧接着，一系列的文章，星罗棋布，或许是望远镜观察到的吧。轻点做题，有选择，填空，简答。作答时虚无缥缈的手机屏幕键盘也好似有了力量，闪烁着，跳跃着，好似希望的火苗。

平时阅读时，我便会轻点屏幕，那些晦涩难懂的短语、单词的释义便会跃然屏幕上，加入单词本中供我积累。

此时，窗外正是一半晴一半阴。

“朝晖夕阴，气象万千。”我不禁吟诵道，看着眼前的另一轮朝阳照亮了英语之路，我隐隐地笑了。

以上，致我的一个暑假。

本人拙笔，请见谅。

> [!NOTE]
> 本人之前主写 `c++` 和 `python`，本项目算本人的第一个有前端项目，是边学习边开发的，请各位见谅，另外，本项目的前端由 `llm` 重写了一次，不然原来的 `UI` 完全见不了人。

> [!NOTE]
> 本项目本来想基于 `tauri` 但由于本人能力原因跨平台表现不是很好，故最终选了 `uni-app` 实现。
> 关于支持的平台方面，目前仅支持 `Android`，从理论上 `IOS` 应该也能支持，但本人对 `IOS` 不熟且年费有点高，故暂时不考虑。

> [!NOTE]
> 作为一个 `OIer`, 本人没有过多精力对此项目进行长期维护，欢迎各位贡献者支持。
## 功能

啰嗦了半天废话,下面开始正文

- **阅读**：25 个内置 `RSS` 源，静态抓取+`@mozilla/readability` 抽取正文，支持手动加源。
- **沉浸式阅读器**：字号/行距可调；支持点词查询和选句查询，长按句子空白处可以选择那一句话。
- **英语学习**：
  - 文章「加入计划」→ 计划页选预设（考试对标/题型/考察重点/解析语言/数量）批量生成题集（部分成功）。
  - 答题：一屏一题 + 左右滑动 + 题号导航，点击回到原文查看原文章，草稿自动保存，交卷批量 `LLM` 评分。
  - 错题本：做错自动汇入，可独立重做 / 导出。
  - 单词本: 记录查询过的单词，用于积累
  
- **PDF 导出**：HTML 模板 → WebView → 系统打印（另存为 PDF）。
- **LLM 配置**: 自行配置 api 和模型,apikey保存在本地.

## 技术栈

uni-app 3.0 + Vue3.4 + Vite5.2（5+App）· Pinia（配置/会话态）· `plus.sqlite`（数据存储）· `fast-xml-parser`（RSS）· `@mozilla/readability`（正文抽取）· SCSS。

## 开发

本项目基于 uni-app,推荐使用 `HBuilderX` 进行开发

```bash
npm install
npm run dev:app      
npm run build:app    
```

若是本地编译运行需要下载 [SDK](https://nativesupport.dcloud.net.cn/AppDocs/download/android.html) 版本号 ` Android-SDK@5.23.82669_20260804`。


## TODO
1. 优化 `UI`
2. 支持主题切换
3. 丰富翻译管道
4. 加强提示词
5. 优化性能
6. 增强过滤器
7. 支持图片渲染
  
## 致谢

最后感谢本项目的所有贡献者，特别感谢 ShaDouBuShi123 为本项目提供的图标和大力支持。