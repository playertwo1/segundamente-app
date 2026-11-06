import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/related_sessions_service.dart';
import 'package:memex/data/services/session_report_service.dart';
import 'package:memex/domain/models/related_sessions.dart';
import 'package:memex/domain/models/session_report.dart';

/// Lets the agent read matching session reports and sessions that share their
/// topics.
Tool buildRelatedSessionsTool() {
  return Tool(
    name: 'find_related_sessions',
    description:
        '''Find session reports (meetings, imported transcripts, chats \
with a report) about something the user asks.

Pass a short query about a person, project or subject. The search checks text \
first and may add meaning-based matches when semantic search is enabled. \
Sessions that share a topic or project with a match come after them. When \
nothing matches it returns no session: say so, do not guess.

Returns for each session: its id, title, whether it matched the query or \
came by topic, and its non-discarded report items.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Short word or phrase to look for in session reports',
        },
      },
      'required': ['query'],
    },
    executable: (String query) async {
      final userId = AgentCallToolContext.current!.state.metadata['userId'];
      final found = await RelatedSessionsService().find(userId, query);
      if (found.isEmpty) return 'No session matches "$query".';
      final reports = SessionReportService();
      final out = StringBuffer();
      for (final related in found) {
        final report =
            await reports.load(userId: userId, sessionId: related.sessionId);
        if (report == null) continue;
        out.writeln(renderRelatedSession(related, report));
      }
      return out.toString();
    },
  );
}

String renderRelatedSession(RelatedSession related, SessionReport report) {
  final out = StringBuffer()
    ..writeln('--- Session ${related.sessionId}: ${report.title} '
        '(${related.isSeed ? 'matches the query' : 'same topic'}) ---');
  for (final item in report.items) {
    if (item.status == ReportItemStatus.discarded) continue;
    out.writeln('- [${item.kind.name}] ${item.text}');
  }
  return out.toString();
}
