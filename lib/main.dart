import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers.dart';
import 'screens/matches_screen.dart';
import 'screens/role_selector_screen.dart';
import 'theme.dart';
import 'utils/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // dotenv.load lee `.env` desde rootBundle. En producción `.env` ya no se
  // empaqueta (ver pubspec.yaml). El try/catch evita crash y la app cae al
  // fallback de `String.fromEnvironment` vía Env.get(...).
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[Hito] dotenv load skipped: $e (using --dart-define values)');
  }

  final supabaseUrl = Env.get('SUPABASE_URL');
  final supabaseAnonKey = Env.get('SUPABASE_ANON_KEY');
  if (supabaseUrl != null && supabaseAnonKey != null) {
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
