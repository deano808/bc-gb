# BC-GB Repository Setup Guide

This guide will help you set up your own automated Business Central GB code repository.

## Prerequisites

- Git installed on your machine
- GitHub account
- PowerShell (Windows) or Bash (Linux/Mac)

## Quick Setup

### Option 1: Automated Setup Script (Windows PowerShell)

Save and run the `setup-bc-gb-repo.ps1` script (see below).

### Option 2: Manual Setup

#### Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `bc-gb` (or your preferred name)
3. Description: "Automated mirror of Business Central GB localization code"
4. Choose Public or Private
5. Do NOT initialize with README, .gitignore, or license
6. Click "Create repository"

#### Step 2: Clone and Initialize Locally

```powershell
# Create local directory
mkdir c:\git\bc-gb
cd c:\git\bc-gb

# Initialize git repository
git init
git branch -M main

# Add your GitHub repository as remote (REPLACE YOUR_GITHUB_USERNAME)
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/bc-gb.git
```

#### Step 3: Create Workflow File

Create `.github/workflows/sync-bc-code.yml` with the content provided in this repository.

#### Step 4: Create Version Tracking File

```powershell
# Create .bc-version file
"gb-0" | Out-File -FilePath .bc-version -Encoding utf8 -NoNewline
```

#### Step 5: Create README

Create `README.md` with the content provided in this repository.

#### Step 6: Initial Sync

```powershell
# Add source repository as remote
git remote add source https://github.com/StefanMaron/MSDyn365BC.Code.History.git

# Fetch the latest GB branch
git fetch source gb-27 --depth=1

# Checkout all files from gb-27
git checkout source/gb-27 -- .

# Restore workflow files (if overwritten)
git checkout HEAD -- .github/ .bc-version README.md 2>$null

# Stage and commit
git add -A
git commit -m "Initial sync of Business Central GB code from gb-27

Synced from StefanMaron/MSDyn365BC.Code.History
Branch: gb-27
Date: $(Get-Date -Format 'yyyy-MM-dd')

This is the initial commit containing the complete Business Central GB (Great Britain) localization code."

# Push to GitHub
git push -u origin main
```

#### Step 7: Verify Automation

1. Go to your repository on GitHub
2. Click on the "Actions" tab
3. You should see the workflow "Sync BC GB Code"
4. You can manually trigger it using "Run workflow"

## What Gets Automated

- **Daily Checks**: The workflow runs every day at 2 AM UTC
- **Version Detection**: Automatically finds the latest `gb-XX` branch
- **Smart Updates**: Only syncs when a new version is available
- **Version Tracking**: Updates `.bc-version` file automatically
- **Tagging**: Creates version tags for each sync
- **Manual Trigger**: Run sync anytime from GitHub Actions

## Testing the Setup

To test that everything works:

1. Go to GitHub → Your Repository → Actions
2. Click on "Sync BC GB Code" workflow
3. Click "Run workflow" → "Run workflow"
4. Watch the workflow execute
5. It should detect that you're already on the latest version

## Customization

### Change Sync Schedule

Edit `.github/workflows/sync-bc-code.yml` and modify the cron expression:

```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

Common schedules:
- `'0 0 * * 0'` - Weekly on Sunday at midnight
- `'0 3 * * 1'` - Weekly on Monday at 3 AM
- `'0 2 1 * *'` - Monthly on the 1st at 2 AM

### Track Different Locale

To track a different locale (e.g., `us-27` instead of `gb-27`):

1. Update the grep pattern in the workflow:
   ```bash
   BRANCHES=$(echo "$BRANCHES" | sed 's/gb-//' | sort -n | tail -1)
   ```
   Change `gb-` to your desired prefix (e.g., `us-`, `de-`, `fr-`)

2. Update `.bc-version` with the appropriate starting version

3. Update `README.md` to reflect the locale

## Troubleshooting

### "remote origin already exists"
```powershell
git remote remove origin
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/bc-gb.git
```

### "remote source already exists"
```powershell
git remote remove source
git remote add source https://github.com/StefanMaron/MSDyn365BC.Code.History.git
```

### Large repository size
The BC code is several GB in size. This is normal for a complete Business Central codebase.

### Workflow not running
- Check that the workflow file is in `.github/workflows/` directory
- Ensure GitHub Actions is enabled in your repository settings
- Verify the workflow YAML syntax is correct

## Support

For issues or questions:
- Check the original repository: https://github.com/deano808/bc-gb
- Review GitHub Actions logs for error details
- Consult the source repository: https://github.com/StefanMaron/MSDyn365BC.Code.History

## License

The Business Central code is proprietary to Microsoft Corporation. This setup automates mirroring for reference purposes only.
