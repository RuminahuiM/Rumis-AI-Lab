# Storage Setup (Synology NAS)

The frontend VM stores all persistent data on a Synology NAS via NFS. This allows the VM to be re-provisioned without losing data.

---

## Prerequisites

- Synology NAS with DSM 7.x
- NFS enabled (Control Panel → File Services → NFS → Enable NFS service)
- Network connectivity between the frontend VM and the NAS

---

## Step 1: Create the Shared Folder

1. Open **Control Panel → Shared Folder → Create**
2. Name: `rumis-ai-lab`
3. Location: Choose your volume (e.g. Volume 1)
4. Skip encryption and advanced settings

---

## Step 2: Create Subdirectories

SSH into the NAS or use File Station:

```bash
mkdir -p /volume1/rumis-ai-lab/postgres
mkdir -p /volume1/rumis-ai-lab/openwebui
mkdir -p /volume1/rumis-ai-lab/n8n
```

---

## Step 3: Set NFS Permissions

1. Open **Control Panel → Shared Folder**
2. Select `rumis-ai-lab` → **Edit → NFS Permissions → Create**
3. Configure:
   - **Hostname or IP:** IP address of the frontend VM (or subnet like `192.168.1.0/24`)
   - **Privilege:** Read/Write
   - **Squash:** Map all users to admin
   - **Security:** sys
   - **Enable asynchronous:** Yes (better performance)
   - **Allow connections from non-privileged ports:** Yes
   - **Allow users to access mounted subfolders:** Yes

---

## Step 4: Configure .env

On the frontend VM, set these values in `.env`:

```env
NAS_IP=192.168.1.50
NAS_SHARE_PATH=/volume1/rumis-ai-lab
```

Docker Compose will automatically mount NFS volumes using these values.

---

## Step 5: Verify NFS Mount

Test from the frontend VM before starting services:

```bash
# Install NFS client if not already present
sudo apt install -y nfs-common

# Test mount
sudo mount -t nfs4 -o vers=4.1 192.168.1.50:/volume1/rumis-ai-lab/postgres /mnt
ls /mnt
sudo umount /mnt
```

If the mount succeeds, Docker Compose will work.

---

## Backup

The NAS handles backups. Configure Hyper Backup or Snapshot Replication in DSM for the `rumis-ai-lab` shared folder. PostgreSQL data is crash-consistent due to WAL journaling.

For application-consistent PostgreSQL backups:

```bash
docker exec postgres pg_dumpall -U rumis > backup.sql
```
