import 'dart:convert';

import 'package:certabodriver/CertaboBoard.dart';
import 'package:certabodriver/CertaboBoardType.dart';
import 'package:certabodriver/CertaboProtocol.dart';

abstract class CertaboMessage {
  bool _pieceDetection = false;
  List<List<int>> _items = [];
  int _length = 0;

  bool get PieceDetection {
    return _pieceDetection;
  }
  
  List<List<int>> get items {
    return _items;
  }

  int get length {
    return _length;
  }

  static String parseString(List<int> message) {
    List<int> normalizedMessage = message.map((i) => (i & 127)).toList();
    String decoded = ascii.decode(normalizedMessage).split("\n")[0];
    return decoded;
  }

  static CertaboBoardType detect(String message) {
    final len =  message.trim().split(" ").length;
    if (len == 8) {
      return CertaboBoardType.Tabutronic;
    } else if (len == 320) {
      return CertaboBoardType.Certabo;
    } else {
      return CertaboBoardType.Unknown;
    }
  }

  void parse(CertaboBoardType type, String message) {
    _length = message.length; // because ascii is used 1char == 1byte

    // Split and check if the length is right
    List<String> decodedItems = message.trim().split(" ").toList();

    if (decodedItems.isEmpty) {
      throw CertaboInvalidMessageLengthException(ascii.encode(message));
    }

    if (type == CertaboBoardType.Tabutronic) {
      parseTabutronic(decodedItems);
    } else if (type == CertaboBoardType.Certabo) {
      parseCertabo(decodedItems);
    } else {
      throw CertaboInvalidMessageLengthException(ascii.encode(message));
    }
  }

  void parseCertabo(List<String> items) {
    if (items.length != 320) throw CertaboInvalidMessageLengthException(ascii.encode(items.join(" ")));

    for (var i = 0; i < items.length; i++) {
      if (i % 5 == 0)
        _items.add([int.parse(items[i])]);
      else 
        _items.last.add(int.parse(items[i]));
    }
  }

  void parseTabutronic(List<String> items) {
    if (items.length != 8) throw CertaboInvalidMessageLengthException(ascii.encode(items.join(" ")));

    for (var i = 0; i < items.length; i++) {
      int rowNum = int.parse(items[i]);
      List<List<int>> row = [];
      for (var j = 0; j < 8; j++) {
        List<int> piece = [...CertaboProtocol.emptyFieldId];
        piece[piece.length - 1] = rowNum & 1;
        row.add(piece);
        rowNum = rowNum >> 1;
      }
      _items.addAll(row.reversed.toList());
    }
  }
}

class CertaboMessageBT extends CertaboMessage {

  CertaboMessageBT.parse(CertaboBoardType type, List<int> message) {
    String decoded = CertaboMessage.parseString(message);
    parse(type, decoded);
  }

  static CertaboBoardType detect(List<int> message) {
    String decoded = CertaboMessage.parseString(message);
    return CertaboMessage.detect(decoded);
  }

}

class CertaboMessageUSB extends CertaboMessage {

  static String getLastMessageBySep(String decoded) {
    final sep = decoded.lastIndexOf(":");
    if (sep == -1) {
      throw CertaboInvalidMessageException(ascii.encode(decoded));
    }
    decoded = decoded.substring(sep + 1);
    return decoded;
  }

  CertaboMessageUSB.parse(CertaboBoardType type, List<int> message) {
    String decoded = CertaboMessage.parseString(message);
    String lastMessage = getLastMessageBySep(decoded);
    parse(type, lastMessage);
  }

  static CertaboBoardType detect(List<int> message) {
    String decoded = CertaboMessage.parseString(message);
    String lastMessage = getLastMessageBySep(decoded);
    return CertaboMessage.detect(lastMessage);
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