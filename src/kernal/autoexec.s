; Auto-exec files at the cold start (the user's decisions of 2026-11-14;
; docs/DESIGN.md): SETTINGS.INI [system] autoexec=/a/CONFIGURE
; lines (a path with its drive and folder), run in that order at a fresh
; cold start only (not after a resumed session: HibResume does not
; return then), skipped while SHIFT is held (C= is the resume's own key:
; a fresh start with the auto-execs). As GEOS 2.0's boot (HG2G): each
; is started with GetFile (LdApplic) with firstBoot FALSE and ends with
; EnterDeskTop, which continues with the next one (module 0,
; OvEnterDeskTop, calls AutoNext first); after the last one firstBoot is
; TRUE and the desktop starts. The list is kept in REU bank 1 at
; AUTO_LIST (AUTO_MAX paths of AUTO_LEN bytes, an empty one after the
; last), autoIdx (resident, sysdrive.s) the next one ($FF: none
; running). Modules 92 and 93 (the file read). Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import SysRAMOp, autoIdx, FileEngine, GetFile, OvlCall

firstBoot       = $88C5         ; GEOS: FALSE while the boot runs auto-execs
AUTO_LIST       = $1C00         ; REU bank 1: the list (free up to $1FFF)
AUTO_LEN        = 64            ; a path and its zero
AUTO_MAX        = 8
TEXT            = $4000         ; SETTINGS.INI's text at the cold start
TEXT_MAX        = $0C00         ; (free then: mount.s's buffers)
APP_RAM         = $0400         ; a path and a short name while one starts
SHORT           = APP_RAM + AUTO_LEN

        .segment "OVL92"
        .scope Mod92

        jmp AutoStart           ; entry 0 (the cold start, init.s)
        jmp AutoNext            ; entry 3 (module 0, OvEnterDeskTop)

ReadIni:
        jsr OvlCall             ; (module 93: SETTINGS.INI into TEXT)
        .byte 93, 0

; AutoStart (the cold start's end, a fresh start): firstBoot TRUE; unless
; SHIFT is held, SETTINGS.INI's autoexec= paths to the list, and with
; one or more autoIdx 0 and firstBoot FALSE (EnterDeskTop starts them).
AutoStart:
        lda #$FF
        sta autoIdx
        sta firstBoot
        lda CPU_PORT            ; SHIFT held (either): none (C= is the
        pha                     ; resume's key; the user, 2026-11-14)
        lda #RAM_IO
        sta CPU_PORT
        ldx #0                  ; (X: the SHIFT keys held)
        lda #$FD                ; left SHIFT: column 1, row bit 7
        sta $DC00
        lda $DC01
        bmi :+
        inx
:       lda #$BF                ; right SHIFT: column 6, row bit 4
        sta $DC00
        lda $DC01
        and #$10
        bne :+
        inx
:       lda #$FF
        sta $DC00
        pla
        sta CPU_PORT
        txa
        bne @end
        jsr ReadIni
        bcs @end
        jsr Parse
        lda count
        beq @end
        cmp #AUTO_MAX           ; (an empty entry after the last one)
        bcs :+
        lda #0
        sta APP_RAM
        lda #REU_STASH
        jsr ListOp
:       lda #0
        sta autoIdx
        sta firstBoot
@end:   rts

; Parse: the [system] section's autoexec= lines (keys in any case) to the
; list in their order, count of them (AUTO_MAX at most; a path longer
; than AUTO_LEN - 1 left out).
Parse:  lda #0
        sta count
        sta inSys
        lda #<TEXT
        sta r0L
        lda #>TEXT
        sta r0H
@line:  ldy #0
        lda (r0),y
        bne :+
        rts
:       cmp #'['
        bne @key
        ldx #SysKey - Keys      ; "[system]"
        jsr Match
        lda #0
        bcs :+
        lda #1
:       sta inSys
        jmp @skip
@key:   lda inSys
        beq @skip
        ldx #AutoKey - Keys     ; "autoexec="
        jsr Match
        bcs @skip
        jsr Take                ; (Y at the value)
@skip:  ldy #0                  ; the line's end, then past its LF
@s:     lda (r0),y
        beq @next
        iny
        cmp #10
        bne @s
@next:  tya
        clc
        adc r0L
        sta r0L
        bcc @line
        inc r0H
        bne @line               ; (always)

; Match: C clear when the line at r0 starts with Keys + X (any case); Y
; after it.
Match:  ldy #0
@c:     lda Keys,x
        beq @yes
        lda (r0),y
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       cmp Keys,x
        bne @no
        inx
        iny
        bne @c
@yes:   clc
        rts
@no:    sec
        rts

; Take: the value at r0 + Y (to CR, LF or the end) as the list's next
; path (stashed at AUTO_LIST + count * AUTO_LEN).
Take:   lda count
        cmp #AUTO_MAX
        bcs @end
        ldx #0
@c:     lda (r0),y
        beq @put
        cmp #13
        beq @put
        cmp #10
        beq @put
        sta APP_RAM,x
        iny
        inx
        cpx #AUTO_LEN - 1
        bcc @c
        rts                     ; (too long: left out)
@put:   cpx #0
        beq @end
        lda #0
        sta APP_RAM,x
        lda r0L                 ; (Parse's place in the text: ListOp
        pha                     ; sets r0)
        lda r0H
        pha
        lda #REU_STASH
        jsr ListOp
        pla
        sta r0H
        pla
        sta r0L
        inc count
@end:   rts

; ListOp: A = REU command: APP_RAM <-> list entry count (AUTO_LEN bytes).
; Destroys A, X, Y, r0-r3L.
ListOp: tay
        lda count
        lsr a                   ; * 64: (count >> 2) high, (count << 6) low
        lsr a
        clc
        adc #>AUTO_LIST
        sta r1H
        lda count
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        sta r1L
        lda #<APP_RAM
        sta r0L
        lda #>APP_RAM
        sta r0H
        lda #AUTO_LEN
        sta r2L
        lda #0
        sta r2H
        lda #1                  ; (REU bank 1)
        sta r3L
        jmp SysRAMOp
        .assert <AUTO_LIST = 0 && AUTO_LEN = 64, error, "ListOp: whole pages, 64 a path"

; AutoNext (OvEnterDeskTop, before the desktop): while the list runs
; (autoIdx not $FF), its next path's drive and folder made current
; (FE_SELECT) and the file started (GetFile: it does not return); a
; path not found or a start that fails: the next. After the last one:
; autoIdx $FF, firstBoot TRUE, back (the desktop starts).
AutoNext:
        lda autoIdx
        cmp #AUTO_MAX
        bcs @done
        sta count
        inc autoIdx
        lda #REU_FETCH          ; its path to APP_RAM
        jsr ListOp
        lda APP_RAM
        beq @done               ; (the list's end: an empty entry)
        lda #<APP_RAM
        sta r0L
        lda #>APP_RAM
        sta r0H
        lda #<SHORT
        sta r1L
        lda #>SHORT
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne AutoNext            ; (not there: the next)
        lda #<SHORT
        sta r6L
        lda #>SHORT
        sta r6H
        lda #0
        sta r0L
        jsr GetFile             ; (an auto-exec: no return)
        jmp AutoNext            ; (it could not start: the next)
@done:  lda #$FF
        sta autoIdx
        sta firstBoot
        rts

Keys:
SysKey:         .byte "[system]", 0
AutoKey:        .byte "autoexec=", 0
count:          .byte 0
inSys:          .byte 0

        .endscope

        .segment "OVL93"
        .scope Mod93

        jmp ReadIni             ; entry 0 (module 92)

; ReadIni: SETTINGS.INI (the home folder's) into TEXT, zero-ended. C set
; when it cannot be read.
ReadIni:
        lda #<TEXT
        sta r1L
        lda #>TEXT
        sta r1H
        lda #0
        sta TEXT
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @fail
        ldx #$FF                ; + "SETTINGS.INI"
@e:     inx
        lda TEXT,x
        bne @e
        ldy #0
@n:     lda IniName,y
        sta TEXT,x
        beq @open
        inx
        iny
        bne @n
@open:  lda #<TEXT
        sta r0L
        lda #>TEXT
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        bne @fail
        lda #<TEXT
        sta r1L
        lda #>TEXT
        sta r1H
        lda #<(TEXT_MAX - 1)
        sta r2L
        lda #>(TEXT_MAX - 1)
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        stx tmp
        lda r2L                 ; the end: zero
        clc
        adc #<TEXT
        sta r0L
        lda r2H
        adc #>TEXT
        sta r0H
        ldy #0
        tya
        sta (r0),y
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda tmp
        bne @fail
        clc
        rts
@fail:  sec
        rts

IniName:        .byte "SETTINGS.INI", 0
handle:         .byte 0
tmp:            .byte 0

        .endscope
