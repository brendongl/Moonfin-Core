import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:moonfin/sipflix/sipflix_log.dart';

class _CapturingOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

// `Logger()` uses DevelopmentFilter, which makes its decision inside an
// `assert`. Release builds strip asserts, so that filter always answers "no"
// and every Sipflix diagnostic went missing on exactly the boxes worth
// diagnosing — a 2026-08-21 investigation into a bogus "1.3 Mbps" preflight
// reading found no instrumentation surviving on the device at all.
void main() {
  test('sipflixLogger actually emits at info and above', () {
    final out = _CapturingOutput();
    final log = sipflixLogger(output: out);

    log.i('probe result');
    log.w('probe warning');

    expect(out.lines.join('\n'), contains('probe result'));
    expect(out.lines.join('\n'), contains('probe warning'));
  });

  test('it uses a filter whose verdict does not depend on asserts', () {
    final production = ProductionFilter()..level = Level.info;
    expect(production.shouldLog(LogEvent(Level.info, 'x')), isTrue);

    // The trap, documented: DevelopmentFilter only says yes while asserts run,
    // so this assertion passes in debug and would have failed on the fleet.
    var assertsOn = false;
    assert(() {
      assertsOn = true;
      return true;
    }());
    final dev = DevelopmentFilter()..level = Level.info;
    expect(dev.shouldLog(LogEvent(Level.info, 'x')), equals(assertsOn));
  });

  test('below-level events are still dropped', () {
    final out = _CapturingOutput();
    sipflixLogger(level: Level.warning, output: out).i('chatter');
    expect(out.lines, isEmpty);
  });
}
