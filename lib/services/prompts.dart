/// Every prompt the app sends to a language model lives here.
///
/// House rules, applied to all of them:
/// - Role first, output contract last: the model reads the contract right
///   before it answers.
/// - The contract names every key and what may go in it; nothing is left to
///   "reasonable JSON".
/// - Whatever the app displays is asked for in the language the app displays
///   it in (Chinese for analysis, comments and glosses; English for the item
///   itself).
/// - Facts stay in the article. A question that cannot be proved from the text
///   is dropped, never guessed.
library;

/// One line of a practice set: a type, its display label, and how many items.
class PracticeItem {
  final String type;
  final String label;
  final int count;

  const PracticeItem({
    required this.type,
    required this.label,
    required this.count,
  });
}

class Prompts {
  Prompts._();

  /// Appended by `LlmService.structured` to every request that expects JSON.
  static const jsonOnly =
      'Output: return exactly one JSON value and nothing else. The first character must be { or [. '
      'No Markdown fences, no preamble, no trailing notes.';

  // ---------------------------------------------------------------- practice

  static const practiceSystem =
      'You are an experienced English reading-test writer for Chinese learners of English. '
      'You write items that can be proved from the article you are given and from nothing else. '
      'You never invent facts, numbers, names, quotations or citations.';

  /// Per-type rules. Each one says what makes a good item and what `answers`
  /// must contain, because the grader compares text, not intent.
  static const _typeRules = <String, String>{
    'choice':
        'Ask about one specific fact, cause, attitude or inference. 4 options, exactly one correct; '
            'the other three are plausible to a careless reader but contradicted by a detail in the text. '
            'answers = [the full text of the correct option, not a letter].',
    'cloze':
        'Copy one sentence from the article and replace one word or short phrase with "____". '
            'The blank must be recoverable from grammar and context. options = []. '
            'answers = [the removed text].',
    'blank':
        'Copy one sentence and replace one word with "____"; the task is to supply the correct form '
            '(tense, voice, agreement, derivation). options = []. answers = [the missing form].',
    'match':
        'Write one statement and give 4–5 targets to match it to (headings, names, sections). '
            'options = the target list in a fixed order; answers = [the matching target text].',
    'tf':
        'Write a statement that is strictly true or strictly false according to the article. '
            'options = ["True","False"]; answers = ["True"] or ["False"]. '
            'Roughly half must be false, and every false one is falsified by a specific word in the text.',
    'order':
        'Take 4–5 consecutive sentences from one paragraph, shuffle them, and list them as (1)…(n) '
            'inside prompt. options = []. answers = [the correct order as numbers, e.g. "2","4","1","3"].',
    'summary':
        'Ask for a summary of the article in 60–80 English words. options = []. '
            'answers = [one model summary inside the word limit].',
    'translateEn':
        'Pick one informative sentence from the article and ask for its Chinese translation. '
            'options = []. answers = [one faithful Chinese translation].',
    'translateZh':
        'Give a Chinese translation of one sentence from the article and ask the learner to render it '
            'back into English. options = []. answers = [the original English sentence].',
    'vocab':
        'Take one word from the article and ask what it means in this sentence. '
            'options = 4 short Chinese glosses, or [] if the answer is typed; answers = [the correct gloss].',
    'phrase':
        'Take a collocation or fixed phrase from the article, blank it out inside its sentence, and ask '
            'for the missing phrase. options = []. answers = [the phrase as it appears in the text].',
    'rewrite':
        'Give one sentence and a rewrite instruction (passive, reported speech, combine with although…). '
            'options = []. answers = [one acceptable rewrite].',
    'open':
        'Ask a question that needs 2–3 sentences of reasoning grounded in the article (why, how, what it '
            'implies). options = []. answers = [a model answer of 2–3 sentences].',
  };

  static const _genericRule =
      'Write items of this type about the article. options = [] unless the type needs choices; '
      'answers = [the expected answer as text].';

  static String practiceUser({
    required List<PracticeItem> plan,
    required String article,
    String? level,
    String? extra,
  }) {
    final total = plan.fold<int>(0, (sum, item) => sum + item.count);
    final mix = plan
        .map(
          (item) =>
              '- ${item.label} (type "${item.type}") — ${item.count} question(s). '
              '${_typeRules[item.type] ?? _genericRule}',
        )
        .join('\n');
    final levelBlock = (level == null || level.trim().isEmpty)
        ? 'Keep the text accessible to an upper-intermediate reader: common vocabulary, '
            'sentences of ordinary length, inference that stays close to the text.'
        : 'Target level: ${level.trim()}\n'
            'Keep vocabulary, sentence length and inference depth inside that level.';
    final extraBlock = (extra == null || extra.trim().isEmpty)
        ? ''
        : '\nEXTRA REQUIREMENTS FROM THE READER\n'
            '${extra.trim()}\n'
            'Obey them unless they conflict with the rules above.';
    return 'Write reading-exercise items about the article at the end of this message. '
        'Read it first; the items come from it and from nothing else.\n'
        '\nWHAT TO WRITE\n'
        'Exactly $total items, in this mix:\n'
        '$mix\n'
        '\nHARD RULES\n'
        '1. Exactly $total items. Never pad with a question you cannot prove from the article.\n'
        '2. Every answer is findable in the article. No outside knowledge, no general knowledge, '
        'no guessing.\n'
        '3. Each item tests something different; never ask two questions about the same sentence.\n'
        '4. sourceQuote is one sentence copied verbatim from the article that proves the answer. '
        'If no such sentence exists, replace the item with one you can prove.\n'
        '5. analysis is in Chinese, 1–2 sentences: where the answer sits in the text, and why the '
        'other options fail or why this form is correct.\n'
        '6. In choice items the four options differ in meaning, exactly one is right, and no option '
        'is "all of the above" or "none of the above".\n'
        '7. prompts, options and sourceQuote are in English; only analysis is in Chinese.\n'
        '8. $levelBlock\n'
        '$extraBlock'
        '\nOUTPUT\n'
        'A JSON array of exactly $total objects. Each object has these keys:\n'
        '- type: one of ${plan.map((item) => item.type).join(', ')}\n'
        '- prompt: the question or task, in English\n'
        '- options: the choice list; [] unless the type rule above fills it\n'
        '- answers: the expected answer(s), as plain text\n'
        '- analysis: 中文解析\n'
        '- sourceQuote: one verbatim sentence from the article\n'
        'Shape:\n'
        '[{"type":"choice","prompt":"...","options":["..."],"answers":["..."],'
        '"analysis":"...","sourceQuote":"..."}]'
        '\n\nARTICLE\n'
        '$article';
  }

  // ------------------------------------------------------------------ curate

  static const curateSystem =
      'You are a careful editor preparing an English article for a Chinese learner who reads English '
      'as a foreign language. You cut; you never add.';

  static String curateUser({String? focus}) {
    final focusBlock = (focus == null || focus.trim().isEmpty)
        ? ''
        : '\nFOCUS\n'
            'The reader asked for this angle: ${focus.trim()}\n'
            'Keep material that serves it and cut harder elsewhere.\n';
    return 'Tighten the article below for a learner who wants the reporting without the padding.\n'
        '\nRULES\n'
        '1. Delete boilerplate, repeated background, housekeeping sentences, and anything that only '
        'restates the sentence before it.\n'
        '2. Keep every number, name, date and quotation exactly as written. Never paraphrase a fact.\n'
        '3. Sentences you keep stay verbatim and in their original order: drop sentences, do not rewrite '
        'them.\n'
        '4. Add nothing: no headings, no summary, no explanation, no opinion.\n'
        '5. Keep 45–65% of the original length, and at least 3 paragraphs.\n'
        '6. Every paragraph must still read as complete sentences.\n'
        '$focusBlock'
        '\nOUTPUT\n'
        'A JSON array of paragraph strings in reading order, nothing else:\n'
        '["first paragraph", "second paragraph"]';
  }

  // ------------------------------------------------------------------- grade

  static const gradeSystem =
      'You grade short answers written by Chinese learners of English. '
      'You are strict about meaning and lenient about form.';

  static String gradeUser({required String expected, required String answer}) {
    return 'EXPECTED ANSWER\n'
        '$expected\n'
        '\nLEARNER\'S ANSWER\n'
        '$answer\n'
        '\nJudge the learner\'s answer against the expected answer.\n'
        '- correct = true only when it carries the same meaning. Ignore capitalisation, punctuation, '
        'articles and small spelling slips; accept a synonym or a grammatical paraphrase.\n'
        '- correct = false when it is off-topic, contradicts the expected answer, is too vague to '
        'check, or only repeats words from the question.\n'
        '- score: 1.0 exact; 0.8–0.9 the same meaning in different words; 0.4–0.6 partly right; 0 wrong.\n'
        '- comment: Chinese, at most 25 characters, says what was right or what was missing. '
        'No praise padding, no restating the answer.\n'
        '\nOUTPUT\n'
        '{"correct": true, "score": 0.9, "comment": "意思对，但漏了时间"}';
  }

  // ---------------------------------------------------------------- sentence

  static const sentenceSystem =
      '你是英语语法与语块分析助手，服务对象是把英语当外语学的中文母语者。'
      '只输出 JSON 对象，不要解释、不要 Markdown。';

  static String sentenceUser(String sentence) {
    return '拆解并分析这句话：\n'
        '$sentence\n'
        '\n规则\n'
        '1. translation：整句自然中文，不要逐字直译。\n'
        '2. chunks：3–6 个语块，text 必须是原句里连续出现的原文片段，不许改写；'
        'type 取 phrase / clause / idiom / fixed；note 用中文说明这个语块的意思或语法作用。\n'
        '3. grammar：最多 3 条，point 是语法点名称（如「现在完成时」），explain 一句话说清它在这句里干什么。\n'
        '4. keywords：最多 5 个，只挑影响理解的词；pos 用 n. / v. / adj. / adv. / prep. 这类缩写，'
        'zh 给这个词在这句语境里的意思。\n'
        '5. 不确定就不要写，宁可少一条。\n'
        '\n输出\n'
        '{"translation":"...","chunks":[{"text":"...","type":"phrase","note":"..."}],'
        '"grammar":[{"point":"...","explain":"..."}],'
        '"keywords":[{"word":"...","pos":"n.","zh":"..."}]}';
  }

  // ------------------------------------------------------------------- vocab

  static const organizeSystem =
      '你是一个英语词汇整理助手，为中文母语的学习者服务。只输出 JSON。';

  static String organizeUser(String listJson) {
    return '输入是一批用户在阅读时查过的生词（JSON 数组，每项含 word / mode / hint）。\n'
        '\n任务\n'
        '按语义主题把它们分组，并为每个词补全词条信息。\n'
        '\n规则\n'
        '1. 每个输入词必须原样出现在输出里，且只出现一次；不要新增输入里没有的词。\n'
        '2. groups 最多 6 组，theme 用中文短名（如「经济与商业」），每组至少 2 个词。\n'
        '3. lemma 是词族原形，小写；family 含 lemma 本身，按常见程度排序，最多 6 个。\n'
        '4. pos 用 n. / v. / adj. / adv. / phr. 这类缩写。\n'
        '5. zh 给最常见的一到两个义项，用「；」分隔；en 是一句不超过 15 词的英文释义。\n'
        '6. example 是一个 12–18 词的英文例句，语境贴近新闻阅读，不要出现中文。\n'
        '7. hint 只是参考，与 word 本身冲突时以 word 为准。\n'
        '\n输出\n'
        '{"groups":[{"theme":"...","items":[{"word":"...","lemma":"...","pos":"...","zh":"...",'
        '"en":"...","family":["..."],"example":"..."}]}]}\n'
        '\n生词列表\n'
        '$listJson';
  }

  // --------------------------------------------------------------- translate

  static const translateSystem =
      'You are a translator. You translate faithfully and completely, keep names, numbers and line '
      'structure, and output only the translation: no notes, no quotes, no original text.';

  static String translateUser({
    required String from,
    required String to,
    required String text,
  }) {
    return 'Translate the text below from $from to $to.\n'
        '\nTEXT\n'
        '$text';
  }
}
