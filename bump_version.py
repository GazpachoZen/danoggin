#!/usr/bin/env python3
"""
Version bumper for Flutter projects.
This script increments the build number in pubspec.yaml and updates the
corresponding version in android/app/build.gradle.
"""
import re
import sys
import os

def bump_version(pubspec_path):
    """Bump the build number in pubspec.yaml while preserving formatting."""
    # Read the entire file
    with open(pubspec_path, 'r') as file:
        content = file.readlines()
    
    # Pattern to find the version line
    version_pattern = re.compile(r'^(\s*version:\s*)(\d+\.\d+\.\d+)\+(\d+)(.*)$')
    
    # Track if we found and updated the version
    updated = False
    new_version = ""
    new_build = 0
    
    # Process each line
    for i, line in enumerate(content):
        match = version_pattern.match(line)
        if match:
            # Extract components
            prefix = match.group(1)  # The "version: " part with spacing
            version = match.group(2)  # The semantic version (e.g., "1.0.0")
            build = int(match.group(3))  # The build number
            suffix = match.group(4)  # Any trailing content
            
            # Increment build number
            new_build = build + 1
            new_version = version
            
            # Create new line with incremented build number
            content[i] = f"{prefix}{version}+{new_build}{suffix}\n"
            
            print(f"Updated pubspec.yaml version from {version}+{build} to {version}+{new_build}")
            updated = True
            break
    
    if not updated:
        print("No version pattern found in pubspec.yaml")
        return False, None, None
    
    # Write the modified content back
    with open(pubspec_path, 'w') as file:
        file.writelines(content)
    
    return True, new_version, new_build

def update_gradle(gradle_path, version_name, version_code):
    """Update the version information in build.gradle."""
    if not os.path.exists(gradle_path):
        print(f"Cannot find build.gradle at {gradle_path}")
        return False
    
    with open(gradle_path, 'r') as file:
        content = file.readlines()
    
    # Patterns to find the version code and version name
    version_code_pattern = re.compile(r'^(\s*versionCode\s+)(\d+)(.*)$')
    version_name_pattern = re.compile(r'^(\s*versionName\s+["|\'])(.+)(["|\'].*)$')
    
    # Track which version properties we've updated
    updated_code = False
    updated_name = False
    
    # Process each line
    for i, line in enumerate(content):
        # Check for versionCode
        code_match = version_code_pattern.match(line)
        if code_match and not updated_code:
            prefix = code_match.group(1)
            suffix = code_match.group(3)
            content[i] = f"{prefix}{version_code}{suffix}\n"
            updated_code = True
            print(f"Updated build.gradle versionCode to {version_code}")
            continue
        
        # Check for versionName
        name_match = version_name_pattern.match(line)
        if name_match and not updated_name:
            prefix = name_match.group(1)
            suffix = name_match.group(3)
            content[i] = f"{prefix}{version_name}{suffix}\n"
            updated_name = True
            print(f"Updated build.gradle versionName to {version_name}")
            continue
    
    # Check if we were able to update both properties
    if not (updated_code and updated_name):
        # If we couldn't find explicit version props, look for Flutter's default pattern
        flutter_pattern = re.compile(r'^\s*(versionCode|versionName)\s+flutter')
        has_flutter_version = any(flutter_pattern.match(line) for line in content)
        
        if has_flutter_version:
            print("Version properties in build.gradle are using Flutter's defaults.")
            print(f"Make sure your pubspec.yaml version ({version_name}+{version_code}) is correct.")
            return True
        else:
            print("Could not locate version properties in build.gradle")
            return False
    
    # Write the modified content back
    with open(gradle_path, 'w') as file:
        file.writelines(content)
    
    return True

if __name__ == "__main__":
    pubspec_path = "pubspec.yaml"
    gradle_path = "android/app/build.gradle"
    
    # Allow specifying different paths
    if len(sys.argv) > 1:
        pubspec_path = sys.argv[1]
    if len(sys.argv) > 2:
        gradle_path = sys.argv[2]
    
    # First update pubspec.yaml
    success, version_name, version_code = bump_version(pubspec_path)
    
    if success:
        print("Version bump in pubspec.yaml completed successfully!")
        
        # Then update build.gradle
        if update_gradle(gradle_path, version_name, version_code):
            print("Version update in build.gradle completed successfully!")
            print(f"Your app version is now: {version_name}+{version_code}")
        else:
            print("Warning: Version update in build.gradle failed.")
            print("You may need to manually update the version in build.gradle.")
    else:
        print("Version bump failed.")