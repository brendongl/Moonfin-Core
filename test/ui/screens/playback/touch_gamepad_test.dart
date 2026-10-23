import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/playback/touch_gamepad.dart';
import 'package:moonfin/util/core_input_descriptors.dart';
import 'package:moonfin/util/touch_gamepad_layout.dart';

const _size = Size(844, 390);
const _picture = Rect.fromLTWH(162, 0, 520, 390);

class _Log {
  final masks = <int>[];
  final sticks = <(Offset, Offset)>[];
  int menu = 0;
  int get mask => masks.isEmpty ? 0 : masks.last;
}

Future<_Log> _pump(
  WidgetTester tester,
  String core, {
  int analogPorts = 0,
}) async {
  tester.view.physicalSize = _size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final log = _Log();
  await tester.pumpWidget(
    MaterialApp(
      home: TouchGamepad(
        core: core,
        size: _size,
        safe: EdgeInsets.zero,
        pictureRect: _picture,
        portrait: false,
        inputDescriptors: CoreInputDescriptors.empty,
        analogPorts: analogPorts,
        padType: 1,
        onMask: log.masks.add,
        onSticks: (l, r) => log.sticks.add((l, r)),
        onPointer: (_, _, _) {},
        onMenu: () => log.menu++,
      ),
    ),
  );
  return log;
}

Offset _center(String core, String label, {int analogPorts = 0}) =>
    placeTouchPad(
      touchPadLayoutFor(core, analogPorts: analogPorts),
      _size,
      EdgeInsets.zero,
      _picture,
      portrait: false,
    ).firstWhere((p) => p.control.label == label).center;

void main() {
  testWidgets('the d-pad follows a sliding thumb and lets go on lift', (
    tester,
  ) async {
    final log = await _pump(tester, 'snes');
    final dpad = _center('snes', 'D-pad');

    final g = await tester.startGesture(dpad + const Offset(45, 0));
    expect(log.mask, 1 << RetroPadId.right);
    await g.moveTo(dpad + const Offset(40, -40));
    expect(log.mask, (1 << RetroPadId.right) | (1 << RetroPadId.up));
    await g.moveTo(dpad + const Offset(0, -45));
    expect(log.mask, 1 << RetroPadId.up);
    await g.up();
    expect(log.mask, 0);
  });

  testWidgets('two fingers hold two controls at once', (tester) async {
    final log = await _pump(tester, 'snes');
    final dpad = _center('snes', 'D-pad');
    final a = _center('snes', 'A');

    final thumb = await tester.startGesture(dpad + const Offset(-45, 0));
    final finger = await tester.startGesture(a);
    expect(log.mask, (1 << RetroPadId.left) | (1 << RetroPadId.a));
    await finger.moveTo(_center('snes', 'B'));
    expect(log.mask, (1 << RetroPadId.left) | (1 << RetroPadId.b));
    await finger.up();
    expect(log.mask, 1 << RetroPadId.left);
    await thumb.up();
    expect(log.mask, 0);
  });

  testWidgets('a stick is analog where the core reads one, else 8-way', (
    tester,
  ) async {
    final analog = await _pump(tester, 'n64', analogPorts: 1);
    final stick = _center('n64', 'Control stick', analogPorts: 1);
    final g = await tester.startGesture(stick + const Offset(60, 0));
    expect(analog.sticks.last.$1.dx, closeTo(1, 0.01));
    expect(analog.mask, 0);
    await g.up();
    expect(analog.sticks.last, (Offset.zero, Offset.zero));

    final digital = await _pump(tester, 'n64');
    final g2 = await tester.startGesture(
      _center('n64', 'Control stick') + const Offset(60, 0),
    );
    expect(digital.mask, 1 << RetroPadId.right);
    expect(digital.sticks, isEmpty);
    await g2.up();
  });

  testWidgets('the menu button opens the menu', (tester) async {
    final log = await _pump(tester, 'nes');
    await tester.tapAt(_center('nes', 'Menu'));
    expect(log.menu, 1);
  });
}
