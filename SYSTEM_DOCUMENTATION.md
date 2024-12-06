# VPS System Documentation

## 🔄 Backup System
- **Location**: All backup configurations and scripts are in the root account
- **Storage**: Using Vultr Object Storage (S3-compatible)
- **Bucket Name**: tysbucket
- **What's Backed Up**:
  - SSH configurations (/etc/ssh)
  - Fail2ban settings (/etc/fail2ban)
  - System configuration files:
    - /etc/fstab
    - /etc/hostname
    - /etc/hosts

### Important Notes
1. **Configuration Location**
   - Vultr storage configuration: `/root/.s3cfg`
   - Backup script: `/root/vps-setup/scripts/backup-script/backup.sh`

2. **Access and Management**
   - All backup operations run under root privileges
   - DO NOT move configurations to user account
   - Use `sudo` when checking backup status

3. **Best Practices**
   - Keep using root account for backup operations
   - Maintain current configuration paths
   - Don't modify backup settings from user account

## 🔒 Vultr Object Storage Management
### Access Setup
- Server backups run as root (automated)
- User storage management runs as 'toowired' (manual)
- Configuration file: `~/.s3cfg` (copied from root)

### Storage Structure
Files are organized using these path prefixes:
- **system_backups/** - Automated server backups (root only)
- **laptop_backups/** - Files backed up from your laptop
- **documents/** - Important documents
- **media/** - Media files (images, videos, etc.)
- **archives/** - Old files for long-term storage

### Storage Management Commands
```bash
# List contents of any folder
s3cmd ls s3://tysbucket/folder_name/

# Upload files
s3cmd put local_file s3://tysbucket/folder_name/

# Download files
s3cmd get s3://tysbucket/folder_name/file local_file

# Move files between folders
s3cmd mv s3://tysbucket/old_path/file s3://tysbucket/new_path/

# Delete files (use with caution)
s3cmd del s3://tysbucket/folder_name/file

# Sync local folder to bucket (useful for laptop backups)
s3cmd sync local_folder/ s3://tysbucket/laptop_backups/

# Get folder size
s3cmd du s3://tysbucket/folder_name/

# List all files recursively
s3cmd ls --recursive s3://tysbucket/
```

### Best Practices for Storage
1. **Organization**
   - System backups are handled automatically by root
   - Personal files can be managed directly without sudo
   - Use appropriate paths for different types of files
   - Keep consistent naming conventions

2. **Maintenance**
   - Regularly clean up old files
   - Check storage usage with `s3cmd du`
   - Keep folder structure organized
   - Use descriptive file names

3. **Backup Strategy**
   - Server: Automated backups to system_backups/
   - Laptop: Manual uploads to laptop_backups/
   - Important files: Store in documents/
   - Large media: Use media/ folder
   - Old files: Move to archives/

## 🔒 Security Setup
- Fail2ban active for intrusion prevention
- SSH secured with root login restrictions
- System files regularly backed up
- Permissions properly segregated between root and user accounts

## 👤 User Management
- Regular server operations: Use 'toowired' account
- Backup/security management: Use root account when necessary
- Keep this separation for security purposes

## ⚠️ Important Warnings
1. DO NOT:
   - Move backup configurations from root
   - Change backup script locations
   - Modify Vultr storage settings without backup
   - Change file permissions of backup components

2. DO:
   - Keep backup system under root
   - Maintain current file structure
   - Use sudo for checking backup status
   - Keep this documentation updated

## 📋 Quick Reference
To check backup status (requires sudo):
```bash
# View backup script
sudo cat /root/vps-setup/scripts/backup-script/backup.sh

# Check backup schedule
sudo crontab -l

# View recent backups
sudo s3cmd ls s3://tysbucket/system_backups/
```

## 🔄 Recovery Procedures
1. In case of issues:
   - First check root's crontab for backup schedule
   - Verify Vultr storage configuration in root's home
   - Check backup script permissions
   - Review system logs for backup operations

2. If system needs restore:
   - Access Vultr Object Storage
   - Locate latest backup in tysbucket
   - Download and extract to appropriate locations

## 📝 Maintenance Notes
- Keep root account secure
- Regularly verify backup success
- Monitor storage usage in Vultr
- Check system logs periodically

## 🔑 Root User Actions Log
### Initial Setup Actions
1. **System Configuration**
   - Created initial backup script in `/root/vps-setup/scripts/backup-script/`
   - Set up Vultr Object Storage configuration in `/root/.s3cfg`
   - Configured automated system backups

2. **Security Setup**
   - Configured Fail2ban for intrusion prevention
   - Set up SSH security restrictions
   - Established root login limitations

3. **Storage Configuration**
   - Created and configured tysbucket in Vultr Object Storage
   - Set up automated backup paths
   - Configured s3cmd for system backups

### Recent Changes
1. **User Management**
   - Created 'toowired' user account
   - Added user to sudo group
   - Shared s3cmd configuration with user account

2. **Permission Updates**
   - Maintained root-level backup automation
   - Allowed user-level storage management
   - Kept system backup security isolated

### Tracking Changes
To maintain this log:
1. Document all root-level changes here
2. Include dates of major system modifications
3. Note any security-related updates
4. Record configuration file changes