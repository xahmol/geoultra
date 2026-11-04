; File engine: info blocks (engine.inc, "Info block") for FE_STAT and
; FE_READDIR. Assembled into each module that needs it: an overlay module
; cannot call another's code.

; FillInfo: r5 = a directory entry (its CBM type byte first): feInfo.
; Destroys A, X, Y.
FillInfo:
        lda #0
        jsr InfoKind
        ldy #0
        lda (r5),y
        sta feInfo + FI_CBM
        asl                     ; bit 6, locked, to FF_READONLY (bit 0 of
        asl                     ; the cleared flags)
        rol feInfo + FI_FLAGS
        ldy #OFF_SIZE
        lda (r5),y
        sta feInfo + FI_SIZE
        iny
        lda (r5),y
        sta feInfo + FI_SIZE + 1
        ldx #FE_K_FOLDER
        lda feInfo + FI_CBM
        and #$07
        cmp #5                  ; (1581 partition)
        beq @kind
        cmp #6                  ; (native folder)
        beq @kind
        ldx #FE_K_CBM
        ldy #OFF_GHDR_PTR       ; no header: a plain CBM file
        lda (r5),y
        beq @kind
        lda feInfo + FI_FLAGS
        ora #FF_GEOS
        sta feInfo + FI_FLAGS
        ldy #OFF_GSTRUC_TYPE    ; structure, type, date: GEOS files only
        lda (r5),y
        sta feInfo + FI_STRUCT
        iny
        lda (r5),y
        sta feInfo + FI_GTYPE
        ldx #0
@date:  iny
        lda (r5),y
        sta feInfo + FI_DATE,x
        inx
        cpx #5
        bne @date
        ldx #FE_K_GEOS
@kind:  stx feInfo + FI_KIND
        rts
        .assert OFF_GSTRUC_TYPE + 1 = OFF_GFILE_TYPE, error, "FillInfo: entry layout"
        .assert FF_READONLY = 1, error, "FillInfo: FF_READONLY from the carry"

; InfoKind: feInfo cleared, of kind A. Destroys X.
InfoKind:
        pha
        lda #0
        ldx #FE_INFO_LEN - 1
@zero:  sta feInfo,x
        dex
        bpl @zero
        pla
        sta feInfo + FI_KIND
        rts

; PutInfo: feInfo to the caller's info block (r1 at the call). X = 0.
; Destroys A, Y, r1.
PutInfo:
        lda argR1
        sta r1L
        lda argR1+1
        sta r1H
        ldy #FE_INFO_LEN - 1
@copy:  lda feInfo,y
        sta (r1),y
        dey
        bpl @copy
        ldx #0
        rts
