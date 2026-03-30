import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';
import 'math_puzzle.dart';
import 'ad_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  bool isFavorite;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isFavorite = false,
  });
}

class ChatBotHomePage extends StatefulWidget {
  final double fontScale;
  final ThemeMode currentThemeMode;
  final Future<void> Function(ThemeMode mode, double fontScale) onApplySettings;

  const ChatBotHomePage({
    super.key,
    required this.fontScale,
    required this.currentThemeMode,
    required this.onApplySettings,
  });

  @override
  State<ChatBotHomePage> createState() => _ChatBotHomePageState();
}

class _ChatBotHomePageState extends State<ChatBotHomePage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _showTimestamps = true;
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
    // Load first interstitial ad
    AdService().loadInterstitialAd();
  }

  String _buildExportText() {
    final buffer = StringBuffer();
    for (final m in _messages) {
      final who = m.isUser ? 'You' : 'AI';
      final time = _formatTime(m.timestamp);
      buffer.writeln('[$time] $who: ${m.text}');
    }
    return buffer.toString().trim();
  }

  Future<void> _openSettings() async {
    final exportText = _buildExportText();
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          exportText: exportText,
          initialThemeMode: widget.currentThemeMode,
          initialFontScale: widget.fontScale,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      final themeStr = result['theme'] as String? ?? 'system';
      final scale = (result['fontScale'] as double?) ?? widget.fontScale;
      final ThemeMode mode = themeStr == 'light'
          ? ThemeMode.light
          : themeStr == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system;
      await widget.onApplySettings(mode, scale);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings applied')),
      );
      setState(() {}); // trigger rebuild to reflect fontScale usage
    }
  }

  Future<void> _contactUs() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'abcd@gmail.com',
      queryParameters: {
        'subject': 'AI:Ask Anything - Support',
      },
    );
    try {
      final can = await canLaunchUrl(uri);
      if (can) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open email: $e')),
      );
    }
  }

  void _addWelcomeMessage() {
    // Welcome message removed as requested
  }

  Future<String> _getChatGPTResponse(String question) async {
    try {
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
        throw Exception('OpenAI API key not configured');
      }

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'user',
              'content': question,
            }
          ],
          'max_tokens': 30,
          'temperature': 0.7,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        throw Exception('ChatGPT API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('ChatGPT failed: $e');
    }
  }

  String _getOfflineResponse(String question) {
    final lowerQuestion = question.toLowerCase();
    
    if (lowerQuestion.contains('flutter')) {
      return 'Flutter is an open-source UI software development toolkit created by Google. It is used to develop cross-platform applications for Android, iOS, Linux, macOS, Windows, Google Fuchsia, and the web from a single codebase. Flutter was first described in 2015 and was released in May 2017. Flutter uses the Dart programming language, which was also developed by Google. The framework provides a rich set of pre-designed widgets that follow specific design languages. For Android, it follows Material Design, and for iOS, it follows Cupertino. Flutter applications are built using a reactive framework, which takes inspiration from React. The central idea is that you build your UI out of widgets. Widgets describe what their view should look like given their current configuration and state. When a widget state changes, the widget rebuilds its description, and the framework diffs the new description against the previous description to determine the minimal changes needed in the underlying render tree to transition from one state to the next. Flutter includes a modern reactive framework, a 2D rendering engine, ready-made widgets, and development tools. These components work together to help you design, build, test, and debug apps.';
    } else if (lowerQuestion.contains('artificial intelligence') || lowerQuestion.contains('ai')) {
      return 'Artificial Intelligence (AI) is the simulation of human intelligence in machines that are programmed to think and learn like humans. The term may also be applied to any machine that exhibits traits associated with a human mind such as learning and problem-solving. AI research has been highly successful in developing effective techniques for solving a wide range of problems, from game playing to medical diagnosis. However, some observers argue that computers cannot be programmed to truly think, and that simulated thinking is not the same as actual thinking. The field of AI research was born at a Dartmouth College workshop in 1956. Attendees Allen Newell, Herbert Simon, John McCarthy, Marvin Minsky and Arthur Samuel became the founders and leaders of AI research. They and their students produced programs that the press described as astonishing: computers were learning checkers strategies, solving word problems in algebra, proving logical theorems and speaking English. By the middle of the 1960s, research in the U.S. was heavily funded by the Department of Defense and laboratories had been established around the world. AI research includes machine learning, natural language processing, computer vision, robotics, expert systems, and neural networks. Modern AI techniques have experienced a resurgence following concurrent advances in computer power, large amounts of data, and theoretical understanding.';
    } else if (lowerQuestion.contains('python')) {
      return 'Python is a high-level, interpreted programming language with dynamic semantics. Its high-level built-in data structures, combined with dynamic typing and dynamic binding, make it very attractive for Rapid Application Development, as well as for use as a scripting or glue language to connect existing components together. Python was conceived in the late 1980s by Guido van Rossum at Centrum Wiskunde & Informatica (CWI) in the Netherlands as a successor to the ABC language, and was first released in 1991 as Python 0.9.0. Python 2.0 was released in 2000 and introduced new features such as list comprehensions and a garbage collection system. Python 3.0 was released in 2008 and was a major revision of the language that is not completely backward-compatible. Python is dynamically typed and garbage-collected. It supports multiple programming paradigms, including structured, object-oriented and functional programming. Python is often described as a batteries included language due to its comprehensive standard library. Python interpreters are available for many operating systems. A global community of programmers develops and maintains CPython, a free and open-source reference implementation. Python is used in web development, data science, artificial intelligence, scientific computing, automation, and many other fields.';
    } else if (lowerQuestion.contains('javascript')) {
      return 'JavaScript is a programming language that is one of the core technologies of the World Wide Web, alongside HTML and CSS. Over 97% of websites use JavaScript on the client side for web page behavior, often incorporating third-party libraries. JavaScript was initially created to make web pages alive. The programs in this language are called scripts. They can be written right in a web page HTML and run automatically as the page loads. Scripts are provided and executed as plain text. They do not need special preparation or compilation to run. JavaScript was originally developed by Brendan Eich of Netscape Communications under the name Mocha, which was later renamed to LiveScript, and finally to JavaScript. The change of name from LiveScript to JavaScript roughly coincided with Netscape adding support for Java technology in its browser. JavaScript is a high-level, often just-in-time compiled language that conforms to the ECMAScript standard. It has dynamic typing, prototype-based object-orientation, and first-class functions. It is multi-paradigm, supporting event-driven, functional, and imperative programming styles. JavaScript engines were originally used only in web browsers, but they are now core components of many software systems, most notably servers and a variety of applications. The most popular runtime system for this usage is Node.js.';
    } else if (lowerQuestion.contains('machine learning')) {
      return 'Machine Learning is a method of data analysis that automates analytical model building. It is a branch of artificial intelligence based on the idea that systems can learn from data, identify patterns and make decisions with minimal human intervention. Machine learning algorithms build a model based on training data in order to make predictions or decisions without being explicitly programmed to do so. Machine learning algorithms are used in a wide variety of applications, such as in medicine, email filtering, speech recognition, and computer vision, where it is difficult or unfeasible to develop conventional algorithms to perform the needed tasks. The term machine learning was coined in 1959 by Arthur Samuel, an American IBMer and pioneer in the field of computer gaming and artificial intelligence. Machine learning is closely related to computational statistics, which focuses on making predictions using computers. The study of mathematical optimization delivers methods, theory and application domains to the field of machine learning. Data mining is a related field of study, focusing on exploratory data analysis through unsupervised learning. Some machine learning methods include supervised learning, unsupervised learning, semi-supervised learning, reinforcement learning, self-learning, feature learning, sparse dictionary learning, anomaly detection, robot learning, and association rules.';
    } else if (lowerQuestion.contains('android')) {
      return 'Android is a mobile operating system based on a modified version of the Linux kernel and other open source software, designed primarily for touchscreen mobile devices such as smartphones and tablets. Android is developed by a consortium of developers known as the Open Handset Alliance and commercially sponsored by Google. It was unveiled in November 2007, with the first commercial Android device launched in September 2008. Android is the most widely used mobile operating system in the world, with over 3 billion active devices as of May 2021. The operating system has been the best-selling OS worldwide on smartphones since 2011 and on tablets since 2013. As of May 2021, it has over three billion monthly active users, the largest installed base of any operating system in the world, and as of January 2021, the Google Play Store features over 3 million apps. Android has been the best-selling OS worldwide on smartphones since 2011 and on tablets since 2013. Android applications are usually developed in the Java language using the Android software development kit (SDK), although other development platforms are available. The Android SDK includes a comprehensive set of development tools, including a debugger, software libraries, a handset emulator based on QEMU, documentation, sample code, and tutorials.';
    } else if (lowerQuestion.contains('hello') || lowerQuestion.contains('hi')) {
      return 'Hello! I am your AI assistant. I can help answer questions about technology, programming, science, and many other topics. What would you like to know? I have extensive knowledge about programming languages like Python, JavaScript, Java, and frameworks like Flutter and React. I can also discuss topics related to artificial intelligence, machine learning, mobile development, web development, databases, and much more. Feel free to ask me anything you are curious about, and I will do my best to provide you with detailed and helpful information.';
    } else if (lowerQuestion.contains('java')) {
      return 'Java is a high-level, class-based, object-oriented programming language that is designed to have as few implementation dependencies as possible. It is a general-purpose programming language intended to let programmers write once, run anywhere (WORA), meaning that compiled Java code can run on all platforms that support Java without the need to recompile. Java applications are typically compiled to bytecode that can run on any Java virtual machine (JVM) regardless of the underlying computer architecture. Java was originally developed by James Gosling at Sun Microsystems and released in May 1995 as a core component of Sun Microsystems Java platform. The original and reference implementation Java compilers, virtual machines, and class libraries were originally released by Sun under proprietary licenses. As of May 2007, in compliance with the specifications of the Java Community Process, Sun had relicensed most of its Java technologies under the GPL-2.0-only license. Oracle offers its own HotSpot Java Virtual Machine, however the official reference implementation is the OpenJDK JVM which is free open-source software and used by most developers and is the default JVM for almost all Linux distributions.';
    } else if (lowerQuestion.contains('react')) {
      return 'React is a free and open-source front-end JavaScript library for building user interfaces based on UI components. It is maintained by Meta and a community of individual developers and companies. React can be used as a base in the development of single-page, mobile, or server-rendered applications with frameworks like Next.js. However, React is only concerned with state management and rendering that state to the DOM, so creating React applications usually requires the use of additional libraries for routing, as well as certain client-side functionality. React was created by Jordan Walke, a software engineer at Facebook, who released an early prototype of React called FaxJS. He was influenced by XHP, an HTML component library for PHP. It was first deployed on Facebook news feed in 2011 and later on Instagram in 2012. It was open-sourced at JSConf US in May 2013. React Native, which enables native Android, iOS, and UWP development with React, was announced at Facebook React Conf in February 2015 and open-sourced in March 2015. On April 18, 2017, Facebook announced React Fiber, a new set of internal algorithms for rendering, as opposed to React Stack, the prior rendering algorithm. React Fiber was to become the foundation of any future improvements and feature development of the React library.';
    } else if (lowerQuestion.contains('database')) {
      return 'A database is an organized collection of structured information, or data, typically stored electronically in a computer system. A database is usually controlled by a database management system (DBMS). Together, the data and the DBMS, along with the applications that are associated with them, are referred to as a database system, often shortened to just database. Data within the most common types of databases in operation today is typically modeled in rows and columns in a series of tables to make processing and data querying efficient. The data can then be easily accessed, managed, modified, updated, controlled, and organized. Most databases use structured query language (SQL) for writing and querying data. There are many different types of databases. The best database for a specific organization depends on how the organization intends to use the data. Relational databases became dominant in the 1980s. These model data as rows and columns in a series of tables, and the vast majority use SQL for writing and querying data. In the 2000s, non-relational databases became popular, referred to as NoSQL because they use different query languages. More recently, NewSQL databases have been developed that combine the benefits of relational and non-relational databases. Common database types include relational databases, object-oriented databases, distributed databases, data warehouses, NoSQL databases, graph databases, and HTAP databases.';
    } else {
      return 'I can help you with questions about technology, programming, artificial intelligence, and many other topics. I have extensive knowledge in areas such as programming languages (Python, JavaScript, Java, Dart), frameworks and technologies (Flutter, React, Android development), computer science concepts (algorithms, data structures, databases), artificial intelligence and machine learning, web development, mobile app development, software engineering principles, and much more. Could you please rephrase your question or ask about something specific? I am here to provide detailed and comprehensive answers to help you learn and understand various topics in technology and beyond.';
    }
  }



  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    // Add user message immediately
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });

    _messageController.clear();
    // Dismiss keyboard after sending
    FocusScope.of(context).unfocus();
    
    // Process response with ChatGPT first, fallback to offline
    await _processResponse(message);
  }

  Future<void> _processResponse(String message) async {
    String response;
    try {
      // Try ChatGPT first
      response = await _getChatGPTResponse(message);
    } catch (e) {
      // If ChatGPT fails, use offline response
      print('ChatGPT failed: $e');
      response = _getOfflineResponse(message);
    }

    // Update UI with response
    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          text: response,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
      
      // Try to show interstitial ad after AI response
      AdService().tryShowInterstitialAd();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _startNewConversation() {
    // Dismiss keyboard and reset view
    FocusScope.of(context).unfocus();
    if (mounted) {
      setState(() {
        _messages.clear();
        _isLoading = false;
        _showFavoritesOnly = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Started new conversation')));
    }
  }

  Future<void> _confirmClearChats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chats?'),
        content: const Text('This will remove all messages in the conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _messages.clear();
        _isLoading = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Chats cleared')));
    }
  }

  // Formats a timestamp like 3:07 PM (no external deps)
  String _formatTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI:Ask Anything',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Math puzzles',
            icon: const Icon(Icons.extension_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MathPuzzlePage()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) {
              if (value == 'toggle_timestamps') {
                setState(() => _showTimestamps = !_showTimestamps);
              } else if (value == 'new_conversation') {
                _startNewConversation();
              } else if (value == 'toggle_favorites_view') {
                setState(() => _showFavoritesOnly = !_showFavoritesOnly);
              } else if (value == 'clear_chats') {
                _confirmClearChats();
              } else if (value == 'contact_us') {
                _contactUs();
              } else if (value == 'settings') {
                _openSettings();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'new_conversation',
                child: Row(
                  children: const [
                    Icon(Icons.create_new_folder_outlined),
                    SizedBox(width: 12),
                    Text('New conversation'),
                  ],
                ),
              ),
              CheckedPopupMenuItem<String>(
                value: 'toggle_timestamps',
                checked: _showTimestamps,
                child: Row(
                  children: [
                    Icon(_showTimestamps ? Icons.schedule : Icons.schedule_outlined),
                    const SizedBox(width: 12),
                    Text(_showTimestamps ? 'Timestamps: On' : 'Timestamps: Off'),
                  ],
                ),
              ),
              CheckedPopupMenuItem<String>(
                value: 'toggle_favorites_view',
                checked: _showFavoritesOnly,
                child: Row(
                  children: [
                    Icon(_showFavoritesOnly ? Icons.star : Icons.star_border),
                    const SizedBox(width: 12),
                    Text(_showFavoritesOnly ? 'Show favorites only: On' : 'Show favorites only: Off'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear_chats',
                child: Row(
                  children: const [
                    Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text('Clear chats'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'contact_us',
                child: Row(
                  children: const [
                    Icon(Icons.email_outlined),
                    SizedBox(width: 12),
                    Text('Contact us'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: const [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Center(
                    child: Text(
                      'Designed and developed by MahaRana Studios',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.08),
              Theme.of(context).colorScheme.secondary.withOpacity(0.06),
              Theme.of(context).colorScheme.tertiary.withOpacity(0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
          Expanded(
            child: Builder(
              builder: (context) {
                final messagesToShow = _showFavoritesOnly
                    ? _messages.where((m) => m.isFavorite).toList()
                    : _messages;
                if (messagesToShow.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: Icon(
                            _showFavoritesOnly ? Icons.star_outline : Icons.psychology_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _showFavoritesOnly ? 'No favorites yet' : 'AI:Ask Anything',
                          style: TextStyle(
                            fontSize: (_showFavoritesOnly ? 18 : 28) * widget.fontScale,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(_showFavoritesOnly ? 0.7 : 0.8),
                            letterSpacing: _showFavoritesOnly ? 0.5 : 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showFavoritesOnly 
                              ? 'Star messages to see them here' 
                              : 'Your intelligent AI assistant',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (!_showFavoritesOnly) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              '💡 Try asking about technology, science, or math',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messagesToShow.length,
                  itemBuilder: (context, index) {
                    final message = messagesToShow[index];
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 140,
                      child: LinearProgressIndicator(minHeight: 4),
                    ),
                    const SizedBox(width: 10),
                    Text('AI is thinking…', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          _buildMessageInput(),
        ],
      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.smart_toy, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPressStart: (details) async {
                final selected = await showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    details.globalPosition.dx,
                    details.globalPosition.dy,
                    details.globalPosition.dx,
                    details.globalPosition.dy,
                  ),
                  items: [
                    const PopupMenuItem<String>(value: 'copy', child: Text('Copy')),
                    PopupMenuItem<String>(
                      value: 'favorite',
                      child: Text(message.isFavorite ? 'Unfavorite' : 'Favorite'),
                    ),
                    if (message.isUser)
                      const PopupMenuItem<String>(value: 'edit', child: Text('Edit & resend')),
                    const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                  ],
                );
                if (!mounted || selected == null) return;
                final messenger = ScaffoldMessenger.of(context);
                switch (selected) {
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: message.text));
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(const SnackBar(content: Text('Copied')));
                    break;
                  case 'favorite':
                    setState(() => message.isFavorite = !message.isFavorite);
                    break;
                  case 'edit':
                    _messageController.text = message.text;
                    FocusScope.of(context).requestFocus(FocusNode());
                    FocusScope.of(context).unfocus();
                    FocusScope.of(context).requestFocus();
                    break;
                  case 'delete':
                    setState(() {
                      _messages.remove(message);
                    });
                    break;
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: message.isUser
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(message.isUser ? 20 : 6),
                    bottomRight: Radius.circular(message.isUser ? 6 : 20),
                  ),
                  border: message.isUser
                      ? null
                      : Border.all(color: theme.colorScheme.outline.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: message.isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.isUser
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                              fontSize: 15 * MediaQuery.of(context).textScaleFactor * widget.fontScale,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          splashRadius: 18,
                          tooltip: message.isFavorite ? 'Unfavorite' : 'Favorite',
                          icon: Icon(
                            message.isFavorite ? Icons.star : Icons.star_border,
                            color: message.isFavorite ? theme.colorScheme.secondary : theme.hintColor,
                          ),
                          onPressed: () {
                            setState(() => message.isFavorite = !message.isFavorite);
                          },
                        ),
                      ],
                    ),
                    if (_showTimestamps) ...[
                      const SizedBox(height: 6),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: message.isUser ? theme.colorScheme.onPrimary.withOpacity(0.7) : theme.colorScheme.onSurfaceVariant,
                          fontSize: 12 * widget.fontScale,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(Icons.person, color: theme.colorScheme.onSecondaryContainer),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: '💭 Ask me anything...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: _isLoading ? null : _sendMessage,
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Icon(
                _isLoading ? Icons.hourglass_empty : Icons.send_rounded,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}