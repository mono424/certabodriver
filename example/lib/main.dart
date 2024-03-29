import 'package:certabodriver/CertaboBoard.dart';
import 'package:certabodriver/CertaboCommunicationClient.dart';
import 'package:certabodriver/LEDPattern.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(key: Key("home")),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({required Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  CertaboBoard? connectedBoard;

  void connect() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    print(devices);
    if (devices.length == 0) {
      return;
    }

    List<UsbDevice> boardDevices = devices.where((d) => d.vid == 4292).toList();
    UsbPort? usbDevice = await boardDevices[0].create();
    if (usbDevice == null) return;
    await usbDevice.open();

    await usbDevice.setDTR(true);
	  await usbDevice.setRTS(true);

	  usbDevice.setPortParameters(38400, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    CertaboCommunicationClient client = CertaboCommunicationClient(CertaboConnectionType.USB, usbDevice.write);
    usbDevice.inputStream!.listen(client.handleReceive);
    
    if (boardDevices.length > 0) {
      // connect to board and initialize
      CertaboBoard nBoard = new CertaboBoard();
      await nBoard.init(client);
      print("CertaboBoard connected");

      // set connected board
      setState(() {
        connectedBoard = nBoard;
      });
    }
  }

  Map<String, List<int>>? lastData;

  LEDPattern ledpattern = LEDPattern();

  void toggleLed(String square) {
    ledpattern.setSquare(square, !ledpattern.getSquare(square));
    connectedBoard!.setLEDs(ledpattern);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: Text("certabodriver example"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(child: TextButton(
            child: Text(connectedBoard == null ? "Try to connect to board" : "Connected"),
            onPressed: connectedBoard == null ? connect : null,
          )),
          Center( child: StreamBuilder(
            stream: connectedBoard?.getBoardUpdateStream(),
            builder: (context, AsyncSnapshot<Map<String, List<int>>> snapshot) {
              if (!snapshot.hasData && lastData == null) return Text("- no data -");

              Map<String, List<int>>? fieldUpdate = snapshot.data ?? lastData;
              lastData = fieldUpdate;
              List<Widget> rows = [];
              
              for (var i = 0; i < 8; i++) {
                List<Widget> cells = [];
                for (var j = 0; j < 8; j++) {
                    MapEntry<String, List<int>> entry = fieldUpdate!.entries.toList()[i * 8 + j];
                    cells.add(
                      TextButton(
                        onPressed: () => toggleLed(entry.key),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size(width / 8 - 4, width / 8 - 4),
                          alignment: Alignment.centerLeft
                        ),
                        child: Container(
                          padding: EdgeInsets.only(bottom: 2),
                          width: width / 8 - 4,
                          height: width / 8 - 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: ledpattern.getSquare(entry.key) ? Colors.blueAccent : Colors.black54,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(entry.key, style: TextStyle(color: Colors.white)),
                                Text("[" + entry.value.join(", ") + "]", style: TextStyle(color: Colors.white, fontSize: 8)),
                              ],
                            )
                          ),
                        ),
                      )
                    );
                }
                rows.add(Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: cells,
                ));
              }

              return Column(
                children: rows,
              );
            }
          )),
        ],
      ),
    );
  }
}
