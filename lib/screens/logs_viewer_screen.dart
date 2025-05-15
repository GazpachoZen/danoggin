import 'package:flutter/material.dart';
import 'package:danoggin/services/notification_helper.dart';

class LogsViewerScreen extends StatefulWidget {
  const LogsViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogsViewerScreen> createState() => _LogsViewerScreenState();
}

class _LogsViewerScreenState extends State<LogsViewerScreen> {
  List<String> _logs = [];
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }
  
  void _loadLogs() {
    setState(() {
      _logs = NotificationHelper.logs;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              NotificationHelper.clearLogs();
              _loadLogs();
            },
          ),
        ],
      ),
      body: _logs.isEmpty
          ? Center(child: Text('No logs available'))
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Text(
                    _logs[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                      color: _logs[index].contains('ERROR') 
                          ? Colors.red 
                          : Colors.black,
                    ),
                  ),
                );
              },
            ),
    );
  }
}