; gush: starting programs (docs/GUSH.md, "Starting programs"). A word
; that is no command names a GEOS application or desk accessory: by its
; path, or by name in the current directory and then in the root of each
; drive A-D (drive E, "/e/bin" in the design, when the file engine knows
; drive E). FE_SELECT makes its drive and folder current, GetFile starts
; it: an application replaces gush; a desk accessory comes back, and gush
; redraws its screen. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Status, ConRedraw, argLo, argHi
        .export StartProgram

GetFile         = $C208         ; GEOS jump table
FI_KIND         = 0
FI_GTYPE        = 3
K_GEOS          = 3
FE_SELECT       = 21

        .segment "CODE"

; StartProgram: word 0 as a program. X = 0 (a desk accessory ran), or
; FILE_NOT_FOUND (none), STRUCT_MISMAT (found, but no program), or
; GetFile's error. An application does not come back.
StartProgram:
        lda argLo               ; a "/" in it: that path only
        sta r0L
        lda argHi
        sta r0H
        ldy #$FF
@slash: iny
        lda (r0),y
        beq @name
        cmp #'/'
        bne @slash
        jsr Try                 ; (r0: the word)
        bcc Found
        rts
@name:  sty wordLen             ; (its length)
        jsr Try                 ; the current directory
        bcc Found
        cpx #FILE_NOT_FOUND
        bne @end
        lda wordLen             ; longer than a name: on no drive's root
        cmp #FE_NAME_MAX_LONG + 1
        bcs @end
        lda #'a'                ; then "/a/NAME" .. "/d/NAME"
        sta drive
@drive: jsr Build
        jsr Try
        bcc Found
        cpx #FILE_NOT_FOUND
        bne @end
        inc drive
        lda drive
        cmp #'d' + 1
        bcc @drive
@end:   rts

; Try: the path at r0 a program? C clear (r0 kept in prog); else C set,
; X = FILE_NOT_FOUND or STRUCT_MISMAT (there, but no program).
Try:    lda r0L
        sta prog
        lda r0H
        sta prog+1
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        bne @none
        ldx #STRUCT_MISMAT
        lda info + FI_KIND
        cmp #K_GEOS
        bne @no
        lda info + FI_GTYPE
        cmp #APPLICATION
        beq @yes
        cmp #DESK_ACC
        bne @no
@yes:   clc
        rts
@none:  ldx #FILE_NOT_FOUND     ; (any error: not there)
@no:    sec
        rts

; Found: its folder current (FE_SELECT), GetFile by its short name.
Found:  lda prog
        sta r0L
        lda prog+1
        sta r0H
        lda #<short
        sta r1L
        lda #>short
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @end
        lda #<short
        sta r6L
        lda #>short
        sta r6H
        lda #0                  ; (no data file)
        sta r0L
        jsr GetFile             ; (an application: no return)
        txa
        pha
        jsr ConRedraw           ; a desk accessory back: the screen anew
        jsr Status
        pla
        tax
@end:   rts

; Build: path = "/" drive "/" word 0, at r0.
Build:  lda #'/'
        sta path
        sta path+2
        lda drive
        sta path+1
        lda argLo
        sta r1L
        lda argHi
        sta r1H
        ldy #0
@copy:  lda (r1),y              ; (at most FE_NAME_MAX_LONG: StartProgram
        sta path+3,y            ; checked it)
        beq @done
        iny
        bne @copy
@done:  lda #<path
        sta r0L
        lda #>path
        sta r0H
        rts

FE_NAME_MAX_LONG = 60

        .segment "DATA"

drive:          .byte 0
wordLen:        .byte 0
prog:           .word 0

        .segment "BSS"

info:           .res 16
short:          .res 17
path:           .res 3 + FE_NAME_MAX_LONG + 1
