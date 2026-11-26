import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/prompts.dart';
import 'package:global_overview/models/models.dart';

class CurateService {
  final LlmService _llm;
  CurateService(this._llm);

  Future<List<ArticleBlock>> curate(List<ArticleBlock> blocks, {String? focus}) async {
    final text = blocks.where((b) => b.type == 'p').map((b) => b.text ?? '').join('\n\n');
    final res = await _llm.structured(
      Prompts.curateSystem,
      '${Prompts.curateUser(focus: focus)}\n\nARTICLE\n${LlmService.clipArticle(text)}',
      operation: 'AI 精选',
    );
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
