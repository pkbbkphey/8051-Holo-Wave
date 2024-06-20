;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;; RECEIVER SIDE (旋轉LED) ;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; NOTICE : This code is dedicated
;   for STC 15F2K32S2 micro controller

; ===== DATA MEMORY DISTRIBUTION =====
;  ADDRESS       FUNCTION
; 000H~007H     registers
; 008H~01FH     stack
; 020H~07FH
; 080H~0FFH     存過去音訊資料(128筆)
; ====================================

; ===== PIN DEFINITION =====
P4          EQU 0C0H
; ==========================

; ===== VARIABLES USED =====
TEMP        EQU R2  ; 臨時使用的變數
TEMP1       EQU R3
OPTR        EQU R0  ; OLD DATA POINTER
OPTR_       EQU 00H ; OLD DATA POINTER
NPTR        EQU R1  ; NEW DATA POINTER
; ==========================

ORG 0000H
AJMP SETTING

ORG 0003H   ; INT0中斷向量
AJMP ROTATION_INT

ORG 0023H   ; 串列傳輸中斷向量
AJMP SERIAL_INT

ORG 0050H
SETTING:
    ; STC-15F2K32S2與MCS-51預設狀態不同，啟用串列傳輸的方式如下：
    ANL 0A2H,#00111111B ; UART1使用P3.0及P3.1
    ; CLR S1_S0
    ; CLR S1_S1

    ANL 097H,#11101111B ; UART1 works on normal mode
    ; CLR Tx_Rx

    ANL 08EH,#11011110B ; The clock source of Timer 1 is SYSclk/12.
                        ; Select Timer 1 as the baud-rate generator of UART1
    ; Datasheet P.560 提到 "UART1 prefer to select Timer 2 as its 
    ; baud-rate generator..." 可知預設為T2，若直接使用T1是行不通的

    MOV TMOD,#00100000B ; set timer 1 as mode 2 (8-bit auto reload)
    MOV TL1,#0FAH   ; timer1作為baud rate generator，
    MOV TH1,#0FAH	; 且 baud rate = 12000
    ORL PCON,#80H   ; SMOD = 1 (timer1頻率除以二)
    SETB TR1        ; timer 1 run

    SETB ES		; enable串列傳輸中斷
    SETB PS   ; 串列傳輸中斷優先
    CLR TI      ; 清空串列傳輸中斷旗標
    CLR RI      ; 清空串列傳輸中斷旗標

    SETB EX0    ; enable INT0
    SETB IT0    ; INT0設為負緣觸發
    CLR IE0     ; 清空INT0中斷旗標

    SETB EA

    CLR SM2     ; 不使用一對多模式
    SETB SM1    ; 串列傳輸 mode 1
    CLR SM0     ; 串列傳輸 mode 1

    SETB REN    ; receive enable

    MOV NPTR,#080H  ; 新資料指標指向聲音Array的第一筆

LOOP:
    AJMP LOOP

; ================ SOME FUNCTIONS ================
DISPLAY_OPTR:   ; 利用外圍的LED顯示過往的128筆聲音資料
    CLR A
    MOV A,@OPTR
    ANL A,#00111100B    ; 以OPTR指向的資料的.5~.2作為Index
    RR A
    RR A
    MOV B,#2
    MUL AB
    MOV TEMP,A

    MOV DPTR,#MAGNI_VISUALIZE

    MOVC A,@A+DPTR      ; 取第一筆資料
    MOV P2,A
    MOV A,TEMP
    INC A
    MOVC A,@A+DPTR      ; 取下一筆資料
    MOV P4,A

    RET

DISPLAY_NPTR_INNER: ; 利用內圈的LED顯示當前的聲音強度
    CLR A
    MOV A,@NPTR
    ANL A,#00111100B    ; 以NPTR指向的資料的.5~.2作為Index
    RR A
    RR A
    MOV B,#2
    MUL AB
    MOV TEMP,A

    MOV DPTR,#MAGNI_VISUALIZE

    MOVC A,@A+DPTR      ; 取第一筆資料
    MOV P0,A
    MOV A,TEMP
    INC A
    MOVC A,@A+DPTR      ; 取下一筆資料
    MOV P1,A
    RET

DELAY: 
    MOV R7,#7
DELAY1: 
    MOV R6,#45
DELAY2: 
    DJNZ R6,DELAY2 
    DJNZ R7,DELAY1 
    RET

; ============== INTERRUPT FUNCTIONS =============
SERIAL_INT:     ; 串列傳輸的中斷副程式
    CJNE NPTR,#0FFH,INC_NPTR    ; 使NPTR的值在#080H~#0FFH之間循環
    MOV NPTR,#080H
    SJMP INSERT_NEW
    INC_NPTR:
    INC NPTR

    INSERT_NEW:     ; 在當前NPTR指向的位置放入接收到的聲音強度資料
    MOV @NPTR,SBUF

    ACALL DISPLAY_NPTR_INNER    ; 將當前聲音強度顯示在旋轉LED內圈

    CLR TI
    CLR RI

    RETI

ROTATION_INT:
    MOV A,NPTR  ; 取樣NPTR
    MOV OPTR,A
    INC OPTR    ; 從最舊的資料開始顯示()

    MOV TEMP1,#128  ; 限制螢幕寬為 128 pixels

    DISPLAY_LOOP:
        CJNE OPTR,#0FFH,INC_OPTR    ; 限制OPTR的值在#080H~#0FFH之間
        MOV OPTR,#080H
        SJMP CALL_DISPLAY_OPTR
        INC_OPTR:
        INC OPTR
        CALL_DISPLAY_OPTR:
        ACALL DISPLAY_OPTR  ; 將過去128筆聲音資料顯示在旋轉LED外圍
        ACALL DELAY
    DJNZ TEMP1,DISPLAY_LOOP ; 限制此LOOP指執行128次

    RETI

; ==================== TABLES ====================
MAGNI_VISUALIZE:    ; 每個聲音強度所對應的LED圖樣
    DB 11111111B, 01111111B
    DB 11111111B, 00111111B
    DB 11111111B, 00011111B
    DB 11111111B, 00001111B
    DB 11111111B, 00000111B
    DB 11111111B, 00000011B
    DB 11111111B, 00000001B
    DB 11111111B, 00000000B

    DB 01111111B, 00000000B
    DB 00111111B, 00000000B
    DB 00011111B, 00000000B
    DB 00001111B, 00000000B
    DB 00000111B, 00000000B
    DB 00000011B, 00000000B
    DB 00000001B, 00000000B
    DB 00000000B, 00000000B
