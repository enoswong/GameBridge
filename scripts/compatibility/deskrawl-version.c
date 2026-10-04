/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 GameBridge contributors
 * ABI-correct forwarding to the system version library, loaded by absolute path.
 */
#define _WIN32_WINNT 0x0A00
#include <windows.h>
static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static HMODULE system_version;
static BOOL CALLBACK load_version(PINIT_ONCE init, PVOID argument, PVOID *context) {
    (void)init; (void)argument; (void)context;
    WCHAR path[MAX_PATH];
    UINT n = GetSystemDirectoryW(path, MAX_PATH);
    if (!n || n + 13 >= MAX_PATH) return FALSE;
    lstrcatW(path, L"\\version.dll");
    system_version = LoadLibraryW(path);
    return system_version != NULL;
}
static FARPROC resolve(const char *name) {
    if (!InitOnceExecuteOnce(&once, load_version, NULL, NULL)) return NULL;
    return GetProcAddress(system_version, name);
}
DWORD WINAPI gb_VerFindFileA(DWORD uFlags,LPSTR szFileName,LPSTR szWinDir,LPSTR szAppDir,LPSTR szCurDir,PUINT lpuCurDirLen,LPSTR szDestDir,PUINT lpuDestDirLen) {
    typedef DWORD (WINAPI *Function)(DWORD uFlags,LPSTR szFileName,LPSTR szWinDir,LPSTR szAppDir,LPSTR szCurDir,PUINT lpuCurDirLen,LPSTR szDestDir,PUINT lpuDestDirLen);
    Function function = (Function)resolve("VerFindFileA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(uFlags, szFileName, szWinDir, szAppDir, szCurDir, lpuCurDirLen, szDestDir, lpuDestDirLen);
}
DWORD WINAPI gb_VerFindFileW(DWORD uFlags,LPWSTR szFileName,LPWSTR szWinDir,LPWSTR szAppDir,LPWSTR szCurDir,PUINT lpuCurDirLen,LPWSTR szDestDir,PUINT lpuDestDirLen) {
    typedef DWORD (WINAPI *Function)(DWORD uFlags,LPWSTR szFileName,LPWSTR szWinDir,LPWSTR szAppDir,LPWSTR szCurDir,PUINT lpuCurDirLen,LPWSTR szDestDir,PUINT lpuDestDirLen);
    Function function = (Function)resolve("VerFindFileW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(uFlags, szFileName, szWinDir, szAppDir, szCurDir, lpuCurDirLen, szDestDir, lpuDestDirLen);
}
DWORD WINAPI gb_VerInstallFileA(DWORD uFlags,LPSTR szSrcFileName,LPSTR szDestFileName,LPSTR szSrcDir,LPSTR szDestDir,LPSTR szCurDir,LPSTR szTmpFile,PUINT lpuTmpFileLen) {
    typedef DWORD (WINAPI *Function)(DWORD uFlags,LPSTR szSrcFileName,LPSTR szDestFileName,LPSTR szSrcDir,LPSTR szDestDir,LPSTR szCurDir,LPSTR szTmpFile,PUINT lpuTmpFileLen);
    Function function = (Function)resolve("VerInstallFileA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(uFlags, szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir, szTmpFile, lpuTmpFileLen);
}
DWORD WINAPI gb_VerInstallFileW(DWORD uFlags,LPWSTR szSrcFileName,LPWSTR szDestFileName,LPWSTR szSrcDir,LPWSTR szDestDir,LPWSTR szCurDir,LPWSTR szTmpFile,PUINT lpuTmpFileLen) {
    typedef DWORD (WINAPI *Function)(DWORD uFlags,LPWSTR szSrcFileName,LPWSTR szDestFileName,LPWSTR szSrcDir,LPWSTR szDestDir,LPWSTR szCurDir,LPWSTR szTmpFile,PUINT lpuTmpFileLen);
    Function function = (Function)resolve("VerInstallFileW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(uFlags, szSrcFileName, szDestFileName, szSrcDir, szDestDir, szCurDir, szTmpFile, lpuTmpFileLen);
}
DWORD WINAPI gb_GetFileVersionInfoSizeA(LPCSTR lptstrFilename,LPDWORD lpdwHandle) {
    typedef DWORD (WINAPI *Function)(LPCSTR lptstrFilename,LPDWORD lpdwHandle);
    Function function = (Function)resolve("GetFileVersionInfoSizeA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(lptstrFilename, lpdwHandle);
}
DWORD WINAPI gb_GetFileVersionInfoSizeW(LPCWSTR lptstrFilename,LPDWORD lpdwHandle) {
    typedef DWORD (WINAPI *Function)(LPCWSTR lptstrFilename,LPDWORD lpdwHandle);
    Function function = (Function)resolve("GetFileVersionInfoSizeW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(lptstrFilename, lpdwHandle);
}
DWORD WINAPI gb_GetFileVersionInfoSizeExA(DWORD dwFlags, LPCSTR lpwstrFilename, LPDWORD lpdwHandle) {
    typedef DWORD (WINAPI *Function)(DWORD dwFlags, LPCSTR lpwstrFilename, LPDWORD lpdwHandle);
    Function function = (Function)resolve("GetFileVersionInfoSizeExA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(dwFlags, lpwstrFilename, lpdwHandle);
}
DWORD WINAPI gb_GetFileVersionInfoSizeExW(DWORD dwFlags, LPCWSTR lpwstrFilename, LPDWORD lpdwHandle) {
    typedef DWORD (WINAPI *Function)(DWORD dwFlags, LPCWSTR lpwstrFilename, LPDWORD lpdwHandle);
    Function function = (Function)resolve("GetFileVersionInfoSizeExW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(dwFlags, lpwstrFilename, lpdwHandle);
}
WINBOOL WINAPI gb_GetFileVersionInfoA(LPCSTR lptstrFilename,DWORD dwHandle,DWORD dwLen,LPVOID lpData) {
    typedef WINBOOL (WINAPI *Function)(LPCSTR lptstrFilename,DWORD dwHandle,DWORD dwLen,LPVOID lpData);
    Function function = (Function)resolve("GetFileVersionInfoA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(lptstrFilename, dwHandle, dwLen, lpData);
}
WINBOOL WINAPI gb_GetFileVersionInfoW(LPCWSTR lptstrFilename,DWORD dwHandle,DWORD dwLen,LPVOID lpData) {
    typedef WINBOOL (WINAPI *Function)(LPCWSTR lptstrFilename,DWORD dwHandle,DWORD dwLen,LPVOID lpData);
    Function function = (Function)resolve("GetFileVersionInfoW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(lptstrFilename, dwHandle, dwLen, lpData);
}
WINBOOL WINAPI gb_GetFileVersionInfoExA(DWORD dwFlags, LPCSTR lpwstrFilename, DWORD dwHandle, DWORD dwLen, LPVOID lpData) {
    typedef WINBOOL (WINAPI *Function)(DWORD dwFlags, LPCSTR lpwstrFilename, DWORD dwHandle, DWORD dwLen, LPVOID lpData);
    Function function = (Function)resolve("GetFileVersionInfoExA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(dwFlags, lpwstrFilename, dwHandle, dwLen, lpData);
}
WINBOOL WINAPI gb_GetFileVersionInfoExW(DWORD dwFlags, LPCWSTR lpwstrFilename, DWORD dwHandle, DWORD dwLen, LPVOID lpData) {
    typedef WINBOOL (WINAPI *Function)(DWORD dwFlags, LPCWSTR lpwstrFilename, DWORD dwHandle, DWORD dwLen, LPVOID lpData);
    Function function = (Function)resolve("GetFileVersionInfoExW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(dwFlags, lpwstrFilename, dwHandle, dwLen, lpData);
}
DWORD WINAPI gb_VerLanguageNameA(DWORD wLang,LPSTR szLang,DWORD nSize) {
    typedef DWORD (WINAPI *Function)(DWORD wLang,LPSTR szLang,DWORD nSize);
    Function function = (Function)resolve("VerLanguageNameA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(wLang, szLang, nSize);
}
DWORD WINAPI gb_VerLanguageNameW(DWORD wLang,LPWSTR szLang,DWORD nSize) {
    typedef DWORD (WINAPI *Function)(DWORD wLang,LPWSTR szLang,DWORD nSize);
    Function function = (Function)resolve("VerLanguageNameW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(wLang, szLang, nSize);
}
WINBOOL WINAPI gb_VerQueryValueA(LPCVOID pBlock,LPCSTR lpSubBlock,LPVOID *lplpBuffer,PUINT puLen) {
    typedef WINBOOL (WINAPI *Function)(LPCVOID pBlock,LPCSTR lpSubBlock,LPVOID *lplpBuffer,PUINT puLen);
    Function function = (Function)resolve("VerQueryValueA");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(pBlock, lpSubBlock, lplpBuffer, puLen);
}
WINBOOL WINAPI gb_VerQueryValueW(LPCVOID pBlock,LPCWSTR lpSubBlock,LPVOID *lplpBuffer,PUINT puLen) {
    typedef WINBOOL (WINAPI *Function)(LPCVOID pBlock,LPCWSTR lpSubBlock,LPVOID *lplpBuffer,PUINT puLen);
    Function function = (Function)resolve("VerQueryValueW");
    if (!function) { SetLastError(ERROR_PROC_NOT_FOUND); return 0; }
    return function(pBlock, lpSubBlock, lplpBuffer, puLen);
}
