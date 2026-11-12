import 'package:memex/config/app_flavor.dart';
import 'package:memex/domain/models/llm_config.dart';

/// Centralized feature configuration that varies by flavor.
///
/// All flavor-dependent feature flags and provider lists live here.
/// UI and business logic should query this class instead of checking
/// [AppFlavor] directly, so that adding a new flavor or changing
/// availability is a single-file change.
class AppConfig {
  AppConfig._();

  // ─── LLM Providers ───────────────────────────────────────────────

  /// Provider types available in the current flavor.
  static List<String> get availableProviders {
    return _globalProviders;
  }

  /// Returns true if [providerType] is available in the current flavor.
  static bool isProviderAvailable(String providerType) {
    return availableProviders.contains(providerType);
  }

  static const _globalProviders = [
    // OpenAI
    LLMConfig.typeChatCompletion,
    LLMConfig.typeResponses,
    LLMConfig.typeOpenAiOauth,
    // Anthropic
    LLMConfig.typeClaude,
    LLMConfig.typeClaudeOauth,
    LLMConfig.typeBedrockClaude,
    // Google
    LLMConfig.typeGemini,
    LLMConfig.typeGeminiOauth,
    // Aggregators
    LLMConfig.typeOpenRouter,
    LLMConfig.typeOllama,
  ];

  // ─── Feature Flags ───────────────────────────────────────────────
  // Add more flavor-dependent flags here as needed, e.g.:
  //
  // D-035: the upstream project's paid model service (memexlab.ai) is not
  // offered in Segunda Mente; the code stays dormant behind this flag.
  static bool get enableMemexModelService => false;

  // F7-03: entry to the hands-free voice screen. The microphone is closed
  // while the app speaks and a tap interrupts it, because the S25 loudspeaker
  // echo triggered the voice detector (D-049, docs/F7-03-voz-duplex.md).
  static bool get enableDuplexVoice => true;
  // static bool get enableICloudSync => AppFlavor.isGlobal;
  // static bool get enableHealthKit  => AppFlavor.isGlobal;
}
