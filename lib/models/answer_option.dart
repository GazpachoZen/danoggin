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
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
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
  // Updated _simplifiedTextRendering method for lib/models/answer_option.dart
// Replace your current _simplifiedTextRendering method with this one

  Widget _simplifiedTextRendering(
      String text, BoxConstraints constraints, bool disabled) {
    final textColor = disabled ? Colors.grey : Colors.black87;

    // Platform-specific adjustments
    final isIOS = Platform.isIOS;

    return LayoutBuilder(
      builder: (context, textConstraints) {
        final availableWidth = textConstraints.maxWidth *
            0.92; // Slightly reduced width for padding
        final availableHeight =
            textConstraints.maxHeight * 0.85; // Allow some vertical padding

        // First check if we should attempt to break the text for better display
        final breakIndex = _findNaturalBreakPoint(text);
        final shouldBreak =
            breakIndex > 0 && text.length > 10; // Only break longer text

        if (shouldBreak) {
          final firstLine = text.substring(0, breakIndex).trim();
          final secondLine = text.substring(breakIndex).trim();

          return Container(
            width: availableWidth,
            height: availableHeight,
            child: AutoSizeText(
              '$firstLine\n$secondLine',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isIOS
                    ? 22.0
                    : 20.0, // Start with slightly larger font on iOS
                color: textColor,
                height: 1.1, // Tighter line height for two lines
              ),
              maxLines: 2,
              minFontSize: isIOS ? 12.0 : 10.0,
              stepGranularity: 0.5, // Finer steps for better sizing
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        // For text that doesn't need breaking or is too short to benefit from breaking
        return Container(
          width: availableWidth,
          height: availableHeight,
          child: AutoSizeText(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isIOS ? 26.0 : 24.0, // Larger initial font size
              color: textColor,
            ),
            maxLines:
                text.length > 12 ? 2 : 1, // Allow long text to use 2 lines
            minFontSize: isIOS ? 12.0 : 10.0,
            stepGranularity: 0.5,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

// Improved natural break point finder
  int _findNaturalBreakPoint(String text) {
    // For simplicity, find approximately the middle of the text
    final middle = text.length ~/ 2;

    // Minimum length for first segment to ensure good breaks
    final minFirstSegmentLength = text.length > 12 ? 4 : 2;

    // Look for space character near the middle (search outward)
    for (int offset = 0; offset < middle; offset++) {
      // Check after the middle
      final afterIndex = middle + offset;
      if (afterIndex < text.length &&
          text[afterIndex] == ' ' &&
          afterIndex >= minFirstSegmentLength) {
        return afterIndex;
      }

      // Check before the middle
      final beforeIndex = middle - offset;
      if (beforeIndex >= minFirstSegmentLength &&
          beforeIndex < text.length &&
          text[beforeIndex] == ' ') {
        return beforeIndex;
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
