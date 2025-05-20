// lib/screens/logs_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:danoggin/utils/logger.dart';
import 'package:flutter/services.dart';

class LogsViewerScreen extends StatefulWidget {
  const LogsViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogsViewerScreen> createState() => _LogsViewerScreenState();
}

class _LogsViewerScreenState extends State<LogsViewerScreen> {
  List<String> _allLogs = []; // All logs without filtering
  List<String> _filteredLogs = []; // Filtered logs for display
  LogLevel _selectedLogLevel = Logger().logLevel; // Get current log level
  
  // String representations for log levels (for nice display)
  final Map<LogLevel, String> _logLevelNames = {
    LogLevel.verbose: 'Verbose',
    LogLevel.debug: 'Debug',
    LogLevel.info: 'Info',
    LogLevel.warning: 'Warning',
    LogLevel.error: 'Error',
    LogLevel.none: 'None',
  };

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    setState(() {
      _allLogs = Logger().logs;
      _applyLogLevelFilter();
    });
  }
  
  // Apply the current log level filter to all logs
  void _applyLogLevelFilter() {
    if (_selectedLogLevel == LogLevel.none) {
      _filteredLogs = []; // No logs should be shown
    } else if (_selectedLogLevel == LogLevel.verbose) {
      _filteredLogs = List.from(_allLogs); // Show all logs
    } else {
      // Filter logs based on their level
      _filteredLogs = _allLogs.where((log) {
        // Extract the log level from the log string
        if (log.contains('[ERROR]')) {
          return LogLevel.error.index >= _selectedLogLevel.index;
        } else if (log.contains('[WARNING]')) {
          return LogLevel.warning.index >= _selectedLogLevel.index;
        } else if (log.contains('[INFO]')) {
          return LogLevel.info.index >= _selectedLogLevel.index;
        } else if (log.contains('[DEBUG]')) {
          return LogLevel.debug.index >= _selectedLogLevel.index;
        } else if (log.contains('[VERBOSE]')) {
          return LogLevel.verbose.index >= _selectedLogLevel.index;
        } else {
          // Default to INFO level for logs without explicit level
          return LogLevel.info.index >= _selectedLogLevel.index;
        }
      }).toList();
    }
  }
  
  void _changeLogLevel(LogLevel? newLevel) {
    if (newLevel != null) {
      setState(() {
        _selectedLogLevel = newLevel;
        Logger().setLogLevel(newLevel);
        
        // Apply filter to existing logs
        _applyLogLevelFilter();
        
        // Show a confirmation message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Log level set to ${_logLevelNames[newLevel]}'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Logs'),
        actions: [
          // Log level dropdown in app bar
          DropdownButton<LogLevel>(
            value: _selectedLogLevel,
            dropdownColor: Theme.of(context).primaryColor,
            underline: Container(), // Remove the default underline
            icon: Icon(Icons.filter_list, color: Colors.white),
            onChanged: _changeLogLevel,
            items: LogLevel.values.map<DropdownMenuItem<LogLevel>>((LogLevel level) {
              return DropdownMenuItem<LogLevel>(
                value: level,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _logLevelNames[level] ?? level.toString().split('.').last,
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
            icon: const Icon(Icons.copy),
            tooltip: 'Copy All Logs',
            onPressed: _copyLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Logger().clearLogs();
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
      // Add a footer to show log count
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

  void _copyLogs() {
    if (_filteredLogs.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No logs to copy')));
      return;
    }

    // Join all filtered logs with newlines
    final String allLogs = _filteredLogs.join('\n');

    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: allLogs)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filtered logs copied to clipboard (${_filteredLogs.length} entries)'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }
}