#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated setup script for BC-GB repository synchronization.

.DESCRIPTION
    This script sets up a local repository that automatically synchronizes with the latest
    Business Central GB localization code from StefanMaron/MSDyn365BC.Code.History.

.PARAMETER GitHubUsername
    Your GitHub username (required)

.PARAMETER RepoName
    Name for the repository (default: bc-gb)

.PARAMETER LocalPath
    Local path where the repository will be created (default: c:\git\bc-gb)

.PARAMETER Locale
    The BC locale to track (default: gb). Examples: us, de, fr, etc.

.PARAMETER SkipInitialSync
    Skip the initial code sync (useful for testing)

.EXAMPLE
    .\setup-bc-gb-repo.ps1 -GitHubUsername "yourusername"

.EXAMPLE
    .\setup-bc-gb-repo.ps1 -GitHubUsername "yourusername" -Locale "us" -RepoName "bc-us"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Your GitHub username")]
    [string]$GitHubUsername,
    
    [Parameter(Mandatory=$false)]
    [string]$RepoName = "bc-gb",
    
    [Parameter(Mandatory=$false)]
    [string]$LocalPath = "c:\git\bc-gb",
    
    [Parameter(Mandatory=$false)]
    [string]$Locale = "gb",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipInitialSync
)

# Color output functions
function Write-Step {
    param([string]$Message)
    Write-Host "`n✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

# Main script
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  BC-GB Repository Setup Script" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

Write-Info "Configuration:"
Write-Info "  GitHub Username: $GitHubUsername"
Write-Info "  Repository Name: $RepoName"
Write-Info "  Local Path: $LocalPath"
Write-Info "  Locale: $Locale"
Write-Info "  Skip Initial Sync: $SkipInitialSync"

# Step 1: Check prerequisites
Write-Step "Checking prerequisites..."

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not installed or not in PATH"
    exit 1
}
Write-Info "Git: $(git --version)"

# Step 2: Create local directory
Write-Step "Creating local directory..."

if (Test-Path $LocalPath) {
    Write-Warning "Directory already exists: $LocalPath"
    $response = Read-Host "Delete and recreate? (y/N)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Remove-Item -Path $LocalPath -Recurse -Force
        Write-Info "Deleted existing directory"
    } else {
        Write-Error "Setup cancelled"
        exit 1
    }
}

New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
Set-Location $LocalPath
Write-Info "Created: $LocalPath"

# Step 3: Initialize Git repository
Write-Step "Initializing Git repository..."

git init
git branch -M main
Write-Info "Initialized Git repository on 'main' branch"

# Step 4: Add remotes
Write-Step "Adding Git remotes..."

git remote add origin "https://github.com/$GitHubUsername/$RepoName.git"
Write-Info "Added origin: https://github.com/$GitHubUsername/$RepoName.git"

git remote add source "https://github.com/StefanMaron/MSDyn365BC.Code.History.git"
Write-Info "Added source: StefanMaron/MSDyn365BC.Code.History"

# Step 5: Create workflow directory
Write-Step "Creating workflow files..."

New-Item -ItemType Directory -Path ".github\workflows" -Force | Out-Null

# Create workflow file
$workflowContent = @"
name: Sync BC GB Code

on:
  schedule:
    # Run daily at 2 AM UTC
    - cron: '0 2 * * *'
  workflow_dispatch: # Allow manual trigger

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: `${{ secrets.GITHUB_TOKEN }}
      
      - name: Configure Git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
      
      - name: Get current version
        id: current
        run: |
          if [ -f .bc-version ]; then
            CURRENT_VERSION=`$(cat .bc-version)
            echo "Current version: `$CURRENT_VERSION"
            echo "version=`$CURRENT_VERSION" >> `$GITHUB_OUTPUT
          else
            echo "No version file found, will sync latest"
            echo "version=$Locale-0" >> `$GITHUB_OUTPUT
          fi
      
      - name: Fetch latest $Locale version from source repo
        id: latest
        run: |
          # Get all branches from source repo
          BRANCHES=`$(curl -s "https://api.github.com/repos/StefanMaron/MSDyn365BC.Code.History/branches?per_page=100")
          
          # Extract $Locale-* branches and find highest version
          LATEST_VERSION=`$(echo "`$BRANCHES" | jq -r '.[].name' | grep '^$Locale-' | sed 's/$Locale-//' | sort -n | tail -1)
          LATEST_BRANCH="$Locale-`$LATEST_VERSION"
          
          echo "Latest version: `$LATEST_BRANCH"
          echo "branch=`$LATEST_BRANCH" >> `$GITHUB_OUTPUT
          echo "version=`$LATEST_VERSION" >> `$GITHUB_OUTPUT
      
      - name: Check if update needed
        id: check
        run: |
          CURRENT="`${{ steps.current.outputs.version }}"
          LATEST="`${{ steps.latest.outputs.branch }}"
          
          if [ "`$CURRENT" = "`$LATEST" ]; then
            echo "Already up to date with `$LATEST"
            echo "update_needed=false" >> `$GITHUB_OUTPUT
          else
            echo "Update needed: `$CURRENT -> `$LATEST"
            echo "update_needed=true" >> `$GITHUB_OUTPUT
          fi
      
      - name: Add source repository as remote
        if: steps.check.outputs.update_needed == 'true'
        run: |
          git remote add source https://github.com/StefanMaron/MSDyn365BC.Code.History.git || true
          git remote set-url source https://github.com/StefanMaron/MSDyn365BC.Code.History.git
      
      - name: Fetch and sync latest version
        if: steps.check.outputs.update_needed == 'true'
        run: |
          BRANCH="`${{ steps.latest.outputs.branch }}"
          echo "Fetching `$BRANCH from source repository..."
          
          # Fetch only the specific branch with shallow history
          git fetch source `$BRANCH --depth=1
          
          # Remove all files except .git, .github, .bc-version, README.md, and setup files
          find . -maxdepth 1 ! -name '.git' ! -name '.github' ! -name '.bc-version' ! -name 'README.md' ! -name 'SETUP.md' ! -name 'setup-bc-gb-repo.ps1' ! -name '.' -exec rm -rf {} +
          
          # Checkout files from the source branch
          git checkout source/`$BRANCH -- . || true
          
          # Restore our workflow files and metadata
          git checkout HEAD -- .github/ .bc-version README.md SETUP.md setup-bc-gb-repo.ps1 2>/dev/null || true
      
      - name: Update version file
        if: steps.check.outputs.update_needed == 'true'
        run: |
          echo "`${{ steps.latest.outputs.branch }}" > .bc-version
          git add .bc-version
      
      - name: Commit and push changes
        if: steps.check.outputs.update_needed == 'true'
        run: |
          git add -A
          
          if git diff --staged --quiet; then
            echo "No changes to commit"
          else
            BRANCH="`${{ steps.latest.outputs.branch }}"
            git commit -m "Sync to Business Central `$BRANCH

Automated sync from StefanMaron/MSDyn365BC.Code.History
Source branch: `$BRANCH
Sync date: `$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
            
            git push origin main
            echo "Successfully synced to `$BRANCH"
          fi
      
      - name: Create release tag
        if: steps.check.outputs.update_needed == 'true'
        env:
          GITHUB_TOKEN: `${{ secrets.GITHUB_TOKEN }}
        run: |
          BRANCH="`${{ steps.latest.outputs.branch }}"
          TAG_NAME="sync-`$BRANCH-`$(date +%Y%m%d)"
          
          git tag -a "`$TAG_NAME" -m "Business Central `$BRANCH code sync"
          git push origin "`$TAG_NAME" || echo "Tag already exists or push failed"
      
      - name: Summary
        run: |
          if [ "`${{ steps.check.outputs.update_needed }}" = "true" ]; then
            echo "✅ Successfully synced to `${{ steps.latest.outputs.branch }}"
          else
            echo "ℹ️ Already up to date with `${{ steps.current.outputs.version }}"
          fi
"@

$workflowContent | Out-File -FilePath ".github\workflows\sync-bc-code.yml" -Encoding utf8
Write-Info "Created workflow file"

# Step 6: Create .bc-version file
Write-Step "Creating version tracking file..."

"$Locale-0" | Out-File -FilePath ".bc-version" -Encoding utf8 -NoNewline
Write-Info "Created .bc-version"

# Step 7: Create README
Write-Step "Creating README..."

$readmeContent = @"
# Business Central $($Locale.ToUpper()) Code Repository

This repository contains an automatically synchronized copy of the latest Microsoft Dynamics 365 Business Central $($Locale.ToUpper()) localization code.

## 🎯 Purpose

This repo maintains a current snapshot of the BC $($Locale.ToUpper()) codebase from [StefanMaron/MSDyn365BC.Code.History](https://github.com/StefanMaron/MSDyn365BC.Code.History), making it easy to reference, search, and track changes to the $($Locale.ToUpper()) localization without cloning the entire multi-branch history repository.

## 🔄 Automatic Synchronization

- **Source**: ``StefanMaron/MSDyn365BC.Code.History`` (branch pattern: ``$Locale-XX``)
- **Update Frequency**: Daily at 2 AM UTC
- **Current Version**: See [.bc-version](.bc-version) file

The repository automatically checks for new $($Locale.ToUpper()) versions daily and updates when a newer version is available.

## 📋 What's Included

- Complete Business Central $($Locale.ToUpper()) localization code
- Application objects (tables, pages, codeunits, reports, etc.)
- Test frameworks and libraries
- Localization-specific implementations

## 🚀 Usage

### Clone this repository

``````bash
git clone https://github.com/$GitHubUsername/$RepoName.git
cd $RepoName
``````

### View current version

``````bash
cat .bc-version
``````

### Manual sync trigger

Go to **Actions** → **Sync BC $($Locale.ToUpper()) Code** → **Run workflow**

## 📊 Automation Details

The GitHub Actions workflow:
1. Checks daily for new ``$Locale-XX`` versions
2. Compares with current ``.bc-version``
3. If newer version found:
   - Fetches new branch content
   - Updates all files
   - Commits with descriptive message
   - Creates version tag
   - Pushes to repository

## 🔧 Setup

To replicate this setup in your own repository, see [SETUP.md](SETUP.md).

## 📝 Version History

Each sync creates a commit and tag. View the history:
- Commits: Shows all synced versions
- Tags: Named as ``sync-$Locale-XX-YYYYMMDD``

## ⚠️ Disclaimer

All code is owned by Microsoft Corporation. This repository is for reference and development purposes only.

This is a mirror repository - no pull requests are accepted as the source code comes from Microsoft's Business Central product.

## 📄 License

The Business Central code is proprietary to Microsoft Corporation. Refer to Microsoft's licensing terms for usage rights.

## 🔗 Links

- **Source Repository**: [StefanMaron/MSDyn365BC.Code.History](https://github.com/StefanMaron/MSDyn365BC.Code.History)
- **Microsoft Dynamics 365 Business Central**: [Official Site](https://dynamics.microsoft.com/en-us/business-central/overview/)

---

*Last updated: $(Get-Date -Format 'yyyy-MM-dd')*
"@

$readmeContent | Out-File -FilePath "README.md" -Encoding utf8
Write-Info "Created README.md"

# Step 8: Copy setup files to repo
Write-Step "Copying setup files..."

Copy-Item -Path $PSCommandPath -Destination "setup-bc-gb-repo.ps1" -Force
Write-Info "Copied setup script"

# Step 9: Commit setup files
Write-Step "Committing setup files..."

git add .github/ .bc-version README.md setup-bc-gb-repo.ps1
git commit -m "Initial setup: Add automation for BC $($Locale.ToUpper()) code sync

- GitHub Actions workflow for daily sync
- Version tracking file
- Documentation and setup script"

Write-Info "Committed setup files"

# Step 10: Initial sync (optional)
if (-not $SkipInitialSync) {
    Write-Step "Performing initial code sync..."
    Write-Warning "This will download several GB of data and may take 10-30 minutes"
    
    $response = Read-Host "Continue with initial sync? (Y/n)"
    if ($response -eq 'n' -or $response -eq 'N') {
        Write-Info "Skipping initial sync"
    } else {
        Write-Info "Fetching latest $Locale branch..."
        
        # Get latest version
        $branches = Invoke-RestMethod -Uri "https://api.github.com/repos/StefanMaron/MSDyn365BC.Code.History/branches?per_page=100"
        $latestVersion = ($branches | Where-Object { $_.name -match "^$Locale-\d+" } | ForEach-Object { 
            [int]($_.name -replace "$Locale-", "")
        } | Measure-Object -Maximum).Maximum
        $latestBranch = "$Locale-$latestVersion"
        
        Write-Info "Latest version: $latestBranch"
        
        git fetch source $latestBranch --depth=1
        git checkout "source/$latestBranch" -- .
        
        # Restore our files
        git checkout HEAD -- .github/ .bc-version README.md setup-bc-gb-repo.ps1 2>$null
        
        # Update version
        $latestBranch | Out-File -FilePath ".bc-version" -Encoding utf8 -NoNewline
        
        git add -A
        git commit -m "Initial sync of Business Central $($Locale.ToUpper()) code from $latestBranch

Synced from StefanMaron/MSDyn365BC.Code.History
Branch: $latestBranch
Date: $(Get-Date -Format 'yyyy-MM-dd')

This is the initial commit containing the complete Business Central $($Locale.ToUpper()) localization code."
        
        Write-Info "Initial sync complete"
    }
}

# Step 11: Push to GitHub
Write-Step "Pushing to GitHub..."

Write-Info "Attempting to push to: https://github.com/$GitHubUsername/$RepoName.git"
Write-Warning "Make sure you have created the repository on GitHub first!"
Write-Warning "Repository URL: https://github.com/new"

$response = Read-Host "Ready to push? (Y/n)"
if ($response -ne 'n' -and $response -ne 'N') {
    git push -u origin main
    
    if ($LASTEXITCODE -eq 0) {
        Write-Step "Setup complete! 🎉"
        Write-Info "Repository: https://github.com/$GitHubUsername/$RepoName"
        Write-Info "Actions: https://github.com/$GitHubUsername/$RepoName/actions"
    } else {
        Write-Error "Push failed. Please check:"
        Write-Info "1. Repository exists on GitHub"
        Write-Info "2. You have push access"
        Write-Info "3. GitHub credentials are configured"
    }
} else {
    Write-Info "Skipped push to GitHub"
    Write-Info "To push later, run: git push -u origin main"
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  Next Steps:" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta
Write-Info "1. Go to https://github.com/$GitHubUsername/$RepoName"
Write-Info "2. Check the Actions tab to see the workflow"
Write-Info "3. Manually trigger a sync to test: Actions → Sync BC $($Locale.ToUpper()) Code → Run workflow"
Write-Info "4. Share the SETUP.md with team members"
Write-Host ""
