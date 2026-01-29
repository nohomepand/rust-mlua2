// Luaグローバル関数 sleep(millisec) を登録
pub fn register_sleep(lua: &Lua) -> LuaResult<()> {
    let sleep_fn = lua.create_function(|_, secs: f64| {
        std::thread::sleep(std::time::Duration::from_secs_f64(secs));
        Ok(())
    })?;
    lua.globals().set("sleep", sleep_fn)?;
    Ok(())
}
// luamod.rs
// Lua VM・coroutine・API登録

use mlua::{Lua, Result as LuaResult, Thread, UserData, UserDataMethods, Variadic};
use std::fs;
use std::sync::{Arc, Mutex};

pub struct LuaWindow {
    pub id: String,
    pub width: usize,
    pub height: usize,
    pub buffer: Vec<u8>, // RGBA * (width*height)
    pub text_color: (u8, u8, u8, u8),
    pub text_font_size: usize,
}

impl LuaWindow {
    #[inline(always)]
    // 境界チェックなし、高速化、アルファブレンドあり
    pub fn unsafe_point(&mut self, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) {
        // TODO: point以外でも使えそう（ただしtextは text_color+フォントのアルファの影響を受けるので別実装）
        let idx = (y as usize * self.width + x as usize) * 4;

        let dst_r = self.buffer[idx] as u16;
        let dst_g = self.buffer[idx + 1] as u16;
        let dst_b = self.buffer[idx + 2] as u16;
        let dst_a = self.buffer[idx + 3] as u16;

        let src_r = r as u16;
        let src_g = g as u16;
        let src_b = b as u16;
        let src_a = a as u16;

        // アルファブレンド (整数演算)
        // out_a = src_a + dst_a * (255 - src_a) / 255
        let out_a = src_a + ((dst_a * (255 - src_a)) / 255);
        if out_a > 0 {
            self.buffer[idx] = ((src_r * src_a + dst_r * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
            self.buffer[idx + 1] = ((src_g * src_a + dst_g * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
            self.buffer[idx + 2] = ((src_b * src_a + dst_b * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
            self.buffer[idx + 3] = out_a.min(255) as u8;
        } else {
            self.buffer[idx] = 0;
            self.buffer[idx + 1] = 0;
            self.buffer[idx + 2] = 0;
            self.buffer[idx + 3] = 0;
        }
    }
    
    pub fn point(&mut self, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }
        self.unsafe_point(x, y, r, g, b, a);
    }
    pub fn line(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, r: u8, g: u8, b: u8, a: u8) {
        let mut x0 = x0;
        let mut y0 = y0;
        let dx = (x1 - x0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let dy = -(y1 - y0).abs();
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;
        loop {
            self.point(x0, y0, r, g, b, a);
            if x0 == x1 && y0 == y1 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x0 += sx;
            }
            if e2 <= dx {
                err += dx;
                y0 += sy;
            }
        }
    }
    pub fn circle(&mut self, cx: i32, cy: i32, radius: i32, r: u8, g: u8, b: u8, a: u8) {
        let mut x = 0;
        let mut y = radius;
        let mut d = 3 - 2 * radius;
        while y >= x {
            // 8方向対称点
            let points = [
                (cx + x, cy + y),
                (cx - x, cy + y),
                (cx + x, cy - y),
                (cx - x, cy - y),
                (cx + y, cy + x),
                (cx - y, cy + x),
                (cx + y, cy - x),
                (cx - y, cy - x),
            ];
            for &(px, py) in &points {
                self.point(px, py, r, g, b, a);
            }
            x += 1;
            if d > 0 {
                y -= 1;
                d = d + 4 * (x - y) + 10;
            } else {
                d = d + 4 * x + 6;
            }
        }
    }
    pub fn set_text_color(&mut self, r: u8, g: u8, b: u8, a: u8) {
        self.text_color = (r, g, b, a);
    }
    pub fn get_text_color(&self) -> (u8, u8, u8, u8) {
        self.text_color
    }
    pub fn set_text_font_size(&mut self, size: usize) {
        self.text_font_size = size;
    }
    pub fn get_text_font_size(&self) -> usize {
        self.text_font_size
    }
    pub fn text(&mut self, x: i32, y: i32, text: &str) {
        use std::sync::OnceLock;
        use unicode_width::UnicodeWidthChar;
        static FONT: OnceLock<fontdue::Font> = OnceLock::new();
        let font = FONT.get_or_init(|| {
            let data = std::fs::read("assets/fonts.ttf").expect("assets/fonts.ttf not found");
            fontdue::Font::from_bytes(data, fontdue::FontSettings::default())
                .expect("font load failed")
        });
        let (r, g, b, a) = self.text_color;
        let font_size = self.text_font_size as f32;
        let mut pen_x = x;
        let base_y = y + self.text_font_size as i32;
        for ch in text.chars() {
            let (metrics, bitmap) = font.rasterize(ch, font_size);
            // 下ぞろえ: ベースラインから高さ分引く
            let draw_y = base_y - metrics.height as i32 - metrics.ymin;
            for dy in 0..metrics.height {
                for dx in 0..metrics.width {
                    let cov = bitmap[dy * metrics.width + dx];
                    if cov > 0 {
                        let px = pen_x + dx as i32 + metrics.xmin;
                        let py = draw_y + dy as i32;
                        if px >= 0 && px < self.width as i32 && py >= 0 && py < self.height as i32 {
                            let idx = (py as usize * self.width + px as usize) * 4;
                            let src_a = (cov as u16 * a as u16) / 255;
                            let dst_r = self.buffer[idx] as u16;
                            let dst_g = self.buffer[idx + 1] as u16;
                            let dst_b = self.buffer[idx + 2] as u16;
                            let dst_a = self.buffer[idx + 3] as u16;
                            let out_a = src_a + ((dst_a * (255 - src_a)) / 255);
                            if out_a > 0 {
                                self.buffer[idx] = ((r as u16 * src_a + dst_r * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                self.buffer[idx + 1] = ((g as u16 * src_a + dst_g * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                self.buffer[idx + 2] = ((b as u16 * src_a + dst_b * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                self.buffer[idx + 3] = out_a.min(255) as u8;
                            } else {
                                self.buffer[idx] = 0;
                                self.buffer[idx + 1] = 0;
                                self.buffer[idx + 2] = 0;
                                self.buffer[idx + 3] = 0;
                            }
                        }
                    }
                }
            }
            // 半角/全角で横幅を調整
            let ch_width = match UnicodeWidthChar::width(ch) {
                Some(1) => (self.text_font_size / 2) as i32,
                _ => self.text_font_size as i32,
            };
            pen_x += ch_width;
        }
    }
    pub fn scroll(&mut self, dx: i32, dy: i32, r: u8, g: u8, b: u8, a: u8) {
        let (w, h) = (self.width as i32, self.height as i32);
        let mut new_buf = vec![0u8; self.buffer.len()];
        for y in 0..h {
            for x in 0..w {
                let nx = x - dx;
                let ny = y - dy;
                let idx = (y as usize * self.width + x as usize) * 4;
                if nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let src = (ny as usize * self.width + nx as usize) * 4;
                    new_buf[idx..idx + 4].copy_from_slice(&self.buffer[src..src + 4]);
                } else {
                    new_buf[idx] = r;
                    new_buf[idx + 1] = g;
                    new_buf[idx + 2] = b;
                    new_buf[idx + 3] = a;
                }
            }
        }
        self.buffer = new_buf;
    }
}

impl UserData for LuaWindow {
    fn add_methods<'lua, M: UserDataMethods<'lua, Self>>(methods: &mut M) {
        // #region image methods
        // drawimage: w:drawimage(img, x, y, img_sx, img_sy, img_dx, img_dy)
        methods.add_method_mut(
            "drawimage",
            |_, this, (img, x, y, img_sx, img_sy, img_dx, img_dy): (mlua::AnyUserData, i32, i32, Option<u32>, Option<u32>, Option<u32>, Option<u32>)| {
                use crate::luaimage::LuaImage;
                let img = img.borrow::<LuaImage>()?;
                let sx = img_sx.unwrap_or(0);
                let sy = img_sy.unwrap_or(0);
                let dx = img_dx.unwrap_or(img.img.width());
                let dy = img_dy.unwrap_or(img.img.height());
                // 切り取り
                let subimg = img.img.crop_imm(sx, sy, dx, dy);
                let (w, h) = (this.width as i32, this.height as i32);
                let subimg = subimg.to_rgba8();
                for iy in 0..subimg.height() {
                    for ix in 0..subimg.width() {
                        let px = x + ix as i32;
                        let py = y + iy as i32;
                        if px >= 0 && py >= 0 && px < w && py < h {
                            // this.point(px, py, rgba[0], rgba[1], rgba[2], rgba[3]);
                            let idx = (py as usize * this.width + px as usize) * 4;
                            let rgba = subimg.get_pixel(ix, iy).0;
                            let src_r = rgba[0] as u16;
                            let src_g = rgba[1] as u16;
                            let src_b = rgba[2] as u16;
                            let src_a = rgba[3] as u16;
                            let dst_r = this.buffer[idx] as u16;
                            let dst_g = this.buffer[idx + 1] as u16;
                            let dst_b = this.buffer[idx + 2] as u16;
                            let dst_a = this.buffer[idx + 3] as u16;

                            // out_a = src_a + dst_a * (255 - src_a) / 255
                            let out_a = src_a + ((dst_a * (255 - src_a)) / 255);
                            if out_a > 0 {
                                this.buffer[idx] = ((src_r * src_a + dst_r * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                this.buffer[idx + 1] = ((src_g * src_a + dst_g * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                this.buffer[idx + 2] = ((src_b * src_a + dst_b * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                this.buffer[idx + 3] = out_a.min(255) as u8;
                            } else {
                                this.buffer[idx] = 0;
                                this.buffer[idx + 1] = 0;
                                this.buffer[idx + 2] = 0;
                                this.buffer[idx + 3] = 0;
                            }
                        }
                    }
                }
                Ok(())
            }
        );
        // captureimage: w:captureimage(x, y, width, height)
        methods.add_method(
            "captureimage",
            |lua, this, (x, y, width, height): (i32, i32, u32, u32)| {
                use crate::luaimage::LuaImage;
                let mut buf = vec![0u8; (width * height * 4) as usize];
                for iy in 0..height {
                    for ix in 0..width {
                        let sx = x + ix as i32;
                        let sy = y + iy as i32;
                        let idx_src = if sx >= 0 && sy >= 0 && sx < this.width as i32 && sy < this.height as i32 {
                            (sy as usize * this.width + sx as usize) * 4
                        } else {
                            continue;
                        };
                        let idx_dst = (iy as usize * width as usize + ix as usize) * 4;
                        buf[idx_dst] = this.buffer[idx_src];
                        buf[idx_dst + 1] = this.buffer[idx_src + 1];
                        buf[idx_dst + 2] = this.buffer[idx_src + 2];
                        buf[idx_dst + 3] = this.buffer[idx_src + 3];
                    }
                }
                let img = image::RgbaImage::from_vec(width, height, buf).unwrap();
                let dynimg = image::DynamicImage::ImageRgba8(img);
                let luaimg = LuaImage { img: dynimg };
                let ud = lua.create_userdata(luaimg)?;
                Ok(ud)
            }
        );
        // #endregion image methods
        // #region graphic methods
        methods.add_method_mut(
            "cls",
            |_, this, (r, g, b, a): (Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(0);
                let g = g.unwrap_or(0);
                let b = b.unwrap_or(0);
                let a = a.unwrap_or(255);
                for px in this.buffer.chunks_mut(4) {
                    px[0] = r;
                    px[1] = g;
                    px[2] = b;
                    px[3] = a;
                }
                Ok(())
            },
        );
        methods.add_method_mut(
            "point",
            |_, this, (x, y, r, g, b, a): (i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(255);
                let g = g.unwrap_or(255);
                let b = b.unwrap_or(255);
                let a = a.unwrap_or(255);
                this.point(x, y, r, g, b, a);
                Ok(())
            },
        );
        methods.add_method_mut(
            "line",
            |_, this, (x0, y0, x1, y1, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(255);
                let g = g.unwrap_or(255);
                let b = b.unwrap_or(255);
                let a = a.unwrap_or(255);
                this.line(x0, y0, x1, y1, r, g, b, a);
                Ok(())
            },
        );
        methods.add_method_mut(
            "circle",
            |_, this, (cx, cy, radius, r, g, b, a): (i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(255);
                let g = g.unwrap_or(255);
                let b = b.unwrap_or(255);
                let a = a.unwrap_or(255);
                this.circle(cx, cy, radius, r, g, b, a);
                // alphaは255固定（必要ならcircleもa引数追加）
                Ok(())
            },
        );
        methods.add_method_mut(
            "rect",
            |_, this, (x1, y1, x2, y2, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(255);
                let g = g.unwrap_or(255);
                let b = b.unwrap_or(255);
                let a = a.unwrap_or(255);
                this.line(x1, y1, x2, y1, r, g, b, a);
                this.line(x2, y1, x2, y2, r, g, b, a);
                this.line(x2, y2, x1, y2, r, g, b, a);
                this.line(x1, y2, x1, y1, r, g, b, a);
                Ok(())
            },
        );
        methods.add_method_mut(
            "fillrect",
            |_, this, (x1, y1, x2, y2, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let r = r.unwrap_or(255);
                let g = g.unwrap_or(255);
                let b = b.unwrap_or(255);
                let a = a.unwrap_or(255);
                for y in y1.min(y2)..=y1.max(y2) {
                    this.line(x1, y, x2, y, r, g, b, a);
                }
                Ok(())
            },
        );
        methods.add_method_mut(
            "scroll",
            |_, this, (dx, dy, r, g, b, a): (i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                this.scroll(dx, dy, r.unwrap_or(0), g.unwrap_or(0), b.unwrap_or(0), a.unwrap_or(255)); // alphaは255固定
                Ok(())
            },
        );
        // #endregion graphic methods
        // #region text methods
        methods.add_method_mut("settextcolor", |_, this, (r, g, b, a): (Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            this.set_text_color(r.unwrap_or(255), g.unwrap_or(255), b.unwrap_or(255), a.unwrap_or(255));
            // alphaはset_text_colorで255固定
            Ok(())
        });
        methods.add_method("gettextcolor", |_, this, ()| {
            let (r, g, b, a) = this.get_text_color();
            Ok((r, g, b, a))
        });
        methods.add_method_mut(
            "settextfontsize",
            |_, this, size: usize| {
                this.set_text_font_size(size);
                Ok(())
            },
        );
        methods.add_method("gettextfontsize", |_, this, ()| {
            let size = this.get_text_font_size();
            Ok(size)
        });
        methods.add_method_mut(
            "text",
            |_, this, (x, y, args): (i32, i32, Variadic<mlua::Value>)| {
                let s = args
                .iter()
                    .map(|v| match v {
                        mlua::Value::String(s) => s.to_str().unwrap_or("").to_owned(),
                        mlua::Value::Integer(i) => i.to_string(),
                        mlua::Value::Number(f) => f.to_string(),
                        mlua::Value::Boolean(b) => b.to_string(),
                        _ => "".to_owned(),
                    })
                    .collect::<Vec<_>>()
                    .join(" ");
                this.text(x, y, &s);
                Ok(())
            },
        );
        // #endregion text methods
        
        // #region metric methods
        methods.add_method("getwidth", |_, this, ()| {
            Ok(this.width)
        });
        methods.add_method("getheight", |_, this, ()| {
            Ok(this.height)
        });
        // #endregion metric methods
    }
}

pub struct LuaEngine {
    pub lua: Lua,
}

impl LuaEngine {
    pub fn new() -> LuaResult<Self> {
        let lua = Lua::new();
        Ok(Self { lua })
    }
    pub fn repl(&self) -> LuaResult<()> {
        use std::io::{self, Write};
        let stdin = io::stdin();
        let mut stdout = io::stdout();
        let mut line = String::new();
        loop {
            line.clear();
            print!("lua> ");
            stdout.flush().unwrap();
            if stdin.read_line(&mut line)? == 0 {
                break;
            }
            match self.lua.load(&line).eval::<mlua::Value>() {
                Ok(v) => println!("{:?}", v),
                Err(e) => eprintln!("[LuaError] {}", e),
            }
        }
        Ok(())
    }
}

// Luaファイルをcoroutineとしてロードし返す
pub fn load_lua_coroutine<'lua>(lua: &'lua Lua, path: &str) -> LuaResult<Thread<'lua>> {
    let code = fs::read_to_string(path).map_err(|e| mlua::Error::external(e))?;
    // ファイル名をchunk名として渡すことでtracebackに反映される
    let chunk = lua.load(&code).set_name(path);
    let func = chunk.into_function()?;
    lua.create_thread(func)
}

// egui Lua API登録（ダミー実装、必要に応じて本実装に変更）
pub fn register_egui(lua: &Lua, windows: Arc<Mutex<Vec<Arc<Mutex<LuaWindow>>>>>) -> LuaResult<()> {
    let egui_table = lua.create_table()?;
    let windows = windows.clone();
    egui_table.set(
        "create_window",
        lua.create_function(
            move |_, (name, width, height): (String, Option<usize>, Option<usize>)| {
                let w = width.unwrap_or(320);
                let h = height.unwrap_or(240);
                let win = Arc::new(Mutex::new(LuaWindow {
                    id: name.clone(),
                    width: w,
                    height: h,
                    buffer: vec![0; w * h * 4],
                    text_color: (255, 255, 255, 255),
                    text_font_size: 16, // デフォルトサイズ
                }));
                windows.lock().unwrap().push(win.clone());
                Ok(win)
            },
        )?,
    )?;
    lua.globals().set("egui", egui_table)?;
    Ok(())
}
