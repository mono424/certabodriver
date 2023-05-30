import 'dart:async';
import 'dart:typed_data';

import 'package:certabodriver/CertaboBoardType.dart';
import 'package:certabodriver/CertaboCommunicationClient.dart';
import 'package:certabodriver/CertaboConnectionType.dart';
import 'package:certabodriver/CertaboMessage.dart';
import 'package:certabodriver/CertaboProtocol.dart';
import 'package:certabodriver/IntegrityCheckType.dart';
import 'package:certabodriver/LEDPattern.dart';

export 'package:certabodriver/CertaboCommunicationClient.dart';
export 'package:certabodriver/LEDPattern.dart';
export 'package:certabodriver/CertaboBoardType.dart';
export 'package:certabodriver/CertaboConnectionType.dart';

class CertaboBoard {
  Duration redudantOutputMessageDelay = Duration(milliseconds: 100);
  int _redundantOutputMessages = 2;
  int _incoomingIntegrityChecks = 2;
  IntegrityCheckType incoomingIntegrityCheckType = IntegrityCheckType.board;
  List<List<int>> pieceIdWhitelist = [];

  void set redundantOutputMessages(value) {
    if (value < 0) throw Exception("To small value, atleast 0");
    _redundantOutputMessages = value;
  }

  void set incoomingIntegrityChecks(value) {
    if (value < 0) throw Exception("To small value, atleast 0");
    _incoomingIntegrityChecks = value;
  }

  int get redundantOutputMessages {
    return _redundantOutputMessages;
  }

  int get incoomingIntegrityChecks {
    return _incoomingIntegrityChecks;
  }

    
  late StreamController<CertaboMessage> _inputStreamController;
  late StreamController _boardUpdateStreamController;
  late Stream<CertaboMessage> _inputStream;
  late Stream<Map<String, List<int>>> _boardUpdateStream;

  CertaboCommunicationClient? _client;
  List<int> _buffer = [];
  CertaboBoardType _type = CertaboBoardType.Unknown;

  Map<String, List<int>?> _currBoard = Map.fromEntries(CertaboProtocol.squares.map((e) => MapEntry(e, CertaboProtocol.emptyFieldId)));

  CertaboBoardType get type {
    return _type;
  }

  Map<String, List<int>?> get currBoard {
    return _currBoard;
  }

  List<Map<String, List<int>>> _lastBoards = [];

  CertaboBoard() {
    _inputStreamController = new StreamController<CertaboMessage>();
    _boardUpdateStreamController = new StreamController<Map<String, List<int>>>();
    _inputStream = _inputStreamController.stream.asBroadcastStream();
    _boardUpdateStream = _boardUpdateStreamController.stream.asBroadcastStream() as Stream<Map<String, List<int>>>;
  }

  Future<void> init(CertaboCommunicationClient client) async {
    _client = client;
    _client!.receiveStream.listen(_handleInputStream);
    getInputStream().map(createBoardMap).listen(_newBoardState);
    await getInputStream().first;
  }

  void _newBoardState(Map<String, List<int>> state) {
    // PieceId Whitelist
    if (_type != CertaboBoardType.Tabutronic && pieceIdWhitelist.length > 0) {
      state = state.map((key, value) {
        if (pieceIdWhitelist.any((e) => CertaboProtocol.equalId(e, value))) {
          return MapEntry(key, value);
        }
        return MapEntry(key, CertaboProtocol.emptyFieldId);
      });
    }

    // Integrity Checks
    int messagesNeeded = 1 + _incoomingIntegrityChecks;
    _lastBoards.insert(0, state);
    if (_lastBoards.length < messagesNeeded) return;

    _lastBoards = _lastBoards.sublist(0, messagesNeeded);

    if (incoomingIntegrityCheckType == IntegrityCheckType.cell) {
      _currBoard = _currBoard.map((key, value) {
        List<int>? potentialNewValue = _lastBoards.first[key];
        if (_lastBoards.every((e) => CertaboProtocol.equalId(e[key], potentialNewValue))) {
          return MapEntry(key, potentialNewValue);
        }
        return MapEntry(key, value);
      });
    } else {
      if (checkStatesAreEqual(_lastBoards)) {
        _currBoard = _lastBoards.first;
      }
    }

    _boardUpdateStreamController.add(_currBoard);
  }

  bool checkStatesAreEqual(List<Map<String, List<int>>> states) {
    Map<String, List<int>> first = _lastBoards.first;
    for (var entry in first.entries) {
      if (!states.every((e) => CertaboProtocol.equalId(e[entry.key], entry.value))) {
        return false;
      }
    }
    return true;
  }

  bool _isWorking = false;
  void _handleInputStream(Uint8List rawChunk) {
    List<int> chunk = rawChunk.toList();

    _buffer.addAll(chunk);

    if (_isWorking == true) return;
    while(_buffer.length >= 384) {
      CertaboCommunicationClient? client = _client;
      if (client == null) return;
      _isWorking = true;
      try {
        _buffer = skipToNextStart(0, _buffer);

        // Detect board type
        if (_type == CertaboBoardType.Unknown) {
          switch (client.connectionType) {
            case CertaboConnectionType.USB:
              _type = CertaboMessageUSB.detect(_buffer);
              break;
            case CertaboConnectionType.BT:
              _type = CertaboMessageBT.detect(_buffer);
              break;
            default:
              throw Exception("Unknown board type");
          }
        }

        if (_type == CertaboBoardType.Unknown) {
          _buffer = skipToNextStart(1, _buffer);
          continue;
        }

        // Parse message
        CertaboMessage message;
        switch (client.connectionType) {
          case CertaboConnectionType.USB:
            message = CertaboMessageUSB.parse(_type, _buffer);
            break;
          case CertaboConnectionType.BT:
            message = CertaboMessageBT.parse(_type, _buffer);
            break;
          default:
            throw Exception("Unknown board type");
        }

        _inputStreamController.add(message);
        _buffer.removeRange(0, message.length);
        //print("Received valid message");
      } on CertaboInvalidMessageException catch (e) {
        _buffer = skipToNextStart(0, _buffer);
        _inputStreamController.addError(e);
      } on CertaboInvalidMessageLengthException catch (e) {
        _buffer = skipToNextStart(1, _buffer);
        _inputStreamController.addError(e);
      } on CertaboMessageTooShortException catch (_) {
        //_inputStreamController.addError(e);
      } catch (err) {
        //print("Unknown parse-error: " + err.toString());
        _inputStreamController.addError(err);
      }
    }
    _isWorking = false;
  }

  List<int> skipToNextStart(int start, List<int> buffer) {
    int index = start;
    for (; index < buffer.length; index++) {
      if ((buffer[index] & 127) == 58) break;
    }
    if (index == buffer.length) return [];
    return buffer.sublist(index, buffer.length - index);
  }

  Stream<CertaboMessage> getInputStream() {
    return _inputStream;
  }

  Stream<Map<String, List<int>>>? getBoardUpdateStream() {
    return _boardUpdateStream;
  }

  Map<String, List<int>> createBoardMap(CertaboMessage message) {
    Map<String, List<int>> map = Map<String, List<int>>();
    for (var i = 0; i < message.items.length; i++) {
      map[CertaboProtocol.squares[i]] = message.items[i];
    }
    return map;
  }

  Future<void> setLEDs(LEDPattern pattern) async {
    await _send(Uint8List.fromList(pattern.pattern));
  }

  Future<void> _send(Uint8List message) async {
    CertaboCommunicationClient? client = _client;
    if (client == null) return;

    await client.send(message);
    for (var i = 0; i < _redundantOutputMessages; i++) {
      await Future.delayed(redudantOutputMessageDelay);
      await client.send(message);
    }
  }
  
}
