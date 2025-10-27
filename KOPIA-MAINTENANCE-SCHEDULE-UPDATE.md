# Kopia Maintenance Schedule Update

**Date**: October 27, 2025, 10:58 AM UTC
**Status**: ✅ Successfully Updated

---

## Change Applied

**Kopia backup maintenance frequency changed from hourly to every 6 hours**

### Before:
- Maintenance ran **every 1 hour** (24 times per day)
- 12 namespaces × 24 runs = **288 maintenance jobs per day**

### After:
- Maintenance runs **every 6 hours** (4 times per day)
- 12 namespaces × 4 runs = **48 maintenance jobs per day**

**Reduction**: 83% fewer maintenance jobs (288 → 48 per day)

---

## Updated Repositories

All 12 Kopia backup repositories updated:

| Repository | Frequency (Before) | Frequency (After) | Status |
|------------|-------------------|-------------------|--------|
| airflow-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| celery-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| databases-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| dev-tools-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| kube-system-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| logging-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| longhorn-system-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| monitoring-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| nfs-provisioner-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| redis-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| traefik-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |
| velero-default-kopia | 1h0m0s | **6h0m0s** | ✅ Updated |

---

## Next Maintenance Windows

Based on last maintenance completion times:

| Repository | Last Maintenance | Next Maintenance (Approx) |
|------------|-----------------|---------------------------|
| airflow-default-kopia | 9:55 AM UTC | **3:55 PM UTC** (Oct 27) |
| velero-default-kopia | 9:55 AM UTC | **3:55 PM UTC** (Oct 27) |
| celery-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| databases-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| dev-tools-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| kube-system-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| logging-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| longhorn-system-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| monitoring-default-kopia | 10:30 AM UTC | **4:30 PM UTC** (Oct 27) |
| nfs-provisioner-default-kopia | 10:31 AM UTC | **4:31 PM UTC** (Oct 27) |
| redis-default-kopia | 10:31 AM UTC | **4:31 PM UTC** (Oct 27) |
| traefik-default-kopia | 10:31 AM UTC | **4:31 PM UTC** (Oct 27) |

**Next batch**: Most repositories will run maintenance around **4:30-4:31 PM UTC today**

---

## New Access Pattern to Synology NFS

### Before (Hourly):
```
Hour 1:  [5-10 min activity] ---------- [50-55 min idle] ----------
Hour 2:  [5-10 min activity] ---------- [50-55 min idle] ----------
Hour 3:  [5-10 min activity] ---------- [50-55 min idle] ----------
Hour 4:  [5-10 min activity] ---------- [50-55 min idle] ----------
...every hour (24x per day)
```

### After (Every 6 Hours):
```
10:30 AM: [5-10 min maintenance] ----------------------
                                   [~6 hours idle]
4:30 PM:  [5-10 min maintenance] ----------------------
                                   [~6 hours idle]
10:30 PM: [5-10 min maintenance] ----------------------
                                   [~6 hours idle]
4:30 AM:  [5-10 min maintenance] ----------------------
                                   [~6 hours idle]
(Daily backup at 2 AM)
(Weekly backup at 3 AM Sunday)
```

**Daily Pattern**:
- 4 maintenance windows per day (instead of 24)
- Each window: 5-10 minutes for 12 jobs
- Total active time per day: ~20-40 minutes (instead of 120-240 minutes)
- Plus daily backup at 2 AM (~20-30 min)
- Plus weekly backup Sunday 3 AM (~40-60 min)

---

## Impact on Synology DS118

### Network Traffic Reduction:

**Before**:
- 24 maintenance windows per day
- ~2-5 GB transferred per day (maintenance only)

**After**:
- 4 maintenance windows per day
- ~2-5 GB transferred per day (same total work, just less frequent)

**Note**: Total data transferred remains similar (backups need the same validation), but it's spread over 4 windows instead of 24.

### NFS Idle Time:

**Before**: Idle ~85-90% of the time (50-55 min/hour idle)
**After**: Idle ~97-98% of the time (23.5 hours idle per day)

---

## Benefits of 6-Hour Schedule

### ✅ Advantages:

1. **Reduced NFS Access Frequency**
   - Synology accessed 4x per day instead of 24x
   - Feels much less "continuous"
   - LEDs blink less frequently

2. **Reduced Job Overhead**
   - 83% fewer Kubernetes jobs created/deleted
   - Less API server load
   - Cleaner job logs

3. **Batch Efficiency**
   - Longer maintenance windows can be more efficient
   - Better disk cache utilization
   - Reduced overhead from job startup/teardown

4. **Power/Wear Reduction** (minor)
   - Synology disk spinup/spindown cycles reduced
   - Network interface less active
   - Slightly lower power consumption

### ⚠️ Trade-offs:

1. **Backup Issue Detection Time**
   - **Before**: Issues detected within 1 hour
   - **After**: Issues detected within 6 hours
   - **Impact**: Still acceptable for most scenarios

2. **Storage Optimization Delay**
   - Deduplication/compression happens less frequently
   - **Impact**: Minimal, as backups are still deduplicated just not as often

3. **Snapshot Cleanup Delay**
   - Old snapshots cleaned up every 6 hours instead of hourly
   - **Impact**: Negligible, as retention policies are still enforced

---

## What Hasn't Changed

✅ **Daily backups** - Still run at 2 AM daily
✅ **Weekly backups** - Still run at 3 AM Sunday
✅ **Backup quality** - Same data integrity checks
✅ **Retention policies** - Same retention rules applied
✅ **Storage location** - Still on Synology NFS
✅ **Recovery capability** - Can still restore from any backup

**Only the frequency of maintenance checks changed, not the backups themselves.**

---

## Monitoring the Change

### How to Verify New Schedule:

```bash
# Check current maintenance frequency
kubectl get backuprepository -n velero -o custom-columns=NAME:.metadata.name,FREQUENCY:.spec.maintenanceFrequency

# Check last maintenance time
kubectl get backuprepository -n velero -o custom-columns=NAME:.metadata.name,LAST_MAINTENANCE:.status.lastMaintenanceTime

# Watch for next maintenance job
kubectl get jobs -n velero -w | grep kopia-maintain
```

### Expected Next Maintenance:

**Around 4:30 PM UTC today (Oct 27, 2025)**:
- You should see 12 new `kopia-maintain-job` pods appear
- They will run for ~5-10 minutes total
- Then no more maintenance until ~10:30 PM UTC

### After That:

**Regular schedule (4 times per day)**:
- ~4:30 AM UTC
- ~10:30 AM UTC
- ~4:30 PM UTC
- ~10:30 PM UTC

**Plus scheduled backups**:
- 2:00 AM UTC - Daily backup
- 3:00 AM UTC Sunday - Weekly full backup

---

## Reverting if Needed

If you want to go back to hourly maintenance:

```bash
for repo in $(kubectl get backuprepository -n velero -o name); do
  kubectl patch -n velero $repo --type='json' \
    -p='[{"op": "replace", "path": "/spec/maintenanceFrequency", "value": "1h0m0s"}]'
done
```

---

## Commands Used

### Update Command:
```bash
for repo in $(kubectl get backuprepository -n velero -o name); do
  kubectl patch -n velero $repo --type='json' \
    -p='[{"op": "replace", "path": "/spec/maintenanceFrequency", "value": "6h0m0s"}]'
done
```

### Verification:
```bash
kubectl get backuprepository -n velero \
  -o custom-columns=NAME:.metadata.name,FREQUENCY:.spec.maintenanceFrequency,STATUS:.status.phase
```

---

## Summary

✅ **Change Applied**: Kopia maintenance frequency updated from 1 hour to 6 hours
✅ **Repositories Updated**: All 12 backup repositories
✅ **Next Maintenance**: ~4:30 PM UTC today (Oct 27)
✅ **NFS Access Reduced**: From 24x/day to 4x/day (83% reduction)
✅ **Backups Unchanged**: Daily/weekly backups still run as scheduled
✅ **Data Protection**: Same level of backup protection maintained

**Your Synology DS118 will now be accessed much less frequently - only 4 times per day for maintenance, plus the daily/weekly scheduled backups!**

---

**Update completed**: October 27, 2025, 10:58 AM UTC
**Applied by**: Kubernetes patch command
**Effective**: Immediately
