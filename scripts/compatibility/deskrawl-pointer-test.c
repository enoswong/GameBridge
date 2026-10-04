#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdio.h>
#include <string.h>
static int count, failures;
static POINT expected;
static LRESULT CALLBACK proc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
 if(m==WM_POINTERDOWN || m==WM_POINTERUP) {
  POINTER_INFO i={0};
  if(!GetPointerInfo(GET_POINTERID_WPARAM(wp),&i)) failures++;
  if(m==WM_POINTERDOWN && (!(i.pointerFlags&POINTER_FLAG_DOWN)||i.ButtonChangeType!=POINTER_CHANGE_FIRSTBUTTON_DOWN)) failures++;
  if(m==WM_POINTERUP && (!(i.pointerFlags&POINTER_FLAG_UP)||i.ButtonChangeType!=POINTER_CHANGE_FIRSTBUTTON_UP)) failures++;
  POINTER_INPUT_TYPE type=0; RECT device={0},display={0};
  if(!GetPointerType(GET_POINTERID_WPARAM(wp),&type) || type!=PT_MOUSE) failures++;
  if(!GetPointerDeviceRects(i.sourceDevice,&device,&display) || device.right<=device.left || display.bottom<=display.top) failures++;
  if(i.ptPixelLocation.x!=expected.x || i.ptPixelLocation.y!=expected.y) failures++;
  if(i.hwndTarget!=w || i.historyCount!=1) failures++;
  count++;
 }
 return DefWindowProcW(w,m,wp,lp);
}
int main(int argc, char **argv) {
 int inactive=argc>1 && !strcmp(argv[1],"inactive");
 int disabled=argc>1 && !strcmp(argv[1],"disabled");
 DWORD unused=0;
 if(!GetFileVersionInfoSizeW(L"C:\\windows\\system32\\user32.dll",&unused)) { puts("FAIL: version forwarding"); return 5; }
 if(inactive && EnableMouseInPointer(TRUE)) { puts("FAIL: non-target API changed"); return 4; }
 if(!inactive && !EnableMouseInPointer(TRUE)) { puts("FAIL: mouse-in-pointer unavailable"); return 1; }
 if(disabled && !EnableMouseInPointer(FALSE)) return 3;
 WNDCLASSW c={0};c.lpfnWndProc=proc;c.lpszClassName=L"GameBridgePointerTest";c.hInstance=GetModuleHandleW(NULL);RegisterClassW(&c);
 HWND w=CreateWindowW(c.lpszClassName,L"",0,0,0,1,1,HWND_MESSAGE,NULL,c.hInstance,NULL);
 expected.x=5; expected.y=6; ClientToScreen(w,&expected);
 Sleep(400);
 PostMessageW(w,WM_LBUTTONDOWN,MK_LBUTTON,MAKELPARAM(5,6));
 PostMessageW(w,WM_LBUTTONUP,0,MAKELPARAM(5,6));
 MSG m; DWORD until=GetTickCount()+2000;
 while(GetTickCount()<until) {
  // Repeated non-removing peeks must not manufacture duplicate pointer input.
  PeekMessageW(&m,NULL,0,0,PM_NOREMOVE);PeekMessageW(&m,NULL,0,0,PM_NOREMOVE);
  if(PeekMessageW(&m,NULL,0,0,PM_REMOVE)) { TranslateMessage(&m);DispatchMessageW(&m); }
  else Sleep(1);
 }
 DestroyWindow(w);
 printf("pointer events=%d failures=%d\n",count,failures);
 return count==((inactive || disabled)?0:2) && !failures ? 0 : 2;
}
