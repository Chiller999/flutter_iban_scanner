library flutter_iban_scanner;

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:iban/iban.dart';

class IBANScannerView extends StatefulWidget {
  final ValueChanged<String> onScannerResult;
  final List<CameraDescription>? cameras;

  IBANScannerView({
    required this.onScannerResult,
    this.cameras,
  });

  @override
  _IBANScannerViewState createState() => _IBANScannerViewState();
}

class _IBANScannerViewState extends State<IBANScannerView> {
  final textDetector = GoogleMlKit.vision.textRecognizer();
  CameraController? _controller;
  late List<CameraDescription> cameras;
  bool isBusy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  void _initCamera() async {
    cameras = widget.cameras ?? await availableCameras();
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    
    await _controller?.initialize();
    if (mounted) {
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    }
  }

  @override
  void dispose() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    await textDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller?.value.isInitialized != true) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future _processCameraImage(CameraImage image) async {
    if (isBusy) return;
    isBusy = true;

    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: InputImageFormat.yuv_420_888,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    await _processImage(inputImage);
    isBusy = false;
  }

  Future<void> _processImage(InputImage inputImage) async {
    final recognisedText = await textDetector.processImage(inputImage);

    final ibanRegex = RegExp(
      r"([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})",
      caseSensitive: false,
    );

    for (final textBlock in recognisedText.blocks) {
      final match = ibanRegex.firstMatch(textBlock.text.replaceAll(' ', ''));
      if (match != null) {
        final possibleIBAN = match.group(0)!;
        if (isValid(possibleIBAN)) {
          final formattedIBAN = toPrintFormat(possibleIBAN);
          widget.onScannerResult(formattedIBAN);
          return;
        }
      }
    }
  }
}
