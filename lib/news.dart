import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _Lot {
  final String id;
  final String psychologistName;
  final String title;
  final String description;
  final String videoUrl;
  final String videoOriginalName;
  final DateTime? createdAt;

  _Lot({
    required this.id,
    required this.psychologistName,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.videoOriginalName,
    this.createdAt,
  });
}

class _NewsScreenState extends State<NewsScreen> {
  bool _loading = true;
  bool _creating = false;
  String? _userId;
  String _role = 'user';
  List<_Lot> _lots = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId');
    _role = (prefs.getString('role') ?? 'user').trim();
    await _loadLots();
  }

  Future<void> _loadLots() async {
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/content/lots'));
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['items'] as List?) ?? [];

      final lots = items.map((raw) {
        final m = raw as Map<String, dynamic>;
        return _Lot(
          id: '${m['id']}',
          psychologistName: '${m['psychologistName'] ?? 'Психолог'}',
          title: '${m['title'] ?? ''}',
          description: '${m['description'] ?? ''}',
          videoUrl: '${m['videoUrl'] ?? ''}',
          videoOriginalName: '${m['videoOriginalName'] ?? ''}',
          createdAt: m['createdAt'] == null ? null : DateTime.tryParse('${m['createdAt']}'),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _lots = lots;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateLotDialog() async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    PlatformFile? selectedVideo;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Жаңа лот қосу'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Тақырып',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Сипаттама',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.video,
                          withData: true,
                        );
                        if (result == null || result.files.isEmpty) return;
                        setLocalState(() => selectedVideo = result.files.first);
                      },
                      icon: const Icon(Icons.video_file),
                      label: Text(
                        selectedVideo == null
                            ? 'Видео файл таңдау'
                            : selectedVideo!.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _creating ? null : () => Navigator.pop(ctx),
                  child: const Text('Бас тарту'),
                ),
                ElevatedButton(
                  onPressed: _creating
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final description = descriptionCtrl.text.trim();
                          if (title.isEmpty || selectedVideo == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Тақырып пен видео файл міндетті')),
                            );
                            return;
                          }

                          await _createLot(
                            title: title,
                            description: description,
                            video: selectedVideo!,
                          );

                          if (mounted) Navigator.pop(ctx);
                        },
                  child: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Жүктеу'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createLot({
    required String title,
    required String description,
    required PlatformFile video,
  }) async {
    if (_userId == null || _userId!.isEmpty) return;

    setState(() => _creating = true);
    try {
      List<int>? bytes = video.bytes;
      if ((bytes == null || bytes.isEmpty) && video.path != null && video.path!.isNotEmpty) {
        bytes = await File(video.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Video file payload is empty');
      }

      final resp = await http.post(
        Uri.parse('$apiBaseUrl/content/lots'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'psychologistId': _userId,
          'title': title,
          'description': description,
          'videoBase64': base64Encode(bytes),
          'videoName': video.name,
          'mimeType': video.extension == null ? 'video/mp4' : 'video/${video.extension}',
        }),
      );

      if (resp.statusCode == 201) {
        await _loadLots();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Лот сәтті жарияланды')),
          );
        }
      } else {
        final parsed = jsonDecode(resp.body) as Map<String, dynamic>;
        final err = parsed['error']?.toString() ?? 'Жүктеу қатесі';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сервермен байланыс қатесі')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FB),
      appBar: AppBar(
        title: const Text('Психолог лоттары'),
        centerTitle: true,
      ),
      floatingActionButton: _role == 'psychologist'
          ? FloatingActionButton.extended(
              onPressed: _creating ? null : _openCreateLotDialog,
              icon: const Icon(Icons.add),
              label: const Text('Лот қосу'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLots,
              child: _lots.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: 140),
                        Center(
                          child: Text(
                            'Психологтардан жарияланған материалдар әлі жоқ.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _lots.length,
                      itemBuilder: (context, index) {
                        final lot = _lots[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lot.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  lot.description,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        lot.psychologistName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (lot.createdAt != null)
                                      Text(
                                        _formatDate(lot.createdAt!),
                                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed: () => _openVideo(lot.videoUrl),
                                  icon: const Icon(Icons.play_circle_fill),
                                  label: Text(
                                    lot.videoOriginalName.isEmpty
                                        ? 'Видеоны ашу'
                                        : 'Видео: ${lot.videoOriginalName}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
