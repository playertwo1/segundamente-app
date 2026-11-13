import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/domain/models/todo_proposal.dart';
import 'package:uuid/uuid.dart';

class TodoProposalSkill extends Skill {
  TodoProposalSkill()
      : super(
          name: 'propose_todo',
          description:
              'Prepares a Todo task suggestion for the owner to review. It '
              'never saves a task.',
          systemPrompt: _systemPrompt,
          tools: [_buildTool()],
        );

  static const _systemPrompt = '''
## Todo task proposals

Use this only when the owner expresses an intention or explicitly asks to make
a task. Call `create_todo_proposal` to attach an editable confirmation card.
The tool creates a proposal artifact only; the task is saved only after the
owner reviews and confirms it.

- Never infer a date or time. A weekday without a calendar date, such as
  "sexta", is ambiguous: set `date_state` to `ambiguous`, preserve the phrase,
  and omit `due_date`.
- Use `date_state: explicit` only when the date is clear from the owner's words
  and current local time context. Otherwise use `unspecified` if no date was
  mentioned.
- Use `time_state: explicit` only when the exact local time was provided; use
  `ambiguous` for vague phrases such as "de manhã"; use `unspecified` when no
  time was mentioned. Do not fill in a default hour.
- Keep the title faithful to the owner's request. Do not invent priority,
  subtasks, recurrence, or alert settings.
- Do not claim the task is saved. Say it is waiting in the confirmation card.
''';

  static Tool _buildTool() => Tool(
        name: 'create_todo_proposal',
        description:
            'Attaches a Todo task proposal for owner review. Does not save a '
            'Todo task.',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'date_state': {
              'type': 'string',
              'enum': ['unspecified', 'explicit', 'ambiguous'],
            },
            'due_date': {
              'type': 'string',
              'description': 'YYYY-MM-DD, only for an explicit date.',
            },
            'date_phrase': {
              'type': 'string',
              'description': 'Original ambiguous date phrase, if any.',
            },
            'time_state': {
              'type': 'string',
              'enum': ['unspecified', 'explicit', 'ambiguous'],
            },
            'due_time': {
              'type': 'string',
              'description': 'HH:mm, only for an explicit time.',
            },
            'time_phrase': {
              'type': 'string',
              'description': 'Original ambiguous time phrase, if any.',
            },
          },
          'required': ['title', 'date_state', 'time_state'],
        },
        executable: (
          String title,
          String dateState,
          String timeState,
          String? dueDate,
          String? datePhrase,
          String? dueTime,
          String? timePhrase,
        ) async {
          final proposal = TodoProposal(
            id: const Uuid().v4(),
            title: title,
            dateState: TodoProposalDateState.values.byName(dateState),
            dueDate: dueDate,
            datePhrase: datePhrase,
            timeState: TodoProposalTimeState.values.byName(timeState),
            dueTime: dueTime,
            timePhrase: timePhrase,
          );
          final artifact = ChatArtifact.todoProposalCard(proposal: proposal);
          return AgentToolResult(
            content: TextPart(
              'Task proposal is waiting for owner confirmation. It has not '
              'been saved to Todo.',
            ),
            metadata: {'artifact': artifact.toJson()},
          );
        },
      );
}
