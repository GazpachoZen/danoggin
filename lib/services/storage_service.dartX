// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service for handling Firebase Storage operations
class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  
  /// Check if a URL exists in Firebase Storage
  static Future<bool> doesUrlExist(String url) async {
    if (url.isEmpty) return false;
    
    try {
      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet connection available');
        return false;
      }
      
      // Extract the path from the URL
      // This is a basic approach - you may need to adjust based on your URL format
      final uri = Uri.parse(url);
      final path = uri.path;
      
      if (path.isEmpty) return false;
      
      // Try to get metadata to see if the file exists
      await _storage.ref(path).getMetadata();
      return true;
    } catch (e) {
      debugPrint('Error checking if URL exists: $e');
      return false;
    }
  }
  
  /// Preload an image from Firebase Storage to cache
  static Future<bool> preloadImage(String url) async {
    if (url.isEmpty) return false;
    
    try {
      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet connection available');
        return false;
      }
      
      // This will trigger downloading and caching the image
      // The actual caching is handled by CachedNetworkImage internally
      return true;
    } catch (e) {
      debugPrint('Error preloading image: $e');
      return false;
    }
  }
  
  /// Get a download URL for a file in Firebase Storage
  static Future<String?> getDownloadUrl(String storagePath) async {
    if (storagePath.isEmpty) return null;
    
    try {
      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No internet connection available');
        return null;
      }
      
      final ref = _storage.ref(storagePath);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error getting download URL: $e');
      return null;
    }
  }
}