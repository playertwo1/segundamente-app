import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/tag_model.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  Future<TimelineViewModel> pumpBar(WidgetTester tester) async {
    final vm = TimelineViewModel.forTest(autoLoad: false)
      ..tags = [TagModel(name: 'Project')];
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 60,
          child: ListenableBuilder(
            listenable: vm,
            builder: (_, __) => TimelineFilterBar(
              viewModel: vm,
              onPageSelected: (_) {},
              onInsightSelected: () {},
            ),
          ),
        ),
      ),
    ));
    return vm;
  }

  testWidgets('no active-filter chip while showing all', (tester) async {
    await pumpBar(tester);
    expect(find.byKey(const ValueKey('timeline-active-filter')), findsNothing);
  });

  testWidgets('a filter that is not a chip is shown and clears on tap',
      (tester) async {
    final vm = await pumpBar(tester);
    vm.setActiveFilter('teste');
    await tester.pump();

    final chip = find.byKey(const ValueKey('timeline-active-filter'));
    expect(chip, findsOneWidget);
    expect(tester.widget<Semantics>(chip).properties.selected, isTrue);
    expect(find.descendant(of: chip, matching: find.text('teste')),
        findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    expect(vm.activeFilter, 'all');
    expect(find.byKey(const ValueKey('timeline-active-filter')), findsNothing);
  });

  testWidgets('a saved view with several tags is joined', (tester) async {
    final vm = await pumpBar(tester);
    vm.setTagFilters(['a', 'b']);
    await tester.pump();
    expect(find.text('a + b'), findsOneWidget);
  });
}
