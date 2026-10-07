import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';

class SettingsService {
  static const String _settingsKey = 'glassy_whisper_settings';
  
  Future<Settings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      
      if (settingsJson != null) {
        final Map<String, dynamic> json = jsonDecode(settingsJson);
        return Settings.fromJson(json);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
    
    return const Settings();
  }
  
  Future<void> saveSettings(Settings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(settings.toJson());
      await prefs.setString(_settingsKey, settingsJson);
      debugPrint('Settings saved successfully');
    } catch (e) {
      debugPrint('Error saving settings: $e');
      throw Exception('Failed to save settings: $e');
    }
  }
  
  Future<void> resetSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_settingsKey);
      debugPrint('Settings reset to defaults');
    } catch (e) {
      debugPrint('Error resetting settings: $e');
      throw Exception('Failed to reset settings: $e');
    }
  }
}