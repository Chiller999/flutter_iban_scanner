library flutter_iban_scanner;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:iban/iban.dart';

class IBANScannerView extends StatefulWidget {
  final ValueChanged<String> onScannerResult;
  final List<CameraDescription>? cameras;

  const IBANScannerView({
    Key? key,
    required this.onScannerResult,
    this.cameras,
  }) : super(key: key);

  @override
  _IBANScannerViewState createState() => _IBANScannerViewState();
}

class _IBANScannerViewState extends State<IBANScannerView> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = GoogleMlKit.vision.textRecognizer();
  List<CameraDescription> _cameras = [];
  bool _isProcessing = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = widget.cameras ?? await availableCameras();
      if (_cameras.isEmpty) return;

      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        await _controller!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(cameraImage);
      if (inputImage != null) {
        final recognizedText = await _textRecognizer.processImage(inputImage);
        _searchForIBAN(recognizedText);
      }
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage cameraImage) {
    try {
      final camera = _cameras.first;
      final rotation = InputImageRotation.values.firstWhere(
        (element) => element.rawValue == camera.sensorOrientation,
        orElse: () => InputImageRotation.rotation0deg,
      );

      final format = InputImageFormat.values.firstWhere(
        (element) => element.rawValue == cameraImage.format.raw,
        orElse: () => InputImageFormat.nv21,
      );

      final plane = cameraImage.planes.first;
      
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      print('Error converting camera image: $e');
      return null;
    }
  }

  void _searchForIBAN(RecognizedText recognizedText) {
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        String text = line.text.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
        
        // Check if text looks like an IBAN (2 letters + 2 digits + alphanumeric)
        if (RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{4,}$').hasMatch(text)) {
          if (isValid(text)) {
            String formattedIBAN = toPrintFormat(text);
            widget.onScannerResult(formattedIBAN);
            return;
          }
        }
        
        // Also check for partial matches in case IBAN is split across lines
        if (text.length >= 6 && RegExp(r'^[A-Z]{2}[0-9]{2}').hasMatch(text)) {
          String cleanText = text.replaceAll(RegExp(r'[^A-Z0-9]'), '');
          if (cleanText.length >= 15 && isValid(cleanText)) {
            String formattedIBAN = toPrintFormat(cleanText);
            widget.onScannerResult(formattedIBAN);
            return;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera preview
          Positioned.fill(
            child: _buildCameraPreview(),
          ),
          
          // Back button
          SafeArea(
            child: Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          
          // Scanning instruction
          SafeArea(
            child: Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Point camera at IBAN number to scan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final controllerRatio = _controller!.value.aspectRatio;
    
    // Calculate scale to fill the screen
    double scale;
    if (controllerRatio < deviceRatio) {
      scale = deviceRatio / controllerRatio;
    } else {
      scale = controllerRatio / deviceRatio;
    }

    return Center(
      child: Transform.scale(
        scale: scale,
        child: CameraPreview(_controller!),
      ),
    );
  }
}
