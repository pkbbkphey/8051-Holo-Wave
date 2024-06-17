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
; NDATA       EQU R2  ; NEW DATA
; ==========================

ORG 0000H
AJMP SETTING

ORG 0003H  ; INT0
AJMP ROTATION_INT

ORG 0023H
AJMP SERIAL_INT

ORG 0050H
SETTING:
    ; CLR S1_S0
    ; CLR S1_S1
    ANL 0A2H,#00111111B
    ; CLR Tx_Rx
    ANL 097H,#11101111B

    ANL 08EH,#11011110B ; The clock source of Timer 1 is SYSclk/12.
                        ; Select Timer 1 as the baud-rate generator of UART1

    MOV TMOD,#00100000B ; set timer 1 as mode 2 (8-bit auto reload)
    MOV TL1,#0FAH   ; timer1作為baud rate generator，
    MOV TH1,#0FAH	; 且 baud rate = 12000
    ORL PCON,#80H   ; SMOD = 1 (timer1頻率除以二)
    SETB TR1        ; timer 1 run

    SETB ES		; enable串列傳輸中斷
    ; SETB PS   ; 串列傳輸中斷優先
    CLR TI      ; 清空串列傳輸中斷旗標
    CLR RI      ; 清空串列傳輸中斷旗標

    SETB EX0    ; enable INT0
    SETB PX0    ; INT0中斷優先
    SETB IT0    ; INT0設為負緣觸發
    CLR IE0     ; 清空INT0中斷旗標

    SETB EA


    CLR SM2     ; 不使用一對多模式
    SETB SM1    ; 串列傳輸 mode 1
    CLR SM0     ; 串列傳輸 mode 1

    SETB REN    ; receive enable

    CLR P1.7
    MOV NPTR,#080H

LOOP:
    ; vvvvvvvv測試用vvvvvvvv
    ; MOV P0,P3
    ; MOV C,TI
    ; MOV P4.6,C
    ; MOV C,RI
    ; MOV P4.7,C
    ; ^^^^^^^^^^^^^^^^^^^^^
    ; ACALL DISPLAY_NPTR
    AJMP LOOP

; ===== SOME FUNCTIONS =====
DISPLAY_OPTR:
    CLR A
    MOV A,@OPTR
    ANL A,#01111000B  ; 以OPTR指向的資料的.6~.3作為INDEX
    RR A
    RR A
    RR A
    MOV B,#2
    MUL AB
    MOV TEMP,A

    ; PUSH DPL
    ; PUSH DPH
    MOV DPTR,#MAGNI_VISUALIZE

    MOVC A,@A+DPTR
    MOV P2,A
    MOV A,TEMP
    INC A
    MOVC A,@A+DPTR
    MOV P4,A

    ; POP DPH
    ; POP DPL
    RET

DELAY: 
    MOV R7,#10 
DELAY1: 
    MOV R6,#45
DELAY2: 
    DJNZ R6,DELAY2 
    DJNZ R7,DELAY1 
    RET

; ===== INTERRUPT FUNCTIONS =====
SERIAL_INT:
    CJNE NPTR,#0FFH,INC_NPTR
    MOV NPTR,#080H
    SJMP INSERT_NEW
    INC_NPTR:
    INC NPTR

    INSERT_NEW:
    MOV @NPTR,SBUF
    CLR TI
    CLR RI
    CPL P1.7
    RETI

ROTATION_INT:
    CPL P1.5

    MOV A,NPTR  ; 取樣NPTR
    MOV OPTR,A
    INC OPTR    ; 從最舊的資料開始顯示

    MOV TEMP1,#128

    DISPLAY_LOOP:
        CJNE OPTR,#0FFH,INC_OPTR
        MOV OPTR,#080H
        SJMP CALL_DISPLAY_OPTR
        INC_OPTR:
        INC OPTR
        CALL_DISPLAY_OPTR:
        ACALL DISPLAY_OPTR
        ACALL DELAY
    DJNZ TEMP1,DISPLAY_LOOP

    CPL P1.5
    RETI

; ===== TABLES =====
MAGNI_VISUALIZE:
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

    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B
    ; DB 01010101B, 01010101B