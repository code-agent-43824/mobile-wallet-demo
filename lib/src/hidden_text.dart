/// Whether [rune] changes what the eye reads in a text: control characters
/// other than line breaks and tabs, zero-width characters and bidirectional
/// overrides. A signing preview must not show such text as if it were plain.
bool hidesText(int rune) =>
    (rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d) ||
    (rune >= 0x7f && rune <= 0x9f) ||
    (rune >= 0x200b && rune <= 0x200f) ||
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2066 && rune <= 0x2069) ||
    rune == 0xfeff;

/// [text] with every character that [hidesText] spelled out as `\u{…}`, so
/// nothing in it is hidden from the reader.
String revealHiddenText(String text) {
  if (!text.runes.any(hidesText)) {
    return text;
  }
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    buffer.write(
      hidesText(rune)
          ? '\\u{${rune.toRadixString(16).toUpperCase()}}'
          : String.fromCharCode(rune),
    );
  }
  return buffer.toString();
}
