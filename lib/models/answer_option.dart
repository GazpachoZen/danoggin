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
    final charCount = text.length;
    
    // For single words, use a single AutoSizeText with smaller font if needed
    if (wordCount <= 1) {
      return AutoSizeText(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        minFontSize: 18.0,
        maxFontSize: 36.0,
        style: TextStyle(
          fontSize: 36.0,
          color: disabled ? Colors.grey : Colors.black87,
        ),
      );
    }
    
    // For two-word phrases like "New Delhi" or "Mediterranean Sea"
    // Use a two-line layout regardless of word balance if total length is long enough
    if (wordCount == 2 && charCount >= 12) {
      // We'll use an approach where both lines share the same font size
      // and are snugly packed vertically
      return LayoutBuilder(
        builder: (context, constraints) {
          // Get the maximum available width
          final maxWidth = constraints.maxWidth * 0.9;
          
          // Determine the font size needed for the longer word
          TextSpan span1 = TextSpan(text: words[0], style: TextStyle(fontSize: 32.0));
          TextSpan span2 = TextSpan(text: words[1], style: TextStyle(fontSize: 32.0));
          
          TextPainter painter1 = TextPainter(
            text: span1,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          TextPainter painter2 = TextPainter(
            text: span2,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          
          painter1.layout(maxWidth: maxWidth);
          painter2.layout(maxWidth: maxWidth);
          
          // Calculate optimal font size based on the longer word
          double scale = 1.0;
          if (painter1.width > maxWidth || painter2.width > maxWidth) {
            double scale1 = painter1.width > maxWidth ? maxWidth / painter1.width : 1.0;
            double scale2 = painter2.width > maxWidth ? maxWidth / painter2.width : 1.0;
            scale = scale1 < scale2 ? scale1 : scale2;
          }
          
          double fontSize = (32.0 * scale).clamp(18.0, 32.0);
          
          // Return a tightly packed column of text
          return Container(
            height: constraints.maxHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  words[0],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: disabled ? Colors.grey : Colors.black87,
                    height: 0.95, // Tight line height
                  ),
                ),
                SizedBox(height: 0), // No additional space
                Text(
                  words[1],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize, // Same size as first line
                    color: disabled ? Colors.grey : Colors.black87,
                    height: 0.95,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    
    // For three or more words, check if we can split them into two balanced lines
    if (wordCount >= 3) {
      // Find the best split point for multi-word phrases
      int midPoint = charCount ~/ 2;
      int bestSplitIndex = -1;
      
      // Track position while traversing the text
      int currentPos = 0;
      for (int i = 0; i < words.length - 1; i++) {
        currentPos += words[i].length + 1; // Word length plus space
        
        // Find split point closest to middle
        if (bestSplitIndex == -1 || (currentPos - midPoint).abs() < (bestSplitIndex - midPoint).abs()) {
          bestSplitIndex = currentPos;
        }
      }
      
      // If we found a good split point, create a two-line layout
      if (bestSplitIndex > 0) {
        String firstLine = text.substring(0, bestSplitIndex).trim();
        String secondLine = text.substring(bestSplitIndex).trim();
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // Get the maximum available width
            final maxWidth = constraints.maxWidth * 0.9;
            
            // Determine the font size needed for the longer line
            TextSpan span1 = TextSpan(text: firstLine, style: TextStyle(fontSize: 28.0));
            TextSpan span2 = TextSpan(text: secondLine, style: TextStyle(fontSize: 28.0));
            
            TextPainter painter1 = TextPainter(
              text: span1,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            );
            TextPainter painter2 = TextPainter(
              text: span2,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            );
            
            painter1.layout(maxWidth: maxWidth);
            painter2.layout(maxWidth: maxWidth);
            
            // Calculate optimal font size based on the longer line
            double scale = 1.0;
            if (painter1.width > maxWidth || painter2.width > maxWidth) {
              double scale1 = painter1.width > maxWidth ? maxWidth / painter1.width : 1.0;
              double scale2 = painter2.width > maxWidth ? maxWidth / painter2.width : 1.0;
              scale = scale1 < scale2 ? scale1 : scale2;
            }
            
            double fontSize = (28.0 * scale).clamp(14.0, 28.0);
            
            // Return a tightly packed column of text
            return Container(
              height: constraints.maxHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    firstLine,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: disabled ? Colors.grey : Colors.black87,
                      height: 0.95,
                    ),
                  ),
                  SizedBox(height: 0),
                  Text(
                    secondLine,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize, // Same size as first line
                      color: disabled ? Colors.grey : Colors.black87,
                      height: 0.95,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }
    }
    
    // Fall back to FittedBox for all other cases
    return FittedBox(
      fit: BoxFit.contain,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 32.0,
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