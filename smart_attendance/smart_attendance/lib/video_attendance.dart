import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const apiBase = "http://192.168.1.7:8000"; // replace with backend IP

class VideoAttendancePage extends StatefulWidget {
  final Map course;
  const VideoAttendancePage({super.key, required this.course});

  @override
  State<VideoAttendancePage> createState() => _VideoAttendancePageState();
}

class _VideoAttendancePageState extends State<VideoAttendancePage> {
  CameraController? _controller;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/attendance.mp4';
    await _controller!.startVideoRecording();
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final file = await _controller!.stopVideoRecording();
    setState(() => _isRecording = false);

    await _uploadVideo(File(file.path));
  }

  Future<void> _uploadVideo(File videoFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBase/attendance/video/${widget.course['id']}'),
    );
    request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final result = jsonDecode(body);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Attendance Result"),
        content: Text("Present: ${result['present']}\n${result['present_names'].join("\n")}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Video Attendance")),
      body: CameraPreview(_controller!),
      floatingActionButton: FloatingActionButton(
        onPressed: _isRecording ? _stopRecording : _startRecording,
        child: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
      ),
    );
  }
}
