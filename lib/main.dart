import 'dart:io';
//import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final String apiUrl = "http://dog-api.tobyv.dev";

const String API_KEY_ENV = String.fromEnvironment(
  'API_KEY',
  defaultValue: 'API_KEY_NOT_FOUND',
);

String API_KEY = "";

Future<Map<int, String>> loadLabels() async {
  final jsonString = await rootBundle.loadString('assets/labels.json');
  final Map<String, dynamic> data = json.decode(jsonString);

  return data.map((key, value) => MapEntry(value, key));
}

Future<http.Response> createSession() async {
  final uri = Uri.parse("$apiUrl/session");
  final request = http.MultipartRequest('GET', uri);
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  API_KEY = API_KEY_ENV;

  if (API_KEY == 'API_KEY_NOT_FOUND') {
    API_KEY = response.body;
  }
  if (kDebugMode) {
    debugPrint(API_KEY);
  }

  return response;
}

Future<List<String>> loadApiDogs() async {
  final jsonString = await rootBundle.loadString('assets/api_dogs.json');
  final List<dynamic> data = json.decode(jsonString);
  return data.cast<String>();
}

final Future<Map<int, String>> dogClasses = loadLabels();
final Future<List<String>> apiDogs = loadApiDogs();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
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
    checkServer();
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
        status =
            "We think this is a ${top["breed"]} with ${(top["probability"] * 100).toStringAsFixed(1)}% certainty";
      });
    }
  }

  Future<http.Response> _predictDog(String dogPath) async {
    Future<http.Response> sendRequest() async {
      final uri = Uri.parse("$apiUrl/predict");
      final request = http.MultipartRequest('POST', uri);

      final mimeType = dogPath.toLowerCase().endsWith('.png')
          ? MediaType('image', 'png')
          : MediaType('image', 'jpeg');

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          dogPath,
          contentType: mimeType,
        ),
      );

      request.headers["X-API-Key"] = API_KEY;

      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    }

    var response = await sendRequest();

    if (response.statusCode == 403) {
      await createSession();
      response = await sendRequest();
    }

    return response;
  }

  Future<void> _wakeServer() async {
    final uri = Uri.parse("$apiUrl/");
    final request = http.MultipartRequest('GET', uri);
    await request.send();

    if (!mounted) return;

    setState(() {
      _serverUp = true;
      status = "Awaiting dog";
    });
  }

  Future<void> checkServer() async {
    final uri = Uri.parse("$apiUrl/");
    final request = http.MultipartRequest('GET', uri);
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (!mounted) return;
    
    setState(() {
      if (response.statusCode != 502) {
        _serverUp = true;
        status = "Awaiting dog";
      } else {
        _serverUp = false;
        status = "Cannot reach server";

      }
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.pets, size: 80, color: Colors.brown.shade300),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          child: Text(
                            'No dog yet :3',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.brown.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                  textAlign: TextAlign.center,
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
              ] else ...[
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
  bool advanced = false;

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
              setState(() {
                advanced = !advanced;
              });
            },
            icon: Icon(advanced ? Icons.check_circle : Icons.circle_outlined),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DogUploadScreen(),
                ),
              );
            },
            icon: const Icon(Icons.camera_alt_rounded),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: FutureBuilder<List<Object>>(
            future: Future.wait([dogClasses, apiDogs]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      constraints: BoxConstraints().tighten(
                        width: 70,
                        height: 70,
                      ),
                      color: Colors.brown.shade300,
                      strokeWidth: 8,
                    ),
                  ],
                );
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return Text('Error loading dogs: ${snapshot.error}');
              }

              final breeds = snapshot.data![0] as Map<int, String>;
              final allowedBreeds = (snapshot.data![1] as List<String>).toSet();

              var sortedIds = breeds.keys.toList();
              if (!advanced) {
                sortedIds = sortedIds
                    .where((id) => allowedBreeds.contains(breeds[id]))
                    .toList();
              }
              sortedIds.sort((a, b) => breeds[a]!.compareTo(breeds[b]!));

              return GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  for (final i in sortedIds) ...[
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
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Text(
                                breeds[i]!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.brown.shade400,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
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
    final dogBreed = await dogClasses;
    final breedName = dogBreed[widget.dogNum] ?? 'Unknown';

    final jsonString = await rootBundle.loadString('assets/dog_api.json');
    final List<dynamic> allBreeds = jsonDecode(jsonString) as List<dynamic>;

    String normalize(String s) {
      final lower = s.toLowerCase();
      final withoutDog = lower.replaceAll('dog', '');
      final cleaned = withoutDog.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
      final tokens =
          cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList()
            ..sort();
      return tokens.join(' ');
    }

    final target = normalize(breedName);

    Map<String, dynamic>? match;
    for (final item in allBreeds) {
      if (item is Map<String, dynamic>) {
        final name = item['name'] as String? ?? '';
        if (normalize(name) == target) {
          match = item;
          break;
        }
      }
    }

    if (match == null) {
      return <String, dynamic>{'name': breedName};
    }

    return match;
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
                      constraints: BoxConstraints().tighten(
                        width: 70,
                        height: 70,
                      ),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            "Undiscovered :3",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.brown.shade400,
                              fontWeight: FontWeight.w500,
                            ),
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  if (data['description'] != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      data['description'] as String,
                      textAlign: TextAlign.justify,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.brown.shade800,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
