; gush: system commands (docs/GUSH.md, "Step 2"): mount, umount. Own
; code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Status, pwdBuf, startDrive, argc, argLo, argHi
        .import ArgR0, PutArg, Print, Say, Fail
        .import ConPut, ConNewLine
        .export CmdMount, CmdUmount

INSUFF_SPACE    = 3
FE_BAD_PATH     = $49

        .segment "CODE"

; mount: the drives' images. mount image drive: an image on the
; Ultimate into drive /a-/d (its old image written back first), not the
; drive gush runs from.
CmdMount:
        lda argc
        cmp #1
        bne :+
        jmp List
:       cmp #3
        bne Words
        ldx #2
        jsr Drive
        bcs @end
        ldx #1                  ; r1 = the image, r0 = the drive
        jsr ArgR0
        lda r0L
        sta r1L
        lda r0H
        sta r1H
        ldx #2
        jsr ArgR0
        lda #FE_MOUNT
        jsr FileEngine
        txa
        beq Away
        cpx #INSUFF_SPACE       ; (not the disk: the REU)
        bne :+
        ldx #ERR_NO_ROOM
:       ldy #1
        jmp Fail
@end:   rts

; umount drive: the drive's image written back, the drive emptied.
CmdUmount:
        lda argc
        cmp #2
        bne Words
        ldx #1
        jsr Drive
        bcs @end
        ldx #1
        jsr ArgR0
        lda #FE_UMOUNT
        jsr FileEngine
        txa
        beq Away
        ldy #1
        jmp Fail
@end:   rts

; Words: the wrong words for the command.
Words:  ldx #ERR_WORDS
        ldy #$FF
        jmp Fail

; Drive: word X a drive "/a"-"/d" (a "/" after it allowed) other than
; gush's own: slot (0-3) in drive, C clear; else said, C set.
Drive:  stx word
        jsr ArgR0
        ldy #0
        lda (r0),y
        cmp #'/'
        bne @bad
        iny
        lda (r0),y
        ora #$20
        sec
        sbc #'a'
        cmp #4
        bcs @bad
        sta drive
        iny
        lda (r0),y
        beq @own
        cmp #'/'
        bne @bad
        iny
        lda (r0),y
        bne @bad
@own:   lda startDrive          ; not gush's own drive
        sec
        sbc #8
        cmp drive
        beq @mine
        clc
        rts
@mine:  ldx #ERR_OWN_DRIVE
        .byte $2C               ; (bit abs: skips the next ldx)
@bad:   ldx #FE_BAD_PATH
        ldy word
        jsr Fail
        sec
        rts

; Away: gush's current directory, if on drive `drive`, becomes "/" (the
; drive was emptied, or holds another image now); the status line anew.
Away:   lda #<pwdBuf
        sta r0L
        lda #>pwdBuf
        sta r0H
        lda #FE_PWD
        jsr FileEngine
        lda pwdBuf+1
        ora #$20
        sec
        sbc #'a'
        cmp drive
        bne @show
        lda pwdBuf+2
        beq @root
        cmp #'/'
        bne @show
@root:  lda #<Root
        sta r0L
        lda #>Root
        sta r0H
        lda #FE_CD
        jsr FileEngine
@show:  jmp Status

; List: "/a  1581  path" for each drive that holds an image.
List:   lda #0
        sta drive
@drive: lda drive
        clc
        adc #'a'
        sta name+1
        lda #<name
        sta r0L
        lda #>name
        sta r0H
        lda #<path
        sta r1L
        lda #>path
        sta r1H
        lda #FE_MOUNTINFO
        jsr FileEngine
        txa
        bne @next
        lda r2L                 ; (its type)
        pha
        lda #<name
        ldy #>name
        jsr Print
        pla
        tax
        lda TypeLo-1,x
        ldy TypeHi-1,x
        jsr Print
        lda #<path
        ldy #>path
        jsr Say
@next:  inc drive
        lda drive
        cmp #4
        bne @drive
        rts

TypeLo: .byte <T1541, <T1571, <T1581, <TNative
TypeHi: .byte >T1541, >T1571, >T1581, >TNative
T1541:  .byte "  1541    ", 0
T1571:  .byte "  1571    ", 0
T1581:  .byte "  1581    ", 0
TNative:.byte "  native  ", 0
Root:   .byte "/", 0

        .segment "DATA"

name:   .byte "/a", 0
drive:  .byte 0
word:   .byte 0

        .segment "BSS"

path:   .res 64
