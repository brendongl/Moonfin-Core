import 'package:flutter/foundation.dart';

final homeRefreshBus = HomeRefreshBus();

class HomeRefreshBus extends ValueNotifier<int> {
  HomeRefreshBus() : super(0);

  bool _pendingRefresh = false;
  bool _newMediaBar = false;
  bool _newSectionsOnly = false;

  /// [newMediaBar] also loads a new set into the media bar, for a refresh the
  /// viewer asked for. [newSectionsOnly] loads only the sections Home has no
  /// rows for yet, for a change that only adds sections, such as Seerr
  /// signing in.
  void request({bool newMediaBar = false, bool newSectionsOnly = false}) {
    _newMediaBar = _newMediaBar || newMediaBar;
    _newSectionsOnly = newSectionsOnly;
    value = value + 1;
  }

  bool consumeNewMediaBar() {
    final newMediaBar = _newMediaBar;
    _newMediaBar = false;
    return newMediaBar;
  }

  bool consumeNewSectionsOnly() {
    final newSectionsOnly = _newSectionsOnly;
    _newSectionsOnly = false;
    return newSectionsOnly;
  }

  void requestAfterNavigation() {
    _pendingRefresh = true;
  }

  void requestNowOrAfterNavigation({bool newSectionsOnly = false}) {
    if (hasListeners) {
      request(newSectionsOnly: newSectionsOnly);
    } else {
      requestAfterNavigation();
    }
  }

  bool consumePending() {
    if (!_pendingRefresh) {
      return false;
    }
    _pendingRefresh = false;
    return true;
  }
}
