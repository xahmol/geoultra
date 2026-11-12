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

        .import count, Fetch, Place, entryInfo, entryName, text, IsDotDot
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
        ldx #0
@ch:    lda entryName,x
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
        cpx #KEY_CHARS
        bcc @ch
        bcs @ptr
@pad:   iny                     ; (a short name: zeros after it)
        sta (kp),y
        cpy #KEY_CHARS
        bcc @pad
@ptr:   ldy #0                  ; ptrs[i] = this key
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
