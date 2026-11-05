; gush (docs/GUSH.md): constants shared by its sources.

COLS            = 53            ; the console: 6-pixel cells on 320 pixels
ROWS            = 25            ; row 0 the status line
ROWS_TEXT       = 24            ; rows 1-24 text
ROWS_LAST       = 24
STATUS_FROM     = 6             ; the status line: "gush", the path from
STATUS_PATH     = 40            ; column 6 (at most 40 columns), the time
LINE_MAX        = 254           ; an input line, without its zero
ARGS_MAX        = 32            ; words of a command line (after * and ?)
ARGBUF_SIZE     = 1024          ; their bytes

hour            = $8519         ; GEOS's clock (year at $8516)
minutes         = $851A

; Keys (keyData): geos.inc has them (DEL is KEY_DELETE, cursor left
; KEY_LEFT), and CR.

; The file engine (docs/FILE_ENGINE.md): entry 6 of GeoUltra's extension
; jump table, whose address is at guExtTable (gush.s, FileEngine); its
; functions and errors.
guExtTable      = $C0E4
FE_ENTRY        = 30            ; (the entry's offset in the table)
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
