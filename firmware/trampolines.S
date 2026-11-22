.syntax unified
.cpu cortex-m33
.thumb
.section .text.trampolines,"ax",%progbits
.balign 2
.global stock_show
.type stock_show,%function
.thumb_func
stock_show:
.byte 0x90,0xb5,0x83,0xb0
b.w resume_show
.balign 2
.global stock_hide
.type stock_hide,%function
.thumb_func
stock_hide:
.byte 0xb0,0xb5,0x82,0xb0
b.w resume_hide
.balign 2
.global stock_destroy
.type stock_destroy,%function
.thumb_func
stock_destroy:
.byte 0xf0,0xb5,0x4,0x46
b.w resume_destroy
.balign 2
.global stock_wheel
.type stock_wheel,%function
.thumb_func
stock_wheel:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_wheel
.balign 2
.global stock_event
.type stock_event,%function
.thumb_func
stock_event:
.byte 0xb0,0xb5,0x82,0xb0
b.w resume_event
.balign 2
.global stock_message
.type stock_message,%function
.thumb_func
stock_message:
.byte 0xb0,0xb5,0xc,0x46
b.w resume_message
.balign 2
.global stock_dc_text
.type stock_dc_text,%function
.thumb_func
stock_dc_text:
.byte 0xf0,0xb5,0xc3,0xb0
b.w resume_dc_text
.balign 2
.global stock_names
.type stock_names,%function
.thumb_func
stock_names:
.byte 0x2d,0xe9,0xf0,0x4f
b.w resume_names
.balign 2
.global stock_dots
.type stock_dots,%function
.thumb_func
stock_dots:
.byte 0x2d,0xe9,0xf0,0x47
b.w resume_dots
.balign 2
.global stock_delete_dots
.type stock_delete_dots,%function
.thumb_func
stock_delete_dots:
.byte 0x98,0xb5,0x4,0x46
b.w resume_delete_dots
.balign 2
.global stock_lottie
.type stock_lottie,%function
.thumb_func
stock_lottie:
.byte 0xb0,0xb5,0x84,0xb0
b.w resume_lottie
.balign 2
.global stock_app_id
.type stock_app_id,%function
.thumb_func
stock_app_id:
.byte 0x80,0xb5,0x0,0xaf
b.w resume_app_id
.balign 2
.global stock_refresh_label
.type stock_refresh_label,%function
.thumb_func
stock_refresh_label:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_refresh_label
.balign 2
.global stock_vm_event
.type stock_vm_event,%function
.thumb_func
stock_vm_event:
.byte 0xf0,0xb5,0x85,0xb0
b.w resume_vm_event
.balign 2
.global stock_can_wakeup
.type stock_can_wakeup,%function
.thumb_func
stock_can_wakeup:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_can_wakeup
.balign 2
.global stock_open_remote_audio
.type stock_open_remote_audio,%function
.thumb_func
stock_open_remote_audio:
.byte 0x2d,0xe9,0xf0,0x47
b.w resume_open_remote_audio
.balign 2
.global stock_open_recorder
.type stock_open_recorder,%function
.thumb_func
stock_open_recorder:
.byte 0xf0,0xb5,0x83,0xb0
b.w resume_open_recorder
.balign 2
.global stock_screen_state
.type stock_screen_state,%function
.thumb_func
stock_screen_state:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_screen_state
.balign 2
.global stock_factory_reset
.type stock_factory_reset,%function
.thumb_func
stock_factory_reset:
.byte 0xb0,0xb5,0x82,0xb0
b.w resume_factory_reset
.balign 2
.global stock_key_read
.type stock_key_read,%function
.thumb_func
stock_key_read:
.byte 0x0,0x23,0x90,0xb5
b.w resume_key_read
.balign 2
.global stock_wheel_read
.type stock_wheel_read,%function
.thumb_func
stock_wheel_read:
.byte 0x2d,0xe9,0xf0,0x4f
b.w resume_wheel_read

.balign 2
.global stream_register_shim
.type stream_register_shim,%function
.thumb_func
stream_register_shim:
 movs r4,#0
 ldr r0,=0x196dfaf4
 ldr r3,=tio_hook_file
 str r3,[r0,#TIO_STOCK_FILE_CB_RECEIVE]
 ldr r3,=0x105a7d39
 str r3,[r0]
 bx lr
.ltorg
.balign 2
.global m8_hook_frame_start
.type m8_hook_frame_start,%function
.thumb_func
m8_hook_frame_start:
push {r1,r2,r3,lr}
bl m8_impl_frame_start
pop {r1,r2,r3,pc}
.balign 2
.global m8_hook_frame_index
.type m8_hook_frame_index,%function
.thumb_func
m8_hook_frame_index:
push {r1,r2,r3,lr}
bl m8_impl_frame_index
pop {r1,r2,r3,pc}

@ PIN lock gates (TMG13). Each stock entry above jumps here (build-inputs.json, Entry trampoline <name>). The gate saves
@ r0-r3 (the stock arguments) and r4 (eight-byte stack alignment) with lr, so stack arguments stay where stock expects
@ them; asks lock-v1 whether to refuse; restores; then either returns the refusal value or runs the stock prologue
@ (stock_<name>) and resumes in stock. POP does not change the flags, so the test survives the restore.
@ can_wakeup: AssistantService::canWakeup(this, notify), bool; 0 = refuse (every caller stops, nothing retried).
@ open_remote_audio: AudioAdapter::openRemoteAudioStream(), bool; 0 = refuse (the stock conflict result).
@ open_recorder: AudioAdapter::openRecorder(), no result its one caller reads (it reloads r0 right after the call);
@   a refusal returns 0 and leaves the recorder-open byte clear, so the audio block callback sends nothing.
@ screen_state: screen_state_update(new_state, source), result ignored by every caller; it runs with the screen
@   controller mutex held, so lock_refuse_screen may only read lock state, never call a screen or nav function.
@ factory_reset: the factory-reset worker, an LVGL timer callback (lv_timer_t *). SysStateMonitor's
@   handleResetFactoryResult creates its timer (1 s) only when the ERPC reset reports success, so it runs after every
@   refusal check (doFactoryReset's battery check, the ERPC result). lock_on_factory_reset runs first, then stock
@   continues unconditionally.
.balign 2
.global lock_hook_can_wakeup
.type lock_hook_can_wakeup,%function
.thumb_func
lock_hook_can_wakeup:
 push {r0-r4,lr}
 bl lock_refuse_can_wakeup
 cmp r0,#0
 pop {r0-r4,lr}
 bne 1f
 b.w stock_can_wakeup
1:
 movs r0,#0
 bx lr
.balign 2
.global lock_hook_open_remote_audio
.type lock_hook_open_remote_audio,%function
.thumb_func
lock_hook_open_remote_audio:
 push {r0-r4,lr}
 bl lock_refuse_open_remote_audio
 cmp r0,#0
 pop {r0-r4,lr}
 bne 1f
 b.w stock_open_remote_audio
1:
 movs r0,#0
 bx lr
.balign 2
.global lock_hook_open_recorder
.type lock_hook_open_recorder,%function
.thumb_func
lock_hook_open_recorder:
 push {r0-r4,lr}
 bl lock_refuse_open_recorder
 cmp r0,#0
 pop {r0-r4,lr}
 bne 1f
 b.w stock_open_recorder
1:
 movs r0,#0
 bx lr
.balign 2
.global lock_hook_screen_state
.type lock_hook_screen_state,%function
.thumb_func
lock_hook_screen_state:
 push {r0-r4,lr}
 bl lock_refuse_screen
 cmp r0,#0
 pop {r0-r4,lr}
 bne 1f
 b.w stock_screen_state
1:
 bx lr
.balign 2
.global lock_hook_factory_reset
.type lock_hook_factory_reset,%function
.thumb_func
lock_hook_factory_reset:
 push {r0-r4,lr}
 bl lock_on_factory_reset
 pop {r0-r4,lr}
 b.w stock_factory_reset
