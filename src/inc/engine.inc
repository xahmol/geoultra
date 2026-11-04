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
FE_COUNT        = 19
FE_VER          = $0002         ; FE_VERSION's answer (E2)

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

; What a resolved path names (feKind, set by the walk in module 24)
FE_P_ROOT       = 0             ; "/"
FE_P_GEOS       = 1             ; a GEOS drive A-D (feName: the last
                                ; part, empty for the drive itself)
FE_P_DRIVEE     = 2             ; drive E (later)
FE_P_ULTIMATE   = 3             ; /usb0, /usb1, /sd (E3)

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

FRST_ENTRY      = 2             ; a directory block's first entry (type byte)
FE_PATH_MAX     = 127           ; bytes of a path, without its zero
FE_NAME_MAX     = 16            ; a name on a GEOS drive

; REU bank 1, $C000-$C2FF: the engine's lasting state
FE_BANK         = 1
FE_MAGIC        = $C000         ; "FE", FE_LAYOUT: the area is set up
FE_LAYOUT       = 1
FE_CWD          = $C080         ; the current directory (128 bytes)
FE_HANDLES      = $C100         ; FE_HANDLES_N handles of FE_HSIZE bytes
FE_HANDLES_N    = 4
FE_HSIZE        = 64

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
; A stream (HT_READ, HT_WRITE): H_BLKT/S the block, H_OFF its next byte
; (0: past the block's end); for HT_WRITE also, in H_PAT's place:
H_DIRT          = 7             ; the directory block with its entry
H_DIRS          = 8
H_DIRO          = 9             ; the entry's offset (its type byte)
H_SIZE          = 10            ; its blocks (word)
        .assert H_SIZE + 2 <= FE_HUSED, error, "engine.inc: stream handle"

; Work area: the overlay scratch $9F70-$9FFF (overlay.s), owned by the
; engine during a call. No other overlay module uses it; an engine module
; keeps here what must survive its nested overlay calls.
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
feName          = FE_WORK + 28  ; the last part of the path (17 bytes)
feTmp           = FE_WORK + 45  ; a second name (17 bytes)
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
        .assert cEntry + 30 <= feM, error, "engine.inc: cEntry over feM"

; Streams (enginestream.s), over the same place
sPtr            = feInfo        ; the caller's buffer, moving on (word)
sLeft           = feInfo + 2    ; bytes still to go (word)
sGot            = feInfo + 4    ; bytes done (word)
sNew            = feInfo + 6    ; nonzero: a block was added (FE_WRITE)
        .assert sNew < feHandle, error, "engine.inc: streams over feHandle"
        .assert cSame < $A000, error, "engine.inc: the work area overflows"

; The path after module 23: absolute, without "." and "..", at fileHeader
; (free while the engine runs; GEOS routines that use fileHeader are
; called only after the path's parts were taken from it).
fePath          = $8100
