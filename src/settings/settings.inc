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
StashRAM        = $C2C8
FetchRAM        = $C2CB

FE_ENTRY        = 30            ; the file engine: guExtTable + 30

; The screen (docs/SETTINGS.md, "Decisions": a side list of pages, the
; page on the right, OK, Cancel and Save at the bottom)
TITLE_Y         = 10            ; the title's baseline
TITLE_LINE      = 14            ; the line under it
SIDE_W          = 80            ; the side list: x 0-79
SIDE_LINE       = 82            ; the line between list and page
SIDE_TOP        = 20            ; the first page name's row top
SIDE_ROW        = 14            ; a page name's row
PAGE_LEFT       = 90            ; the page: x 90-319
PAGE_TOP        = 16            ; y 16 to PAGE_BOTTOM
PAGE_BOTTOM     = 171
BUTTON_LINE     = 174           ; the line above the buttons
BUTTON_Y        = 180           ; the buttons' top
SCREEN_RIGHT    = 319
PAGES_N         = 6             ; Theme, Desktop, System, Drives, REU,
                                ; Pointer (PAGE_*)
PAGE_THEME      = 0
PAGE_DESKTOP    = 1
PAGE_SYSTEM     = 2
PAGE_DRIVES     = 3
PAGE_REU        = 4
PAGE_POINTER    = 5

; The INI text (src/inc/ini.inc): SETTINGS.INI whole, at most 3072 bytes
; as the desktop and gush read it
INI_MAX         = 3072
