import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'config.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatRoom {
  final String chatId;
  final String kind;
  final String title;
  final String subtitle;
  final DateTime? lastAt;
  final int unreadCount;
  final String? peerId;

  const _ChatRoom({
    required this.chatId,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.lastAt,
    required this.unreadCount,
    required this.peerId,
  });
}

class _ChatMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final String senderType;
  final String? senderId;

  const _ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.senderType,
    required this.senderId,
  });
}

class _ChatScreenState extends State<ChatScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorText;
  io.Socket? _roomsSocket;
  Timer? _roomsRefreshDebounce;

  String? _userId;
  String _userRole = 'user';
  List<_ChatRoom> _rooms = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _roomsRefreshDebounce?.cancel();
    _roomsSocket?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('userId') ?? '').trim();
    final role = (prefs.getString('role') ?? 'user').trim();

    if (!mounted) return;
    setState(() {
      _userId = userId.isEmpty ? null : userId;
      _userRole = role.isEmpty ? 'user' : role;
    });

    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    await _loadRooms(initial: true);
    _connectRoomsSocket();
  }

  Future<void> _loadRooms({bool initial = false}) async {
    if (_userId == null) return;

    if (mounted) {
      setState(() {
        if (initial) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final uri = Uri.parse('$apiBaseUrl/chat/list?userId=$_userId');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('status ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawItems = (data['items'] as List?) ?? [];

      final rooms = rawItems
          .map((e) {
            final m = e as Map<String, dynamic>;
            final peer = (m['peer'] as Map<String, dynamic>?);
            return _ChatRoom(
              chatId: '${m['chatId'] ?? ''}',
              kind: '${m['kind'] ?? 'human'}',
              title: '${m['title'] ?? 'Чат'}',
              subtitle: '${m['subtitle'] ?? ''}',
              lastAt: m['lastAt'] == null
                  ? null
                  : DateTime.tryParse('${m['lastAt']}'),
              unreadCount: (m['unreadCount'] as num?)?.toInt() ?? 0,
              peerId: peer == null ? null : '${peer['id'] ?? ''}',
            );
          })
          .where((r) => r.chatId.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _errorText = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Чаттарды жүктеу кезінде қате шықты.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _connectRoomsSocket() {
    if (_userId == null) return;
    _roomsSocket?.dispose();

    final socket = io.io(
      wsBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'userId': _userId!})
          .disableAutoConnect()
          .build(),
    );

    socket.on('chat:updated', (_) {
      if (!mounted) return;
      _roomsRefreshDebounce?.cancel();
      _roomsRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          _loadRooms();
        }
      });
    });

    socket.connect();
    _roomsSocket = socket;
  }

  Future<void> _openRoom(_ChatRoom room) async {
    if (_userId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ConversationScreen(
          userId: _userId!,
          userRole: _userRole,
          room: room,
        ),
      ),
    );
    await _loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Чаттар')),
        body: const Center(
          child: Text('Чатқа кіру үшін алдымен аккаунтқа кіріңіз.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_userRole == 'psychologist' ? 'Клиенттер' : 'Чаттар'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _loadRooms(),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                _errorText!,
                style: TextStyle(
                    color: Colors.red[700], fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: _rooms.isEmpty
                ? Center(
                    child: Text(
                      _userRole == 'psychologist'
                          ? 'Пайдаланушылардан хабарлама әлі жоқ.'
                          : 'Чаттар әлі жоқ.',
                    ),
                  )
                : ListView.separated(
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      return ListTile(
                        onTap: () => _openRoom(room),
                        leading: CircleAvatar(
                          backgroundColor: room.kind == 'ai'
                              ? theme.colorScheme.primary
                                  .withValues(alpha: 0.18)
                              : theme.colorScheme.secondary
                                  .withValues(alpha: 0.22),
                          child: Icon(
                            room.kind == 'ai'
                                ? Icons.smart_toy_outlined
                                : Icons.person_outline,
                          ),
                        ),
                        title: Text(
                          room.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          room.subtitle.isEmpty ? 'Жаңа чат' : room.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              room.lastAt == null ? '' : _time(room.lastAt!),
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            if (room.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${room.unreadCount}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        onTap: (index) {
          if (index != 2) Navigator.of(context).pop(index);
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

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ConversationScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final _ChatRoom room;

  const _ConversationScreen({
    required this.userId,
    required this.userRole,
    required this.room,
  });

  @override
  State<_ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<_ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<_ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _socketConnected = false;
  String? _errorText;
  io.Socket? _socket;
  Timer? _fallbackPollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectSocket();
    _fallbackPollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) {
        if (!_socketConnected) {
          _loadMessages(silent: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    _socket?.emit('leave_chat', {'chatId': widget.room.chatId});
    _socket?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final socket = io.io(
      wsBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'userId': widget.userId})
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      if (!mounted) return;
      setState(() => _socketConnected = true);
      socket.emit('join_chat', {'chatId': widget.room.chatId});
    });

    socket.onDisconnect((_) {
      if (!mounted) return;
      setState(() => _socketConnected = false);
    });

    socket.onConnectError((_) {
      if (!mounted) return;
      setState(() => _socketConnected = false);
    });

    socket.on('message:new', (payload) {
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      if ('${map['chatId'] ?? ''}' != widget.room.chatId) return;
      final message = _toMessage(map);
      _upsertMessage(message);
    });

    socket.connect();
    _socket = socket;
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/chat/messages?userId=${widget.userId}&chatId=${widget.room.chatId}&limit=300',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('status ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['items'] as List?) ?? [];
      final messages = raw.map((e) {
        final m = e as Map<String, dynamic>;
        return _toMessage(m);
      }).toList();

      if (!mounted) return;
      setState(() {
        _messages = messages;
        _errorText = null;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Хабарламаларды жүктеу сәтсіз аяқталды.';
      });
    } finally {
      if (!mounted) return;
      if (!silent) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{
        'chatId': widget.room.chatId,
        'senderId': widget.userId,
        'text': text,
      };

      if (widget.room.kind == 'human' && widget.room.peerId != null) {
        payload['recipientId'] = widget.room.peerId;
      }

      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/chat/messages'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final item = body['item'];
        final aiReply = body['aiReply'];

        if (item is Map<String, dynamic>) {
          _upsertMessage(_toMessage(item));
        }
        if (aiReply is Map<String, dynamic>) {
          _upsertMessage(_toMessage(aiReply));
        }

        _controller.clear();
        if (!_socketConnected) {
          await _loadMessages(silent: true);
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorText = 'Хабарлама жіберілмеді (код: ${response.statusCode}).';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Хабарлама жіберу кезінде желі қатесі.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 24,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  _ChatMessage _toMessage(Map<String, dynamic> m) {
    final createdAt = DateTime.tryParse('${m['createdAt']}') ?? DateTime.now();
    final id = '${m['id'] ?? m['_id'] ?? ''}'.trim();
    return _ChatMessage(
      id: id.isEmpty
          ? '${createdAt.microsecondsSinceEpoch}_${(m['text'] ?? '').hashCode}'
          : id,
      text: '${m['text'] ?? ''}',
      createdAt: createdAt,
      senderType: '${m['senderType'] ?? 'user'}',
      senderId: m['senderId'] == null ? null : '${m['senderId']}',
    );
  }

  void _upsertMessage(_ChatMessage incoming) {
    if (!mounted) return;
    setState(() {
      final exists = _messages.any((m) => m.id == incoming.id);
      if (!exists) {
        _messages = [..._messages, incoming]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      _errorText = null;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.room.title),
            Text(
              widget.room.kind == 'ai'
                  ? 'ИИ чат'
                  : (widget.userRole == 'psychologist'
                      ? 'Клиентпен диалог'
                      : 'Психологпен диалог'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _socketConnected ? 'online' : 'offline',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                _errorText!,
                style: TextStyle(
                    color: Colors.red[700], fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMine = msg.senderType == 'user' &&
                          msg.senderId == widget.userId;

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: isMine
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.16)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isMine ? 14 : 4),
                              bottomRight: Radius.circular(isMine ? 4 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(msg.text),
                              const SizedBox(height: 4),
                              Text(
                                _time(msg.createdAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Хабарлама...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
