; GeoUltra Desktop: the 8 x 8 icons (docs/DESKTOP.md, "Look and
; themes", step D7a), own drawings from the approved mock-up
; (2026-11-06): an entry's kind in the list, the sidebar's drives,
; Ultimate roots, favourites and recent documents, the open drive's
; arrow and the scroll strip's arrows. Each is a GEOS compacted bitmap
; (one unique packet of 8 bytes) for BitmapUp, so it sits on a card.

        .include "geos.inc"
        .include "desktop.inc"

        .import entryInfo, entryName, IsImage
        .export IconUp, IconFor

FONT            = 8             ; GEOS file type
ICON_BYTES      = 9             ; the packet's count byte and 8 rows

        .segment "CODE"

; IconUp: icon A drawn at card X, pixel row Y (both screens, as
; dispBufferOn says). Destroys A, X, Y, r0-r2 and BitmapUp's.
IconUp: stx r1L
        sty r1H
        sta r0L                 ; Icons + A * ICON_BYTES
        asl a
        asl a
        asl a
        clc
        adc r0L
        clc
        adc #<Icons
        sta r0L
        lda #0
        adc #>Icons
        sta r0H
        lda #1
        sta r2L
        lda #8
        sta r2H
        jmp BitmapUp

; IconFor: A = the icon for the entry in entryInfo/entryName.
IconFor:
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq @folder
        cmp #K_UDIR
        beq @folder
        cmp #K_DRIVE
        beq @drive
        cmp #K_UFILE
        beq @ufile
        cmp #K_GEOS
        bne @file
        lda entryInfo + FI_GTYPE
        cmp #APPLICATION
        beq @app
        cmp #AUTO_EXEC
        beq @app
        cmp #DESK_ACC
        beq @da
        cmp #FONT
        beq @font
        lda #IC_DOC
        rts
@folder:
        lda #IC_FOLDER
        rts
@drive: lda #IC_DRIVE
        rts
@ufile: jsr IsImage             ; (mount.s: a disk image by its name)
        bcs @file
        lda #IC_IMAGE
        rts
@app:   lda #IC_APP
        rts
@da:    lda #IC_DA
        rts
@font:  lda #IC_FONT
        rts
@file:  lda #IC_FILE
        rts

; The icons, rows top to bottom, bit 7 left (the mock-up's drawings).
Icons:  .byte $88, $00, $70, $8F, $81, $81, $81, $FF, $00     ; folder
        .byte $88, $7E, $81, $FF, $81, $A5, $81, $7E, $00     ; application
        .byte $88, $7C, $46, $5F, $41, $5D, $41, $7F, $00     ; document
        .byte $88, $3C, $42, $A5, $81, $BD, $42, $3C, $00     ; desk accessory
        .byte $88, $7E, $5A, $18, $18, $18, $18, $3C, $00     ; font
        .byte $88, $7E, $81, $99, $BD, $99, $81, $7E, $00     ; disk image
        .byte $88, $7C, $44, $46, $42, $42, $42, $7E, $00     ; other file
        .byte $88, $00, $FF, $81, $99, $81, $FF, $00, $00     ; drive
        .byte $88, $00, $FF, $AB, $AB, $AB, $FF, $24, $00     ; native drive
        .byte $88, $18, $3C, $3C, $7E, $7E, $7E, $7E, $00     ; usb
        .byte $88, $3E, $42, $82, $82, $82, $82, $FE, $00     ; sd
        .byte $88, $00, $20, $30, $38, $30, $20, $00, $00     ; the open drive
        .byte $88, $00, $10, $38, $7C, $10, $10, $00, $00     ; scroll up
        .byte $88, $00, $10, $10, $7C, $38, $10, $00, $00     ; scroll down
