import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generates tiny procedural 16-bit PCM mono WAV sound effects into
/// assets/audio/ so the game ships with no external audio dependencies.
const int sampleRate = 22050;

void main() {
  final dir = Directory('assets/audio');
  dir.createSync(recursive: true);

  _write('shoot.wav', _shoot());
  _write('explosion.wav', _explosion());
  _write('build.wav', _build());
  _write('select.wav', _select());
  _write('win.wav', _arp([523.25, 659.25, 783.99, 1046.5], 0.12));
  _write('lose.wav', _arp([392.0, 311.13, 261.63, 196.0], 0.16));

  stdout.writeln('Audio assets generated in assets/audio/');
}

void _write(String name, List<double> samples) {
  final bytes = _encodeWav(samples);
  File('assets/audio/$name').writeAsBytesSync(bytes);
  stdout.writeln('  wrote $name (${samples.length} samples)');
}

// --- effect synths --------------------------------------------------------

List<double> _shoot() {
  final n = (sampleRate * 0.12).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * 28);
    final freq = 620 - 360 * (i / n); // descending zap
    final sq = math.sin(2 * math.pi * freq * t) >= 0 ? 1.0 : -1.0;
    out[i] = sq * env * 0.35;
  }
  return out;
}

List<double> _explosion() {
  final n = (sampleRate * 0.55).round();
  final out = List<double>.filled(n, 0);
  final rnd = math.Random(42);
  var low = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * 7);
    final white = rnd.nextDouble() * 2 - 1;
    low = low * 0.85 + white * 0.15; // crude low-pass for a rumble
    out[i] = (low * 0.8 + white * 0.2) * env * 0.7;
  }
  return out;
}

List<double> _build() {
  return _seq([
    _tone(523.25, 0.1, 0.3),
    _tone(783.99, 0.14, 0.3),
  ]);
}

List<double> _select() {
  final n = (sampleRate * 0.05).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * 60);
    out[i] = math.sin(2 * math.pi * 1100 * t) * env * 0.25;
  }
  return out;
}

List<double> _arp(List<double> freqs, double each) {
  return _seq([for (final f in freqs) _tone(f, each, 0.3)]);
}

List<double> _tone(double freq, double dur, double amp) {
  final n = (sampleRate * dur).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = (1 - (i / n)) * 0.6 + 0.4; // gentle fade
    out[i] = math.sin(2 * math.pi * freq * t) * env * amp;
  }
  return out;
}

List<double> _seq(List<List<double>> parts) {
  final out = <double>[];
  for (final p in parts) {
    out.addAll(p);
  }
  return out;
}

// --- WAV encoding ---------------------------------------------------------

Uint8List _encodeWav(List<double> samples) {
  final dataLen = samples.length * 2;
  final buffer = BytesBuilder();
  void writeStr(String s) => buffer.add(s.codeUnits);
  void writeU32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    buffer.add(b.buffer.asUint8List());
  }

  void writeU16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    buffer.add(b.buffer.asUint8List());
  }

  writeStr('RIFF');
  writeU32(36 + dataLen);
  writeStr('WAVE');
  writeStr('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(1); // mono
  writeU32(sampleRate);
  writeU32(sampleRate * 2); // byte rate
  writeU16(2); // block align
  writeU16(16); // bits per sample
  writeStr('data');
  writeU32(dataLen);

  final data = ByteData(dataLen);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  buffer.add(data.buffer.asUint8List());
  return buffer.toBytes();
}
