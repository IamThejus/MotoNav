import 'dart:typed_data';

// Turn-by-turn BLE packet format (11 bytes):
//
//   [0]      'T'
//   [1]      'N'
//   [2]      current turn sign + 10  (uint8)
//   [3..4]   distance to turn  (uint16 BE, ×10 m → max 655 km)
//   [5..6]   remaining distance (uint16 BE, km → max 65 535 km)
//   [7]      next turn sign + 10  (uint8)
//   [8]      speed km/h  (uint8)
//   [9..10]  ETA minutes (uint16 BE → max 65 535 min ≈ 45 days)

class PacketBuilder {
  static Uint8List buildTurnPacket({
    required int currentSign,
    required int distanceToTurnMeters,
    required int remainingDistanceMeters,
    required int nextSign,
    required double speedKmh,
    required int etaMinutes,
  }) {
    final buf = ByteData(11);
    buf.setUint8(0, 0x54); // 'T'
    buf.setUint8(1, 0x4E); // 'N'
    buf.setUint8(2, (currentSign + 10).clamp(0, 255));
    buf.setUint16(3, (distanceToTurnMeters ~/ 10).clamp(0, 65535), Endian.big);
    buf.setUint16(5, (remainingDistanceMeters ~/ 1000).clamp(0, 65535), Endian.big);
    buf.setUint8(7, (nextSign + 10).clamp(0, 255));
    buf.setUint8(8, speedKmh.round().clamp(0, 255));
    buf.setUint16(9, etaMinutes.clamp(0, 65535), Endian.big);
    return buf.buffer.asUint8List();
  }
}
