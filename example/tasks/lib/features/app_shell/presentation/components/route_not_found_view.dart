import 'package:flutter/material.dart';

final class RouteNotFoundView extends StatelessWidget {
  const RouteNotFoundView({
    required this.message,
    required this.onRecover,
    super.key,
  });

  final String message;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRecover,
                child: const Text('Back to tasks'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
