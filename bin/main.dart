// Copyright (c) 2017, pixel. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:simbackend/simbackend.dart' as simbackend;
import 'package:csv/csv.dart';

class Device {
  String id;
  String name;
  double sus;
  toJson() => {
    "id": id,
    "name": name,
    "sus": sus,
    "disabled": disabled,
  };
  
  bool pairing = false;
  bool infected = false;
  bool disabled = false;
  Set<Device> paired = new Set<Device>();
  
  double lat;
  double lgn;
}

class Packet {
  Packet();
  Packet.tpe(this.type, this.size, this.sus);
  double sus;
  int type;
  double size;
}

class Transaction {
  Transaction(this.device, this.to);
  Device device;
  Device to;
  List<Packet> packets = [];
}

Future main() async {
  var requestServer =
  await HttpServer.bind(InternetAddress.ANY_IP_V4, 80);
  print('listening on localhost, port ${requestServer.port}');
  
  List<WebSocket> clients = [];
  List<Device> devices = [
    new Device()..id = "6420"..name = "headphones 1"..sus = 0.0,
    new Device()..id = "6900"..name = "headphones 2"..sus = 0.0,
    new Device()..id = "6675"..name = "headphones 3"..sus = 0.0,
    new Device()..id = "6947"..name = "headphones 4"..sus = 0.0,
    new Device()..id = "6669"..name = "headphones 5"..sus = 0.0,
  ];
  
  Map<Device, Map<Device, Transaction>> transactions = {};
  
  void sendClients(dynamic data) {
    clients.forEach((w) => w.add(JSON.encode(data)));
  }
  
  void updateSus(Device d) {
    sendClients({
      "type": "sus",
      "id": d.id,
      "sus": d.sus,
    });
  }
  
  void sendPacket(Device from, Device to, Packet p) {
    var transaction = transactions.putIfAbsent(from, () => {}).putIfAbsent(to, () => new Transaction(from, to));
    transaction.packets.add(p);
    p.sus = max(p.sus, 0.2) * from.sus;
    sendClients({
      "type": "packet",
      "ptype": p.type,
      "sus": p.sus,
      "from": from.id,
      "to": to.id,
      "size": p.size,
    });
    to.sus += from.sus / 35;
    to.sus *= 1 + (from.sus / 10);
    to.sus = to.sus.clamp(0.0, 1.0);
    from.sus *= 2;
    from.sus = from.sus.clamp(0.0, 1.0);
    updateSus(from);
    updateSus(to);
  }
  
  void newDevice(Device d) {
    devices.add(d);
    sendClients({
      "type": "create",
      "id": d.id,
      "name": d.name,
      "sus": d.sus,
    });
  }

  void killDevice(Device d) {
    devices.remove(d);
    sendClients({
      "type": "kill",
      "id": d.id,
    });
    d.paired.forEach((pw) => pw.paired.remove(d));
  }

  void disableDevice(Device d) {
    d.paired.forEach((pw) => pw.paired.remove(d));
    d.paired = new Set();
    if (!d.infected) {
      d.sus = 0.0;
      updateSus(d);
    }
    sendClients({
      "type": "disable",
      "id": d.id,
    });
    d.paired.forEach((pw) => pw.paired.remove(d));
  }

  void exploitDevice(Device d, List<String> infecting) {
    sendClients({
      "type": "infect",
      "id": d.id,
      "infecting": infecting.toList(),
    });
  }
  
  int protectionLevel = 0;
  
  void revert() {
    devices.forEach((dv) {
      dv.infected = false;
      dv.sus = 0.0;
      dv.disabled = false;
      dv.paired = new Set();
      dv.pairing = false;
      dv.lat = null;
      dv.lgn = null;
    });
    protectionLevel = 0;
    if (devices.where((dv) => dv.id == "DEAD").isNotEmpty) {
      killDevice(devices.firstWhere((dv) => dv.id == "DEAD"));
    }
    sendClients({
      "type": "revert",
    });
  }
  
  Future propogateDisable(Device d) async {
    d.disabled = true;
    disableDevice(d);
    
    for (var dv in devices.where((dv) => dv != d && !dv.disabled)) {
      await new Future.delayed(const Duration(milliseconds: 100));
      dv.disabled = true;
      sendPacket(d, dv, new Packet.tpe(0, 5.0, 1.0));
      new Future.delayed(const Duration(milliseconds: 1000)).then((x) {
        disableDevice(dv);
      });
    }
  }
  
  Future infectDevice(Device from, Device to, int tier) async {
    to.infected = true;
    sendPacket(from, to, new Packet.tpe(0, 5.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 2000));
    if (!to.infected) return null;
    sendPacket(to, from, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 2000));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 2000));
    if (!to.infected) return null;
    sendPacket(to, from, new Packet.tpe(0, 2.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 2000));
    if (!to.infected) return null;

    if ((protectionLevel > 0 && tier == 1) || (protectionLevel > 1 && tier == 0)) {
      to.infected = false;
      return propogateDisable(to);
    }
    
    sendPacket(from, to, new Packet.tpe(0, 20.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 20.0, 1.0));
    
    await new Future.delayed(const Duration(milliseconds: 1000));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    await new Future.delayed(const Duration(milliseconds: 200));
    if (!to.infected) return null;
    sendPacket(from, to, new Packet.tpe(0, 10.0, 1.0));
    
    await new Future.delayed(const Duration(milliseconds: 2000));
    if (!to.infected) return null;
    sendPacket(to, from, new Packet.tpe(0, 2.0, 1.0));
    
    
    var infecting = (devices.where((dv) => !dv.infected).toList()..shuffle()).take(2).toList();
    exploitDevice(to, infecting.map((dv) => dv.id));
    infecting.forEach((dv) => infectDevice(to, dv, tier + 1));
  }
  
  /*(() async {
    while (true) {
      await new Future.delayed(const Duration(milliseconds: 500));
      if (devices.length > 1) {
        var from = devices[new Random().nextInt(devices.length)];
        Device to;
        do {
          to = devices[new Random().nextInt(devices.length)];
        } while (from == to);
        var p = new Packet();
        p.size = new Random().nextDouble() * 15 + 5;
        p.type = 0;
        p.sus = 0.0;
        sendPacket(from, to, p);
      }
    }
  })();*/
  
  double vecDistance(double ax, double ay, double bx, double by) {
    return sqrt(pow(ax - bx, 2) + pow(ay - by, 2));
  }
  
  Map<String, HttpRequest> pendingReqs = {};
  
  try {
    await for (HttpRequest req in requestServer) {
      try {
        if (req.uri.path == "/ws") {
          var socket = await WebSocketTransformer.upgrade(req);
          clients.add(socket);
  
          String nid;
          var rand = new Random();
          do {
            nid = rand.nextInt(0xFFFF).toRadixString(16).padLeft(4, "0").toUpperCase();
          } while (devices
            .where((d) => d.id == nid)
            .isNotEmpty);
  
          socket.add(JSON.encode({
            "type": "init",
            "devices": devices,
            "id": nid,
          }));
  
          print("sent ${devices.length} devices");
  
          var d = new Device();
          d.id = nid;
          d.name = "device ${devices.length}";
          d.sus = 0.0;
          newDevice(d);
  
          socket.listen((msg) async {
            var data = JSON.decode(msg);
            if (data["type"] == "pair") {
              var pd = devices.firstWhere((pd) => pd.id == data["id"]);
              if (pd.pairing || d.paired.contains(pd)) return;
              d.pairing = true;
              pd.pairing = true;
              sendPacket(d, pd, new Packet.tpe(0, 5.0, 0.0));
              await new Future.delayed(const Duration(milliseconds: 1000));
              if (!d.pairing) return;
              sendPacket(pd, d, new Packet.tpe(0, 10.0, 0.0));
              await new Future.delayed(const Duration(milliseconds: 1000));
              if (!d.pairing) return;
              sendPacket(d, pd, new Packet.tpe(0, 10.0, 0.0));
              await new Future.delayed(const Duration(milliseconds: 1000));
              if (!d.pairing) return;
              sendPacket(pd, d, new Packet.tpe(0, 20.0, 0.0));
              d.pairing = false;
              pd.pairing = false;
              d.paired.add(pd);
              pd.paired.add(d);
              while (true) {
                await new Future.delayed(new Duration(milliseconds: new Random().nextInt(3000) + 1000));
                if (!d.paired.contains(pd)) return;
                for (int i = 0; i < new Random().nextInt(30) + 5; i++) {
                  sendPacket(d, pd, new Packet.tpe(0, 10.0, 0.0));
                  await new Future.delayed(new Duration(milliseconds: 100));
                  if (!d.paired.contains(pd)) return;
                }
              }
            } else if (data["type"] == "attack") {
              if (devices
                .where((dv) => dv.id == "DEAD")
                .isNotEmpty) return;
              await new Future.delayed(const Duration(milliseconds: 2000));
              var mld = new Device();
              mld.id = "DEAD";
              mld.name = "H4x0r";
              mld.sus = 1.0;
              mld.infected = true;
              newDevice(mld);
              infectDevice(mld, d, 0);
            } else if (data["type"] == "revert") {
              revert();
            } else if (data["type"] == "secure1") {
              protectionLevel = 1;
            } else if (data["type"] == "secure2") {
              protectionLevel = 2;
            } else if (data["type"] == "gps") {
              d.lat = data["pos"][0];
              d.lgn = data["pos"][1];
            }
          });
          socket.done.then((reason) {
            clients.remove(socket);
            killDevice(d);
          });
        } else if (req.uri.path == "/hci") {
          print("hcidump");
          try {
            var p = await Process.start("hcidump", ["-r", "/dev/stdin", "-t"]);
            print("pd");
            var requestData = await req.toList();
            print("ws ${requestData.length}");
            stderr.addStream(p.stderr);
            print("ws2");
            await p.stdin.addStream(new Stream.fromIterable(requestData));
            print("wc");
            await p.stdin.close();
            print("decoding");
            var data = await p.stdout.transform(new Utf8Decoder()).join();
            print(data);
            data = data.replaceAll("\n", " ").replaceAll(new RegExp(r"(586524|2017)"), "\n2017");
            //print(data);
            bool skip_header = true;
            List<List<String>> csv_data = [];
            
            csv_data.add([req.headers.value("clid"), ""]);
            
            var lines = data.split("\n");
            print("${lines.length} lines");
            for (int i = 0; i < lines.length; i++) {
              var line = lines[i];
              if (skip_header) {
                i += 2;
                skip_header = false;
              } else if (line.contains("<") && line.contains("HCI")) {
                csv_data.add(line.split("<"));
              } else if (line.contains(">") && line.contains("HCI")) {
                csv_data.add(line.split(">"));
              }
            }
            
            data = const ListToCsvConverter().convert(csv_data);
            
            print(data);
            
            print("done");
            req.response.statusCode = 500;
            req.response.writeln("Die22");
            req.response.close();
          } catch (e) {
            print("ERR WHILE HCIDUMP $e");
          }
        } else if (req.uri.path == "/res") {
          print("METHOD ${req.method}");
          print("${await req.transform(new Utf8Decoder()).join()}");
          req.response.close();
        } else if (req.uri.path == "/status") {
          print("status");
          await req.response.add(JSON
            .encode({
            "dataEntries": devices.where((dv) => dv.lat != null).map((dv) {
              return <String, dynamic>{
                "latitude": dv.lat,
                "longitude": dv.lgn,
                "macAddress": dv.id,
                "deviceName": dv.name,
                "riskLevel": new Random().nextDouble() * 0.5 + 0.5,
              };
            }).toList(),
          }).codeUnits);
          print("status2");
          req.response.close();
          print("status3");
        } else if (req.uri.path == "/loc") {
          var locations = ["", "", ""];
          List<List<double>> lpos = [[], [], []];
          var risk = [0.0, 0.0, 0.0];
          locations.forEach((ln) {
            var i = locations.indexOf(ln);
            devices.where((dv) => dv.lat != null).forEach((dv) {
              risk[i] += 1 / vecDistance(dv.lat, dv.lgn, lpos[i][0], lpos[i][1]);
            });
          });
          req.response.add(JSON.encode({
            "dataEntries": locations.map((ln) {
              var i = locations.indexOf(ln);
              return {
                "hospitalName": ln,
                "riskLevel": risk[i],
                "latitude": lpos[i][0],
              };
            }),
          }).codeUnits);
          req.response.close();
        } else {
          req.response.statusCode = 500;
          req.response.writeln("Die");
          req.response.close();
        }
      } catch (e) {
        print("error! ${e.toString()}");
      }
    }
  } catch (e) {
    print("error! ${e.toString}");
  }
}