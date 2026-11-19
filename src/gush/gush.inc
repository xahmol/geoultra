; gush (docs/GUSH.md): constants shared by its sources.

COLS            = 53            ; the console: 6-pixel cells on 320 pixels
ROWS            = 25            ; row 0 the status line
ROWS_TEXT       = 24            ; rows 1-24 text
ROWS_LAST       = 24
STATUS_FROM     = 6             ; the status line: "gush", the path from
STATUS_PATH     = 38            ; column 6 (at most 38 columns), the time,
CLOSE_COL       = COLS - 2      ; the close "x" (a click there: exit; the
                                ; user, 2026-11-13)
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
FE_RUNSYS       = 22
FE_RUNDOC       = 35            ; (an application on E with a document)
FE_NOT_SUPPORTED = $4E          ; (engine.inc)
FE_UCI          = 30

; Redirection markers: Parse makes an unquoted >, >> or < a word of one
; of these bytes (redir.s)
REDIR_OUT       = 1
REDIR_ADD       = 2
REDIR_IN        = 3

IS_SCRIPT       = $F2           ; prog.s: a plain file, a script (no error)
IS_MODULE       = $F1           ; prog.s: an external command (module.s)
ERR_MODULE      = $F0           ; not a gush command (or for a newer gush)
ERR_URL         = $EF           ; wget: not an http:// URL, or too long
ERR_HTTP        = $EE           ; wget: the answer ended in its headers
ERR_TIMEOUT     = $ED           ; wget: no answer in time

; gush's own errors (cmds.s ErrCodes, ErrTexts)
ERR_DEEP        = $F3           ; scripts nested too deep
ERR_ONE_REDIR   = $F4           ; a second output redirection (a script's)
ERR_LONG        = $F5           ; a script longer than its REU area
ERR_NO_SERVER   = $F6           ; no NTP server given or set
ERR_CLOCK       = $F7           ; the Ultimate's clock may not be set
ERR_NO_TURBO    = $F8           ; no turbo registers
ERR_WORDS       = $F9           ; the wrong words for the command
ERR_OWN_DRIVE   = $FA           ; the drive gush runs from
ERR_NO_ROOM     = $FB           ; no room in the REU

; The file engine's info block (FE_STAT, FE_READDIR; FILE_ENGINE.md):
FI_KIND         = 0             ; the kind (K_*)
FI_CBM          = 1             ; the CBM file type
FI_GTYPE        = 3             ; the GEOS file type
FI_SIZE         = 4             ; blocks (Ultimate: bytes), 32 bits
FI_DATE         = 8
K_ROOT          = 0             ; "/"
K_DRIVE         = 1
K_FOLDER        = 2
K_GEOS          = 3             ; a GEOS file
K_CBM           = 4             ; a plain CBM file
K_UFILE         = 5             ; a file on the Ultimate
K_UDIR          = 6             ; a folder on the Ultimate
FO_READ         = 0             ; FE_OPEN's modes
FO_WRITE        = 1
FO_APPEND       = 2
APPL_DATA       = 7             ; (GEOS file type: a module, prog.s)

; The transient area (ovl.s): the overlays and external commands.
TRANS           = $5000
TRANS_SIZE      = $1000
