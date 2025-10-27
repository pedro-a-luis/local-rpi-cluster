# Synology DS118 High CPU/RAM Usage Investigation

**Date**: October 27, 2025
**Issue**: Synology DS118 using 30% CPU and RAM continuously

---

## Current Status

### Cluster-Side (Normal):
- ✅ MinIO pod: 23m CPU (very low), 709 MB RAM
- ✅ No active backup jobs running
- ✅ Kopia maintenance now every 6 hours (just updated)
- ✅ No heavy NFS traffic from cluster

### Synology-Side (High Usage):
- ⚠️ **30% CPU usage** (continuous)
- ⚠️ **30% RAM usage** (continuous)
- This is happening **on the Synology itself**, not the cluster

---

## Root Cause Analysis

The 30% CPU/RAM usage on your Synology DS118 is likely **NOT** caused by the Kubernetes cluster's NFS access. Here's why:

### Evidence:
1. **Cluster NFS activity is minimal**:
   - No active backup jobs
   - MinIO using only 23 millicores (0.023 CPU cores)
   - Kopia maintenance now runs only 4x/day (down from 24x)

2. **Synology is doing the work**:
   - The CPU/RAM usage is on the **Synology NAS**, not the cluster
   - This suggests Synology's own services are causing the load

---

## Most Likely Causes (Synology-Side)

### 1. 🔍 **Universal Search / Indexing Service**

**What it does**:
- Synology indexes all files for quick searching
- Scans `/volume1/pi-cluster-data` continuously
- Reads file metadata, content for indexing
- This happens in the background

**Impact**:
- High CPU for indexing
- High RAM for index database
- **Can use 20-40% CPU/RAM on DS118**

**How to check**:
1. Go to DSM → **Control Panel** → **Indexing Service**
2. Check if indexing is enabled
3. Look at "Indexed Folders" - is `/volume1/pi-cluster-data` included?

**Solution**:
```
DSM → Control Panel → Indexing Service
→ Uncheck "/volume1/pi-cluster-data" from indexed folders
→ Click "Reindex" if needed to stop current indexing
```

**Why this helps**:
- Backup data doesn't need to be searchable
- Kopia files are binary/compressed - useless to index
- Stops continuous file scanning

---

### 2. 🛡️ **Antivirus / Anti-Malware Scanning**

**What it does**:
- Scans files for viruses
- Real-time protection monitors file changes
- Scans new/modified files automatically

**Impact**:
- Scans Velero backup files continuously
- Each Kopia maintenance creates/modifies files
- **Can use 15-30% CPU/RAM**

**How to check**:
1. DSM → **Package Center** → **Installed**
2. Look for "Antivirus Essential" or similar
3. Check if it's running

**Solution**:
```
DSM → Antivirus Essential → Settings
→ Add exception for "/volume1/pi-cluster-data"
OR
→ Disable real-time protection for this folder
```

**Why this helps**:
- Backup files are trusted (from your own cluster)
- No viruses in Kopia repository files
- Scanning compressed backups is wasteful

---

### 3. 📸 **Thumbnail Generation**

**What it does**:
- Generates thumbnails for photos/videos
- Can try to process non-image files
- Runs in background

**Impact**:
- May try to process backup files
- **Can use 10-20% CPU**

**How to check**:
1. DSM → **Control Panel** → **Media Index Service** (or Photo Station settings)
2. Check indexed folders

**Solution**:
```
DSM → Control Panel → Media Index Service
→ Remove "/volume1/pi-cluster-data" from indexed folders
```

---

### 4. 🔄 **Cloud Sync / Hyper Backup**

**What it does**:
- Syncs files to cloud storage
- Creates backups of NAS data
- Monitors for file changes

**Impact**:
- Could be backing up your backups!
- **Can use 20-40% CPU/RAM**

**How to check**:
1. DSM → **Main Menu** → Check for "Cloud Sync" or "Hyper Backup"
2. See if any tasks involve `/volume1/pi-cluster-data`

**Solution**:
```
DSM → Cloud Sync (or Hyper Backup)
→ Exclude "/volume1/pi-cluster-data" from sync/backup tasks
OR
→ Pause/stop tasks backing up this folder
```

**Why this helps**:
- You don't need to backup your backups
- Cluster already handles redundancy
- Reduces double-work

---

### 5. 📊 **File Access Logging**

**What it does**:
- Logs every file access for security
- Tracks who accessed what files
- Can create large logs

**Impact**:
- High I/O from logging
- **Can use 5-15% CPU/RAM**

**How to check**:
1. DSM → **Control Panel** → **Security** → **Account**
2. Check "Enable file access logging"

**Solution**:
```
DSM → Control Panel → Security → Account
→ Uncheck "Enable file access logging" for /volume1/pi-cluster-data
OR
→ Disable file access logging entirely (if not needed)
```

---

### 6. 💾 **BTRFS Snapshot/Checksum**

**What it does**:
- BTRFS filesystem takes snapshots
- Verifies data checksums
- Background scrubbing

**Impact**:
- Can run background verification
- **Moderate CPU/RAM usage**

**How to check**:
1. DSM → **Storage Manager** → **Volume**
2. Check if BTRFS snapshots are enabled
3. Look at snapshot schedule

**Solution**:
- Snapshots are good for data protection
- But for backup data, might be overkill
- Consider disabling snapshots for `/volume1/pi-cluster-data`

---

## Recommended Actions (Priority Order)

### 1️⃣ **Disable Indexing** (MOST LIKELY CAUSE)

```
DSM → Control Panel → Indexing Service
→ Exclude /volume1/pi-cluster-data
```

**Expected impact**: Should reduce CPU/RAM by 15-30%

---

### 2️⃣ **Exclude from Antivirus Scanning**

```
DSM → Antivirus Essential → Settings
→ Add /volume1/pi-cluster-data to exclusion list
```

**Expected impact**: Should reduce CPU/RAM by 10-20%

---

### 3️⃣ **Disable Media Indexing**

```
DSM → Control Panel → Media Index Service
→ Remove /volume1/pi-cluster-data from indexed folders
```

**Expected impact**: Should reduce CPU by 5-10%

---

### 4️⃣ **Check Cloud Sync / Hyper Backup**

```
DSM → Check if any backup/sync tasks involve this folder
→ Disable or exclude
```

**Expected impact**: Could reduce CPU/RAM by 20-40% if this is running

---

## How to Diagnose on Synology

### Check Resource Monitor:

1. **DSM → Resource Monitor** (or **Main Menu → Resource Monitor**)

2. **CPU Tab**:
   - See which processes are using CPU
   - Look for:
     - `synoindexd` (Indexing Service)
     - `postgres` (Indexing database)
     - `synoavscan` (Antivirus)
     - `synocloudsyncd` (Cloud Sync)
     - `python` (could be various services)

3. **Memory Tab**:
   - See which processes are using RAM
   - Same processes as above

4. **Network Tab**:
   - See if there's continuous NFS traffic
   - Should be minimal when no backups running

### Check Process List:

```
DSM → Resource Monitor → Process
→ Sort by CPU
→ Identify top processes
```

**Common culprits**:
- `synoindexd` → Indexing
- `synoavscan` → Antivirus
- `postgres` → Database (for indexing)
- `synocloudsyncd` → Cloud sync

---

## If It's NOT a Synology Service

### Possibility: NFS Server Overhead

If it's truly NFS causing the load:

1. **Check NFS connections**:
   ```
   DSM → Control Panel → File Services → NFS
   → See active connections
   ```

2. **NFS logs**:
   ```
   DSM → Log Center → System
   → Filter for NFS-related entries
   ```

3. **Disable NFS features**:
   - Disable NFSv4 if only using NFSv3
   - Reduce NFS threads (if too many)

---

## Quick Test: Stop Indexing

To quickly test if indexing is the problem:

1. **DSM → Control Panel → Indexing Service**
2. Click **"Stop"** button (temporary stop)
3. Wait 5-10 minutes
4. Check CPU/RAM usage again

**If usage drops significantly**: Indexing was the culprit
**If usage stays the same**: Look at other services

---

## What About the Cluster?

### Good News:

The cluster is **not** causing continuous load anymore:

✅ **Logs**: Stored on local Longhorn (not NFS)
✅ **Kopia**: Now runs every 6 hours (not hourly)
✅ **MinIO**: Using only 23m CPU (minimal)
✅ **No active jobs**: Nothing running right now

### Cluster Access Pattern Now:

```
4:30 AM:  [5-10 min backup maintenance]
10:30 AM: [5-10 min backup maintenance]
4:30 PM:  [5-10 min backup maintenance]
10:30 PM: [5-10 min backup maintenance]
2:00 AM:  [20-30 min daily backup]
3:00 AM Sunday: [40-60 min weekly backup]

Rest of time: IDLE
```

**The cluster is accessing the Synology minimally.**

---

## Summary

### Problem:
Synology DS118 using 30% CPU and RAM continuously

### Root Cause:
**Likely NOT the Kubernetes cluster** - it's probably a Synology service:
1. Indexing Service (most likely)
2. Antivirus scanning
3. Cloud Sync / Hyper Backup
4. Media indexing
5. File access logging

### Solution:

**Step 1**: Check DSM Resource Monitor → See what process is using CPU/RAM

**Step 2**: Disable/exclude `/volume1/pi-cluster-data` from:
- ✅ Indexing Service
- ✅ Antivirus scanning
- ✅ Media indexing
- ✅ Cloud Sync / Hyper Backup

**Step 3**: Monitor CPU/RAM usage after changes

**Expected Result**: CPU/RAM should drop to **< 5-10%** when no backups running

---

## Commands to Verify Cluster Activity

### Check if any backups are running NOW:
```bash
kubectl get jobs -n velero | grep -v Completed
```

### Check current NFS usage from cluster:
```bash
kubectl top pod -n velero minio-78c74bfdcd-q7kkw
```

### Check next scheduled maintenance:
```bash
kubectl get backuprepository -n velero -o custom-columns=NAME:.metadata.name,LAST:.status.lastMaintenanceTime
```

---

## Next Steps

1. **Check DSM Resource Monitor** to identify the specific process
2. **Disable Indexing Service** for `/volume1/pi-cluster-data` (most likely fix)
3. **Exclude from Antivirus** scanning
4. **Check for Cloud Sync / Backup tasks**
5. **Monitor for 30 minutes** to see if usage drops

**The cluster is not the problem - it's a Synology service scanning/indexing your backup data.**

---

**Report generated**: October 27, 2025
