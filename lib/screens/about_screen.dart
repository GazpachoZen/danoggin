// lib/screens/about_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:danoggin/theme/app_colors.dart';
import 'package:danoggin/utils/logger.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = "";
  String _buildNumber = "";
  String _changelogContent = "";
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Load version info
      final packageInfo = await PackageInfo.fromPlatform();
      
      // Load changelog
      final changelogText = await rootBundle.loadString('assets/changelog.md');
      
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
        _changelogContent = changelogText;
        _isLoading = false;
      });

      // Auto-scroll to most recent entry after content loads
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMostRecent();
      });
    } catch (e) {
      Logger().e('Error loading about screen data: $e');
      setState(() {
        _isLoading = false;
        _changelogContent = "Error loading changelog";
      });
    }
  }

  void _scrollToMostRecent() {
    if (_scrollController.hasClients && _changelogContent.isNotEmpty) {
      // Auto-scroll happens naturally since we build newest entries first
      // Just scroll to top to show the most recent entry
      _scrollController.animateTo(
        0.0,
        duration: Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildChangelogContent() {
    if (_changelogContent.isEmpty) {
      return Center(
        child: Text(
          'No changelog available',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final lines = _changelogContent.split('\n');
    final widgets = <Widget>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.isEmpty) {
        widgets.add(SizedBox(height: 4));
      } else if (line.startsWith('# ')) {
        // Main title - skip since we show it in header
        continue;
      } else if (line.startsWith('## ')) {
        // Version headers
        final versionText = line.substring(3);
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 16, bottom: 4),
            child: Text(
              versionText,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.deepBlue,
              ),
            ),
          ),
        );
      } else if (line.startsWith('### ')) {
        // Section headers (Added, Fixed, etc.)
        final sectionText = line.substring(4);
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              sectionText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.midBlue,
              ),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        // Bullet points
        final bulletText = line.substring(2);
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.midBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    bulletText,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (line.isNotEmpty) {
        // Regular paragraphs
        widgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textDark,
                height: 1.4,
              ),
            ),
          ),
        );
      }
    }
    
    // Add bottom padding
    widgets.add(SizedBox(height: 16));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header section with branding and version
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: AppColors.skyBlue.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.deepBlue.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Danoggin icon
                      Image.asset(
                        'assets/images/danoggin_icon.png',
                        width: 48,
                        height: 48,
                      ),
                      const SizedBox(width: 16),
                      // Branding and version info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Danoggin',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.deepBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Version $_version (Build $_buildNumber)',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.deepBlue.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Changelog section header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Release Notes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                
                // Changelog content
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: _buildChangelogContent(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}