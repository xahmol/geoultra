; Drive E, the system drive (docs/ARCHITECTURE.md "System drive"): a
; native (DNP) image with folders (src/sysdrive.toml) at REU bank
; SYSDRV_BANK (tools/mkimage.py, @BANK4), relocated by tools/sysreloc.py
; so all its track numbers are SYSDRV_TRACK higher: tracks SYSDRV_TRACK+1
; to SYSDRV_TRACK+SYSDRV_TRACKS of every drive read drive E's blocks
; (every drive but a native one with more than SYSDRV_TRACK tracks).
SYSDRV_BANK     = 4             ; banks 4-11 (the ROM mirror, banks 2-17)
SYSDRV_TRACK    = 247
SYSDRV_TRACKS   = 8             ; (src/sysdrive.toml tracks)
        .assert SYSDRV_TRACK + SYSDRV_TRACKS = 255, error, "sysdrive.inc: E's tracks end at 255 (Locate checks no bound)"
