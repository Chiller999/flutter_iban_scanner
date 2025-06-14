library flutter_iban_scanner;

import 'dart:io';

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

  IBANScannerView({
    required this.onScannerResult,
    this.cameras,
    this.allowImagePicker = true,
    this.allowCameraSwitch = true,
  });

  @override
  _IBANScannerViewState createState() => _IBANScannerViewState();
}

class _IBANScannerViewState extends State<IBANScannerView> {
  final textDetector = GoogleMlKit.vision.textRecognizer(
  script: TextRecognitionScript.latin,
);
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
  if (cameras.isEmpty) return; // Optional: early return if no cameras

  if (initialDirection == CameraLensDirection.front) {
    _cameraIndex = 1;
  }
  await _startLiveFeed();
  _imagePicker = ImagePicker();
}


@override
void dispose() {
  _stopLiveFeed();
  textDetector.close();
  super.dispose(); // super.dispose must come after await was removed
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
    if (cameras.length == 1) return null;
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
    if (_mode == ScreenMode.liveFeed)
      body = _liveFeedBody();
    else
      body = _galleryBody();
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
            Mask(),
            Positioned(
              top: 0.0,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: 20.0, top: 20),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(Icons.arrow_back),
                      ),
                    ),
                    if (widget.allowImagePicker)
                      Padding(
                        padding: EdgeInsets.only(right: 20.0, top: 20),
                        child: GestureDetector(
                          onTap: _switchScreenMode,
                          child: Icon(
                            _mode == ScreenMode.liveFeed
                                ? Icons.photo_library_outlined
                                : (Platform.isIOS
                                    ? Icons.camera_alt_outlined
                                    : Icons.camera),
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
    setState(() {});
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
          : Icon(
              Icons.image,
              size: 200,
            ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton(
          child: Text('From Gallery'),
          onPressed: () => _getImage(ImageSource.gallery),
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton(
          child: Text('Take a picture'),
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
    setState(() {});
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

Future _processCameraImage(CameraImage image) async {
  if (isBusy) return; // Prevent concurrent processing
  isBusy = true;

  try {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final camera = cameras[_cameraIndex];
    final imageRotation = InputImageRotation.values.firstWhere(
      (element) => element.rawValue == camera.sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );

    final inputImageFormat = InputImageFormat.yuv_420_888;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    await processImage(inputImage);
  } catch (e) {
    print('Camera image processing error: $e');
  } finally {
    isBusy = false;
  }
}


  Future _startLiveFeed() async {
    final camera = cameras![_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );
	await _controller?.initialize();
    if (!mounted) return;
    await _controller?.startImageStream(_processCameraImage);
    setState(() {});

  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    if (_cameraIndex == 0)
      _cameraIndex = 1;
    else
      _cameraIndex = 0;
    await _stopLiveFeed();
    await _startLiveFeed();
  }

Future _processCameraImage(CameraImage image) async {
  if (isBusy) return;
  isBusy = true;

  try {
    if (image.format.group != ImageFormatGroup.yuv420) {
      debugPrint('Unsupported image format: ${image.format.group}');
      isBusy = false;
      return;
    }

    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final camera = cameras[_cameraIndex];

    final imageRotation = InputImageRotation.values.firstWhere(
      (element) => element.rawValue == camera.sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: InputImageFormat.yuv_420_888,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    await processImage(inputImage);
  } catch (e) {
    debugPrint('Error in processing camera image: $e');
  } finally {
    isBusy = false;
  }
}

  
  
  
}

class Mask extends StatelessWidget {
  const Mask({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color _background = Colors.grey.withOpacity(0.7);

    return SafeArea(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
         
              Container(
                height: MediaQuery.of(context).size.height,
                width: MediaQuery.of(context).size.width,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: Container(                      
              

                        
                        color: Colors.transparent,                  
                        
              
                        
                      ),
                    ),
                  ],
                ),
              ),
           
            ],
          )
        ],
      ),
    );
  }
}
