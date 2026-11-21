// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: GoRouter for declarative routing.
// ViewModels are created in route builders and passed to screens.

import 'package:memex/ui/knowledge/widgets/knowledge_file_page.dart';
import 'package:memex/ui/search/view_models/global_search_viewmodel.dart';
import 'package:memex/ui/search/widgets/global_search_screen.dart';
import 'package:memex/ui/agent_activity/view_models/agent_activity_viewmodel.dart';
import 'package:memex/ui/agent_activity/widgets/agent_activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/memory/view_models/memory_viewmodel.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/ui/media_library/widgets/media_library_screen.dart';
import 'package:memex/ui/thread_document/view_models/thread_document_viewmodel.dart';
import 'package:memex/ui/thread_document/widgets/thread_document_screen.dart';
import 'package:memex/ui/todo/widgets/todo_screen.dart';
import 'package:memex/ui/memory/widgets/memory_screen.dart';
import 'package:memex/ui/character/widgets/character_config_screen.dart';
import 'package:memex/ui/character/widgets/tavern_import_screen.dart';
import 'package:memex/ui/character/view_models/character_viewmodel.dart';
import 'package:memex/ui/character/view_models/character_edit_viewmodel.dart';
import 'package:memex/ui/character/view_models/persona_chat_viewmodel.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/calendar/view_models/calendar_viewmodel.dart';
import 'package:memex/ui/calendar/widgets/calendar_screen.dart';
import 'package:memex/ui/tags/view_models/tag_tree_viewmodel.dart';
import 'package:memex/ui/tags/widgets/tag_tree_screen.dart';
import 'package:memex/ui/glossary/view_models/glossary_viewmodel.dart';
import 'package:memex/ui/glossary/widgets/glossary_screen.dart';
import 'package:memex/ui/saved_views/view_models/saved_views_viewmodel.dart';
import 'package:memex/ui/saved_views/widgets/saved_views_screen.dart';
import 'package:memex/ui/topics/view_models/topics_viewmodel.dart';
import 'package:memex/ui/topics/widgets/topics_screen.dart';
import 'package:memex/ui/chat/view_models/chat_viewmodel.dart';
import 'package:memex/ui/chat/widgets/chat_history_screen.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/floating_chat_mode.dart';
import 'package:memex/ui/floating_chat/view_models/floating_capture_viewmodel.dart';
import 'package:memex/ui/floating_chat/widgets/floating_capture_screen.dart';
import 'package:memex/ui/floating_chat/widgets/floating_chat_screen.dart';
import 'package:memex/ui/floating_chat/view_models/floating_todo_complete_viewmodel.dart';
import 'package:memex/ui/floating_chat/widgets/floating_todo_add_screen.dart';
import 'package:memex/ui/floating_chat/widgets/floating_todo_complete_screen.dart';
import 'package:memex/ui/todo/view_models/todo_viewmodel.dart';

FloatingChatMode _floatingModeOf(
        GoRouterState state, FloatingChatMode fallback) =>
    FloatingChatMode.parse(state.uri.queryParameters['mode']) ?? fallback;

/// A floating sheet page (F15-02, F15-04). Opaque so the screens below are not
/// painted; the Activity itself is transparent, so the launcher shows through.
Page<void> _floatingSheetPage(Widget child) {
  return CustomTransitionPage<void>(
    opaque: true,
    barrierColor: null,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    child: child,
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final arrival = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: arrival,
        child: SlideTransition(
          position: arrival.drive(Tween(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          )),
          child: child,
        ),
      );
    },
  );
}

/// Creates the app [GoRouter]. Root content is built by [rootBuilder].
/// [initialLocation] starts the app elsewhere, e.g. the floating chat sheet.
GoRouter createAppRouter(
  GlobalKey<NavigatorState> navigatorKey,
  Widget Function() rootBuilder, {
  String initialLocation = AppRoutes.home,
  Future<String?> Function()? floatingSessionLoaderForTesting,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => rootBuilder(),
      ),
      GoRoute(
        path: AppRoutes.floatingChat,
        pageBuilder: (context, state) => _floatingSheetPage(
          FloatingChatScreen(
            mode: _floatingModeOf(state, FloatingChatMode.type),
            loadSessionId: floatingSessionLoaderForTesting,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.floatingCapture,
        pageBuilder: (context, state) {
          final mode = _floatingModeOf(state, FloatingChatMode.note);
          return _floatingSheetPage(
            FloatingCaptureScreen(
              viewModel: FloatingCaptureViewModel(
                router: context.read<MemexRouter>(),
                mode: mode,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.floatingTodoAdd,
        pageBuilder: (context, state) => _floatingSheetPage(
          FloatingTodoAddScreen(
            viewModel: TodoViewModel(router: context.read<MemexRouter>()),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.floatingTodoComplete,
        pageBuilder: (context, state) => _floatingSheetPage(
          FloatingTodoCompleteScreen(
            viewModel: FloatingTodoCompleteViewModel(
              router: context.read<MemexRouter>(),
              todoId: state.uri.queryParameters['id'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.userSetup,
        builder: (context, state) => UserSetupScreen(
          onUserCreated: () {
            context.go(AppRoutes.home);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => GlobalSearchScreen(
          viewModel: GlobalSearchViewModel(router: context.read<MemexRouter>()),
          onOpenCard: (card) =>
              context.push('${AppRoutes.timelineCardDetail}/${card.id}'),
          onOpenFile: (path) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => KnowledgeFilePage(filePath: path),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.activity,
        builder: (context, state) => AgentActivityScreen(
          viewModel:
              AgentActivityViewModel(router: context.read<MemexRouter>()),
          onBackToTimeline: () => context.go(AppRoutes.home),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.threadDocument}/:id',
        builder: (context, state) => ThreadDocumentScreen(
          viewModel: ThreadDocumentViewModel(
            router: context.read<MemexRouter>(),
            docId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.todo,
        builder: (context, state) {
          final vm = TodoViewModel(router: context.read<MemexRouter>());
          return TodoScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.memory,
        builder: (context, state) {
          final vm = MemoryViewModel(router: context.read<MemexRouter>());
          vm.loadMemory();
          return MemoryScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.mediaLibrary,
        builder: (context, state) {
          final vm = MediaLibraryViewModel(
            router: context.read<MemexRouter>(),
          );
          return MediaLibraryScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.characterConfig,
        builder: (context, state) {
          final vm = CharacterViewModel(router: context.read<MemexRouter>());
          return CharacterConfigScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.characterEdit,
        builder: (context, state) {
          final character = state.extra as CharacterModel?;
          return CharacterEditPage(
            viewModel: CharacterEditViewModel(
              router: context.read<MemexRouter>(),
              character: character,
            ),
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.personaChat}/:characterId',
        builder: (context, state) {
          final characterId = state.pathParameters['characterId'] ?? '';
          return PersonaChatScreen(
            viewModel: PersonaChatViewModel(
              router: context.read<MemexRouter>(),
              initialCharacterId: characterId,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.tags,
        builder: (context, state) => TagTreeScreen(
          viewModel: TagTreeViewModel(router: context.read<MemexRouter>()),
        ),
      ),
      GoRoute(
        path: AppRoutes.savedViews,
        builder: (context, state) => SavedViewsScreen(
          viewModel: SavedViewsViewModel(router: context.read<MemexRouter>()),
        ),
      ),
      GoRoute(
        path: AppRoutes.glossary,
        builder: (context, state) => GlossaryScreen(
          viewModel: GlossaryViewModel(router: context.read<MemexRouter>()),
        ),
      ),
      GoRoute(
        path: AppRoutes.topics,
        builder: (context, state) => TopicsScreen(
          viewModel: TopicsViewModel(router: context.read<MemexRouter>()),
        ),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) {
          final initialDate = state.extra as DateTime? ?? DateTime.now();
          final vm = CalendarViewModel(
            router: context.read<MemexRouter>(),
            initialDate: initialDate,
          );
          vm.fetchMonthData(DateTime(initialDate.year, initialDate.month));
          return CalendarScreen(initialDate: initialDate, viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.chatHistory,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final agentName = extra['agentName'] as String?;
          final title = extra['title'] as String?;
          final vm = ChatViewModel(
            router: context.read<MemexRouter>(),
            agentName: agentName,
          );
          return ChatHistoryScreen(
            viewModel: vm,
            agentName: agentName,
            title: title,
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.timelineCardDetail}/:id',
        builder: (context, state) {
          final cardId = state.pathParameters['id'] ?? '';
          return TimelineCardDetailScreen(cardId: cardId);
        },
      ),
      GoRoute(
        path: AppRoutes.personalCenter,
        builder: (_, __) => const PersonalCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.tavernImport,
        builder: (_, __) => const TavernImportScreen(),
      ),
    ],
  );
}
