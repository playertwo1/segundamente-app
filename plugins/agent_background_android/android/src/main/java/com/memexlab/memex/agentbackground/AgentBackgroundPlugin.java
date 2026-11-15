package com.memexlab.memex.agentbackground;

import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Map;

public final class AgentBackgroundPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL = "com.memexlab.memex/agent_background";
  private static final String SERVICE_CLASS = "com.memexlab.memex.AgentBackgroundService";
  private static final String ACTION_UPDATE = "com.memexlab.memex.agent_background.UPDATE";
  private static final String ACTION_STOP = "com.memexlab.memex.agent_background.STOP";
  private static final String EXTRA_WATCH_BACKGROUND_WORK = "watchBackgroundWork";
  private static final int NOTIFICATION_ID = 188;
  // Todo widget snapshot: same names as TodoWidgetSnapshot.kt, which only reads them.
  private static final String TODO_CHANNEL = "com.memexlab.memex/todo_widget";
  private static final String TODO_PREFS = "todo_widget_snapshot";
  private static final String TODO_KEY = "snapshot";
  private static final String TODO_REFRESH_ACTION = "com.memexlab.memex.widget.REFRESH";
  private static final String TODO_PROVIDER_CLASS =
      "com.memexlab.memex.widget.SegundaMenteWidgetProvider";

  private Context applicationContext;
  private MethodChannel channel;
  private MethodChannel todoChannel;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    applicationContext = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
    todoChannel = new MethodChannel(binding.getBinaryMessenger(), TODO_CHANNEL);
    todoChannel.setMethodCallHandler(this::onTodoWidgetCall);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    if (todoChannel != null) {
      todoChannel.setMethodCallHandler(null);
      todoChannel = null;
    }
    applicationContext = null;
  }

  // Registered in every engine (app, floating sheet, WorkManager), so any of them can refresh the widget.
  private void onTodoWidgetCall(MethodCall call, MethodChannel.Result result) {
    if (!"updateSnapshot".equals(call.method)) {
      result.notImplemented();
      return;
    }
    if (!(call.arguments instanceof String)) {
      result.error("bad_snapshot", "The Todo snapshot must be a JSON string.", null);
      return;
    }
    // commit(), not apply(): the refresh broadcast below must find the snapshot on disk.
    applicationContext
        .getSharedPreferences(TODO_PREFS, Context.MODE_PRIVATE)
        .edit()
        .putString(TODO_KEY, (String) call.arguments)
        .commit();
    applicationContext.sendBroadcast(
        new Intent(TODO_REFRESH_ACTION)
            .setClassName(applicationContext.getPackageName(), TODO_PROVIDER_CLASS));
    result.success(null);
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (applicationContext == null) {
      result.error("unavailable", "Application context is unavailable", null);
      return;
    }

    switch (call.method) {
      case "updateAgentStatus":
        startOrUpdateService(call);
        result.success(null);
        break;
      case "finishAgentStatus":
        finishService(call);
        result.success(null);
        break;
      case "stopAgentStatus":
        clearService();
        result.success(null);
        break;
      case "consumeInitialAgentAction":
        result.success(null);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private void startOrUpdateService(MethodCall call) {
    Map<?, ?> args = call.arguments instanceof Map ? (Map<?, ?>) call.arguments : null;
    String state = stringArg(args, "state", "active");
    if ("completed".equals(state) || "idle".equals(state)) {
      clearService();
      return;
    }
    Intent intent = serviceIntent(ACTION_UPDATE);
    putStringExtra(intent, args, "state", "active");
    putStringExtra(intent, args, "title", "Memex Agent");
    putStringExtra(intent, args, "stage", "Processing");
    putStringExtra(intent, args, "detail", "");
    putStringExtra(intent, args, "summary", "");
    putStringExtra(intent, args, "taskSummary", "");
    putStringExtra(intent, args, "statusText", "");
    putIntExtra(intent, args, "progressCompleted");
    putIntExtra(intent, args, "progressTotal");
    putIntExtra(intent, args, "remainingTasks");
    putIntExtra(intent, args, "pending");
    putIntExtra(intent, args, "processing");
    putIntExtra(intent, args, "retrying");
    intent.putExtra(EXTRA_WATCH_BACKGROUND_WORK, booleanArg(args, "isInBackground", false));
    startForegroundServiceCompat(intent);
  }

  private void finishService(MethodCall call) {
    Map<?, ?> args = call.arguments instanceof Map ? (Map<?, ?>) call.arguments : null;
    String state = stringArg(args, "state", "active");
    if ("completed".equals(state) || "idle".equals(state)) {
      clearService();
      return;
    }
    state = stringArg(args, "state", "");
    if ("completed".equals(state) || "idle".equals(state)) {
      clearService();
      return;
    }
    startOrUpdateService(call);
  }

  private Intent serviceIntent(String action) {
    Intent intent = new Intent();
    intent.setClassName(applicationContext, SERVICE_CLASS);
    intent.setAction(action);
    return intent;
  }

  private void startForegroundServiceCompat(Intent intent) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      applicationContext.startForegroundService(intent);
    } else {
      applicationContext.startService(intent);
    }
  }

  private void clearService() {
    applicationContext.stopService(serviceIntent(ACTION_STOP));
    NotificationManager manager =
        (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
    if (manager != null) {
      manager.cancel(NOTIFICATION_ID);
    }
  }

  private static void putStringExtra(
      Intent intent, Map<?, ?> args, String key, String fallback) {
    intent.putExtra(key, stringArg(args, key, fallback));
  }

  private static void putIntExtra(Intent intent, Map<?, ?> args, String key) {
    Object value = args == null ? null : args.get(key);
    intent.putExtra(key, value instanceof Number ? ((Number) value).intValue() : 0);
  }

  private static String stringArg(Map<?, ?> args, String key, String fallback) {
    Object value = args == null ? null : args.get(key);
    return value instanceof String ? (String) value : fallback;
  }

  private static boolean booleanArg(Map<?, ?> args, String key, boolean fallback) {
    Object value = args == null ? null : args.get(key);
    return value instanceof Boolean ? (Boolean) value : fallback;
  }
}
