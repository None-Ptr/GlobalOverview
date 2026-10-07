import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/models/models.dart';

class CurateService {
  final LlmService _llm;
  CurateService(this._llm);

  Future<List<ArticleBlock>> curate(List<ArticleBlock> blocks, {String? focus}) async {
    final text = blocks.where((b) => b.type == 'p').map((b) => b.text ?? '').join('\n\n');
    final prompt =
        'Rewrite the following English passage for a Chinese learner: keep core meaning, trim redundancy, keep it readable. ${focus != null ? "Focus: $focus." : ""} Return JSON array of paragraph strings (no images).';
    final res = await _llm.structured('You are an editor that curates English news for learners.', '$prompt\n\nTEXT:\n${LlmService.clipArticle(text)}');
    List<String> paras = [];
    if (res is List) {
      paras = res.whereType<String>().toList();
    } else if (res is Map && res['paragraphs'] is List) {
      paras = (res['paragraphs'] as List).whereType<String>().toList();
    }
    if (paras.isEmpty) return [];
    return paras.map((t) => ArticleBlock(type: 'p', text: t)).toList();
  }
}
