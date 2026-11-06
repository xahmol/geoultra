; gushapi.inc: what an external gush command needs (docs/GUSH_COMMANDS.md).
; A module is linked at GU_TRANS (src/cmds/cmd.cfg) and starts with
;
;       .byte "GCMD", GU_API_VERSION
;       jmp Main
;
; Main runs with the words in place (GU_ARGC, GU_ARG; word 0 the
; command's name) and returns with C clear (done) or set (failed). It may
; use r0-r15 and gush's free zero page GU_ZP .. GU_ZP_END; everything
; else of gush's belongs to gush. Own code, GeoUltra.

GU_API_VERSION  = 1
GU_TRANS        = $5000         ; where the module runs, 4 KB at most

GU_ZP           = $E0           ; zero page free for a module
GU_ZP_END       = $EF

; The jump table (gush.s; registers as given, others destroyed).
GU_PUTC         = $0403         ; A: a character (CR: a new line)
GU_PRINT        = $0406         ; A/Y (low, high): a zero-ended text
GU_NEWLINE      = $0409         ; a new line
GU_FILEENGINE   = $040C         ; A: function, Y: handle, r0-r4
GU_FAIL         = $040F         ; X: error, Y: word ($FF: none); said
GU_ARG          = $0412         ; X: word -> r0: its text (zero-ended)
GU_ARGC         = $0415         ; -> A: the words
GU_GETVAR       = $0418         ; r0: name -> r1: value; C set: none
GU_SETVAR       = $041B         ; r0: name, r1: value; C set: no room
GU_READIN       = $041E         ; r1: buffer, r2: length -> r2: read (0:
                                ; the end); C set: no input; X: error
GU_DECIMAL      = $0421         ; r0-r1: a 32-bit number, A: columns
GU_KEY          = $0424         ; -> A: a key, waited for

; File engine functions (docs/FILE_ENGINE.md) a command needs most.
FE_STAT         = 1
FE_OPENDIR      = 2
FE_READDIR      = 3
FE_CLOSE        = 4
FE_OPEN         = 13
FE_READ         = 14
FE_WRITE        = 15
FO_READ         = 0
FO_WRITE        = 1
FO_APPEND       = 2
