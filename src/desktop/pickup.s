; GeoUltra Desktop: geoLaser's PostScript picked up (docs/design/DESIGN.md
; "Printing", the geoLaser route; the user's decisions of 2026-11-19:
; the pickup only, the files moved). geoLaser and geoPubLaser (the
; user's own) write their PostScript as a CBM SEQ file "PS.<name>" onto
; drive A or B; at the desktop's start (with the CVT font import,
; overlay 9) each such file in the root of drives A-D is copied to
; GEOULTRA/print/<name>.ps on the Ultimate (raw; an older one of that
; name replaced) and deleted from the image; a note says so. No
; Ultimate (no home folder): nothing. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Dialog, RunE, appName, docShort, docDrive
        .export Pickup, Refused

FC_RAW          = $02
FI_CBM          = 1             ; the CBM type byte (its low bits: 1 SEQ)
CBM_SEQ         = 1
KEEP_N          = 4             ; files a drive's pass keeps (the rest:
                                ; at the next start)
SHORT_LEN       = 17            ; a GEOS name and its zero

        .segment "ZEROPAGE"

pLine1: .res 2                  ; (DBVARSTR: zero page pointers)
pp:     .res 2                  ; a name being copied

        .segment "OV9"

; Refused (the desktop's first tick, before the pickup; docs/design/DESIGN.md
; "Serial number" S5, the user's decision of 2026-11-19): when the kernal
; noted an application that refused its serial number (FE_SERIALS with
; r1 = 0: its class; serials.s), a question: "<class> refused to run" /
; "(its serial number). Set it in Settings?"; YES starts GU Settings from
; drive E with the class as its "document" (open.s RunE: Settings opens
; its Serials page and asks the number). Destroys all.
Refused:
        lda #<refCls
        sta r0L
        lda #>refCls
        sta r0H
        lda #0
        sta r1L
        sta r1H
        lda #FE_SERIALS
        jsr FileEngine
        txa
        bne @end
        ldx #1                  ; line 1: (BOLDON,) the class and " refused
        ldy #0                  ; to run"
:       lda refCls,y
        beq :+
        sta refLine,x
        inx
        iny
        cpy #12
        bcc :-
:       dex                     ; (trailing spaces off)
        lda refLine,x
        cmp #' '
        beq :-
        inx
        ldy #0
:       lda RefText,y
        sta refLine,x
        beq :+
        inx
        iny
        bne :-
:       lda #<refLine
        sta pLine1
        lda #>refLine
        sta pLine1 + 1
        lda #<refDlg
        sta r0L
        lda #>refDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #YES
        bne @end
        ldx #SETTINGS_LEN       ; GU Settings with the class
:       lda SettingsName,x
        sta appName,x
        dex
        bpl :-
        ldx #12
:       lda refCls,x
        sta docShort,x
        dex
        bpl :-
        lda #8
        sta docDrive
        jmp RunE                ; (back only after an error)
@end:   rts

; Pickup: see above. Destroys all.
Pickup: lda #<home
        sta r1L
        lda #>home
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @end
        lda home                ; (an empty home: no Ultimate, VICE)
        cmp #'/'
        bne @end
        lda #0
        sta moved
        sta drive
@drive: ldx drive
        lda driveType,x
        beq @next
        jsr Collect             ; its PS.* files' names
        jsr MoveAll
@next:  inc drive
        lda drive
        cmp #4
        bcc @drive
        lda moved
        beq @end
        lda #<NoteText
        sta pLine1
        lda #>NoteText
        sta pLine1 + 1
        lda #<noteDlg
        sta r0L
        lda #>noteDlg
        sta r0H
        jmp Dialog
@end:   rts

; Collect: the names of the CBM SEQ files "PS.*" in the root of drive
; `drive` (at most KEEP_N) in names, their count in found.
Collect:
        lda #0
        sta found
        lda drive
        clc
        adc #'a'
        sta root + 1
        lda #<root
        sta r0L
        lda #>root
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@read:  ldy handle
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<name
        sta r2L
        lda #>name
        sta r2H
        lda #0
        sta r3L
        sta r3H
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close              ; (the end, or an error)
        lda info + FI_KIND
        cmp #K_CBM
        bne @read
        lda info + FI_CBM
        and #7
        cmp #CBM_SEQ
        bne @read
        ldx #2                  ; "PS."
:       lda name,x
        cmp Prefix,x
        bne @read
        dex
        bpl :-
        ldx found
        cpx #KEEP_N
        bcs @read
        jsr NameAt              ; names[found] = name
        ldy #SHORT_LEN - 1
:       lda name,y
        sta (pp),y
        dey
        bpl :-
        ldy #SHORT_LEN - 1       ; (a GEOS name: 16 characters at most)
        lda #0
        sta (pp),y
        inc found
        bne @read
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; NameAt: pp = names + X * SHORT_LEN (X < KEEP_N). Destroys A, X.
NameAt: lda #<names
        sta pp
        lda #>names
        sta pp + 1
        txa
        beq @end
:       lda pp
        clc
        adc #SHORT_LEN
        sta pp
        bcc :+
        inc pp + 1
:       dex
        bne :--
@end:   rts

; MoveAll: each collected file copied to <home>print/<name without
; "PS.">.ps (the folder made first; there already: fine), deleted from
; the image when the copy worked; moved counts them.
MoveAll:
        lda found
        beq @end
        jsr PrintDir
        lda #0
        sta at
@each:  lda at
        cmp found
        bcs @end
        tax
        jsr NameAt
        jsr Paths               ; src, dst
        lda #<src
        sta r0L
        lda #>src
        sta r0H
        lda #<dst
        sta r1L
        lda #>dst
        sta r1H
        lda #FC_OVERWRITE | FC_RAW
        sta r2L
        lda #0
        sta r3L
        sta r3H
        lda #FE_COPY
        jsr FileEngine
        txa
        bne @skip               ; (not copied: left where it is)
        lda #<src
        sta r0L
        lda #>src
        sta r0H
        lda #FE_DELETE          ; (an error not minded: the copy is made;
        jsr FileEngine          ; the next start copies it again, over it)
        inc moved
@skip:  inc at
        bne @each
@end:   rts

; PrintDir: <home>print made (FE_MKDIR; there already: an error, not
; minded).
PrintDir:
        jsr Home
        ldx #0
:       lda PrintText,x
        sta dst,y
        beq :+
        iny
        inx
        bne :-
:       lda #<dst
        sta r0L
        lda #>dst
        sta r0H
        lda #0
        sta r2L
        lda #FE_MKDIR
        jmp FileEngine

; Home: dst = the home folder; Y = its length.
Home:   ldy #0
:       lda home,y
        sta dst,y
        beq :+
        iny
        bne :-
:       rts

; Paths: src = "/x/" + the name at pp; dst = <home>print/ + the name
; less "PS." + ".ps".
Paths:  lda root + 1
        sta src + 1
        lda #'/'
        sta src
        sta src + 2
        ldy #0
:       lda (pp),y
        sta src + 3,y
        beq :+
        iny
        bne :-
:       jsr Home
        ldx #0
:       lda PrintText,x
        beq :+
        sta dst,y
        iny
        inx
        bne :-
:       lda #'/'
        sta dst,y
        iny
        sty tmpN
        ldy #3                  ; (after "PS.")
:       lda (pp),y
        beq :+
        sty tmpY
        ldy tmpN
        sta dst,y
        inc tmpN
        ldy tmpY
        iny
        bne :-
:       ldy tmpN
        ldx #0
:       lda PsExt,x
        sta dst,y
        beq :+
        iny
        inx
        bne :-
:       rts

noteDlg:
        .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, pLine1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word NoteText2
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
refDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, pLine1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word RefText2
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0
RefText:        .byte " refused to run", PLAINTEXT, 0
RefText2:       .byte "(its serial). Set it in Settings?", 0
SettingsName:   .byte "GU Settings", 0
SETTINGS_LEN    = * - SettingsName - 1
NoteText:       .byte BOLDON, "PostScript from geoLaser", PLAINTEXT, 0
NoteText2:      .byte "moved to GEOULTRA/print.", 0
Prefix:         .byte "PS."
PrintText:      .byte "print", 0
PsExt:          .byte ".ps", 0

refCls: .res 13
refLine: .byte BOLDON
        .res 32
root:   .byte "/a", 0
drive:  .byte 0
handle: .byte 0
found:  .byte 0
moved:  .byte 0
at:     .byte 0
tmpN:   .byte 0
tmpY:   .byte 0
home:   .res 32
info:   .res INFO_LEN
name:   .res 61
names:  .res KEEP_N * SHORT_LEN
src:    .res 3 + SHORT_LEN
dst:    .res 32 + 6 + SHORT_LEN + 3
