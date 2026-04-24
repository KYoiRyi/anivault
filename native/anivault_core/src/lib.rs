use ort::{session::{Session, builder::GraphOptimizationLevel}, value::Tensor};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

pub struct ArtCnnEngine {
    session: Session,
}

impl ArtCnnEngine {
    pub fn new(model_path: &str) -> Result<Self, String> {
        let _ = ort::init().with_name("ArtCNN").commit(); // Safe to call multiple times

        let session = Session::builder()
            .map_err(|e| e.to_string())?
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .map_err(|e| e.to_string())?
            .commit_from_file(model_path)
            .map_err(|e| e.to_string())?;

        Ok(Self { session })
    }

    pub fn process_frame(&mut self, rgb24_buffer: &mut [u8], width: usize, height: usize) -> Result<(), String> {
        let ch_size = height * width;
        let mut input_vec = vec![0.0f32; 3 * ch_size];

        for y in 0..height {
            for x in 0..width {
                let idx = (y * width + x) * 4; // 4 bytes per pixel now (rgb0/bgra)
                let flat_idx = y * width + x;
                input_vec[0 * ch_size + flat_idx] = rgb24_buffer[idx] as f32 / 255.0; // R or B
                input_vec[1 * ch_size + flat_idx] = rgb24_buffer[idx + 1] as f32 / 255.0; // G
                input_vec[2 * ch_size + flat_idx] = rgb24_buffer[idx + 2] as f32 / 255.0; // B or R
            }
        }

        let input_name = self.session.inputs()[0].name().to_string();
        let output_name = self.session.outputs()[0].name().to_string();
        let shape = vec![1i64, 3, height as i64, width as i64];
        
        let tensor = Tensor::from_array((shape, input_vec)).map_err(|e| e.to_string())?;
        
        let outputs = self.session.run(ort::inputs![input_name.as_str() => tensor]).map_err(|e| e.to_string())?;

        let val = outputs.get(output_name.as_str()).ok_or("Output not found")?;

        let (_dims, view) = val.try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
        
        for y in 0..height {
            for x in 0..width {
                let idx = (y * width + x) * 4;
                let flat_idx = y * width + x;
                
                let r = (view[0 * ch_size + flat_idx].clamp(0.0, 1.0) * 255.0) as u8;
                let g = (view[1 * ch_size + flat_idx].clamp(0.0, 1.0) * 255.0) as u8;
                let b = (view[2 * ch_size + flat_idx].clamp(0.0, 1.0) * 255.0) as u8;

                rgb24_buffer[idx] = r;
                rgb24_buffer[idx + 1] = g;
                rgb24_buffer[idx + 2] = b;
                // do not touch alpha/padding rgb24_buffer[idx + 3]
            }
        }
        
        Ok(())
    }
}

// ==========================================
// C-FFI / JNI / Dart interface wrappers
// ==========================================

static mut ENGINE_INSTANCE: Option<ArtCnnEngine> = None;

#[no_mangle]
#[allow(unsafe_op_in_unsafe_fn)]
pub unsafe extern "C" fn artcnn_init(model_path_ptr: *const c_char) -> c_int {
    if model_path_ptr.is_null() {
        return -1;
    }
    
    let c_str = CStr::from_ptr(model_path_ptr);
    let model_path = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };

    match ArtCnnEngine::new(model_path) {
        Ok(engine) => {
            ENGINE_INSTANCE = Some(engine);
            0 // Success
        }
        Err(_) => -3, // Failed loading model
    }
}

#[no_mangle]
#[allow(unsafe_op_in_unsafe_fn)]
pub unsafe extern "C" fn artcnn_process_frame(
    buffer_ptr: *mut u8,
    buffer_size: c_int,
    width: c_int,
    height: c_int,
) -> c_int {
    if buffer_ptr.is_null() || ENGINE_INSTANCE.is_none() {
        return -1;
    }

    let engine = ENGINE_INSTANCE.as_mut().unwrap();
    let size = buffer_size as usize;
    let buffer_slice = std::slice::from_raw_parts_mut(buffer_ptr, size);

    match engine.process_frame(buffer_slice, width as usize, height as usize) {
        Ok(_) => 0, // Success
        Err(_) => -2, // Inference error
    }
}
