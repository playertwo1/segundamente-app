// F9-03: roda o corpus F9-02 contra o prompt real do app.
//   dart run docs/medicoes/f9-03/corpus.dart prompts > prompts.json
//   dart run docs/medicoes/f9-03/corpus.dart score respostas.json
// Só dados fictícios. A chamada ao modelo fica em rodar.py.
import 'dart:convert';
import 'dart:io';

import 'package:memex/domain/models/session_report.dart';

const kindOf = {
  'tarefa': ReportItemKind.task,
  'resumo': ReportItemKind.summary,
  'ideia': ReportItemKind.idea,
  'decisao': ReportItemKind.decision,
  'duvida': ReportItemKind.question,
  'followup': ReportItemKind.followUp,
};

List<ReportSegment> segmentsOf(Map c, Map pages) {
  if (c['origem'] == 'pdf') {
    final p = (pages[c['id']] as Map).entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
    final out = <ReportSegment>[];
    for (final e in p) {
      if ((e.value as String? ?? '').trim().isEmpty) continue;
      out.add(ReportSegment(
          id: 'seg_${out.length}', text: e.value as String, clock: 'p.${e.key}'));
    }
    return out;
  }
  final out = <ReportSegment>[];
  for (final line in (c['texto'] as String).split('\n')) {
    final m = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(line.trim());
    if (line.trim().isEmpty) continue;
    out.add(ReportSegment(
        id: 'seg_${out.length}',
        text: m == null ? line.trim() : m.group(2)!,
        clock: m?.group(1)));
  }
  return out;
}

void main(List<String> args) {
  final cases = (jsonDecode(File('docs/medicoes/f9-02/corpus.json')
          .readAsStringSync()) as Map)['casos'] as List;
  final pages = jsonDecode(
      File('test/fixtures/f9/paginas_esperadas.json').readAsStringSync()) as Map;
  if (args.first == 'prompts') {
    print(jsonEncode([
      for (final c in cases)
        if (segmentsOf(c, pages).isNotEmpty)
          {
            'id': c['id'],
            'system': reportExtractionSystemPrompt(ReportKind.livre),
            'user': reportExtractionUserPrompt(segmentsOf(c, pages)),
          }
    ]));
    return;
  }
  final replies =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  var valid = 0, asked = 0, tasksExpected = 0, tasksFound = 0, falseTasks = 0;
  var pdfItems = 0, pdfPageOk = 0;
  for (final c in cases) {
    final segs = segmentsOf(c, pages);
    if (segs.isEmpty) continue;
    asked++;
    final expected = (c['esperado'] as List).cast<Map>();
    final expTasks = expected.where((e) => e['tipo'] == 'tarefa').length;
    tasksExpected += expTasks;
    SessionReport report;
    try {
      report = sessionReportFromModelJson(
        sessionId: c['id'] as String,
        kind: ReportKind.livre,
        customTitle: null,
        segments: segs,
        json: reportModelReplyJson(replies[c['id']] as String),
      );
    } catch (e) {
      print('${c['id']} INVALIDO: $e');
      continue;
    }
    valid++;
    final tasks =
        report.items.where((i) => i.kind == ReportItemKind.task).toList();
    tasksFound += tasks.length < expTasks ? tasks.length : expTasks;
    if (tasks.length > expTasks) falseTasks += tasks.length - expTasks;
    if (c['origem'] == 'pdf') {
      final pagesOk = expected.map((e) => e['evidencia']).toSet();
      for (final i in report.items) {
        pdfItems++;
        if (pagesOk.contains(i.source.clock)) pdfPageOk++;
      }
    }
    print('${c['id']} ${c['categoria']}: esperado '
        '${expected.map((e) => e['tipo']).join(',')} | veio '
        '${report.items.map((i) => i.kind.name).join(',')}');
  }
  print('respostas validas: $valid/$asked');
  print('tarefas esperadas encontradas: $tasksFound/$tasksExpected');
  print('tarefas a mais (falsas): $falseTasks');
  print('PDF itens com pagina certa: $pdfPageOk/$pdfItems');
}
