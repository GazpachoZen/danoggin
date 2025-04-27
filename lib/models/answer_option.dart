// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AnswerOption {
  final String? text;
  final String? imagePath;
  final String? imageUrl; // New field for cloud storage URLs

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
        final hasText = text != null;

        // max size inside square button
        final maxSize = constraints.maxHeight;

        // Image height is flexible: large if solo, smaller if paired with text
        final imageHeight = hasText ? maxSize * 0.45 : maxSize * 0.75;

        // Text size is flexible: larger if solo, smaller if with image
        final fontSize = hasImage ? 16.0 : 30.0;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasImage)
              Container(
                height: imageHeight,
                child: ColorFiltered(
                  // Apply grayscale filter when disabled
                  colorFilter: disabled 
                      ? ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ])
                      : ColorFilter.mode(Colors.transparent, BlendMode.color),
                  child: _buildImage(),
                ),
              ),
            if (hasText)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  text!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    // Reduce opacity of text when disabled
                    color: disabled ? Colors.grey : null,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }

  // Helper method to determine which image source to use
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