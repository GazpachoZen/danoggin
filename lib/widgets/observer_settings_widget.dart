import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/screens/observer_manage_responders_screen.dart';

class ObserverSettingsWidget extends StatefulWidget {
  // Add a callback for relationship changes
  final VoidCallback? onRelationshipsChanged;
  
  const ObserverSettingsWidget({
    super.key, 
    this.onRelationshipsChanged,
  });

  @override
  State<ObserverSettingsWidget> createState() => _ObserverSettingsWidgetState();
}

class _ObserverSettingsWidgetState extends State<ObserverSettingsWidget> {
  double pollingIntervalMinutes = 2;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pollingIntervalMinutes = prefs.getDouble('observerPollInterval') ?? 2;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('observerPollInterval', pollingIntervalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Polling interval: ${pollingIntervalMinutes.round()} minutes', 
                style: TextStyle(fontSize: 16, color: Colors.deepPurple)),
            Text('Range: 1-10', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        Slider(
          value: pollingIntervalMinutes,
          min: 1,
          max: 10,
          divisions: 9,
          label: '${pollingIntervalMinutes.round()} min',
          onChanged: (val) => setState(() => pollingIntervalMinutes = val),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: _savePrefs,
            child: const Text('Save Settings'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.people),
          title: const Text('Manage Responders'),
          subtitle: const Text('Add or remove people you monitor'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async {
            // Wait for result from manage responders screen
            final relationshipsChanged = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => const ObserverManageRespondersScreen(),
              ),
            );
            
            // If relationships changed, notify our parent
            if (relationshipsChanged == true && widget.onRelationshipsChanged != null) {
              widget.onRelationshipsChanged!();
            }
          },
        ),
      ],
    );
  }
}