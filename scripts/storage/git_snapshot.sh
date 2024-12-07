#!/bin/bash

# Configuration
MAIN_BRANCH="main"
NEW_BRANCH="feature/backup-system"
COMMIT_MSG="feat: System snapshot January 2024

- Complete core storage migration system
- Implemented dashboard with security features
- Added comprehensive documentation
- System ready for backup implementation

Documentation:
- Added PROGRESS.md tracking overall progress
- Added BACKUP_DESIGN.md with detailed backup plans
- Added SNAPSHOT_2024_01.md capturing current state

Technical Details:
- Dashboard operational at toowired.solutions/dashboard
- All core features implemented and tested
- Security measures in place
- System architecture documented

Next Steps:
- Implement backup system
- Enhance monitoring capabilities
- Add system integrations"

# Ensure we're in the right directory
if [ ! -d ".git" ]; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Ensure we're up to date
echo "Fetching latest changes..."
git fetch origin

# Switch to main branch
echo "Switching to ${MAIN_BRANCH}..."
git checkout ${MAIN_BRANCH}

# Add all new files and changes
echo "Adding new files and changes..."
git add .

# Create commit
echo "Creating commit..."
git commit -m "${COMMIT_MSG}"

# Push to main
echo "Pushing to ${MAIN_BRANCH}..."
git push origin ${MAIN_BRANCH}

# Create new branch
echo "Creating new branch ${NEW_BRANCH}..."
git checkout -b ${NEW_BRANCH}

# Push new branch
echo "Pushing new branch..."
git push -u origin ${NEW_BRANCH}

echo "Complete!"
echo "Main branch updated with snapshot"
echo "New branch '${NEW_BRANCH}' created for backup system implementation"
echo ""
echo "Next steps:"
echo "1. Continue work in the '${NEW_BRANCH}' branch"
echo "2. Implement backup system according to BACKUP_DESIGN.md"
echo "3. Create pull requests for major features"