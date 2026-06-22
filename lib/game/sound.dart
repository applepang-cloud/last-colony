import 'package:flame_audio/flame_audio.dart';

/// Thin wrapper over flame_audio with throttling + a global mute.
///
/// Stays inert until [init] succeeds, so headless tests (which never call
/// [init]) make every play a no-op.
class SoundFx {
  bool enabled = true;
  bool _ready = false;
  double _shootCd = 0;
  double _boomCd = 0;

  static const _files = [
    'shoot.wav',
    'explosion.wav',
    'build.wav',
    'select.wav',
    'win.wav',
    'lose.wav',
  ];

  Future<void> init() async {
    if (_ready) return;
    try {
      await FlameAudio.audioCache.loadAll(_files);
      _ready = true;
    } catch (_) {
      _ready = false; // audio unavailable (e.g. headless) — silently disable
    }
  }

  void tick(double dt) {
    if (_shootCd > 0) _shootCd -= dt;
    if (_boomCd > 0) _boomCd -= dt;
  }

  void _play(String file, double volume) {
    if (!enabled || !_ready) return;
    FlameAudio.play(file, volume: volume);
  }

  void shoot() {
    if (_shootCd > 0) return;
    _shootCd = 0.07;
    _play('shoot.wav', 0.22);
  }

  void explosion() {
    if (_boomCd > 0) return;
    _boomCd = 0.05;
    _play('explosion.wav', 0.5);
  }

  void build() => _play('build.wav', 0.6);
  void select() => _play('select.wav', 0.4);
  void win() => _play('win.wav', 0.7);
  void lose() => _play('lose.wav', 0.7);
}
