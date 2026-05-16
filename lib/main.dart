import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/matches_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: HitoApp()));
}

class HitoApp extends StatelessWidget {
  const HitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hito',
      debugShowCheckedModeBanner: false,
      theme: buildHitoTheme(),
      home: const MatchesScreen(),
    );
  }
}
