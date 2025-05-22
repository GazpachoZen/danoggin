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
import 'dart:io';

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
          Widget imageWidget = Container(
            height: constraints.maxHeight * 0.8,
            child: _buildImage(),
          );
          
          // Apply grayscale filter when disabled
          if (disabled) {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.matrix([
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0,      0,      0,      1, 0,
              ]), // Grayscale matrix
              child: Opacity(
                opacity: 0.5, // Also reduce opacity for disabled state
                child: imageWidget,
              ),
            );
          }
          
          return imageWidget;
        }
        
        // Only use text if there's no image
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: _simplifiedTextRendering(text ?? '', constraints, disabled),
          ),
        );
      },
    );
  }
  
  // Simplified text rendering with improved line breaking and sizing
  Widget _simplifiedTextRendering(String text, BoxConstraints constraints, bool disabled) {
    final textColor = disabled ? Colors.grey : Colors.black87;
    
    // Platform-specific adjustments
    final isIOS = Platform.isIOS;
    final widthMultiplier = isIOS ? 0.90 : 0.95; // More conservative width on iOS
    final fontSizeMultiplier = isIOS ? 1.1 : 1.0; // Slightly larger fonts on iOS
    
    return LayoutBuilder(
      builder: (context, textConstraints) {
        // Adjust available width for iOS
        final availableWidth = textConstraints.maxWidth * widthMultiplier;
        
        // First attempt: try fitting the text on a single line
        final initialSingleLineSize = isIOS ? 35.0 : 32.0; // Larger starting size on iOS
        final singleLineFits = _measureTextFits(
          text, 
          availableWidth, 
          initialSingleLineSize * fontSizeMultiplier
        );
        
        if (singleLineFits) {
          // If it fits on one line, use AutoSizeText with a larger font
          return AutoSizeText(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: initialSingleLineSize * fontSizeMultiplier, 
              color: textColor
            ),
            minFontSize: isIOS ? 20.0 : 18.0, // Higher minimum on iOS
            maxFontSize: initialSingleLineSize * fontSizeMultiplier,
            maxLines: 1,
          );
        }
        
        // If single line doesn't fit, try to find a natural break point
        final breakIndex = _findNaturalBreakPoint(text);
        
        if (breakIndex > 0) {
          final firstLine = text.substring(0, breakIndex).trim();
          final secondLine = text.substring(breakIndex).trim();
          
          // Start with a larger font size on iOS and reduce if needed
          double fontSize = isIOS ? 30.0 : 28.0;
          final minFontSize = isIOS ? 18.0 : 16.0;
          
          // Find a font size where both lines fit
          while (fontSize > minFontSize) {
            if (_measureTextFits(firstLine, availableWidth, fontSize) &&
                _measureTextFits(secondLine, availableWidth, fontSize)) {
              break; // Found a size that works
            }
            fontSize -= 2.0;
          }
          
          // Return the two-line layout with consistent font size
          return Container(
            height: constraints.maxHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  firstLine,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: textColor,
                    height: isIOS ? 1.0 : 0.95, // Slightly more line height on iOS
                  ),
                ),
                SizedBox(height: isIOS ? 4 : 2), // More space between lines on iOS
                Text(
                  secondLine,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize, // Same size as first line
                    color: textColor,
                    height: isIOS ? 1.0 : 0.95,
                  ),
                ),
              ],
            ),
          );
        }
        
        // Fallback: use AutoSizeText to handle any case
        return AutoSizeText(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isIOS ? 26.0 : 24.0, // Larger fallback size on iOS
            color: textColor
          ),
          minFontSize: isIOS ? 16.0 : 14.0, // Higher minimum on iOS
          maxFontSize: isIOS ? 26.0 : 24.0,
          maxLines: 2,
        );
      },
    );
  }
  
  // Helper to find a natural break point in text (preserves your existing logic)
  int _findNaturalBreakPoint(String text) {
    // For simplicity, find approximately the middle of the text
    // and then look for the nearest space
    final middle = text.length ~/ 2;
    
    // Look for space character near the middle (search outward)
    for (int offset = 0; offset < middle; offset++) {
      // Check after the middle
      if (middle + offset < text.length && text[middle + offset] == ' ') {
        return middle + offset;
      }
      
      // Check before the middle
      if (middle - offset >= 0 && text[middle - offset] == ' ') {
        return middle - offset;
      }
    }
    
    // No good break point found
    return -1;
  }
  
  // Helper to measure if text fits at a specific font size (with iOS adjustments)
  bool _measureTextFits(String text, double maxWidth, double fontSize) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    textPainter.layout(maxWidth: double.infinity);
    
    // Add a small buffer for iOS to account for rendering differences
    final buffer = Platform.isIOS ? 4.0 : 0.0;
    return textPainter.width <= (maxWidth - buffer);
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