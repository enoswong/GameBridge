/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 GameBridge contributors
 * Independently implemented from the documented Win32 pointer/message contracts.
 * This x86-64 Wine compatibility component is enabled only in Deskrawl.exe.
 */
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <windowsx.h>
#include <stdint.h>


static void copy_bytes(void *destination, const void *source, SIZE_T count) {
    BYTE *d = destination; const BYTE *s = source;
    while (count--) *d++ = *s++;
}
static void clear_bytes(void *destination, SIZE_T count) {
    BYTE *d = destination;
    while (count--) *d++ = 0;
}
static HMODULE self;
static BOOL target;
static volatile LONG enabled;
static volatile LONG frames;
typedef struct { HHOOK hook; POINTER_INFO info; BOOL dispatching; } ThreadState;
static DWORD thread_slot = TLS_OUT_OF_INDEXES;
static ThreadState *state(void) {
    return thread_slot == TLS_OUT_OF_INDEXES ? NULL : TlsGetValue(thread_slot);
}
static const HANDLE mouse_device = (HANDLE)(UINT_PTR)1;

static BOOL invalid(void) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }

static BOOL WINAPI pointer_info(UINT32 id, POINTER_INFO *out) {
    ThreadState *s = state();
    if (id != 1 || !out || !s || !s->dispatching) return invalid();
    *out = s->info;
    return TRUE;
}
static BOOL WINAPI pointer_type(UINT32 id, POINTER_INPUT_TYPE *out) {
    if (id != 1 || !out) return invalid();
    *out = PT_MOUSE;
    return TRUE;
}
static BOOL WINAPI pointer_rects(HANDLE device, RECT *input, RECT *display) {
    if (device != mouse_device || !input || !display) return invalid();
    display->left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    display->top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    display->right = display->left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    display->bottom = display->top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    /* Coordinates use the same pixel space on both sides of the mapping. */
    *input = *display;
    return TRUE;
}

static void dispatch_pointer(const MSG *m) {
    ThreadState *s = state();
    if (!s) return;
    UINT kind;
    POINTER_FLAGS flags = POINTER_FLAG_PRIMARY | POINTER_FLAG_INRANGE;
    POINTER_BUTTON_CHANGE_TYPE change = POINTER_CHANGE_NONE;
    switch (m->message) {
    case WM_MOUSEMOVE: kind = WM_POINTERUPDATE; flags |= POINTER_FLAG_UPDATE; break;
    case WM_LBUTTONDOWN: kind = WM_POINTERDOWN; flags |= POINTER_FLAG_DOWN; change = POINTER_CHANGE_FIRSTBUTTON_DOWN; break;
    case WM_LBUTTONUP: kind = WM_POINTERUP; flags |= POINTER_FLAG_UP; change = POINTER_CHANGE_FIRSTBUTTON_UP; break;
    case WM_RBUTTONDOWN: kind = WM_POINTERDOWN; flags |= POINTER_FLAG_DOWN; change = POINTER_CHANGE_SECONDBUTTON_DOWN; break;
    case WM_RBUTTONUP: kind = WM_POINTERUP; flags |= POINTER_FLAG_UP; change = POINTER_CHANGE_SECONDBUTTON_UP; break;
    case WM_MBUTTONDOWN: kind = WM_POINTERDOWN; flags |= POINTER_FLAG_DOWN; change = POINTER_CHANGE_THIRDBUTTON_DOWN; break;
    case WM_MBUTTONUP: kind = WM_POINTERUP; flags |= POINTER_FLAG_UP; change = POINTER_CHANGE_THIRDBUTTON_UP; break;
    case WM_MOUSEWHEEL: kind = WM_POINTERWHEEL; flags |= POINTER_FLAG_WHEEL; break;
    case WM_MOUSEHWHEEL: kind = WM_POINTERHWHEEL; flags |= POINTER_FLAG_HWHEEL; break;
    default: return;
    }
    if (!m->hwnd) return;
    if (m->wParam & MK_LBUTTON) flags |= POINTER_FLAG_FIRSTBUTTON;
    if (m->wParam & MK_RBUTTON) flags |= POINTER_FLAG_SECONDBUTTON;
    if (m->wParam & MK_MBUTTON) flags |= POINTER_FLAG_THIRDBUTTON;
    if (flags & (POINTER_FLAG_FIRSTBUTTON | POINTER_FLAG_SECONDBUTTON | POINTER_FLAG_THIRDBUTTON)) flags |= POINTER_FLAG_INCONTACT;
    POINTER_INFO saved = s->info;
    BOOL saved_dispatch = s->dispatching;
    clear_bytes(&s->info, sizeof(s->info));
    s->info.pointerType = PT_MOUSE;
    s->info.pointerId = 1;
    s->info.frameId = (UINT32)InterlockedIncrement(&frames);
    s->info.pointerFlags = flags;
    s->info.sourceDevice = mouse_device;
    s->info.hwndTarget = m->hwnd;
    s->info.ptPixelLocation.x = GET_X_LPARAM(m->lParam);
    s->info.ptPixelLocation.y = GET_Y_LPARAM(m->lParam);
    if (kind != WM_POINTERWHEEL && kind != WM_POINTERHWHEEL) ClientToScreen(m->hwnd, &s->info.ptPixelLocation);
    s->info.ptPixelLocationRaw = s->info.ptPixelLocation;
    s->info.ptHimetricLocation = s->info.ptPixelLocation;
    s->info.ptHimetricLocationRaw = s->info.ptPixelLocation;
    s->info.dwTime = m->time;
    s->info.historyCount = 1;
    s->info.ButtonChangeType = change;
    if (m->wParam & MK_SHIFT) s->info.dwKeyStates |= POINTER_MOD_SHIFT;
    if (m->wParam & MK_CONTROL) s->info.dwKeyStates |= POINTER_MOD_CTRL;
    if (kind == WM_POINTERWHEEL || kind == WM_POINTERHWHEEL) s->info.InputData = GET_WHEEL_DELTA_WPARAM(m->wParam);
    s->dispatching = TRUE;
    WPARAM wp = MAKEWPARAM(1, flags & 0xffff);
    if (kind == WM_POINTERWHEEL || kind == WM_POINTERHWHEEL) wp = MAKEWPARAM(1, HIWORD(m->wParam));
    /* Synchronous delivery keeps DOWN/UP state aligned even when both are queued.
     * Preserve outer state if the window procedure pumps messages recursively. */
    SendMessageW(m->hwnd, kind, wp, MAKELPARAM(s->info.ptPixelLocation.x, s->info.ptPixelLocation.y));
    s->info = saved;
    s->dispatching = saved_dispatch;
}
static LRESULT CALLBACK messages(int code, WPARAM removed, LPARAM value) {
    if (code == HC_ACTION && removed == PM_REMOVE && InterlockedCompareExchange(&enabled, 0, 0))
        dispatch_pointer((const MSG *)value);
    return CallNextHookEx(NULL, code, removed, value);
}
static BOOL WINAPI enable_mouse(BOOL value) {
    ThreadState *s = state();
    if (value && !s) {
        s = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*s));
        if (!s) return FALSE;
        if (!TlsSetValue(thread_slot, s)) { HeapFree(GetProcessHeap(), 0, s); return FALSE; }
    }
    if (value && !s->hook) {
        s->hook = SetWindowsHookExW(WH_GETMESSAGE, messages, self, GetCurrentThreadId());
        if (!s->hook) return FALSE;
    }
    InterlockedExchange(&enabled, !!value);
    return TRUE;
}

/* No displaced instructions are executed: these four API implementations are
 * wholly replaced for this process. A 14-byte RIP-relative jump preserves all
 * argument registers. Installation is during initial process DLL loading, before
 * application threads start. No trampoline/disassembler dependency is needed. */
typedef struct { const char *name; FARPROC replacement; void *address; BYTE saved[14]; } Patch;
static Patch patches[] = {
    {"EnableMouseInPointer", (FARPROC)enable_mouse, NULL, {0}},
    {"GetPointerInfo", (FARPROC)pointer_info, NULL, {0}},
    {"GetPointerType", (FARPROC)pointer_type, NULL, {0}},
    {"GetPointerDeviceRects", (FARPROC)pointer_rects, NULL, {0}}
};
static BOOL write_code(void *address, const void *bytes) {
    DWORD old, unused;
    if (!VirtualProtect(address, 14, PAGE_EXECUTE_READWRITE, &old)) return FALSE;
    copy_bytes(address, bytes, 14);
    FlushInstructionCache(GetCurrentProcess(), address, 14);
    VirtualProtect(address, 14, old, &unused);
    return TRUE;
}
static BOOL install(void) {
    HMODULE user = GetModuleHandleW(L"user32.dll");
    unsigned n;
    for (n = 0; n < sizeof(patches)/sizeof(patches[0]); ++n) {
        Patch *p = &patches[n];
        p->address = (void *)GetProcAddress(user, p->name);
        if (!p->address) break;
        copy_bytes(p->saved, p->address, 14);
        BYTE jump[14] = {0xff, 0x25, 0, 0, 0, 0};
        copy_bytes(jump + 6, &p->replacement, 8);
        if (!write_code(p->address, jump)) break;
    }
    if (n == sizeof(patches)/sizeof(patches[0])) return TRUE;
    while (n) { --n; write_code(patches[n].address, patches[n].saved); }
    return FALSE;
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        WCHAR path[MAX_PATH];
        self = module;
        DWORD length = GetModuleFileNameW(NULL, path, MAX_PATH);
        if (!length || length >= MAX_PATH) return TRUE;
        WCHAR *base = path;
        for (WCHAR *p = path; *p; ++p) if (*p == L'\\') base = p + 1;
        target = lstrcmpiW(base, L"Deskrawl.exe") == 0;
        if (target) {
            /* Pin the module: process-local entrypoints must never point into an
             * unloaded DLL. Rollback is exiting the app and removing its shim. */
            thread_slot = TlsAlloc();
            if (thread_slot == TLS_OUT_OF_INDEXES) return FALSE;
            HMODULE pinned;
            GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                              (LPCWSTR)(void *)DllMain, &pinned);
            if (!install()) return FALSE;
        }
    } else if (reason == DLL_THREAD_DETACH && target) {
        ThreadState *s = state();
        if (s) {
            if (s->hook) UnhookWindowsHookEx(s->hook);
            HeapFree(GetProcessHeap(), 0, s);
            TlsSetValue(thread_slot, NULL);
        }
    }
    return TRUE;
}
