import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseService {
  static bool _initialized = false;
  static FirebaseApp? _app;
  
  static Future<FirebaseApp> initialize() async {
    if (_initialized && _app != null) {
      print('Firebase already initialized via service, returning existing app');
      return _app!;
    }
    
    try {
      if (Firebase.apps.isEmpty) {
        print('Initializing Firebase from service...');
        _app = await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        print('Using existing Firebase app from service');
        _app = Firebase.app();
      }
      
      _initialized = true;
      return _app!;
    } catch (e) {
      print('❌ Error initializing Firebase in service: $e');
      rethrow;
    }
  }
}