import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/features/barber_console/presentation/console_page.dart';
import 'package:proximo/features/home/presentation/home_page.dart';
import 'package:proximo/features/home/presentation/not_found_page.dart';
import 'package:proximo/features/queue/presentation/join_queue_page.dart';

/// Rotas nomeadas do app (evita strings soltas espalhadas pelas telas).
abstract final class AppRoutes {
  static const home = 'home';
  static const joinQueue = 'join-queue';
  static const console = 'console';
}

/// Slug de barbearia válido (mesma regra do backend em `functions/src/domain/shop.ts`).
final _slugPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])$');

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: '/',
        name: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      // Deep link do QR Code: https://<dominio>/b/barbearia-do-ze
      GoRoute(
        path: '/b/:slug',
        name: AppRoutes.joinQueue,
        redirect: (context, state) =>
            _slugPattern.hasMatch(state.pathParameters['slug'] ?? '') ? null : '/not-found',
        builder: (context, state) => JoinQueuePage(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/console',
        name: AppRoutes.console,
        builder: (context, state) => const ConsolePage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
