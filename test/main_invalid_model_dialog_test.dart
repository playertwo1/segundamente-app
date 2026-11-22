import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/main.dart';

void main() {
  test('shouldSuppressInvalidModelDialog suppresses only companion default key',
      () {
    expect(
      shouldSuppressInvalidModelDialog(
        InvalidModelConfigMessage(
          agentId: 'Companion',
          configKey: LLMConfig.defaultClientKey,
        ),
      ),
      isTrue,
    );
    expect(
      shouldSuppressInvalidModelDialog(
        InvalidModelConfigMessage(
          agentId: 'Insight',
          configKey: LLMConfig.defaultClientKey,
        ),
      ),
      isFalse,
    );
    expect(
      shouldSuppressInvalidModelDialog(
        InvalidModelConfigMessage(
          agentId: 'Companion',
          configKey: 'custom-key',
        ),
      ),
      isFalse,
    );
  });
}
