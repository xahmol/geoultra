; Drive E, the system drive (docs/ARCHITECTURE.md "System drive"): its
; 1541 image at REU bank SYSDRV_BANK (tools/mkimage.py, @BANK4), relocated
; by tools/sysreloc.py so all its track numbers are SYSDRV_TRACK higher:
; tracks 221-255 of every drive read drive E's blocks.
SYSDRV_BANK     = 4
SYSDRV_TRACK    = 220
