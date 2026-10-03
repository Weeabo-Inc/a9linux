/*
 * handoff-stub.S — a stand-in for the part of a9boot that touches the kernel.
 *
 * WHY: the arm64 boot contract has exactly four things a loader can get wrong
 * in a way that produces a silent hang, and QEMU's own `-kernel` loader hides
 * all four because QEMU implements them for us. This stub implements them
 * ourselves, so the harness can fail if our sequence is wrong:
 *
 *   1. x0 = physical address of the DTB          (get it wrong: no DT at all)
 *   2. x1 = x2 = x3 = 0                          (reserved, must be zeroed)
 *   3. MMU off, D-cache off, interrupts masked at entry
 *   4. the secondary core parked on a spin-table mailbox, replying to the
 *      kernel's release write. Get cpu-release-addr wrong and the kernel
 *      waits ~7.5s and boots one CPU (measured: see logs/04).
 *
 * It also proves the two blobs a9boot must place by itself: /chosen/bootargs
 * (the kernel's ONLY command-line source on the arm64 boot path - there is no
 * cmdline register) and /chosen/initrd-start/end.
 *
 * It is NOT a9boot and it is NOT a model of the A9 bootrom. It runs at EL1 on
 * QEMU virt with a QEMU-supplied reset vector. See CANNOT-PROVE.md.
 *
 * Build: mk-handoff-stub.sh  (aarch64-linux-gnu-as/ld/objcopy)
 */
	.section .text
	.global _start

	.equ UART_DR,   0x09000000	/* QEMU virt PL011 data register */
	.equ UART_FR,   0x18		/* PL011 flag register; bit 5 = TXFF */

/*
 * The load map lives in mk-handoff-stub.sh and run-stub.sh; these are the
 * defaults and every one of them can be overridden with `as --defsym`.
 * QEMU reserves 0x40000000-0x40100000 for the DTB IT generates (even when we
 * do not use it), and the 58MB Ubuntu Image occupies 0x40080000-0x437e2988,
 * so the loader-owned blobs all live above 0x43800000.
 */
	.ifndef STUB_BASE
	.equ STUB_BASE, 0x43800000	/* this stub, CPU0 reset vector */
	.endif
	.ifndef MAILBOX
	.equ MAILBOX,   0x43804000	/* spin-table cpu-release-addr, from our DTB */
	.endif
	.ifndef STACK
	.equ STACK,     0x43808000	/* loader-reserved stack top */
	.endif
	.ifndef DTB
	.equ DTB,       0x43900000	/* where the loader put the DTB */
	.endif
	.ifndef IMAGE
	.equ IMAGE,     0x40080000	/* RAM base 0x40000000 + text_offset 0x80000 */
	.endif

_start:
	mrs	x19, mpidr_el1
	and	x19, x19, #0xff
	cbnz	x19, parked_cpu

/* ------------------------------------------------------------------ CPU0 --- */
primary:
	adr	x0, msg_cpu0
	bl	puts
	ldr	x5, =IMAGE
	adr	x0, msg_jump
	bl	puts

	/* arm64 boot protocol: x0 = DTB, x1..x3 reserved and ZERO.
	   These are set LAST: every bl above clobbers x0-x3. */
	ldr	x0, =DTB
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	ldr	x4, =STACK
	mov	sp, x4
	msr	daifset, #0xf			/* interrupts masked */
	/* MMU and caches are already off: QEMU resets them that way, and this
	   stub never enables them. That is the state a9boot must hand over in. */
	br	x5
1:	wfe
	b	1b

/* ------------------------------------------------------------- CPU1 (park) --- */
parked_cpu:
	adr	x0, msg_cpu1
	bl	puts
	ldr	x20, =MAILBOX
spin:
	ldr	x21, [x20]
	cbz	x21, idle
	/* arm64 spin-table binding: release the core only after cache
	   maintenance, since the kernel wrote the entry address through its own
	   mapping with the MMU on. */
	dsb	sy
	ic	ialluis
	dsb	sy
	isb
	br	x21
idle:
	wfe
	b	spin

/* --------------------------------------------------------------- helpers --- */
puts:
	ldr	x1, =UART_DR
1:	ldrb	w2, [x0], #1
	cbz	w2, 2f
3:	ldr	w3, [x1, #UART_FR]
	tbnz	w3, #5, 3b			/* wait while TX FIFO full */
	str	w2, [x1]
	b	1b
2:	ret

	.section .rodata
msg_cpu0:	.asciz "\r\n[stub] CPU0: hand-off contract emulated (x0=DTB, x1..x3=0, MMU off)\r\n"
msg_jump:	.asciz "[stub] CPU0: jumping to Image entry 0x40080000\r\n"
msg_cpu1:	.asciz "[stub] CPU1: parked on spin-table mailbox\r\n"
