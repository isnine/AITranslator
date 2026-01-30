# Git History Cleanup Plan for AITranslator

## Overview

This document outlines the steps to remove sensitive secrets from the git history before open-sourcing the repository.

**WARNING: This process rewrites git history and requires force push. All collaborators must re-clone after completion.**

---

## Identified Secrets in Git History

### 1. Azure OpenAI API Key
- **Value:** `[REDACTED]`
- **Found in commits:**
  - `967b02c` - Adjust config
  - `cacfdaa` - Provider build-in TTS
  - `db630c3` - [developer] Support ICloud
  - `09d2c3f` - [Fixed] Adjust Config Load
  - `6161fab` - [Added] Support switch config
  - `ef38ee3` - Back to Azure Server
  - `361d5d1` - [Added] Server support & new action
  - `a40cd71` - [Added] TTS
  - `93dd624` - switch to gpt-5-nano
  - `e963f42` - Fix streaming issue
  - `e3d1b74` - Added UI
- **Files affected:** `AITranslator/Resources/DefaultConfiguration.json`

### 2. HMAC Secret (Built-in Cloud)
- **Value:** `[REDACTED]`
- **Found in commits:**
  - `106e732` - Implement model selection and management UI
  - `0812d5b` - Switch back from diff view
  - `cacfdaa` - Provider build-in TTS
  - `7ccf77c` - Provider build-in server
- **Files affected:**
  - `ShareCore/Configuration/ModelConfig.swift`
  - `ShareCore/Configuration/TTSConfiguration.swift`
  - `ShareCore/Configuration/ProviderConfig.swift` (deleted)
  - `agent.md`

### 3. Azure Endpoint
- **Value:** `[REDACTED]`
- **Found in same commits as Azure API Key**
- **Files affected:** `AITranslator/Resources/DefaultConfiguration.json`

---

## Cleanup Method: git filter-repo

We'll use `git filter-repo` which is the recommended replacement for `git filter-branch`.

### Prerequisites

```bash
# Install git-filter-repo
brew install git-filter-repo

# Or via pip
pip3 install git-filter-repo
```

---

## Step-by-Step Execution Plan

### Step 1: Create Full Backup

```bash
# Create a complete backup of the repository
cd /Users/zander/Work
cp -r AITranslator AITranslator-backup-$(date +%Y%m%d-%H%M%S)

# Also create a git bundle backup
cd AITranslator
git bundle create ../AITranslator-backup-$(date +%Y%m%d-%H%M%S).bundle --all
```

### Step 2: Create Replacement File

Create a file `replacements.txt` with the secrets to replace:

```bash
cat > /tmp/aitranslator-replacements.txt << 'EOF'
YOUR_AZURE_API_KEY==>REDACTED_AZURE_API_KEY
YOUR_HMAC_SECRET==>REDACTED_HMAC_SECRET
YOUR_AZURE_ENDPOINT==>REDACTED_AZURE_ENDPOINT
EOF
```

### Step 3: Run git filter-repo

```bash
cd /Users/zander/Work/AITranslator

# This will rewrite history, replacing all occurrences of the secrets
git filter-repo --replace-text /tmp/aitranslator-replacements.txt --force
```

### Step 4: Verify Cleanup

```bash
# Verify the secrets are gone from history
git log --all -p -S "YOUR_SECRET_HERE" 
# Should return empty

git log --all -p -S "YOUR_HMAC_SECRET_HERE"
# Should return empty

git log --all -p -S "YOUR_ENDPOINT_HERE"
# Should return empty

# Also search for partial matches
git grep -i "YOUR_PARTIAL_SECRET" $(git rev-list --all)
# Should return empty
```

### Step 5: Re-add Remote (filter-repo removes it)

```bash
git remote add origin https://github.com/isnine/AITranslator.git
```

### Step 6: Force Push to Remote

**DANGER ZONE - This rewrites remote history**

```bash
# Force push all branches
git push origin --all --force

# Force push all tags
git push origin --tags --force
```

### Step 7: Notify Collaborators

Send notification to all collaborators:

```
Subject: [ACTION REQUIRED] AITranslator Repository History Rewritten

The AITranslator repository history has been rewritten to remove sensitive data.

You MUST take the following actions:
1. Delete your local clone
2. Re-clone the repository: git clone https://github.com/isnine/AITranslator.git
3. Do NOT attempt to merge your old local branches with the new history

If you have unmerged work, contact the repository owner before taking any action.
```

### Step 8: Request GitHub Cache Cleanup

1. Go to GitHub repository settings
2. Contact GitHub Support to request:
   - Clear cached views
   - Run garbage collection on the repository
   - Remove any cached/reflog commits

Or use the GitHub API:
```bash
# Request garbage collection (may require admin token)
curl -X POST \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/isnine/AITranslator/git/gc
```

### Step 9: Verify Remote is Clean

```bash
# Fresh clone to verify
cd /tmp
git clone https://github.com/isnine/AITranslator.git AITranslator-verify

cd AITranslator-verify
git log --all -p -S "YOUR_SECRET_HERE"
# Should return empty
```

---

## Alternative Method: BFG Repo-Cleaner

If `git filter-repo` is unavailable, use BFG:

```bash
# Install BFG
brew install bfg

# Create replacement file
echo "YOUR_AZURE_API_KEY" > /tmp/secrets-to-remove.txt
echo "YOUR_HMAC_SECRET" >> /tmp/secrets-to-remove.txt
echo "YOUR_AZURE_ENDPOINT" >> /tmp/secrets-to-remove.txt

# Run BFG
cd /Users/zander/Work/AITranslator
bfg --replace-text /tmp/secrets-to-remove.txt

# Cleanup
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

---

## Execution Checklist

Before running the cleanup:

- [ ] Created full backup of repository
- [ ] Rotated/revoked all exposed secrets (see KEY_ROTATION_CHECKLIST.md)
- [ ] All team members notified of upcoming history rewrite
- [ ] All pending PRs merged or documented
- [ ] Verified local code changes are committed

After running the cleanup:

- [ ] Verified secrets removed from all branches
- [ ] Force pushed to remote
- [ ] Notified all collaborators to re-clone
- [ ] Requested GitHub cache cleanup
- [ ] Verified fresh clone is clean
- [ ] Updated any CI/CD that references old commit hashes

---

## Notes

- **Commit hashes will change**: All commits from the first affected commit onwards will have new hashes
- **CI/CD pipelines**: May need to update any hardcoded commit references
- **GitHub Actions caches**: May contain old commits temporarily
- **Forks**: Any public forks will still contain the secrets - contact fork owners

## Timeline Estimate

1. Backup creation: 5 minutes
2. Running filter-repo: 1-5 minutes (depends on repo size)
3. Verification: 10 minutes
4. Force push and notifications: 10 minutes
5. GitHub cache cleanup request: 1-2 business days for GitHub to process

Total active time: ~30 minutes
Total elapsed time: 1-2 days (waiting for GitHub)
