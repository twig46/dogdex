import 'dart:io';
//import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

final String apiUrl = "https://dog-api.tobyv.dev";

const String API_KEY_ENV = String.fromEnvironment(
  'API_KEY',
  defaultValue: 'API_KEY_NOT_FOUND',
);

String API_KEY = "";

String _toSnakeCase(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

Future<void> _launchURL(String url) async {
   final Uri uri = Uri.parse(url);
   if (!await launchUrl(uri)) {
        throw Exception('Could not launch $url');
    }
}

String article(String word) {
  return RegExp(r'^[aeiouAEIOU]').hasMatch(word) ? 'an' : 'a';
} 

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
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is String) {
        API_KEY = decoded;
      } else {
        API_KEY = response.body;
      }
    } catch (_) {
      API_KEY = response.body;
    }
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

Future<Map<String, String>> loadSavedDogImages() async {
  final dir = await getApplicationDocumentsDirectory();
  final directory = Directory(dir.path);

  final List<FileSystemEntity> entries = await directory.list().toList();
  final Map<String, String> images = {};

  for (final entry in entries) {
    if (entry is File && entry.path.toLowerCase().endsWith('.png')) {
      final segments = entry.path.split(Platform.pathSeparator);
      final fileName = segments.isNotEmpty ? segments.last : '';
      if (fileName.isEmpty) continue;

      final nameWithoutExt = fileName.toLowerCase().endsWith('.png')
          ? fileName.substring(0, fileName.length - 4)
          : fileName;

      images[nameWithoutExt] = entry.path;
    }
  }

  return images;
}

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
      title: 'DogDex',
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
  String status = "Checking if server is available";
  final ImagePicker _picker = ImagePicker();
  bool _serverUp = false;
  String? breed;
  double? confidence;

  @override
  void initState() {
    super.initState();
    checkServer();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _dogImage = File(image.path);
        status = "Analyzing...";
      });
      final response = await _predictDog(image.path);
      if (kDebugMode) {
        debugPrint(response.body);
      }
      if (response.statusCode != 200) {
        setState(() {
          status = "Error: ${response.statusCode}";
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded["predictions"] is! List ||
          (decoded["predictions"] as List).isEmpty) {
        setState(() {
          status = "Unexpected response from server";
        });
        return;
      }

      final top =
          (decoded["predictions"] as List).first as Map<String, dynamic>;
      setState(() {
        status = "Awaiting dog";
        breed = top["breed"];
        confidence = (top["probability"] * 100);
        if (kDebugMode) {
          debugPrint("$breed with ${confidence?.toStringAsFixed(1)}% confidence");
        }
      });
    }
  }

  Future<String> saveImage(File image, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();

    final path = "${dir.path}/$fileName.png";

    final newImage = await image.copy(path);

    return newImage.path;
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

    Map<String, dynamic>? errorBody;
    try {
      errorBody = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      errorBody = null;
    }

    if (response.statusCode == 403 ||
        errorBody?["detail"] == "Could not validate credentials") {
      if (kDebugMode) {
        debugPrint("Creating new session...");
      }
      await createSession();
      response = await sendRequest();
    }

    return response;
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

  void _showImageSourceMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.photo),
                title: Text('Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera),
                title: Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Upload',
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
              if (_dogImage == null) ...[
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
              ],
              if (_serverUp && status != "Analyzing...") ...[
                FilledButton.icon(
                  onPressed: () => _showImageSourceMenu(context),
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
                const SizedBox(height: 20),
                if (_dogImage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade400,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      "Breed",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: [
                      Text(
                        'We are ${(confidence as double).toStringAsFixed(1)}% certain',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'this is ${article(breed as String)} ${breed as String}',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.brown.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade400,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      "Save to your collection?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      if (_dogImage == null || breed == null) {
                        return;
                      }
                      final navigator = Navigator.of(context);
                      final imageKey = _toSnakeCase(breed!);
                      await saveImage(
                        _dogImage!,
                        imageKey,
                      );
                      if (!mounted) return;
                      navigator.pop(imageKey);
                      
                    },
                    icon: const Icon(Icons.done),
                    label: Text("Ok"),
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
                ],
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
  late Future<Map<String, String>> _savedDogImages;
  final List<GlobalKey> globalKeys = [];
  String? _scrollToImageKey;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _savedDogImages = loadSavedDogImages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 DogDex',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(onPressed: () async {await _launchURL("https://github.com/twig46/dogdex/issues/new/choose");} , icon: Icon(Icons.flag)),
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
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (context) => const DogUploadScreen(),
                ),
              )
                  .then((result) {
                setState(() {
                  _savedDogImages = loadSavedDogImages();
                  if (result is String) {
                    advanced = true;
                    _scrollToImageKey = result;
                  }
                });
              });
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
            future: Future.wait<Object>([dogClasses, apiDogs, _savedDogImages]),
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
              final savedImages = snapshot.data![2] as Map<String, String>;

              var sortedIds = breeds.keys.toList();
              if (!advanced) {
                sortedIds = sortedIds
                    .where((id) => allowedBreeds.contains(breeds[id]))
                    .toList();
              }
              sortedIds.sort((a, b) => breeds[a]!.compareTo(breeds[b]!));

              globalKeys
                ..clear()
                ..addAll(List.generate(sortedIds.length, (_) => GlobalKey()));

              if (_scrollToImageKey != null) {
                int? targetIndex;
                for (var index = 0; index < sortedIds.length; index++) {
                  final breedName = breeds[sortedIds[index]]!;
                  final imageKey = _toSnakeCase(breedName);
                  if (imageKey == _scrollToImageKey) {
                    targetIndex = index;
                    break;
                  }
                }

                if (targetIndex != null) {
                  final int indexToScroll = targetIndex;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      final row = indexToScroll ~/ 2; // crossAxisCount = 2
                      final maxExtent = _scrollController.position.maxScrollExtent;
                      final rows = (sortedIds.length / 2).ceil().clamp(1, 1000000);
                      final double rowHeight = rows > 1
                          ? (maxExtent / (rows - 1))
                          : 0.0;
                      final double offset = (row * rowHeight)
                          .clamp(0.0, maxExtent);

                      _scrollController.animateTo(
                        offset,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                      );
                    }
                  });
                } else {
                  if (kDebugMode) {
                    debugPrint('DogCollectionScreen: no tile found for key $_scrollToImageKey');
                  }
                }

                _scrollToImageKey = null;
              }

              return GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                controller: _scrollController,
                children: [
                  for (var index = 0; index < sortedIds.length; index++)
                    GestureDetector(
                      key: globalKeys[index],
                      onTap: () {
                        final i = sortedIds[index];
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
                        child: () {
                          final i = sortedIds[index];
                          final breedName = breeds[i]!;
                          final imageKey = _toSnakeCase(breedName);
                          final imagePath = savedImages[imageKey];

                          if (imagePath == null) {
                            return Column(
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
                                    breedName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.brown.shade400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.file(
                              File(imagePath),
                              height: 300,
                              fit: BoxFit.cover,
                            ),
                          );
                        }(),
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

    final savedImages = await loadSavedDogImages();
    final imageKey = _toSnakeCase(breedName);
    final imagePath = savedImages[imageKey];

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
      return <String, dynamic>{
        'name': breedName,
        'imagePath': imagePath,
      };
    }

    final result = Map<String, dynamic>.from(match);
    if (imagePath != null) {
      result['imagePath'] = imagePath;
    }
    return result;
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
          '🐕 Info',
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
              return SingleChildScrollView(
                child: Column(
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
                    child: () {
                      final imagePath = data['imagePath'] as String?;
                      if (imagePath != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(
                            File(imagePath),
                            height: 300,
                            fit: BoxFit.cover,
                          ),
                        );
                      }

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.pets,
                            size: 80,
                            color: Colors.brown.shade300,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
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
                      );
                    }(),
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




                  const SizedBox(height: 15),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 15,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          spacing: 15,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                            decoration: BoxDecoration(
                              color: Colors.brown.shade100,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.brown.shade100,
                                width: 15,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              children: [
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
                                    "Height",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Text(
                                  "${data['height']['metric']}cm"
                                ),
                                const SizedBox(height: 15),
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
                                    "Weight",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Text(
                                  "${data['weight']['metric']}kg"
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.brown.shade100,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.brown.shade100,
                                width: 15,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              children: [
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
                                    "Lifespan",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Text(
                                  "${data['life_span']} years"
                                ),
                              ],
                            ),
                          ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.brown.shade100,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.brown.shade100,
                                  width: 15,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Column(
                                children: [
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
                                      "Temperament",
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    data["temperament"],
                                    textAlign: TextAlign.left,
                                    softWrap: true,
                                  ),
                                  const SizedBox(height: 15),
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
                                      "Description",
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    data["description"],
                                    textAlign: TextAlign.left,
                                    softWrap: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  




                  // if (data['description'] != null) ...[
                  //   const SizedBox(height: 16),
                  //   Text(
                  //     data['description'] as String,
                  //     textAlign: TextAlign.justify,
                  //     style: TextStyle(
                  //       fontSize: 16,
                  //       color: Colors.brown.shade800,
                  //     ),
                  //   ),
                  // ],









              
                ],
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}
