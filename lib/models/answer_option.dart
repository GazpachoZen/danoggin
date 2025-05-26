// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'dart:math' show max;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:danoggin/utils/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Debug flag for text rendering logs
const bool _debugTextRendering = true;

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
            child: _unifiedTextRendering(text ?? '', constraints, disabled),
          ),
        );
      },
    );
  }

  /// Unified text rendering approach for both iOS and Android
  Widget _unifiedTextRendering(
      String text, BoxConstraints constraints, bool disabled) {
    final textColor = disabled ? Colors.grey : Colors.black87;
    final logger = Logger();
    final isIOS = Platform.isIOS;

    // Conservative safety margin (slightly more conservative for iOS)
    final safetyMargin = isIOS ? 0.60 : 0.80;
    final availableWidth = constraints.maxWidth * safetyMargin;
    
    // Base font size
    const baseFontSize = 26.0;

    if (_debugTextRendering) {
      logger.i('Rendering text: "$text" on ${isIOS ? "iOS" : "Android"}');
      logger.i('Available width: $availableWidth ($safetyMargin * ${constraints.maxWidth})');
    }

    // Step 1: Check if text fits on single line at base font size
    final textWidth = _measureTextWidth(text, baseFontSize);
    final fitsOnSingleLine = textWidth <= availableWidth;

    if (_debugTextRendering) {
      logger.i('Text width at ${baseFontSize}px: $textWidth, fits on single line: $fitsOnSingleLine');
    }

    if (fitsOnSingleLine) {
      // Text fits on single line - use base font size
      if (_debugTextRendering) {
        logger.i('Using single line rendering with font size: $baseFontSize');
      }
      
      return Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: baseFontSize,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // Step 2: Text doesn't fit on single line - check for logical break point
    final breakIndex = _findBreakNearMiddle(text);

    if (_debugTextRendering) {
      logger.i('Break index found: $breakIndex');
    }

    if (breakIndex <= 0) {
      // No logical break point - scale down for single line
      final scaleFactor = availableWidth / textWidth;
      final scaledFontSize = baseFontSize * scaleFactor;
      
      if (_debugTextRendering) {
        logger.i('No break point found, scaling to font size: $scaledFontSize (scale factor: $scaleFactor)');
      }

      return Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: scaledFontSize,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // Step 3: Break text and determine sizing
    final firstLine = text.substring(0, breakIndex).trim();
    final secondLine = text.substring(breakIndex).trim();

    if (_debugTextRendering) {
      logger.i('Split text into: "$firstLine" and "$secondLine"');
    }

    // Measure both lines at base font size
    final firstLineWidth = _measureTextWidth(firstLine, baseFontSize);
    final secondLineWidth = _measureTextWidth(secondLine, baseFontSize);
    final widerLineWidth = max(firstLineWidth, secondLineWidth);

    if (_debugTextRendering) {
      logger.i('First line width: $firstLineWidth, Second line width: $secondLineWidth');
      logger.i('Wider line width: $widerLineWidth');
    }

    // Determine final font size
    double finalFontSize;
    if (widerLineWidth <= availableWidth) {
      // Wider line fits - use base font size
      finalFontSize = baseFontSize;
      if (_debugTextRendering) {
        logger.i('Wider line fits, using base font size: $finalFontSize');
      }
    } else {
      // Wider line doesn't fit - scale down
      final scaleFactor = availableWidth / widerLineWidth;
      finalFontSize = baseFontSize * scaleFactor;
      if (_debugTextRendering) {
        logger.i('Wider line doesn\'t fit, scaling to font size: $finalFontSize (scale factor: $scaleFactor)');
      }
    }

    // Render two-line text
    return Text(
      '$firstLine\n$secondLine',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: finalFontSize,
        color: textColor,
        fontWeight: FontWeight.w500,
        height: 1.05, // Tighter line height for two lines
      ),
    );
  }

  // Find a natural break point (space) near the middle of the text
  int _findBreakNearMiddle(String text) {
    // Look for spaces in the string
    final spaceIndices = <int>[];
    for (int i = 0; i < text.length; i++) {
      if (text[i] == ' ') {
        spaceIndices.add(i);
      }
    }

    // If no spaces found, can't break naturally
    if (spaceIndices.isEmpty) {
      return -1;
    }

    // Find the middle of the text
    final middle = text.length / 2;

    // Find the space closest to the middle
    int closestSpaceIndex = spaceIndices[0];
    double minDistance = (spaceIndices[0] - middle).abs();

    for (int i = 1; i < spaceIndices.length; i++) {
      final distance = (spaceIndices[i] - middle).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closestSpaceIndex = spaceIndices[i];
      }
    }

    return closestSpaceIndex;
  }

  // Helper method to measure text width
  double _measureTextWidth(String text, double fontSize) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500, // Match the weight used in rendering
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

    textPainter.layout();
    return textPainter.width;
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