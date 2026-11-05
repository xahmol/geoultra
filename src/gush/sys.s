; gush: system commands (docs/GUSH.md, "Step 2"): mount, umount,
; mkimg, free, reboot. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Status, pwdBuf, startDrive, argc, argLo, argHi
        .import ArgR0, PutArg, Print, Say, Fail, Decimal, num
        .import ConPut, ConNewLine, Options, firstArg, tracks
        .export CmdMount, CmdUmount, CmdMkimg, CmdFree, CmdReboot

INSUFF_SPACE    = 3
PATH_MAX        = 250           ; a new image's path (the engine's: 255)
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

; mkimg [-t tracks] type path [name]: a new, empty disk image on the
; Ultimate: type d64, d71, d81 or dnp (-t: its tracks, else 16); ".type"
; added to the path when it does not end so; the disk name the file's
; name (16 characters at most) unless given.
CmdMkimg:
        jsr Options
        bcs @end
        lda argc                ; two or three words after the options
        sec
        sbc firstArg
        cmp #2
        bcc @words
        cmp #4
        bcc :+
@words: jmp Words
:       sta words
        ldx firstArg            ; the type
        jsr ArgR0
        ldx #3
@type:  ldy #0
@ch:    lda (r0),y
        ora #$20
        cmp Kinds,x             ; (Kinds: "d64", "d71", "d81", "dnp",
        bne @next               ; one byte per kind per column)
        iny
        txa
        clc
        adc #4
        tax
        cpy #3
        bne @ch
        lda (r0),y
        beq @kind
@next:  txa                     ; the next kind (X back to its column 0)
        and #3
        tax
        dex
        bpl @type
        ldy firstArg
        ldx #FE_BAD_PATH
        jmp Fail
@kind:  txa
        and #3
        sta kind
        jsr Path
        bcs @end
        jsr DiskName
        lda #<imgPath
        sta r0L
        lda #>imgPath
        sta r0H
        lda #<diskName
        sta r1L
        lda #>diskName
        sta r1H
        lda tracks
        sta r2L
        lda #FE_MKIMG
        jsr FileEngine
        txa
        beq @end
        cpx #INSUFF_SPACE
        bne :+
        ldx #ERR_NO_ROOM
:       ldy firstArg
        iny
        jmp Fail
@end:   rts

; Path: the path word to imgPath, ".type" added when it does not end so.
; C set when it is too long (said).
Path:   ldx firstArg
        inx
        jsr ArgR0
        ldy #0
@copy:  lda (r0),y
        sta imgPath,y
        beq @end
        iny
        cpy #PATH_MAX
        bcc @copy
@long:  ldx #FE_BAD_PATH
        ldy firstArg
        iny
        jsr Fail
        sec
        rts
@end:   sty pathLen
        cpy #4                  ; ".xyz" at its end?
        bcc @add
        lda imgPath-4,y
        cmp #'.'
        bne @add
        ldx kind
        lda imgPath-3,y
        ora #$20
        cmp Kinds,x
        bne @add
        lda imgPath-2,y
        ora #$20
        cmp Kinds+4,x
        bne @add
        lda imgPath-1,y
        ora #$20
        cmp Kinds+8,x
        beq @ok
@add:   cpy #PATH_MAX - 4
        bcs @long
        lda #'.'
        sta imgPath,y
        ldx kind
        lda Kinds,x
        sta imgPath+1,y
        lda Kinds+4,x
        sta imgPath+2,y
        lda Kinds+8,x
        sta imgPath+3,y
        lda #0
        sta imgPath+4,y
        tya
        clc
        adc #4
        sta pathLen
@ok:    clc
        rts

; DiskName: the name word (the third), else imgPath's file name without
; its extension, to diskName (16 characters at most, zero-ended).
DiskName:
        lda words
        cmp #3
        bne @file
        ldx firstArg
        inx
        inx
        jsr ArgR0
        ldy #0
@word:  lda (r0),y
        sta diskName,y
        beq @end
        iny
        cpy #16
        bne @word
        beq @cut
@file:  ldx pathLen             ; after the last "/"
@slash: dex
        bmi @from
        lda imgPath,x
        cmp #'/'
        bne @slash
@from:  inx
        ldy #0
@char:  lda imgPath,x
        beq @cut
        cmp #'.'
        beq @dot
        sta diskName,y
        inx
        iny
        cpy #16
        bne @char
        beq @cut
@dot:   stx dotAt               ; (the last "." ends it)
        jsr LastDot
        bcc @cut
        lda #'.'
        sta diskName,y
        inx
        iny
        cpy #16
        bne @char
@cut:   lda #0
        sta diskName,y
@end:   rts

; LastDot: C set when another "." follows dotAt in imgPath.
LastDot:
        ldx dotAt
@more:  inx
        lda imgPath,x
        beq @no
        cmp #'.'
        bne @more
        ldx dotAt
        sec
        rts
@no:    ldx dotAt
        clc
        rts

Kinds:  .byte "dddd", "678n", "411p"    ; d64, d71, d81, dnp by column

; free: the REU's banks for drives (31-187): each drive's, in all, free.
CmdFree:
        lda #0
        sta drive
        sta used
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
        ldx r2L                 ; its banks (native: its tracks)
        lda BanksOf-1,x
        bne :+
        lda r3L
:       pha
        clc
        adc used
        sta used
        lda #<name
        ldy #>name
        jsr Print
        pla
        ldx #6
        jsr Number
        lda #<Banks
        ldy #>Banks
        jsr Say
@next:  inc drive
        lda drive
        cmp #4
        bne @drive
        lda #<Drives            ; "drives: N of 157 banks used, M free"
        ldy #>Drives
        jsr Print
        lda used
        ldx #1
        jsr Number
        lda #<Of
        ldy #>Of
        jsr Print
        lda #DRIVE_BANKS
        sec
        sbc used
        ldx #1
        jsr Number
        lda #<FreeText
        ldy #>FreeText
        jmp Say

; Number: A in decimal, right-aligned in X columns.
Number: sta num
        lda #0
        sta num+1
        sta num+2
        sta num+3
        txa
        jmp Decimal

BanksOf:.byte 3, 6, 13, 0       ; 1541, 1571, 1581; native: its tracks
Banks:  .byte " banks (64 KB each)", 0
Drives: .byte "drives: ", 0
Of:     .byte " of 157 banks used, ", 0
FreeText:.byte " free", 0
DRIVE_BANKS     = 157           ; banks 31-187 (docs/DESIGN.md, REU map)

; reboot: every drive written back, GeoUltra started afresh (the
; hibernated session dropped). Back only when that failed.
CmdReboot:
        lda argc
        cmp #1
        beq :+
        jmp Words
:       lda #FE_REBOOT
        jsr FileEngine
        ldy #$FF
        jmp Fail

TypeLo: .byte <T1541, <T1571, <T1581, <TNative
TypeHi: .byte >T1541, >T1571, >T1581, >TNative
T1541:  .byte "  1541    ", 0
T1571:  .byte "  1571    ", 0
T1581:  .byte "  1581    ", 0
TNative:.byte "  native  ", 0
Root:   .byte "/", 0

        .segment "DATA"

kind:   .byte 0
words:  .byte 0
used:   .byte 0
pathLen:.byte 0
dotAt:  .byte 0
name:   .byte "/a", 0
drive:  .byte 0
word:   .byte 0

        .segment "BSS"

path:   .res 64
imgPath:.res PATH_MAX + 1
diskName:.res 17
