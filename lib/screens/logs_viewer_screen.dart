import 'package:danoggin/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:danoggin/services/log_service.dart';

class LogsViewerScreen extends StatefulWidget {
  const LogsViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogsViewerScreen> createState() => _LogsViewerScreenState();
}

class _LogsViewerScreenState extends State<LogsViewerScreen> {
  List<String> _allLogs = [];
  List<String> _filteredLogs = [];
  LogLevel _selectedLogLevel = LogService().logLevel;
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    setState(() {
      _allLogs = LogService().logs;
      _filteredLogs = LogService().getFilteredLogs(_selectedLogLevel);
    });
  }
  
  void _changeLogLevel(LogLevel? newLevel) {
    if (newLevel != null) {
      setState(() {
        _selectedLogLevel = newLevel;
        LogService().setLogLevel(newLevel);
        _filteredLogs = LogService().getFilteredLogs(newLevel);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Log level set to ${LogService().getLevelName(newLevel)}'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
  }

  Future<void> _emailLogs() async {
    final result = await LogService().emailLogs(context);
    
    if (result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening email app with logs attached'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(),
        actions: [
          DropdownButton<LogLevel>(
            value: _selectedLogLevel,
            dropdownColor: Theme.of(context).primaryColor,
            underline: Container(),
            icon: Icon(Icons.filter_list, color: Colors.white),
            onChanged: _changeLogLevel,
            items: LogLevel.values.map<DropdownMenuItem<LogLevel>>((LogLevel level) {
              return DropdownMenuItem<LogLevel>(
                value: level,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    LogService().getLevelName(level),
                    style: TextStyle(
                      color: _selectedLogLevel == level 
                          ? Colors.white 
                          : Colors.white70,
                      fontWeight: _selectedLogLevel == level 
                          ? FontWeight.bold 
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.email),
            tooltip: 'Email Logs',
            onPressed: _emailLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              LogService().clearLogs();
              _loadLogs();
            },
          ),
        ],
      ),
      body: _filteredLogs.isEmpty
          ? Center(child: Text('No logs available for the selected level'))
          : ListView.builder(
              itemCount: _filteredLogs.length,
              itemBuilder: (context, index) {
                final logLine = _filteredLogs[index];
                
                // Determine log entry color based on level
                Color logColor = Colors.black;
                if (logLine.contains('[ERROR]')) {
                  logColor = Colors.red;
                } else if (logLine.contains('[WARNING]')) {
                  logColor = Colors.orange;
                } else if (logLine.contains('[DEBUG]')) {
                  logColor = Colors.blue;
                } else if (logLine.contains('[VERBOSE]')) {
                  logColor = Colors.grey;
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Text(
                    logLine,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                      color: logColor,
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: Container(
        height: 24,
        color: Colors.grey[200],
        child: Center(
          child: Text(
            'Showing ${_filteredLogs.length} of ${_allLogs.length} logs',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
      ),
    );
  }
}