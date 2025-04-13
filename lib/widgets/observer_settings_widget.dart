import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/screens/observer_add_responder_screen.dart';

class ObserverSettingsWidget extends StatefulWidget {
  const ObserverSettingsWidget({super.key});

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
        const Text('Polling Interval (minutes)',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
          leading: const Icon(Icons.link),
          title: const Text('Link to a responder'),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ObserverAddResponderScreen(),
            ));
          },
        ),
      ],
    );
  }
}
