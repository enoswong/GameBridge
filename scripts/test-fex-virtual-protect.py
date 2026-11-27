#!/usr/bin/env python3
"""Compile the exact Win32 wrapper body against a contract-checking API double."""
import pathlib
import re
import subprocess
import sys
import tempfile

header = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'^inline bool VirtualProtect\(void\* Ptr, size_t Size, ProtectOptions options\) \{\n  DWORD prot .*?^\}', header, re.M | re.S)
if not match:
    sys.exit('Pinned Windows VirtualProtect wrapper not found')
source = r'''
#include <initializer_list>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
using DWORD = uint32_t;
constexpr DWORD PAGE_NOACCESS=1, PAGE_READONLY=2, PAGE_READWRITE=4, PAGE_EXECUTE_READ=32, PAGE_EXECUTE_READWRITE=64;
enum class ProtectOptions: uint32_t { None=0, Read=1, Write=2, Exec=4 };
constexpr ProtectOptions operator|(ProtectOptions a, ProtectOptions b) { return ProtectOptions(uint32_t(a)|uint32_t(b)); }
#define LOGMAN_MSG_A_FMT(...) std::abort()
static bool api_success, output_supplied;
static void* seen_ptr;
static size_t seen_size;
static DWORD seen_prot;
int VirtualProtect(void* ptr, size_t size, DWORD prot, DWORD* old) {
    seen_ptr=ptr; seen_size=size; seen_prot=prot; output_supplied=old!=nullptr;
    if (!old || !api_success) return 0;
    *old=PAGE_READWRITE;
    return 1;
}
namespace FEXCore::Allocator {
''' + match.group(0) + r'''
}
int main() {
    using P=ProtectOptions;
    struct Case { P options; DWORD prot; };
    Case cases[]={{P::None,PAGE_NOACCESS},{P::Read,PAGE_READONLY},{P::Read|P::Write,PAGE_READWRITE},{P::Read|P::Exec,PAGE_EXECUTE_READ},{P::Read|P::Write|P::Exec,PAGE_EXECUTE_READWRITE}};
    int failures=0;
    char buffer[4096];
    for (auto c: cases) for (bool success: {false,true}) {
        api_success=success;
        auto result=FEXCore::Allocator::VirtualProtect(buffer,sizeof(buffer),c.options);
        if (!output_supplied || result!=success || seen_ptr!=buffer || seen_size!=sizeof(buffer) || seen_prot!=c.prot) {
            std::fprintf(stderr,"contract violation: prot=%u success=%d result=%d old_output=%d\n",c.prot,success,result,output_supplied);
            ++failures;
        }
    }
    std::printf("%d/10 cases passed\n",10-failures);
    return failures?1:0;
}
'''
with tempfile.TemporaryDirectory() as d:
    cpp = pathlib.Path(d, 'contract.cpp')
    exe = pathlib.Path(d, 'contract')
    cpp.write_text(source)
    subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror', str(cpp), '-o', str(exe)], check=True)
    sys.exit(subprocess.run([str(exe)]).returncode)
