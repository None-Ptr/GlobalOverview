/// The four things a first run points at. Shared by the onboarding's closing
/// step and the one-time sheet shown to readers who were already past it.
class FeatureNote {
  final String title;
  final String note;

  const FeatureNote(this.title, this.note);
}

const featureNotes = <FeatureNote>[
  FeatureNote('导入文章', '阅读页右上角的 +；粘贴正文或输入网址，和订阅文章排在一起。'),
  FeatureNote('自定义 RSS', '「我的 → 来源与加速」里添加自己的订阅源，可单独刷新。'),
  FeatureNote('AI 精选', '阅读器右上角「更多 → AI 精选」，把长文读短，可随时切回原文。'),
  FeatureNote('生成精读练习', '阅读器底部的「生成精读练习」，按难度出题，答完自动判分。'),
];
