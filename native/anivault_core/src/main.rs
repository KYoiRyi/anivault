use std::ffi::CString;
use std::ptr;

fn check_status(status: std::os::raw::c_int) {
    if status < 0 {
        panic!("mpv error code: {}", status);
    }
}

fn main() {
    println!("Initializing AniVault Core (Rust MPV-sys Engine)...");

    unsafe {
        // Create context
        let ctx = libmpv_sys::mpv_create();
        if ctx.is_null() {
            panic!("Failed to create MPV instance.");
        }

        // Helper macro to set string options
        macro_rules! set_str {
            ($name:expr, $val:expr) => {
                let name = CString::new($name).unwrap();
                let val = CString::new($val).unwrap();
                check_status(libmpv_sys::mpv_set_option_string(ctx, name.as_ptr(), val.as_ptr()));
            };
        }

        // Core Player Settings
        set_str!("vo", "gpu-next");
        set_str!("hwdec", "auto");
        set_str!("terminal", "yes");
        set_str!("msg-level", "all=v");

        println!("Mounting ArtCNN Shader: ../ArtCNN_C4F32.glsl");
        set_str!("glsl-shaders", "../ArtCNN_C4F32.glsl");

        // Initialize mpv instance
        check_status(libmpv_sys::mpv_initialize(ctx));

        println!("Starting playback... [Close the player window to exit]");
        // Play Haikyuu reference file
        let cmd = CString::new("loadfile").unwrap();
        let arg1 = CString::new("../[VCB-Studio] Haikyuu!! 2nd Season [01][Ma10p_1080p][x265_flac].mkv").unwrap();
        
        let mut cmd_ptrs = [cmd.as_ptr(), arg1.as_ptr(), ptr::null()];
        check_status(libmpv_sys::mpv_command(ctx, cmd_ptrs.as_mut_ptr()));

        // Event loop
        loop {
            let event = libmpv_sys::mpv_wait_event(ctx, -1.0);
            if (*event).event_id == libmpv_sys::mpv_event_id_MPV_EVENT_SHUTDOWN {
                println!("Received Shutdown event from MPV.");
                break;
            }
        }
        
        libmpv_sys::mpv_terminate_destroy(ctx);
    }
}
