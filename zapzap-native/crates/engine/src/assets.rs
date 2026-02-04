use std::collections::HashMap;
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys::HtmlImageElement;

/// Handle to a loaded texture, used to reference textures in the renderer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TextureHandle(pub(crate) u32);

/// Raw image data decoded from an asset file.
pub struct ImageData {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// Manages loading assets from a base path (typically `public/assets/`).
/// Generic: knows nothing about tiles, zaps, or game-specific concepts.
pub struct AssetManager {
    base_path: String,
    next_handle: u32,
    loaded: HashMap<String, TextureHandle>,
}

impl AssetManager {
    pub fn new(base_path: &str) -> Self {
        Self {
            base_path: base_path.trim_end_matches('/').to_string(),
            next_handle: 0,
            loaded: HashMap::new(),
        }
    }

    /// Returns a previously loaded texture handle by name, if it exists.
    pub fn get(&self, name: &str) -> Option<TextureHandle> {
        self.loaded.get(name).copied()
    }

    /// Allocates a new texture handle and records it by name.
    /// The actual GPU texture creation happens in the renderer.
    pub fn register(&mut self, name: &str) -> TextureHandle {
        if let Some(handle) = self.loaded.get(name) {
            return *handle;
        }
        let handle = TextureHandle(self.next_handle);
        self.next_handle += 1;
        self.loaded.insert(name.to_string(), handle);
        handle
    }

    /// Builds the full URL path for an asset file.
    pub fn asset_url(&self, filename: &str) -> String {
        format!("{}/{}", self.base_path, filename)
    }

    /// Load an image from the assets directory using the browser's image decoder.
    /// Returns raw RGBA pixel data suitable for GPU texture upload.
    pub async fn load_image(&self, filename: &str) -> Result<ImageData, JsValue> {
        let url = self.asset_url(filename);
        let image = load_image_element(&url).await?;
        decode_image_to_rgba(&image)
    }
}

/// Load an HtmlImageElement from a URL, waiting for the load event.
async fn load_image_element(url: &str) -> Result<HtmlImageElement, JsValue> {
    let image = HtmlImageElement::new()?;

    let promise = js_sys::Promise::new(&mut |resolve, reject| {
        let resolve_clone = resolve.clone();
        let reject_clone = reject.clone();

        let onload = Closure::once(move || {
            resolve_clone.call0(&JsValue::NULL).ok();
        });
        let onerror = Closure::once(move || {
            reject_clone
                .call1(&JsValue::NULL, &JsValue::from_str("Image load failed"))
                .ok();
        });

        image.set_onload(Some(onload.as_ref().unchecked_ref()));
        image.set_onerror(Some(onerror.as_ref().unchecked_ref()));

        // Prevent closures from being dropped while the image loads
        onload.forget();
        onerror.forget();
    });

    image.set_cross_origin(Some("anonymous"));
    image.set_src(url);

    wasm_bindgen_futures::JsFuture::from(promise).await?;
    Ok(image)
}

/// Decode an HtmlImageElement to raw RGBA bytes using a canvas 2D context.
fn decode_image_to_rgba(image: &HtmlImageElement) -> Result<ImageData, JsValue> {
    let width = image.natural_width();
    let height = image.natural_height();

    let document = web_sys::window()
        .ok_or("no window")?
        .document()
        .ok_or("no document")?;

    let canvas = document
        .create_element("canvas")?
        .dyn_into::<web_sys::HtmlCanvasElement>()?;
    canvas.set_width(width);
    canvas.set_height(height);

    let ctx = canvas
        .get_context("2d")?
        .ok_or("no 2d context")?
        .dyn_into::<web_sys::CanvasRenderingContext2d>()?;

    ctx.draw_image_with_html_image_element(image, 0.0, 0.0)?;

    let data = ctx.get_image_data(0.0, 0.0, width as f64, height as f64)?;
    let rgba = data.data().to_vec();

    Ok(ImageData {
        width,
        height,
        rgba,
    })
}
