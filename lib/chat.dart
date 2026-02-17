import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String kApiBaseUrl = 'http://localhost:4000';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  bool _inDialog = false;

  @override
  void initState() {
    super.initState();

    _messages.add(
      _ChatMessage(
        text:
            'Сәлеметсіз бе! Мен Qorga AI көмекшісімін.\nҚандай сұрағыңыз бар?',
        isUser: false,
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _controller.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      final uri = Uri.parse('$kApiBaseUrl/chat/send');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply =
            (data['reply'] as String?) ?? 'Кешіріңіз, жауап таба алмадым.';

        setState(() {
          _messages.add(
            _ChatMessage(text: reply, isUser: false),
          );
        });
        _scrollToBottom();
      } else {
        setState(() {
          _messages.add(
            _ChatMessage(
              text:
                  'Серверден жауап алу мүмкін болмады. (Код: ${response.statusCode})',
              isUser: false,
            ),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text: 'Сервермен байланыс кезінде қате болды.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _inDialog ? _buildDialogScreen(context) : _buildListScreen(context);
  }

  Widget _buildListScreen(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаттар'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Text(
                'AI',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: const Text(
              'Qorga AI Көмекшісі',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _messages.isNotEmpty
                  ? _messages.last.text.length > 40
                      ? _messages.last.text.substring(0, 40) + '...'
                      : _messages.last.text
                  : 'AI-мен анонимді түрде сөйлесіңіз',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              setState(() {
                _inDialog = true;
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        onTap: (index) {
          if (index != 2) {
            Navigator.of(context).pop(index);
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Басты'),
          BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border), label: 'Көңіл-күй'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline), label: 'Чат'),
          BottomNavigationBarItem(
              icon: Icon(Icons.newspaper), label: 'Мақалалар'),
        ],
      ),
    );
  }

  Widget _buildDialogScreen(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _inDialog = false;
            });
          },
        ),
        title: const Text('Qorga AI Көмекшісі'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.isUser;

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? theme.colorScheme.primary.withOpacity(0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        fontSize: 16,
                        color: isUser ? Colors.black : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Сұрағыңызды жазыңыз...',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      onPressed: _sending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
