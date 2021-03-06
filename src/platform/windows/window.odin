package windows

import "../../application"

info: BITMAPINFO = {
	bmiHeader = {
    	biSize          = size_of(BITMAPINFOHEADER),
    	biPlanes        = 1,
    	biBitCount      = 32,
    	biCompression   = BI_RGB 
	}	
};

win_dc: HDC;
win_rect: RECT;
window: HWND;

import "core:runtime"

performance_counter: LARGE_INTEGER;

raw_inputs: RAWINPUT;
raw_input_handle: HRAWINPUT;
raw_input_device: RAWINPUTDEVICE;
raw_input_size: UINT;
raw_input_size_ptr: PUINT = cast(PUINT)(&raw_input_size);
raw_input_header_size: UINT = size_of(RAWINPUTHEADER);


getRawInput :: inline proc(raw_input: LPVOID = nil) -> u32 do
	return GetRawInputData(
 		raw_input_handle, 
 		RID_INPUT, 
 		raw_input, 
 		raw_input_size_ptr, 
 		raw_input_header_size
 	);

mouseMoved :: proc(lParam: LPARAM) -> bool {
	using raw_inputs.data.mouse;
 	raw_input_handle = transmute(HRAWINPUT)(uintptr(INT(lParam)));
 	
 	return 
 		getRawInput() == 0 && raw_input_size != 0 &&
 		getRawInput(LPVOID(&raw_inputs)) == raw_input_size && 
 		raw_inputs.header.dwType == RIM_TYPEMOUSE && (
 			lLastX != 0 || 
 			lLastY != 0
 		);
}

default_context: runtime.Context;
win32TicksPerSecond: u64;
win32GetTicks :: proc() -> u64 {
	QueryPerformanceCounter(&performance_counter);
	return u64(performance_counter.QuadPart);
}

WndProc:: proc "std" (hWnd: HWND, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
	using application;
	using frame_buffer;
	using info.bmiHeader;
	using win_rect;

	context = default_context;

	switch message {
		case WM_SIZE:
			GetClientRect(window, &win_rect);
			biWidth  = right - left; 
		    biHeight = top - bottom;
		    resize(biWidth, -biHeight);

		case WM_KEYUP:   keyChanged(u8(wParam), false);
		case WM_KEYDOWN: keyChanged(u8(wParam), true);
		
		case WM_MOUSEMOVE: setMousePosition(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));

		case WM_LBUTTONDBLCLK: 
			if mouse_is_captured {
				mouse_is_captured = false;
				ReleaseCapture();
				ShowCursor(true);	
			} else {
				mouse_is_captured = true;
				SetCapture(window);
				ShowCursor(false);
			}
			
		case WM_MBUTTONUP:   setMouseButtonUp(  &middle_mouse_button, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
			ReleaseCapture();
			ShowCursor(true);

		case WM_MBUTTONDOWN: setMouseButtonDown(&middle_mouse_button, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
			SetCapture(window);
			ShowCursor(false);

		case WM_LBUTTONDOWN: setMouseButtonDown(&left_mouse_button,  GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
		case WM_LBUTTONUP  : setMouseButtonUp(  &left_mouse_button,  GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
		case WM_RBUTTONDOWN: setMouseButtonDown(&right_mouse_button, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
		case WM_RBUTTONUP:   setMouseButtonUp(  &right_mouse_button, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));

		case WM_MOUSEWHEEL:
			setMouseWheel(f32(GET_WHEEL_DELTA_WPARAM(wParam)) / f32(WHEEL_DELTA*4));

		 case WM_INPUT:
		 	using raw_inputs.data.mouse;
		 	if mouseMoved(lParam) do setMouseMovement(lLastX, lLastY);

		case WM_PAINT:
		    SetDIBitsToDevice(win_dc, 0, 0, u32(width), u32(height),
		                              0, 0, 0,          u32(height),
		                      &frame_buffer_bits[0], &info, DIB_RGB_COLORS);
		    ValidateRgn(window, nil);

        case WM_DESTROY:
        	is_running = false;
        	PostQuitMessage(0);

		case:
			return DefWindowProcA(hWnd, message, wParam, lParam);
	}

	return 0;
}

run_application :: proc() {
	using application;
	default_context = context;

	performance_frequency: LARGE_INTEGER;
	QueryPerformanceFrequency(&performance_frequency);
	win32TicksPerSecond = u64(performance_frequency.QuadPart);

	initApplication(win32GetTicks, win32TicksPerSecond);
	up_key       = 'R';
	down_key     = 'F';
	forward_key  = 'W';
	backward_key = 'S';
	left_key     = 'A';  turn_left_key  = 'Q';
	right_key    = 'D';  turn_right_key = 'E';
	
	toggle_map_debug = VK_SHIFT;
	toggle_map   = VK_TAB;
	no_filter    = '1';
	bi_linear    = '2';
	tri_linear   = '3';
	ctrl_key     = VK_CONTROL;
	exit_key     = VK_ESCAPE;

	HInstance: HINSTANCE = transmute(HINSTANCE)GetModuleHandleA(nil);
	window_class: WNDCLASSA = {
	    lpszClassName  = class_name,
	    hInstance      = HInstance,
	    lpfnWndProc    = WndProc,
	    style          = CS_OWNDC|CS_HREDRAW|CS_VREDRAW|CS_DBLCLKS,
	    hCursor        = LoadCursorA(nil, IDC_ARROW)
	};
	result := RegisterClassA(&window_class);
	when ODIN_DEBUG do asset(result != 0, "Failed to register class!");

    window = CreateWindowExA(0, class_name, "Application", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        FRAME_BUFFER__INITIAL_WIDTH, 
        FRAME_BUFFER__INITIAL_HEIGHT, 
        nil, nil, HInstance, nil);
    when ODIN_DEBUG do assert(window != nil, "Failed to create window!");

    raw_input_device.usUsagePage = 0x01;
    raw_input_device.usUsage     = 0x02;
    err := RegisterRawInputDevices(&raw_input_device, 1, size_of(raw_input_device));
	when ODIN_DEBUG do assert(bool(err), "Failed to register raw input device!");

    win_dc = GetDC(window);
    ShowWindow(window, SW_SHOWDEFAULT);
    message: MSG;

    // point: POINT;

    for is_running {
		for PeekMessageA(&message, nil, 0, 0, PM_REMOVE) {
			TranslateMessage(&message);
            DispatchMessageA(&message);	
		}
		// GetCursorPos(&point);
		// mouseMoved(point.x, point.y);
		update();
		render();
		InvalidateRgn(window, nil, false);
    }
}