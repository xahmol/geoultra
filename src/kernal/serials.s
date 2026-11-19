; GeoUltra kernal: serial numbers per application from SETTINGS.INI's
; [serials] (docs/design/DESIGN.md "Serial number": the user's decisions of
; 2026-11-19: keys are the class only, "geoWrite=58B5", any case,
; trailing spaces ignored; a change takes effect at once). The section
; is parsed into a table in REU bank SERIALS_BANK at SERIALS_AT (a
; count, then SERIALS_MAX entries of the class, 12 characters padded
; with spaces, and the serial, low byte first): at the cold start (mount.s
; module 122, from SETTINGS.INI's text) and by FE_SERIALS (Settings, on
; Save: its INI text). GetSerialNumber asks module 127 first: the
; running application's class (task.s taskName) against the table.
; This is not the bypass (bypass.s): the user lists the serial an
; application of theirs was installed under. Own code.

        .include "geos.inc"
        .include "engine.inc"
        .include "sysdrive.inc"
        .include "hw.inc"

CR_     = 13

        .import SysRAMOp, taskName, serialNumber, OvlCall

; Module scratch ($9F70-$9FFF: kept for the running module across the
; REU operations; overlay.s)
textAt          = $9F70         ; word: the text's next byte
textEnd2        = $9F72         ; word: its end
count           = $9F74
entry           = $9F75         ; SER_LEN bytes: an entry being built / read
name12          = entry         ; (its first 12 bytes)
inSect          = $9F84         ; $80: in [serials]
lineAt          = $9F85         ; word: the current line's start
keep            = $9F87

; ======================================================================

        .segment "OVL126"
        .scope Mod126

        jmp Parse               ; entry 0 (mount.s module 122: r2 = the
                                ; text, r3 = its end)
        jmp OvSerials           ; entry 3 (FE_SERIALS)

; OvSerials (FE_SERIALS, the file engine's dispatcher): r0 = an INI text,
; r1 = its length: its [serials] parsed into the table at once. X = 0.
; r1 = 0: the query instead (module 127 entry 6): the class of an
; application that refused to run since the last query.
OvSerials:
        lda argR1
        ora argR1+1
        bne :+
        jsr OvlCall             ; (a tail call)
        .byte 127, 6
:       lda argR0
        sta r2L
        clc
        adc argR1
        sta r3L
        lda argR0+1
        sta r2H
        adc argR1+1
        sta r3H
        jsr Parse
        ldx #0
        rts

; Parse: the [serials] section of the text r2..r3 (lines "class=hex",
; CR or LF between them; up to the next "[" line or the end) into the
; table: up to SERIALS_MAX entries, then the count. Lines without "=", a
; class longer than 12 characters or no hex digits are left out.
Parse:  lda r2L
        sta textAt
        lda r2H
        sta textAt+1
        lda r3L
        sta textEnd2
        lda r3H
        sta textEnd2+1
        lda #0
        sta count
        sta inSect
@line:  jsr AtEnd
        bcs @done
        jsr Byte                ; the line's first character
        cmp #'['
        bne @body
        jsr Section             ; inSect: "[serials]"?
        jmp @skip
@body:  bit inSect
        bpl @skip
        cmp #CR_
        beq @line
        cmp #LF
        beq @line
        jsr Back1               ; (the first character is the class's)
        jsr Entry               ; one entry, when the line is one
@skip:  jsr SkipLine
        jmp @line
@done:  lda #<count             ; the count, last
        ldx #>count
        ldy #0                  ; (at SERIALS_AT)
        jsr StashAt
        rts

; Section: inSect = $80 when the text after "[" is "serials]".
Section:
        ldx #0
@cmp:   jsr AtEnd
        bcs @no
        jsr Byte
        jsr Upper
        cmp SectName,x
        bne @no
        inx
        cpx #SECT_LEN
        bcc @cmp
        lda #$80
        sta inSect
        rts
@no:    lda #0
        sta inSect
        rts
SectName:       .byte "SERIALS]"
SECT_LEN        = * - SectName

; Entry: the line at textAt as "class=hex" into the next table entry
; (SERIALS_MAX at most).
Entry:  lda count
        cmp #SERIALS_MAX
        bcs @end
        ldx #11                 ; the class: spaces first
        lda #' '
:       sta name12,x
        dex
        bpl :-
        ldx #0
@name:  jsr AtEnd
        bcs @end
        jsr Byte
        cmp #'='
        beq @hex
        cmp #CR_
        beq @end
        cmp #LF
        beq @end
        cpx #12
        bcs @long
        sta name12,x
        inx
        bne @name
@long:  cmp #' '                ; (trailing spaces beyond 12: fine)
        beq @name
        rts                     ; (a class longer than 12: left out)
@hex:   txa
        beq @end                ; (no class)
        lda #0
        sta entry + 12
        sta entry + 13
        ldx #0                  ; digits read
@dig:   jsr AtEnd
        bcs @put
        jsr Byte
        jsr Hex
        bcs @back
        ldy #4                  ; serial = serial * 16 + digit
:       asl entry + 12
        rol entry + 13
        dey
        bne :-
        ora entry + 12
        sta entry + 12
        inx
        bne @dig
@back:  jsr Back1               ; (the line's end: SkipLine finds it)
@put:   txa
        beq @end                ; (no digits)
        lda count               ; the entry at SERIALS_AT + 1 + count * 14
        jsr EntryAddr
        lda #<entry
        ldx #>entry
        jsr Stash
        inc count
@end:   rts

; Hex: A as a hex digit (any case): C clear, A its value; else C set.
Hex:    jsr Upper
        cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcc @dec
        cmp #'A'
        bcc @no
        cmp #'F' + 1
        bcs @no
        sbc #'A' - 10 - 1       ; (carry clear here)
        clc
        rts
@dec:   sec
        sbc #'0'
        clc
        rts
@no:    sec
        rts

; Upper: A in upper case (ASCII letters). Keeps X, Y.
Upper:  cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        and #$DF
:       rts

; SkipLine: textAt past the line's end (CR, LF, or both).
SkipLine:
@to:    jsr AtEnd
        bcs @end
        jsr Byte
        cmp #CR_
        beq @eol
        cmp #LF
        bne @to
@eol:   jsr AtEnd               ; (a CR LF pair: both)
        bcs @end
        jsr Byte
        cmp #LF
        beq @end
        cmp #CR_
        beq @end
        jsr Back1
@end:   rts

; AtEnd: C set when textAt has reached textEnd2. Keeps X, Y.
AtEnd:  lda textAt
        cmp textEnd2
        lda textAt+1
        sbc textEnd2+1
        rts

; Byte: A = the text's next byte. Back1: one back. Keep X, Y.
Byte:   sty keep
        ldy #0
        lda textAt
        sta r0L
        lda textAt+1
        sta r0H
        lda (r0),y
        inc textAt
        bne :+
        inc textAt+1
:       ldy keep
        rts
Back1:  lda textAt
        bne :+
        dec textAt+1
:       dec textAt
        rts

; EntryAddr: r1 = SERIALS_AT + 1 + A * SER_LEN (A <= SERIALS_MAX).
EntryAddr:
        tax
        lda #<(SERIALS_AT + 1)
        sta r1L
        lda #>(SERIALS_AT + 1)
        sta r1H
@add:   dex
        bmi @end
        lda r1L
        clc
        adc #SER_LEN
        sta r1L
        bcc @add
        inc r1H
        bne @add
@end:   rts

; Stash: SER_LEN bytes at A/X to the REU at r1 (bank SERIALS_BANK).
; StashAt: 1 byte at A/X to SERIALS_AT + Y.
Stash:  sta r0L
        stx r0H
        lda #SER_LEN
        bne Op
StashAt:
        sta r0L
        stx r0H
        tya
        clc
        adc #<SERIALS_AT
        sta r1L
        lda #>SERIALS_AT
        adc #0
        sta r1H
        lda #1
Op:     sta r2L
        lda #0
        sta r2H
        lda #SERIALS_BANK
        sta r3L
        ldy #REU_STASH
        jmp SysRAMOp

        .endscope

; ======================================================================

        .segment "OVL127"
        .scope Mod127

        jmp Lookup              ; entry 0 (GetSerialNumber)
        jmp Refusal             ; entry 3 (dialog.s module 11, OvSaveState)
        jmp Query               ; entry 6 (FE_SERIALS with r1 = 0)

; Refusal (a dialog box starting: DBoxDesc its description; r-registers
; free, the state just saved): when one of its texts (DBTXTSTR) is a
; known refusal of the serial number (Refused below: fixed texts as
; Berkeley's applications show them; style codes before them skipped),
; the running application's class (taskName) is noted in the REU
; (SERIALS_REFUSED) for the desktop (the user's decision of 2026-11-19).
Refusal:
        lda taskName
        beq @end
        ldy #0                  ; the items after the position (as DoDlgBox)
        lda (DBoxDesc),y
        asl a
        ldy #7
        bcc @item
        ldy #1
@item:  cpy #$F0                ; (a stale description: the scan ends)
        bcs @end
        lda (DBoxDesc),y
        beq @end
        iny
        cmp #DBTXTSTR
        beq @text
        cmp #DBVARSTR
        beq @var
        and #$3F                ; (DBGETFILES' MegaPatch flags)
        tax
        cpx #ITEM_N
        bcs @end                ; (unknown: stop)
        tya
        clc
        adc ItemLen,x
        tay
        jmp @item
@var:   iny                     ; DBVARSTR: x, y, the register holding
        iny                     ; the text's address (geoWrite's showError)
        lda (DBoxDesc),y
        tax
        lda 0,x
        sta r0L
        lda 1,x
        jmp @look
@text:  iny                     ; DBTXTSTR: x, y, the text's address
        iny
        lda (DBoxDesc),y
        sta r0L
        iny
        lda (DBoxDesc),y
@look:  sta r0H
        iny
        sty at
        jsr Known
        ldy at
        bcs @item
        lda #<taskName          ; noted: its class
        ldx #>taskName
        ldy #REU_STASH
        jmp RefOp
@end:   rts

; Known: C clear when the text at r0 (style codes first skipped) starts
; with one of the refusal texts.
Known:  ldy #0
:       lda (r0),y
        beq @no
        cmp #$20
        bcs :+
        iny
        bne :-
:       sty r1L                 ; (its first character)
        ldx #0
@text:  ldy r1L
@cmp:   lda Refused,x
        beq @yes
        cmp (r0),y
        bne @next
        inx
        iny
        bne @cmp
@next:  lda Refused,x           ; the next refusal text
        beq :+
        inx
        bne @next
:       inx
        lda Refused,x
        bne @text
@no:    sec
        rts
@yes:   clc
        rts

; The refusal texts (each zero-ended; an empty one ends the list).
Refused:        .byte "Please reboot your system", 0  ; (geoWrite 2.1's: "...
                .byte 0                 ; using the same GEOS disk", mist64)
; The bytes after each command's code (GEOS's dialog commands 0-19).
ItemLen:        .byte 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 3, 4, 0, 2, 2, 2, 4, 2
ITEM_N          = * - ItemLen

; Query (FE_SERIALS with r1 = 0): the noted class to r0 (13 bytes) and
; cleared. X = 0, or FILE_NOT_FOUND when there was none.
Query:  lda argR0                ; straight into the caller's buffer
        ldx argR0+1
        ldy #REU_FETCH
        jsr RefOp
        ldx #FILE_NOT_FOUND
        ldy #0
        lda (r0),y
        beq @end
        lda #<ItemLen           ; cleared (ItemLen starts with a zero)
        ldx #>ItemLen
        ldy #REU_STASH
        jsr RefOp
        ldx #0
@end:   rts

; RefOp: Y the command, 13 bytes between A/X (low/high) and the REU's
; SERIALS_REFUSED (bank SERIALS_BANK). r0 = A/X afterwards.
RefOp:  sta r0L
        stx r0H
        lda #<SERIALS_REFUSED
        sta r1L
        lda #>SERIALS_REFUSED
        sta r1H
        lda #13
        sta r2L
        jmp FetchOp

Fetch:  ldy #REU_FETCH
FetchOp:
        lda #0
        sta r2H
        lda #SERIALS_BANK
        sta r3L
        jmp SysRAMOp

; Lookup: C clear and r0 = the serial listed in [serials] for the running
; application (taskName: its class, 12 characters; any case); else C set
; and r0 = the system's own (misc.s serialNumber: GetSerialNumber's
; default, here to save the resident kernal's bytes). Keeps X, Y.
Lookup: stx keepX
        sty keepY
        lda taskName            ; (no application named: nothing)
        beq @no
        lda #1                  ; the count
        sta r2L
        lda #<count
        sta r0L
        lda #>count
        sta r0H
        lda #<SERIALS_AT
        sta r1L
        lda #>SERIALS_AT
        sta r1H
        jsr Fetch
        lda count
        cmp #SERIALS_MAX + 1
        bcs @none               ; (no table yet: garbage)
        lda #0
        sta at
@each:  lda at
        cmp count
        bcs @none
        jsr Addr
        lda #<entry
        sta r0L
        lda #>entry
        sta r0H
        lda #SER_LEN
        sta r2L
        jsr Fetch
        jsr Same
        bcc @found
        inc at
        bne @each
@found: lda entry + 12
        sta r0L
        lda entry + 13
        sta r0H
        ldx keepX
        ldy keepY
        clc
        rts
@none:
@no:    lda serialNumber
        sta r0L
        lda serialNumber+1
        sta r0H
        ldx keepX
        ldy keepY
        sec
        rts

; Same: C clear when the entry's class is taskName's (12 characters,
; taskName padded with spaces after its end; letters in any case).
Same:   ldx #0
        ldy #0                  ; (Y: $80 once taskName has ended)
@cmp:   lda taskName,x
        bne :+
        ldy #$80
:       tya
        bpl :+
        lda #' '
        bne @c                  ; (always)
:       lda taskName,x
@c:     jsr Up
        sta keep
        lda name12,x
        jsr Up
        cmp keep
        bne @no
        inx
        cpx #12
        bcc @cmp
        clc
        rts
@no:    sec
        rts

; Up: A in upper case (ASCII letters).
Up:     cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        and #$DF
:       rts

; Addr: r1 = SERIALS_AT + 1 + at * SER_LEN.
Addr:   lda #<(SERIALS_AT + 1)
        sta r1L
        lda #>(SERIALS_AT + 1)
        sta r1H
        ldx at
@add:   dex
        bmi @end
        lda r1L
        clc
        adc #SER_LEN
        sta r1L
        bcc @add
        inc r1H
        bne @add
@end:   rts


keepX   = $9F88
keepY   = $9F89
at      = $9F8C

        .endscope
