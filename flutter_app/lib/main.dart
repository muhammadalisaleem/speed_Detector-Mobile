import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  IOWebSocketChannel? channel;
  bool streaming = false;
  List<dynamic> detections = [];
  String serverAddress = 'ws://10.0.2.2:8000/ws'; // emulator default; replace with host IP on device
  bool _processing = false;
  int _lastSentMs = 0;
  String status = 'Initializing camera...';
  late final TextEditingController _serverAddressController;
  late final TextEditingController _calibrationController;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _serverAddressController = TextEditingController(text: serverAddress);
    _calibrationController = TextEditingController(text: '0.05');
    _initCamera();
  }

  void _applyCalibration() {
    final value = double.tryParse(_calibrationController.text.trim());
    if (value == null || value <= 0) {
      setState(() => status = 'Calibration must be a positive number');
      return;
    }

    _connectWebSocket();
    if (channel == null) {
      setState(() => status = 'WebSocket not connected');
      return;
    }

    channel!.sink.add(jsonEncode({
      'type': 'calibration',
      'meters_per_pixel': value,
    }));
    setState(() => status = 'Sent calibration: $value m/px');
  }

  Future<void> _initCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => status = 'No cameras found');
        return;
      }
      controller = CameraController(cameras[0], ResolutionPreset.low, enableAudio: false);
      await controller!.initialize();
      if (mounted) {
        setState(() => status = 'Camera ready');
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Camera init failed: $e');
      }
    }
  }

  void _connectWebSocket() {
    if (channel != null) return;
    try {
      channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));
      channel!.stream.listen((message) {
        try {
          final parsed = jsonDecode(message);
          if (parsed is List) {
            setState(() => detections = parsed);
          } else if (parsed is Map && parsed['type'] == 'calibration_ack') {
            if (parsed['ok'] == true) {
              final v = (parsed['meters_per_pixel'] as num?)?.toDouble();
              if (v != null) {
                _calibrationController.text = v.toStringAsFixed(4);
              }
              setState(() => status = 'Calibration applied');
            } else {
              setState(() => status = 'Calibration failed: ${parsed['error']}');
            }
          }
        } catch (_) {
          // ignore parse errors
        }
      }, onDone: () {
        channel = null;
        if (mounted && !_isDisposing) {
          setState(() {
            streaming = false;
            status = 'WebSocket closed';
          });
        }
      }, onError: (err) {
        channel = null;
        if (mounted && !_isDisposing) {
          setState(() {
            streaming = false;
            status = 'WebSocket error: $err';
          });
        }
      });
      setState(() => status = 'WebSocket connected');
    } catch (e) {
      setState(() => status = 'WebSocket connect failed: $e');
    }
  }

  void _startStreaming() {
    if (controller == null || !controller!.value.isInitialized) {
      setState(() => status = 'Camera is not ready yet');
      return;
    }
    _connectWebSocket();
    try {
      controller!.startImageStream((CameraImage image) async {
        if (!streaming) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        // throttle to ~8-10 FPS
        if (now - _lastSentMs < 120) return;
        if (_processing) return;
        _lastSentMs = now;
        _processing = true;
        try {
          final params = {
            'width': image.width,
            'height': image.height,
            'y': image.planes[0].bytes,
            'u': image.planes.length > 1 ? image.planes[1].bytes : Uint8List(0),
            'v': image.planes.length > 2 ? image.planes[2].bytes : Uint8List(0),
            'yRowStride': image.planes[0].bytesPerRow,
            'uvRowStride': image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
            'uvPixelStride': image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1,
            'platform': Platform.isAndroid ? 'android' : 'ios',
          };

          final jpeg = await compute(_convertYUV420ToJpeg, params);
          if (channel != null) channel!.sink.add(jpeg);
        } catch (e) {
          if (mounted) {
            setState(() => status = 'Frame processing error: $e');
          }
        } finally {
          _processing = false;
        }
      });
      setState(() {
        streaming = true;
        status = 'Streaming frames';
      });
    } catch (e) {
      setState(() => status = 'Start stream failed: $e');
    }
  }

  void _stopStreaming() {
    streaming = false;
    try {
      controller?.stopImageStream();
    } catch (e) {
      if (mounted && !_isDisposing) {
        setState(() => status = 'Stop stream failed: $e');
      }
    }
    channel?.sink.close();
    channel = null;
    if (mounted && !_isDisposing) {
      setState(() => status = 'Streaming stopped');
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _stopStreaming();
    _serverAddressController.dispose();
    _calibrationController.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Speed App')),
      body: Column(
        children: [
          if (controller != null && controller!.value.isInitialized)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  CameraPreview(controller!),
                  CustomPaint(
                    painter: OverlayPainter(detections),
                    child: Container(),
                  ),
                ],
              ),
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Center(child: Text('Initializing camera...')),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(labelText: 'WebSocket Server'),
                  controller: _serverAddressController,
                  onChanged: (v) => serverAddress = v,
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (streaming) {
                    _stopStreaming();
                  } else {
                    _startStreaming();
                  }
                },
                child: Text(streaming ? 'Stop' : 'Start'),
              )
            ]),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: 'Calibration (meters/pixel)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    controller: _calibrationController,
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _applyCalibration,
                  child: Text('Apply'),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(status, style: TextStyle(color: Colors.grey[700])),
            ),
          ),

          Expanded(
            child: ListView(
              children: detections.map((d) {
                final label = (d['label'] ?? 'object').toString();
                final moving = d['moving'] == true;
                return ListTile(
                  title: Text('$label  ID: ${d['id']}'),
                  subtitle: Text('x:${d['x']} y:${d['y']} speed:${(d['speed'] ?? 0).toStringAsFixed(1)} km/h ${moving ? '(moving)' : '(still)'}'),
                );
              }).toList(),
            ),
          )
        ],
      ),
    );
  }
}

// Runs in an isolate via compute; params must be plain values/Uint8List
Uint8List _convertYUV420ToJpeg(Map<String, dynamic> params) {
  final int width = params['width'];
  final int height = params['height'];
  final Uint8List y = params['y'];
  final Uint8List u = params['u'];
  final Uint8List v = params['v'];
  final int yRowStride = params['yRowStride'];
  final int uvRowStride = params['uvRowStride'];
  final int uvPixelStride = params['uvPixelStride'];
  final String platform = params['platform'];

  final imglib.Image img = imglib.Image(width, height);

  if (platform == 'ios') {
    // iOS (BGRA)
    final bytes = y; // on iOS image.planes[0].bytes is BGRA
    int bi = 0;
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final b = bytes[bi++] & 0xff;
        final g = bytes[bi++] & 0xff;
        final r = bytes[bi++] & 0xff;
        bi++; // alpha
        img.setPixelRgba(col, row, r, g, b);
      }
    }
  } else {
    // Android YUV420 -> RGB
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final int yIndex = row * yRowStride + col;
        final int yVal = y[yIndex] & 0xff;

        final int uvRow = (row >> 1) * uvRowStride;
        final int uvIndex = uvRow + (col >> 1) * uvPixelStride;
        final int uVal = u.isNotEmpty ? u[uvIndex] & 0xff : 128;
        final int vVal = v.isNotEmpty ? v[uvIndex] & 0xff : 128;

        int r = (yVal + (1.370705 * (vVal - 128))).round();
        int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round();
        int b = (yVal + (1.732446 * (uVal - 128))).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        img.setPixelRgba(col, row, r, g, b);
      }
    }
  }

  // encode to JPEG
  final jpg = imglib.encodeJpg(img, quality: 70);
  return Uint8List.fromList(jpg);
}

class OverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  OverlayPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final centerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (var d in detections) {
      try {
        final x = (d['x'] as num).toDouble();
        final y = (d['y'] as num).toDouble();
        final x1 = (d['x1'] as num).toDouble();
        final y1 = (d['y1'] as num).toDouble();
        final x2 = (d['x2'] as num).toDouble();
        final y2 = (d['y2'] as num).toDouble();
        final id = d['id'];
        final label = (d['label'] ?? 'object').toString();
        final speed = (d['speed'] as num).toDouble();
        final moving = d['moving'] == true;

        final frameW = ((d['frame_w'] as num?)?.toDouble() ?? 640.0).clamp(1.0, 99999.0);
        final frameH = ((d['frame_h'] as num?)?.toDouble() ?? 360.0).clamp(1.0, 99999.0);

        // Map server coordinates from model frame space to preview space.
        final px = x / frameW * size.width;
        final py = y / frameH * size.height;
        final rx1 = x1 / frameW * size.width;
        final ry1 = y1 / frameH * size.height;
        final rx2 = x2 / frameW * size.width;
        final ry2 = y2 / frameH * size.height;

        boxPaint.color = moving ? Colors.greenAccent : Colors.orangeAccent;
        canvas.drawRect(Rect.fromLTRB(rx1, ry1, rx2, ry2), boxPaint);

        canvas.drawCircle(Offset(px, py), 4, centerPaint);

        final tp = TextPainter(
          text: TextSpan(
            text: '$label  ID:$id ${speed.toStringAsFixed(1)} km/h',
            style: TextStyle(
              color: moving ? Colors.white : Colors.orangeAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(rx1 + 2, (ry1 - 16).clamp(0, size.height - 16)));
      } catch (e) {
        // ignore
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
