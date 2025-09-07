import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

const String apiBase = 'http://192.168.1.7:8000'; // change to backend IP
Map<String, dynamic>? currentTeacher;

void main() {
  runApp(const MyApp());
}

/* =====================
   APP ROOT
   ===================== */
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF2B2B2),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF6F6),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shadowColor: Colors.black26,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF2B2B2),
            foregroundColor: Colors.black87,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            elevation: 3,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF2B2B2),
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

/* =====================
   LOGIN / SIGNUP PAGE
   ===================== */
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool newUser = false;
  String msg = "";

  Future<void> _loginOrSignup() async {
    if (newUser) {
      final res = await http.post(Uri.parse('$apiBase/signup'), body: {
        'name': nameCtrl.text,
        'email': emailCtrl.text,
        'password': passwordCtrl.text,
      });
      final j = jsonDecode(res.body);
      if (j['success'] == true) {
        currentTeacher = j['teacher'];
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const CoursesPage()));
      } else {
        setState(() => msg = j['msg']);
      }
    } else {
      final res = await http.post(Uri.parse('$apiBase/login'), body: {
        'email': emailCtrl.text,
        'password': passwordCtrl.text,
      });
      final j = jsonDecode(res.body);
      if (j['success'] == true) {
        currentTeacher = j['teacher'];
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const CoursesPage()));
      } else {
        setState(() => msg = j['msg']);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(newUser ? "Sign Up" : "Login",
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      TextField(
                          controller: emailCtrl,
                          decoration:
                              const InputDecoration(labelText: "Email")),
                      if (newUser)
                        TextField(
                            controller: nameCtrl,
                            decoration:
                                const InputDecoration(labelText: "Name")),
                      TextField(
                        controller: passwordCtrl,
                        decoration:
                            const InputDecoration(labelText: "Password"),
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                          onPressed: _loginOrSignup,
                          child: Text(newUser ? "Sign Up" : "Login")),
                      TextButton(
                          onPressed: () => setState(() => newUser = !newUser),
                          child: Text(newUser
                              ? "Already registered? Login"
                              : "New user? Sign Up")),
                      Text(msg, style: const TextStyle(color: Colors.red))
                    ]))));
  }
}

/* =====================
   COURSES PAGE
   ===================== */
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  List courses = [];

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    final res =
        await http.get(Uri.parse('$apiBase/courses/${currentTeacher!['id']}'));
    if (res.statusCode == 200) {
      setState(() => courses = jsonDecode(res.body));
    }
  }

  void _createCourse() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text("Create Course"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: "Course Name")),
                  TextField(
                      controller: codeCtrl,
                      decoration:
                          const InputDecoration(labelText: "Course Code")),
                ],
              ),
              actions: [
                ElevatedButton(
                    onPressed: () async {
                      final req = http.MultipartRequest(
                          'POST', Uri.parse('$apiBase/courses/create'));
                      req.fields['name'] = nameCtrl.text;
                      req.fields['code'] = codeCtrl.text;
                      req.fields['teacher_id'] =
                          currentTeacher!['id'].toString();
                      final res = await req.send();
                      if (res.statusCode == 200) {
                        if (!mounted) return;
                        Navigator.pop(context);
                        _fetchCourses();
                      }
                    },
                    child: const Text("Save"))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("My Courses")),
        body: ListView(
          padding: const EdgeInsets.all(10),
          children: courses
              .map((c) => Card(
                  child: ListTile(
                      title: Text(c['name']),
                      subtitle: Text("Code: ${c['code']}"),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CourseDetailPage(course: c))))))
              .toList(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createCourse,
          backgroundColor: const Color(0xFFF2B2B2),
          child: const Icon(Icons.add),
        ));
  }
}

/* =====================
   CAMERA CAPTURE PAGE
   ===================== */
/* =====================
   CAMERA CAPTURE PAGE
   ===================== */
/* =====================
   CAMERA CAPTURE PAGE
   ===================== */
class CameraCapturePage extends StatefulWidget {
  final bool isVideo;
  final int courseId;
  const CameraCapturePage(
      {super.key, required this.isVideo, required this.courseId});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  late CameraController controller;
  bool isRecording = false;
  File? capturedFile; // ✅ captured photo or video
  VideoPlayerController? videoController; // ✅ for previewing video
  bool isUploading = false; // ✅ show buffering symbol

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    controller = CameraController(cameras.first, ResolutionPreset.medium);
    await controller.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    videoController?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (widget.isVideo) {
      if (!isRecording) {
        await controller.startVideoRecording();
        setState(() => isRecording = true);
      } else {
        final file = await controller.stopVideoRecording();
        setState(() {
          isRecording = false;
          capturedFile = File(file.path);
        });

        // ✅ Setup video playback
        videoController = VideoPlayerController.file(File(file.path));
        await videoController!.initialize();
        videoController!.setLooping(true);
        videoController!.play();
        setState(() {});
      }
    } else {
      final image = await controller.takePicture();
      setState(() => capturedFile = File(image.path));
    }
  }

  Future<void> _uploadFile(String path, {required bool isVideo}) async {
    setState(() => isUploading = true);

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse(
            '$apiBase/attendance/${isVideo ? "video/" : ""}${widget.courseId}'),
      );

      req.files.add(
          await http.MultipartFile.fromPath(isVideo ? 'video' : 'image', path));

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);

      setState(() => isUploading = false);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final count = data['present'];
        final names = List<String>.from(data['present_names'] ?? []);

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(isVideo ? "Video Attendance" : "Photo Attendance"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("✅ Present: $count students"),
                  const SizedBox(height: 10),
                  if (names.isNotEmpty)
                    ...names.map((n) => Text(n)).toList()
                  else
                    const Text("No students detected"),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    Navigator.pop(
                        context, true); // go back & tell list screen to refresh
                  },
                  child: const Text("OK"))
            ],
          ),
        );
      } else {
        _showError("Upload failed (code ${res.statusCode})");
      }
    } catch (e) {
      setState(() => isUploading = false);
      _showError("Error: $e");
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _retake() {
    setState(() {
      capturedFile = null;
      videoController?.dispose();
      videoController = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVideo ? "Video Attendance" : "Photo Attendance"),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: capturedFile == null
                    ? CameraPreview(controller) // ✅ live preview
                    : widget.isVideo
                        ? (videoController != null &&
                                videoController!.value.isInitialized
                            ? AspectRatio(
                                aspectRatio: videoController!.value.aspectRatio,
                                child: VideoPlayer(videoController!),
                              )
                            : const Center(child: Text("Loading video...")))
                        : Image.file(capturedFile!), // ✅ photo preview
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (capturedFile == null)
                      FloatingActionButton(
                        backgroundColor: Colors.pink,
                        onPressed: _capture,
                        child: Icon(widget.isVideo
                            ? (isRecording ? Icons.stop : Icons.videocam)
                            : Icons.camera_alt),
                      )
                    else
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _retake,
                            icon: const Icon(Icons.refresh),
                            label: const Text("Retake"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (capturedFile != null) {
                                _uploadFile(capturedFile!.path,
                                    isVideo: widget.isVideo);
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: const Text("Upload & Submit"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      )
                  ],
                ),
              )
            ],
          ),
          if (isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            )
        ],
      ),
    );
  }
}

/* =====================
   COURSE DETAIL PAGE
   ===================== */
class CourseDetailPage extends StatelessWidget {
  final Map course;
  const CourseDetailPage({super.key, required this.course});

  Future<void> _pickStudentImage(BuildContext context) async {
    final rollCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Student"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rollCtrl,
              decoration: const InputDecoration(labelText: "Roll No"),
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Name"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              FilePickerResult? result =
                  await FilePicker.platform.pickFiles(type: FileType.image);
              if (result != null) {
                File file = File(result.files.single.path!);
                final req = http.MultipartRequest(
                    'POST', Uri.parse('$apiBase/students/add/${course['id']}'));
                req.fields['roll_no'] = rollCtrl.text;
                req.fields['name'] = nameCtrl.text;
                req.files
                    .add(await http.MultipartFile.fromPath('image', file.path));
                await req.send();

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Student ${nameCtrl.text} Added")),
                );
              }
            },
            child: const Text("Next"),
          ),
        ],
      ),
    );
  }

  Future<void> _generateEncodings(BuildContext context) async {
    await http.post(Uri.parse('$apiBase/encodings/${course['id']}'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Encodings Generated")));
  }

  Future<void> _viewAttendance(BuildContext context) async {
    final res =
        await http.get(Uri.parse('$apiBase/attendance/list/${course['id']}'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Attendance Records"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: data.length,
              itemBuilder: (_, i) {
                final s = data[i];
                return ListTile(
                  title: Text("${s['roll_no']} - ${s['name']}"),
                  subtitle: Text(
                      "${s['status']} on ${s['date'] ?? 'N/A'} at ${s['time'] ?? 'N/A'}"),
                  trailing: TextButton(
                    onPressed: () async {
                      final newStatus =
                          s['status'] == "Present" ? "Absent" : "Present";
                      final resp = await http.post(
                        Uri.parse(
                            '$apiBase/attendance/update/${course['id']}/${s['id']}'),
                        body: {"status": newStatus},
                      );
                      if (resp.statusCode == 200 && context.mounted) {
                        Navigator.pop(context);
                        _viewAttendance(context);
                      }
                    },
                    child: Text(
                      s['status'] == "Present" ? "Mark Absent" : "Mark Present",
                      style: const TextStyle(color: Colors.pink),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"))
          ],
        ),
      );
    }
  }

  Future<void> _downloadExcel(BuildContext context) async {
    final res =
        await http.get(Uri.parse('$apiBase/attendance/excel/${course['id']}'));
    if (res.statusCode == 200) {
      final dir = Directory("/storage/emulated/0/Download");
      final file = File("${dir.path}/${course['name']}_attendance.xlsx");
      await file.writeAsBytes(res.bodyBytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Saved to ${file.path}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(course['name'])),
        body: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(children: [
                ElevatedButton.icon(
                    onPressed: () => _pickStudentImage(context),
                    icon: const Icon(Icons.person_add),
                    label: const Text("Add Student")),
                ElevatedButton.icon(
                    onPressed: () => _generateEncodings(context),
                    icon: const Icon(Icons.memory),
                    label: const Text("Generate Encodings")),
                ElevatedButton.icon(
                  onPressed: () async {
                    final didUpdate = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraCapturePage(
                          isVideo: false,
                          courseId: course['id'],
                        ),
                      ),
                    );
                    if (didUpdate == true && context.mounted) {
                      _viewAttendance(
                          context); // show the updated editable list
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Take Attendance (Photo)"),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final didUpdate = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraCapturePage(
                          isVideo: true,
                          courseId: course['id'],
                        ),
                      ),
                    );
                    if (didUpdate == true && context.mounted) {
                      _viewAttendance(
                          context); // show the updated editable list
                    }
                  },
                  icon: const Icon(Icons.videocam),
                  label: const Text("Take Attendance (Video)"),
                ),
                ElevatedButton.icon(
                    onPressed: () => _viewAttendance(context),
                    icon: const Icon(Icons.list),
                    label: const Text("View / Edit Attendance")),
                ElevatedButton.icon(
                    onPressed: () => _downloadExcel(context),
                    icon: const Icon(Icons.download),
                    label: const Text("Download Excel")),
              ]),
            )));
  }
}
