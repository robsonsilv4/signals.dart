// coverage:ignore-start
import 'dart:convert';

import 'dart:developer' as developer;

import 'core/signals.dart';
import 'utils/constants.dart';

/// Reload the devtools
@Deprecated('Use the DevToolsSignalsObserver instead')
void reloadSignalsDevTools() {
  final target = SignalsObserver.instance;
  if (target is DevToolsSignalsObserver) {
    target.reassemble();
  }
}

/// Disable the devtools
@Deprecated('Use the "signalsDevToolsEnabled = false" instead')
void disableSignalsDevTools() {
  signalsDevToolsEnabled = false;
}

/// Check if the signals devtools are enabled
bool get signalsDevToolsEnabled {
  final target = SignalsObserver.instance;
  if (target is DevToolsSignalsObserver) {
    return target.enabled;
  }
  return false;
}

/// Manually enable/disable signals devtools
set signalsDevToolsEnabled(bool value) {
  final target = SignalsObserver.instance;
  if (target is! DevToolsSignalsObserver && value) {
    SignalsObserver.instance = DevToolsSignalsObserver();
  } else if (target is DevToolsSignalsObserver) {
    target.enabled = value;
  }
}

/// Signals DevTools observer
class DevToolsSignalsObserver implements SignalsObserver {
  final Set<WeakReference<ReadonlySignal>> _signals = {};
  final Set<WeakReference<Computed>> _computed = {};
  final Map<int, int> _effectCount = {};
  final Set<WeakReference<Effect>> _effects = {};

  bool _devToolsInitialized = false;
  bool _devToolsEnabled = kDebugMode;

  /// Check if devTools is enabled
  bool get enabled => _devToolsEnabled;

  /// Enable/Disable devTools
  set enabled(bool value) {
    _devToolsEnabled = value;
    _devToolsInitialized = value;
  }

  /// Reload the signals devTools
  void reassemble() {
    final observer = SignalsObserver.instance;
    if (observer is! DevToolsSignalsObserver) return;
    _debugPostEvent('ext.signals.reassemble', () => observer._getNodes());
  }

// ignore: public_member_api_docs
  void _initDevTools() {
    if (!_devToolsEnabled || _devToolsInitialized) return;
    developer.registerExtension(
      'ext.signals.getAllNodes',
      (method, parameters) async {
        return developer.ServiceExtensionResponse.result(
          json.encode(_getNodes()),
        );
      },
    );
    _devToolsInitialized = true;
  }

// ignore: public_member_api_docs
  void _debugPostEvent(
    String eventKind,
    Map<Object?, Object?> Function() event,
  ) {
    _initDevTools();
    if (!enabled) return;
    if (developer.extensionStreamHasListener) {
      developer.postEvent(eventKind, event());
    }
  }

  @override
  void onComputedCreated(Computed instance) {
    if (!enabled) return;
    log('computed created: [${instance.globalId}|${instance.debugLabel}]');
    _debugPostEvent('ext.signals.computedCreate', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'sources': instance.sources.map((e) => e.globalId).join(','),
        'targets': instance.targets.map((e) => e.globalId).join(','),
        'value': '',
        'type': 'computed',
      };
    });
    _computed.add(WeakReference(instance));
  }

  @override
  void onComputedUpdated(Computed instance, value) {
    if (!enabled) return;
    log('computed updated: [${instance.globalId}|${instance.debugLabel}] => $value');
    _debugPostEvent('ext.signals.computedUpdate', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'value': value?.toString(),
        'sources': instance.sources.map((e) => e.globalId).join(','),
        'targets': instance.targets.map((e) => e.globalId).join(','),
        'type': 'computed',
      };
    });
  }

  @override
  void onSignalCreated(Signal instance) {
    if (!enabled) return;
    log('signal created: [${instance.globalId}|${instance.debugLabel}] => ${instance.peek()}');
    _debugPostEvent('ext.signals.signalCreate', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'value': instance.peek()?.toString(),
        'targets': instance.targets.map((e) => e.globalId).join(','),
        'type': 'signal',
      };
    });
    _signals.add(WeakReference(instance));
  }

  @override
  void onSignalUpdated(Signal instance, dynamic value) {
    if (!enabled) return;
    log('signal updated: [${instance.globalId}|${instance.debugLabel}] => $value');
    _debugPostEvent('ext.signals.signalUpdate', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'value': value?.toString(),
        'targets': instance.targets.map((e) => e.globalId).join(','),
        'type': 'signal',
      };
    });
  }

  /// Logs a message to the console.
  void log(String message) => developer.log(message);

  @override
  void onEffectCreated(Effect instance) {
    if (!enabled) return;
    _effectCount[instance.globalId] = 0;
    _effects.add(WeakReference(instance));
    _debugPostEvent('ext.signals.effectCreate', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'sources': instance.sources.map((e) => e.globalId).join(','),
        'value': '0',
        'type': 'effect',
      };
    });
  }

  @override
  void onEffectCalled(Effect instance) {
    if (!enabled) return;
    var count = _effectCount[instance.globalId] ??= 0;
    _effectCount[instance.globalId] = ++count;
    _debugPostEvent('ext.signals.effectCalled', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        'sources': instance.sources.map((e) => e.globalId).join(','),
        'value': '$count',
        'type': 'effect',
      };
    });
  }

  @override
  void onEffectRemoved(Effect instance) {
    if (!enabled) return;
    _effectCount.remove(instance.globalId);
    _effects.removeWhere((e) => e.target == instance);
    _debugPostEvent('ext.signals.effectRemove', () {
      return {
        'id': instance.globalId,
        'label': instance.debugLabel,
        // 'sources': instance.sources.map((e) => e.globalId).join(','),
        'value': '-1',
        'type': 'effect',
      };
    });
  }

  Map<String, dynamic> _getNodes() {
    final signals = _signals
        .where((e) => e.target != null)
        .map((e) => e.target!)
        .map((e) => {
              'id': e.globalId,
              'label': e.debugLabel,
              'value': e.toString(),
              'targets': e.targets.map((e) => e.globalId).join(','),
              'type': 'signal',
            })
        .toList();
    final computed = _computed
        .where((e) => e.target != null)
        .map((e) => e.target!)
        .map((e) => {
              'id': e.globalId,
              'label': e.debugLabel,
              'value': e.toString(),
              'targets': e.targets.map((e) => e.globalId).join(','),
              'sources': e.sources.map((e) => e.globalId).join(','),
              'type': 'computed',
            })
        .toList();
    final effects = _effects
        .where((e) => e.target != null)
        .map((e) => e.target!)
        .map((e) => {
              'id': e.globalId,
              'label': e.debugLabel,
              'value': '${_effectCount[e.globalId] ?? 0}',
              'sources': e.sources.map((e) => e.globalId).join(','),
              'type': 'effect',
            })
        .toList();
    return {
      'nodes': [...signals, ...computed, ...effects]
    };
  }
}

// coverage:ignore-end
