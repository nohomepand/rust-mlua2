/// RGBAフォーマットのピクセルバッファを管理し、基本的なグラフィック描画機能を提供する構造体。
///
/// # フィールド
/// - `width`: バッファの幅（ピクセル単位）
/// - `height`: バッファの高さ（ピクセル単位）
/// - `buffer`: RGBA形式のピクセルデータ（各ピクセル4バイト）
/// - `fontpath`: テキスト描画時に使用するフォントファイルのパス
/// - `text_color`: テキスト描画時の色（RGBA）
/// - `text_font_size`: テキスト描画時のフォントサイズ
///
/// # 主なメソッド
///
/// ## new
/// ```rust
/// /// 新しいバッファを作成する。
/// ///
/// /// # 引数
/// /// * `width` - バッファの幅（ピクセル）
/// /// * `height` - バッファの高さ（ピクセル）
/// /// * `ref_buffer` - 既存のバッファ参照（省略時はゼロクリア）
/// ///
/// /// # 戻り値
/// /// 新しい `RGBABufferBase` インスタンス
/// ```
///
/// ## clear
/// ```rust
/// /// バッファ全体を指定した色でクリアする。
/// ///
/// /// # 引数
/// /// * `r`, `g`, `b`, `a` - クリア色（RGBA）
/// ```
///
/// ## scroll
/// ```rust
/// /// バッファ内容を指定ピクセル分スクロールし、空いた部分を指定色で塗りつぶす。
/// ///
/// /// # 引数
/// /// * `dx`, `dy` - スクロール量（ピクセル）
/// /// * `r`, `g`, `b`, `a` - 埋める色（RGBA）
/// ```
///
/// ## point
/// ```rust
/// /// 指定座標に点を描画する（範囲外は無視）。
/// ///
/// /// # 引数
/// /// * `x`, `y` - 描画座標
/// /// * `r`, `g`, `b`, `a` - 色（RGBA）
/// ```
///
/// ## get_point
/// ```rust
/// /// 指定座標のピクセル色を取得する（範囲外は(0,0,0,0)）。
/// ///
/// /// # 引数
/// /// * `x`, `y` - 座標
/// ///
/// /// # 戻り値
/// /// (r, g, b, a)
/// ```
///
/// ## line
/// ```rust
/// /// 2点間に直線を描画する。
/// ///
/// /// # 引数
/// /// * `x0`, `y0` - 始点
/// /// * `x1`, `y1` - 終点
/// /// * `r`, `g`, `b`, `a` - 色（RGBA）
/// ```
///
/// ## circle
/// ```rust
/// /// 指定中心・半径で円を描画する。
/// ///
/// /// # 引数
/// /// * `cx`, `cy` - 中心座標
/// /// * `radius` - 半径
/// /// * `r`, `g`, `b`, `a` - 色（RGBA）
/// ```
///
/// ## set_text_color / get_text_color
/// ```rust
/// /// テキスト描画時の色を設定・取得する。
/// ///
/// /// # 引数
/// /// * `r`, `g`, `b`, `a` - 色（RGBA）
/// ```
///
/// ## set_text_font_size / get_text_font_size
/// ```rust
/// /// テキスト描画時のフォントサイズを設定・取得する。
/// ///
/// /// # 引数
/// /// * `size` - フォントサイズ（ピクセル）
/// ```
///
/// ## set_fontpath / get_fontpath
/// ```rust
/// /// テキスト描画時のフォントファイルパスを設定・取得する。
/// ///
/// /// # 引数
/// /// * `path` - フォントファイルパス
/// ```
///
/// ## text_metrics
/// ```rust
/// /// 指定テキストの描画幅・高さを取得する（半角/全角対応）。
/// ///
/// /// # 引数
/// /// * `text` - 計測するテキスト
/// ///
/// /// # 戻り値
/// /// (幅, 高さ)
/// ```
///
/// ## text
/// ```rust
/// /// 指定座標にテキストを描画する。
/// ///
/// /// # 引数
/// /// * `x`, `y` - 描画開始座標
/// /// * `text` - 描画するテキスト
/// ///
/// /// # 戻り値
/// /// (描画幅, 高さ)
/// ```
///
/// ## toimage
/// ```rust
/// /// バッファ内容を image::DynamicImage に変換する。
/// ///
/// /// # 戻り値
/// /// LuaImage ユーザーデータ
/// ```
///
/// # Luaバインディング
/// Luaからは `graphic.create(width, height)` でインスタンス生成可能。
/// 各種メソッドは Lua からも同名で利用できる。
use crate::luaimage;
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use unicode_width::UnicodeWidthChar;
use mlua::{Lua, Result as LuaResult, UserData, UserDataMethods};

static FONTS: OnceLock<Mutex<HashMap<String, Box<&fontdue::Font>>>> = OnceLock::new();

fn get_font(fontpath: &str) -> &'static fontdue::Font {
    let fonts_mutex = FONTS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut fonts = fonts_mutex.lock().unwrap();
    if let Some(font) = fonts.get(fontpath) {
        return font;
    }
    let data = std::fs::read(fontpath).expect(format!("font file not found: {}", fontpath).as_str());
    let font = fontdue::Font::from_bytes(data, fontdue::FontSettings::default())
        .expect("font load failed");
    let boxed = Box::new(font);
    let static_ref: &'static fontdue::Font = Box::leak(boxed);
    fonts.insert(fontpath.to_string(), Box::from(static_ref));
    static_ref
}

#[derive(Clone, Debug)]
pub struct RGBABufferBase {
    pub width: usize,
    pub height: usize,
    buffer: Box<[u8]>, // RGBAフォーマット（参照保持）
    pub fontpath: String,
    pub text_color: (u8, u8, u8, u8),
    pub text_font_size: usize,
}

impl RGBABufferBase {
    pub fn new(width: usize, height: usize, ref_buffer: Option<&[u8]>) -> Self {
        Self {
            width,
            height,
            buffer: ref_buffer.map_or_else(
                || vec![0u8; width * height * 4].into_boxed_slice(),
                |buf| buf.to_vec().into_boxed_slice()
            ),
            fontpath: "assets/fonts.ttf".to_string(),
            text_color: (255, 255, 255, 255),
            text_font_size: 16,
        }
    }

    pub fn clear(&mut self, r: u8, g: u8, b: u8, a: u8) {
        for y in 0..self.height {
            for x in 0..self.width {
                let idx = (y * self.width + x) * 4;
                self.buffer[idx] = r;
                self.buffer[idx + 1] = g;
                self.buffer[idx + 2] = b;
                self.buffer[idx + 3] = a;
            }
        }
    }
    
    pub fn scroll(&mut self, dx: i32, dy: i32, r: u8, g: u8, b: u8, a: u8) {
        for y in 0..self.height as i32 {
            for x in 0..self.width as i32 {
                let src_x = x - dx;
                let src_y = y - dy;
                let dst_idx = (y as usize * self.width + x as usize) * 4;
                if src_x >= 0 && src_x < self.width as i32 && src_y >= 0 && src_y < self.height as i32 {
                    let src_idx = (src_y as usize * self.width + src_x as usize) * 4;
                    self.buffer[dst_idx] = self.buffer[src_idx];
                    self.buffer[dst_idx + 1] = self.buffer[src_idx + 1];
                    self.buffer[dst_idx + 2] = self.buffer[src_idx + 2];
                    self.buffer[dst_idx + 3] = self.buffer[src_idx + 3];
                } else {
                    self.buffer[dst_idx] = 0;
                    self.buffer[dst_idx + 1] = 0;
                    self.buffer[dst_idx + 2] = 0;
                    self.buffer[dst_idx + 3] = 0;
                }
            }
        }
        // dx, dyだけずらした部分をr,g,b,aで埋める
        for y in 0..self.height as i32 {
            for x in 0..self.width as i32 {
            let src_x = x - dx;
            let src_y = y - dy;
            if !(src_x >= 0 && src_x < self.width as i32 && src_y >= 0 && src_y < self.height as i32) {
                let dst_idx = (y as usize * self.width + x as usize) * 4;
                self.buffer[dst_idx] = r;
                self.buffer[dst_idx + 1] = g;
                self.buffer[dst_idx + 2] = b;
                self.buffer[dst_idx + 3] = a;
            }
            }
        }
    }

    pub fn unsafe_point(&mut self, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) {
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

    #[inline(always)]
    pub fn unsafe_get_buffer(&self) -> Box<[u8]> {
        self.buffer.clone()
    }

    #[inline(always)]
    pub fn point(&mut self, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }
        self.unsafe_point(x, y, r, g, b, a);
    }
    
    pub fn get_point(&self, x: i32, y: i32) -> (u8, u8, u8, u8) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return (0, 0, 0, 0);
        }
        let idx = (y as usize * self.width + x as usize) * 4;
        (
            self.buffer[idx],
            self.buffer[idx + 1],
            self.buffer[idx + 2],
            self.buffer[idx + 3],
        )
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

    pub fn set_fontpath(&mut self, path: &str) {
        self.fontpath = path.to_string();
    }

    pub fn get_fontpath(&self) -> String {
        self.fontpath.clone()
    }
    
    pub fn text_metrics(&self, text: &str) -> (usize, usize) {
        // let font = get_font(self.fontpath.as_str());
        // let font_size = self.text_font_size as f32;
        let mut width = 0;
        for ch in text.chars() {
            // 半角/全角で横幅を調整
            let ch_width = match UnicodeWidthChar::width(ch) {
                Some(1) => (self.text_font_size / 2) as i32,
                _ => self.text_font_size as i32,
            };
            width += ch_width as usize;
        }
        (width, self.text_font_size)
    }
    
    pub fn text(&mut self, x: i32, y: i32, text: &str) -> (usize, usize) {
        let font = get_font(self.fontpath.as_str());
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
                                self.buffer[idx] = ((r as i32 * src_a + dst_r * dst_a * (255 - src_a) / 255) / out_a) .min(255) as u8;
                                self.buffer[idx + 1] = ((g as i32 * src_a + dst_g * dst_a * (255 - src_a) / 255) / out_a) .min(255) as u8;
                                self.buffer[idx + 2] = ((b as i32 * src_a + dst_b * dst_a * (255 - src_a) / 255) / out_a) .min(255) as u8;
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
}

impl UserData for RGBABufferBase {
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
        methods.add_method("getwidth", |_, this, ()| {
            Ok(this.width)
        });
        methods.add_method("getheight", |_, this, ()| {
            Ok(this.height)
        });
        methods.add_method_mut("clear", |_, this, (r, g, b, a): (Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.clear(r, g, b, a);
            Ok(())
        });
        methods.add_method_mut("scroll", |_, this, (dx, dy, r, g, b, a): (i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.scroll(dx, dy, r, g, b, a);
            Ok(())
        });
        methods.add_method_mut("point", |_, this, (x, y, r, g, b, a): (i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.point(x, y, r, g, b, a);
            Ok(())
        });
        methods.add_method("getpoint", |_, this, (x, y): (i32, i32)| {
            Ok(this.get_point(x, y))
        });
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
        methods.add_method_mut("line", |_, this, (x0, y0, x1, y1, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.line(x0, y0, x1, y1, r, g, b, a);
            Ok(())
        });
        methods.add_method_mut("circle", |_, this, (cx, cy, radius, r, g, b, a): (i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.circle(cx, cy, radius, r, g, b, a);
            Ok(())
        });
        methods.add_method_mut("rect", |_, this, (x, y, width, height, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            this.line(x, y, x + width, y, r, g, b, a);
            this.line(x + width, y, x + width, y + height, r, g, b, a);
            this.line(x + width, y + height, x, y + height, r, g, b, a);
            this.line(x, y + height, x, y, r, g, b, a);
            Ok(())
        });
        methods.add_method_mut("fillrect", |_, this, (x, y, width, height, r, g, b, a): (i32, i32, i32, i32, Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(0);
            let g = g.unwrap_or(0);
            let b = b.unwrap_or(0);
            let a = a.unwrap_or(255);
            for fy in y..(y + height) {
                for fx in x..(x + width) {
                    this.unsafe_point(fx, fy, r, g, b, a);
                }
            }
            Ok(())
        });
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
                    return Ok(());
                }
                let mut stack = Vec::with_capacity((w * h).min(4096) as usize);
                let mut visited = vec![false; (w * h) as usize];

                let boundary = (sr, sg, sb, sa);
                let fill = (r, g, b, a);

                // 既に塗りつぶし色なら何もしない
                let idx0 = (y as usize * this.width + x as usize) * 4;
                let pixel0 = (
                    this.buffer[idx0],
                    this.buffer[idx0 + 1],
                    this.buffer[idx0 + 2],
                    this.buffer[idx0 + 3],
                );
                if pixel0 == fill || pixel0 == boundary {
                    return Ok(());
                }

                stack.push((x, y));
                while let Some((cx, cy)) = stack.pop() {
                    if cx < 0 || cy < 0 || cx >= w || cy >= h {
                        continue;
                    }
                    let idx = cy as usize * this.width + cx as usize;
                    if visited[idx] {
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
                    visited[idx] = true;
                    stack.push((cx + 1, cy));
                    stack.push((cx - 1, cy));
                    stack.push((cx, cy + 1));
                    stack.push((cx, cy - 1));
                }
                Ok(())
            },
        );
        methods.add_method_mut("settextcolor", |_, this, (r, g, b, a): (Option<u8>, Option<u8>, Option<u8>, Option<u8>)| {
            let r = r.unwrap_or(255);
            let g = g.unwrap_or(255);
            let b = b.unwrap_or(255);
            let a = a.unwrap_or(255);
            this.set_text_color(r, g, b, a);
            Ok(())
        });
        methods.add_method("gettextcolor", |_, this, ()| {
            Ok(this.get_text_color())
        });
        methods.add_method_mut("settextfontsize", |_, this, size: usize| {
            this.set_text_font_size(size);
            Ok(())
        });
        methods.add_method("gettextfontsize", |_, this, ()| {
            Ok(this.get_text_font_size())
        });
        methods.add_method_mut("setfontpath", |_, this, path: String| {
            this.set_fontpath(&path);
            Ok(())
        });
        methods.add_method("getfontpath", |_, this, ()| {
            Ok(this.get_fontpath())
        });
        methods.add_method("textmetrics", |_, this, text: String| {
            Ok(this.text_metrics(&text))
        });
        methods.add_method_mut("text", |_, this, (x, y, text): (i32, i32, String)| {
            Ok(this.text(x, y, &text))
        });
        methods.add_method("toimage", |lua, this, ()| {
            let raw = this.buffer.clone();
            let img = luaimage::LuaImage {
                img: image::DynamicImage::ImageRgba8(
                    image::ImageBuffer::from_raw(this.width as u32, this.height as u32, raw.to_vec())
                        .expect("Failed to create ImageBuffer")
                )
            };
            Ok(lua.create_userdata(img)?)
        });
    }
}

pub fn register_lua_graphic(lua: &Lua) -> LuaResult<()> {
    let graphic_mod = lua.create_table()?;
    graphic_mod.set("create", lua.create_function(|lua, (width, height): (usize, usize)| {
        let buf = RGBABufferBase::new(width, height, None);
        let ud = lua.create_userdata(buf)?;
        Ok(ud)
    })?)?;
    lua.globals().set("graphic", graphic_mod)?;
    Ok(())
}
