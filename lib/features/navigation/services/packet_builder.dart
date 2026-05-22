import 'dart:typed_data';

// Turn-by-turn BLE packet format (9 bytes):
//
//   [0]      'T'
//   [1]      'N'
//   [2]      current turn sign + 10  (uint8)
//   [3..4]   distance to turn  (uint16 BE, ×10 m units → max 655 350 m = 655 km)
//   [5..6]   remaining distance (uint16 BE, km units → max 65 535 km)
//   [7]      next turn sign + 10  (uint8)
//   [8]      speed km/h  (uint8)
//
// Encoding rationale:
//   ×10 m for turn distance: handles up to 655 km before any turn (long highways)
//   km for remaining: handles up to 65 535 km total trip

class PacketBuilder {
  static Uint8List buildTurnPacket({
    required int currentSign,
    required int distanceToTurnMeters,
    required int remainingDistanceMeters,
    required int nextSign,
    required double speedKmh,
  }) {
    final buf = ByteData(9);
    buf.setUint8(0, 0x54); // 'T'
    buf.setUint8(1, 0x4E); // 'N'
    buf.setUint8(2, (currentSign + 10).clamp(0, 255));
    // ÷10 so uint16 covers up to 655 350 m
    buf.setUint16(3, (distanceToTurnMeters ~/ 10).clamp(0, 65535), Endian.big);
    // ÷1000 → km, uint16 covers up to 65 535 km
    buf.setUint16(
        5, (remainingDistanceMeters ~/ 1000).clamp(0, 65535), Endian.big);
    buf.setUint8(7, (nextSign + 10).clamp(0, 255));
    buf.setUint8(8, speedKmh.round().clamp(0, 255));
    return buf.buffer.asUint8List();
  }
}
