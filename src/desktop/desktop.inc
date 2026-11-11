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

; GEOS's date and time (year in geos.inc)
month           = $8517
day             = $8518
hour            = $8519
minutes         = $851A

; The icons (icons.s)
IC_FOLDER       = 0
IC_APP          = 1
IC_DOC          = 2
IC_DA           = 3
IC_FONT         = 4
IC_IMAGE        = 5
IC_FILE         = 6
IC_DRIVE        = 7
IC_RAM          = 8
IC_USB          = 9
IC_SD           = 10
IC_ARROW        = 11
IC_UP           = 12
IC_DOWN         = 13

; More file engine functions
FE_DF           = 16
HorizontalLine  = $C118
VerticalLine    = $C121

; Theme styles (theme.s; the mock-up's buttons in order, 0 the first)
THEMES_N        = 6             ; built-in themes
ST_CLOCK        = 1             ; menubar: 0 plain
ST_NARROW       = 1             ; sidebar: 0 wide
ST_UNDERLINED   = 2             ; headings: 0 inverted, 1 band
ST_PLAIN        = 3
ST_LINE         = 2             ; titlebar: 0 stripes, 1 solid
ST_NONE         = 3
ST_BAR          = 1             ; selection: 0 invert
ST_FRAME        = 2
ST_MARK         = 1             ; cursor: 0 dotted, 2 underline
ST_THIN         = 1             ; scrollbar: 0 arrows
ST_OFF          = 1             ; icons, status: 0 on

; The view (theme.s viewMode) and the clock (clockMode)
VIEW_LIST       = 0
VIEW_ICONS      = 1
VIEW_DETAILED   = 2
CLOCK_24        = 0
CLOCK_12        = 1
CLOCK_OFF       = 2
FI_SIZE         = 4             ; 4 bytes: blocks (GEOS drives), bytes (Ultimate)
FI_DATE         = 8             ; year, month, day, hour, minute (GEOS files)
K_CBM           = 4

; The sidebar's lists and the INI files (side.s, inifile.s)
LIST_MAX        = 4             ; favourites, recent documents, [desktop] lines
PATH_LEN        = 63            ; a path and its zero (entryName's size:
                                ; SidePress shows one in the question)
TEXT_MAX        = 3072          ; an INI file's bytes, at most
L_FAV           = 0             ; the lists ("which")
L_REC           = 1
L_DESK          = 2             ; SETTINGS.INI's [desktop] lines
WANT_LEN        = 16            ; the theme's name a [desktop] line names
