import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'screens/matches_screen.dart';
import 'screens/role_selector_screen.dart';
import 'theme.dart';

/// Sello de build visible abajo del todo — sirve para confirmar que el deploy
/// en Vercel quedó actualizado. Bump manual en cada commit, o inyectable en el
/// build de Vercel con `--dart-define=BUILD_VERSION=$VERCEL_GIT_COMMIT_SHA`.
const String kBuildVersion = String.fromEnvironment(
  'BUILD_VERSION',
  defaultValue: 'v2026.06.12-1 · oruro',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // dotenv.load lee `.env` desde rootBundle. En producción `.env` ya no se
  // empaqueta (ver pubspec.yaml). El try/catch evita crash y la app cae al
  // fallback de `String.fromEnvironment` vía Env.get(...).
  //
  // Appwrite no requiere init global como Supabase: el `Client` vive en
  // `appwriteClientProvider` (lazy) y se construye en el primer uso con los
  // valores públicos de endpoint/projectId.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[Hito] dotenv load skipped: $e (using --dart-define values)');
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
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: IgnorePointer(
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Text(
                      'Hito · $kBuildVersion',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.2,
                        color: Color.fromRGBO(0, 0, 0, 0.38),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
