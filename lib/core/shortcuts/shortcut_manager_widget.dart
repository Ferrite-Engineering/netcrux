// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/core/shortcuts/shortcut_conflicts.dart';

/// A [ShortcutManager] that passes all key events through when a text-input
/// widget ([EditableText]) currently holds focus.
///
/// Without this guard, single-character shortcuts would swallow keystrokes
/// inside dialogs or inline text fields. Mirrors the WaveCrux pattern.
class _TextAwareShortcutManager extends ShortcutManager {
  _TextAwareShortcutManager({required super.shortcuts});

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_isTextInputFocused() && _isBareLetter()) {
      return KeyEventResult.ignored;
    }
    if (_activatesFocusedControl(event)) return KeyEventResult.ignored;
    return super.handleKeypress(context, event);
  }

  /// True for a bare Space or Enter while the focused widget is a control
  /// that Space and Enter activate — a button, a checkbox, a tile.
  ///
  /// This manager sits above the framework's own `Space → ActivateIntent`
  /// shortcut, so an action bound to a bare Space or Enter (a user remap —
  /// bare keys are bindable) would consume the key on a focused button and
  /// the button would never activate. Keyboard and screen-reader users press
  /// exactly those keys on the control they are on. Controls that accept
  /// activation own the two keys; everywhere else (the schematic canvas) the
  /// binding still fires.
  static bool _activatesFocusedControl(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!_isBareLetter() || HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final action = Actions.maybeFind<ActivateIntent>(focusContext);
    return action != null && action.isEnabled(const ActivateIntent());
  }

  /// True when the current event has no Ctrl / Cmd / Alt modifier. Shift
  /// alone is not counted — bare Shift+key combos should still be blocked
  /// inside text fields.
  static bool _isBareLetter() =>
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.isMetaPressed &&
      !HardwareKeyboard.instance.isAltPressed;

  /// True when a text-input widget is anywhere in the focus ancestry.
  ///
  /// `EditableText` attaches its `FocusNode` to an inner `Focus` child, so
  /// `primaryFocus.context.widget` is never `EditableText` itself; walking
  /// up the ancestor elements finds it reliably.
  static bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

/// Wraps [child] with Flutter's [Shortcuts] and [Actions] machinery, using
/// bindings from [ShortcutBindingsProvider].
///
/// Pass [handlers] for globally-scoped actions (e.g. opening the command
/// palette). Context-sensitive actions (zoom, pan, navigation) should
/// register their own [Actions] widget lower in the tree — unhandled
/// intents propagate up to the global handler.
///
/// The keyboard is a fourth action surface: when [actionContextResolver]
/// is supplied, the global handler evaluates the action's descriptor
/// visibility and enablement (`isActionInvocable` over the resolved
/// [NetcruxActionContext]) before invoking, so a chord bound to a hidden or
/// currently-disabled action is inert instead of a silent handler-side
/// no-op. The resolver is injected (rather than read from the
/// composition provider directly) because this widget lives in `core/`,
/// which must not depend on the feature layer that assembles the
/// context; the workspace shell passes
/// `() => ref.read(netcruxActionContextProvider)`.
class ShortcutManagerWidget extends ConsumerWidget {
  /// Creates a shortcut-manager scope rooted at [child].
  const ShortcutManagerWidget({
    required this.child,
    this.handlers = const {},
    this.actionContextResolver,
    super.key,
  });

  /// The subtree that should resolve shortcut activators through these
  /// bindings.
  final Widget child;

  /// Callbacks invoked when a matched shortcut fires. Actions not present
  /// here propagate to [Actions] widgets registered below.
  final Map<NetcruxAction, VoidCallback> handlers;

  /// Resolves the enablement context at keypress time. When null, no
  /// enablement gating is applied (test harnesses and embeddings that
  /// have no workspace context).
  final NetcruxActionContext Function()? actionContextResolver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(shortcutBindingsProvider);
    // Resolve collisions deterministically: when two actions share a chord, the
    // user's customized binding wins over the action that holds it by default
    // (shadowed losers are dropped), so a fresh remap actually fires. Previously
    // the map literal let whichever action came later in `bindings` iteration
    // order (NetcruxAction enum declaration order) silently win.
    final effective = resolveShortcutConflicts(bindings).effectiveBindings;
    return Shortcuts.manager(
      manager: _TextAwareShortcutManager(
        // The effective bindings plus the layout aliases (Cmd/Ctrl+`+` for
        // Zoom In and the numpad forms), which fire only while the action
        // keeps its default key.
        shortcuts: <ShortcutActivator, Intent>{
          for (final e in activatorsWithAliases(effective).entries)
            e.key: NetcruxActionIntent(e.value),
        },
      ),
      child: Actions(
        actions: <Type, Action<Intent>>{
          NetcruxActionIntent: CallbackAction<NetcruxActionIntent>(
            onInvoke: (intent) {
              // Gate the keyboard surface on the same descriptor
              // visibility and enablement the menu / palette / toolbar
              // render. Resolved
              // at keypress time so enablement is always current without
              // rebuilding the shortcut tree on every state change.
              final resolver = actionContextResolver;
              if (resolver != null &&
                  !isActionInvocable(intent.action, resolver())) {
                return null;
              }
              handlers[intent.action]?.call();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
