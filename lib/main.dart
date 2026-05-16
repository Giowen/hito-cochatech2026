import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers.dart';
import 'screens/matches_screen.dart';
import 'screens/role_selector_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: false,
    );
  }

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
      home: const _HitoRoot(),
    );
  }
}

/// Root widget — route condicional según si el usuario ya eligió rol.
/// Sin auth/signup → la elección María/Juan reemplaza a un login screen.
class _HitoRoot extends ConsumerWidget {
  const _HitoRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRole = ref.watch(hasSelectedRoleProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: hasRole
          ? const MatchesScreen()
          : const RoleSelectorScreen(),
    );
  }
}
