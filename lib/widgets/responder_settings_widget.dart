import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/screens/responder_invite_code_screen.dart';
import 'package:danoggin/screens/responder_manage_observers_screen.dart';
import 'package:danoggin/widgets/question_pack_selector_widget.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/services/auth_service.dart';

class ResponderSettingsWidget extends StatefulWidget {
  // Add callback for relationship changes
  final VoidCallback? onRelationshipsChanged;
  
  const ResponderSettingsWidget({
    super.key,
    this.onRelationshipsChanged,
  });

  @override
  State<ResponderSettingsWidget> createState() =>
      _ResponderSettingsWidgetState();
}

class _ResponderSettingsWidgetState extends State<ResponderSettingsWidget> {
  TimeOfDay startHour = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endHour = const TimeOfDay(hour: 20, minute: 0);
  double alertFrequencyMinutes = 5;
  double timeoutMinutes = 1;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      startHour = _getTimeOfDay(prefs.getString('startHour')) ?? startHour;
      endHour = _getTimeOfDay(prefs.getString('endHour')) ?? endHour;
      alertFrequencyMinutes =
          prefs.getDouble('alertFrequency') ?? alertFrequencyMinutes;
      timeoutMinutes = prefs.getDouble('timeoutDuration') ?? timeoutMinutes;
    });
  }

  TimeOfDay? _getTimeOfDay(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTimeOfDay(TimeOfDay tod) =>
      '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';

  String _formatTimeOfDayAMPM(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final local = TimeOfDay.fromDateTime(dt);
    return local.format(context); // Uses device locale and AM/PM
  }

Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Format the hours for storage
    final startHourStr = _formatTimeOfDay(startHour);
    final endHourStr = _formatTimeOfDay(endHour);
    
    // Save locally to SharedPreferences
    await prefs.setString('startHour', startHourStr);
    await prefs.setString('endHour', endHourStr);
    await prefs.setDouble('alertFrequency', alertFrequencyMinutes);
    await prefs.setDouble('timeoutDuration', timeoutMinutes);
    
    // Sync to Firestore for observer visibility
    try {
      final uid = AuthService.currentUserId;
      await ResponderSettingsRepository.saveActiveHours(
        uid: uid,
        startHour: startHourStr,
        endHour: endHourStr,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error syncing settings to Firestore: $e');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving cloud settings: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pickTime(BuildContext context, bool isStart) async {
    final initialTime = isStart ? startHour : endHour;
    final picked =
        await showTimePicker(context: context, initialTime: initialTime);
    if (picked != null) {
      setState(() {
        if (isStart) {
          startHour = picked;
        } else {
          endHour = picked;
        }
      });
    }
  }

  // Handler for pack selection changes
  void _handlePackSelectionChanged() {
    // Just trigger the callback to parent if needed
    if (widget.onRelationshipsChanged != null) {
      widget.onRelationshipsChanged!();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Go back to using SingleChildScrollView which works better in this context
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16.0),
              child: Text('Hours of Operation',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickTime(context, true),
                  child: Text('Start: ${_formatTimeOfDayAMPM(startHour)}'),
                ),
                TextButton(
                  onPressed: () => _pickTime(context, false),
                  child: Text('End: ${_formatTimeOfDayAMPM(endHour)}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Alert Frequency: ${alertFrequencyMinutes.round()} min',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: alertFrequencyMinutes,
              min: 5,
              max: 360,
              divisions: 71,
              label: '${alertFrequencyMinutes.round()} min',
              onChanged: (val) => setState(() => alertFrequencyMinutes = val),
            ),
            const SizedBox(height: 8),
            Text('Response Timeout: ${timeoutMinutes.toStringAsFixed(1)} min',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: timeoutMinutes,
              min: 0.5,
              max: 10,
              divisions: 19,
              label: '${timeoutMinutes.toStringAsFixed(1)} min',
              onChanged: (val) => setState(() => timeoutMinutes = val),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: _savePrefs,
                child: const Text('Save Settings'),
              ),
            ),
            const Divider(height: 32),
            
            // Add the question pack selector with better spacing
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: QuestionPackSelectorWidget(
                onPacksChanged: _handlePackSelectionChanged,
              ),
            ),
            
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Show my invite code'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResponderInviteCodeScreen(),
                  ),
                );
              },
            ),
            // Add new option for managing observers
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Who is observing me'),
              subtitle: const Text('See and manage observers'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                // Navigate to manage observers screen and await result
                final relationshipsChanged = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const ResponderManageObserversScreen(),
                  ),
                );
                
                // If relationships changed and we have a callback, notify parent
                if (relationshipsChanged == true && widget.onRelationshipsChanged != null) {
                  widget.onRelationshipsChanged!();
                }
              },
            ),
            // Add extra padding at the bottom
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}