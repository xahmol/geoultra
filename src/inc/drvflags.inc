; Shared GeoUltra system constants (one place for values that several
; source files use).

; Drive flags (drvFlags, one byte per drive; mount.s sets them at boot,
; the driver and the write-back keep them; docs/reference/ARCHITECTURE.md).
F_DIRTY         = $01           ; changed since the last write-back
F_READONLY      = $02           ; the image file is read-only
F_BACKUP        = $04           ; writeback.s: a backup copy was made
F_RESIZED       = $08           ; a native drive of another size than its file
F_NOLONG        = $10           ; long names off: no new GU.LONGNAMES records
                                ; (MOUNTS.INI ",longnames=off"; the user,
                                ; 2026-11-14, Settings' Drives page)
F_KNOWN         = F_DIRTY | F_READONLY | F_BACKUP | F_RESIZED | F_NOLONG

; REU bank 3, $FF00: the list of applications that run at 1 MHz
; (SETTINGS.INI [system] slow=; mount.s writes it, speed.s reads it).
SLOW_BANK       = 3
