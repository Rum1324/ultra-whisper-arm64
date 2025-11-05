import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_service.dart';
import 'floating_overlay.dart';

class AppContent extends StatelessWidget {
  const AppContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: FloatingOverlay(),
        );
      },
    );
  }
}