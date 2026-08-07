import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialSlidesScreen extends StatefulWidget {
  const TutorialSlidesScreen({super.key});

  @override
  State<TutorialSlidesScreen> createState() => _TutorialSlidesScreenState();
}

class _TutorialSlidesScreenState extends State<TutorialSlidesScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_Slide> _slides = const [
    _Slide(
      title: 'Welcome to Vapor',
      description: 'The Zero-Trust Amnesiac Peer-to-Peer File Transfer Engine.',
      icon: Icons.shield,
    ),
    _Slide(
      title: 'Zero-Persistence',
      description:
          'No history, no accounts, no trace. Once a transfer is complete, everything is wiped from memory.',
      icon: Icons.auto_delete,
    ),
    _Slide(
      title: 'Hybrid Cascade Router',
      description:
          'Vapor automatically connects off-grid if you are on the same Wi-Fi, or uses the cloud if you aren\'t.',
      icon: Icons.router,
    ),
    _Slide(
      title: 'Emergency Duress',
      description:
          'Set a Duress PIN in settings. Entering it will instantly shred all keys and active connections.',
      icon: Icons.warning,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _markSeen();
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_tutorial', true);
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          slide.icon,
                          size: 100,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 48),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('SKIP'),
                  ),
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _nextPage,
                    child: Text(
                      _currentPage == _slides.length - 1 ? 'START' : 'NEXT',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String title;
  final String description;
  final IconData icon;

  const _Slide({
    required this.title,
    required this.description,
    required this.icon,
  });
}
