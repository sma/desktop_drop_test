import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DropTarget extends ValueNotifier<bool> {
  static final channel = MethodChannel('desktop_drop_test');
  static final instance = DropTarget();

  final _droppedController = StreamController<List<File>>.broadcast();

  DropTarget() : super(false) {
    channel.setMethodCallHandler((call) {
      print(call.method);
      switch (call.method) {
        case 'entered':
          value = true;
          break;
        case 'exited':
          value = false;
          break;
        case 'updated':
          break;
        case 'dropped':
          _droppedController.add(List.of((call.arguments as List).map((uri) => File.fromUri(Uri.parse(uri)))));
          value = false;
          break;
      }
      return null;
    });
  }

  void close() {
    _droppedController.close();
  }

  Stream<List<File>> get dropped => _droppedController.stream;
}
