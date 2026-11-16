; pdfa4, pdfletter: the PDF text GU PDF A4 and GU PDF Letter write
; (src/printer/pdf.s), as scripts (pdfscript.inc); data files on drive E
; that the driver reads into its work area for StartPrint and StopPrint
; (the driver's 1600 bytes did not hold them). Assembled at 0: two
; words, SImage's and SStop's offsets, then SFirst (which runs on into
; SImage), SImage, SStop. The image 8" x 9.4" = 576 x 676.8 points,
; centred: on A4 (595 x 842 points) at 9.5, 82.6; on Letter (LETTER
; defined: 612 x 792) at 18, 57.6. Own code, 2026-11-16.

        .include "pdfscript.inc"

        .segment "CODE"
        .word SImage, SStop
.ifdef LETTER
.define CONTENT "q 576 0 0 676.8 18 57.6 cm /I Do Q"
.define MEDIA "/MediaBox [0 0 612 792]"
.else
.define CONTENT "q 576 0 0 676.8 9.5 82.6 cm /I Do Q"
.define MEDIA "/MediaBox [0 0 595 842]"
.endif
SFirst: .byte "%PDF-1.4", 10, "%", $E2, $E3, $CF, $D3, 10
        .byte C_AT, V_CAT, "1 0 obj", 10, "<< /Type /Catalog /Pages 2 0 R >>", 10, "endobj", 10
SImage: .byte C_AT, V_IMG, C_OBJ, 0
        .byte "<< /Subtype /Image /Width 640 /Height 752 /ImageMask true"
        .byte " /Decode [1 0] /Length 60160 >>", 10, "stream", 10, 0
SStop:  .byte 10, "endstream", 10, "endobj", 10
        .byte C_AT, V_CONT, C_OBJ, 1, "<< /Length ", .sprintf("%d", .strlen(CONTENT))
        .byte " >>", 10, "stream", 10, CONTENT, 10, "endstream", 10, "endobj", 10
        .byte C_AT, V_PAGE, C_OBJ, 2, "<< /Type /Page /Parent 2 0 R ", MEDIA
        .byte " /Resources << /XObject << /I ", C_REF, 0, ">> >> /Contents ", C_REF, 1
        .byte ">>", 10, "endobj", 10
        .byte C_PAGE, 0
        .byte C_AT, V_TREE, "2 0 obj", 10, "<< /Type /Pages /Count ", C_NUM, V_PAGES
        .byte " /Kids [ ", C_KIDS, 0, "] >>", 10, "endobj", 10
        .byte C_AT, V_XREF, "xref", 10, C_SUB, 0
        .byte C_ENTRY, V_IMG, C_ENTRY, V_CONT, C_ENTRY, V_PAGE
        .byte "trailer", 10, "<< /Size ", C_ONUM, 3, " /Root 1 0 R", C_SUB, 4
        .byte " >>", 10, "startxref", 10, C_NUM, V_XREF, 10, "%%EOF", 10, 0
