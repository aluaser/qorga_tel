import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat.dart';
import 'config.dart';
import 'mood.dart';
import 'login.dart';
import 'profile.dart';
import 'news.dart';
import 'help.dart';
import 'about_us.dart';
import 'test.dart';

const Color kPrimaryColor = Color(0xFF3B82F6);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  String? _userId;
  String? _email;
  String? _name;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _userId = prefs.getString('userId');
      _email = prefs.getString('email');
      _name = prefs.getString('name');
      _isLoading = false;
    });
  }

  Future<void> _openPsychologyTest() async {
    if (_userId == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      await _loadUserData();
      if (!mounted || _userId == null) return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PsychologyTestScreen(
          baseUrl: apiBaseUrl,
          userId: _userId!,
        ),
      ),
    );
  }

  void _onTabTapped(int index) async {
    if (index == 2) {
      final newIndex = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
      if (newIndex is int && newIndex != 2) {
        setState(() {
          _tab = newIndex;
        });
      }
      return;
    }
    if (index == 1) {
      if (_userId == null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        await _loadUserData();
        if (!mounted || _userId == null) return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoodPage(
            baseUrl: apiBaseUrl,
            userId: _userId!,
          ),
        ),
      );
      return;
    }

    setState(() {
      _tab = index;
    });
  }

  List<Widget> _buildTabScreens() {
    return [
      _buildHomePageBody(),
      Container(),
      Container(),
      const NewsScreen(),
    ];
  }

  Widget _buildHomePageBody() {
    final displayName = (_name == null || _name!.trim().isEmpty)
        ? 'достым'
        : _name!.split(' ').first;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF3B82F6),
                    Color(0xFF60A5FA),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Сәлем, $displayName 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'QORGA сені қолдайды.\nКөңіл-күйіңді бақылап, қажет кезде көмек ал.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lightbulb_outline,
                                  size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Көңіл-күйіңді бүгін белгілеуді ұмытпа ✨',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Text(
                        '💙',
                        style: TextStyle(fontSize: 34),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _QuoteGeneratorWidget(),
          const SizedBox(height: 14),
          _PsychologyTestCard(onStart: _openPsychologyTest),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF3FF),
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: const Text(
          'QORGA',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        backgroundColor: kPrimaryColor,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildTabScreens()[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: kPrimaryColor,
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

  Drawer _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: kPrimaryColor.withOpacity(0.1),
                child: const Icon(
                  Icons.account_circle,
                  size: 30,
                  color: kPrimaryColor,
                ),
              ),
              title: Text(
                _name ?? 'Пайдаланушы',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(_userId == null ? 'Кіру' : (_email ?? 'Профиль')),
              onTap: () async {
                Navigator.pop(context);
                if (_userId == null) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                  await _loadUserData();
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                  await _loadUserData();
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.call, color: kPrimaryColor),
              title: const Text('Көмек'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.menu_book_outlined, color: kPrimaryColor),
              title: const Text('Біз туралы'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutUsScreen()),
                );
              },
            ),
            const Spacer(),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _QuoteGeneratorWidget extends StatefulWidget {
  const _QuoteGeneratorWidget();

  @override
  State<_QuoteGeneratorWidget> createState() => _QuoteGeneratorWidgetState();
}

class _QuoteGeneratorWidgetState extends State<_QuoteGeneratorWidget> {
  final List<Map<String, String>> _quotes = [
    {"quote": "Ең үлкен жеңіс - өзіңді жеңу.", "author": "Платон"},
    {
      "quote": "Білімді болу жеткіліксіз, оны қолдана білу керек.",
      "author": "Иоганн Гёте"
    },
    {"quote": "Сен не ойласаң, сен солсың.", "author": "Будда"},
    {"quote": "Жақсылық жасаудан ешқашан жалықпа.", "author": "Марк Твен"},
    {
      "quote": "Ертеңгі күннің кедергісі - бүгінгі күмән.",
      "author": "Франклин Рузвельт"
    },
    {
      "quote":
          "Өзгерістің құпиясы - ескімен күресуге емес, жаңаны құруға назар аудару.",
      "author": "Сократ"
    },
    {
      "quote":
          "Жетістікке жетудің жалғыз жолы - жасап жатқан ісіңді жақсы көру.",
      "author": "Стив Джобс"
    }
  ];

  late Map<String, String> _currentQuote;

  @override
  void initState() {
    super.initState();
    _generateNewQuote();
  }

  void _generateNewQuote() {
    setState(() {
      _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _generateNewQuote,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Күннің дәйексөзі',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kPrimaryColor.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 12),
              Icon(
                Icons.format_quote_rounded,
                color: kPrimaryColor.withOpacity(0.7),
                size: 30,
              ),
              const SizedBox(height: 8),
              Text(
                _currentQuote['quote']!,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "— ${_currentQuote['author']!}",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PsychologyTestCard extends StatelessWidget {
  final VoidCallback onStart;

  const _PsychologyTestCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onStart,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: SizedBox(
            height: 150,
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      '🧠',
                      style: TextStyle(fontSize: 30),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Психологиялық тест',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '10 сұрақ • 3–4 минут',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          'Қазіргі эмоциялық күйіңді анықтап, нәтижені сақтаймыз. '
                          'Картаны басып, қысқа тесттен өт.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Тестті бастау',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: kPrimaryColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: kPrimaryColor,
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
