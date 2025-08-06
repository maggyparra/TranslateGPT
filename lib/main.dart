import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';


//Gemini service that lets me use the Gemini AI
class GeminiService {

  final String apiKey; //custom api key for Gemini API
  final String apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=';

  GeminiService(this.apiKey);

  Future<String> getGeminiResponse(List<Map<String, String>> messages) async {
  final geminiMessages = messages.map((msg) {
    return {
      "role": msg["role"] == "assistant" ? "model" : msg["role"],
      "parts": [
        {"text": msg["content"]}
      ],
    };
  }).toList();

  int retries = 0;
  const maxRetries = 5; // Increased max retries for better handling
  var retryDelay = const Duration(seconds: 2); // Use a variable for the delay

  while (retries < maxRetries) {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": geminiMessages,
          "generationConfig": {
            "temperature": 0.8, // Slightly increased for more creativity
            "maxOutputTokens": 500,
          },
        }),
      );

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        return decodedResponse['candidates'][0]['content']['parts'][0]['text'];
      } else if (response.statusCode == 503 || response.statusCode == 429) {
        // Service unavailable or rate-limited — wait and try again with a longer delay
        print('Gemini overloaded or rate limited, retrying in ${retryDelay.inSeconds} seconds...');
        await Future.delayed(retryDelay);
        retries++;
        retryDelay *= 2; // DOUBLE the delay for the next attempt
      } else {
        print('Gemini API Error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get response from Gemini: ${response.statusCode}');
      }
    } on SocketException catch (e) {
      print('No internet connection: $e');
      throw SocketException('No internet connection');
    } catch (e) {
      print('Unexpected error: $e');
      rethrow;
    }
  }

  throw Exception("Gemini is currently overloaded. Please try again later.");
}

}


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TranslateGPT',
      theme: ThemeData(
       
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      
      home: const TranslateGPT(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 62, 62, 62),
      appBar: null,
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class TranslateGPT extends StatefulWidget {
  const TranslateGPT({super.key});

  @override
  State<TranslateGPT> createState() => _TranslateGPTState();
}

enum LoadingPhase {
  idle,
  loading,
  reasoning,
  translating,
}

class _TranslateGPTState extends State<TranslateGPT> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _contextController = TextEditingController();

  String _sourceLanguage = 'English';
  String _targetLanguage = 'Spanish'; // Initial target language

  // Changed to a list to hold multiple alternate translations, now including a showExplanation flag
  List<Map<String, dynamic>> _alternateTranslations = [];
  String _translationResult = '';
  String _nuanceResult = '';
  String _translationTags = '';
  String _explanationResult = '';
  bool _showExplanation = false;
  bool _isLoading = false;
  LoadingPhase _currentLoadingPhase = LoadingPhase.idle; // New state for loading messages

  late final GeminiService _geminiService;

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService('AIzaSyBdn0SvajUduAWbUdvNXUxamhh4cij6vVE');  // my api key
  }

  void _performTranslation() async {
    FocusScope.of(context).unfocus();
    if (_textController.text.isEmpty) {
      setState(() {
        _translationResult = "Please enter text to translate.";
        _nuanceResult = "";
        _explanationResult = "";
        _alternateTranslations = []; // Clear the list
        _showExplanation = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _currentLoadingPhase = LoadingPhase.loading; // Start loading phase
      _translationResult = '';
      _nuanceResult = "";
      _explanationResult = "";
      _alternateTranslations = []; // Clear the list while loading
      _showExplanation = false;
    });

    String translationInstruction;
if (_targetLanguage == 'Meaning') {
  translationInstruction = """
  Provide a deep understanding of the meaning of the following text, especially diving deeper into Urban Dictionary or similar sources if it uses slang or generational terms. Break down the cultural, regional, or hidden meanings. If the meaning contains profanity or sensitive terms, replace letters with asterisks (e.g., 'f***', 'b*****') but do not remove them entirely. Explain everything in detail.
  """;
} else {
  translationInstruction = """
  Translate the following text from $_sourceLanguage to $_targetLanguage.

  Provide ALL possible interpretations, including both **literal** and **figurative** translations. Explicitly include any direct, word-for-word translations, even if they sound less natural, alongside more idiomatic or contextual translations. And limit translations to as many translations with DISTINCT meanings and avoid repeating similar translations, only use the most word for word translations.

  For each translation (including the main one), you may provide one or more relevant tags from the following list only if it applies and you feel it's VERY necessary to add: **Literal**, **Figurative**, **Idiom**, **Slang**, **Formal**, **Informal**, **Regional**, **Most Common**. Separate multiple tags with a comma.

  Structure the response as follows:

  Translation: [The best or most natural translation.]
  Tags: [e.g., Most Common, Informal]
  Explanation: [ALWAYS explain how this translation fits, including cultural notes, slang, tone, or grammar. If there is no specific cultural or nuanced explanation, state that this is a direct translation.]

  Alternate Translations:
  1. Translation: [First alternate translation]
  - Tags: [Tags from the list above, ONLY if very necessary]
  - Explanation: [Explanation for first alternate]
  2. Translation: [Second alternate translation]
  - Tags: [Tags from the list above, ONLY if very necessary]
  - Explanation: [Explanation for second alternate]
  (Continue numbering for all applicable alternatives. If no alternatives, state 'None' after "Alternate Translations:")


  """;
}

final String fullPrompt = """
    $translationInstruction
    Text: "${_textController.text}"
    ${_contextController.text.isNotEmpty ? "Context: \"${_contextController.text}\"" : ""}

    Please provide a response that ONLY contains the structured sections as specified in the instruction. Do not add any extra text or commentary or parentheses outside of these sections.
""";
   try {
  final response = await _geminiService.getGeminiResponse([
    {"role": "user", "content": fullPrompt}
  ]);
  _parseAndDisplayResponse(response);
} on SocketException {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Please check your internet connection and try again...', style: TextStyle(color: Colors.white, fontSize: 18),),
      backgroundColor: Colors.redAccent,
    ),
  );
} catch (e) {
  setState(() {
    _translationResult = "Error: $e";
    
    _nuanceResult = "";
    _explanationResult = "";
    _alternateTranslations = [];
    _showExplanation = false;
  });
} finally { // Ensure loading state is reset even on error
    if (mounted) {
      setState(() {
        _isLoading = false;
        _currentLoadingPhase = LoadingPhase.idle; // Reset phase
      });
    }
  }
}

void _parseAndDisplayResponse(String response) {
  // Regex for main Translation and Explanation
  final translationRegex = RegExp(r'Translation: (.*?)\n', dotAll: true);
  final translationTagsRegex = RegExp(r'Tags: (.*?)\n', dotAll: true);
  final explanationRegex = RegExp(r'Explanation: (.*?)\n', dotAll: true);
  final nuanceRegex = RegExp(r'Nuances: (.*?)$', dotAll: true); // Matches to end of string for nuance

  // Regex for Alternate Translations section
  final alternateSectionRegex = RegExp(r'Alternate Translations:\n(.*?)(?=\nNuances:|$)', dotAll: true);
  // Regex for individual numbered translations within the alternate section
  final individualAlternateRegex = RegExp(r'(\d+)\. Translation: (.*?)\n- Tags: (.*?)\n- Explanation: (.*?)(?=\n\d+\. Translation:|\nAlternate Translations:|\nNuances:|$)', dotAll: true);

  final translationMatch = translationRegex.firstMatch(response);
  final translationTagsMatch = translationTagsRegex.firstMatch(response);
  final explanationMatch = explanationRegex.firstMatch(response);
  final nuanceMatch = nuanceRegex.firstMatch(response);
  final alternateSectionMatch = alternateSectionRegex.firstMatch(response);

  setState(() {
    _translationResult = translationMatch?.group(1)?.trim() ?? "No translation found.";
    _translationTags = translationTagsMatch?.group(1)?.trim() ?? "No tags found.";
    _explanationResult = explanationMatch?.group(1)?.trim() ?? "No explanation provided.";
    _nuanceResult = nuanceMatch?.group(1)?.trim() ?? "None";

    _alternateTranslations = []; // Clear previous alternate translations

    if (alternateSectionMatch != null) {
      final String alternateContent = alternateSectionMatch.group(1)?.trim() ?? '';
      if (alternateContent.toLowerCase() != 'none' && alternateContent.isNotEmpty) {
        // Find all individual alternate translations
        final Iterable<RegExpMatch> matches = individualAlternateRegex.allMatches(alternateContent);
        for (final match in matches) {
          final String altTranslation = match.group(2)?.trim() ?? '';
          final String altTags = match.group(3)?.trim() ?? '';
          final String altExplanation = match.group(4)?.trim() ?? '';
          if (altTranslation.isNotEmpty) {
            _alternateTranslations.add({
              'translation': altTranslation,
              'tags': altTags,
              'explanation': altExplanation,
              'showExplanation': false, // Initialize to false for each alternate
            });
          }
        }
      }
    }

    _showExplanation = false; // Reset main explanation visibility
  });
}


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
    behavior: HitTestBehavior.opaque, // So even blank space registers taps
    onTap: () {
      FocusScope.of(context).unfocus(); // Hides the keyboard
    },
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 40, 40, 40),  
        appBar: AppBar(
        title: Image.asset('assets/TranslateGPTWord.png', height: 190, width: 250), // Centered image in the app bar
        backgroundColor: const Color.fromARGB(255, 35, 35, 35), // Changed AppBar background to black
      ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch, // Added to stretch children horizontally
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _sourceLanguage,
                      isExpanded: true, // ✨ IMPORTANT: Ensures the dropdown button itself expands
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color.fromARGB(255, 81, 80, 80),
                       
                        labelStyle: TextStyle(color: Colors.white, fontSize: 18), // Added to make label visible on black
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder( // Added to make border visible
                          borderSide: BorderSide(color: Color.fromARGB(255, 81, 80, 80))
                        ),
                        focusedBorder: OutlineInputBorder( // Added for focus state
                          borderSide: BorderSide(color: Color.fromARGB(255, 81, 80, 80))
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), // Adjusted vertical padding
                      ),
                      dropdownColor: Colors.black87, // Make dropdown menu dark
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), // Make dropdown item text visible
                      items: <String>[
                        'English', 'Spanish', 'French', 'German', 'Italian',
                        'Japanese', 'Chinese (Simplified)', 'Korean', 'Meaning' // Added 'Meaning'
                      ].map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          // No need for Expanded around Text in item here, as isExpanded on the parent handles it better
                          child: Text(
                            value,
                            overflow: TextOverflow.ellipsis, // Keep ellipsis for long text in menu
                            style: const TextStyle(color: Colors.white), // Make selected item text visible
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _sourceLanguage = newValue!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _targetLanguage,
                      isExpanded: true, // ✨ IMPORTANT: Ensures the dropdown button itself expands
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color.fromARGB(255, 81, 80, 80),
             
                        labelStyle: TextStyle(color: Colors.white, fontSize: 18),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder( // Added to make border visible
                          borderSide: BorderSide(color:Color.fromARGB(255, 81, 80, 80),) /// when clicked
                        ),
                        focusedBorder: OutlineInputBorder( // Added for focus state
                          borderSide: BorderSide(color: Color.fromARGB(255, 81, 80, 80),)
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), // Adjusted vertical padding
                      ),
                      dropdownColor: Colors.black87, // Make dropdown menu dark
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), // Make dropdown item text visible
                      items: <String>[
                        'Spanish', 'English', 'French', 'German', 'Italian',
                        'Japanese', 'Chinese (Simplified)', 'Korean', 'Meaning' // Added 'Meaning'
                      ].map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          // No need for Expanded around Text in item here, as isExpanded on the parent handles it better
                          child: Text(
                            value,
                            overflow: TextOverflow.ellipsis, // Keep ellipsis for long text in menu
                            style: const TextStyle(color: Colors.white), // Make selected item text visible
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _targetLanguage = newValue!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
      
               Container(
                constraints: const BoxConstraints(minHeight: 50), // Minimum height to make it visible
                child: TextField(
                  controller: _textController,
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: 'Enter text',
                    hintStyle: TextStyle(fontSize: 26, color: Color.fromARGB(255, 89, 88, 88)),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color.fromARGB(255, 81, 80, 80))
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color.fromARGB(255, 81, 80, 80))
                    ),
                    fillColor: Color.fromARGB(26, 27, 17, 17),
                    filled: true,
                    prefixIcon: null,
                  ),
                  maxLines: null, // Allow for multiple lines
                  expands: false, // Prevent the TextField from expanding to fill available space
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(color: Colors.white, fontSize: 26),
                ),
              ),
              const SizedBox(height: 16),
      
              Container(
                constraints: const BoxConstraints(minHeight: 15),
                child: TextField(
                  controller: _contextController,
                  decoration: InputDecoration(
                    hintText: 'Optional: Add context (e.g., "formal setting", "casual conversation")',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: const OutlineInputBorder(),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color.fromARGB(137, 33, 28, 28))
                    ),
                    focusedBorder: const OutlineInputBorder( 
                      borderSide: BorderSide(color: Color.fromARGB(255, 35, 27, 27))
                    ),
                    fillColor: Colors.white10, 
                    filled: true,
                    prefixIcon: const Icon(Icons.info_outline, color: Colors.white54), 
                  ),
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white), 
                ),
              ),
              const SizedBox(height: 16),
      
         ElevatedButton(
  onPressed: _isLoading ? null : _performTranslation,
  style: ButtonStyle(
    fixedSize: WidgetStateProperty.all(const Size(130, 50)),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return const Color.fromARGB(255, 90, 90, 90);
        }
        if (states.contains(WidgetState.disabled)) {
          return const Color.fromARGB(255, 90, 90, 90);
        }
        return const Color.fromARGB(255, 66, 66, 66);
      },
    ),
    foregroundColor: WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return const Color.fromARGB(255, 66, 66, 66);
        }
        if (states.contains(WidgetState.disabled)) {
          return Colors.white54;
        }
        return Colors.white;
      },
    ),
  ),
  child: const Text('Translate', style: TextStyle(fontSize: 18)),
),
const SizedBox(height: 16),

/// 👇 Show loading spinner or result
if (_isLoading)
  Column( // Use a Column to center the text and potentially a spinner if desired
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const CircularProgressIndicator( // Keep a small spinner for visual feedback
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        strokeWidth: 3,
      ),
      const SizedBox(height: 10),
      Text(
        _currentLoadingPhase == LoadingPhase.loading
            ? 'Loading...'
            : _currentLoadingPhase == LoadingPhase.reasoning
                ? 'Reasoning...'
                : 'Translating...',
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
       // Add some space
      
    ],
  )
else if (_translationResult.isNotEmpty)
  Expanded(
    flex: 2,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Translation:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21, color: Color.fromARGB(255, 160, 158, 158)),
                ),
        
                Text(
                  _translationResult,
                  textAlign: TextAlign.left, // Added for left alignment
                  style: const TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),
                    fontWeight: FontWeight.bold,
                    fontSize: 23,
                  ),
                ),
                SizedBox(height: 8),
                if (_translationTags.isNotEmpty) 
                  _TagChip(tags: _translationTags),
                // Button to toggle main explanation visibility
                if (_explanationResult.isNotEmpty)
                ElevatedButton(
  onPressed: () {
    setState(() {
      _showExplanation = !_showExplanation;
    });
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color.fromARGB(0, 66, 66, 66),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    foregroundColor: Colors.white,
    elevation: 0,
    padding: EdgeInsets.zero,
    minimumSize: Size.zero,
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min, // Make the row as small as its children
    children: [
      Text(
        _showExplanation ? 'Hide Explanation' : 'Show Explanation',
        style: const TextStyle(
          decoration: TextDecoration.underline, color: Color.fromARGB(173, 244, 244, 244),
        ),
      ),
      const SizedBox(width: 5), // Adds a little space between the text and icon
      Icon(
        _showExplanation ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        color: Colors.white, size:25, 
      ),
    ],
  ),
),

              // Conditionally show the main explanation text
              if (_showExplanation && _explanationResult.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0), // Reduced top padding
                  child: Text(
                    _explanationResult,
                    style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
                  ),
                ),

              // Section for Alternate Translations - now always visible if content exists
              if (_alternateTranslations.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Removed "Alternate Translations:" heading as each will be numbered
                    // Removed the "Show/Hide Alternates" button

                    // Loop through and display each alternate translation
                    ..._alternateTranslations.asMap().entries.map((entry) {
                      int index = entry.key;
                      Map<String, dynamic> alt = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20), // Spacing between each translation
                          Text(
                            '${index + 2}. ${alt['translation']!}', // Numbering starts from 2
                            style: const TextStyle(
                              color: Color.fromARGB(255, 255, 255, 255),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          if (alt['tags']!.isNotEmpty)
                            _TagChip(tags: alt['tags']!),
                       // Reduced SizedBox height
                          // Button to toggle individual alternate explanation visibility
                          if (alt['explanation']!.isNotEmpty)
                          ElevatedButton(
  onPressed: () {
    setState(() {
      // Toggle the showExplanation for this specific alternate
      _alternateTranslations[index]['showExplanation'] = !alt['showExplanation'];
    });
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: EdgeInsets.zero,
    minimumSize: Size.zero, 
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        alt['showExplanation'] ? 'Hide Explanation' : 'Show Explanation',
        style: const TextStyle(
          decoration: TextDecoration.underline, color: Color.fromARGB(173, 244, 244, 244),
        ),
      ),
      const SizedBox(width: 8),
      Icon(
        alt['showExplanation'] ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        color: Colors.white,
        size: 18,
      ),
    ],
  ),
),
                          // Conditionally show individual alternate explanation
                          if (alt['showExplanation'])
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0), // Reduced top padding
                              child: Text(
                                alt['explanation']!,
                                style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
                              ),
                            ),
                        ],
                      );
                    }).toList(),
                  ],
                ),

              // Nuances section
              if (_nuanceResult.isNotEmpty && _nuanceResult.toLowerCase() != 'none')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      'Nuances:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21, color: Color.fromARGB(255, 160, 158, 158)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nuanceResult,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),

            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _contextController.dispose();
    super.dispose();
  }
}

class _TagChip extends StatelessWidget {
  final String tags;

  const _TagChip({super.key, required this.tags});

  Color _darkenColor(Color color, double factor) { // this method darkens a color by the given factor
  final hsl = HSLColor.fromColor(color);
  final darkerHsl = hsl.withLightness(hsl.lightness * (1 - factor));
  return darkerHsl.toColor();
}

  Color _getColorForTag(String tag) {
    switch (tag.trim().toLowerCase()) {
      case 'most common':
        return Colors.green;
      case 'literal':
        return Colors.red[900]!;
      case 'idiom':
        return Colors.orange[800]!;
      case 'slang':
        return Colors.yellow[700]!;
      case 'formal':
        return Colors.blue[900]!;
      case 'informal':
        return Colors.teal;
      case 'regional':
        return Colors.brown[800]!;
      case 'uncommon':
        return Colors.deepPurple[300]!;
      default:
        return Colors.grey;
    }
  }
@override
Widget build(BuildContext context) {
  if (tags.isEmpty || tags == "No tags found.") {
    return const SizedBox.shrink();
  }

  final List<String> tagList = tags.split(',').map((tag) => tag.trim()).toList();

  return Wrap(
    spacing: 5.0,
    runSpacing: 5.0,
    children: tagList.map((tag) {
      return ElevatedButton(
  onPressed: null, // Makes the button unclickable
  style: ElevatedButton.styleFrom(
    backgroundColor: _getColorForTag(tag),
    disabledBackgroundColor: _getColorForTag(tag),
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.0),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6.0),
      side: BorderSide(
        color: _darkenColor(_getColorForTag(tag), 0.2), // Darken the background color
        width: 1.0, // Adjust the border width as needed
      ),
    ),
  ),
  child: Text(
    tag,
    style: const TextStyle(color: Colors.white, fontSize: 15),
  ),
);
    }).toList(),
  );
}
}