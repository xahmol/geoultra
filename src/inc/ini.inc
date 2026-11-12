; INI text in memory (docs/SETTINGS.md, "Structure"): find, set and
; delete a key in a section of SETTINGS.INI, MOUNTS.INI or a theme file
; held whole in a buffer. Shared code, own design; reading and writing
; the file are the includer's (they differ per program). Lines end in
; CR, LF or CR LF (all three are read; added lines get CR LF); section
; and key names match in any case (ASCII); "key=value" without spaces
; around "=". Other lines, comments and blank lines are kept as they are.
;
; The includer defines INI_BUF (the buffer's address) and INI_MAX (the
; text's room: the buffer is INI_MAX + 1 bytes, the text always followed
; by a zero, which the scan relies on), includes geos.inc first and puts
; this include in a code segment; iniLen (the text's length) is the
; includer's to set after reading the file (with the zero after it) and
; to use when writing it. A key may stand in its section more than once
; (SETTINGS.INI's slow=): iniSkip, set before a call, passes over that
; many of its lines (each call sets it back to 0); $FF makes IniSet add
; a new line even when the key is there. Exports IniFind, IniSet,
; IniDel, iniLen, iniSkip. All three destroy A, X, Y, r0-r7.

        .export iniLen, iniSkip

        .pushseg
        .segment "BSS"
iniLen:         .res 2          ; the text's length (the includer's)
iniSkip:        .res 1          ; the key's lines to pass over (IniFind)
        .popseg

        .scope IniImpl          ; (its names stay its own: no clash with
                                ; the includer's)
MoveData        = $C17E         ; GEOS jump table

; IniFind: r0 = a section's name ("desktop", zero-ended, without the
; brackets), r1 = a key ("view", without "="). C clear: found, r2 = the
; value's first byte, A = its length (to the line's end, at most 255).
; C set: not there. Either way the places IniSet and IniDel need are
; kept (iniSect: the section found; iniIns: where a new line of it goes;
; iniLine, iniNext: the key's line and the next line's start).
IniFind:
        jsr Params
        lda #0
        sta iniSect
        sta inSect
        lda #<INI_BUF           ; iniIns: the text's end until a section
        clc                     ; is found
        adc iniLen
        sta iniIns
        lda #>INI_BUF
        adc iniLen+1
        sta iniIns+1
        lda #<INI_BUF           ; r5: the line's start
        sta r5L
        lda #>INI_BUF
        sta r5H
@line:  jsr AtEnd
        bcc :+
        lda #0                  ; (the text's end: not found; iniSkip
        sta iniSkip             ; back to 0)
        sec
        rts
:       lda r5L
        sta iniLine
        lda r5H
        sta iniLine+1
        ldy #0
        lda (r5),y
        cmp #'['
        bne @key
        jsr IsSection           ; a section: ours?           ; (inSect set or cleared)
        lda inSect
        beq @next
        inc iniSect             ; (found: new lines after its header for
        jsr NextLine            ; now)
        jsr Ins
        jmp @line
@key:   lda inSect
        beq @next
        jsr IsBlank             ; (a blank line: no new place after it)
        beq @next
        jsr IsKey               ; C clear: ours, r2 its value, A the length
        bcs @other
        ldx iniSkip             ; (one to pass over: as another line)
        beq @ours
        dec iniSkip
        bcc @other              ; (C clear from IsKey: always)
@ours:  pha
        jsr NextLine
        lda r5L
        sta iniNext
        lda r5H
        sta iniNext+1
        pla
        clc
        rts
@other: jsr NextLine            ; another line of the section: new lines
        jsr Ins                 ; after it
        jmp @line
@next:  jsr NextLine
        jmp @line

; Ins: iniIns = r5 (the next line's start).
Ins:    lda r5L
        sta iniIns
        lda r5H
        sta iniIns+1
        rts

; IniSet: r0 = the section, r1 = the key, r2 = the value (zero-ended,
; at most 200 characters). The key's value replaced, or "key=value" added
; as its section's last line (the section added at the text's end when
; missing). C set: the buffer is too small (nothing changed).
IniSet:
        lda r2L                 ; (the value: IniFind uses r2)
        sta valP
        lda r2H
        sta valP+1
        jsr IniFind
        bcs @add
        sta oldLen              ; replace: the old value's bytes out, the
        lda r2L                 ; new ones in
        sta at
        lda r2H
        sta at+1
        jsr ValLen
        sta newLen
        lda #0                  ; (room: newLen - oldLen more)
        sta n+1
        lda newLen
        sec
        sbc oldLen
        sta n
        bcs :+
        dec n+1
:       jsr Room
        bcc :+
        rts                     ; (too small: C set)
:       lda oldLen
        ldx #0
        jsr Cut                 ; (at, A/X bytes)
        lda newLen
        ldx valP
        ldy valP+1
        jmp Put                 ; (at: A bytes from X/Y; C clear)
@add:   lda #0                  ; the new line in lineBuf: key=value CR LF
        sta lineN
        lda keyP
        ldx keyP+1
        jsr Add
        lda #'='
        jsr AddCh
        lda valP
        ldx valP+1
        jsr Add
        jsr AddEnd
        lda iniSect
        bne @line
        lda #0                  ; a new section first: "[name]" CR LF at
        sta sectN               ; the text's end
        jsr SectLine            ; (sectBuf, sectN)
        lda lineN               ; room for both and a line end before
        clc
        adc sectN
        adc #2
        sta n
        lda #0
        sta n+1
        jsr Room
        bcs @end
        jsr EndText             ; at = the text's end, a line end added
        lda sectN               ; when the last line has none
        ldx #<sectBuf
        ldy #>sectBuf
        jsr Put
        jmp @put
@line:  lda lineN               ; in the section: at iniIns
        clc
        adc #2
        sta n
        lda #0
        sta n+1
        jsr Room
        bcs @end
        lda iniIns
        sta at
        lda iniIns+1
        sta at+1
        jsr LineEnd             ; (at the text's end: its last line ended)
@put:   lda lineN
        ldx #<lineBuf
        ldy #>lineBuf
        jmp Put
@end:   rts

; IniDel: r0 = the section, r1 = the key: its line taken out (with its
; line end). C set: there was none.
IniDel: jsr IniFind
        bcs @end
        lda iniLine
        sta at
        lda iniLine+1
        sta at+1
        lda iniNext             ; its bytes: iniNext - iniLine
        sec
        sbc iniLine
        pha
        lda iniNext+1
        sbc iniLine+1
        tax
        pla
        jsr Cut
        clc
@end:   rts

; --- the scan

; Params: the section and key pointers kept (r0, r1).
Params: lda r0L
        sta sectP
        lda r0H
        sta sectP+1
        lda r1L
        sta keyP
        lda r1H
        sta keyP+1
        rts

; AtEnd: C set when r5 is at the text's end.
AtEnd:  lda r5L
        sec
        sbc #<INI_BUF
        tax
        lda r5H
        sbc #>INI_BUF
        cmp iniLen+1
        bne @cmp
        cpx iniLen
@cmp:   rts                     ; (C set: r5 - INI_BUF >= iniLen)

; NextLine: r5 = the next line's start (past one CR, LF or CR LF), or
; the text's end.
NextLine:
@ch:    jsr AtEnd
        bcs @end
        ldy #0
        lda (r5),y
        jsr Step
        cmp #CR
        beq @cr
        cmp #LF
        bne @ch
        rts
@cr:    jsr AtEnd               ; (CR LF: the LF too)
        bcs @end
        ldy #0
        lda (r5),y
        cmp #LF
        bne @end
        jsr Step
@end:   rts

; Step: r5 one on (A kept).
Step:   inc r5L
        bne :+
        inc r5H
:       rts

; IsBlank: Z set when the line at r5 is empty (it starts with its end).
IsBlank:
        jsr AtEnd
        bcs @yes
        ldy #0
        lda (r5),y
        cmp #CR
        beq @yes
        cmp #LF
@yes:   rts

; IsSection: inSect = 1 when the line at r5 is "[" the section "]",
; else 0.
IsSection:
        lda #0
        sta inSect
        lda sectP
        sta r6L
        lda sectP+1
        sta r6H
        ldy #1                  ; (past "[")
        jsr Same                ; the name, any case (Y on)
        bcs @no
        lda (r5),y
        cmp #']'
        bne @no
        inc inSect
@no:    rts

; IsKey: C clear when the line at r5 is the key "=": r2 = its value, A
; its length (to the line's end, at most 255).
IsKey:  lda keyP
        sta r6L
        lda keyP+1
        sta r6H
        ldy #0
        jsr Same
        bcs @no
        lda (r5),y
        cmp #'='
        bne @no
        iny                     ; r2 = the value
        tya
        clc
        adc r5L
        sta r2L
        lda r5H
        adc #0
        sta r2H
        ldx #0                  ; its length: to CR, LF or the text's end
@len:   txa
        clc
        adc r2L
        sta r7L
        lda r2H
        adc #0
        sta r7H
        lda r7L                 ; (the text's end?)
        sec
        sbc #<INI_BUF
        sta r4L
        lda r7H
        sbc #>INI_BUF
        cmp iniLen+1
        bne :+
        lda r4L
        cmp iniLen
:       bcs @got
        ldy #0
        lda (r7),y
        cmp #CR
        beq @got
        cmp #LF
        beq @got
        inx
        bne @len
        dex                     ; (255 at most)
@got:   txa
        clc
        rts
@no:    sec
        rts

; Same: C clear when the zero-ended name at r6 matches the text at r5
; from Y on (any case), Y then past it; C set when not. The text's end
; counts as a mismatch.
Same:   sty r4H                 ; (r4H: the text's offset, r4L: the name's)
        lda #0
        sta r4L
@ch:    ldy r4L
        lda (r6),y
        beq @yes
        jsr Lower
        sta r7L
        ldy r4H
        lda (r5),y
        jsr Lower
        cmp r7L
        bne @no
        inc r4L
        inc r4H
        bne @ch
@no:    sec
        rts
@yes:   ldy r4H
        clc
        rts

; Lower: A in lower case (ASCII A-Z).
Lower:  cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       rts

; --- changing the text

; ValLen: A = the value's length at valP (to its zero, at most 200).
ValLen: ldy #0
        lda valP
        sta r6L
        lda valP+1
        sta r6H
@ch:    lda (r6),y
        beq @end
        iny
        cpy #INI_VAL_MAX
        bcc @ch
@end:   tya
        rts

; Room: C set when n more bytes (a signed word) do not fit in INI_MAX.
Room:   lda iniLen
        clc
        adc n
        tax
        lda iniLen+1
        adc n+1
        cmp #>INI_MAX
        bne :+
        cpx #<INI_MAX
:       beq @fits               ; (equal: fits)
        rts                     ; (C: more than INI_MAX)
@fits:  clc
        rts

; Cut: A/X bytes taken out at at (the rest moved down, iniLen less).
Cut:    sta r2L
        stx r2H
        ora r2H
        beq @end
        lda at                  ; r0 = at + count: the rest's start
        clc
        adc r2L
        sta r0L
        lda at+1
        adc r2H
        sta r0H
        lda r2L                 ; (the count, while Tail takes r2)
        pha
        lda r2H
        pha
        jsr Tail                ; r2 = the rest from r0, with the zero
        pla
        tax
        pla
        pha
        txa
        pha
        lda at
        sta r1L
        lda at+1
        sta r1H
        jsr Move
        pla                     ; iniLen -= count
        sta n+1
        pla
        sta n
        lda iniLen
        sec
        sbc n
        sta iniLen
        lda iniLen+1
        sbc n+1
        sta iniLen+1
@end:   rts

; Put: A bytes from X/Y inserted at at (the rest moved up, iniLen more);
; at then after them. C clear.
Put:    sta count
        stx srcP
        sty srcP+1
        lda count
        beq @done
        lda at                  ; the rest from at moved up by count
        sta r0L
        lda at+1
        sta r0H
        jsr Tail                ; (its length before iniLen grows)
        lda at
        clc
        adc count
        sta r1L
        lda at+1
        adc #0
        sta r1H
        jsr Move
        lda iniLen
        clc
        adc count
        sta iniLen
        bcc :+
        inc iniLen+1
:       lda srcP                ; the bytes in
        sta r6L
        lda srcP+1
        sta r6H
        lda at
        sta r7L
        lda at+1
        sta r7H
        ldy #0
@b:     lda (r6),y
        sta (r7),y
        iny
        cpy count
        bne @b
        tya
        clc
        adc at
        sta at
        bcc @done
        inc at+1
@done:  clc
        rts

; Tail: r2 = the bytes from r0 to the text's end and its zero.
Tail:   lda #<INI_BUF
        sec                     ; (+ 1: the zero)
        adc iniLen
        sta r2L
        lda #>INI_BUF
        adc iniLen+1
        sta r2H
        lda r2L
        sec
        sbc r0L
        sta r2L
        lda r2H
        sbc r0H
        sta r2H
        rts

; Move: MoveData (r0 to r1, r2 bytes; any overlap), nothing for 0.
Move:   lda r2L
        ora r2H
        beq :+
        jmp MoveData
:       rts

; EndText: at = the text's end; a CR LF added first when the last line
; has no end (or nothing when the text is empty).
EndText:
        lda #<INI_BUF
        clc
        adc iniLen
        sta at
        lda #>INI_BUF
        adc iniLen+1
        sta at+1
; LineEnd: at the text's end after a line without its end: CR LF put
; there first.
LineEnd:
        lda at                  ; at the text's end?
        sec
        sbc #<INI_BUF
        tax
        lda at+1
        sbc #>INI_BUF
        cmp iniLen+1
        bne @end
        cpx iniLen
        bne @end
        txa                     ; (an empty text: nothing before)
        ora iniLen+1
        beq @end
        lda at                  ; the byte before
        sec
        sbc #1
        sta r6L
        lda at+1
        sbc #0
        sta r6H
        ldy #0
        lda (r6),y
        cmp #CR
        beq @end
        cmp #LF
        beq @end
        lda #2
        ldx #<CrLf
        ldy #>CrLf
        jmp Put
@end:   rts

; Add: the zero-ended text at A/X to lineBuf (lineN on). AddCh: A.
; AddEnd: CR LF.
Add:    sta r6L
        stx r6H
        ldy #0
@ch:    lda (r6),y
        beq @end
        jsr AddCh
        iny
        cpy #INI_VAL_MAX
        bcc @ch
@end:   rts
AddCh:  ldx lineN
        cpx #INI_LINE_MAX
        bcs :+
        sta lineBuf,x
        inc lineN
:       rts
AddEnd: lda #CR
        jsr AddCh
        lda #LF
        jmp AddCh

; SectLine: "[" the section "]" CR LF in sectBuf (sectN its length).
SectLine:
        ldx #0
        lda #'['
        sta sectBuf
        inx
        lda sectP
        sta r6L
        lda sectP+1
        sta r6H
        ldy #0
@ch:    lda (r6),y
        beq @close
        sta sectBuf,x
        inx
        iny
        cpx #INI_SECT_MAX - 3
        bcc @ch
@close: lda #']'
        sta sectBuf,x
        inx
        lda #CR
        sta sectBuf,x
        inx
        lda #LF
        sta sectBuf,x
        inx
        stx sectN
        rts

CrLf:   .byte CR, LF

INI_VAL_MAX     = 200           ; a value's characters, at most
INI_LINE_MAX    = 250           ; a new line (key, "=", value, CR LF)
INI_SECT_MAX    = 40            ; a new section's line

        .pushseg
        .segment "BSS"
iniSect:        .res 1          ; IniFind: the section was found
iniIns:         .res 2          ; IniFind: where a new line goes
iniLine:        .res 2          ; IniFind: the key's line
iniNext:        .res 2          ; and the next line's start
inSect:         .res 1
sectP:          .res 2
keyP:           .res 2
valP:           .res 2
srcP:           .res 2
at:             .res 2          ; a place in the text (Cut, Put)
n:              .res 2          ; Room: bytes more (signed)
count:          .res 1
oldLen:         .res 1
newLen:         .res 1
lineN:          .res 1
sectN:          .res 1
lineBuf:        .res INI_LINE_MAX
sectBuf:        .res INI_SECT_MAX
        .popseg

        .endscope
IniFind = IniImpl::IniFind     ; (the routines, outside the scope)
IniSet = IniImpl::IniSet
IniDel = IniImpl::IniDel
        .export IniFind, IniSet, IniDel
