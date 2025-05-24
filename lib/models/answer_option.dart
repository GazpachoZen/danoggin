// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'dart:math' show max, min;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:danoggin/utils/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

// Generalized text rendering solution for any multi-word string
// This approach is based on actual text width measurement, not character count

  Widget _simplifiedTextRendering(
      String text, BoxConstraints constraints, bool disabled) {
    final textColor = disabled ? Colors.grey : Colors.black87;
    final logger = Logger();
    final isIOS = Platform.isIOS;

    // Add an iOS-specific safety margin
    final safetyMargin = isIOS ? 0.85 : 0.92; // More conservative for iOS

    // Log the platform and text
    logger.i('Rendering text: "$text" on ${isIOS ? "iOS" : "Android"}');

    return LayoutBuilder(
      builder: (context, textConstraints) {
        final availableWidth = textConstraints.maxWidth * safetyMargin;
        logger.i('Available width: $availableWidth');

        // Use a standard font size
        final singleLineFontSize = 26.0;

        // Check if text fits on single line with more conservative width for iOS
        final textWidth = _measureTextWidth(text, singleLineFontSize);
        final fitsOnSingleLine = textWidth <= availableWidth;

        logger.i(
            'Text width at ${singleLineFontSize}px: $textWidth, fits on single line: $fitsOnSingleLine');

        if (fitsOnSingleLine) {
          // If it fits on one line, still use AutoSizeText on iOS for safety
          if (isIOS) {
            logger.i(
                'iOS: Using single line AutoSizeText with font size: $singleLineFontSize');
            return Center(
              child: Container(
                width: textConstraints.maxWidth * 0.9, // Fixed container width
                child: AutoSizeText(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: singleLineFontSize,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                  minFontSize: 16.0,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
            );
          } else {
            // Android stays the same
            logger.i(
                'Using single line rendering with font size: $singleLineFontSize');
            return Center(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: singleLineFontSize,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
        }

        // For text that doesn't fit on a single line
        final breakIndex = _findBreakNearMiddle(text);
        logger.i('Break index found: $breakIndex');

        // If we can't find a good break point, use AutoSizeText
        if (breakIndex <= 0) {
          logger.i('No good break point found, using AutoSizeText');

          return Center(
            child: Container(
              width: textConstraints.maxWidth * 0.9, // Fixed container width
              child: AutoSizeText(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: singleLineFontSize,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
                minFontSize: isIOS ? 14.0 : 14.0,
                maxLines: 2, // Allow 2 lines for long text
                stepGranularity: 0.5,
                overflow: TextOverflow.visible,
              ),
            ),
          );
        }

        // Break the text at the found position
        final firstLine = text.substring(0, breakIndex).trim();
        final secondLine = text.substring(breakIndex).trim();

        logger.i('Split text into: "$firstLine" and "$secondLine"');

        // Measure both lines with a more conservative available width for iOS
        final firstLineWidth = _measureTextWidth(firstLine, singleLineFontSize);
        final secondLineWidth =
            _measureTextWidth(secondLine, singleLineFontSize);

        logger.i(
            'First line width: $firstLineWidth, Second line width: $secondLineWidth');

        // Determine the scaling factor needed to make the wider line fit
        final maxLineWidth = max(firstLineWidth, secondLineWidth);
        final scaleFactor = availableWidth / maxLineWidth;

        // Calculate the font size that will fit both lines
        // Be slightly more conservative on iOS
        final twoLineFontSize = min(
            singleLineFontSize * (isIOS ? scaleFactor * 0.95 : scaleFactor),
            singleLineFontSize);

        logger.i(
            'Calculated two-line font size: $twoLineFontSize (scale factor: $scaleFactor)');

        // For iOS, we'll use a fixed-width container with RichText
        if (isIOS) {
          logger.i(
              'iOS: Using RichText with explicit line break in fixed container');
          return Center(
            child: Container(
              width: textConstraints.maxWidth * 0.9, // Fixed container width
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: twoLineFontSize,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                  ),
                  children: [
                    TextSpan(text: firstLine),
                    TextSpan(text: '\n'),
                    TextSpan(text: secondLine),
                  ],
                ),
              ),
            ),
          );
        } else {
          // Android behavior unchanged
          return Center(
            child: Text(
              '$firstLine\n$secondLine',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: twoLineFontSize,
                color: textColor,
                fontWeight: FontWeight.w500,
                height: 1.05, // Tighter line height for two lines
              ),
            ),
          );
        }
      },
    );
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
