// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------

// widgets/question_pack_selector_widget.dart
import 'package:flutter/material.dart';
import 'package:danoggin/models/question_pack.dart';
import 'package:danoggin/services/question_pack_service.dart';

class QuestionPackSelectorWidget extends StatefulWidget {
  final VoidCallback? onPacksChanged;

  const QuestionPackSelectorWidget({
    super.key,
    this.onPacksChanged,
  });

  @override
  State<QuestionPackSelectorWidget> createState() =>
      _QuestionPackSelectorWidgetState();
}

class _QuestionPackSelectorWidgetState
    extends State<QuestionPackSelectorWidget> {
  List<QuestionPack> _availablePacks = [];
  Set<String> _selectedPackIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load all available packs
      final allPacks = await QuestionPackService.getAvailablePacks();

      // Load user's current selections
      final userPacks = await QuestionPackService.getUserPacks();

      setState(() {
        _availablePacks = allPacks;
        _selectedPackIds = Set.from(userPacks.subscribedPackIds);
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading question packs: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSelections() async {
    setState(() => _isLoading = true);

    try {
      // Ensure at least one pack is selected
      if (_selectedPackIds.isEmpty) {
        _selectedPackIds.add('demo_pack');
      }

      await QuestionPackService.updateUserPacks(_selectedPackIds.toList());

      if (widget.onPacksChanged != null) {
        widget.onPacksChanged!();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Question packs updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating packs: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Question Pack Subscriptions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select which question packs you want to receive:',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),
        ..._availablePacks.map((pack) => _buildCompactPackCheckbox(pack)),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: ElevatedButton(
              onPressed: _saveSelections,
              child: const Text('Save Selections'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactPackCheckbox(QuestionPack pack) {
    final isSelected = _selectedPackIds.contains(pack.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CheckboxListTile(
        title: Text(
          '${pack.name} (${pack.questions.length} questions)',
          style: TextStyle(fontSize: 16),
        ),
        dense: true,
        visualDensity: VisualDensity(horizontal: 0, vertical: -4),
        contentPadding: EdgeInsets.zero,
        value: isSelected,
        onChanged: (value) {
          setState(() {
            if (value == true) {
              _selectedPackIds.add(pack.id);
            } else {
              _selectedPackIds.remove(pack.id);
            }
          });
        },
      ),
    );
  }
}
