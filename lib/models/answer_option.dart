// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:auto_size_text/auto_size_text.dart';

class AnswerOption {
  final String? text;
  final String? imagePath;
  final String? imageUrl; 

  const AnswerOption({
    this.text, 
    this.imagePath, 
    this.imageUrl,
  });

  factory AnswerOption.fromJson(Map<String, dynamic> json) {
    return AnswerOption(
      text: json['text'] as String?,
      imagePath: json['imagePath'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (text != null) 'text': text,
      if (imagePath != null) 'imagePath': imagePath,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  Widget render({bool disabled = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasImage = imagePath != null || imageUrl != null;
        
        // If we have an image, we'll use it and ignore text
        if (hasImage) {
          return Container(
            height: constraints.maxHeight * 0.8,
            child: _buildImage(),
          );
        }
        
        // Only use text if there's no image
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: _buildTextWithFontScaling(text ?? '', constraints, disabled),
          ),
        );
      },
    );
  }
  
  // This is the new core text rendering function that handles everything in one approach
  Widget _buildTextWithFontScaling(String text, BoxConstraints constraints, bool disabled) {
    // Get words for analysis
    final words = text.split(' ');
    final wordCount = words.length;
    
    // For single words, use a single AutoSizeText with smaller font if needed
    if (wordCount <= 1) {
      return AutoSizeText(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        minFontSize: 14.0,
        maxFontSize: 36.0,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: 36.0,
          color: disabled ? Colors.grey : Colors.black87,
        ),
      );
    }
    
    // For multi-word text (2 or more words), try the FittedBox approach first
    // This will automatically scale text without breaking words
    return FittedBox(
      fit: BoxFit.contain,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 28.0, // Base font size before scaling
          color: disabled ? Colors.grey : Colors.black87,
        ),
      ),
    );
  }

  // Helper method to determine which image source to use
  Widget _buildImage() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.contain,
        placeholder: (context, url) => CircularProgressIndicator(),
        errorWidget: (context, url, error) => Image.asset(imagePath!),
      );
    } else if (imagePath != null && imagePath!.isNotEmpty) {
      return Image.asset(
        imagePath!,
        fit: BoxFit.contain,
      );
    } else {
      return Icon(Icons.image_not_supported);
    }
  }
  
  @override
  String toString() => text ?? '[Image Answer]';
}