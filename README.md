# desktop_drop_test

An experimental macOS desktop drop target test.

## The Goal

Making a Flutter macOS desktop app a drop target without really knowing how to write macOS apps (yet).

## Steps

If not already done, make sure to enable desktop mode:

    $ flutter config --enable-macos-desktop

I create this app:

    $ fluter create desktop_drop_test

Then, I remove the `ios`, `android`, `web` and `test` folders, leaving only the `macos` folder (I haven't enabled Windows or Linux support because I know even less about those desktop platforms).

I check that everything works:

    $ flutter run

This should start the usual counter app on your Mac.

To support dropping files, we need to somehow make the application window aware of drop operations. This has to be done on the native side, so let's open Xcode and dig around.

    $ open macos/Runner.xcworkspace/

`MainFlutterWindow.swift` seems to be the best place to start.

After some reading about AppKit programming and some failed attempts, I came up with the following approach: I overlay the window's content view (a `FlutterView` object) with a transparent custom `NSView` which implements the `NSDraggingDestination` protocol and which registers itself for receiving file URLs. This seems to be the data type used when dropping files from the Finder.

To use `.fileURL` the project's minimal OS version must be 10.13.

Here is a minimal implementation:

```swift
class DropTarget: NSView {
    static func attach(to flutterViewController: FlutterViewController) {
        let d = DropTarget(frame: flutterViewController.view.bounds)
        d.autoresizingMask = [.width, .height]
        d.registerForDraggedTypes([.fileURL])
        flutterViewController.view.addSubview(d)
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var urls = [String]()
        if let items = sender.draggingPasteboard.pasteboardItems {
            for item in items {
                if let alias = item.string(forType: .fileURL) {
                    urls.append(URL(fileURLWithPath: alias).standardized.absoluteString)
                }
            }
        }
        print(urls)
        return true
    }
}
```

The `DropTarget` is attached in `awakeFromNib` like so:

```swift
    ...
    DropTarget.attach(to: flutterViewController)
    super.awakeFromNib()
}
```

This took me an hour or two implement. Running the application should now allow to drop files from the Finder into the Flutter window and should print the absolute file names on the console.

## The Dart Side

To send those filenames to the Dark ahem Dart side, I will setup a `FlutterMethodChannel` and post the file names to that channel, receiving them on the Flutter side. I could also post other events like `draggingEntered`, `draggingExited` or `draggingUpdated`, but because the Flutter API is asynchronous and Apple's API synchronous, I cannot ask the Flutter side whether a drop should be allowed or not. Therefore, for now, I kept everything as simple as possible.

Here's the next version of the code:

```swift
class DropTarget: NSView {
    static func attach(to flutterViewController: FlutterViewController) {
        let n = "desktop_drop_test"
        let r = flutterViewController.registrar(forPlugin: n)
        let channel = FlutterMethodChannel(name: n, binaryMessenger: r.messenger)
        
        let d = DropTarget(frame: flutterViewController.view.bounds, channel: channel)
        d.autoresizingMask = [.width, .height]
        d.registerForDraggedTypes([.fileURL])
        flutterViewController.view.addSubview(d)
    }
    
    private let channel: FlutterMethodChannel
    
    init(frame: NSRect, channel: FlutterMethodChannel) {
        self.channel = channel
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        channel.invokeMethod("entered", arguments: nil)
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        channel.invokeMethod("exited", arguments: nil)
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = sender.draggingLocation
        channel.invokeMethod("updated", arguments: [location.x, bounds.height - location.y])
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var urls = [String]()
        if let items = sender.draggingPasteboard.pasteboardItems {
            for item in items {
                if let alias = item.string(forType: .fileURL) {
                    urls.append(URL(fileURLWithPath: alias).standardized.absoluteString)
                }
            }
        }
        channel.invokeMethod("dropped", arguments: urls)
        return true
    }
}
```

I struggled with how to best design the Flutter API. Here is what I came up with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DropTarget extends ValueNotifier<bool> {
  static final channel = MethodChannel('desktop_drop_test');
  static final instance = DropTarget();

  final _droppedController = StreamController<List<File>>.broadcast(sync: false);

  DropTarget() : super(false) {
    channel.setMethodCallHandler((call) {
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
```

Converting `arguments` to a `List<File>` took an embarrassing amout of time until I noticed that my initially implemention silently crashed. I was thinking about sending strings instead of `File`s but then decided to hide the required conversion inside of my API. I would have prefered to use URLs, but Flutter's `Image.network` seems to not work with `file:` URLs so I had to use `Image.file` instead.

Last but not least, here's a widget that accepts images and displays them:

```dart
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<File>>(
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
    );
  }
}
```

It does not do any error checking.

This is just a proof of concept. To test not only the `Stream<List<File>>` part of the API but also the `ChangeNotifier`, here's another widget that signals if something is dragged over the window:

```dart
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
```

If somebody has an idea how to let the Flutter side decide whether `draggingEntered` should accept the operation or not, please tell me (or create a PR). Also, a widget that restricts the drop operation to its bounds instead of working on the whole native window would be nice.
