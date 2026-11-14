; GeoUltra Desktop: the list sorted (overlay 6, ovl.s; the user,
; 2026-11-11): ".." first, then folders and drives, then files, each
; group by name, any case. Run from MainLoop right after a folder was
; read (list.s marks the list, theme.s's ClockTick calls SortNow), so
; it may be an overlay although ListRead is also called from overlays.
;
; Each entry gets an 8-byte key (its group and the first 7 characters of
; its name, folded to upper case) in side.s's text buffer, free at that
; moment; a Shell sort orders an array of pointers to the keys; then the
; entries are moved in the REU table along the permutation's cycles,
; one entry at a time. Up to SORT_MAX entries (folders with more stay in
; disk order); names alike in their first 7 characters keep their disk
; order among themselves. Own code (Shell sort with Ciura's gaps, a
; textbook algorithm).

        .include "geos.inc"
        .include "desktop.inc"

        .import count, Fetch, Place, entryInfo, entryName, text, IsDotDot, sortMode
        .export Ov_SortList
Ov_SortList = SortList

KEY_LEN         = 8             ; a key: its group and 7 characters
KEY_CHARS       = KEY_LEN - 1
SORT_MAX        = (TEXT_MAX + 1) / KEY_LEN ; 384 keys in text
ENTRY_BYTES     = INFO_LEN + NAME_LEN ; an entry in the REU table (list.s)
G_UP            = 0             ; the groups: ".." (0), folders and
                                ; drives (1), files (2)

kp      = r5                    ; a key (building), the key compared
pp      = r6                    ; a pointer in ptrs
ka      = r7                    ; Compare: the two keys
kb      = r8

        .segment "OV6"

; SortList (list.s, SortNow): the entry table sorted (nothing for fewer
; than 2 entries or more than SORT_MAX).
SortList:
        lda count+1
        cmp #>SORT_MAX
        bcc @size
        bne @end
        lda count
        cmp #<SORT_MAX + 1
        bcs @end
@size:  lda count+1
        bne :+
        lda count
        cmp #2
        bcc @end
:       jsr Keys
        jsr Shell
        jmp Permute
@end:   rts

; Keys: a key per entry in text, ptrs[i] = its address.
Keys:   lda #<text
        sta kp
        lda #>text
        sta kp+1
        lda #<ptrs
        sta pp
        lda #>ptrs
        sta pp+1
        lda #0
        sta iL
        sta iH
@entry: lda iL
        cmp count
        bne :+
        lda iH
        cmp count+1
        bne :+
        rts                     ; (all keys made)
:       lda iL
        ldx iH
        jsr Fetch               ; (r0-r3; kp and pp kept)
        lda #G_UP               ; its group: "..",
        sta grp
        jsr IsDotDot            ; (Z set: "..")
        beq @group
        inc grp                 ; a folder or drive,
        ldx entryInfo + FI_KIND
        cpx #K_FOLDER
        beq @group
        cpx #K_UDIR
        beq @group
        cpx #K_DRIVE
        beq @group
        inc grp                 ; or a file
@group: ldy #0
        lda grp
        sta (kp),y
        jsr Lead                ; (the sort order's bytes; Y the last one)
        ldx #0
@ch:    cpy #KEY_CHARS          ; (the key full)
        bcs @ptr
        lda entryName,x
        beq @pad
        cmp #'a'                ; (upper case: names sort in any case;
        bcc :+                  ; ASCII's a-z and PETSCII's capitals
        cmp #'z' + 1            ; $C1-$DA, as CBM programs name files)
        bcs @petscii
        and #$DF
        bne :+
@petscii:
        cmp #$C1
        bcc :+
        cmp #$DA + 1
        bcs :+
        and #$7F
:       iny
        sta (kp),y
        inx
        bne @ch                 ; (always)
@pad:   cpy #KEY_CHARS          ; (a short name: zeros after it)
        bcs @ptr
        iny
        sta (kp),y
        bne @pad                ; (Y not 0: always)
@ptr:   bit sortMode        ; reversed (SORT_REV): the key's bytes
        bpl @keep               ; after its group inverted, so folders
        ldy #KEY_CHARS          ; stay first
@inv:   lda (kp),y
        eor #$FF
        sta (kp),y
        dey
        bne @inv
@keep:  ldy #0                  ; ptrs[i] = this key
        lda kp
        sta (pp),y
        iny
        lda kp+1
        sta (pp),y
        lda kp                  ; the next key and pointer
        clc
        adc #KEY_LEN
        sta kp
        bcc :+
        inc kp+1
:       lda pp
        clc
        adc #2
        sta pp
        bcc :+
        inc pp+1
:       inc iL
        bne :+
        inc iH
:       jmp @entry

; Lead: the sort order's bytes after the group (sortMode, SETTINGS.INI
; [desktop] sort=; the user, 2026-11-12, after GeoDesk64's sort modes):
; (bit 7, SORT_REV: the whole order reversed, Keys) name: none; date:
; newest first (year with its century, month, day,
; hour, minute, each inverted); size: largest first (its three low
; bytes, inverted); type: the GEOS file type + 1 (other files 0). The
; name follows in what is left of the key. Y = the last byte written.
Lead:   lda sortMode
        and #SORT_KEYS
        tax
        beq @end
        dex
        beq @date
        dex
        beq @size
        ldx #0                  ; type
        lda entryInfo + FI_KIND
        cmp #K_GEOS
        bne :+
        ldx entryInfo + FI_GTYPE
        inx
:       txa
        iny
        sta (kp),y
@end:   rts
@date:  lda entryInfo + FI_DATE ; the year: 80-99 before 0-79
        cmp #80
        bcs :+
        adc #100
:       jsr Down
        ldx #1
@d:     lda entryInfo + FI_DATE,x
        jsr Down
        inx
        cpx #5
        bcc @d
        rts
@size:  ldx #2
@s:     lda entryInfo + FI_SIZE,x
        jsr Down
        dex
        bpl @s
        rts

; Down: A inverted into the key's next byte (larger sorts first).
Down:   eor #$FF
        iny
        sta (kp),y
        rts

; Shell: ptrs[0..count-1] ordered by their keys (Shell sort; each gap's
; pass an insertion sort over elements gap apart).
Shell:  ldx #0
@gap:   stx gapAt
        lda GapLo,x
        sta gapL
        lda GapHi,x
        sta gapH
        ora gapL
        bne :+
        rts                     ; (the table's end: gap 1 was the last)
:       lda gapH                ; a gap not below count: nothing to do
        cmp count+1
        bcc @pass
        beq :+
        jmp @next
:       lda gapL
        cmp count
        bcc @pass
        jmp @next
@pass:  lda gapL                ; i = gap
        sta iL
        lda gapH
        sta iH
@i:     lda iL                  ; i < count
        cmp count
        lda iH
        sbc count+1
        bcc :+
        jmp @next
:
        lda iL                  ; t = ptrs[i]
        ldx iH
        jsr PtrAt
        ldy #0
        lda (pp),y
        sta tL
        iny
        lda (pp),y
        sta tH
        lda iL                  ; j = i
        sta jL
        lda iH
        sta jH
@j:     lda jL                  ; while j >= gap and ptrs[j - gap] > t
        cmp gapL
        lda jH
        sbc gapH
        bcc @put
        lda jL
        sec
        sbc gapL
        sta kL
        lda jH
        sbc gapH
        sta kH
        tax
        lda kL
        jsr PtrAt               ; pp = &ptrs[j - gap]
        ldy #0
        lda (pp),y
        sta ka
        iny
        lda (pp),y
        sta ka+1
        lda tL
        sta kb
        lda tH
        sta kb+1
        jsr Compare             ; (C set: ka > kb)
        bcc @put
        lda jL                  ; ptrs[j] = ptrs[j - gap]
        ldx jH
        jsr PtrAt
        ldy #0
        lda ka
        sta (pp),y
        iny
        lda ka+1
        sta (pp),y
        lda kL                  ; j -= gap
        sta jL
        lda kH
        sta jH
        jmp @j
@put:   lda jL                  ; ptrs[j] = t
        ldx jH
        jsr PtrAt
        ldy #0
        lda tL
        sta (pp),y
        iny
        lda tH
        sta (pp),y
        inc iL
        bne :+
        inc iH
:       jmp @i
@next:  ldx gapAt
        inx
        jmp @gap
@end:   rts

; PtrAt: pp = &ptrs[A/X].
PtrAt:  sta pp
        stx pp+1
        asl pp
        rol pp+1
        lda pp
        clc
        adc #<ptrs
        sta pp
        lda pp+1
        adc #>ptrs
        sta pp+1
        rts

; Compare: C set when the key at ka sorts after the key at kb (ties:
; C clear, so the pass keeps disk order).
Compare:
        ldy #0
@b:     lda (kb),y
        cmp (ka),y              ; (C clear: kb < ka at the first difference)
        bne @diff
        iny
        cpy #KEY_LEN
        bcc @b
        clc
        rts
@diff:  bcc :+
        clc
        rts
:       sec
        rts

; Permute: the REU table in the order of ptrs: entry j becomes the entry
; that was at Index(ptrs[j]), along each cycle (the first entry of a
; cycle kept in held while the others move up one by one).
Permute:
        ldx #VISIT_LEN - 1
        lda #0
@clr:   sta visited,x
        dex
        bpl @clr
        sta pL
        sta pH
@p:     lda pL                  ; p < count
        cmp count
        lda pH
        sbc count+1
        bcs @end
        lda pL
        ldx pH
        jsr Seen
        bne @nextp              ; (moved already)
        lda pL                  ; held = entry p
        ldx pH
        jsr Fetch
        ldx #ENTRY_BYTES - 1
@hold:  lda entryInfo,x
        sta held,x
        dex
        bpl @hold
        lda pL                  ; j = p
        sta jL
        lda pH
        sta jH
@chain: lda jL
        ldx jH
        jsr Mark
        lda jL                  ; o = where entry j comes from
        ldx jH
        jsr Index
        cmp pL
        bne @move
        cpx pH
        bne @move
        ldx #ENTRY_BYTES - 1    ; the cycle closed: held into j
@back:  lda held,x
        sta entryInfo,x
        dex
        bpl @back
        jsr StashJ
        jmp @nextp
@move:  sta oL                  ; entry o into j, then on from o
        stx oH
        jsr Fetch
        jsr StashJ
        lda oL
        sta jL
        lda oH
        sta jH
        jmp @chain
@nextp: inc pL
        bne :+
        inc pH
:       jmp @p
@end:   rts

; StashJ: entryInfo/entryName into the table's place j.
StashJ: lda jL
        ldx jH
        jsr Place
        jmp StashRAM

; Index: A/X = the entry number of the key ptrs[A/X] points to
; ((pointer - text) / KEY_LEN).
Index:  jsr PtrAt
        ldy #0
        lda (pp),y
        sec
        sbc #<text
        sta kL
        iny
        lda (pp),y
        sbc #>text
        ldx #3                  ; / 8
@sh:    lsr a
        ror kL
        dex
        bne @sh
        tax
        lda kL
        rts
        .assert KEY_LEN = 8, error, "Index: / 8"

; Seen: Z clear when entry A/X was moved. Mark: it is now.
Seen:   jsr BitOf
        and visited,x
        rts
Mark:   jsr BitOf
        ora visited,x
        sta visited,x
        rts

; BitOf: X = A/X's byte in visited, A = its bit.
BitOf:  sta kL
        stx kH
        and #7
        tay
        lda #1
@b:     dey
        bmi :+
        asl a
        bne @b
:       pha
        lsr kH
        ror kL
        lsr kH
        ror kL
        lsr kH
        ror kL
        ldx kL
        pla
        rts

; Ciura's gaps (and 1), below SORT_MAX; 0 ends the table.
GapLo:  .byte <301, <132, 57, 23, 10, 4, 1, 0
GapHi:  .byte >301, >132, 0, 0, 0, 0, 0, 0

VISIT_LEN       = (SORT_MAX + 7) / 8

; Scratch (overlay data: fetched anew with the overlay)
iL:     .byte 0
iH:     .byte 0
jL:     .byte 0
jH:     .byte 0
kL:     .byte 0
kH:     .byte 0
pL:     .byte 0
pH:     .byte 0
oL:     .byte 0
oH:     .byte 0
tL:     .byte 0
tH:     .byte 0
gapL:   .byte 0
gapH:   .byte 0
gapAt:  .byte 0
grp:    .byte 0
visited:        .res VISIT_LEN
held:           .res ENTRY_BYTES
ptrs:           .res SORT_MAX * 2
