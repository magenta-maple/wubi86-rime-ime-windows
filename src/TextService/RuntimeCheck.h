#pragma once

#include "Globals.h"

namespace Meifeng {
namespace RuntimeCheck {

// 32 位进程里 %ProgramFiles% 会指到 x86，要用 ProgramW6432 才能看到 x64 的 .NET
inline bool DirHasDotNet10(const std::wstring& dir) {
    WIN32_FIND_DATAW fd = {};
    HANDLE h = FindFirstFileW((dir + L"\\10.*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) return false;
    bool ok = false;
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && fd.cFileName[0] != L'.') {
            ok = true;
            break;
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return ok;
}

inline bool HasDotNetDesktop10() {
    wchar_t buf[MAX_PATH] = {};
    const wchar_t* vars[] = {L"ProgramW6432", L"ProgramFiles"};
    for (auto var : vars) {
        buf[0] = 0;
        if (!GetEnvironmentVariableW(var, buf, MAX_PATH) || !buf[0]) continue;
        if (DirHasDotNet10(std::wstring(buf) + L"\\dotnet\\shared\\Microsoft.WindowsDesktop.App"))
            return true;
    }
    return false;
}

inline std::wstring LaunchStampPath() {
    wchar_t tmp[MAX_PATH] = {};
    GetTempPathW(MAX_PATH, tmp);
    return std::wstring(tmp) + L"MeifengWubi.launch";
}

// 任意进程（含 32 位）共用：5 分钟内只允许拉起一次服务，避免每个窗口都弹出 .NET 安装框
inline bool RecentlyTriedLaunch(ULONGLONG windowMs = 5ull * 60 * 1000) {
    HANDLE h = CreateFileW(LaunchStampPath().c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    ULONGLONG t = 0;
    DWORD n = 0;
    ReadFile(h, &t, sizeof(t), &n, nullptr);
    CloseHandle(h);
    if (n != sizeof(t)) return false;
    ULONGLONG now = GetTickCount64();
    return now >= t && now - t < windowMs;
}

inline void MarkTriedLaunch() {
    HANDLE h = CreateFileW(LaunchStampPath().c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    ULONGLONG t = GetTickCount64();
    DWORD n = 0;
    WriteFile(h, &t, sizeof(t), &n, nullptr);
    CloseHandle(h);
}

}  // namespace RuntimeCheck
}  // namespace Meifeng
