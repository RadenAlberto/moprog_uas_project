import 'package:flutter_test/flutter_test.dart';
import 'package:project_uts/SERVICES/learned_model.dart';

void main() {
  tearDown(() => LearnedModel.current = null);

  test('model valid dipasang dan dibaca', () {
    final ok = LearnedModel.install({
      'version': 'v1',
      'components': {
        'tone_color': {
          'source': 'trained:real',
          'table': {
            'warm': {'medium': {'red': 0.9}}
          }
        },
        'color_pair': {
          'source': 'prior:theory',
          'matrix': {'black': {'white': 0.8}}
        },
      },
    });
    expect(ok, isTrue);
    final m = LearnedModel.current!;
    expect(m.tone('warm', 'medium', 'red'), 0.9);
    expect(m.tone('cool', 'medium', 'red'), isNull);
    expect(m.pair('black', 'white'), 0.8);
    expect(m.sourceOf('tone_color'), 'trained:real');
  });

  test('model rusak ditolak tanpa crash', () {
    expect(LearnedModel.install('bukan model'), isFalse);
    expect(LearnedModel.install({'components': 5}), isFalse);
    expect(LearnedModel.current, isNull);
  });
}
