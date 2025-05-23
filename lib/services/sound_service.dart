import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/utils/logger.dart';

/// Service for managing quiz feedback sounds
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;

  final Logger _logger = Logger();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Default sound setting
  bool _soundsEnabled = true;
  bool _isInitialized = false;

  SoundService._internal();

  /// Initialize the sound service and load preferences
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadSoundPreference();
      _isInitialized = true;
      _logger.i('SoundService initialized');
    } catch (e) {
      _logger.e('Error initializing SoundService: $e');
    }
  }

  /// Load sound preference from SharedPreferences
  Future<void> _loadSoundPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundsEnabled = prefs.getBool('soundsEnabled') ?? true;
      _logger.i('Sound preference loaded: $_soundsEnabled');
    } catch (e) {
      _logger.e('Error loading sound preference: $e');
      _soundsEnabled = true; // Default to enabled
    }
  }

  /// Get current sound enabled state
  bool get soundsEnabled => _soundsEnabled;

  /// Set sound enabled state and save to preferences
  Future<void> setSoundsEnabled(bool enabled) async {
    try {
      _soundsEnabled = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('soundsEnabled', enabled);
      _logger.i('Sound preference updated: $enabled');
    } catch (e) {
      _logger.e('Error saving sound preference: $e');
    }
  }

  /// Play correct answer sound
  Future<void> playCorrectSound() async {
    await _playSound('sounds/correct.mp3', 'correct answer');
  }

  /// Play first incorrect attempt sound
  Future<void> playIncorrectFirstSound() async {
    await _playSound('sounds/incorrect_first.mp3', 'first incorrect');
  }

  /// Play final incorrect attempt sound
  Future<void> playIncorrectFinalSound() async {
    await _playSound('sounds/incorrect_final.mp3', 'final incorrect');
  }

  /// Play timeout missed sound
  Future<void> playTimeoutSound() async {
    await _playSound('sounds/timeout_missed.mp3', 'timeout');
  }

  /// Internal method to play a sound file
  Future<void> _playSound(String assetPath, String soundType) async {
    if (!_soundsEnabled) {
      _logger.d('Sounds disabled, skipping $soundType sound');
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.d('Playing $soundType sound: $assetPath');
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (e) {
      _logger.e('Error playing $soundType sound: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    _audioPlayer.dispose();
  }
}