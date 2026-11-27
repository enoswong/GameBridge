/* Standalone Windows x64 Wine/FEX smoke probe. No Steam or network access. */
typedef unsigned short W;
__declspec(dllimport) void __stdcall ExitProcess(unsigned int);
__declspec(dllimport) void *__stdcall LoadLibraryW(const W *);
__declspec(dllimport) void *__stdcall GetProcAddress(void *, const char *);
__declspec(dllimport) int __stdcall MessageBoxW(void *, const W *, const W *, unsigned int);
typedef long (__stdcall *CreateDevice)(void *, int, void *, unsigned int,
    const int *, unsigned int, unsigned int, void **, int *, void **);
void mainCRTStartup(void) {
    void *device = 0, *context = 0;
    int feature = 0;
    MessageBoxW(0, (const W *)L"Win32 x64 execution reached.\n\n繁體中文測試\n简体中文测试\n\nPress OK to test D3D11.",
                (const W *)L"GameBridge native smoke test", 0);
    void *module = LoadLibraryW((const W *)L"d3d11.dll");
    CreateDevice create = module ? (CreateDevice)GetProcAddress(module, "D3D11CreateDevice") : 0;
    long hr = create ? create(0, 1, 0, 0, 0, 0, 7, &device, &feature, &context) : -1;
    if (hr >= 0 && device && context) {
        MessageBoxW(0, (const W *)L"D3D11 hardware device creation succeeded. This is not an FPS or rendering test.",
                    (const W *)L"GameBridge D3D11 PASS", 0);
        ExitProcess(0);
    }
    MessageBoxW(0, (const W *)L"D3D11 device creation failed. Export the Madeira log.",
                (const W *)L"GameBridge D3D11 FAIL", 0x10);
    ExitProcess(1);
}
