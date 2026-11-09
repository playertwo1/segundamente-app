class AgentDefinitions {
  static const String commentAgent = 'comment_agent';
  static const String chatAgent = 'chat_agent';
  // Keep the persisted ID stable so existing per-agent model settings survive
  // the consolidation from CompanionAgent to CharacterAgent.
  static const String characterAgent = 'companion_agent';
  static const String profileAgent = 'profile_agent';
  // Optional: a cheaper model for the background insight analysis. Unset, the
  // analysis uses the chat model.
  static const String insightAgent = 'insight_agent';

  /// Order here drives the display order in the agent configuration screen.
  static const Map<String, String> displayNames = {
    chatAgent: 'Chat',
    commentAgent: 'Comments',
    characterAgent: 'Companion',
    profileAgent: 'Memory',
    insightAgent: 'Insights',
  };

  /// Agent IDs exposed in the model configuration screen.
  ///
  /// Keeping this derived from the display-name registry makes the settings UI
  /// pick up newly registered built-in agents automatically.
  static List<String> get configurableAgentIds =>
      List.unmodifiable(displayNames.keys);
}
