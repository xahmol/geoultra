; GeoUltra Settings: constants shared by its modules (docs/SETTINGS.md).

; GEOS jump table (and GeoUltra's extension table)
guExtTable      = $C0E4         ; GeoUltra: the extension table
HorizontalLine  = $C118
VerticalLine    = $C121
Rectangle       = $C124
FrameRectangle  = $C127
InvertRectangle = $C12A
SetPattern      = $C139
BitmapUp        = $C142
PutString       = $C148
UseSystemFont   = $C14B
DoIcons         = $C15A
GetCharWidth    = $C1C9
EnterDeskTop    = $C22C
DoDlgBox        = $C256
FindFile        = $C20B
OpenDisk        = $C2A1
StashRAM        = $C2C8
FetchRAM        = $C2CB

FE_ENTRY        = 30            ; the file engine: guExtTable + 30
TXT_LN_4_Y      = 64            ; a dialog's fourth text line (16 to 80 in steps of 16)

; The screen (docs/SETTINGS.md, "Decisions": a side list of pages, the
; page on the right, OK, Cancel and Save at the bottom)
TITLE_Y         = 11            ; the title's baseline (the bar: y 0-15)
TITLE_LINE      = 15            ; the line under it
SIDE_W          = 80            ; the side list: x 0-79
SIDE_LINE       = 82            ; the line between list and page
SIDE_TOP        = 16            ; the first page name's row top (rows on
SIDE_ROW        = 16            ; whole cards: the mark's colours; from 16
                                ; since 2026-11-19: ten pages to the button
                                ; line, 176)
PAGE_LEFT       = 90            ; the page: x 90-319
PAGE_TOP        = 16            ; y 16 to PAGE_BOTTOM
PAGE_BOTTOM     = 171
BUTTON_LINE     = 176           ; the line above the buttons (the buttons'
                                ; strip: card rows 22-24)
BUTTON_Y        = 180           ; the buttons' top
SCREEN_RIGHT    = 319
PAGE_CARD       = PAGE_LEFT / 8 ; the page's first card (11: x 88)
PAGES_N         = 10            ; Theme, Desktop, System, Time, Drives,
                                ; REU, Pointer, Start, Printing, Serials
                                ; (PAGE_*; the user, 2026-11-12: Time its
                                ; own page; 2026-11-19: Serials)
        .assert SIDE_TOP + PAGES_N * SIDE_ROW <= BUTTON_LINE, error, "settings.inc: the side list into the buttons"
PAGE_THEME      = 0
PAGE_DESKTOP    = 1
PAGE_SYSTEM     = 2
PAGE_TIME       = 3
PAGE_DRIVES     = 4
PAGE_REU        = 5
PAGE_POINTER    = 6
PAGE_START      = 7             ; auto-exec files at the cold start (pstart.s)
PAGE_PRINT      = 8             ; the printer (pprint.s)
PAGE_SERIALS    = 9             ; serial numbers (pser.s)

; The INI text (src/inc/ini.inc): SETTINGS.INI whole, at most 2048 bytes
; as the desktop and gush read it
INI_MAX         = 2048          ; (as the desktop's TEXT_MAX; 3072 until 2026-11-13)
THEME_MAX       = 1024          ; a theme file (the desktop's FILE_MAX)
THEME_NAME      = 16            ; a theme's name and its zero
THEMES_MAX      = 10            ; theme files listed (as the desktop's menu)

; A theme's line (chrome.s ReadLine)
VAL_MAX         = 60            ; a line's value, at most
DEF_INK         = 11            ; a missing line: dark grey on light grey
DEF_PAPER       = 15
