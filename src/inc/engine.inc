; File engine (docs/FILE_ENGINE.md): constants, the work area and the REU
; layout shared by its overlay modules (src/kernal/engine*.s). Included by
; each engine source; defines symbols only, no code.

; Jump table entries the engine modules call. Not FindFile: the jump
; table's (SysFindFile, sysdrive.s) goes on to the root folder and drive E
; for a desk accessory or font; the engine imports files.s's own, which
; looks in the current folder only.
SetDevice       = $C2B0
DeleteFile      = $C238
RenameFile      = $C259
GetFHdrInfo     = $C229
CalcBlksFree    = $C1DB
SetNextFree     = $C292

; Function numbers (A at FileEngine; the table in engine.s follows them)
FE_VERSION      = 0
FE_STAT         = 1
FE_OPENDIR      = 2
FE_READDIR      = 3
FE_CLOSE        = 4
FE_COPY         = 5
FE_MOVE         = 6
FE_DELETE       = 7
FE_MKDIR        = 8
FE_RMDIR        = 9
FE_RENAME       = 10
FE_CD           = 11
FE_PWD          = 12
FE_OPEN         = 13
FE_READ         = 14
FE_WRITE        = 15
FE_DF           = 16
FE_MOUNT        = 17
FE_UMOUNT       = 18
FE_GETLONG      = 19
FE_SETLONG      = 20            ; (the same as FE_RENAME)
FE_SELECT       = 21            ; a file's drive and folder made current
FE_RUNSYS       = 22            ; an application on drive E started
FE_MOUNTINFO    = 23            ; a drive's image: type, tracks, path
FE_MKIMG        = 24            ; a new, empty disk image on the Ultimate
FE_TURBO        = 25            ; the U64's speed step, asked or set
FE_HOME         = 26            ; the home folder's path
FE_SETTIME      = 27            ; the Ultimate's clock from GEOS's
FE_REBOOT       = 28            ; written back, the C64 restarted afresh
FE_NTP          = 29            ; the clocks from an NTP server
FE_UCI          = 30            ; a command to the Ultimate, its reply
FE_COUNT        = 31
FE_VER          = $0003         ; FE_VERSION's answer (E3)

; FE_COPY, FE_MOVE: flags (r2L)
FC_OVERWRITE    = $01           ; an existing target file is replaced
FC_RAW          = $02           ; no CVT conversion (E4; GEOS drives: none)

; FE_OPEN: modes (r2L)
FO_READ         = 0
FO_WRITE        = 1             ; a new file (an existing one replaced)
FO_APPEND       = 2             ; at the end (made when not there)

; Errors: GEOS's own where they fit (FILE_NOT_FOUND, STRUCT_MISMAT,
; DEV_NOT_FOUND from geos.inc), GeoUltra's folder codes, then the
; engine's from $48.
INSUFF_SPACE    = 3
WR_PR_ON        = $26           ; (a locked file, drive E)
FILE_EXISTS     = $40           ; (as folders.s)
DIR_NOT_EMPTY   = $41
FE_CANCELLED    = $47           ; the progress routine asked to stop
FE_END_OF_DIR   = $48           ; FE_READDIR: no more entries
FE_BAD_PATH     = $49           ; too long, a name too long, nothing named
FE_NOT_FOLDER   = $4A           ; a folder was expected
FE_IS_FOLDER    = $4B           ; a file was expected
FE_BAD_HANDLE   = $4C           ; not open, or no handle number
FE_NO_HANDLE    = $4D           ; all FE_HANDLES in use
FE_NOT_SUPPORTED = $4E          ; not (yet) on this kind of path
FE_ULTIMATE     = $4F           ; the Ultimate's DOS refused (E3)
FE_NO_SLOT      = $50           ; drive E needs an empty drive letter (A-D)

; What a resolved path names (feKind, set by the walk in module 24)
FE_P_ROOT       = 0             ; "/"
FE_P_GEOS       = 1             ; a GEOS drive A-D (feName: the last
                                ; part, empty for the drive itself)
                                ; (2: was drive E; E is a GEOS drive now,
                                ; shown in a free slot: sysenter.s)
FE_P_ULTIMATE   = 3             ; /usb0, /usb1, /sd: the walk leaves fePos
                                ; at the "/" before the last part (feName
                                ; nonzero) or at the path's end (the top
                                ; itself, feName 0); only when feUlt is set,
                                ; else FE_NOT_SUPPORTED

; Info block (FE_STAT, FE_READDIR), FE_INFO_LEN bytes at the caller's r1
FE_INFO_LEN     = 16
FI_KIND         = 0             ; FE_K_*
FI_CBM          = 1             ; CBM type byte (directory entry +0)
FI_STRUCT       = 2             ; GEOS structure (0 sequential, 1 VLIR)
FI_GTYPE        = 3             ; GEOS file type
FI_SIZE         = 4             ; 4 bytes, low first: blocks (GEOS drives)
FI_DATE         = 8             ; year, month, day, hour, minute
FI_FLAGS        = 13            ; FF_* bits
FE_K_ROOT       = 0
FE_K_DRIVE      = 1
FE_K_FOLDER     = 2
FE_K_GEOS       = 3
FE_K_CBM        = 4
FE_K_UFILE      = 5
FE_K_UDIR       = 6
FF_READONLY     = $01
FF_GEOS         = $02
FF_CUT          = $04           ; an Ultimate name cut to FE_LONG_MAX

FRST_ENTRY      = 2             ; a directory block's first entry (type byte)
FE_PATH_MAX     = 255           ; bytes of a path, without its zero
FE_NAME_MAX     = 16            ; a name in a GEOS directory entry
FE_LONG_MAX     = 60            ; a long name (feName, feTmp: + its zero)
FE_UPART_MAX    = 120           ; the last part of an Ultimate path (it
                                ; goes into uCmd with a command)

; REU bank 1, $C000-$C7FF: the engine's lasting state (and FE_WSAVE)
FE_BANK         = 1
FE_MAGIC        = $C000         ; "FE", FE_LAYOUT: the area is set up
FE_LAYOUT       = 2             ; (1: E1-E3, the directory in 128 bytes)
FE_CWD          = $C100         ; the current directory (256 bytes)
FE_HANDLES      = $C200         ; FE_HANDLES_N handles of FE_HSIZE bytes
FE_HANDLES_N    = 4
FE_HSIZE        = 64
FE_UPATHS       = $C300         ; an Ultimate stream's path per handle
                                ; (256 bytes each, to $C6FF)

; A handle (FE_HUSED bytes kept, at feH while a call works on it)
H_TYPE          = 0             ; HT_*
H_DRIVE         = 1             ; device
H_FOLDT         = 2             ; the drive's folder while listing
H_FOLDS         = 3
H_BLKT          = 4             ; the directory block next read (0: end)
H_BLKS          = 5
H_OFF           = 6             ; the next entry's type byte in that block
H_PAT           = 7             ; the pattern, zero-terminated (17 bytes)
FE_HUSED        = H_PAT + FE_NAME_MAX + 1
HT_FREE         = 0
HT_DIR          = 1             ; a GEOS directory
HT_ROOT         = 2             ; "/": the drives (H_BLKT: the next slot)
HT_READ         = 3             ; a file read (H_BLKT/S, H_OFF)
HT_WRITE        = 4             ; a file written (and H_DIR*, H_SIZE)
HT_UDIR         = 5             ; an Ultimate listing in REU bank
                                ; FE_UBANK + handle (H_UCOUNT, H_UNEXT,
                                ; H_PAT)
HT_UREAD        = 6             ; an Ultimate file read (enginestreamu.s)
HT_UWRITE       = 7             ; an Ultimate file written
; A stream (HT_READ, HT_WRITE): H_BLKT/S the block, H_OFF its next byte
; (0: past the block's end); for HT_WRITE also, in H_PAT's place:
H_DIRT          = 7             ; the directory block with its entry
H_DIRS          = 8
H_DIRO          = 9             ; the entry's offset (its type byte)
H_SIZE          = 10            ; its blocks (word)
        .assert H_SIZE + 2 <= FE_HUSED, error, "engine.inc: stream handle"
H_UPOS          = 2             ; HT_UREAD, HT_UWRITE: the next byte's
                                ; place in the file (3 bytes)
H_UEND          = 5             ; HT_UREAD: where the data ends (3 bytes)
H_UFPOS         = 8             ; the path's folder end (fePos), the path
                                ; itself in FE_UPATHS
H_UCOUNT        = 2             ; HT_UDIR: entries in the bank (word)
H_UNEXT         = 4             ; the next one to look at (word)

; The Ultimate (DOS target 2; write-back and hibernation use target 1).
; A listing: one slot of FE_USLOT bytes per entry (the FAT attribute byte,
; the name, zero-ended, at most FE_USLOT - 2 characters).
FE_UBANK        = 188           ; banks 188-191: one per handle (the drives
                                ; end before, mount.s LAST_BANK)
FE_USLOT        = 64
FE_USLOTS       = $10000 / FE_USLOT
UA_READONLY     = $01           ; FAT attributes
UA_DIR          = $10
U_TARGET        = 2
U_OPEN          = $02           ; DOS commands
U_CLOSE         = $03
U_SEEK          = $06
U_READ          = $04
U_WRITE         = $05
U_INFO          = $07
U_DELETE        = $09
U_RENAME        = $0A
U_CD            = $11
U_OPENDIR       = $13
U_READDIR       = $14
U_MKDIR         = $16
UO_READ         = $01           ; open attributes
UO_NEW          = $06           ; write, a new file
UO_ALWAYS       = $0A           ; write, made or replaced
UO_WRITE        = $02           ; write, an existing file
UO_APPEND       = $12           ; write, made when not there
U_CMD_MAX       = 128
uCmd            = fileTrScTab + $80 ; the command (U_CMD_MAX bytes; the
                                ; engine destroys fileTrScTab)

; Work area: the overlay scratch $9F70-$9FFF (overlay.s), owned by the
; engine during a call. Write-back and hibernation use it from MainLoop;
; FE_UMOUNT, which calls the write-back, keeps it at FE_WSAVE meanwhile
; (enginemount.s). An engine module keeps here what must survive its
; nested overlay calls.
FE_WORK         = $9F70
feFunc          = FE_WORK       ; the function number
feY             = FE_WORK + 1   ; Y at the call (a handle)
feA             = FE_WORK + 2   ; A and X of the function, for the way out
feErr           = FE_WORK + 3
feTouched       = FE_WORK + 4   ; nonzero: a drive was used (restore it)
saveDrive       = FE_WORK + 5   ; the caller's curDrive
saveFT          = FE_WORK + 6   ; the caller's folderT[4], folderS[4]
saveFS          = FE_WORK + 10
argR            = FE_WORK + 14  ; the caller's r0-r4 (10 bytes): arguments
argR0           = argR          ; in, results out (the dispatcher puts
argR1           = argR + 2      ; them back in r0-r4 at the end)
argR2           = argR + 4
argR3           = argR + 6
argR4           = argR + 8
feKind          = FE_WORK + 24  ; FE_P_* of the resolved path
feDrive         = FE_WORK + 25  ; its device (FE_P_GEOS)
fePos           = FE_WORK + 26  ; the walk's place in fePath
feEnd           = FE_WORK + 27
feShort         = FE_WORK + 28  ; the short name a path's last part has on
                                ; disk (17 bytes; 0 first: none found)
lnKeyT          = FE_WORK + 45  ; long names (enginelong.s): a file's key,
lnKeyS          = FE_WORK + 46  ; its directory block and the entry's
lnKeyO          = FE_WORK + 47  ; offset (its type byte)
lnBlkT          = FE_WORK + 48  ; GU.LONGNAMES: the block in diskBlkBuf
lnBlkS          = FE_WORK + 49
lnOff           = FE_WORK + 50  ; the record's offset in it (2 or 129)
lnDirT          = FE_WORK + 51  ; its own entry's place (to grow it)
lnDirS          = FE_WORK + 52
lnDirO          = FE_WORK + 53
lnFreeT         = FE_WORK + 54  ; a free record found while looking
lnFreeS         = FE_WORK + 55  ; (0: none)
lnFreeO         = FE_WORK + 56
feInfo          = FE_WORK + 62  ; an info block being built (16 bytes)
feHandle        = FE_WORK + 78  ; the handle number being worked on
feH             = FE_WORK + 79  ; that handle (FE_HUSED = 24 bytes)
feM             = FE_WORK + 103 ; pattern match: the star's place in the
feMN            = FE_WORK + 104 ; pattern and in the name

; FE_COPY, FE_MOVE (enginecopy.s), over feInfo..feH, which they do not use
cEntry          = feInfo        ; the source's directory entry (30 bytes)
cSrcDrv         = FE_WORK + 105 ; the source's drive, folder, and its entry
cSrcFT          = FE_WORK + 106 ; (directory block, offset)
cSrcFS          = FE_WORK + 107
cSrcET          = FE_WORK + 108
cSrcES          = FE_WORK + 109
cSrcEO          = FE_WORK + 110
cDstDrv         = FE_WORK + 111 ; the target's drive
cNextT          = FE_WORK + 112 ; the source block read next
cNextS          = FE_WORK + 113
cCurT           = FE_WORK + 114 ; the target block being filled
cCurS           = FE_WORK + 115
cLastT          = FE_WORK + 116 ; the last block taken (0: none yet)
cLastS          = FE_WORK + 117
cDone           = FE_WORK + 118 ; blocks copied (word)
cRec            = FE_WORK + 120 ; VLIR: the index entry being copied
cMove           = FE_WORK + 121 ; nonzero: FE_MOVE
cSame           = FE_WORK + 122 ; nonzero: the target folder is the source's
feUlt           = FE_WORK + 123 ; nonzero: the function takes Ultimate paths
U_STAT_MAX      = 6             ; status characters kept ("FILE E")
uStat           = FE_WORK + 124 ; the Ultimate's status, zero-ended
uLen            = FE_WORK + 124 + U_STAT_MAX + 1 ; uCmd's length
uEnd            = uLen + 1      ; the reply's data: up to here (a word)
cToU            = uEnd + 2      ; FE_COPY: nonzero, the target is the Ultimate
cLeft           = cToU + 1      ; a copy from the Ultimate: bytes still to
                                ; read (3 bytes)
uCdEnd          = cLeft + 3     ; module 36's folder change: fePath up to
uCdPos          = cLeft + 4     ; here, the piece now, the next one
uCdNext         = cLeft + 5
cCvt            = cLeft + 6     ; a copy between a GEOS drive and the Ultimate:
                                ; nonzero, as CVT (enginecvt.s)
cCount          = cLeft + 7     ; CVT from the Ultimate: bytes of one read
uNamed          = cLeft + 8     ; a copy onto the Ultimate: nonzero, the
                                ; file named after the source (PutSrc)
        .assert uNamed <= $9FFF, error, "engine.inc: the work area past $9FFF"
        .assert cEntry + 30 <= feM, error, "engine.inc: cEntry over feM"

; FE_MOUNT, FE_UMOUNT (enginemount.s), over the same place
mSlot           = feInfo        ; the drive (0-3)
mType           = feInfo + 1    ; the image's DRV_* type
mBanks          = feInfo + 2    ; its REU banks
mTracks         = feInfo + 3    ; native: its tracks (else 0)
mBank           = feInfo + 4    ; its first bank
mTmp            = feInfo + 5
mIdx            = feInfo + 6    ; FE_MKIMG: a track or block being made
FE_FIRST_BANK   = 31            ; drives: REU banks 31-187 (mount.s)
FE_LAST_BANK    = FE_UBANK - 1
FE_WSAVE        = $C700         ; REU bank 1: the work area while the
                                ; write-back runs (it uses $9F70-$9FFF)
FE_WORK_LEN     = $A000 - FE_WORK

; FE_NTP (enginentp.s), over the same place
nTime           = feInfo        ; the time: NTP seconds, then Unix ones (4)
nOff            = feInfo + 4    ; SETTINGS.INI's offset from UTC, seconds (3,
                                ; signed)
nSock           = feInfo + 7    ; the UDP socket
nTry            = feInfo + 8    ; reads still to try
nDays           = feInfo + 9    ; days since 1970 (word)
nRest           = feInfo + 11   ; seconds of the day (3)
nYear           = feInfo + 14   ; the year (word)
nHost           = feName        ; the server's name (FE_LONG_MAX + 1 bytes)

; Streams (enginestream.s), over the same place
sPtr            = feInfo        ; the caller's buffer, moving on (word)
sLeft           = feInfo + 2    ; bytes still to go (word)
sGot            = feInfo + 4    ; bytes done (word)
sNew            = feInfo + 6    ; nonzero: a block was added (FE_WRITE)
        .assert sNew < feHandle, error, "engine.inc: streams over feHandle"
        .assert uCdNext < $A000, error, "engine.inc: the work area overflows"

.define LN_NAME "GU.LONGNAMES"  ; its name (felong.inc, enginelong.s)
LN_EXACT        = $01           ; H_PAT's first byte: an exact short name
                                ; follows (FE_OPENDIR on one file)
; GU.LONGNAMES (docs/FILE_ENGINE.md, "Long names"): records of LN_REC
; bytes, two in each block's data, never across blocks.
LN_REC          = 127
LN_T            = 0             ; the file's directory block (0: free)
LN_S            = 1
LN_O            = 2             ; its entry's offset in the block
LN_SHORT        = 3             ; its short name, $A0-padded
LN_LONG         = 19            ; its long name, zero-ended
        .assert LN_LONG + FE_LONG_MAX + 1 <= LN_REC && 2 * LN_REC = 254, error, "engine.inc: records"

; Names (FE_LONG_MAX + 1 bytes each), in fileTrScTab before uCmd: the
; path's last part, and a second name (a copy's target, a new name).
feName          = fileTrScTab
feTmp           = fileTrScTab + $40
feOld           = uCmd          ; a rename's old short name (17 bytes;
                                ; uCmd is free on GEOS drives)
        .assert feTmp + FE_LONG_MAX + 1 <= uCmd, error, "engine.inc: names over uCmd"

; The path after module 23: absolute, without "." and "..", at fileHeader
; (free while the engine runs; GEOS routines that use fileHeader are
; called only after the path's parts were taken from it).
fePath          = $8100
