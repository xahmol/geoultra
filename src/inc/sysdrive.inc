; Drive E, the system drive (docs/ARCHITECTURE.md "System drive"): a
; native (DNP) image with folders (src/sysdrive.toml) at REU bank
; SYSDRV_BANK (tools/mkimage.py, @BANK4), relocated by tools/sysreloc.py
; so all its track numbers are SYSDRV_TRACK higher: tracks SYSDRV_TRACK+1
; to SYSDRV_TRACK+SYSDRV_TRACKS of every drive read drive E's blocks
; (every drive but a native one with more than SYSDRV_TRACK tracks).
SYSDRV_BANK     = 4             ; banks 4-11 (the ROM mirror, banks 2-17)
SYSDRV_TRACK    = 247
SYSDRV_TRACKS   = 8             ; (src/sysdrive.toml tracks)
; The scrap store (docs/DESIGN.md "Clipboard"): every program's scrap
; files ("Text  Scrap", "Photo Scrap" ...) in REU banks SCRAP_BANK on,
; read and written as tracks SCRAP_TRACK+1 to SYSDRV_TRACK of every drive
; (not E's read-only way: no dirty map, also on a write-protected drive;
; scrap.s).
SCRAP_BANK      = 29            ; banks 29-30
SCRAP_TRACK     = 245
SCRAP_TRACKS    = 2
        .assert SCRAP_TRACK + SCRAP_TRACKS = SYSDRV_TRACK, error, "sysdrive.inc: the scrap store's tracks end below E's"
; The system fonts (docs/DESIGN.md "System font folder"): GEOULTRA/
; FONTS.DNP, 8 tracks, loaded at the cold start into REU banks FONT_BANK
; on and relocated there to tracks FONT_TRACK+1 to SCRAP_TRACK, read-only
; for programs as E is (reudrv.s Locate).
FONT_BANK       = 180           ; banks 180-187 (the drives' area ends below)
COLD_BANK       = 17            ; fontsOn and guPrnFast as the cold start
COLD_KEYS       = $FF00         ; set them (mount.s module 122), for a
                                ; resumed session (hibernate.s Resumed: its
                                ; RAM holds the saved session's, older
                                ; ones): the ROM mirror's last bank, unused
                                ; (E ends at 11) and not in HIBERNAT.BIN,
                                ; whose bank 1 the resume loads after the
                                ; cold start (bank 1 did not work)
FONT_TRACK      = 237
FONT_TRACKS     = 8
        .assert FONT_TRACK + FONT_TRACKS = SCRAP_TRACK, error, "sysdrive.inc: the fonts' tracks end below the scrap store's"
        .assert SYSDRV_TRACK + SYSDRV_TRACKS = 255, error, "sysdrive.inc: E's tracks end at 255 (Locate checks no bound)"

; [serials] (serials.s, docs/DESIGN.md "Serial number"): the table in the
; ROM mirror's unused last bank, below COLD_KEYS
SERIALS_BANK    = COLD_BANK
SERIALS_AT      = $F000         ; a count, then the entries
SERIALS_MAX     = 32
SER_LEN         = 14            ; the class (12 characters) and the serial
        .assert SERIALS_AT + 1 + SERIALS_MAX * SER_LEN <= COLD_KEYS, error, "sysdrive.inc: [serials] into COLD_KEYS"
