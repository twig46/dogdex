import 'package:encrypt/encrypt.dart' show RSAKeyParser;
import 'package:pointycastle/asymmetric/api.dart';
import 'dart:io';
//import 'dart:developer';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<RSAPublicKey> loadPublicKey() async {
  final String pemString = await rootBundle.loadString(
    'assets/keys/public_key.pem',
  );
  final parser = RSAKeyParser();
  final RSAPublicKey publicKey = parser.parse(pemString) as RSAPublicKey;
  return publicKey;
}

String apiUrl = "https://dog-api.tobyv.dev";

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

Future<Map<String, Set<String>>> loadDogNamesByCommonality() async {
  final jsonString = await rootBundle.loadString('assets/dog_names.json');
  final Map<String, dynamic> data = json.decode(jsonString);
  return data.map(
    (key, value) =>
        MapEntry(key, (value as List<dynamic>).cast<String>().toSet()),
  );
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

final Future<Map<int, String>> dogClasses = loadLabels();
final Future<Map<String, Set<String>>> dogNamesByCommonality =
    loadDogNamesByCommonality();

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
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return _HorizontalWidthScale(child: child);
      },
      home: const DogCollectionScreen(showOnlySaved: false),
    );
  }
}

class _HorizontalWidthScale extends StatelessWidget {
  const _HorizontalWidthScale({required this.child});

  final Widget child;
  static const double _designWidth = 430;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return child;
        }

        final width = constraints.maxWidth;
        final scaleX = width > _designWidth ? width / _designWidth : 1.0;

        if (scaleX <= 1.0) {
          return child;
        }

        final scaledChildHeight = constraints.maxHeight / scaleX;

        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _designWidth,
                height: scaledChildHeight,
                child: child,
              ),
            ),
          ),
        );
      },
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
  bool _analyzing = false;
  bool _checking = true;
  bool _correct = false;
  bool _set = false;
  final ImagePicker _picker = ImagePicker();
  bool _serverUp = false;
  String? breed;
  double? confidence;
  List<DropdownMenuEntry<String>> dogClassOptions = [];
  List<String> get dogClassNames =>
      dogClassOptions.map((entry) => entry.value).toList(growable: false);

  Future<void> _loadDogClassOptions() async {
    final classes = await dogClasses;
    final breedNames = classes.values.toList()..sort();

    if (!mounted) return;

    setState(() {
      dogClassOptions = breedNames
          .map((name) => DropdownMenuEntry<String>(value: name, label: name))
          .toList();
    });
  }

  @override
  void initState() {
    super.initState();
    checkServer();
  }

  Future<void> _showDogDialog(BuildContext context) async {
    if (!mounted) return;

    String? newBreed = breed;
    var loading = dogClassOptions.isEmpty;
    var loadStarted = false;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && !loadStarted) {
              loadStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  await Future<void>.delayed(const Duration(milliseconds: 180));
                  await _loadDogClassOptions();
                } finally {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    loading = false;
                  });
                }
              });
            }

            return AlertDialog(
              title: Text("Breed?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) ...[
                    CircularProgressIndicator(color: Colors.brown.shade300),
                    const SizedBox(height: 12),
                    const Text("Loading breeds..."),
                  ] else ...[
                    Text(
                      "If you are unhappy with our guess you can change the estimated breed here",
                    ),
                    const SizedBox(height: 15),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.brown.shade200,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.brown.shade200, width: 5),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(left: 10, right: 5),
                        child: DropdownMenu<String>(
                          inputDecorationTheme: const InputDecorationTheme(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          width: 260,
                          dropdownMenuEntries: dogClassOptions,
                          initialSelection: dogClassNames.contains(newBreed)
                              ? newBreed
                              : null,
                          onSelected: (String? value) {
                            if (value == null) return;
                            setState(() {
                              newBreed = value;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text("Cancel"),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => {
                          setState(() {
                            _dogImage = null;
                            _set = false;
                            _correct = false;
                          }),
                          Navigator.pop(dialogContext),
                        },
                  child: Text("Don't add"),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => {
                          setState(() {
                            breed = newBreed;
                            _set = true;
                          }),
                          Navigator.pop(dialogContext),
                        },
                  child: Text("Set"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _dogImage = File(image.path);
        _analyzing = true;
      });
      final response = await _predictDog(image.path);
      if (kDebugMode) {
        debugPrint(response.body);
      }
      if (response.statusCode != 200) {
        setState(() {
          _analyzing = false;
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded["predictions"] is! List ||
          (decoded["predictions"] as List).isEmpty) {
        setState(() {
          _analyzing = false;
        });
        return;
      }

      final top =
          (decoded["predictions"] as List).first as Map<String, dynamic>;
      setState(() {
        _analyzing = false;
        breed = top["breed"];
        confidence = (top["probability"] * 100);
        if (kDebugMode) {
          debugPrint(
            "$breed with ${confidence?.toStringAsFixed(1)}% confidence",
          );
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
      _checking = false;
      _serverUp = response.statusCode != 502;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Analyze',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
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
                if (!_serverUp) ...[
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
                      _checking ? "Checking for server" : "Cannot reach server",
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
                if (_serverUp && !_analyzing) ...[
                  if (_dogImage == null) ...[
                    Row(
                      spacing: 15,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera),
                          label: Text('Camera'),
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
                        FilledButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo),
                          label: Text('Gallery'),
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
                    ),
                  ] else ...[
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
                        "Identified!",
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
                          _set ? 'You are 100% certain' : 'We are ${(confidence as double).toStringAsFixed(1)}% certain',
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
                    if (!_correct) ...[
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
                          "Is this correct?",
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
                      Row(
                        spacing: 15,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () async {
                              setState(() {
                                _correct = true;
                              });
                            },
                            icon: const Icon(Icons.done),
                            label: Text("Yes"),
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
                          FilledButton.icon(
                            onPressed: () {
                              _showDogDialog(context);
                            },
                            icon: const Icon(Icons.close),
                            label: Text("No"),
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
                      ),
                    ] else ...[
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
                          "Add to your collection?",
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
                      Row(
                        spacing: 15,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () async {
                              if (_dogImage == null || breed == null) {
                                return;
                              }
                              final navigator = Navigator.of(context);
                              final imageKey = _toSnakeCase(breed!);
                              await saveImage(_dogImage!, imageKey);
                              if (!mounted) return;
                              navigator.pop(imageKey);
                            },
                            icon: const Icon(Icons.done),
                            label: Text("Yes"),
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
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _dogImage = null;
                                _set = false;
                                _correct = false;
                              });
                            },
                            icon: const Icon(Icons.close),
                            label: Text("No"),
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
                      ),
                    ],
                    const SizedBox(height: 30),
                    Text(
                      "DogDex identification is by no means 100% accurate.\nIf information it provides looks innacurate it probably is.\nAlways make sure to double check",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ] else ...[
                  if (_analyzing) ...[
                    const SizedBox(height: 10),
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
                        "Analyzing",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DogCollectionScreen extends StatefulWidget {
  final bool showOnlySaved;
  const DogCollectionScreen({super.key, required this.showOnlySaved});

  @override
  State<DogCollectionScreen> createState() => _DogCollectionScreenState();
}

class _DogCollectionScreenState extends State<DogCollectionScreen> {
  String commonality = "very_common";
  late bool showOnlySaved;
  late Future<Map<String, String>> _savedDogImages;
  final List<GlobalKey> globalKeys = [];
  String? _scrollToImageKey;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _savedDogImages = loadSavedDogImages();
    showOnlySaved = widget.showOnlySaved;
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        commonality = prefs.getString('commonality') ?? "very_common";
      });
    });
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
        leading: !showOnlySaved
            ? IconButton(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      )
                      .then((result) {
                        SharedPreferences.getInstance().then((prefs) {
                          if (!mounted) return;
                          setState(() {
                            commonality =
                                prefs.getString('commonality') ?? "very_common";
                          });
                        });
                      });
                },
                icon: Icon(Icons.settings),
              )
            : null,
        actions: <Widget>[
          // IconButton(
          //   onPressed: () {
          //     setState(() {
          //       advanced = !advanced;
          //     });
          //   },
          //   icon: Icon(advanced ? Icons.check_circle : Icons.circle_outlined),
          // ),
          IconButton(
            onPressed: () {
              if (showOnlySaved) {
                Navigator.of(context).pop();
                return;
              }

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      const DogCollectionScreen(showOnlySaved: true),
                ),
              );
            },
            icon: Icon(showOnlySaved ? Icons.photo : Icons.photo_outlined),
          ),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 0),
        child: SizedBox(
          height: 80,
          width: 80,
          child: FloatingActionButton(
            shape: CircleBorder(),
            backgroundColor: Colors.brown.shade500,
            foregroundColor: Colors.brown.shade50,
            child: const Icon(Icons.camera_alt, size: 35),
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => const DogUploadScreen(),
                    ),
                  )
                  .then((result) {
                    SharedPreferences.getInstance().then((prefs) {
                      if (!mounted) return;
                      setState(() {
                        _savedDogImages = loadSavedDogImages();
                        if (result is String) {
                          _scrollToImageKey = result;
                        }
                      });
                    });
                  });
            },
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: FutureBuilder<List<Object>>(
            future: Future.wait<Object>([
              dogClasses,
              dogNamesByCommonality,
              _savedDogImages,
            ]),
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
              final commonalityMap =
                  snapshot.data![1] as Map<String, Set<String>>;
              final savedImages = snapshot.data![2] as Map<String, String>;

              Set<String> allowedForCommonality(String selectedCommonality) {
                const order = ["very_common", "common", "rarer", "hyper_niche"];
                final maxIndex = order.indexOf(selectedCommonality);
                final clampedMaxIndex = maxIndex >= 0 ? maxIndex : 0;
                final allowed = <String>{};
                for (var i = 0; i <= clampedMaxIndex; i++) {
                  allowed.addAll(commonalityMap[order[i]] ?? const <String>{});
                }
                return allowed;
              }

              var sortedIds = breeds.keys.toList();
              final pendingScrollKey = _scrollToImageKey;
              final allowedBreeds = allowedForCommonality(commonality);
              sortedIds = sortedIds.where((id) {
                final breedName = breeds[id];
                if (breedName == null) return false;

                if (showOnlySaved) {
                  return true;
                }

                if (allowedBreeds.contains(breedName)) {
                  return true;
                }

                if (pendingScrollKey != null &&
                    _toSnakeCase(breedName) == pendingScrollKey) {
                  return true;
                }

                return false;
              }).toList();

              if (showOnlySaved) {
                sortedIds = sortedIds
                    .where(
                      (id) =>
                          savedImages.containsKey(_toSnakeCase(breeds[id]!)),
                    )
                    .toList();
              }
              sortedIds.sort((a, b) => breeds[a]!.compareTo(breeds[b]!));

              globalKeys
                ..clear()
                ..addAll(List.generate(sortedIds.length, (_) => GlobalKey()));

              if (pendingScrollKey != null) {
                int? targetIndex;
                for (var index = 0; index < sortedIds.length; index++) {
                  final breedName = breeds[sortedIds[index]]!;
                  final imageKey = _toSnakeCase(breedName);
                  if (imageKey == pendingScrollKey) {
                    targetIndex = index;
                    break;
                  }
                }

                if (targetIndex != null) {
                  final int indexToScroll = targetIndex;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    void tryScroll(int attemptsRemaining) {
                      if (!mounted || !_scrollController.hasClients) return;
                      if (indexToScroll >= globalKeys.length) return;

                      final targetContext =
                          globalKeys[indexToScroll].currentContext;
                      if (targetContext != null) {
                        Scrollable.ensureVisible(
                          targetContext,
                          duration: const Duration(milliseconds: 500),
                          alignment: 0.2,
                          curve: Curves.easeInOut,
                        );
                        return;
                      }

                      if (attemptsRemaining <= 0) {
                        if (kDebugMode) {
                          debugPrint(
                            'DogCollectionScreen: tile context unavailable for index $indexToScroll',
                          );
                        }
                        return;
                      }

                      final maxExtent =
                          _scrollController.position.maxScrollExtent;
                      if (maxExtent <= 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          tryScroll(attemptsRemaining - 1);
                        });
                        return;
                      }

                      final denominator = sortedIds.length <= 1
                          ? 1
                          : sortedIds.length - 1;
                      final approximateOffset =
                          (maxExtent * (indexToScroll / denominator))
                              .clamp(0.0, maxExtent)
                              .toDouble();

                      _scrollController
                          .animateTo(
                            approximateOffset,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          )
                          .then((_) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              tryScroll(attemptsRemaining - 1);
                            });
                          });
                    }

                    tryScroll(4);
                  });
                } else {
                  if (kDebugMode) {
                    debugPrint(
                      'DogCollectionScreen: no tile found for key $pendingScrollKey',
                    );
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
                                  size: 70,
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
  bool imperial = false;

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
      return <String, dynamic>{'name': breedName, 'imagePath': imagePath};
    }

    final result = Map<String, dynamic>.from(match);
    if (imagePath != null) {
      result['imagePath'] = imagePath;
    }
    return result;
  }

  List<String> measurementParser(Map<String, dynamic> data, String field) {
    String value = data[field][imperial ? 'imperial' : 'metric'];
    final unit = imperial
        ? (field == 'height' ? 'in' : 'lbs')
        : (field == 'height' ? 'cm' : 'kg');
    if (value.contains("Male")) {
      return value.split(";").map((w) => "$w$unit").toList();
    }
    return ["$value$unit"];
  }

  @override
  void initState() {
    super.initState();
    dogInfo = _getInfo();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        imperial = prefs.getBool('imperial') ?? false;
      });
    });
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
                clipBehavior: Clip.none,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
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

                    if (data["description"] != null) ...[
                      const SizedBox(height: 30),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.brown.shade200,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.brown.shade200,
                              spreadRadius: 15,
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 15,
                              children: [
                                Expanded(
                                  flex: 43,
                                  child: Column(
                                    spacing: 15,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade100,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: Colors.brown.shade100,
                                            width: 15,
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.brown.shade400,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                "Height",
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ),
                                            for (String h in measurementParser(
                                              data,
                                              'height',
                                            ))
                                              Text(h),
                                            const SizedBox(height: 15),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.brown.shade400,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                "Weight",
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ),
                                            for (String w in measurementParser(
                                              data,
                                              'weight',
                                            ))
                                              Text(w),
                                          ],
                                        ),
                                      ),
                                      // Container(
                                      //   decoration: BoxDecoration(
                                      //     color: Colors.brown.shade100,
                                      //     borderRadius: BorderRadius.circular(15),
                                      //     border: Border.all(
                                      //       color: Colors.brown.shade100,
                                      //       width: 15,
                                      //       style: BorderStyle.solid,
                                      //     ),
                                      //   ),
                                      //   child: Column(
                                      //     children: [
                                      //       Row(
                                      //         mainAxisAlignment: MainAxisAlignment.center,
                                      //         children: [
                                      //           SizedBox(
                                      //             width: 32,
                                      //             child: Text(
                                      //               "in",
                                      //               textAlign: TextAlign.center,
                                      //               style: TextStyle(
                                      //                 fontWeight: FontWeight(500),
                                      //                 color: Colors.brown.shade500
                                      //               ),
                                      //             ),
                                      //           ),
                                      //           Switch(
                                      //             activeThumbColor: Colors.brown.shade300,
                                      //             value: !imperial,
                                      //             onChanged: (bool value) async {
                                      //               final prefs = await SharedPreferences.getInstance();
                                      //               setState(() {
                                      //                 imperial = !value;
                                      //               });
                                      //               await prefs.setBool('imperial', imperial);
                                      //             }
                                      //           ),
                                      //           SizedBox(
                                      //             width: 32,
                                      //             child: Text(
                                      //               "cm",
                                      //               textAlign: TextAlign.center,
                                      //               style: TextStyle(
                                      //                 fontWeight: FontWeight(500),
                                      //                 color: Colors.brown.shade500
                                      //               ),
                                      //             ),
                                      //           ),
                                      //         ],
                                      //       )
                                      //     ],
                                      //   ),
                                      // ),
                                      if (data["life_span"] != null) ...[
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.brown.shade100,
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                            border: Border.all(
                                              color: Colors.brown.shade100,
                                              width: 15,
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.brown.shade400,
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                ),
                                                child: Text(
                                                  "Lifespan",
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    letterSpacing: 2,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                "${data['life_span']} years",
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 55,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade100,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: Colors.brown.shade100,
                                            width: 15,
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.brown.shade400,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                "Temperament",
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.brown.shade400,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                "Description",
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
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
                            const SizedBox(height: 15),
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
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.brown.shade400,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      "History",
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    data["history"],
                                    textAlign: TextAlign.left,
                                    softWrap: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 15),
                      Text(
                        "Sorry, we currently don't have any\ninformation about this dog.\nFeel free to look it up.",
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 30),
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool imperial = false;
  String commonality = "very_common";

  final List<DropdownMenuItem<String>> commonalityOptions = [
    DropdownMenuItem<String>(value: "very_common", child: Text("Very Common")),
    DropdownMenuItem<String>(value: "common", child: Text("Common")),
    DropdownMenuItem<String>(value: "rarer", child: Text("Rarer")),
    DropdownMenuItem<String>(value: "hyper_niche", child: Text("Hyper Niche")),
  ];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        imperial = prefs.getBool('imperial') ?? false;
        commonality = prefs.getString('commonality') ?? "very_common";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '🐕 Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          SizedBox(
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: () => {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DangerScreen(),
                  ),
                )
              },
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
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
                    child: Image.asset(
                      "assets/icon.png",
                      height: 300,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Winner of \"Cutest Dog of All Time\" Award, Kora",
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 15),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.brown.shade200,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(width: 15, color: Colors.brown.shade200),
                  ),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.brown.shade100,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.brown.shade100,
                            width: 15,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 75,
                              child: Text(
                                imperial ? "Imperial" : "Metric",
                                style: TextStyle(
                                  fontWeight: FontWeight(500),
                                  color: Colors.brown.shade700,
                                ),
                              ),
                            ),
                            Switch(
                              activeThumbColor: Colors.brown.shade300,
                              value: !imperial,
                              onChanged: (bool value) async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                setState(() {
                                  imperial = !value;
                                });
                                await prefs.setBool('imperial', imperial);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.brown.shade100,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.brown.shade100,
                            width: 15,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                "Dog Commonality",
                                style: TextStyle(
                                  fontWeight: FontWeight(500),
                                  color: Colors.brown.shade700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.brown.shade200,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.brown.shade200,
                                    width: 5,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.only(left: 10, right: 5),
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    items: commonalityOptions,
                                    value: commonality,
                                    underline: Container(height: 0),
                                    onChanged: (String? value) async {
                                      if (value == null) return;
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      setState(() {
                                        commonality = value;
                                      });
                                      await prefs.setString(
                                        'commonality',
                                        commonality,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.brown.shade100,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.brown.shade100,
                            width: 15,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Column(
                              children: [
                                Text(
                                  "Found a bug or have a really cool\nidea for a feature?\nSubmit it on my GitHub",
                                  softWrap: true,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight(500),
                                    color: Colors.brown.shade700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                FilledButton.icon(
                                  onPressed: () async {
                                    await _launchURL(
                                      "https://github.com/twig46/dogdex/issues/new/choose",
                                    );
                                  },
                                  icon: const Icon(Icons.bug_report),
                                  label: Text('Submit an Issue'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.brown.shade600,
                                    textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DangerScreen extends StatefulWidget {
  const DangerScreen({super.key});

  @override
  State<DangerScreen> createState() => _DangerScreenState();
}

class _DangerScreenState extends State<DangerScreen> {
  final TextEditingController _urlController = TextEditingController();
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown.shade50,
      appBar: AppBar(
        title: const Text(
          '⚠️ Danger',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.brown.shade300,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Enter API URL',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade800,
                  ),
                ),
                Text("(Do not set if you don't know what this means)"),
                const SizedBox(height: 15),
                TextField(
                  controller: _urlController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'API URL',
                    hintText: 'Enter your new API URL',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.lock),
                    filled: true,
                    fillColor: Colors.brown.shade100,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (){apiUrl = _urlController.text;},
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.brown.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.brown.shade300,
                    ),
                    child: const Text(
                      'Set',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
