import 'dart:io';

import 'package:flutter/material.dart';

import 'drop_target.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DropNotifier(
        child: StreamBuilder<List<File>>(
          stream: DropTarget.instance.dropped,
          initialData: [],
          builder: (context, snapshot) {
            return Row(
              children: [
                ...snapshot.data.map((file) => Image.file(file)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class DropNotifier extends StatelessWidget {
  final Widget child;

  const DropNotifier({Key key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DropTarget.instance,
      builder: (context, value, child) {
        return Stack(
          children: [
            child,
            AnimatedContainer(
              duration: Duration(milliseconds: 250),
              decoration: BoxDecoration(
                border: Border.all(
                  color: value ? Colors.green : Colors.transparent,
                  width: 8,
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
