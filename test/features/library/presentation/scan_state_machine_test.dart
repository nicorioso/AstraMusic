import 'package:astramusic/features/library/presentation/scan_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('solo inicia desde idle y no reinicia mientras cancela', () {
    final machine = ScanStateMachine();

    expect(machine.start(), isTrue);
    expect(machine.phase, ScanPhase.scanning);
    expect(machine.start(), isFalse);

    expect(machine.requestCancellation(), isTrue);
    expect(machine.phase, ScanPhase.cancelling);
    expect(machine.start(), isFalse);
    expect(machine.requestCancellation(), isFalse);

    machine.finish();
    expect(machine.phase, ScanPhase.idle);
    expect(machine.start(), isTrue);
  });
}
