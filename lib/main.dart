import 'dart:io';
//import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<Map<int, String>> loadLabels() async {
  final jsonString = await rootBundle.loadString('assets/labels.json');
  final Map<String, dynamic> data = json.decode(jsonString);

  return data.map((key, value) => MapEntry(value, key));
}

final Future<Map<int, String>> dogClasses = loadLabels();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dogdex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DogCollectionScreen(),
    );
  }
}

class DogUploadScreen extends StatefulWidget {
  const DogUploadScreen({super.key});

  @override
  State<DogUploadScreen> createState() => _DogUploadScreenState();
}

class _DogUploadScreenState extends State<DogUploadScreen> {
  File? _dogImage;
  String status = "Waiting for server to start";
  final ImagePicker _picker = ImagePicker();
  bool _serverUp = false;

  @override
  void initState() {
    super.initState();
    _wakeServer();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _dogImage = File(image.path);
        status = "Analyzing...";
      });
      final response = await _predictDog(image.path);
      if (kDebugMode) {
        debugPrint(response.body);
      }
      final predictions = jsonDecode(response.body) as Map<String, dynamic>;
      final top = predictions["predictions"][0];
      setState(() {
        status = "We think this is a ${top["breed"]} with ${(top["probability"]*100).toStringAsFixed(1)}% certainty";
      });
    }
  }

  Future<http.Response> _predictDog(String dogPath) async {
    final uri = Uri.parse("https://dog-api.up.railway.app/predict");
    final request = http.MultipartRequest('POST', uri);
    
    final mimeType = dogPath.toLowerCase().endsWith('.png') 
        ? MediaType('image', 'png') 
        : MediaType('image', 'jpeg');

    request.files.add(await http.MultipartFile.fromPath(
      'image', 
      dogPath,
      contentType: mimeType,
    ));

    const apiKey = String.fromEnvironment(
      'DOG_API_KEY', 
      defaultValue: 'API_KEY_NOT_FOUND'
    );

    request.headers["X-API-Key"] = apiKey;

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  Future<void> _wakeServer() async {
    final uri = Uri.parse("https://dog-api.up.railway.app/");
    final request = http.MultipartRequest('GET', uri);
    await request.send();

    if (!mounted) return;

    setState(() {
      _serverUp = true;
      status = "Awaiting dog";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Dogdex',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_dogImage != null) ...[
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.brown.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(
                      _dogImage!,
                      height: 300,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.brown.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.brown.shade300,
                      width: 3,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_serverUp) ...[
                        Icon(
                          Icons.pets,
                          size: 80,
                          color: Colors.brown.shade300,
                        ),
                      ]
                      else ...[
                        CircularProgressIndicator(
                          constraints: BoxConstraints().tighten(width: 70, height: 70),
                          color: Colors.brown.shade300,
                          strokeWidth: 8,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'No dog yet :3',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.brown.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.brown.shade400,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_serverUp && status != "Analyzing...") ...[
                FilledButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(_dogImage == null ? 'Upload Dog' : 'Change Dog'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.brown.shade600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ]
              else ...[
                const SizedBox(height: 37),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DogCollectionScreen extends StatefulWidget {
  const DogCollectionScreen({super.key});

  @override
  State<DogCollectionScreen> createState() => _DogCollectionScreenState();
}

class _DogCollectionScreenState extends State<DogCollectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Collection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DogUploadScreen(),
                ),
              );
            }, 
            icon: const Icon(Icons.camera_alt_rounded)
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (int i = 1; i < 119; i++) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => DogInfoScreen(dogNum: i),
                      ),
                    );
                  },
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.brown.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.brown.shade300,
                        width: 3,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pets,
                          size: 80,
                          color: Colors.brown.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Undiscovered :3',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.brown.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DogInfoScreen extends StatefulWidget {
  final int dogNum;

  const DogInfoScreen({super.key, required this.dogNum});

  @override
  State<DogInfoScreen> createState() => _DogInfoScreenState();
}

class _DogInfoScreenState extends State<DogInfoScreen> {
  late Future<Map<String, dynamic>> dogInfo;

  Future<Map<String, dynamic>> _getInfo() async {
    final uri = Uri.parse("https://dog-api.up.railway.app/info");
    final request = http.MultipartRequest('POST', uri);

    final dogBreed = await dogClasses;
    request.fields.addEntries({'breed': dogBreed[widget.dogNum] ?? 'Unknown'}.entries);

    const apiKey = String.fromEnvironment(
      'DOG_API_KEY', 
      defaultValue: 'API_KEY_NOT_FOUND'
    );

    request.headers["X-API-Key"] = apiKey;

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  void initState() {
    super.initState();
    dogInfo = _getInfo();
    if (kDebugMode) {
      debugPrint("Screen initialized for breed: ${widget.dogNum}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Dogdex',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: FutureBuilder<Map<String, dynamic>>(
            future: dogInfo,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      constraints: BoxConstraints().tighten(width: 70, height: 70),
                      color: Colors.brown.shade300,
                      strokeWidth: 8,
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              final data = snapshot.data ?? {};
              return Column(
                children: [
                  Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.brown.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.brown.shade300,
                        width: 3,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pets,
                          size: 80,
                          color: Colors.brown.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No dog yet :3',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.brown.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade400,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      data["name"] as String? ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}