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
FE_MOUNT        = 17
FE_UMOUNT       = 18
FE_SELECT       = 21
FE_MOUNTINFO    = 23
FE_MKIMG        = 24
FE_REBOOT       = 28

; Redirection markers: Parse makes an unquoted >, >> or < a word of one
; of these bytes (redir.s)
REDIR_OUT       = 1
REDIR_ADD       = 2
REDIR_IN        = 3

; gush's own errors (cmds.s ErrCodes, ErrTexts)
ERR_NO_SERVER   = $F6           ; no NTP server given or set
ERR_CLOCK       = $F7           ; the Ultimate's clock may not be set
ERR_NO_TURBO    = $F8           ; no turbo registers
ERR_WORDS       = $F9           ; the wrong words for the command
ERR_OWN_DRIVE   = $FA           ; the drive gush runs from
ERR_NO_ROOM     = $FB           ; no room in the REU
