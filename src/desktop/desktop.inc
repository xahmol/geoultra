; GeoUltra Desktop: constants shared by its modules (code sweep
; 2026-11-11: one definition each instead of copies per file).

; GEOS jump table (and GeoUltra's extension table)
guExtTable      = $C0E4         ; GeoUltra: the extension table
guMouse2        = $C0E6         ; GeoUltra: the right mouse button (info.s)
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
PutChar         = $C145
IsMseInRegion   = $C2B3
GetNextChar     = $C2A7
SwapRAM         = $C2CE

; The file engine (docs/FILE_ENGINE.md): functions, flags, info block, kinds
FE_CD           = 11
FE_CLOSE        = 4
FE_COPY         = 5
FE_DELETE       = 7
FE_HOME         = 26
FE_MKDIR        = 8
FE_MOUNT        = 17
FE_MOUNTINFO    = 23
FE_DRVSWAP      = 34            ; drive B and r0L swapped (kernal drvswap.s)
FE_MOVE         = 6
FE_OPEN         = 13
FE_OPENDIR      = 2
FE_PWD          = 12
FE_READ         = 14
FE_READDIR      = 3
FE_RENAME       = 10
FE_RMDIR        = 9
FE_RUNSYS       = 22
FE_TASK         = 32            ; (engine.inc: the tasks, task.s)
FE_SPOOL        = 33            ; (engine.inc: the print queue, spool.s)
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
INSUFF_SPACE    = 3             ; the engine's errors errors.s words
WR_PR_ON        = $26           ; (src/inc/engine.inc)
FILE_EXISTS     = $40
DIR_NOT_EMPTY   = $41
FE_NOT_SUPPORTED = $4E
FE_NO_SLOT      = $50
FE_MOUNTED      = $51
FE_IN_TASK      = $52           ; (engine.inc: open in another task)
FE_NO_TASK      = $53           ; (engine.inc: no task slot free)
ERR_IMAGE       = $60           ; the desktop's own: a disk image onto A-D
ERR_REU         = $61           ; a disk image gone into: no room in the REU
ERR_INIMG       = $62           ; a program or document inside a disk image
ERR_PRINTER     = $63           ; (no error: a printer driver chosen)
                                ; refused (tree.s, errors.s)

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
GU_CLOCK_FRESH  = $C0FB         ; the kernal's info block: the clock fresh
                                ; from the Ultimate's (inifile.s ClockAdjust)
FE_SETTIME      = 27

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
DrawPoint       = $C133
VerticalLine    = $C121

; Theme styles (theme.s; the mock-up's buttons in order, 0 the first)
THEMES_N        = 6             ; built-in themes
ST_CLOCK        = 1             ; menubar: 0 plain
ST_NARROW       = 1             ; sidebar: 0 wide
ST_UNDERLINED   = 2             ; headings: 0 inverted, 1 band
ST_PLAIN        = 3
ST_SOLID        = 1             ; titlebar: 0 stripes
ST_LINE         = 2
ST_NONE         = 3
ST_BAR          = 1             ; selection: 0 invert
ST_FRAME        = 2
ST_MARK         = 1             ; cursor: 0 dotted, 2 underline
ST_THIN         = 1             ; scrollbar: 0 arrows
ST_OFF          = 1             ; icons, status: 0 on

; The view (theme.s viewMode) and the clock (clockMode)
THM_STYLES      = 11            ; a theme record: style bytes, then colour
THM_LEN         = 23            ; bytes (theme.s's record, themefile.s's)
ITYPES_N        = 6             ; the icon colours by type after it
ITYPE_NONE      = $FF           ; (themedef.inc: not set)
BIG_BANK        = 6             ; the icon view's generic icons in the REU
BIG_PAGE        = $FE           ; (tooldraw.s puts them, iconview.s reads;
                                ; after the icon cache, iconview.s)
CTX_N           = 12            ; the context menu's items (ctxmenu.s):
                                ; open, open in new task, copy, cut,
                                ; paste, rename, delete,
                                ; info, favourite, new folder, copy and move
                                ; to the other pane (list.s CtxDo)
PANE_W          = 160           ; a pane: x 0-159 or 160-319 (panes.s,
                                ; listin.s's letters)
PANE_BANK       = 5             ; the other pane's state (list.s SwapPane):
PANE_PAGE       = $FC           ; after the clipboard (actions.s), 4 pages
PREF_COPY       = $03           ; deskPrefs (side.s; SETTINGS.INI [desktop],
COPY_ASK        = 0             ; the user, 2026-11-12, after GeoDesk64):
COPY_REPLACE    = 1             ; copy= what an existing file at the
COPY_SKIP       = 2             ; target gets (tree.s CopyFile)
COPY_NEWER      = 3
PREF_NOASK      = $04           ; delete=now: no question first (actions.s)
PREF_PLAIN      = $08           ; iconcolours=off: no icon colours by type
                                ; (iconview.s; the user, 2026-11-14)
ENTRY_MAX       = 1024          ; a pane's entries (list.s: two REU banks)
SEL_LEN         = ENTRY_MAX / 8 ; the selection's bytes
DROP_OTHER_COPY = 2             ; a drop (listin.s -> desktop.s DropDo; 0
                                ; none): into the other pane, or into the
DROP_PATH_COPY  = 4             ; folder dropPath; + 1: moved (bit 0)
CODE_REC        = $90           ; sidebar codes: favourites $80 + the slot,
                                ; recent documents CODE_REC + the slot
TB_TWO          = 0             ; the toolbar (tbMode): two lines, 16 px,
TB_ONE          = 1             ; one line, 8 px,
TB_OFF          = 2             ; none
TB_Y            = MENU_BOTTOM + 2 ; the toolbar's first pixel row (16)
TB_BUTTONS      = 17            ; (toolbar.s, tooldraw.s)
VIEW_LIST       = 0
VIEW_ICONS      = 1
VIEW_DETAILED   = 2
SORT_REV        = $80           ; sortMode: the order reversed (sort=-date;
SORT_KEYS       = $7F           ; the user, 2026-11-13), the rest the key
SORT_DATE       = 1             ; (0 name, 3 type)
SORT_SIZE       = 2
COL_SIZE        = 246           ; the detailed view (list.s): sizes end
COL_DATE        = 254           ; here, dates start here (their headings
                                ; on the path line: a click sorts, listin.s)
ARROW_ROOM      = 10            ; one list: the sort arrow's room at the
                                ; path line's right end (list.s, listin.s)
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
TEXT_MAX        = 2048          ; an INI file's bytes, at most (3072 until
                                ; 2026-11-13: 1 KB back for the core; the
                                ; files are far smaller; settings.inc INI_MAX,
                                ; gush sysset.s the same)
L_FAV           = 0             ; the lists ("which")
L_REC           = 1
L_DESK          = 2             ; SETTINGS.INI's [desktop] lines
WANT_LEN        = 16            ; the theme's name a [desktop] line names
OPEN_MOUNT      = $80           ; openReq: mount the cursor's disk image
                                ; (listin.s IconHit -> desktop.s OpenReq)
