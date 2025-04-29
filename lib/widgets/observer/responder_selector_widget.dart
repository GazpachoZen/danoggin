import 'package:flutter/material.dart';

class ResponderSelectorWidget extends StatelessWidget {
  final Map<String, String> responderMap;
  final String? selectedResponderUid;
  final Function(String) onResponderSelected;

  const ResponderSelectorWidget({
    Key? key,
    required this.responderMap,
    required this.selectedResponderUid,
    required this.onResponderSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (responderMap.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Responder:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: responderMap.entries.map((entry) {
                  final isSelected = entry.key == selectedResponderUid;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    onSelected: (_) => onResponderSelected(entry.key),
                    backgroundColor: Colors.grey[200],
                    selectedColor: Colors.deepPurple[100],
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.deepPurple[800] : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}