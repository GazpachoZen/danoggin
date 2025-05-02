#!/usr/bin/env python3
"""
Version bumper for Flutter pubspec.yaml files.
This script increments the build number while preserving file structure.
"""
import re
import sys

def bump_version(file_path):
    """Bump the build number in pubspec.yaml while preserving formatting."""
    # Read the entire file
    with open(file_path, 'r') as file:
        content = file.readlines()
    
    # Pattern to find the version line
    version_pattern = re.compile(r'^(\s*version:\s*)(\d+\.\d+\.\d+)\+(\d+)(.*)$')
    
    # Track if we found and updated the version
    updated = False
    
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
            
            # Create new line with incremented build number
            content[i] = f"{prefix}{version}+{new_build}{suffix}\n"
            
            print(f"Updated version from {version}+{build} to {version}+{new_build}")
            updated = True
            break
    
    if not updated:
        print("No version pattern found in pubspec.yaml")
        return False
    
    # Write the modified content back
    with open(file_path, 'w') as file:
        file.writelines(content)
    
    return True

if __name__ == "__main__":
    pubspec_path = "pubspec.yaml"
    
    # Allow specifying a different path
    if len(sys.argv) > 1:
        pubspec_path = sys.argv[1]
    
    if bump_version(pubspec_path):
        print("Version bump completed successfully!")
    else:
        print("Version bump failed.")