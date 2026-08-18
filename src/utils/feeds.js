// 内置 RSS 源目录（来源：rss.md，6 轮可达性实测，共 86 个，全部在中国大陆网络可达）
// 设计上把"默认订阅"与"完整目录"分开：
//   - DEFAULT_FEEDS：首次启动只订阅这一小撮（覆盖主要类别），避免一次性并发抓取 86 个源拖慢首屏。
//   - FEEDS：完整目录（86 个），供"按分类选择订阅源"的浏览面板使用；用户可随时追加。
//   - CATEGORIES：分类顺序与中文标签，驱动阅读页的分类导航。

export const CATEGORIES = [
  { key: 'News', label: '新闻' },
  { key: 'Science', label: '科学' },
  { key: 'Health', label: '健康' },
  { key: 'Tech', label: '科技' },
  { key: 'Business', label: '商业' },
  { key: 'Environment', label: '环境' },
  { key: 'Food', label: '食物' },
  { key: 'Art', label: '艺术' },
  { key: 'Design', label: '设计' },
  { key: 'Books', label: '书籍文学' },
  { key: 'Ideas', label: '思想文化' },
  { key: 'Learner', label: '英语学习' },
  { key: 'Sports', label: '体育' },
  { key: 'Travel', label: '旅行' },
  { key: 'Education', label: '教育' },
  { key: 'Policy', label: '政策智库' },
  { key: 'Life', label: '生活' },
]

// 完整目录（86 个），按 CATEGORIES 顺序排列。
export const FEEDS = [
  // —— News ——
  { title: 'NPR News', url: 'https://feeds.npr.org/1001/rss.xml', category: 'News' },
  { title: 'NPR World', url: 'https://feeds.npr.org/1004/rss.xml', category: 'News' },
  { title: 'France24 English', url: 'https://www.france24.com/en/rss', category: 'News' },
  { title: 'Sky News World', url: 'https://feeds.skynews.com/feeds/rss/world.xml', category: 'News' },
  { title: 'CNBC Top', url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114', category: 'News' },
  { title: 'The Hill', url: 'https://thehill.com/feed/', category: 'News' },
  { title: 'The 19th', url: 'https://19thnews.org/feed/', category: 'News' },

  // —— Science ——
  { title: 'Nature', url: 'https://www.nature.com/nature.rss', category: 'Science' },
  { title: 'Quanta', url: 'https://www.quantamagazine.org/feed/', category: 'Science' },
  { title: 'NPR Science', url: 'https://feeds.npr.org/1019/rss.xml', category: 'Science' },
  { title: 'Space.com', url: 'https://www.space.com/feeds/all', category: 'Science' },
  { title: 'Live Science', url: 'https://www.livescience.com/feeds/all', category: 'Science' },
  { title: 'Popular Science', url: 'https://www.popsci.com/feed/', category: 'Science' },
  { title: 'Science Daily', url: 'https://www.sciencedaily.com/rss/all.xml', category: 'Science' },
  { title: 'Hakai Magazine', url: 'https://hakaimagazine.com/feed/', category: 'Science' },
  { title: 'Undark', url: 'https://undark.org/feed/', category: 'Science' },
  { title: 'Anthropocene', url: 'https://www.anthropocenemagazine.org/feed/', category: 'Science' },
  { title: 'Nautilus', url: 'https://nautil.us/feed/', category: 'Science' },
  { title: 'Asimov Press', url: 'https://www.asimov.press/feed', category: 'Science' },

  // —— Health ——
  { title: 'NPR Health', url: 'https://feeds.npr.org/1025/rss.xml', category: 'Health' },
  { title: 'STAT', url: 'https://www.statnews.com/feed/', category: 'Health' },

  // —— Tech ——
  { title: 'The Verge', url: 'https://www.theverge.com/rss/index.xml', category: 'Tech' },
  { title: 'Ars Technica', url: 'http://feeds.arstechnica.com/arstechnica/index', category: 'Tech' },
  { title: 'Wired', url: 'https://www.wired.com/feed/rss', category: 'Tech' },
  { title: 'Hacker News', url: 'https://hnrss.org/frontpage', category: 'Tech' },
  { title: 'Engadget', url: 'https://www.engadget.com/rss.xml', category: 'Tech' },
  { title: 'MIT Tech Review', url: 'https://www.technologyreview.com/feed/', category: 'Tech' },
  { title: 'TechCrunch', url: 'https://techcrunch.com/feed/', category: 'Tech' },
  { title: 'Dev.to', url: 'https://dev.to/feed', category: 'Tech' },
  { title: 'freeCodeCamp', url: 'https://www.freecodecamp.org/news/rss/', category: 'Tech' },
  { title: 'HackerNoon', url: 'https://hackernoon.com/feed', category: 'Tech' },
  { title: 'InfoQ', url: 'https://feed.infoq.com/', category: 'Tech' },
  { title: 'Stratechery', url: 'https://stratechery.com/feed/', category: 'Tech' },

  // —— Business ——
  { title: 'Fortune', url: 'https://fortune.com/feed', category: 'Business' },

  // —— Environment ——
  { title: 'Grist', url: 'https://grist.org/feed/', category: 'Environment' },

  // —— Food ——
  { title: 'Eater', url: 'https://www.eater.com/rss/index.xml', category: 'Food' },
  { title: 'Bon Appétit', url: 'https://www.bonappetit.com/feed/rss', category: 'Food' },

  // —— Art ——
  { title: 'Hyperallergic', url: 'https://hyperallergic.com/feed/', category: 'Art' },
  { title: 'Colossal', url: 'https://www.thisiscolossal.com/feed/', category: 'Art' },

  // —— Design ——
  { title: 'Smashing Magazine', url: 'https://www.smashingmagazine.com/feed/', category: 'Design' },

  // —— Books / Literature ——
  { title: 'NPR Books', url: 'https://feeds.npr.org/1032/rss.xml', category: 'Books' },
  { title: 'Literary Hub', url: 'https://lithub.com/feed/', category: 'Books' },
  { title: 'Longreads', url: 'https://longreads.com/feed/', category: 'Books' },
  { title: 'Brain Pickings', url: 'https://www.brainpickings.org/feed/', category: 'Books' },
  { title: 'Wait But Why', url: 'https://waitbutwhy.com/feed', category: 'Books' },
  { title: 'Electric Literature', url: 'https://electricliterature.com/feed/', category: 'Books' },
  { title: 'Book Riot', url: 'https://bookriot.com/feed/', category: 'Books' },
  { title: 'The Paris Review', url: 'https://www.theparisreview.org/blog/feed/', category: 'Books' },
  { title: 'Arts & Letters Daily', url: 'https://aldaily.com/feed/', category: 'Books' },

  // —— Ideas / Culture ——
  { title: 'NPR TED', url: 'https://feeds.npr.org/1054/rss.xml', category: 'Ideas' },
  { title: 'TED Blog', url: 'https://blog.ted.com/feed/', category: 'Ideas' },
  { title: 'TED Ideas', url: 'https://ideas.ted.com/feed/', category: 'Ideas' },
  { title: 'The Browser', url: 'https://thebrowser.com/feed/', category: 'Ideas' },
  { title: 'Aeon', url: 'https://aeon.co/feed', category: 'Ideas' },
  { title: 'Psyche', url: 'https://psyche.co/feed', category: 'Ideas' },
  { title: '3 Quarks Daily', url: 'https://3quarksdaily.com/feed/', category: 'Ideas' },
  { title: 'Farnam Street', url: 'https://fs.blog/feed/', category: 'Ideas' },
  { title: 'Freakonomics', url: 'https://freakonomics.com/feed/', category: 'Ideas' },
  { title: 'Works in Progress', url: 'https://www.worksinprogress.news/feed', category: 'Ideas' },
  { title: 'Mental Floss', url: 'https://www.mentalfloss.com/feed', category: 'Ideas' },
  { title: 'JSTOR Daily', url: 'https://daily.jstor.org/feed/', category: 'Ideas' },
  { title: 'HistoryExtra', url: 'https://www.historyextra.com/feed/', category: 'Ideas' },
  { title: 'Nieman Lab', url: 'https://www.niemanlab.org/feed/', category: 'Ideas' },
  { title: 'Our World in Data', url: 'https://ourworldindata.org/feed', category: 'Ideas' },

  // —— Learner (英语训练) ——
  { title: 'News in Levels', url: 'https://www.newsinlevels.com/feed/', category: 'Learner' },
  { title: 'Grammarly Blog', url: 'https://www.grammarly.com/blog/feed/', category: 'Learner' },
  { title: 'Open Culture', url: 'https://www.openculture.com/feed', category: 'Learner' },
  { title: 'Daily Writing Tips', url: 'https://www.dailywritingtips.com/feed/', category: 'Learner' },
  { title: 'Writing Excuses', url: 'https://writingexcuses.com/feed/', category: 'Learner' },
  { title: 'Espresso English', url: 'https://www.espressoenglish.net/feed/', category: 'Learner' },
  { title: 'engVid', url: 'https://www.engvid.com/feed/', category: 'Learner' },
  { title: 'FluentU Blog', url: 'https://www.fluentu.com/blog/english/feed/', category: 'Learner' },
  { title: 'A Way with Words', url: 'https://www.awaywithwords.com/feed/', category: 'Learner' },

  // —— Sports ——
  { title: 'Sky Sports', url: 'https://www.skysports.com/rss/12040', category: 'Sports' },
  { title: 'SB Nation', url: 'https://www.sbnation.com/rss/index.xml', category: 'Sports' },
  { title: 'CyclingTips', url: 'https://www.cyclingtips.com/feed/', category: 'Sports' },

  // —— Travel ——
  { title: 'Skift', url: 'https://skift.com/feed/', category: 'Travel' },
  { title: 'Matador Network', url: 'https://matadornetwork.com/feed/', category: 'Travel' },

  // —— Education ——
  { title: 'Inside Higher Ed', url: 'https://www.insidehighered.com/rss.xml', category: 'Education' },
  { title: 'The Hechinger Report', url: 'https://hechingerreport.org/feed/', category: 'Education' },
  { title: 'Higher Ed Dive', url: 'https://www.highereddive.com/feeds/news/', category: 'Education' },
  { title: 'KQED MindShift', url: 'https://ww2.kqed.org/mindshift/feed/', category: 'Education' },
  { title: 'TeachThought', url: 'https://www.teachthought.com/feed/', category: 'Education' },

  // —— Policy / Think Tank ——
  { title: 'Bruegel', url: 'https://www.bruegel.org/rss.xml', category: 'Policy' },
  { title: 'Aspen Institute', url: 'https://www.aspeninstitute.org/feed/', category: 'Policy' },

  // —— Life ——
  { title: 'Lifehacker', url: 'https://lifehacker.com/rss', category: 'Life' },
]

// 首次启动默认订阅（覆盖主要类别、数量克制，避免一次性并发抓取 86 个源）
export const DEFAULT_FEEDS = [
  { title: 'NPR News', url: 'https://feeds.npr.org/1001/rss.xml', category: 'News' },
  { title: 'France24 English', url: 'https://www.france24.com/en/rss', category: 'News' },
  { title: 'Nature', url: 'https://www.nature.com/nature.rss', category: 'Science' },
  { title: 'Quanta', url: 'https://www.quantamagazine.org/feed/', category: 'Science' },
  { title: 'The Verge', url: 'https://www.theverge.com/rss/index.xml', category: 'Tech' },
  { title: 'Ars Technica', url: 'http://feeds.arstechnica.com/arstechnica/index', category: 'Tech' },
  { title: 'Hacker News', url: 'https://hnrss.org/frontpage', category: 'Tech' },
  { title: 'Literary Hub', url: 'https://lithub.com/feed/', category: 'Books' },
  { title: 'Wait But Why', url: 'https://waitbutwhy.com/feed', category: 'Books' },
  { title: 'Aeon', url: 'https://aeon.co/feed', category: 'Ideas' },
  { title: 'Psyche', url: 'https://psyche.co/feed', category: 'Ideas' },
  { title: 'News in Levels', url: 'https://www.newsinlevels.com/feed/', category: 'Learner' },
  { title: 'Espresso English', url: 'https://www.espressoenglish.net/feed/', category: 'Learner' },
  { title: 'Fortune', url: 'https://fortune.com/feed', category: 'Business' },
  { title: 'Lifehacker', url: 'https://lifehacker.com/rss', category: 'Life' },
]

// 兼容旧的具名导入（如 app.js 中 import { builtin }）
export const builtin = DEFAULT_FEEDS
