// luamod.rs
// Lua VM・coroutine・API登録
use mlua::{Lua, Result as LuaResult, StdLib, Thread, UserData, UserDataMethods, Variadic, LuaOptions};
use std::fs;
use std::sync::{Arc, Mutex};

// Luaグローバル関数 sleep(millisec) を登録
pub fn register_sleep(lua: &Lua) -> LuaResult<()> {
    let sleep_fn = lua.create_function(|_, secs: f64| {
        std::thread::sleep(std::time::Duration::from_secs_f64(secs));
        Ok(())
    })?;
    lua.globals().set("sleep", sleep_fn)?;
    Ok(())
}

static NOW: std::sync::LazyLock<std::time::Instant> = std::sync::LazyLock::new(|| std::time::Instant::now());
pub fn register_hpc(lua: &Lua) -> LuaResult<()> {
    let hpc_fn = lua.create_function(|_, ()| {
        let hpc = NOW.elapsed().as_secs_f64();
        Ok(hpc)
    })?;
    lua.globals().set("hpc", hpc_fn)?; // high performance counter
    Ok(())
}

pub fn register_utcdatetime(_lua: &Lua) -> LuaResult<()> {
    let datetime_fn = _lua.create_function(|lua, ()| {
        use chrono::prelude::*;
        let now = chrono::Utc::now();
        let table = lua.create_table()?;
        table.set("year", now.year())?;
        table.set("month", now.month())?;
        table.set("date", now.day())?;
        table.set("hour", now.hour())?;
        table.set("min", now.minute())?;
        table.set("sec", now.second())?;
        table.set("nanosec", now.nanosecond())?;
        Ok(table)
    })?;
    _lua.globals().set("utcdatetime", datetime_fn)?;
    Ok(())
}

pub fn register_localdatetime(_lua: &Lua) -> LuaResult<()> {
    let datetime_fn = _lua.create_function(|lua, ()| {
        use chrono::prelude::*;
        let now = chrono::Local::now();
        let table = lua.create_table()?;
        table.set("year", now.year())?;
        table.set("month", now.month())?;
        table.set("date", now.day())?;
        table.set("hour", now.hour())?;
        table.set("min", now.minute())?;
        table.set("sec", now.second())?;
        table.set("nanosec", now.nanosecond())?;
        Ok(table)
    })?;
    _lua.globals().set("datetime", datetime_fn)?;
    Ok(())
}

pub struct LuaWindow {
    pub id: String,
    pub x: i32, // 親ウィンドウ座標
    pub y: i32, // 親ウィンドウ座標
    pub width: usize,
    pub height: usize,
    pub buffer: Vec<u8>, // RGBA * (width*height)
    pub text_color: (u8, u8, u8, u8),
    pub text_font_size: usize,
    pub fillpaint_stack: Vec<(i32, i32)>,
    pub fillpaint_visited: Vec<bool>,
}

impl LuaWindow {
    #[inline(always)]
    // 境界チェックなし、高速化、アルファブレンドあり
    pub fn unsafe_point(&mut self, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) {
        // TODO: point以外でも使えそう（ただしtextは text_color+フォントのアルファの影響を受けるので別実装）
        let idx = (y as usize * self.width + x as usize) * 4;

        let dst_r = self.buffer[idx] as i32;
        let dst_g = self.buffer[idx + 1] as i32;
        let dst_b = self.buffer[idx + 2] as i32;
        let dst_a = self.buffer[idx + 3] as i32;

        let src_r = r as i32;
        let src_g = g as i32;
        let src_b = b as i32;
        let src_a = a as i32;

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
        let mut x = radius;
        let mut y = 0;
        let mut q = radius;
        while x >= y {
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
            q = q - y - y - 1;
            y = y + 1;
            if q < 0 {
                q = q + x + x - 1;
                x = x - 1;
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
    pub fn text(&mut self, x: i32, y: i32, text: &str) -> (usize, usize) {
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
        let mut width = 0;
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
                            let src_a = (cov as i32 * a as i32) / 255;
                            let dst_r = self.buffer[idx] as i32;
                            let dst_g = self.buffer[idx + 1] as i32;
                            let dst_b = self.buffer[idx + 2] as i32;
                            let dst_a = self.buffer[idx + 3] as i32;
                            let out_a = src_a + ((dst_a * (255 - src_a)) / 255);
                            if out_a > 0 {
                                self.buffer[idx] = ((r as i32 * src_a + dst_r * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                self.buffer[idx + 1] = ((g as i32 * src_a + dst_g * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
                                self.buffer[idx + 2] = ((b as i32 * src_a + dst_b * dst_a * (255 - src_a) / 255) / out_a).min(255) as u8;
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
            width += ch_width as usize;
        }
        (width, self.text_font_size)
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
                            let src_r = rgba[0] as i32;
                            let src_g = rgba[1] as i32;
                            let src_b = rgba[2] as i32;
                            let src_a = rgba[3] as i32;
                            let dst_r = this.buffer[idx] as i32;
                            let dst_g = this.buffer[idx + 1] as i32;
                            let dst_b = this.buffer[idx + 2] as i32;
                            let dst_a = this.buffer[idx + 3] as i32;

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
        methods.add_method(
            "getpoint",
            |_, this, (x, y): (i32, i32)| {
                if x < 0 || y < 0 || x >= this.width as i32 || y >= this.height as i32 {
                    return Ok((0u8, 0u8, 0u8, 0u8));
                }
                let idx = (y as usize * this.width + x as usize) * 4;
                let r = this.buffer[idx];
                let g = this.buffer[idx + 1];
                let b = this.buffer[idx + 2];
                let a = this.buffer[idx + 3];
                Ok((r, g, b, a))
            },
        );
        methods.add_method(
            "getpointi",
            |lua, this, (x, y, table,): (i32, i32, Option<mlua::Table>,)| {
                let table = match table {
                    Some(t) => t,
                    None => lua.create_table()?,
                };
                
                if x < 0 || y < 0 || x >= this.width as i32 || y >= this.height as i32 {
                    table.set(1, 0)?;
                    table.set(2, 0)?;
                    table.set(3, 0)?;
                    table.set(4, 0)?;
                } else {
                    let idx = (y as usize * this.width + x as usize) * 4;
                    let r = this.buffer[idx];
                    let g = this.buffer[idx + 1];
                    let b = this.buffer[idx + 2];
                    let a = this.buffer[idx + 3];
                    table.set(1, r)?;
                    table.set(2, g)?;
                    table.set(3, b)?;
                    table.set(4, a)?;
                }
                Ok(table)
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
        methods.add_method_mut(
            "paint",
            |_, this, (x, y, r, g, b, a, sr, sg, sb, sa): (i32, i32, u8, u8, u8, Option<u8>, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
                let a = a.unwrap_or(255);
                let sr = sr.unwrap_or(r);
                let sg = sg.unwrap_or(g);
                let sb = sb.unwrap_or(b);
                let sa = sa.unwrap_or(a);
                let (w, h) = (this.width as i32, this.height as i32);
                if x < 0 || y < 0 || x >= w || y >= h {
                    return Ok(0);
                }
                this.fillpaint_stack.clear();
                this.fillpaint_visited.fill(false);
                // let mut stack: Vec<(i32, i32)> = Vec::with_capacity((w * h).min(4096) as usize);
                // let mut visited = vec![false; (w * h) as usize];

                let boundary = (sr, sg, sb, sa);
                let fill = (r, g, b, a);
                let mut count: usize = 0;

                // 既に塗りつぶし色なら何もしない
                let idx0 = (y as usize * this.width + x as usize) * 4;
                let pixel0 = (
                    this.buffer[idx0],
                    this.buffer[idx0 + 1],
                    this.buffer[idx0 + 2],
                    this.buffer[idx0 + 3],
                );
                if pixel0 == boundary {
                    return Ok(0);
                }

                this.fillpaint_stack.push((x, y));
                while let Some((cx, cy)) = this.fillpaint_stack.pop() {
                    if cx < 0 || cy < 0 || cx >= w || cy >= h {
                        continue;
                    }
                    let idx = cy as usize * this.width + cx as usize;
                    if this.fillpaint_visited[idx] {
                        continue;
                    }
                    let idx_buf = idx * 4;
                    let pr = this.buffer[idx_buf];
                    let pg = this.buffer[idx_buf + 1];
                    let pb = this.buffer[idx_buf + 2];
                    let pa = this.buffer[idx_buf + 3];
                    if (pr, pg, pb, pa) == boundary || (pr, pg, pb, pa) == fill {
                        continue;
                    }
                    this.unsafe_point(cx, cy, r, g, b, a);
                    this.fillpaint_visited[idx] = true;
                    this.fillpaint_stack.push((cx + 1, cy));
                    this.fillpaint_stack.push((cx - 1, cy));
                    this.fillpaint_stack.push((cx, cy + 1));
                    this.fillpaint_stack.push((cx, cy - 1));
                    count += 1;
                }
                Ok(count)
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
                Ok(this.text(x, y, &s))
            },
        );
        // #endregion text methods
        
        // #region metric methods
        methods.add_method("getx", |_, this, ()| {
            Ok(this.x)
        });
        methods.add_method("gety", |_, this, ()| {
            Ok(this.y)
        });
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
        // Ok(Lua::new_with(StdLib::ALL_SAFE | StdLib::JIT, LuaOptions::default())?);
        unsafe {
            let lua = Lua::unsafe_new_with(StdLib::ALL, LuaOptions::default());
            Ok(Self { lua })
        }
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
                    x: 0,
                    y: 0,
                    width: w,
                    height: h,
                    buffer: vec![0; w * h * 4],
                    text_color: (255, 255, 255, 255),
                    text_font_size: 16, // デフォルトサイズ
                    fillpaint_stack: Vec::new(),
                    fillpaint_visited: vec![false; (w * h) as usize],
                }));
                windows.lock().unwrap().push(win.clone());
                Ok(win)
            },
        )?,
    )?;
    lua.globals().set("egui", egui_table)?;
    Ok(())
}
