; GeoUltra Desktop: constants shared by its modules (code sweep
; 2026-11-11: one definition each instead of copies per file).

; GEOS jump table (and GeoUltra's extension table)
guExtTable      = $C0E4         ; GeoUltra: the extension table
Rectangle       = $C124
FrameRectangle  = $C127
InvertRectangle = $C12A
RecoverRectangle = $C12D
SetPattern      = $C139
BitmapUp        = $C142
PutString       = $C148
UseSystemFont   = $C14B
DoMenu          = $C151
MoveData        = $C17E
ReDoMenu        = $C193
GotoFirstMenu   = $C1BD
GetCharWidth    = $C1C9
GetFile         = $C208
FindFTypes      = $C23B
DoDlgBox        = $C256
OpenDisk        = $C2A1
SetDevice       = $C2B0
RstrFrmDialogue = $C2BF
StashRAM        = $C2C8
FetchRAM        = $C2CB

; The file engine (docs/FILE_ENGINE.md): functions, flags, info block, kinds
FE_CD           = 11
FE_CLOSE        = 4
FE_COPY         = 5
FE_DELETE       = 7
FE_HOME         = 26
FE_MKDIR        = 8
FE_MOUNT        = 17
FE_MOUNTINFO    = 23
FE_MOVE         = 6
FE_OPEN         = 13
FE_OPENDIR      = 2
FE_PWD          = 12
FE_READ         = 14
FE_READDIR      = 3
FE_RENAME       = 10
FE_RMDIR        = 9
FE_RUNSYS       = 22
FE_SELECT       = 21
FE_STAT         = 1
FE_UMOUNT       = 18
FE_WRITE        = 15
FI_GTYPE        = 3
FI_KIND         = 0
FO_READ         = 0
FO_WRITE        = 1
INFO_LEN        = 16            ; an info block (FE_STAT, FE_READDIR)
K_DRIVE         = 1
K_FOLDER        = 2
K_GEOS          = 3
K_UDIR          = 6
K_UFILE         = 5
FC_OVERWRITE    = $01
FE_ULTIMATE     = $4F           ; (an error: the Ultimate refused)

; Layout (docs/DESKTOP.md, "Screen"), the entry name, dialogs, modifiers
BASELINE        = 7             ; a row's baseline below its top
DBI_X_0         = 1             ; the left icon's place in a dialog
LIST_LEFT       = 82
LIST_TOP        = 28            ; the list: rows of ROW_H pixels
MENU_BOTTOM     = 14
MOD_CBM         = 2
MOD_SHIFT       = 1
NAME_LEN        = 61            ; a long name and its zero (entryName)
PATH_Y          = 24            ; the path line's baseline
ROW_H           = 9
SCREEN_RIGHT    = 319
SIDE_RIGHT      = 79            ; the sidebar: x 0-79
STRIP_LEFT      = 312           ; the scroll strip: x 312-319
