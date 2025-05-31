library flutter_iban_scanner;

import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:iban/iban.dart';
import 'package:image_picker/image_picker.dart';

enum ScreenMode { liveFeed, gallery }

class IBANScannerView extends StatefulWidget {
  final ValueChanged<String> onScannerResult;
  final List<CameraDescription>? cameras;
  final bool allowImagePicker;
  final bool allowCameraSwitch;

  const IBANScannerView({
    Key? key,
    required this.onScannerResult,
    this.cameras,
    this.allowImagePicker = true,
    this.allowCameraSwitch = true,
  }) : super(key: key);

  @override
  _IBANScannerViewState createState() => _IBANScannerViewState();
}

class _IBANScannerViewState extends State<IBANScannerView> {
  final textDetector = GoogleMlKit.vision.textRecognizer();
  ScreenMode _mode = ScreenMode.liveFeed;
  CameraLensDirection initialDirection = CameraLensDirection.back;
  CameraController? _controller;
  File? _image;
  late ImagePicker _imagePicker;
  int _cameraIndex = 0;
  List<CameraDescription> cameras = [];
  bool isBusy = false;
  bool ibanFound = false;
  String iban = "";

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() async {
    cameras = widget.cameras ?? await availableCameras();
    if (initialDirection == CameraLensDirection.front) {
      _cameraIndex = cameras.length > 1 ? 1 : 0;
    }
    await _startLiveFeed();
    _imagePicker = ImagePicker();
  }

  @override
  void dispose() async {
    await _stopLiveFeed();
    await textDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body(),
      floatingActionButton: _floatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget? _floatingActionButton() {
    if (_mode == ScreenMode.gallery) return null;
    if (cameras.isEmpty || cameras.length == 1) return null;
    if (widget.allowCameraSwitch == false) return null;
    return Container(
        height: 70.0,
        width: 70.0,
        child: FloatingActionButton(
          child: Icon(
            Platform.isIOS
                ? Icons.flip_camera_ios_outlined
                : Icons.flip_camera_android_outlined,
            size: 40,
          ),
          onPressed: _switchLiveCamera,
        ));
  }

  Widget _body() {
    Widget body;
    if (_mode == ScreenMode.liveFeed) {
      body = _liveFeedBody();
    } else {
      body = _galleryBody();
    }
    return body;
  }

  Widget _liveFeedBody() {
    if (_controller?.value.isInitialized == false) {
      return Container();
    }
    return SafeArea(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_controller != null) CameraPreview(_controller!),
            const Mask(),
            Positioned(
              top: 0.0,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 20.0, top: 20),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    if (widget.allowImagePicker)
                      Padding(
                        padding: const EdgeInsets.only(right: 20.0, top: 20),
                        child: GestureDetector(
                          onTap: _switchScreenMode,
                          child: Icon(
                            _mode == ScreenMode.liveFeed
                                ? Icons.photo_library_outlined
                                : (Platform.isIOS
                                    ? Icons.camera_alt_outlined
                                    : Icons.camera),
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _switchScreenMode() async {
    if (_mode == ScreenMode.liveFeed) {
      _mode = ScreenMode.gallery;
      await _stopLiveFeed();
    } else {
      _mode = ScreenMode.liveFeed;
      await _startLiveFeed();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Widget _galleryBody() {
    return ListView(shrinkWrap: true, children: [
      _image != null
          ? Container(
              height: 400,
              width: 400,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.file(_image!),
                ],
              ),
            )
          : const Icon(
              Icons.image,
              size: 200,
            ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton(
          child: const Text('From Gallery'),
          onPressed: () => _getImage(ImageSource.gallery),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton(
          child: const Text('Take a picture'),
          onPressed: () => _getImage(ImageSource.camera),
        ),
      ),
    ]);
  }

  Future _getImage(ImageSource source) async {
    final pickedFile = await _imagePicker.pickImage(source: source);
    if (pickedFile != null) {
      _processPickedFile(pickedFile);
    } else {
      print('No image selected.');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future _processPickedFile(XFile pickedFile) async {
    setState(() {
      _image = File(pickedFile.path);
    });
    final inputImage = InputImage.fromFilePath(pickedFile.path);
    processImage(inputImage);
  }

  RegExp regExp = RegExp(
    r"^(.*)(([A-Z]{2}[ \-]?[0-9]{2})(?=(?:[ \-]?[A-Z0-9]){9,30}$)((?:[ \-]?[A-Z0-9]{3,5}){2,7})([ \-]?[A-Z0-9]{1,3})?)$",
    caseSensitive: false,
    multiLine: false,
  );

  Future<void> processImage(InputImage inputImage) async {
    if (isBusy) return;
    isBusy = true;

    try {
      final recognisedText = await textDetector.processImage(inputImage);

      for (final textBlock in recognisedText.blocks) {
        // Clean the text by removing spaces and special characters for IBAN validation
        String cleanText = textBlock.text.replaceAll(RegExp(r'[\s\-]'), '');
        
        // Check if it looks like an IBAN (starts with 2 letters followed by 2 digits)
        if (RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]+$', caseSensitive: false).hasMatch(cleanText)) {
          if (isValid(cleanText)) {
            iban = toPrintFormat(cleanText);
            ibanFound = true;
            break;
          }
        }
        
        // Also try the original regex approach as fallback
        if (!ibanFound && regExp.hasMatch(textBlock.text)) {
          var possibleIBAN = regExp.firstMatch(textBlock.text)?.group(2);
          if (possibleIBAN != null && isValid(possibleIBAN)) {
            iban = toPrintFormat(possibleIBAN);
            ibanFound = true;
            break;
          }
        }
      }

      if (ibanFound) {
        widget.onScannerResult(iban);
      }
    } catch (e) {
      print('Error processing image: $e');
    }

    isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future _startLiveFeed() async {
    if (cameras.isEmpty) return;
    
    final camera = cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.yuv420,
      enableAudio: false,
    );
    
    try {
      await _controller?.initialize();
      if (!mounted) {
        return;
      }
      await _controller?.startImageStream(_processCameraImage);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error starting camera: $e');
    }
  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    if (cameras.isEmpty) return;
    
    if (_cameraIndex == 0) {
      _cameraIndex = 1;
    } else {
      _cameraIndex = 0;
    }
    
    // Ensure we don't go out of bounds
    if (_cameraIndex >= cameras.length) {
      _cameraIndex = 0;
    }
    
    await _stopLiveFeed();
    await _startLiveFeed();
  }

  Future _processCameraImage(CameraImage image) async {
    if (isBusy) return;
    
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final camera = cameras[_cameraIndex];
      final imageRotation = InputImageRotation.values.firstWhere(
        (element) => element.rawValue == camera.sensorOrientation,
        orElse: () => InputImageRotation.rotation0deg,
      );

      final inputImageFormat = InputImageFormat.values.firstWhere(
        (element) => element.rawValue == image.format.raw,
        orElse: () => InputImageFormat.yuv420,
      );

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage =
          InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      
      if (mounted) {
        await processImage(inputImage);
      }
    } catch (e) {
      print('Error processing camera image: $e');
    }
  }
}

class Mask extends StatelessWidget {
  const Mask({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
        ),
        child: CustomPaint(
          painter: MaskPainter(),
          child: Container(),
        ),
      ),
    );
  }
}

class MaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final transparentPaint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear;

    // Draw the overlay
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Create a transparent rectangle in the center for scanning area
    final scanAreaHeight = size.height * 0.3;
    final scanAreaWidth = size.width * 0.8;
    final left = (size.width - scanAreaWidth) / 2;
    final top = (size.height - scanAreaHeight) / 2;

    canvas.drawRect(
      Rect.fromLTWH(left, top, scanAreaWidth, scanAreaHeight),
      transparentPaint,
    );

    // Draw border around scanning area
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(
      Rect.fromLTWH(left, top, scanAreaWidth, scanAreaHeight),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
