import 'dart:convert';

class CertaboMessage {

  List<List<int>> _items = [];
  int _length = 0;

  CertaboMessage.parse(List<int> message) {
    if (message.length < 384) throw CertaboMessageTooShortException(message);

    // Get rid of parity bit
    List<int> normalizedMessage = message.map((i) => (i & 127)).toList();
    String decoded = ascii.decode(normalizedMessage).split("\n")[0];

    // Check if starts with ":"
    if (!decoded.startsWith(":")) {
      throw CertaboInvalidMessageException(ascii.encode(decoded));
    }
    decoded = decoded.substring(1);

    // Split and check if the length is right
    List<String> decodedItems = decoded.trim().split(" ").toList();
    if (decodedItems.length != 320) {
      throw CertaboInvalidMessageLengthException(ascii.encode(decoded));
    }
    for (var i = 0; i < decodedItems.length; i++) {
      if (i % 5 == 0)
        _items.add([int.parse(decodedItems[i])]);
      else 
        _items.last.add(int.parse(decodedItems[i]));
    }
    _length = decoded.length; // because ascii is used 1char == 1byte
  }

  List<List<int>> get items {
    return _items;
  }

  int get length {
    return _length;
  }

}

abstract class CertaboMessageException implements Exception {
  final List<int> buffer;
  CertaboMessageException(this.buffer);
}

class CertaboMessageTooShortException extends CertaboMessageException {
  CertaboMessageTooShortException(List<int> buffer) : super(buffer);
}

class CertaboInvalidMessageLengthException extends CertaboMessageException {
  CertaboInvalidMessageLengthException(List<int> buffer) : super(buffer);
}

class CertaboInvalidMessageException extends CertaboMessageException {
  CertaboInvalidMessageException(List<int> buffer) : super(buffer);
}