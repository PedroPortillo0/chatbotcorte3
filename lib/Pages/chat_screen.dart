import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; //el bot usa el alta voz
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;  //microfono escucha el bot
import 'package:flutter_tts/flutter_tts.dart';  //lee lo que escribio y lo dice en vos alta
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';  //persistencia de datos

// Colores atractivos
const Color primaryColor = Color(0xFF6200EA); // Púrpura intenso: Creatividad y calma
const Color userMessageColor = Color(0xFFBB86FC); // Lila: Calidez y creatividad
const Color botMessageColor = Color(0xFFF5F5F5); // Blanco suave: Neutralidad
const Color actionColor = Color(0xFFFFC107); // Amarillo: Energía y optimismo
const Color backgroundColor = Color(0xFFF3E5F5); // Rosa claro: Alegría y calma

const String apiKey = "AIzaSyCSODG2Bohy9_tSYKXAtrL6s3KEEk-smeI";

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  late final GenerativeModel _model;
  late final ChatSession _chatSession;
  bool _isListening = false;
  bool _isConnected = true;
  String _speechText = '';
  String _selectedLanguage = "en-US";
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
    _chatSession = _model.startChat();

    await _requestMicrophonePermission();
    await _checkInternetConnection();
    await _loadMessages();
  }

  Future<void> _requestMicrophonePermission() async {  //permisos de micro
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _checkInternetConnection() async {
    try {
      final response = await http.get(Uri.parse('https://google.com'));
      if (response.statusCode == 200) {
        setState(() {
          _isConnected = true;
        });
      } else {
        setState(() {
          _isConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
      });
    }
  }

  Future<void> _startListening() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done') {
            _stopListening();
          }
        },
        onError: (val) => print('Error: $val'),
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _speechText = val.recognizedWords;
              _controller.text = _speechText;
            });
          },
          localeId: _selectedLanguage,
        );
      }
    } else {
      print("Permisos de micrófono denegados");
    }
  }

  void _stopListening() {
    setState(() => _isListening = false);
    _speech.stop();
  }

  Future<void> _sendMessage() async {  //muestra el metodo en la aplicacion
    await _checkInternetConnection();
    if (!_isConnected) {
      setState(() {
        _messages.add(ChatMessage(
            text: "No se puede enviar el mensaje. Conéctate a Internet.", isUser: false));
      });
      return;
    }

    if (_controller.text.isNotEmpty) {
      setState(() {
        _messages.add(ChatMessage(text: _controller.text, isUser: true));
      });
      String userMessage = _controller.text;
      _controller.clear();

      setState(() {
        _messages.add(ChatMessage(text: ".....", isUser: false));
      });

      try {
        final response = await _chatSession.sendMessage(Content.text(userMessage));
        final botResponse = response.text ?? "No se recibió respuesta";

        setState(() {
          _messages.removeLast();
          _messages.add(ChatMessage(text: botResponse, isUser: false));
        });

        await _saveMessages();
        await _speak(botResponse);
      } catch (e) {
        setState(() {
          _messages.removeLast();
          _messages.add(ChatMessage(text: "Error: $e", isUser: false));
        });
      }
    }
  }

  Future<void> _speak(String text) async {  // nuevas respuestas del bot
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.speak(text);
  }

  void _changeLanguage(String languageCode) {
    setState(() {
      _selectedLanguage = languageCode;
    });
  }

  Future<void> _saveMessages() async { //aca se hace la persistencia de datos
    final prefs = await SharedPreferences.getInstance();
    List<String> messagesToSave = _messages
        .take(40)
        .map((msg) => "${msg.isUser ? 'user:' : 'bot:'}${msg.text}")
        .toList();
    await prefs.setStringList('chatMessages', messagesToSave);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedMessages = prefs.getStringList('chatMessages');

    if (savedMessages != null) {
      setState(() {
        _messages.clear();
        _messages.addAll(savedMessages.map((msg) {
          bool isUser = msg.startsWith('user:');
          String text = msg.replaceFirst(isUser ? 'user:' : 'bot:', '');
          return ChatMessage(text: text, isUser: isUser);
        }).toList());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chatbot AI', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: Align(
                    alignment: _messages[index].isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Row(
                      mainAxisAlignment: _messages[index].isUser
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        if (!_messages[index].isUser)
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: AssetImage('assets/images/bot.png'),
                          ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _messages[index].isUser
                                  ? userMessageColor
                                  : botMessageColor,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: _messages[index].isUser
                                    ? Radius.circular(16)
                                    : Radius.circular(0),
                                bottomRight: _messages[index].isUser
                                    ? Radius.circular(0)
                                    : Radius.circular(16),
                              ),
                            ),
                            child: Text(
                              _messages[index].text,
                              style: TextStyle(
                                color: _messages[index].isUser
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        if (_messages[index].isUser)
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: AssetImage('assets/images/user.png'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_off : Icons.mic,
                    color: actionColor,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      filled: true,
                      fillColor: botMessageColor,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: actionColor),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _changeLanguage("en-US"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.black,
                  ),
                  child: Text("Inglés (EE.UU.)"),
                ),
                ElevatedButton(
                  onPressed: () => _changeLanguage("es-MX"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.black,
                  ),
                  child: Text("Español (México)"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}
