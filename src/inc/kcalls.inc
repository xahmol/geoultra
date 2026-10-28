; Disk routines the kernal's file code calls: jump table entries (through
; the disk driver's vectors) and driver entries. Not for the driver itself,
; whose own routines carry these names.
GetBlock        = $C1E4
PutBlock        = $C1E7
GetDirHead      = $C247
PutDirHead      = $C24A
ReadBuff        = $903C
WriteBuff       = $903F
BlkAlloc        = $C1FC
FreeBlock       = $C2B9
GetFreeDirBlk   = $C1F6
