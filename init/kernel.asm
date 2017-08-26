;	deeppinkos
;-------------------------------------------------------------------------------
;                                      BIOS内存映射
;-------------------------------------------------------------------------------
;	TAB=4			SP=0x7c00		0x8000=拷贝到启动区
;-------------------------------------------------------------------------------
;	|中断向量表|		|;代码存储位置|	......	| 512|
;	|	  |		|	     |	......	|    |
;-------------------------------------------------------------------------------
;								0x8200=后边的程序
;	在某种意义上理解，我们的程序只需要在磁盘的开始512字节就行
;	然后硬件上自动去读这512，然后执行这段程序

; 1-> 读取磁盘后边扇区的数据
; 2-> 在bootsecond.nas中添加LCD支持
; 3-> 初始化PIC
; 4-> 打开A20，进入保护模式
; 5-> 设置CR0的PE和PG
; 6-> 更新D、E、F、G、S，其中数代表的是第几个GDT

[bits 32]
GLOBAL  _start
GLOBAL	myprintf
GLOBAL  load_gdtr
EXTERN  kernel_start

BOTPAK	EQU		0x00280000
DSKCAC	EQU		0x00100000
DSKCAC0	EQU		0x00008000

;BOOT_INFO信息
CYLS		EQU	0x0ff0
LEDS		EQU	0x0ff1
LCDMODE		EQU	0x0ff2  ;
SCREENX		EQU	0x0ff4  ;	x
SCREENY		EQU	0x0ff6  ;	y
LCDRAM		EQU	0x0ff8  ; 图像缓冲区的开始地址


_start:
        ;INT     0x10
	MOV     ESP,0x00007000
        MOV     EBP,ESP
        ;AND     ESP,0FFFFFFF0H
        ;MOV     AH,0x0f
        ;MOV     AL,'V'
        ;MOV     BYTE [0xb8008],'V'
        MOV     EAX,kernel_start
        JMP     EAX
        ;SUB     EAX,0x8080
        ;CALL    EAX
; 加载gdtr地址需要，后面函数调用
load_gdtr:
        MOV     EAX,[ESP+4]
        LGDT    [EAX]
        MOV     AX,0x10
        MOV     DS,AX
        MOV     ES,AX
        MOV     FS,AX
        MOV     GS,AX
        MOV     SS,AX

        JMP     0x08:.flush
.flush:
        ret

load_idtr:
        MOV     EAX,[ESP+4]
        LIDT    [EAX]
        ret

; 定义两个构造中断处理函数的宏(有的中断有错误代码，有的没有)
; 用于没有错误代码的中断
%macro ISR_NOERRCODE 1
[GLOBAL isr%1]
isr%1:
	cli                         ; 首先关闭中断
	push 0                      ; push 无效的中断错误代码(起到占位作用，便于所有isr函数统一清栈)
	push %1                     ; push 中断号
	jmp isr_common_stub
%endmacro

; 用于有错误代码的中断
%macro ISR_ERRCODE 1
[GLOBAL isr%1]
isr%1:
	cli                         ; 关闭中断
	push %1                     ; push 中断号
	jmp isr_common_stub
%endmacro

; 定义中断处理函数
ISR_NOERRCODE  0 	; 0 #DE 除 0 异常
ISR_NOERRCODE  1 	; 1 #DB 调试异常
ISR_NOERRCODE  2 	; 2 NMI
ISR_NOERRCODE  3 	; 3 BP 断点异常 
ISR_NOERRCODE  4 	; 4 #OF 溢出 
ISR_NOERRCODE  5 	; 5 #BR 对数组的引用超出边界 
ISR_NOERRCODE  6 	; 6 #UD 无效或未定义的操作码 
ISR_NOERRCODE  7 	; 7 #NM 设备不可用(无数学协处理器) 
ISR_ERRCODE    8 	; 8 #DF 双重故障(有错误代码) 
ISR_NOERRCODE  9 	; 9 协处理器跨段操作
ISR_ERRCODE   10 	; 10 #TS 无效TSS(有错误代码) 
ISR_ERRCODE   11 	; 11 #NP 段不存在(有错误代码) 
ISR_ERRCODE   12 	; 12 #SS 栈错误(有错误代码) 
ISR_ERRCODE   13 	; 13 #GP 常规保护(有错误代码) 
ISR_ERRCODE   14 	; 14 #PF 页故障(有错误代码) 
ISR_NOERRCODE 15 	; 15 CPU 保留 
ISR_NOERRCODE 16 	; 16 #MF 浮点处理单元错误 
ISR_ERRCODE   17 	; 17 #AC 对齐检查 
ISR_NOERRCODE 18 	; 18 #MC 机器检查 
ISR_NOERRCODE 19 	; 19 #XM SIMD(单指令多数据)浮点异常

; 20~31 Intel 保留
ISR_NOERRCODE 20
ISR_NOERRCODE 21
ISR_NOERRCODE 22
ISR_NOERRCODE 23
ISR_NOERRCODE 24
ISR_NOERRCODE 25
ISR_NOERRCODE 26
ISR_NOERRCODE 27
ISR_NOERRCODE 28
ISR_NOERRCODE 29
ISR_NOERRCODE 30
ISR_NOERRCODE 31
; 32～255 用户自定义
ISR_NOERRCODE 255

[GLOBAL isr_common_stub]
[EXTERN isr_handler]
; 中断服务程序
isr_common_stub:
	pusha                    ; Pushes edi, esi, ebp, esp, ebx, edx, ecx, eax
	mov ax, ds
	push eax                ; 保存数据段描述符
	
	mov ax, 0x10            ; 加载内核数据段描述符表
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	
	push esp		; 此时的 esp 寄存器的值等价于 pt_regs 结构体的指针
	call isr_handler        ; 在 C 语言代码里
	add esp, 4 		; 清除压入的参数
	
	pop ebx                 ; 恢复原来的数据段描述符
	mov ds, bx
	mov es, bx
	mov fs, bx
	mov gs, bx
	mov ss, bx
	
	popa                     ; Pops edi, esi, ebp, esp, ebx, edx, ecx, eax
	add esp, 8               ; 清理栈里的 error code 和 ISR
	iret
.end:

;stop:
;        JMP     stop
;stack:
 ;       times   32768 db 0
;glb_mboot_ptr:
;	resb	4

;STACK_TOP equ $-stack-1




